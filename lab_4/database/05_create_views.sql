-- =====================================================================
-- 05_create_views.sql — представлення для спрощення доступу до даних
-- =====================================================================

-- 1. Повний каталог: книга + жанр + видавництво + автори + рейтинг
CREATE OR REPLACE VIEW v_books_catalog AS
SELECT b.book_id,
       b.title,
       b.isbn,
       STRING_AGG(a.first_name || ' ' || a.last_name, ', ' ORDER BY ba.author_order) AS authors,
       g.genre_id,
       g.name  AS genre,
       p.name  AS publisher,
       b.publish_year,
       b.pages,
       b.price,
       b.total_copies,
       b.available_copies,
       (SELECT ROUND(AVG(r.rating), 2) FROM reviews r WHERE r.book_id = b.book_id) AS avg_rating,
       (SELECT COUNT(*) FROM loans l WHERE l.book_id = b.book_id)                  AS times_borrowed
FROM books b
JOIN genres g          ON g.genre_id = b.genre_id
LEFT JOIN publishers p ON p.publisher_id = b.publisher_id
LEFT JOIN book_authors ba ON ba.book_id = b.book_id
LEFT JOIN authors a       ON a.author_id = ba.author_id
GROUP BY b.book_id, g.genre_id, g.name, p.name;

-- 2. Невидані (на руках) книги з кількістю днів прострочення
CREATE OR REPLACE VIEW v_active_loans AS
SELECT l.loan_id,
       l.book_id,
       b.title,
       l.reader_id,
       r.ticket_number,
       r.last_name || ' ' || r.first_name               AS reader_name,
       r.phone,
       l.loan_date,
       l.due_date,
       l.extensions_count,
       GREATEST(CURRENT_DATE - l.due_date, 0)           AS days_overdue,
       GREATEST(CURRENT_DATE - l.due_date, 0) * 5.00    AS expected_fine,
       CASE WHEN l.due_date < CURRENT_DATE THEN 'overdue' ELSE 'active' END AS state
FROM loans l
JOIN books   b ON b.book_id   = l.book_id
JOIN readers r ON r.reader_id = l.reader_id
WHERE l.return_date IS NULL;

-- 3. Статистика по кожному читачу
CREATE OR REPLACE VIEW v_reader_statistics AS
SELECT r.reader_id,
       r.ticket_number,
       r.last_name || ' ' || r.first_name                        AS reader_name,
       r.email,
       r.is_active,
       COUNT(l.loan_id)                                          AS total_loans,
       COUNT(l.loan_id) FILTER (WHERE l.return_date IS NULL)     AS books_on_hand,
       COUNT(l.loan_id) FILTER (WHERE l.return_date IS NULL
                                  AND l.due_date < CURRENT_DATE) AS overdue_now,
       COALESCE(SUM(l.fine_amount), 0)                           AS total_fines,
       MAX(l.loan_date)                                          AS last_visit
FROM readers r
LEFT JOIN loans l ON l.reader_id = r.reader_id
GROUP BY r.reader_id;

-- 4. Статистика за жанрами (для аналітики та діаграм)
CREATE OR REPLACE VIEW v_genre_statistics AS
SELECT g.genre_id,
       g.name AS genre,
       (SELECT COUNT(*) FROM books b WHERE b.genre_id = g.genre_id)                      AS books_count,
       (SELECT COALESCE(SUM(b.total_copies), 0) FROM books b WHERE b.genre_id = g.genre_id) AS copies_count,
       (SELECT COUNT(*) FROM loans l JOIN books b ON b.book_id = l.book_id
         WHERE b.genre_id = g.genre_id)                                                  AS loans_count,
       (SELECT ROUND(AVG(rv.rating), 2) FROM reviews rv JOIN books b ON b.book_id = rv.book_id
         WHERE b.genre_id = g.genre_id)                                                  AS avg_rating
FROM genres g;

-- 5. Кількість видач по місяцях (для графіка динаміки)
CREATE OR REPLACE VIEW v_monthly_loans AS
SELECT DATE_TRUNC('month', loan_date)::DATE AS month,
       COUNT(*)                             AS loans_count,
       COUNT(DISTINCT reader_id)            AS unique_readers,
       SUM(fine_amount)                     AS fines
FROM loans
GROUP BY DATE_TRUNC('month', loan_date)
ORDER BY month;
