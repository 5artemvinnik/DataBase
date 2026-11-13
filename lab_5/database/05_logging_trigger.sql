-- =====================================================================
-- 05_logging_trigger.sql — тригер логування вставки та оновлення (рівень 1)
--
-- Історія цін книг: при додаванні книги фіксується початкова ціна,
-- при зміні ціни — стара і нова ціна, відсоток зміни та хто її змінив.
-- Потрібно для обліку вартості фонду та компенсації втрачених книг.
-- =====================================================================

CREATE TABLE IF NOT EXISTS book_price_history (
    history_id  BIGSERIAL PRIMARY KEY,
    book_id     INTEGER      NOT NULL REFERENCES books(book_id) ON DELETE CASCADE,
    operation   VARCHAR(10)  NOT NULL,          -- INSERT або UPDATE
    old_price   NUMERIC(8,2),
    new_price   NUMERIC(8,2) NOT NULL,
    change_pct  NUMERIC(6,2),                   -- зміна ціни у відсотках
    changed_by  VARCHAR(50)  NOT NULL,
    changed_at  TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS idx_price_history_book ON book_price_history (book_id, changed_at DESC);

CREATE OR REPLACE FUNCTION fn_log_book_price()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO book_price_history (book_id, operation, old_price, new_price, change_pct, changed_by)
    VALUES (NEW.book_id,
            TG_OP,                                                   -- 'INSERT' або 'UPDATE'
            CASE WHEN TG_OP = 'UPDATE' THEN OLD.price END,
            NEW.price,
            CASE WHEN TG_OP = 'UPDATE' AND OLD.price > 0
                 THEN ROUND((NEW.price - OLD.price) / OLD.price * 100, 2) END,
            -- користувач застосунку, а якщо зміна напряму в БД — роль PostgreSQL
            COALESCE(NULLIF(current_setting('app.username', TRUE), ''), session_user));
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_books_price_insert ON books;
DROP TRIGGER IF EXISTS trg_books_price_update ON books;

-- Нова книга: фіксуємо початкову ціну
CREATE TRIGGER trg_books_price_insert
AFTER INSERT ON books
FOR EACH ROW
EXECUTE FUNCTION fn_log_book_price();

-- Оновлення: лише якщо ціна справді змінилась (умова WHEN перевіряється
-- ще до виклику функції, тому зміна інших полів не створює зайвих записів)
CREATE TRIGGER trg_books_price_update
AFTER UPDATE OF price ON books
FOR EACH ROW
WHEN (OLD.price IS DISTINCT FROM NEW.price)
EXECUTE FUNCTION fn_log_book_price();

-- ---------------------------------------------------------------------
-- Перевірка роботи тригера
-- ---------------------------------------------------------------------
-- 1) Вставка нової книги
INSERT INTO books (title, isbn, genre_id, publisher_id, publish_year, pages, price, total_copies, available_copies)
VALUES ('Бази даних: практикум', '978-617-0000-01-5', 7, 1, 2025, 320, 450.00, 3, 3);

-- 2) Подорожчання на 10% та знижка — два записи в історії
SET app.username = 'librarian';
UPDATE books SET price = price * 1.10 WHERE isbn = '978-617-0000-01-5';
UPDATE books SET price = 399.00      WHERE isbn = '978-617-0000-01-5';
RESET app.username;

-- 3) Зміна кількості сторінок — ціна не змінилась, запису не буде
UPDATE books SET pages = 336 WHERE isbn = '978-617-0000-01-5';

-- Історія цін нової книги
SELECT h.history_id, b.title, h.operation, h.old_price, h.new_price,
       h.change_pct AS "зміна, %", h.changed_by, h.changed_at::TIMESTAMP(0)
FROM book_price_history h
JOIN books b ON b.book_id = h.book_id
WHERE b.isbn = '978-617-0000-01-5'
ORDER BY h.history_id;
