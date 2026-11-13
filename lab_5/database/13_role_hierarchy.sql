-- =====================================================================
-- 13_role_hierarchy.sql — ієрархія ролей з детальною системою прав (рівень 3)
--
--   lib_administrator  ── усе: усі таблиці, журнал аудиту, обслуговування БД
--          │ успадковує
--   lib_moderator      ── бібліотекар: каталог, видачі, модерація відгуків,
--          │ успадковує     обмежений доступ до персональних даних читачів
--   lib_user           ── читач: перегляд каталогу, рейтингів, бронювання
--
-- Групові ролі мають NOLOGIN; користувачі (LOGIN) отримують одну з них.
-- Права надаються на рівнях: база -> схема -> таблиця -> СТОВПЕЦЬ -> функція.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 0. Принцип найменших привілеїв: за замовчуванням функції в PostgreSQL
--    може виконувати будь-хто (PUBLIC). Забираємо це право й надаємо явно.
-- ---------------------------------------------------------------------
REVOKE EXECUTE ON ALL FUNCTIONS  IN SCHEMA public FROM PUBLIC;
REVOKE EXECUTE ON ALL PROCEDURES IN SCHEMA public FROM PUBLIC;
REVOKE CREATE ON SCHEMA public FROM PUBLIC;          -- (у PostgreSQL 15+ вже так за замовчуванням)

-- Тригерні функції, що пишуть у службові таблиці (журнал, історія цін,
-- повідомлення, облікові записи), виконуються з правами власника.
-- Так користувачі не отримують прямого права INSERT у audit_log,
-- але їхні дії все одно потрапляють у журнал.
ALTER FUNCTION fn_audit()                     SECURITY DEFINER SET search_path = public;
ALTER FUNCTION fn_audit_truncate()            SECURITY DEFINER SET search_path = public;
ALTER FUNCTION fn_log_book_price()            SECURITY DEFINER SET search_path = public;
ALTER FUNCTION fn_reservations_notify()       SECURITY DEFINER SET search_path = public;
ALTER FUNCTION fn_loans_fine_notify()         SECURITY DEFINER SET search_path = public;
ALTER FUNCTION fn_readers_blocked()           SECURITY DEFINER SET search_path = public;

-- ---------------------------------------------------------------------
-- 1. Групові ролі
-- ---------------------------------------------------------------------
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'lib_user') THEN
        CREATE ROLE lib_user NOLOGIN;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'lib_moderator') THEN
        CREATE ROLE lib_moderator NOLOGIN;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'lib_administrator') THEN
        CREATE ROLE lib_administrator NOLOGIN;
    END IF;
END
$$;

COMMENT ON ROLE lib_user          IS 'Читач: перегляд каталогу та бронювання';
COMMENT ON ROLE lib_moderator     IS 'Бібліотекар: каталог, видачі, модерація відгуків';
COMMENT ON ROLE lib_administrator IS 'Адміністратор: повний доступ, аудит, обслуговування';

-- ---------------------------------------------------------------------
-- 2. lib_user — звичайний користувач
-- ---------------------------------------------------------------------
GRANT CONNECT ON DATABASE library TO lib_user;
GRANT USAGE   ON SCHEMA public   TO lib_user;
GRANT SELECT  ON genres, publishers, authors, books, book_authors, reviews,
                 v_books_catalog, v_book_popularity, mv_genre_monthly_stats TO lib_user;
-- Бронювання — через функцію: користувач не має прав на таблиці reservations,
-- loans, readers, але функція (SECURITY DEFINER) сама перевіряє всі правила
-- й виконується з правами власника. Доступ до даних — лише через «шлюз».
ALTER FUNCTION reserve_book(INTEGER, INTEGER) SECURITY DEFINER SET search_path = public;
GRANT EXECUTE ON FUNCTION reserve_book(INTEGER, INTEGER) TO lib_user;

-- ---------------------------------------------------------------------
-- 3. lib_moderator — успадковує все від lib_user і додає:
-- ---------------------------------------------------------------------
GRANT lib_user TO lib_moderator;

-- керування каталогом
GRANT INSERT, UPDATE, DELETE ON genres, publishers, authors, books, book_authors TO lib_moderator;
-- модерація відгуків: можна змінити текст або видалити, але не створити від імені читача
GRANT UPDATE (comment), DELETE ON reviews TO lib_moderator;
-- читачі: лише потрібні для роботи стовпці (без адреси та дати народження)
GRANT SELECT (reader_id, ticket_number, first_name, last_name, email, phone,
              registration_date, is_active) ON readers TO lib_moderator;
GRANT INSERT (ticket_number, first_name, last_name, email, phone, birth_date, address) ON readers TO lib_moderator;
GRANT UPDATE (phone, email, is_active) ON readers TO lib_moderator;
-- видачі та бронювання
GRANT SELECT, INSERT, UPDATE ON loans, reservations TO lib_moderator;
GRANT SELECT ON v_active_loans, v_overdue_readers, v_reader_statistics, notifications TO lib_moderator;
GRANT EXECUTE ON FUNCTION issue_book(INTEGER, INTEGER, INTEGER),
                          return_book(INTEGER),
                          extend_loan(INTEGER, INTEGER),
                          get_reader_history(INTEGER) TO lib_moderator;
GRANT EXECUTE ON PROCEDURE update_overdue_status() TO lib_moderator;
GRANT USAGE ON ALL SEQUENCES IN SCHEMA public TO lib_moderator;

-- ---------------------------------------------------------------------
-- 4. lib_administrator — успадковує lib_moderator і отримує повний доступ
-- ---------------------------------------------------------------------
GRANT lib_moderator TO lib_administrator;
GRANT ALL PRIVILEGES ON ALL TABLES    IN SCHEMA public TO lib_administrator;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO lib_administrator;
GRANT EXECUTE ON ALL FUNCTIONS  IN SCHEMA public TO lib_administrator;
GRANT EXECUTE ON ALL PROCEDURES IN SCHEMA public TO lib_administrator;
GRANT pg_read_all_stats TO lib_administrator;      -- вбудована роль: статистика для моніторингу

-- Таблиці, створені в майбутньому, автоматично доступні адміністратору
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES    TO lib_administrator;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO lib_administrator;

-- ---------------------------------------------------------------------
-- 5. Користувачі з правом входу
-- ---------------------------------------------------------------------
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'olena_reader') THEN
        CREATE USER olena_reader WITH PASSWORD 'Olena#Reader1' CONNECTION LIMIT 2;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'ivan_moder') THEN
        CREATE USER ivan_moder   WITH PASSWORD 'Ivan#Moder1'   CONNECTION LIMIT 5;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'petro_admin') THEN
        CREATE USER petro_admin  WITH PASSWORD 'Petro#Admin1'  CREATEROLE
            VALID UNTIL '2027-06-30';                  -- обліковий запис з терміном дії
    END IF;
END
$$;

GRANT lib_user          TO olena_reader;
GRANT lib_moderator     TO ivan_moder;
GRANT lib_administrator TO petro_admin;

-- Обмеження ресурсів на рівні ролі
ALTER ROLE olena_reader SET statement_timeout = '5s';
ALTER ROLE ivan_moder   SET statement_timeout = '30s';

-- ---------------------------------------------------------------------
-- 6. Документація прав
-- ---------------------------------------------------------------------
-- Дерево успадкування ролей (рекурсивний запит до pg_auth_members)
WITH RECURSIVE tree AS (
    SELECT r.oid, r.rolname, 0 AS lvl, r.rolname::TEXT AS path
    FROM pg_roles r WHERE r.rolname = 'lib_user'
    UNION ALL
    SELECT m.member, c.rolname, t.lvl + 1, t.path || ' → ' || c.rolname
    FROM tree t
    JOIN pg_auth_members m ON m.roleid = t.oid
    JOIN pg_roles c ON c.oid = m.member
)
SELECT repeat('    ', lvl) || rolname AS "Роль / користувач",
       CASE WHEN (SELECT rolcanlogin FROM pg_roles WHERE oid = tree.oid) THEN 'LOGIN' ELSE 'група' END AS "Тип",
       path AS "Ланцюжок успадкування"
FROM tree ORDER BY path;

-- Матриця прав: S = SELECT, I = INSERT, U = UPDATE, D = DELETE;
-- мала літера + «с» — право лише на окремі стовпці, «-» — немає права.
CREATE OR REPLACE FUNCTION rights_cell(p_role TEXT, p_obj TEXT)
RETURNS TEXT LANGUAGE sql STABLE AS $$
    SELECT string_agg(CASE WHEN has_table_privilege(p_role, p_obj, p)      THEN left(p, 1)
                           WHEN p = 'DELETE'                               THEN '-'   -- DELETE лише для всієї таблиці
                           ELSE CASE WHEN has_any_column_privilege(p_role, p_obj, p)
                                     THEN lower(left(p, 1)) || 'с' ELSE '-' END
                      END, ' ' ORDER BY o)
    FROM unnest(ARRAY['SELECT', 'INSERT', 'UPDATE', 'DELETE']) WITH ORDINALITY AS a(p, o);
$$;

SELECT t.obj                               AS "Об'єкт",
       rights_cell('olena_reader', t.obj)  AS "olena_reader (user)",
       rights_cell('ivan_moder',   t.obj)  AS "ivan_moder (moderator)",
       rights_cell('petro_admin',  t.obj)  AS "petro_admin (admin)"
FROM unnest(ARRAY['books', 'reviews', 'readers', 'loans', 'reservations', 'notifications',
                  'audit_log', 'app_users', 'v_book_popularity', 'mv_genre_monthly_stats']) AS t(obj);

-- Права на виконання функцій
SELECT f.fn AS "Функція",
       has_function_privilege('olena_reader', f.fn, 'EXECUTE') AS "user",
       has_function_privilege('ivan_moder',   f.fn, 'EXECUTE') AS "moderator",
       has_function_privilege('petro_admin',  f.fn, 'EXECUTE') AS "admin"
FROM unnest(ARRAY['reserve_book(integer,integer)', 'issue_book(integer,integer,integer)',
                  'return_book(integer)', 'audit_history(text,integer)']) AS f(fn);
