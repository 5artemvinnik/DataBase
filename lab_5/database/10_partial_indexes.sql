-- =====================================================================
-- 10_partial_indexes.sql — часткові індекси та аналіз їх ефективності (рівень 2)
--
-- Частковий індекс містить лише рядки, що задовольняють умові WHERE.
-- Він менший, швидше оновлюється і краще вміщується в пам'ять, але
-- використовується тільки тоді, коли умова запиту ВИПЛИВАЄ з умови індексу.
-- =====================================================================

-- P1. Черга модерації: найновіші негативні відгуки (оцінка 1–2)
-- P2. Бронювання, що очікують і скоро спливають (для нагадувань)
-- Вимірюємо ДО створення індексів
SELECT measure_query('до', 'P1 Негативні відгуки',
  $q$SELECT review_id, book_id, reader_id, rating, created_at FROM reviews
     WHERE rating <= 2 ORDER BY created_at DESC LIMIT 20$q$) AS "P1 до, мс";

SELECT measure_query('до', 'P2 Бронювання, що спливають',
  $q$SELECT reservation_id, book_id, reader_id, expires_at FROM reservations
     WHERE status = 'pending' AND expires_at < NOW() + INTERVAL '1 day'
     ORDER BY expires_at$q$) AS "P2 до, мс";

-- ---------------------------------------------------------------------
-- Часткові індекси
-- ---------------------------------------------------------------------
-- Лише відгуки з оцінкою 1–2 (≈25% таблиці), упорядковані від найновіших
CREATE INDEX IF NOT EXISTS idx_reviews_negative
    ON reviews (created_at DESC) WHERE rating <= 2;

-- Лише бронювання в статусі pending (≈5% таблиці)
CREATE INDEX IF NOT EXISTS idx_reservations_pending
    ON reservations (expires_at) WHERE status = 'pending';

ANALYZE reviews;
ANALYZE reservations;

-- Плани запитів після створення індексів
EXPLAIN (ANALYZE, BUFFERS)
SELECT review_id, book_id, reader_id, rating, created_at
FROM reviews
WHERE rating <= 2
ORDER BY created_at DESC
LIMIT 20;

EXPLAIN (ANALYZE, BUFFERS)
SELECT reservation_id, book_id, reader_id, expires_at
FROM reservations
WHERE status = 'pending' AND expires_at < NOW() + INTERVAL '1 day'
ORDER BY expires_at;

SELECT measure_query('після', 'P1 Негативні відгуки',
  $q$SELECT review_id, book_id, reader_id, rating, created_at FROM reviews
     WHERE rating <= 2 ORDER BY created_at DESC LIMIT 20$q$) AS "P1 після, мс";

SELECT measure_query('після', 'P2 Бронювання, що спливають',
  $q$SELECT reservation_id, book_id, reader_id, expires_at FROM reservations
     WHERE status = 'pending' AND expires_at < NOW() + INTERVAL '1 day'
     ORDER BY expires_at$q$) AS "P2 після, мс";

SELECT * FROM v_perf_comparison WHERE "Запит" LIKE 'P%';

-- ---------------------------------------------------------------------
-- Аналіз ефективності: розмір часткового індексу проти повного.
-- Для порівняння тимчасово створюємо повні аналоги й одразу їх видаляємо.
-- ---------------------------------------------------------------------
CREATE INDEX tmp_full_reviews_created     ON reviews (created_at DESC);
CREATE INDEX tmp_full_reservations_expire ON reservations (expires_at);

SELECT i.indexrelname                                  AS "Індекс",
       CASE WHEN x.indpred IS NULL THEN 'повний' ELSE 'частковий' END AS "Тип",
       pg_size_pretty(pg_relation_size(i.indexrelid))  AS "Розмір",
       pg_relation_size(i.indexrelid)                  AS "Байт",
       pg_get_expr(x.indpred, x.indrelid)              AS "Умова"
FROM pg_stat_user_indexes i
JOIN pg_index x ON x.indexrelid = i.indexrelid
WHERE i.indexrelname IN ('idx_reviews_negative', 'tmp_full_reviews_created',
                         'idx_reservations_pending', 'tmp_full_reservations_expire',
                         'idx_loans_open')
ORDER BY i.relname, 4;

DROP INDEX tmp_full_reviews_created;
DROP INDEX tmp_full_reservations_expire;

-- ---------------------------------------------------------------------
-- Важливо: частковий індекс НЕ використовується, якщо умова запиту
-- ширша за умову індексу. Оцінка <= 3 не випливає з rating <= 2,
-- тому тут буде Seq Scan і сортування.
-- ---------------------------------------------------------------------
EXPLAIN (COSTS OFF)
SELECT review_id, rating, created_at FROM reviews
WHERE rating <= 3 ORDER BY created_at DESC LIMIT 20;

-- А для вужчої умови (rating = 1) індекс підходить
EXPLAIN (COSTS OFF)
SELECT review_id, rating, created_at FROM reviews
WHERE rating = 1 ORDER BY created_at DESC LIMIT 20;
