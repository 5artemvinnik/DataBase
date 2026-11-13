#!/bin/bash
# =====================================================================
# Регламентне обслуговування бази «Електронна бібліотека» (рівень 3)
#
#   1) VACUUM (ANALYZE) — прибирає «мертві» версії рядків. Усередині
#      процедури його виконати не можна, тому — утилітою vacuumdb;
#   2) CALL maintain_database() — ANALYZE, REINDEX, оновлення MV,
#      прострочені видачі, очищення старого аудиту.
#
# Запуск вручну:   bash scripts/maintenance.sh
# За розкладом (cron, щоночі о 03:00):
#   0 3 * * *  cd /шлях/до/lab_5 && bash scripts/maintenance.sh >> backups/maintenance.log 2>&1
# =====================================================================
set -euo pipefail
CONTAINER=${CONTAINER:-library_lab5}
DB=${DB:-library}

echo "[$(date '+%F %T')] Початок обслуговування бази $DB"

echo "--- vacuumdb: очищення та оновлення статистики"
podman exec "$CONTAINER" vacuumdb -U postgres -d "$DB" --analyze --verbose 2>&1 \
    | grep -E 'INFO:  vacuuming "library\.public\.' | sed 's/^INFO:  /  /' | head -20 || true

echo "--- maintain_database()"
podman exec "$CONTAINER" psql -U postgres -d "$DB" -X -q -c "CALL maintain_database();" 2>&1 \
    | sed 's/^NOTICE:  //'

echo "--- Стан найбільших таблиць після обслуговування"
podman exec "$CONTAINER" psql -U postgres -d "$DB" -X -P footer=off -c "
SELECT relname AS таблиця, n_live_tup AS живих, n_dead_tup AS мертвих,
       last_vacuum::TIMESTAMP(0) AS vacuum, last_analyze::TIMESTAMP(0) AS analyze
FROM pg_stat_user_tables ORDER BY n_live_tup DESC LIMIT 5;"

echo "[$(date '+%F %T')] Обслуговування завершено"
