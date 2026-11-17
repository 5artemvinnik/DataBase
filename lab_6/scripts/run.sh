#!/bin/bash
# Показ скрипту mongosh «як у консолі»: кожен блок (відокремлений порожнім рядком)
# виводиться з підказкою бази, після чого виконується і друкується його результат.
#   docker exec -it library_mongo1 bash /lab6/scripts/run.sh 04_read.js [блоки] [база]
#   [блоки] — діапазон блоків з кодом, наприклад 1-3 або 4- (за замовчуванням усі).
# Блоки виконуються окремими викликами mongosh, тому кожен блок самодостатній.
FILE=/lab6/scripts/$1
RANGE=${2:-1-}
DB=${3:-library}
FROM=${RANGE%-*}; TO=${RANGE#*-}; TO=${TO:-9999}
n=0
URI="mongodb://mongo1,mongo2,mongo3/$DB?replicaSet=rs0"

awk 'BEGIN { RS = ""; ORS = "\0" } { print }' "$FILE" |
while IFS= read -r -d '' block; do
    code=$(printf '%s\n' "$block" | grep -v '^\s*//')
    if [ -z "$(printf '%s' "$code" | tr -d '[:space:]')" ]; then
        [ "$n" -eq 0 ] && [ "$FROM" -le 1 ] && printf '\e[90m%s\e[0m\n' "$block"   # заголовок скрипту
        continue
    fi
    n=$((n + 1))
    { [ "$n" -lt "$FROM" ] || [ "$n" -gt "$TO" ]; } && continue
    printf '\e[32m%s>\e[0m %s\n' "$DB" "$block"
    mongosh "$URI" --quiet --eval "$block" 2>&1
    echo
done
