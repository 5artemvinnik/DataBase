-- =====================================================================
-- 03_indexes.sql — індекси для оптимізації запитів Q1–Q3 (рівень 1)
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. GIN-індекс на триграмах назви (розширення pg_trgm).
-- Назва розбивається на трійки символів («мая», «аяк», …), тому індекс
-- підтримує LIKE / ILIKE з % на початку шаблону, а також пошук схожих рядків.
-- ---------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_books_title_trgm
    ON books USING GIN (title gin_trgm_ops);

-- ---------------------------------------------------------------------
-- 2. Покривний (covering) B-tree індекс за датою повернення.
-- INCLUDE (fine_amount) зберігає суму штрафу прямо в індексі, тож для Q2
-- можливе Index Only Scan — без звернення до самої таблиці loans.
-- ---------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_loans_return_date
    ON loans (return_date) INCLUDE (fine_amount);

-- ---------------------------------------------------------------------
-- 3. Складений індекс для зовнішнього ключа reviews.reader_id.
-- Другий стовпець created_at DESC віддає відгуки одразу у потрібному
-- порядку, тому зникає окреме сортування. Індекс також прискорює
-- перевірку FK при видаленні читача (ON DELETE CASCADE).
-- ---------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_reviews_reader_created
    ON reviews (reader_id, created_at DESC);

-- Оновлюємо статистику та карту видимості (потрібна для Index Only Scan)
VACUUM ANALYZE books;
VACUUM ANALYZE loans;
VACUUM ANALYZE reviews;

-- Розмір нових індексів
SELECT indexrelname                                   AS "Індекс",
       relname                                        AS "Таблиця",
       pg_size_pretty(pg_relation_size(indexrelid))   AS "Розмір"
FROM pg_stat_user_indexes
WHERE indexrelname IN ('idx_books_title_trgm', 'idx_loans_return_date', 'idx_reviews_reader_created');

-- ---------------------------------------------------------------------
-- Повторний аналіз тих самих запитів
-- ---------------------------------------------------------------------
EXPLAIN (ANALYZE, BUFFERS)
SELECT b.book_id, b.title, g.name AS genre, b.publish_year, b.available_copies
FROM books b
JOIN genres g ON g.genre_id = b.genre_id
WHERE b.title ILIKE '%маяк. книга 1%'
ORDER BY b.title
LIMIT 20;

EXPLAIN (ANALYZE, BUFFERS)
SELECT DATE_TRUNC('week', return_date)::DATE AS week,
       COUNT(*)                              AS fined_loans,
       SUM(fine_amount)                      AS fines_total
FROM loans
WHERE return_date >= CURRENT_DATE - 90
  AND fine_amount > 0
GROUP BY 1
ORDER BY 1;

EXPLAIN (ANALYZE, BUFFERS)
SELECT b.title, rv.rating, rv.created_at,
       (SELECT COUNT(*) FROM loans l
        WHERE l.reader_id = rv.reader_id AND l.book_id = rv.book_id) AS times_borrowed
FROM reviews rv
JOIN books b ON b.book_id = rv.book_id
WHERE rv.reader_id = 777
ORDER BY rv.created_at DESC;

-- ---------------------------------------------------------------------
-- Вимірювання після оптимізації та порівняння
-- ---------------------------------------------------------------------
SELECT measure_query('після', 'Q1 Пошук за назвою',
  $q$SELECT b.book_id, b.title, g.name, b.publish_year, b.available_copies
     FROM books b JOIN genres g ON g.genre_id = b.genre_id
     WHERE b.title ILIKE '%маяк. книга 1%' ORDER BY b.title LIMIT 20$q$) AS "Q1, мс";

SELECT measure_query('після', 'Q2 Штрафи за 90 днів',
  $q$SELECT DATE_TRUNC('week', return_date)::DATE, COUNT(*), SUM(fine_amount)
     FROM loans WHERE return_date >= CURRENT_DATE - 90 AND fine_amount > 0
     GROUP BY 1 ORDER BY 1$q$) AS "Q2, мс";

SELECT measure_query('після', 'Q3 Кабінет читача',
  $q$SELECT b.title, rv.rating, rv.created_at,
            (SELECT COUNT(*) FROM loans l WHERE l.reader_id = rv.reader_id AND l.book_id = rv.book_id)
     FROM reviews rv JOIN books b ON b.book_id = rv.book_id
     WHERE rv.reader_id = 777 ORDER BY rv.created_at DESC$q$) AS "Q3, мс";

SELECT stage AS "Етап", query_name AS "Запит", exec_ms AS "Час, мс", plan_nodes AS "Методи доступу"
FROM perf_results ORDER BY query_name, stage DESC;

SELECT * FROM v_perf_comparison;
