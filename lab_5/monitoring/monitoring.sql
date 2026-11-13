-- =====================================================================
-- monitoring.sql — SQL-запити моніторингу продуктивності (рівень 3)
-- Ті самі дані, що збирає monitor.py, але для запуску вручну в psql.
-- =====================================================================

-- 1. Cache hit ratio: частка читань сторінок із пам'яті (норма > 99%)
SELECT datname,
       ROUND(100.0 * blks_hit / NULLIF(blks_hit + blks_read, 0), 2) AS cache_hit_pct,
       xact_commit, xact_rollback, deadlocks
FROM pg_stat_database
WHERE datname = current_database();

-- 2. Індекси, які жодного разу не використовувались (кандидати на видалення).
--    Первинні ключі та унікальні індекси не враховуємо — вони забезпечують цілісність.
SELECT s.schemaname,
       s.relname                                    AS table_name,
       s.indexrelname                               AS index_name,
       s.idx_scan                                   AS index_scans,
       s.idx_tup_read                               AS tuples_read,
       s.idx_tup_fetch                              AS tuples_fetched,
       pg_size_pretty(pg_relation_size(s.indexrelid)) AS index_size
FROM pg_stat_user_indexes s
JOIN pg_index i ON i.indexrelid = s.indexrelid
WHERE s.idx_scan = 0 AND NOT i.indisunique
ORDER BY pg_relation_size(s.indexrelid) DESC;

-- 3. Таблиці, які найчастіше читаються повним скануванням
SELECT relname, seq_scan, seq_tup_read, idx_scan,
       ROUND(100.0 * idx_scan / NULLIF(seq_scan + idx_scan, 0), 1) AS idx_usage_pct,
       n_live_tup
FROM pg_stat_user_tables
WHERE seq_scan > 0
ORDER BY seq_tup_read DESC
LIMIT 10;

-- 4. Найповільніші запити (розширення pg_stat_statements)
SELECT calls,
       ROUND(total_exec_time::NUMERIC, 1) AS total_ms,
       ROUND(mean_exec_time::NUMERIC, 2)  AS mean_ms,
       ROUND(max_exec_time::NUMERIC, 2)   AS max_ms,
       LEFT(REGEXP_REPLACE(query, '\s+', ' ', 'g'), 80) AS query
FROM pg_stat_statements
WHERE dbid = (SELECT oid FROM pg_database WHERE datname = current_database())
ORDER BY mean_exec_time DESC
LIMIT 10;

-- 5. Запити, що виконуються довше хвилини, та блокування
SELECT pid, usename, state, NOW() - query_start AS duration, LEFT(query, 60) AS query
FROM pg_stat_activity
WHERE state <> 'idle' AND NOW() - query_start > INTERVAL '1 minute';

SELECT pid, pg_blocking_pids(pid) AS blocked_by, LEFT(query, 60) AS query
FROM pg_stat_activity
WHERE cardinality(pg_blocking_pids(pid)) > 0;

-- =====================================================================
-- Реакція на результати моніторингу.
-- monitor.py показав, що таблиця readers читається повним скануванням
-- (≈50% звернень), а в pg_stat_statements другим за часом виявився запит
-- «SELECT COUNT(*) FROM readers WHERE registration_date = ...».
-- Додаємо індекс і перевіряємо план.
-- =====================================================================
EXPLAIN (ANALYZE, COSTS OFF)
SELECT COUNT(*) FROM readers WHERE registration_date = CURRENT_DATE - 100;

CREATE INDEX IF NOT EXISTS idx_readers_registration ON readers (registration_date);
ANALYZE readers;

EXPLAIN (ANALYZE, COSTS OFF)
SELECT COUNT(*) FROM readers WHERE registration_date = CURRENT_DATE - 100;
