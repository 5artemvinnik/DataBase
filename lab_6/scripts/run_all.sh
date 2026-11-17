#!/bin/bash
# Виконує всі кроки лабораторної (01…18) по черзі на чистій базі, без виводу.
#   docker exec library_mongo1 bash /lab6/scripts/run_all.sh
# Крок 16 чекає ~1,5 хв, поки спрацює TTL-індекс.
set -e
cd /lab6/scripts
for f in [01]*.js; do
    [ "$f" = 00_init_replica.js ] && continue
    echo ">>> $f"
    bash run.sh "$f" > /dev/null
done
echo "Готово: усі скрипти виконано."
