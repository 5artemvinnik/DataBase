-- =====================================================================
-- 09_audit_system.sql — система логування змін (рівень 2)
--
-- Таблиця audit_log і універсальна тригерна функція fn_audit() з'явилися
-- ще в лабораторній 4 (07_create_audit.sql) і вже фіксують:
--   тип операції, назву таблиці, час, користувача, старі та нові значення.
-- У цій роботі систему розширено:
--   1) додаткові поля: роль БД, IP-адреса клієнта, програма, номер транзакції;
--   2) аудит ще двох таблиць (reviews, book_authors) та операції TRUNCATE;
--   3) журнал зроблено незмінним (append-only): редагувати чи видаляти
--      записи заборонено, очищення старих записів — лише процедурою обслуговування;
--   4) функція audit_history() — історія змін конкретного запису.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Додаткові поля журналу
-- ---------------------------------------------------------------------
ALTER TABLE audit_log
    ADD COLUMN IF NOT EXISTS db_user     VARCHAR(50) DEFAULT current_user,      -- роль PostgreSQL
    ADD COLUMN IF NOT EXISTS client_addr INET        DEFAULT inet_client_addr(), -- звідки підключення
    ADD COLUMN IF NOT EXISTS app_name    VARCHAR(64) DEFAULT current_setting('application_name'),
    ADD COLUMN IF NOT EXISTS tx_id       BIGINT      DEFAULT txid_current();     -- одна транзакція = один id

COMMENT ON TABLE audit_log IS 'Журнал змін даних (append-only)';

-- ---------------------------------------------------------------------
-- 2. Оновлена універсальна тригерна функція
--    TG_ARGV[0] — назва стовпця первинного ключа таблиці.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_audit()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE
    v_user VARCHAR(50);
    v_old  JSONB;
    v_new  JSONB;
    v_id   INTEGER;
BEGIN
    -- користувач застосунку, а якщо зміну зроблено напряму в БД — роль сесії
    v_user := COALESCE(NULLIF(current_setting('app.username', TRUE), ''), session_user);

    IF TG_OP IN ('UPDATE', 'DELETE') THEN v_old := to_jsonb(OLD) - 'password_hash'; END IF;
    IF TG_OP IN ('INSERT', 'UPDATE') THEN v_new := to_jsonb(NEW) - 'password_hash'; END IF;

    -- в UPDATE зберігаємо лише ті поля, що змінилися
    IF TG_OP = 'UPDATE' THEN
        SELECT jsonb_object_agg(n.key, n.value), jsonb_object_agg(n.key, v_old -> n.key)
        INTO v_new, v_old
        FROM jsonb_each(v_new) n
        WHERE n.value IS DISTINCT FROM v_old -> n.key;
        IF v_new IS NULL THEN RETURN NEW; END IF;           -- фактично нічого не змінилось
    END IF;

    v_id := (COALESCE(to_jsonb(NEW), to_jsonb(OLD)) ->> TG_ARGV[0])::INTEGER;

    -- db_user = session_user: справжня роль, що підключилася (функція може
    -- виконуватися як SECURITY DEFINER, тоді current_user був би власником)
    INSERT INTO audit_log (table_name, operation, record_id, old_data, new_data, changed_by, db_user)
    VALUES (TG_TABLE_NAME, TG_OP, v_id, v_old, v_new, v_user, session_user);

    RETURN COALESCE(NEW, OLD);
END;
$$;

-- Аудит таблиць, які не охоплювала лабораторна 4
DROP TRIGGER IF EXISTS trg_audit_reviews ON reviews;
CREATE TRIGGER trg_audit_reviews AFTER INSERT OR UPDATE OR DELETE ON reviews
    FOR EACH ROW EXECUTE FUNCTION fn_audit('review_id');

DROP TRIGGER IF EXISTS trg_audit_book_authors ON book_authors;
CREATE TRIGGER trg_audit_book_authors AFTER INSERT OR UPDATE OR DELETE ON book_authors
    FOR EACH ROW EXECUTE FUNCTION fn_audit('book_id');

-- ---------------------------------------------------------------------
-- 3. TRUNCATE не викликає рядкових тригерів, тому для нього —
--    окремий тригер рівня оператора (FOR EACH STATEMENT).
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_audit_truncate()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO audit_log (table_name, operation, details, changed_by, db_user)
    VALUES (TG_TABLE_NAME, 'TRUNCATE', 'Таблицю повністю очищено',
            COALESCE(NULLIF(current_setting('app.username', TRUE), ''), session_user), session_user);
    RETURN NULL;
END;
$$;

DO $$
DECLARE t TEXT;
BEGIN
    FOREACH t IN ARRAY ARRAY['books','authors','readers','loans','reservations',
                             'reviews','genres','publishers','book_authors'] LOOP
        EXECUTE format('DROP TRIGGER IF EXISTS trg_audit_truncate ON %I', t);
        EXECUTE format('CREATE TRIGGER trg_audit_truncate BEFORE TRUNCATE ON %I
                        FOR EACH STATEMENT EXECUTE FUNCTION fn_audit_truncate()', t);
    END LOOP;
END
$$;

-- ---------------------------------------------------------------------
-- 4. Захист журналу від змін (append-only).
--    Видалення дозволене лише якщо в транзакції встановлено
--    audit.allow_purge = on (так робить процедура обслуговування).
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_audit_protect()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    IF TG_OP = 'DELETE' AND current_setting('audit.allow_purge', TRUE) = 'on' THEN
        RETURN OLD;
    END IF;
    RAISE EXCEPTION 'Журнал аудиту не можна змінювати (операція %)', TG_OP
        USING ERRCODE = 'insufficient_privilege',
              HINT    = 'Старі записи видаляє лише процедура maintain_database()';
END;
$$;

DROP TRIGGER IF EXISTS trg_audit_log_protect ON audit_log;
CREATE TRIGGER trg_audit_log_protect
BEFORE UPDATE OR DELETE ON audit_log
FOR EACH ROW EXECUTE FUNCTION fn_audit_protect();

DROP TRIGGER IF EXISTS trg_audit_log_no_truncate ON audit_log;
CREATE TRIGGER trg_audit_log_no_truncate
BEFORE TRUNCATE ON audit_log
FOR EACH STATEMENT EXECUTE FUNCTION fn_audit_protect();

-- ---------------------------------------------------------------------
-- 5. Історія змін конкретного запису
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION audit_history(p_table TEXT, p_id INTEGER)
RETURNS TABLE (changed_at TIMESTAMP, operation VARCHAR, changed_by VARCHAR,
               field TEXT, old_value TEXT, new_value TEXT)
LANGUAGE sql STABLE AS $$
    SELECT a.changed_at::TIMESTAMP(0), a.operation, a.changed_by,
           f.key, a.old_data ->> f.key, a.new_data ->> f.key
    FROM audit_log a
    CROSS JOIN LATERAL (SELECT jsonb_object_keys(COALESCE(a.new_data, a.old_data)) AS key) f
    WHERE a.table_name = p_table AND a.record_id = p_id
    ORDER BY a.log_id, f.key;
$$;

-- ---------------------------------------------------------------------
-- Перевірка: INSERT, UPDATE, DELETE в одній таблиці
-- ---------------------------------------------------------------------
SET app.username = 'librarian';
INSERT INTO genres (name, description) VALUES ('Комікси', 'Графічні романи та комікси');
UPDATE genres SET description = 'Графічні романи, манга та комікси' WHERE name = 'Комікси';
DELETE FROM genres WHERE name = 'Комікси';
RESET app.username;

-- Останні записи журналу (UPDATE зберігає лише змінене поле)
SELECT log_id, table_name, operation, record_id, changed_by, db_user, tx_id,
       old_data, new_data, changed_at::TIME(0) AS changed_at
FROM audit_log
WHERE table_name = 'genres'
ORDER BY log_id DESC
LIMIT 3;

-- Історія змін конкретного запису
SELECT * FROM audit_history('genres', (SELECT MAX(record_id) FROM audit_log WHERE table_name = 'genres'));

-- Спроба «підчистити» журнал — відхиляється
DO $$
BEGIN
    DELETE FROM audit_log WHERE table_name = 'genres';
EXCEPTION WHEN insufficient_privilege THEN
    RAISE NOTICE 'Відхилено: %', SQLERRM;
END
$$;

-- Статистика журналу за типами операцій
SELECT table_name AS "Таблиця", operation AS "Операція", COUNT(*) AS "Записів"
FROM audit_log
GROUP BY 1, 2
ORDER BY 1, 2;
