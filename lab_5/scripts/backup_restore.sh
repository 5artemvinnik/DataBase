#!/bin/bash
# =====================================================================
# Резервне копіювання (pg_dump) та відновлення (pg_restore) — рівень 2
#
#  1. Повна копія у форматі custom (-F c) зі стисненням — основна.
#  2. Копія у вигляді SQL-скрипту (-F p) — читабельна, для psql.
#  3. Копія однієї таблиці (-t).
#  4. Відновлення повної копії в нову базу test_restore і звірка даних.
#  5. Вибіркове відновлення однієї таблиці після «аварії».
#
# Утиліти виконуються всередині контейнера; папка ./backups змонтована
# в контейнер як /backups, тому файли копій лежать поруч із проєктом.
# Запуск з папки lab_5:  bash scripts/backup_restore.sh
# =====================================================================
set -euo pipefail
CONTAINER=${CONTAINER:-library_lab5}
DB=library
STAMP=$(date +%Y%m%d_%H%M)
X="podman exec $CONTAINER"

echo "=== 1. Повна резервна копія (custom format, стиснення 9)"
time $X pg_dump -U postgres -d $DB -F c -Z 9 -f /backups/library_$STAMP.dump

echo "=== 2. Копія у форматі SQL"
$X pg_dump -U postgres -d $DB -F p -f /backups/library_$STAMP.sql

echo "=== 3. Копія однієї таблиці (genres)"
$X pg_dump -U postgres -d $DB -t genres -F p -f /backups/genres_$STAMP.sql

echo "=== Файли резервних копій"
ls -lh backups/ | grep "$STAMP"
echo "Об'єктів у змісті (TOC) повної копії: $($X pg_restore -l /backups/library_$STAMP.dump | grep -vc '^;')"

echo
echo "=== 4. Відновлення в нову базу test_restore"
$X dropdb -U postgres --if-exists test_restore
$X createdb -U postgres test_restore
time $X pg_restore -U postgres -d test_restore --jobs 4 /backups/library_$STAMP.dump

echo "=== Звірка оригіналу та відновленої копії"
COMPARE="
SELECT obj, cnt FROM (VALUES
 (1,  'books',                  (SELECT COUNT(*) FROM books)),
 (2,  'readers',                (SELECT COUNT(*) FROM readers)),
 (3,  'loans',                  (SELECT COUNT(*) FROM loans)),
 (4,  'reviews',                (SELECT COUNT(*) FROM reviews)),
 (5,  'audit_log',              (SELECT COUNT(*) FROM audit_log)),
 (6,  'mv_genre_monthly_stats', (SELECT COUNT(*) FROM mv_genre_monthly_stats)),
 (7,  'функції/процедури',      (SELECT COUNT(*) FROM pg_proc WHERE pronamespace = 'public'::regnamespace)),
 (8,  'тригери',                (SELECT COUNT(*) FROM pg_trigger t JOIN pg_class c ON c.oid = t.tgrelid
                                 WHERE NOT t.tgisinternal AND c.relnamespace = 'public'::regnamespace)),
 (9,  'представлення',          (SELECT COUNT(*) FROM pg_views WHERE schemaname = 'public')),
 (10, 'індекси',                (SELECT COUNT(*) FROM pg_indexes WHERE schemaname = 'public')),
 (11, 'сума штрафів, грн',      (SELECT SUM(fine_amount)::BIGINT FROM loans))
) v(n, obj, cnt) ORDER BY n"
paste -d'|' \
  <($X psql -U postgres -d $DB -X -A -t -F'|' -c "$COMPARE") \
  <($X psql -U postgres -d test_restore -X -A -t -F'|' -c "$COMPARE" | cut -d'|' -f2) \
  | awk -F'|' 'BEGIN { printf "%-24s %12s %12s  %s\n", "Об'"'"'єкт", "library", "test_restore", "Збіг";
                       print "------------------------------------------------------------" }
               { printf "%-24s %12s %12s  %s\n", $1, $2, $3, ($2 == $3 ? "так" : "НІ") }'

echo
echo "=== 5. «Аварія»: у test_restore випадково очистили таблицю notifications"
$X psql -U postgres -d test_restore -X -q -c "TRUNCATE notifications;" \
       -c "SELECT COUNT(*) AS notifications_після_аварії FROM notifications;"
echo "--- Відновлюємо лише дані цієї таблиці з повної копії"
$X pg_restore -U postgres -d test_restore --data-only -t notifications /backups/library_$STAMP.dump
$X psql -U postgres -d test_restore -X -c "SELECT COUNT(*) AS notifications_після_відновлення FROM notifications;"
