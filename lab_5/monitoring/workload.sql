-- Імітація навантаження для pgbench: типові запити вебзастосунку бібліотеки
-- з випадковими параметрами. Запуск (з папки lab_5):
--   podman cp monitoring/workload.sql library_lab5:/tmp/workload.sql
--   podman exec library_lab5 pgbench -U postgres -n -c 4 -T 30 -f /tmp/workload.sql library
\set book random(1, 50000)
\set reader random(16, 50015)
\set genre random(1, 10)

-- каталог: пошук за назвою
SELECT book_id, title FROM books WHERE title ILIKE '%маяк. книга ' || :book % 100 || '%' LIMIT 20;
-- сторінка книги
SELECT * FROM v_books_catalog WHERE book_id = :book;
-- кабінет читача
SELECT b.title, rv.rating FROM reviews rv JOIN books b USING (book_id)
WHERE rv.reader_id = :reader ORDER BY rv.created_at DESC;
SELECT * FROM get_reader_history(:reader) LIMIT 10;
-- статистика жанру з матеріалізованого представлення
SELECT month, loans_count FROM mv_genre_monthly_stats WHERE genre_id = :genre ORDER BY month DESC LIMIT 12;
-- важкий звіт без індексу: читачі, зареєстровані в певний день
SELECT COUNT(*) FROM readers WHERE registration_date = CURRENT_DATE - (:reader % 1000);
-- звіт про штрафи
SELECT SUM(fine_amount) FROM loans WHERE return_date >= CURRENT_DATE - 30;
