#!/bin/sh
# Початкове розгортання: відтворюємо базу з лабораторної роботи 4,
# а потім підключаємо розширення, потрібні для лабораторної 5.
set -e
for f in /lab4/0*.sql; do
    echo ">>> $f"
    psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" -q -f "$f"
done

psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" <<'SQL'
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;   -- найповільніші запити (рівень 3)
CREATE EXTENSION IF NOT EXISTS pg_trgm;              -- триграмні індекси для пошуку за підрядком
SQL
