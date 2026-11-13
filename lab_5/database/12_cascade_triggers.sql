-- =====================================================================
-- 12_cascade_triggers.sql — каскадні тригери для бізнес-логіки (рівень 3)
--
-- Каскадні тригери: зміна в одній таблиці запускає тригер, який змінює
-- іншу таблицю, а там спрацьовує наступний тригер і так далі.
-- Глибину ланцюжка показує функція pg_trigger_depth().
--
-- Ланцюжок А — повернення книги, на яку є черга:
--   loans (return_date)                 тригер лаб. 4 trg_loans_sync_availability
--     -> books.available_copies + 1     новий trg_books_notify_reservation
--       -> reservations.notified_at     новий trg_reservations_notify
--         -> notifications (повідомлення читачу з черги)
--   а також loans -> notifications, якщо при поверненні нараховано штраф.
--
-- Ланцюжок Б — блокування читацького квитка:
--   readers.is_active = FALSE           новий trg_readers_blocked
--     -> reservations: pending -> cancelled -> notifications (trg_reservations_notify)
--     -> app_users.is_active = FALSE    -> audit_log (trg_audit_users з лаб. 4)
--     -> notifications (повідомлення про блокування)
-- =====================================================================

-- ---------------------------------------------------------------------
-- Нові структури
-- ---------------------------------------------------------------------
ALTER TABLE reservations ADD COLUMN IF NOT EXISTS notified_at TIMESTAMP;   -- коли читача повідомили

CREATE TABLE IF NOT EXISTS notifications (
    notification_id BIGSERIAL PRIMARY KEY,
    reader_id       INTEGER     NOT NULL REFERENCES readers(reader_id) ON DELETE CASCADE,
    kind            VARCHAR(20) NOT NULL
                    CHECK (kind IN ('book_ready', 'reservation', 'fine', 'account')),
    message         TEXT        NOT NULL,
    trigger_depth   SMALLINT,                       -- на якому рівні каскаду створено
    created_at      TIMESTAMP   NOT NULL DEFAULT CURRENT_TIMESTAMP,
    is_read         BOOLEAN     NOT NULL DEFAULT FALSE
);
CREATE INDEX IF NOT EXISTS idx_notifications_unread
    ON notifications (reader_id, created_at DESC) WHERE NOT is_read;      -- частковий індекс

-- ---------------------------------------------------------------------
-- А1. Кількість доступних примірників зросла -> повідомляємо першого
--     в черзі бронювань і даємо йому 3 дні, щоб забрати книгу.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_books_notify_reservation()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE
    v_res_id INTEGER;
BEGIN
    IF pg_trigger_depth() > 5 THEN RETURN NULL; END IF;     -- захист від нескінченного каскаду

    SELECT reservation_id INTO v_res_id
    FROM reservations
    WHERE book_id = NEW.book_id AND status = 'pending' AND notified_at IS NULL
    ORDER BY reservation_date                                -- черга: хто раніше забронював
    LIMIT 1
    FOR UPDATE SKIP LOCKED;

    IF FOUND THEN
        RAISE NOTICE '[рівень %] books: книга % знову доступна -> бронювання %',
            pg_trigger_depth(), NEW.book_id, v_res_id;
        UPDATE reservations
        SET notified_at = CURRENT_TIMESTAMP,
            expires_at  = CURRENT_TIMESTAMP + INTERVAL '3 days'
        WHERE reservation_id = v_res_id;
    END IF;
    RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS trg_books_notify_reservation ON books;
CREATE TRIGGER trg_books_notify_reservation
AFTER UPDATE OF available_copies ON books
FOR EACH ROW
WHEN (NEW.available_copies > OLD.available_copies)
EXECUTE FUNCTION fn_books_notify_reservation();

-- ---------------------------------------------------------------------
-- А2 / Б. Зміни бронювання -> повідомлення читачу.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_reservations_notify()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE
    v_title TEXT;
BEGIN
    SELECT title INTO v_title FROM books WHERE book_id = NEW.book_id;

    IF NEW.notified_at IS NOT NULL AND OLD.notified_at IS NULL THEN
        RAISE NOTICE '[рівень %] reservations: бронювання % -> повідомлення читачу %',
            pg_trigger_depth(), NEW.reservation_id, NEW.reader_id;
        INSERT INTO notifications (reader_id, kind, message, trigger_depth)
        VALUES (NEW.reader_id, 'book_ready',
                format('Заброньована книга «%s» чекає на вас до %s', v_title,
                       to_char(NEW.expires_at, 'DD.MM.YYYY HH24:MI')),
                pg_trigger_depth());

    ELSIF NEW.status IN ('cancelled', 'expired') AND OLD.status = 'pending' THEN
        RAISE NOTICE '[рівень %] reservations: бронювання % -> %',
            pg_trigger_depth(), NEW.reservation_id, NEW.status;
        INSERT INTO notifications (reader_id, kind, message, trigger_depth)
        VALUES (NEW.reader_id, 'reservation',
                format('Бронювання книги «%s» %s', v_title,
                       CASE NEW.status WHEN 'cancelled' THEN 'скасовано' ELSE 'прострочено' END),
                pg_trigger_depth());
    END IF;
    RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS trg_reservations_notify ON reservations;
CREATE TRIGGER trg_reservations_notify
AFTER UPDATE OF notified_at, status ON reservations
FOR EACH ROW EXECUTE FUNCTION fn_reservations_notify();

-- ---------------------------------------------------------------------
-- А3. Книгу повернули зі штрафом -> повідомлення про штраф.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_loans_fine_notify()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    RAISE NOTICE '[рівень %] loans: видача % повернена зі штрафом % грн',
        pg_trigger_depth(), NEW.loan_id, NEW.fine_amount;
    INSERT INTO notifications (reader_id, kind, message, trigger_depth)
    SELECT NEW.reader_id, 'fine',
           format('Нараховано штраф %s грн за прострочення книги «%s» на %s дн.',
                  NEW.fine_amount, b.title, NEW.return_date - NEW.due_date),
           pg_trigger_depth()
    FROM books b WHERE b.book_id = NEW.book_id;
    RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS trg_loans_fine_notify ON loans;
CREATE TRIGGER trg_loans_fine_notify
AFTER UPDATE OF return_date ON loans
FOR EACH ROW
WHEN (OLD.return_date IS NULL AND NEW.return_date IS NOT NULL AND NEW.fine_amount > 0)
EXECUTE FUNCTION fn_loans_fine_notify();

-- ---------------------------------------------------------------------
-- Б. Блокування читача: скасувати бронювання, заблокувати обліковий запис.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_readers_blocked()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE
    v_cnt INTEGER;
BEGIN
    RAISE NOTICE '[рівень %] readers: читача % заблоковано', pg_trigger_depth(), NEW.reader_id;

    UPDATE reservations SET status = 'cancelled'               -- -> trg_reservations_notify
    WHERE reader_id = NEW.reader_id AND status = 'pending';
    GET DIAGNOSTICS v_cnt = ROW_COUNT;

    UPDATE app_users SET is_active = FALSE                     -- -> trg_audit_users (аудит)
    WHERE reader_id = NEW.reader_id AND is_active;

    INSERT INTO notifications (reader_id, kind, message, trigger_depth)
    VALUES (NEW.reader_id, 'account',
            format('Ваш читацький квиток %s заблоковано. Скасовано бронювань: %s',
                   NEW.ticket_number, v_cnt),
            pg_trigger_depth());
    RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS trg_readers_blocked ON readers;
CREATE TRIGGER trg_readers_blocked
AFTER UPDATE OF is_active ON readers
FOR EACH ROW
WHEN (OLD.is_active AND NOT NEW.is_active)
EXECUTE FUNCTION fn_readers_blocked();

-- =====================================================================
-- Перевірка ланцюжка А
-- =====================================================================
-- Нова книга з одним примірником
INSERT INTO books (title, isbn, genre_id, publisher_id, publish_year, pages, price, total_copies, available_copies)
VALUES ('PostgreSQL. Тригери на практиці', '978-617-0000-02-2', 7, 2, 2026, 280, 520.00, 1, 1);

-- Примірник забирає Олена Петренко (LIB-200001), а Бондаренко (читач 3) стає в чергу
SELECT issue_book((SELECT book_id FROM books WHERE isbn = '978-617-0000-02-2'),
                  (SELECT reader_id FROM readers WHERE ticket_number = 'LIB-200001')) AS loan_id;
SELECT reserve_book((SELECT book_id FROM books WHERE isbn = '978-617-0000-02-2'), 3) AS reservation_id;

SELECT book_id, title, available_copies FROM books WHERE isbn = '978-617-0000-02-2';

-- Повернення книги запускає каскад: loans -> books -> reservations -> notifications
SELECT return_book((SELECT l.loan_id FROM loans l JOIN books b USING (book_id)
                    WHERE b.isbn = '978-617-0000-02-2' AND l.return_date IS NULL)) AS fine;

SELECT r.reservation_id, r.reader_id, r.status, r.notified_at::TIMESTAMP(0), r.expires_at::TIMESTAMP(0)
FROM reservations r JOIN books b USING (book_id) WHERE b.isbn = '978-617-0000-02-2';

-- Повернення простроченої книги -> повідомлення про штраф (рівень 1)
SELECT return_book((SELECT loan_id FROM loans
                    WHERE return_date IS NULL AND due_date < CURRENT_DATE - 5
                    ORDER BY loan_id LIMIT 1)) AS fine;

-- =====================================================================
-- Перевірка ланцюжка Б: блокування читача 3, у якого є бронювання
-- =====================================================================
UPDATE readers SET is_active = FALSE WHERE reader_id = 3;

SELECT username, is_active FROM app_users WHERE reader_id = 3;

-- Усі повідомлення, створені каскадами
SELECT n.notification_id AS id, n.reader_id, n.kind, n.trigger_depth AS depth, n.message
FROM notifications n
ORDER BY n.notification_id;

-- Повертаємо читача 3 до активного стану (для подальших кроків)
UPDATE readers   SET is_active = TRUE WHERE reader_id = 3;
UPDATE app_users SET is_active = TRUE WHERE reader_id = 3;
