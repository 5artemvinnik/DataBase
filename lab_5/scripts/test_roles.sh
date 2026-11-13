#!/bin/bash
# Перевірка ієрархії ролей: однакові дії від імені трьох користувачів.
# Запуск з папки lab_5:  bash scripts/test_roles.sh
CONTAINER=${CONTAINER:-library_lab5}
TESTS=$(mktemp)

cat > "$TESTS" <<'SQL'
\pset footer off
SELECT current_user AS "користувач", (SELECT COUNT(*) FROM books) AS "книг";
\echo '--- 1. Додати жанр (каталог)'
INSERT INTO genres (name) VALUES ('Тест ролей ' || current_user);
\echo '--- 2. Прочитати адресу читача (персональні дані)'
SELECT address FROM readers WHERE reader_id = 1;
\echo '--- 3. Прочитати квиток і телефон читача'
SELECT ticket_number, phone FROM readers WHERE reader_id = 1;
\echo '--- 4. Видати книгу читачу 12 (функція issue_book)'
SELECT issue_book(CASE current_user WHEN 'ivan_moder' THEN 13 ELSE 15 END, 12) AS loan_id;
\echo '--- 5. Забронювати книгу для читача 14 (функція reserve_book)'
SELECT reserve_book(CASE current_user WHEN 'olena_reader' THEN 14
                                      WHEN 'ivan_moder'   THEN 17 ELSE 18 END, 14) AS reservation_id;
\echo '--- 6. Переглянути журнал аудиту'
SELECT COUNT(*) AS audit_rows FROM audit_log;
\echo '--- 7. Видалити таблицю'
DROP TABLE notifications;
SQL

podman cp "$TESTS" "$CONTAINER":/tmp/role_tests.sql
rm -f "$TESTS"

run_as() {   # run_as <користувач> <пароль>
    echo "================ $1 ================"
    # -t (псевдотермінал) зберігає правильний порядок результатів і помилок
    podman exec -t -e PGPASSWORD="$2" "$CONTAINER" \
        psql -h localhost -U "$1" -d library -X -q -f /tmp/role_tests.sql 2>&1 \
        | sed 's/^psql:[^:]*:[0-9]*: //' | tr -d '\r'
}

run_as olena_reader 'Olena#Reader1'
run_as ivan_moder   'Ivan#Moder1'
run_as petro_admin  'Petro#Admin1'
