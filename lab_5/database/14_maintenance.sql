-- =====================================================================
-- 14_maintenance.sql — збережена процедура автоматизованого обслуговування (рівень 3)
--
-- CALL maintain_database() виконує:
--   1) ANALYZE лише тих таблиць, де з моменту останнього аналізу змінилось
--      більше p_analyze_pct % рядків (а не всієї бази щоразу);
--   2) REINDEX таблиць, де частка «мертвих» рядків перевищує p_dead_pct %
--      (після масових UPDATE/DELETE індекси «розбухають»);
--   3) оновлення матеріалізованого представлення;
--   4) бізнес-обслуговування: прострочені видачі та бронювання (процедура з лаб. 4);
--   5) очищення журналу аудиту, старшого за p_audit_keep.
-- Кожен крок фіксується в maintenance_log з тривалістю.
--
-- VACUUM та REINDEX DATABASE не можна виконувати всередині процедури
-- (транзакційного блоку), тому VACUUM запускається окремо скриптом
-- scripts/maintenance.sh через утиліту vacuumdb.
-- =====================================================================

CREATE TABLE IF NOT EXISTS maintenance_log (
    log_id      SERIAL PRIMARY KEY,
    run_id      INTEGER     NOT NULL,              -- номер запуску процедури
    operation   VARCHAR(30) NOT NULL,
    object_name TEXT,
    details     TEXT,
    duration_ms NUMERIC(10,1),
    executed_at TIMESTAMP   NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE SEQUENCE IF NOT EXISTS maintenance_run_seq;

CREATE OR REPLACE PROCEDURE maintain_database(
    p_analyze_pct NUMERIC  DEFAULT 5,              -- поріг змін для ANALYZE, %
    p_dead_pct    NUMERIC  DEFAULT 10,             -- поріг «мертвих» рядків для REINDEX, %
    p_audit_keep  INTERVAL DEFAULT INTERVAL '1 year',
    p_dry_run     BOOLEAN  DEFAULT FALSE           -- TRUE: лише показати, що буде зроблено
)
LANGUAGE plpgsql AS $$
DECLARE
    v_run   INTEGER := nextval('maintenance_run_seq');
    v_t0    TIMESTAMP;
    v_total TIMESTAMP := clock_timestamp();
    v_cnt   INTEGER;
    tbl     RECORD;

BEGIN
    RAISE NOTICE '=== Обслуговування БД, запуск № % % ===', v_run,
        CASE WHEN p_dry_run THEN '(пробний режим)' ELSE '' END;

    -- 1. ANALYZE таблиць із суттєвими змінами
    FOR tbl IN
        SELECT schemaname, relname, n_live_tup, n_mod_since_analyze,
               ROUND(100.0 * n_mod_since_analyze / GREATEST(n_live_tup, 1), 1) AS mod_pct
        FROM pg_stat_user_tables
        WHERE schemaname = 'public'
          AND 100.0 * n_mod_since_analyze / GREATEST(n_live_tup, 1) > p_analyze_pct
        ORDER BY n_mod_since_analyze DESC
    LOOP
        v_t0 := clock_timestamp();
        IF NOT p_dry_run THEN
            EXECUTE format('ANALYZE %I.%I', tbl.schemaname, tbl.relname);
        END IF;
        INSERT INTO maintenance_log (run_id, operation, object_name, details, duration_ms)
        VALUES (v_run, 'ANALYZE', tbl.relname,
                format('змінено %s з %s рядків (%s%%)', tbl.n_mod_since_analyze, tbl.n_live_tup, tbl.mod_pct),
                EXTRACT(EPOCH FROM clock_timestamp() - v_t0) * 1000);
        RAISE NOTICE 'ANALYZE %: змінено % %%', tbl.relname, tbl.mod_pct;
    END LOOP;

    -- 2. REINDEX таблиць з великою часткою «мертвих» рядків
    FOR tbl IN
        SELECT schemaname, relname, n_live_tup, n_dead_tup,
               ROUND(100.0 * n_dead_tup / GREATEST(n_live_tup + n_dead_tup, 1), 1) AS dead_pct,
               pg_size_pretty(pg_indexes_size(relid)) AS idx_size
        FROM pg_stat_user_tables
        WHERE schemaname = 'public'
          AND n_live_tup + n_dead_tup > 1000
          AND 100.0 * n_dead_tup / GREATEST(n_live_tup + n_dead_tup, 1) > p_dead_pct
    LOOP
        v_t0 := clock_timestamp();
        IF NOT p_dry_run THEN
            EXECUTE format('REINDEX TABLE %I.%I', tbl.schemaname, tbl.relname);
        END IF;
        INSERT INTO maintenance_log (run_id, operation, object_name, details, duration_ms)
        VALUES (v_run, 'REINDEX', tbl.relname,
                format('мертвих рядків %s%%, індекси до перебудови: %s', tbl.dead_pct, tbl.idx_size),
                EXTRACT(EPOCH FROM clock_timestamp() - v_t0) * 1000);
        RAISE NOTICE 'REINDEX %: мертвих рядків % %%', tbl.relname, tbl.dead_pct;
    END LOOP;

    -- 3. Оновлення матеріалізованого представлення
    v_t0 := clock_timestamp();
    IF NOT p_dry_run THEN
        REFRESH MATERIALIZED VIEW CONCURRENTLY mv_genre_monthly_stats;
    END IF;
    INSERT INTO maintenance_log (run_id, operation, object_name, duration_ms)
    VALUES (v_run, 'REFRESH MV', 'mv_genre_monthly_stats',
            EXTRACT(EPOCH FROM clock_timestamp() - v_t0) * 1000);

    -- 4. Бізнес-обслуговування: прострочені видачі, протерміновані бронювання
    v_t0 := clock_timestamp();
    IF NOT p_dry_run THEN
        CALL update_overdue_status();
    END IF;
    INSERT INTO maintenance_log (run_id, operation, object_name, duration_ms)
    VALUES (v_run, 'OVERDUE', 'loans, reservations',
            EXTRACT(EPOCH FROM clock_timestamp() - v_t0) * 1000);

    -- 5. Очищення старих записів журналу аудиту (журнал захищений тригером,
    --    тому дозвіл вмикається лише в межах цієї транзакції)
    v_t0 := clock_timestamp();
    IF p_dry_run THEN
        SELECT COUNT(*) INTO v_cnt FROM audit_log WHERE changed_at < NOW() - p_audit_keep;
    ELSE
        PERFORM set_config('audit.allow_purge', 'on', TRUE);
        DELETE FROM audit_log WHERE changed_at < NOW() - p_audit_keep;
        GET DIAGNOSTICS v_cnt = ROW_COUNT;
        PERFORM set_config('audit.allow_purge', 'off', TRUE);
    END IF;
    INSERT INTO maintenance_log (run_id, operation, object_name, details, duration_ms)
    VALUES (v_run, 'PURGE AUDIT', 'audit_log',
            format('записів старших за %s: %s', p_audit_keep, v_cnt),
            EXTRACT(EPOCH FROM clock_timestamp() - v_t0) * 1000);

    INSERT INTO maintenance_log (run_id, operation, details, duration_ms)
    VALUES (v_run, 'TOTAL', CASE WHEN p_dry_run THEN 'пробний запуск' ELSE 'виконано' END,
            EXTRACT(EPOCH FROM clock_timestamp() - v_total) * 1000);

    RAISE NOTICE '=== Завершено за % мс ===',
        ROUND(EXTRACT(EPOCH FROM clock_timestamp() - v_total) * 1000);
END;
$$;

REVOKE EXECUTE ON PROCEDURE maintain_database(NUMERIC, NUMERIC, INTERVAL, BOOLEAN) FROM PUBLIC;
GRANT  EXECUTE ON PROCEDURE maintain_database(NUMERIC, NUMERIC, INTERVAL, BOOLEAN) TO lib_administrator;
GRANT  SELECT ON maintenance_log TO lib_administrator;

-- ---------------------------------------------------------------------
-- Перевірка: імітуємо інтенсивну роботу — масове оновлення 30% видач
-- (кожен UPDATE лишає «мертву» версію рядка), а потім запускаємо обслуговування
-- ---------------------------------------------------------------------
SET session_replication_role = replica;     -- без тригерів аудиту, лише для імітації навантаження
UPDATE loans SET extensions_count = extensions_count WHERE loan_id % 10 < 3;
SET session_replication_role = origin;

SELECT relname, n_live_tup, n_dead_tup, n_mod_since_analyze,
       pg_size_pretty(pg_indexes_size(relid)) AS indexes_size
FROM pg_stat_user_tables WHERE relname = 'loans';

-- Пробний запуск: лише показує, що буде зроблено
CALL maintain_database(p_dry_run => TRUE);

-- Реальний запуск
CALL maintain_database();

SELECT relname, n_live_tup, n_dead_tup, n_mod_since_analyze,
       pg_size_pretty(pg_indexes_size(relid)) AS indexes_size
FROM pg_stat_user_tables WHERE relname = 'loans';

-- Журнал останнього запуску
SELECT run_id, operation, object_name, details, duration_ms
FROM maintenance_log
WHERE run_id = (SELECT MAX(run_id) FROM maintenance_log)
ORDER BY log_id;
