-- =====================================================================
-- 06_limited_user.sql — користувач з обмеженими правами (рівень 1)
--
-- report_viewer — аналітик, який будує звіти. Він може лише ЧИТАТИ
-- довідники, каталог і два представлення з кроку 4. Таблиця readers йому
-- недоступна: контакти бачить лише для боржників і лише через представлення
-- v_overdue_readers (представлення як механізм безпеки). Змінювати дані не може.
-- =====================================================================

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'report_viewer') THEN
        CREATE USER report_viewer WITH PASSWORD 'Rep0rt_Viewer!2026'
            CONNECTION LIMIT 3;                 -- не більше 3 одночасних підключень
    END IF;
END
$$;

-- Право підключатися до бази та бачити об'єкти схеми public
GRANT CONNECT ON DATABASE library TO report_viewer;
GRANT USAGE   ON SCHEMA public   TO report_viewer;

-- Лише читання: довідники, каталог і представлення
GRANT SELECT ON genres, publishers, authors, books, book_authors TO report_viewer;
GRANT SELECT ON v_book_popularity, v_overdue_readers           TO report_viewer;

-- Обмеження часу виконання запиту, щоб звіт не «повісив» сервер
ALTER ROLE report_viewer SET statement_timeout = '30s';

-- Перевіряємо права без підключення від імені користувача
SELECT t.obj AS "Об'єкт",
       has_table_privilege('report_viewer', t.obj, 'SELECT') AS "SELECT",
       has_table_privilege('report_viewer', t.obj, 'INSERT') AS "INSERT",
       has_table_privilege('report_viewer', t.obj, 'UPDATE') AS "UPDATE",
       has_table_privilege('report_viewer', t.obj, 'DELETE') AS "DELETE"
FROM unnest(ARRAY['books', 'genres', 'v_book_popularity', 'v_overdue_readers',
                  'readers', 'loans', 'app_users']) AS t(obj);
