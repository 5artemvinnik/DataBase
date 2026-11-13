-- =====================================================================
-- 02_performance_before.sql — аналіз продуктивності ДО оптимізації (рівень 1)
--
-- Три типові «важкі» запити електронної бібліотеки:
--   Q1  пошук книги за частиною назви (рядок пошуку на сайті);
--   Q2  фінансовий звіт: штрафи за останні 90 днів по тижнях;
--   Q3  особистий кабінет читача: його відгуки та скільки разів він брав книгу.
-- Кожен запит аналізується через EXPLAIN (ANALYZE, BUFFERS), а час
-- виконання автоматично зберігається в таблицю perf_results для порівняння.
-- =====================================================================

-- ---------------------------------------------------------------------
-- Інфраструктура для вимірювань
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS perf_results (
    result_id   SERIAL PRIMARY KEY,
    stage       VARCHAR(10)  NOT NULL CHECK (stage IN ('до', 'після')),
    query_name  VARCHAR(60)  NOT NULL,
    exec_ms     NUMERIC(10,3) NOT NULL,   -- медіана часу виконання
    plan_nodes  TEXT,                     -- які методи доступу обрав оптимізатор
    measured_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- Виконує запит p_runs разів через EXPLAIN (ANALYZE, FORMAT JSON),
-- бере медіану часу (перший «холодний» запуск не враховується)
-- і записує результат разом із типами вузлів плану.
CREATE OR REPLACE FUNCTION measure_query(p_stage TEXT, p_name TEXT, p_sql TEXT, p_runs INT DEFAULT 7)
RETURNS NUMERIC LANGUAGE plpgsql AS $$
DECLARE
    v_plan   JSONB;
    v_times  NUMERIC[] := '{}';
    v_nodes  TEXT;
    v_median NUMERIC;
BEGIN
    EXECUTE 'EXPLAIN (ANALYZE, FORMAT JSON) ' || p_sql INTO v_plan;      -- прогрів кешу
    FOR i IN 1..p_runs LOOP
        EXECUTE 'EXPLAIN (ANALYZE, FORMAT JSON) ' || p_sql INTO v_plan;
        v_times := v_times || (v_plan -> 0 ->> 'Execution Time')::NUMERIC;
    END LOOP;

    SELECT percentile_cont(0.5) WITHIN GROUP (ORDER BY t) INTO v_median FROM unnest(v_times) t;

    -- усі методи доступу до таблиць (Seq Scan, Index Scan, Bitmap ...) з назвами об'єктів
    SELECT string_agg(DISTINCT n ->> 'Node Type' ||
                      COALESCE(' ' || COALESCE(n ->> 'Index Name', n ->> 'Relation Name'), ''), ', ')
    INTO v_nodes
    FROM jsonb_path_query(v_plan, 'strict $.**') n
    WHERE jsonb_typeof(n) = 'object' AND n ->> 'Node Type' ~ 'Scan';

    INSERT INTO perf_results (stage, query_name, exec_ms, plan_nodes)
    VALUES (p_stage, p_name, ROUND(v_median, 3), v_nodes);
    RETURN ROUND(v_median, 3);
END;
$$;

-- Порівняння «до / після» з відсотком покращення
CREATE OR REPLACE VIEW v_perf_comparison AS
SELECT b.query_name                                           AS "Запит",
       b.exec_ms                                              AS "До, мс",
       a.exec_ms                                              AS "Після, мс",
       ROUND((1 - a.exec_ms / NULLIF(b.exec_ms, 0)) * 100, 1) AS "Покращення, %",
       ROUND(b.exec_ms / NULLIF(a.exec_ms, 0), 1)             AS "Прискорення, разів"
FROM (SELECT DISTINCT ON (query_name) * FROM perf_results WHERE stage = 'до'
      ORDER BY query_name, measured_at DESC) b
JOIN (SELECT DISTINCT ON (query_name) * FROM perf_results WHERE stage = 'після'
      ORDER BY query_name, measured_at DESC) a USING (query_name)
ORDER BY 1;

-- ---------------------------------------------------------------------
-- Q1. Пошук книг за частиною назви (без урахування регістру)
-- ILIKE '%...%' не може використати звичайний B-tree індекс, бо шаблон
-- починається з %, тому PostgreSQL переглядає всі 50 000 книг.
-- ---------------------------------------------------------------------
EXPLAIN (ANALYZE, BUFFERS)
SELECT b.book_id, b.title, g.name AS genre, b.publish_year, b.available_copies
FROM books b
JOIN genres g ON g.genre_id = b.genre_id
WHERE b.title ILIKE '%маяк. книга 1%'
ORDER BY b.title
LIMIT 20;

-- ---------------------------------------------------------------------
-- Q2. Штрафи за останні 90 днів, згруповані по тижнях
-- Індексу за датою повернення немає — повне сканування 500 000 видач.
-- ---------------------------------------------------------------------
EXPLAIN (ANALYZE, BUFFERS)
SELECT DATE_TRUNC('week', return_date)::DATE AS week,
       COUNT(*)                              AS fined_loans,
       SUM(fine_amount)                      AS fines_total
FROM loans
WHERE return_date >= CURRENT_DATE - 90
  AND fine_amount > 0
GROUP BY 1
ORDER BY 1;

-- ---------------------------------------------------------------------
-- Q3. Кабінет читача: відгуки читача, від найновіших, і скільки разів
-- він брав кожну книгу. Зовнішній ключ reviews.reader_id не має
-- власного індексу (PostgreSQL не створює їх автоматично), тому
-- доводиться перебирати весь індекс uq_review (book_id, reader_id).
-- ---------------------------------------------------------------------
EXPLAIN (ANALYZE, BUFFERS)
SELECT b.title, rv.rating, rv.created_at,
       (SELECT COUNT(*) FROM loans l
        WHERE l.reader_id = rv.reader_id AND l.book_id = rv.book_id) AS times_borrowed
FROM reviews rv
JOIN books b ON b.book_id = rv.book_id
WHERE rv.reader_id = 777
ORDER BY rv.created_at DESC;

-- ---------------------------------------------------------------------
-- Фіксуємо медіанний час виконання до оптимізації
-- ---------------------------------------------------------------------
SELECT measure_query('до', 'Q1 Пошук за назвою',
  $q$SELECT b.book_id, b.title, g.name, b.publish_year, b.available_copies
     FROM books b JOIN genres g ON g.genre_id = b.genre_id
     WHERE b.title ILIKE '%маяк. книга 1%' ORDER BY b.title LIMIT 20$q$) AS "Q1, мс";

SELECT measure_query('до', 'Q2 Штрафи за 90 днів',
  $q$SELECT DATE_TRUNC('week', return_date)::DATE, COUNT(*), SUM(fine_amount)
     FROM loans WHERE return_date >= CURRENT_DATE - 90 AND fine_amount > 0
     GROUP BY 1 ORDER BY 1$q$) AS "Q2, мс";

SELECT measure_query('до', 'Q3 Кабінет читача',
  $q$SELECT b.title, rv.rating, rv.created_at,
            (SELECT COUNT(*) FROM loans l WHERE l.reader_id = rv.reader_id AND l.book_id = rv.book_id)
     FROM reviews rv JOIN books b ON b.book_id = rv.book_id
     WHERE rv.reader_id = 777 ORDER BY rv.created_at DESC$q$) AS "Q3, мс";

SELECT stage AS "Етап", query_name AS "Запит", exec_ms AS "Час, мс", plan_nodes AS "Методи доступу"
FROM perf_results WHERE stage = 'до' ORDER BY query_name;
