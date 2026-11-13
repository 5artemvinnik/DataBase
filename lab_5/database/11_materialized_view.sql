-- =====================================================================
-- 11_materialized_view.sql — матеріалізоване представлення з
-- автоматичним оновленням через тригери (рівень 3)
--
-- mv_genre_monthly_stats — щомісячна статистика за жанрами: видачі,
-- унікальні читачі, сума штрафів, середня тривалість читання, середня оцінка.
-- Звичайне представлення щоразу агрегувало б 500 000 видач, а
-- матеріалізоване зберігає готовий результат (≈ 400 рядків).
-- =====================================================================

DROP MATERIALIZED VIEW IF EXISTS mv_genre_monthly_stats CASCADE;

CREATE MATERIALIZED VIEW mv_genre_monthly_stats AS
WITH loan_stats AS (
    SELECT b.genre_id,
           DATE_TRUNC('month', l.loan_date)::DATE                  AS month,
           COUNT(*)                                                AS loans_count,
           COUNT(DISTINCT l.reader_id)                             AS unique_readers,
           SUM(l.fine_amount)                                      AS fines_total,
           ROUND(AVG(l.return_date - l.loan_date), 1)              AS avg_days_reading
    FROM loans l
    JOIN books b ON b.book_id = l.book_id
    GROUP BY 1, 2
), review_stats AS (
    SELECT b.genre_id,
           DATE_TRUNC('month', r.created_at)::DATE                 AS month,
           ROUND(AVG(r.rating), 2)                                 AS avg_rating,
           COUNT(*)                                                AS reviews_count
    FROM reviews r
    JOIN books b ON b.book_id = r.book_id
    GROUP BY 1, 2
)
SELECT g.genre_id,
       g.name                              AS genre,
       ls.month,
       ls.loans_count,
       ls.unique_readers,
       ls.fines_total,
       ls.avg_days_reading,
       rs.avg_rating,
       COALESCE(rs.reviews_count, 0)       AS reviews_count,
       NOW()                               AS refreshed_at       -- час останнього оновлення
FROM loan_stats ls
JOIN genres g ON g.genre_id = ls.genre_id
LEFT JOIN review_stats rs ON rs.genre_id = ls.genre_id AND rs.month = ls.month;

-- Унікальний індекс обов'язковий для REFRESH ... CONCURRENTLY
-- (оновлення без блокування читання) і прискорює пошук за жанром/місяцем
CREATE UNIQUE INDEX idx_mv_genre_month ON mv_genre_monthly_stats (genre_id, month);

COMMENT ON MATERIALIZED VIEW mv_genre_monthly_stats IS
    'Щомісячна статистика за жанрами; оновлюється автоматично тригерами';

-- ---------------------------------------------------------------------
-- Автоматичне оновлення.
-- Наївний варіант — REFRESH після кожного оператора — при пакетній
-- роботі виконував би важке оновлення багато разів у межах однієї транзакції.
-- Тому використано ВІДКЛАДЕНИЙ тригер обмеження (CONSTRAINT TRIGGER ...
-- INITIALLY DEFERRED): він спрацьовує в момент COMMIT, а прапорець у
-- налаштуваннях транзакції гарантує, що REFRESH виконається ОДИН раз на
-- транзакцію, скільки б рядків вона не змінила.
-- SECURITY DEFINER: оновлювати MV може лише власник, тому функція
-- виконується з правами власника (postgres), а не користувача застосунку.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_refresh_genre_stats()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
    v_start TIMESTAMP := clock_timestamp();
BEGIN
    -- уже оновлювали в цій транзакції — пропускаємо
    IF current_setting('lab5.mv_refreshed_tx', TRUE) = txid_current()::TEXT THEN
        RETURN NULL;
    END IF;
    PERFORM set_config('lab5.mv_refreshed_tx', txid_current()::TEXT, TRUE);   -- TRUE = до кінця транзакції

    REFRESH MATERIALIZED VIEW CONCURRENTLY mv_genre_monthly_stats;

    RAISE NOTICE 'mv_genre_monthly_stats оновлено за % мс (таблиця %, операція %)',
        ROUND(EXTRACT(EPOCH FROM clock_timestamp() - v_start) * 1000), TG_TABLE_NAME, TG_OP;
    RETURN NULL;
END;
$$;

REVOKE ALL ON FUNCTION fn_refresh_genre_stats() FROM PUBLIC;

DROP TRIGGER IF EXISTS trg_mv_refresh_loans ON loans;
CREATE CONSTRAINT TRIGGER trg_mv_refresh_loans
AFTER INSERT OR UPDATE OR DELETE ON loans
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION fn_refresh_genre_stats();

DROP TRIGGER IF EXISTS trg_mv_refresh_reviews ON reviews;
CREATE CONSTRAINT TRIGGER trg_mv_refresh_reviews
AFTER INSERT OR UPDATE OR DELETE ON reviews
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION fn_refresh_genre_stats();

-- ---------------------------------------------------------------------
-- Перевірка
-- ---------------------------------------------------------------------
-- Розмір та кількість рядків
SELECT COUNT(*) AS "Рядків у MV",
       pg_size_pretty(pg_total_relation_size('mv_genre_monthly_stats')) AS "Розмір"
FROM mv_genre_monthly_stats;

-- Порівняння швидкості: той самий агрегат за останні 12 місяців
-- через MV (≈120 готових рядків) та «на льоту» з 500 000 видач
\timing on
SELECT genre, SUM(loans_count) AS loans_12m
FROM mv_genre_monthly_stats
WHERE month >= DATE_TRUNC('month', CURRENT_DATE) - INTERVAL '11 months'
GROUP BY genre ORDER BY 2 DESC LIMIT 3;

SELECT g.name AS genre, COUNT(*) AS loans_12m
FROM loans l
JOIN books  b ON b.book_id  = l.book_id
JOIN genres g ON g.genre_id = b.genre_id
WHERE l.loan_date >= DATE_TRUNC('month', CURRENT_DATE) - INTERVAL '11 months'
GROUP BY g.name ORDER BY 2 DESC LIMIT 3;
\timing off

-- Стан ДО: статистика поточного місяця для жанрів книг 1, 6 (Поезія) і 2
SELECT genre, month, loans_count, unique_readers, refreshed_at::TIME(0)
FROM mv_genre_monthly_stats
WHERE genre_id IN (1, 2) AND month = DATE_TRUNC('month', CURRENT_DATE)
ORDER BY genre_id;

-- Транзакція з трьома видачами новій читачці (LIB-200001, крок 8):
-- MV оновиться ОДИН раз — під час COMMIT
BEGIN;
SELECT issue_book(1, r.reader_id) AS loan_1,
       issue_book(6, r.reader_id) AS loan_2,
       issue_book(2, r.reader_id) AS loan_3
FROM readers r WHERE r.ticket_number = 'LIB-200001';
COMMIT;

-- Стан ПІСЛЯ: лічильники зросли (+2 і +1) без ручного REFRESH
SELECT genre, month, loans_count, unique_readers, refreshed_at::TIME(0)
FROM mv_genre_monthly_stats
WHERE genre_id IN (1, 2) AND month = DATE_TRUNC('month', CURRENT_DATE)
ORDER BY genre_id;
