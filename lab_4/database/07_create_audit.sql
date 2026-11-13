-- =====================================================================
-- 07_create_audit.sql — журнал (логування) усіх операцій з даними
-- Зміни даних фіксуються тригерами автоматично. Застосунок передає
-- ім'я поточного користувача через SET LOCAL app.username = '...',
-- а також записує власні події (вхід, вихід, звіти, резервні копії).
-- =====================================================================

DROP TABLE IF EXISTS audit_log CASCADE;

CREATE TABLE audit_log (
    log_id     BIGSERIAL PRIMARY KEY,
    table_name VARCHAR(50),
    operation  VARCHAR(20) NOT NULL,          -- INSERT / UPDATE / DELETE / LOGIN / LOGOUT / REPORT / BACKUP / ...
    record_id  INTEGER,
    old_data   JSONB,
    new_data   JSONB,
    changed_by VARCHAR(50) NOT NULL DEFAULT session_user,
    details    TEXT,
    changed_at TIMESTAMP   NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_audit_changed_at ON audit_log (changed_at DESC);
CREATE INDEX idx_audit_table_op   ON audit_log (table_name, operation);
CREATE INDEX idx_audit_user       ON audit_log (changed_by);

-- ---------------------------------------------------------------------
-- Універсальна тригерна функція аудиту
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_audit()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE
    v_user   VARCHAR(50);
    v_pk     TEXT;
    v_old    JSONB;
    v_new    JSONB;
    v_id     INTEGER;
BEGIN
    -- користувач застосунку (або роль БД, якщо зміну зроблено напряму)
    v_user := COALESCE(NULLIF(current_setting('app.username', TRUE), ''), session_user);
    v_pk   := TG_ARGV[0];                                  -- назва колонки первинного ключа

    IF TG_OP IN ('UPDATE', 'DELETE') THEN v_old := to_jsonb(OLD); END IF;
    IF TG_OP IN ('INSERT', 'UPDATE') THEN v_new := to_jsonb(NEW); END IF;
    -- хеші паролів у журнал не потрапляють
    v_old := v_old - 'password_hash';
    v_new := v_new - 'password_hash';

    -- В UPDATE зберігаємо лише змінені поля
    IF TG_OP = 'UPDATE' THEN
        SELECT jsonb_object_agg(n.key, n.value), jsonb_object_agg(n.key, v_old -> n.key)
        INTO v_new, v_old
        FROM jsonb_each(v_new) n
        WHERE n.value IS DISTINCT FROM v_old -> n.key;
        IF v_new IS NULL THEN RETURN NEW; END IF;          -- фактично нічого не змінилось
    END IF;

    v_id := (COALESCE(to_jsonb(NEW), to_jsonb(OLD)) ->> v_pk)::INTEGER;

    INSERT INTO audit_log (table_name, operation, record_id, old_data, new_data, changed_by)
    VALUES (TG_TABLE_NAME, TG_OP, v_id, v_old, v_new, v_user);

    RETURN COALESCE(NEW, OLD);
END;
$$;

-- Підключаємо аудит до основних таблиць
CREATE TRIGGER trg_audit_books        AFTER INSERT OR UPDATE OR DELETE ON books
    FOR EACH ROW EXECUTE FUNCTION fn_audit('book_id');
CREATE TRIGGER trg_audit_authors      AFTER INSERT OR UPDATE OR DELETE ON authors
    FOR EACH ROW EXECUTE FUNCTION fn_audit('author_id');
CREATE TRIGGER trg_audit_readers      AFTER INSERT OR UPDATE OR DELETE ON readers
    FOR EACH ROW EXECUTE FUNCTION fn_audit('reader_id');
CREATE TRIGGER trg_audit_loans        AFTER INSERT OR UPDATE OR DELETE ON loans
    FOR EACH ROW EXECUTE FUNCTION fn_audit('loan_id');
CREATE TRIGGER trg_audit_reservations AFTER INSERT OR UPDATE OR DELETE ON reservations
    FOR EACH ROW EXECUTE FUNCTION fn_audit('reservation_id');
CREATE TRIGGER trg_audit_genres       AFTER INSERT OR UPDATE OR DELETE ON genres
    FOR EACH ROW EXECUTE FUNCTION fn_audit('genre_id');
CREATE TRIGGER trg_audit_publishers   AFTER INSERT OR UPDATE OR DELETE ON publishers
    FOR EACH ROW EXECUTE FUNCTION fn_audit('publisher_id');
CREATE TRIGGER trg_audit_users        AFTER INSERT OR UPDATE OR DELETE ON app_users
    FOR EACH ROW EXECUTE FUNCTION fn_audit('user_id');

-- Записи журналу бачить лише адміністратор
GRANT ALL PRIVILEGES ON audit_log TO library_admin;
GRANT USAGE ON SEQUENCE audit_log_log_id_seq TO library_admin;
