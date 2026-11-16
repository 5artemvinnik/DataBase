#!/bin/sh
# Виконує всі кроки лабораторної (database/01…14) по черзі всередині контейнера.
# Запуск з будь-якої ОС:  docker exec library_lab5 sh /lab5/scripts/run_all.sh
set -e
for f in /lab5/database/*.sql; do
    echo ">>> $f"
    psql -U postgres -d library -v ON_ERROR_STOP=1 -q -f "$f" > /dev/null
done
echo "Готово: усі скрипти виконано без помилок."
