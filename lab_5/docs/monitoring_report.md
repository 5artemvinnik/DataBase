# Звіт моніторингу PostgreSQL

Сформовано: 13.11.2026 11:39:46

## 1. Загальний стан

* База **library**, PostgreSQL 17.12, розмір 149 MB, працює 0:03:09
* Підключень: 1 з 100
* Cache hit ratio: **99.97%**
* Транзакцій: 72905 commit / 0 rollback, deadlocks: 0

## 2. Таблиці

| Таблиця | Рядків | Мертвих % | Seq scan | Idx scan | Через індекс % | Розмір |
|---|---|---|---|---|---|---|
| loans | 503031 | 0.0 | 0 | 41652 | 100.0 | 82 MB |
| books | 50022 | 0.0 | 1228 | 155503 | 99.2 | 20 MB |
| reviews | 100015 | 0.0 | 0 | 41604 | 100.0 | 16 MB |
| readers | 50017 | 0.0 | 10401 | 10401 | 50.0 | 13 MB |
| book_authors | 60023 | 0.0 | 0 | 31203 | 100.0 | 5184 kB |
| reservations | 20014 | 0.0 | 0 | 0 | — | 2912 kB |

## 3. Індекси

| Індекс | Таблиця | Сканувань | Прочитано | Розмір |
|---|---|---|---|---|
| books_pkey | books | 146330 | 146330 | 1312 kB |
| authors_pkey | authors | 54027 | 54027 | 64 kB |
| idx_reviews_book | reviews | 31203 | 41392 | 1544 kB |
| genres_pkey | genres | 20802 | 20802 | 16 kB |
| idx_loans_return_date | loans | 20802 | 78017901 | 13 MB |
| idx_book_authors_author | book_authors | 20802 | 20802 | 592 kB |
| publishers_pkey | publishers | 20802 | 20802 | 16 kB |
| idx_loans_book | loans | 10449 | 104738 | 4568 kB |
| idx_loans_reader | loans | 10401 | 104377 | 4576 kB |
| book_authors_pkey | book_authors | 10401 | 12423 | 1960 kB |
| idx_mv_genre_month | mv_genre_monthly_stats | 10401 | 124812 | 40 kB |
| readers_pkey | readers | 10401 | 10401 | 1112 kB |
| idx_reviews_reader_created | reviews | 10401 | 21103 | 3104 kB |
| idx_books_title_trgm | books | 9173 | 250232 | 2480 kB |
| idx_readers_last_name | readers | 0 | 0 | 432 kB |
| idx_loans_open | loans | 0 | 0 | 40 kB |
| idx_loans_loan_date | loans | 0 | 0 | 3552 kB |
| idx_reservations_book | reservations | 0 | 0 | 848 kB |
| app_users_pkey | app_users | 0 | 0 | 16 kB |
| app_users_username_key | app_users | 0 | 0 | 16 kB |
| app_users_reader_id_key | app_users | 0 | 0 | 16 kB |
| idx_app_users_role | app_users | 0 | 0 | 16 kB |
| audit_log_pkey | audit_log | 0 | 0 | 16 kB |
| idx_audit_changed_at | audit_log | 0 | 0 | 16 kB |
| idx_audit_table_op | audit_log | 0 | 0 | 16 kB |
| idx_audit_user | audit_log | 0 | 0 | 16 kB |
| perf_results_pkey | perf_results | 0 | 0 | 16 kB |
| book_price_history_pkey | book_price_history | 0 | 0 | 16 kB |
| idx_price_history_book | book_price_history | 0 | 0 | 16 kB |
| idx_reviews_negative | reviews | 0 | 0 | 456 kB |
| idx_reservations_pending | reservations | 0 | 0 | 40 kB |
| notifications_pkey | notifications | 0 | 0 | 16 kB |
| idx_notifications_unread | notifications | 0 | 0 | 16 kB |
| maintenance_log_pkey | maintenance_log | 0 | 0 | 16 kB |
| genres_name_key | genres | 0 | 0 | 16 kB |
| publishers_name_key | publishers | 0 | 0 | 16 kB |
| books_isbn_key | books | 0 | 0 | 2208 kB |
| readers_ticket_number_key | readers | 0 | 0 | 1552 kB |
| readers_email_key | readers | 0 | 0 | 3480 kB |
| loans_pkey | loans | 0 | 0 | 11 MB |
| reservations_pkey | reservations | 0 | 0 | 456 kB |
| uq_reservation_pending | reservations | 0 | 0 | 48 kB |
| reviews_pkey | reviews | 0 | 0 | 2208 kB |
| uq_review | reviews | 0 | 0 | 2208 kB |
| idx_books_genre | books | 0 | 0 | 384 kB |
| idx_books_publisher | books | 0 | 0 | 384 kB |
| idx_books_title_lower | books | 0 | 0 | 4536 kB |

Невикористаних індексів: **15** `idx_readers_last_name`, `idx_loans_open`, `idx_loans_loan_date`, `idx_reservations_book`, `idx_app_users_role`, `idx_audit_changed_at`, `idx_audit_table_op`, `idx_audit_user`, `idx_price_history_book`, `idx_reviews_negative`, `idx_reservations_pending`, `idx_notifications_unread`, `idx_books_genre`, `idx_books_publisher`, `idx_books_title_lower`

## 4. Найповільніші запити

| Сер., мс | Макс., мс | Викликів | % часу | Запит |
|---|---|---|---|---|
| 2.82 | 5.76 | 10401 | 44.0 | SELECT COUNT(*) FROM readers WHERE registration_date = CURRENT_DATE - ($1 % $2) |
| 2.81 | 33.46 | 10401 | 43.8 | SELECT book_id, title FROM books WHERE title ILIKE $1 \|\| $2 % $3 \|\| $4 LIMIT $5 |
| 0.51 | 1.63 | 10401 | 8.0 | SELECT SUM(fine_amount) FROM loans WHERE return_date >= CURRENT_DATE - $1 |
| 0.11 | 2.64 | 10401 | 1.7 | SELECT * FROM get_reader_history($1) LIMIT $2 |
| 0.07 | 0.77 | 10401 | 1.1 | SELECT * FROM v_books_catalog WHERE book_id = $1 |
| 0.05 | 0.96 | 10401 | 0.8 | SELECT l.loan_id, b.title, l.loan_date, l.due_date, l.return_date, l.status, GREATEST(COA… |

## 5. Рекомендації

* Таблиця readers (50017 рядків): 10401 повних сканувань, лише 50.0% звернень через індекси — знайти запит з Seq Scan і додати індекс
* 15 індексів (10.5 MB) не використовувались з моменту скидання статистики. Кожен сповільнює INSERT/UPDATE; перед видаленням переконатися, що вони не потрібні рідкісним звітам
