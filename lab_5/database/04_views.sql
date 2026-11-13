-- =====================================================================
-- 04_views.sql — представлення для часто використовуваних запитів (рівень 1)
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Популярність книг: видачі за 30 / 90 / 365 днів, рейтинг, відгуки.
-- Використовується для рекомендацій на головній сторінці та закупівель.
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW v_book_popularity AS
SELECT b.book_id,
       b.title,
       g.name                                                               AS genre,
       COUNT(l.loan_id) FILTER (WHERE l.loan_date >= CURRENT_DATE - 30)     AS loans_30d,
       COUNT(l.loan_id) FILTER (WHERE l.loan_date >= CURRENT_DATE - 90)     AS loans_90d,
       COUNT(l.loan_id) FILTER (WHERE l.loan_date >= CURRENT_DATE - 365)    AS loans_365d,
       COUNT(l.loan_id)                                                     AS loans_total,
       r.avg_rating,
       COALESCE(r.reviews_count, 0)                                         AS reviews_count
FROM books b
JOIN genres g ON g.genre_id = b.genre_id
LEFT JOIN loans l ON l.book_id = b.book_id
LEFT JOIN LATERAL (SELECT ROUND(AVG(rating), 2) AS avg_rating, COUNT(*) AS reviews_count
                   FROM reviews rv WHERE rv.book_id = b.book_id) r ON TRUE
GROUP BY b.book_id, b.title, g.name, r.avg_rating, r.reviews_count;

COMMENT ON VIEW v_book_popularity IS 'Популярність книг за різні періоди та їхній рейтинг';

-- ---------------------------------------------------------------------
-- 2. Боржники: читачі з простроченими книгами, згруповано по читачу.
-- Бібліотекар бачить, кому дзвонити, скільки книг і який очікуваний штраф.
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW v_overdue_readers AS
SELECT r.reader_id,
       r.ticket_number,
       r.last_name || ' ' || r.first_name                        AS reader_name,
       r.phone,
       r.email,
       COUNT(*)                                                  AS overdue_books,
       MIN(l.due_date)                                           AS oldest_due_date,
       MAX(CURRENT_DATE - l.due_date)                            AS max_days_overdue,
       SUM(CURRENT_DATE - l.due_date) * 5.00                     AS expected_fine,
       STRING_AGG(b.title, '; ' ORDER BY l.due_date)             AS books
FROM loans l
JOIN readers r ON r.reader_id = l.reader_id
JOIN books   b ON b.book_id   = l.book_id
WHERE l.return_date IS NULL
  AND l.due_date < CURRENT_DATE
GROUP BY r.reader_id;

COMMENT ON VIEW v_overdue_readers IS 'Читачі з простроченими книгами та очікуваним штрафом';

-- ---------------------------------------------------------------------
-- Перевірка роботи представлень
-- ---------------------------------------------------------------------
-- Топ-10 книг за останній рік
SELECT title, genre, loans_30d, loans_90d, loans_365d, avg_rating, reviews_count
FROM v_book_popularity
ORDER BY loans_365d DESC, avg_rating DESC NULLS LAST
LIMIT 10;

-- Найбільші боржники
SELECT ticket_number, reader_name, phone, overdue_books, max_days_overdue, expected_fine
FROM v_overdue_readers
ORDER BY expected_fine DESC
LIMIT 10;

-- Представлення можна фільтрувати, як звичайну таблицю
SELECT COUNT(*) AS "Боржників", SUM(expected_fine) AS "Очікувані штрафи, грн"
FROM v_overdue_readers;
