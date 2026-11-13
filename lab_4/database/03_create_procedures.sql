-- =====================================================================
-- 03_create_procedures.sql — збережені процедури та функції
-- Бізнес-правила бібліотеки:
--   * читач може мати не більше 5 невиданих (не повернених) книг;
--   * читач з простроченими книгами не може отримати нову;
--   * термін видачі — 14 днів, продовження — до 2 разів по 7 днів;
--   * штраф за прострочення — 5 грн за кожен день.
-- Помилки повертаються через RAISE EXCEPTION з українським текстом,
-- який застосунки показують користувачу.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Видача книги читачу. Повертає ідентифікатор нової видачі.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION issue_book(
    p_book_id   INTEGER,
    p_reader_id INTEGER,
    p_days      INTEGER DEFAULT 14
) RETURNS INTEGER
LANGUAGE plpgsql AS $$
DECLARE
    v_available      INTEGER;
    v_reader_active  BOOLEAN;
    v_open_loans     INTEGER;
    v_overdue        INTEGER;
    v_foreign_reserv INTEGER;
    v_loan_id        INTEGER;
BEGIN
    IF p_days NOT BETWEEN 1 AND 60 THEN
        RAISE EXCEPTION 'Термін видачі має бути від 1 до 60 днів (отримано %)', p_days;
    END IF;

    -- Блокуємо рядок книги, щоб дві одночасні видачі не взяли останній примірник
    SELECT available_copies INTO v_available
    FROM books WHERE book_id = p_book_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Книгу з ID % не знайдено', p_book_id;
    END IF;

    SELECT is_active INTO v_reader_active FROM readers WHERE reader_id = p_reader_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Читача з ID % не знайдено', p_reader_id;
    ELSIF NOT v_reader_active THEN
        RAISE EXCEPTION 'Читацький квиток читача % заблоковано', p_reader_id;
    END IF;

    -- Перевірка лімітів читача
    SELECT COUNT(*) FILTER (WHERE return_date IS NULL),
           COUNT(*) FILTER (WHERE return_date IS NULL AND due_date < CURRENT_DATE)
    INTO v_open_loans, v_overdue
    FROM loans WHERE reader_id = p_reader_id;

    IF v_overdue > 0 THEN
        RAISE EXCEPTION 'Читач має % прострочених книг — спочатку їх треба повернути', v_overdue;
    END IF;
    IF v_open_loans >= 5 THEN
        RAISE EXCEPTION 'Перевищено ліміт: читач уже має % книг на руках (максимум 5)', v_open_loans;
    END IF;

    -- Примірники, заброньовані іншими читачами, видавати не можна
    SELECT COUNT(*) INTO v_foreign_reserv
    FROM reservations
    WHERE book_id = p_book_id AND status = 'pending'
      AND reader_id <> p_reader_id AND expires_at > CURRENT_TIMESTAMP;

    IF v_available - v_foreign_reserv <= 0 THEN
        RAISE EXCEPTION 'Немає вільних примірників книги (доступно %, заброньовано іншими %)',
            v_available, v_foreign_reserv;
    END IF;

    INSERT INTO loans (book_id, reader_id, loan_date, due_date)
    VALUES (p_book_id, p_reader_id, CURRENT_DATE, CURRENT_DATE + p_days)
    RETURNING loan_id INTO v_loan_id;
    -- available_copies зменшує тригер trg_loans_sync_availability

    -- Якщо читач бронював цю книгу — бронювання виконано
    UPDATE reservations SET status = 'fulfilled'
    WHERE book_id = p_book_id AND reader_id = p_reader_id AND status = 'pending';

    RETURN v_loan_id;
END;
$$;

-- ---------------------------------------------------------------------
-- 2. Повернення книги. Нараховує штраф і повертає його суму.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION return_book(p_loan_id INTEGER)
RETURNS NUMERIC
LANGUAGE plpgsql AS $$
DECLARE
    v_loan loans%ROWTYPE;
    v_fine NUMERIC(8,2) := 0;
BEGIN
    SELECT * INTO v_loan FROM loans WHERE loan_id = p_loan_id FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Видачу з ID % не знайдено', p_loan_id;
    END IF;
    IF v_loan.return_date IS NOT NULL THEN
        RAISE EXCEPTION 'Книгу за видачею % уже повернено %', p_loan_id, v_loan.return_date;
    END IF;

    IF CURRENT_DATE > v_loan.due_date THEN
        v_fine := (CURRENT_DATE - v_loan.due_date) * 5.00;
    END IF;

    UPDATE loans
    SET return_date = CURRENT_DATE,
        status      = 'returned',
        fine_amount = v_fine
    WHERE loan_id = p_loan_id;
    -- available_copies збільшує тригер trg_loans_sync_availability

    RETURN v_fine;
END;
$$;

-- ---------------------------------------------------------------------
-- 3. Продовження терміну видачі (не більше 2 разів, не для прострочених).
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION extend_loan(p_loan_id INTEGER, p_days INTEGER DEFAULT 7)
RETURNS DATE
LANGUAGE plpgsql AS $$
DECLARE
    v_loan     loans%ROWTYPE;
    v_reserved INTEGER;
    v_new_due  DATE;
BEGIN
    SELECT * INTO v_loan FROM loans WHERE loan_id = p_loan_id FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Видачу з ID % не знайдено', p_loan_id;
    ELSIF v_loan.return_date IS NOT NULL THEN
        RAISE EXCEPTION 'Неможливо продовжити: книгу вже повернено';
    ELSIF v_loan.due_date < CURRENT_DATE THEN
        RAISE EXCEPTION 'Неможливо продовжити прострочену видачу';
    ELSIF v_loan.extensions_count >= 2 THEN
        RAISE EXCEPTION 'Видачу вже продовжено максимальну кількість разів (2)';
    END IF;

    -- Якщо книгу чекають інші читачі — продовження заборонене
    SELECT COUNT(*) INTO v_reserved
    FROM reservations
    WHERE book_id = v_loan.book_id AND status = 'pending' AND reader_id <> v_loan.reader_id;

    IF v_reserved > 0 THEN
        RAISE EXCEPTION 'Книгу заброньували інші читачі (%), продовження неможливе', v_reserved;
    END IF;

    v_new_due := v_loan.due_date + p_days;

    UPDATE loans
    SET due_date = v_new_due,
        extensions_count = extensions_count + 1
    WHERE loan_id = p_loan_id;

    RETURN v_new_due;
END;
$$;

-- ---------------------------------------------------------------------
-- 4. Бронювання книги читачем. Повертає ID бронювання.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION reserve_book(p_book_id INTEGER, p_reader_id INTEGER)
RETURNS INTEGER
LANGUAGE plpgsql AS $$
DECLARE
    v_id INTEGER;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM books WHERE book_id = p_book_id) THEN
        RAISE EXCEPTION 'Книгу з ID % не знайдено', p_book_id;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM readers WHERE reader_id = p_reader_id AND is_active) THEN
        RAISE EXCEPTION 'Читач % не існує або заблокований', p_reader_id;
    END IF;
    IF EXISTS (SELECT 1 FROM loans
               WHERE book_id = p_book_id AND reader_id = p_reader_id AND return_date IS NULL) THEN
        RAISE EXCEPTION 'Ця книга вже є у читача на руках';
    END IF;
    IF EXISTS (SELECT 1 FROM reservations
               WHERE book_id = p_book_id AND reader_id = p_reader_id AND status = 'pending') THEN
        RAISE EXCEPTION 'Читач уже забронював цю книгу';
    END IF;

    INSERT INTO reservations (book_id, reader_id)
    VALUES (p_book_id, p_reader_id)
    RETURNING reservation_id INTO v_id;

    RETURN v_id;
END;
$$;

-- ---------------------------------------------------------------------
-- 5. Процедура обслуговування: позначає прострочені видачі
--    та закриває протерміновані бронювання. Виклик: CALL update_overdue_status();
-- ---------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE update_overdue_status()
LANGUAGE plpgsql AS $$
DECLARE
    v_loans INTEGER;
    v_res   INTEGER;
BEGIN
    UPDATE loans SET status = 'overdue'
    WHERE return_date IS NULL AND due_date < CURRENT_DATE AND status = 'active';
    GET DIAGNOSTICS v_loans = ROW_COUNT;

    UPDATE reservations SET status = 'expired'
    WHERE status = 'pending' AND expires_at < CURRENT_TIMESTAMP;
    GET DIAGNOSTICS v_res = ROW_COUNT;

    RAISE NOTICE 'Позначено прострочених видач: %, протерміновано бронювань: %', v_loans, v_res;
END;
$$;

-- ---------------------------------------------------------------------
-- 6. Звіт по читачу: повна історія видач зі штрафами.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION get_reader_history(p_reader_id INTEGER)
RETURNS TABLE (
    loan_id     INTEGER,
    book_title  VARCHAR,
    loan_date   DATE,
    due_date    DATE,
    return_date DATE,
    status      VARCHAR,
    days_late   INTEGER,
    fine        NUMERIC
)
LANGUAGE plpgsql AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM readers r WHERE r.reader_id = p_reader_id) THEN
        RAISE EXCEPTION 'Читача з ID % не знайдено', p_reader_id;
    END IF;

    RETURN QUERY
    SELECT l.loan_id, b.title, l.loan_date, l.due_date, l.return_date, l.status,
           GREATEST(COALESCE(l.return_date, CURRENT_DATE) - l.due_date, 0)::INTEGER,
           CASE WHEN l.return_date IS NULL
                THEN GREATEST(CURRENT_DATE - l.due_date, 0) * 5.00   -- очікуваний штраф
                ELSE l.fine_amount END
    FROM loans l
    JOIN books b ON b.book_id = l.book_id
    WHERE l.reader_id = p_reader_id
    ORDER BY l.loan_date DESC;
END;
$$;
