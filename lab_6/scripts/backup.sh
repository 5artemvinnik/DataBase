#!/bin/bash
# Крок 19. Автоматизоване резервне копіювання MongoDB (mongodump) з ротацією та перевіркою.
#  1. Повна копія бази library: один стиснений архів (--archive --gzip), читання з вторинного вузла.
#  2. Копія однієї колекції та експорт books у JSON (mongoexport).
#  3. Ротація: зберігаються лише KEEP останніх архівів.
#  4. Перевірка: архів відновлюється в окрему базу library_restore і звіряється з оригіналом.
#
# Запуск вручну з папки lab_6:  bash scripts/backup.sh
# Щодня о 02:30 (crontab -e):    30 2 * * *  cd /шлях/до/lab_6 && bash scripts/backup.sh >> backups/backup.log 2>&1
set -euo pipefail
ENGINE=${ENGINE:-$(command -v podman >/dev/null 2>&1 && echo podman || echo docker)}   # Podman або Docker
CONTAINER=${CONTAINER:-library_mongo1}
KEEP=${KEEP:-7}
STAMP=$(date +%Y%m%d_%H%M%S)
URI="mongodb://mongo1,mongo2,mongo3/?replicaSet=rs0&readPreference=secondaryPreferred"
X="$ENGINE exec $CONTAINER"

echo "[$(date '+%F %T')] Резервне копіювання бази library"
echo "=== 1. Повна копія (архів gzip, читання з вторинного вузла)"
$X mongodump --uri "$URI" --db library --archive=/backups/library_$STAMP.archive.gz --gzip 2>&1 | grep "done dumping" | sed -E 's/.*done dumping `([^`]*)` \((.*)\)/  \1: \2/'

echo "=== 2. Копія колекції books_history і експорт books у JSON"
$X mongodump --uri "$URI" --db library --collection books_history --out /backups/books_history_$STAMP --quiet
$X mongoexport --uri "$URI" --db library --collection books --jsonArray --pretty --out /backups/books_$STAMP.json --quiet

echo "=== 3. Ротація: залишаємо $KEEP останніх повних копій"
ls -1t backups/library_*.archive.gz | tail -n +$((KEEP + 1)) | while read -r old; do echo "  видалено $old"; rm -f "$old"; done
du -sh backups/*"$STAMP"* | awk '{ printf "  %-45s %6s\n", $2, $1 }'

echo "=== 4. Перевірка: відновлення в library_restore і звірка"
$X mongosh --quiet "$URI" --eval 'db.getSiblingDB("library_restore").dropDatabase()' >/dev/null
$X mongorestore --uri "mongodb://mongo1,mongo2,mongo3/?replicaSet=rs0" --archive=/backups/library_$STAMP.archive.gz --gzip \
    --nsFrom 'library.*' --nsTo 'library_restore.*' --drop --quiet
$X mongosh --quiet "mongodb://mongo1,mongo2,mongo3/?replicaSet=rs0" --eval '
  const a = db.getSiblingDB("library"), b = db.getSiblingDB("library_restore");
  const rows = a.getCollectionInfos({ type: "collection" }).map(c => c.name).filter(n => !n.startsWith("system.")).sort().map(n => ({
    collection: n, library: a[n].countDocuments(), restored: b[n].countDocuments(),
    indexes: a[n].getIndexes().length + " / " + b[n].getIndexes().length,
    ok: a[n].countDocuments() === b[n].countDocuments() && a[n].getIndexes().length === b[n].getIndexes().length ? "так" : "НІ" }));
  rows.push({ collection: "views", library: a.getCollectionInfos({ type: "view" }).length, restored: b.getCollectionInfos({ type: "view" }).length });
  console.table(rows);
  print("валідатор books відновлено: " + !!b.getCollectionInfos({ name: "books" })[0].options.validator);'
$X mongosh --quiet "mongodb://mongo1,mongo2,mongo3/?replicaSet=rs0" --eval 'db.getSiblingDB("library_restore").dropDatabase()' >/dev/null
echo "[$(date '+%F %T')] Готово: backups/library_$STAMP.archive.gz"
