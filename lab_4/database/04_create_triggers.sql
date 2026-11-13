-- =====================================================================
-- 04_create_triggers.sql — тригери для автоматизації процесів
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Синхронізація кількості доступних примірників з видачами.
--    INSERT видачі       -> available_copies - 1
--    повернення (UPDATE) -> available_copies + 1
--    DELETE невиданої    -> available_copies + 1
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_sync_book_availability()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    IF TG_OP = 'INSERT' AND NEW.return_date IS NULL THEN
        UPDATE books SET available_copies = available_copies - 1
        WHERE book_id = NEW.book_id;

    ELSIF TG_OP = 'UPDATE' THEN
        -- книгу повернули
        IF OLD.return_date IS NULL AND NEW.return_date IS NOT NULL THEN
            UPDATE books SET available_copies = available_copies + 1
            WHERE book_id = NEW.book_id;
        -- повернення скасували (виправлення помилки бібліотекаря)
        ELSIF OLD.return_date IS NOT NULL AND NEW.return_date IS NULL THEN
            UPDATE books SET available_copies = available_copies - 1
            WHERE book_id = NEW.book_id;
        END IF;

    ELSIF TG_OP = 'DELETE' AND OLD.return_date IS NULL THEN
        UPDATE books SET available_copies = available_copies + 1
        WHERE book_id = OLD.book_id;
    END IF;

    RETURN COALESCE(NEW, OLD);
END;
$$;

CREATE TRIGGER trg_loans_sync_availability
AFTER INSERT OR UPDATE OF return_date OR DELETE ON loans
FOR EACH ROW EXECUTE FUNCTION fn_sync_book_availability();

-- ---------------------------------------------------------------------
-- 2. Перевірка та доповнення видачі перед вставкою:
--    термін за замовчуванням 14 днів, заборона видачі заблокованим
--    читачам і книгам без вільних примірників.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_validate_loan()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE
    v_available INTEGER;
BEGIN
    IF NEW.loan_date IS NULL THEN
        NEW.loan_date := CURRENT_DATE;
    END IF;
    IF NEW.due_date IS NULL THEN
        NEW.due_date := NEW.loan_date + 14;
    END IF;

    IF NOT (SELECT is_active FROM readers WHERE reader_id = NEW.reader_id) THEN
        RAISE EXCEPTION 'Неможливо видати книгу: читацький квиток заблоковано';
    END IF;

    IF NEW.return_date IS NULL THEN
        SELECT available_copies INTO v_available FROM books WHERE book_id = NEW.book_id;
        IF v_available <= 0 THEN
            RAISE EXCEPTION 'Неможливо видати книгу: немає доступних примірників';
        END IF;
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_loans_validate
BEFORE INSERT ON loans
FOR EACH ROW EXECUTE FUNCTION fn_validate_loan();

-- ---------------------------------------------------------------------
-- 3. Автоматичне оновлення поля updated_at у книгах.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_set_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    NEW.updated_at := CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_books_updated_at
BEFORE UPDATE ON books
FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

-- ---------------------------------------------------------------------
-- 4. Зміна загальної кількості примірників автоматично коригує
--    доступні; не можна зменшити нижче кількості виданих.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_adjust_copies()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE
    v_on_hand INTEGER;
BEGIN
    IF NEW.total_copies <> OLD.total_copies THEN
        v_on_hand := OLD.total_copies - OLD.available_copies;
        IF NEW.total_copies < v_on_hand THEN
            RAISE EXCEPTION 'Не можна встановити % примірників: % зараз видано читачам',
                NEW.total_copies, v_on_hand;
        END IF;
        NEW.available_copies := NEW.total_copies - v_on_hand;
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_books_adjust_copies
BEFORE UPDATE OF total_copies ON books
FOR EACH ROW EXECUTE FUNCTION fn_adjust_copies();
