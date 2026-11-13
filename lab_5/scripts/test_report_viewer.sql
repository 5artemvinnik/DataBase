-- Перевірка прав report_viewer: виконується ВІД ІМЕНІ цього користувача
--   psql -U report_viewer -d library -f scripts/test_report_viewer.sql
\set ON_ERROR_STOP off
SELECT current_user AS "Підключено як";

-- Дозволено: читання каталогу та представлень
SELECT COUNT(*) AS "Книг у каталозі" FROM books;
SELECT ticket_number, reader_name, overdue_books, expected_fine
FROM v_overdue_readers ORDER BY expected_fine DESC LIMIT 3;

-- Заборонено: персональні дані читачів
SELECT email, phone FROM readers LIMIT 1;

-- Заборонено: зміна даних
UPDATE books SET price = 0 WHERE book_id = 1;
DELETE FROM genres WHERE genre_id = 1;

-- Заборонено: журнал аудиту та облікові записи
SELECT * FROM app_users LIMIT 1;
