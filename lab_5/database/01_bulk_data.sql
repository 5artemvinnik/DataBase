-- =====================================================================
-- Лабораторна робота 5. Електронна бібліотека
-- 01_bulk_data.sql — генерація великого обсягу тестових даних
--
-- На таблицях із кількома десятками рядків оптимізатор завжди обирає
-- Seq Scan, тому для аналізу продуктивності база наповнюється:
--   2 000 авторів, 50 000 книг, 50 000 читачів, 500 000 видач,
--   100 000 відгуків, 20 000 бронювань.
-- setseed() робить «випадкові» дані однаковими при кожному запуску.
-- =====================================================================

\timing on
SELECT setseed(0.42);

-- Під час масового завантаження вимикаємо користувацькі тригери
-- (аудит, перевірки видач). Інакше кожен рядок записувався б ще й у
-- audit_log, а завантаження тривало б у десятки разів довше.
-- Цілісність даних гарантує сам генератор.
BEGIN;   -- усе завантаження — одна транзакція: при помилці нічого не збережеться
SET LOCAL session_replication_role = replica;

-- ---------------------------------------------------------------------
-- Довідкові слова для правдоподібних назв та імен
-- ---------------------------------------------------------------------
CREATE TEMP TABLE w_adj  (i SERIAL, w TEXT);
CREATE TEMP TABLE w_noun (i SERIAL, w TEXT);
CREATE TEMP TABLE w_fn   (i SERIAL, w TEXT);
CREATE TEMP TABLE w_ln   (i SERIAL, w TEXT);

INSERT INTO w_adj (w) SELECT unnest(ARRAY[
 'Таємний','Останній','Забутий','Вічний','Тихий','Золотий','Темний','Далекий','Зимовий','Старий',
 'Новий','Чарівний','Холодний','Великий','Незнаний','Срібний','Нічний','Весняний','Втрачений','Дикий']);
INSERT INTO w_noun (w) SELECT unnest(ARRAY[
 'сад','міст','острів','шлях','ліс','вогонь','берег','світ','дім','лист',
 'кобзар','вітер','голос','замок','океан','спогад','код','алгоритм','степ','храм',
 'архів','годинник','маяк','кордон','сон']);
INSERT INTO w_fn (w) SELECT unnest(ARRAY[
 'Олександр','Марія','Іван','Олена','Андрій','Наталія','Дмитро','Ірина','Сергій','Юлія',
 'Максим','Катерина','Богдан','Софія','Тарас','Анна','Василь','Оксана','Роман','Дарина']);
INSERT INTO w_ln (w) SELECT unnest(ARRAY[
 'Коваленко','Шевчук','Бондаренко','Ткаченко','Кравченко','Олійник','Мельник','Савченко',
 'Поліщук','Лисенко','Руденко','Мороз','Гончаренко','Петренко','Кузьменко','Левченко',
 'Марченко','Сидоренко','Павленко','Гуменюк','Остапенко','Зінченко','Литвин','Романюк','Дяченко']);

-- ---------------------------------------------------------------------
-- 1. Автори (2 000)
-- ---------------------------------------------------------------------
INSERT INTO authors (author_id, first_name, last_name, birth_year, country)
SELECT 15 + g,                                          -- явні id: 16 … 2015
       (SELECT w FROM w_fn WHERE i = 1 + (g * 7) % 20),
       (SELECT w FROM w_ln WHERE i = 1 + (g * 13) % 25),
       1900 + (random() * 100)::INT,
       CASE WHEN random() < 0.7 THEN 'Україна' ELSE 'Польща' END
FROM generate_series(1, 2000) g;

-- ---------------------------------------------------------------------
-- 2. Книги (50 000)
-- Назва: «<прикметник> <іменник>. Книга N»; ISBN 979-1xxxxxxxxx
-- ---------------------------------------------------------------------
INSERT INTO books (book_id, title, isbn, genre_id, publisher_id, publish_year, pages,
                   price, total_copies, available_copies, created_at, updated_at)
SELECT 20 + g,                                          -- явні id: 21 … 50020
       a.w || ' ' || n.w || '. Книга ' || g,
       '979-1' || LPAD(g::TEXT, 8, '0') || (g % 10),
       1 + (random() * 9)::INT,
       1 + (random() * 9)::INT,
       1950 + (random() * 75)::INT,
       80 + (random() * 900)::INT,
       ROUND((50 + random() * 950)::NUMERIC, 2),
       c.copies, c.copies,
       NOW() - random() * INTERVAL '1500 days',
       NOW() - random() * INTERVAL '30 days'
FROM generate_series(1, 50000) g
CROSS JOIN LATERAL (SELECT 1 + (random() * 4)::INT AS copies) c
JOIN w_adj  a ON a.i = 1 + (g * 31) % 20
JOIN w_noun n ON n.i = 1 + (g * 17 + g / 25) % 25;

-- Кожній новій книзі — 1 автор, кожній п'ятій — ще й співавтор
INSERT INTO book_authors (book_id, author_id, author_order)
SELECT b.book_id, 16 + (b.book_id * 37) % 2000, 1
FROM books b WHERE b.book_id > 20;
INSERT INTO book_authors (book_id, author_id, author_order)
SELECT b.book_id, 16 + (b.book_id * 53 + 7) % 2000, 2
FROM books b WHERE b.book_id > 20 AND b.book_id % 5 = 0
  AND (b.book_id * 53 + 7) % 2000 <> (b.book_id * 37) % 2000;

-- ---------------------------------------------------------------------
-- 3. Читачі (50 000), квитки LIB-100001 … LIB-150000
-- ---------------------------------------------------------------------
INSERT INTO readers (reader_id, ticket_number, first_name, last_name, email, phone,
                     birth_date, registration_date, is_active)
SELECT 15 + g,                                          -- явні id: 16 … 50015
       'LIB-' || (100000 + g),
       (SELECT w FROM w_fn WHERE i = 1 + (g * 3) % 20),
       (SELECT w FROM w_ln WHERE i = 1 + (g * 11) % 25),
       'reader' || g || '@example.com',
       '+38067' || LPAD((g % 10000000)::TEXT, 7, '0'),
       DATE '1960-01-01' + (random() * 16000)::INT,
       CURRENT_DATE - (random() * 1500)::INT,
       random() > 0.05                                   -- 5% заблокованих
FROM generate_series(1, 50000) g;

-- ---------------------------------------------------------------------
-- 4. Історичні (повернені) видачі (500 000) за останні ~3 роки.
-- Повернення через 3–30 днів, штраф 5 грн за кожен день прострочення.
-- ---------------------------------------------------------------------
INSERT INTO loans (book_id, reader_id, loan_date, due_date, return_date,
                   status, extensions_count, fine_amount)
SELECT book_id, reader_id, d, d + 14, d + ret,
       'returned', 0, GREATEST(ret - 14, 0) * 5.00
FROM (
    SELECT 1 + (random() * 49999)::INT                AS book_id,
           16 + (random() * 49999)::INT               AS reader_id,
           CURRENT_DATE - 31 - (random() * 1065)::INT AS d,
           3 + (random() * 27)::INT                   AS ret
    FROM generate_series(1, 500000)
) s;

-- Відкриті видачі (3 000 різних книг), частина з них прострочена
INSERT INTO loans (book_id, reader_id, loan_date, due_date, status)
SELECT b, 16 + (b * 7919) % 49999, d, d + 14,
       CASE WHEN d + 14 < CURRENT_DATE THEN 'overdue' ELSE 'active' END
FROM (SELECT b, CURRENT_DATE - (random() * 40)::INT AS d
      FROM generate_series(1001, 4000) b) s;

-- Узгоджуємо кількість доступних примірників із відкритими видачами
UPDATE books b
SET available_copies = b.total_copies - o.cnt
FROM (SELECT book_id, COUNT(*) AS cnt FROM loans
      WHERE return_date IS NULL GROUP BY book_id) o
WHERE o.book_id = b.book_id;

-- ---------------------------------------------------------------------
-- 5. Відгуки (100 000) — лише від тих, хто брав книгу
-- ---------------------------------------------------------------------
INSERT INTO reviews (book_id, reader_id, rating, comment, created_at)
SELECT book_id, reader_id,
       (ARRAY[1,2,3,3,4,4,4,5,5,5])[1 + FLOOR(random() * 10)::INT],   -- 20% негативних (1–2)
       CASE WHEN random() < 0.3 THEN 'Автоматично згенерований відгук' END,
       return_date + random() * INTERVAL '10 days'
FROM (SELECT DISTINCT ON (book_id, reader_id) book_id, reader_id, return_date
      FROM loans WHERE return_date IS NOT NULL AND loan_id > 25
      ORDER BY book_id, reader_id) s
WHERE (book_id * 7 + reader_id) % 4 = 0           -- детермінована вибірка ~25% пар
LIMIT 100000
ON CONFLICT ON CONSTRAINT uq_review DO NOTHING;

-- ---------------------------------------------------------------------
-- 6. Бронювання (20 000): переважно виконані, ~5% очікують
-- ---------------------------------------------------------------------
INSERT INTO reservations (book_id, reader_id, reservation_date, expires_at, status)
SELECT 1 + (g * 7) % 50000, 16 + (g * 104729) % 49999, t, t + INTERVAL '3 days',
       CASE WHEN g % 20 = 0 THEN 'pending'
            WHEN g % 7 = 0  THEN 'cancelled'
            WHEN g % 11 = 0 THEN 'expired'
            ELSE 'fulfilled' END
FROM (SELECT g, CASE WHEN g % 20 = 0 THEN NOW() - random() * INTERVAL '2 days'
                     ELSE NOW() - INTERVAL '5 days' - random() * INTERVAL '900 days' END AS t
      FROM generate_series(1, 20000) g) s
ON CONFLICT DO NOTHING;

-- Лічильники SERIAL продовжують нумерацію після явно вставлених id
SELECT setval('authors_author_id_seq', (SELECT MAX(author_id) FROM authors));
SELECT setval('books_book_id_seq',     (SELECT MAX(book_id)   FROM books));
SELECT setval('readers_reader_id_seq', (SELECT MAX(reader_id) FROM readers));

-- У режимі replica не перевіряються й зовнішні ключі (вони теж реалізовані
-- тригерами), тому цілісність перевіряємо вручну ПЕРЕД фіксацією транзакції
DO $$
DECLARE v_bad INTEGER;
BEGIN
    SELECT (SELECT COUNT(*) FROM loans l   WHERE NOT EXISTS (SELECT 1 FROM books b   WHERE b.book_id = l.book_id))
         + (SELECT COUNT(*) FROM loans l   WHERE NOT EXISTS (SELECT 1 FROM readers r WHERE r.reader_id = l.reader_id))
         + (SELECT COUNT(*) FROM reviews v WHERE NOT EXISTS (SELECT 1 FROM books b   WHERE b.book_id = v.book_id))
         + (SELECT COUNT(*) FROM reservations v WHERE NOT EXISTS (SELECT 1 FROM books b WHERE b.book_id = v.book_id))
         + (SELECT COUNT(*) FROM book_authors x WHERE NOT EXISTS (SELECT 1 FROM authors a WHERE a.author_id = x.author_id))
    INTO v_bad;
    IF v_bad > 0 THEN
        RAISE EXCEPTION 'Порушено посилальну цілісність: % рядків без батьківського запису', v_bad;
    END IF;
    RAISE NOTICE 'Посилальна цілісність перевірена: порушень немає';
END
$$;

-- Завершуємо транзакцію; SET LOCAL автоматично повертає звичайний режим тригерів
COMMIT;

-- Оновлюємо статистику оптимізатора після масового завантаження
ANALYZE;

-- Підсумок: кількість рядків і розмір таблиць
SELECT relname                                         AS "Таблиця",
       n_live_tup                                      AS "Рядків",
       pg_size_pretty(pg_total_relation_size(relid))  AS "Розмір з індексами"
FROM pg_stat_user_tables
WHERE relname IN ('authors','books','book_authors','readers','loans','reviews','reservations')
ORDER BY n_live_tup DESC;
