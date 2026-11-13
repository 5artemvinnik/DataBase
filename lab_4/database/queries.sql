-- =====================================================================
-- queries.sql — SQL-запити різної складності
-- =====================================================================

-- ---------------------------------------------------------------------
-- РІВЕНЬ 1. Базові запити
-- ---------------------------------------------------------------------

-- Запит 1. Проста фільтрація: доступні книги дешевші за 300 грн
SELECT title, publish_year, price, available_copies
FROM books
WHERE available_copies > 0 AND price < 300
ORDER BY price;

-- Запит 2. JOIN кількох таблиць: книги з авторами, жанром і видавництвом
SELECT b.title,
       a.first_name || ' ' || a.last_name AS author,
       g.name AS genre,
       p.name AS publisher
FROM books b
JOIN book_authors ba ON ba.book_id = b.book_id
JOIN authors a       ON a.author_id = ba.author_id
JOIN genres g        ON g.genre_id = b.genre_id
LEFT JOIN publishers p ON p.publisher_id = b.publisher_id
ORDER BY b.title, ba.author_order;

-- Запит 3. Агрегація: кількість книг та примірників у кожному жанрі
SELECT g.name AS genre,
       COUNT(b.book_id)            AS books,
       COALESCE(SUM(b.total_copies), 0) AS copies,
       ROUND(AVG(b.price), 2)      AS avg_price
FROM genres g
LEFT JOIN books b ON b.genre_id = g.genre_id
GROUP BY g.name
HAVING COUNT(b.book_id) > 0
ORDER BY books DESC, genre;

-- Запит 4. Підзапит: читачі, які брали книг більше за середнє
SELECT r.ticket_number, r.last_name, r.first_name, COUNT(l.loan_id) AS loans
FROM readers r
JOIN loans l ON l.reader_id = r.reader_id
GROUP BY r.reader_id
HAVING COUNT(l.loan_id) > (
    SELECT AVG(cnt) FROM (SELECT COUNT(*) AS cnt FROM loans GROUP BY reader_id) t
)
ORDER BY loans DESC;

-- Запит 5. Підзапит з NOT EXISTS: книги, які жодного разу не видавались
SELECT b.title, b.publish_year
FROM books b
WHERE NOT EXISTS (SELECT 1 FROM loans l WHERE l.book_id = b.book_id)
ORDER BY b.title;

-- Запит 6. Боржники: прострочені видачі зі штрафом, що очікується
SELECT r.last_name || ' ' || r.first_name AS reader, r.phone, b.title,
       l.due_date, CURRENT_DATE - l.due_date AS days_late,
       (CURRENT_DATE - l.due_date) * 5 AS fine_uah
FROM loans l
JOIN readers r ON r.reader_id = l.reader_id
JOIN books b   ON b.book_id   = l.book_id
WHERE l.return_date IS NULL AND l.due_date < CURRENT_DATE
ORDER BY days_late DESC;

-- ---------------------------------------------------------------------
-- РІВЕНЬ 2. Складні аналітичні запити з агрегацією
-- ---------------------------------------------------------------------

-- Аналітика 1. ТОП-5 найпопулярніших книг з рейтингом і місцем (віконні функції)
SELECT RANK() OVER (ORDER BY COUNT(l.loan_id) DESC) AS place,
       b.title,
       COUNT(l.loan_id)                                AS loans,
       ROUND(AVG(rv.rating), 2)                        AS avg_rating,
       ROUND(100.0 * COUNT(l.loan_id) / SUM(COUNT(l.loan_id)) OVER (), 1) AS share_percent
FROM books b
LEFT JOIN loans l ON l.book_id = b.book_id
LEFT JOIN (SELECT book_id, AVG(rating) AS rating FROM reviews GROUP BY book_id) rv
       ON rv.book_id = b.book_id
GROUP BY b.book_id, b.title
ORDER BY loans DESC, b.title
LIMIT 5;

-- Аналітика 2. Динаміка видач по місяцях з накопичувальним підсумком
SELECT TO_CHAR(DATE_TRUNC('month', loan_date), 'YYYY-MM') AS month,
       COUNT(*) AS loans,
       SUM(COUNT(*)) OVER (ORDER BY DATE_TRUNC('month', loan_date)) AS running_total,
       COUNT(*) - LAG(COUNT(*), 1, 0::BIGINT) OVER (ORDER BY DATE_TRUNC('month', loan_date)) AS diff_prev
FROM loans
GROUP BY DATE_TRUNC('month', loan_date)
ORDER BY month;

-- Аналітика 3. Ефективність авторів: видачі, середній рейтинг, дисципліна повернень
SELECT a.last_name || ' ' || a.first_name                      AS author,
       COUNT(DISTINCT b.book_id)                               AS books,
       COUNT(l.loan_id)                                        AS loans,
       COUNT(l.loan_id) FILTER (WHERE l.fine_amount > 0)       AS late_returns,
       COALESCE(SUM(l.fine_amount), 0)                         AS fines_uah
FROM authors a
JOIN book_authors ba ON ba.author_id = a.author_id
JOIN books b         ON b.book_id = ba.book_id
LEFT JOIN loans l    ON l.book_id = b.book_id
GROUP BY a.author_id
ORDER BY loans DESC, author;

-- Аналітика 4. Вікові групи читачів та улюблені жанри (CTE + DISTINCT ON)
WITH reader_genres AS (
    SELECT CASE
             WHEN AGE(r.birth_date) < INTERVAL '25 years' THEN '1) до 25'
             WHEN AGE(r.birth_date) < INTERVAL '35 years' THEN '2) 25-34'
             ELSE '3) 35+'
           END AS age_group,
           g.name AS genre,
           COUNT(*) AS loans
    FROM loans l
    JOIN readers r ON r.reader_id = l.reader_id
    JOIN books b   ON b.book_id = l.book_id
    JOIN genres g  ON g.genre_id = b.genre_id
    GROUP BY 1, 2
)
SELECT DISTINCT ON (age_group) age_group, genre AS favourite_genre, loans,
       (SELECT SUM(loans) FROM reader_genres rg2 WHERE rg2.age_group = rg.age_group) AS total_loans
FROM reader_genres rg
ORDER BY age_group, loans DESC, genre;

-- ---------------------------------------------------------------------
-- Виклик процедур і перегляд представлень
-- ---------------------------------------------------------------------
SELECT * FROM v_active_loans ORDER BY days_overdue DESC;
SELECT * FROM v_reader_statistics ORDER BY total_loans DESC LIMIT 5;
SELECT * FROM get_reader_history(1);

-- ---------------------------------------------------------------------
-- РІВЕНЬ 3. Перевірка використання індексів
-- ---------------------------------------------------------------------
EXPLAIN ANALYZE
SELECT * FROM books WHERE LOWER(title) = LOWER('Кобзар');

EXPLAIN ANALYZE
SELECT * FROM loans WHERE return_date IS NULL AND due_date < CURRENT_DATE;
