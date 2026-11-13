# Лабораторна робота №5. Керування БД, оптимізація продуктивності та автоматизація

Тема: «Електронна бібліотека» (база з лабораторної роботи №4). Виконано всі три рівні.

**Виконав:** Віннік Артем, група ІПЗ-31
**Звіт:** [docs/report.md](docs/report.md)

## Що зроблено

| Рівень | Завдання | Файл |
|---|---|---|
| 1 | Генерація 500 000 видач, 50 000 книг і читачів | `database/01_bulk_data.sql` |
| 1 | EXPLAIN ANALYZE трьох запитів до оптимізації | `database/02_performance_before.sql` |
| 1 | 3 індекси (GIN-триграмний, покривний, складений) і повторний аналіз | `database/03_indexes.sql` |
| 1 | 2 представлення | `database/04_views.sql` |
| 1 | Тригер логування вставки та оновлення (історія цін) | `database/05_logging_trigger.sql` |
| 1 | Користувач з обмеженими правами | `database/06_limited_user.sql`, `scripts/test_report_viewer.sql` |
| 2 | Представлення, що оновлюється через правила (RULES) | `database/07_rules_view.sql` |
| 2 | Тригери валідації з обробкою помилок | `database/08_validation_triggers.sql` |
| 2 | Система аудиту audit_log (незмінний журнал) | `database/09_audit_system.sql` |
| 2 | Часткові індекси та аналіз їх ефективності | `database/10_partial_indexes.sql` |
| 2 | Резервне копіювання `pg_dump` і відновлення `pg_restore` | `scripts/backup_restore.sh` |
| 3 | Матеріалізоване представлення з автооновленням тригерами | `database/11_materialized_view.sql` |
| 3 | Каскадні тригери | `database/12_cascade_triggers.sql` |
| 3 | Ієрархія ролей user → moderator → administrator | `database/13_role_hierarchy.sql`, `scripts/test_roles.sh` |
| 3 | Процедура обслуговування `maintain_database()` | `database/14_maintenance.sql`, `scripts/maintenance.sh` |
| 3 | Скрипт моніторингу продуктивності | `monitoring/monitor.py`, `monitoring/monitoring.sql` |

## Запуск

Для лабораторної піднімається **окремий** контейнер `library_lab5` на порту **5433**. Він створюється
SQL-скриптами лабораторної 4 (`../lab_4/database`), тому велике тестове навантаження не зачіпає базу вебзастосунку.

```bash
cd lab_5
python -m venv .venv && .venv/bin/pip install -r requirements.txt

# 1. Сервер PostgreSQL 17 з pg_stat_statements (Docker або Podman)
docker compose up -d            # або: .venv/bin/podman-compose up -d

# 2. Скрипти виконуються по черзі, один раз на чистій базі
for f in database/*.sql; do
    docker exec -i library_lab5 psql -U postgres -d library -v ON_ERROR_STOP=1 < "$f"
done

# 3. Перевірки та утиліти
docker exec -i -e PGPASSWORD='Rep0rt_Viewer!2026' library_lab5 \
    psql -h localhost -U report_viewer -d library < scripts/test_report_viewer.sql
bash scripts/test_roles.sh          # права трьох ролей
bash scripts/backup_restore.sh      # резервна копія і відновлення
bash scripts/maintenance.sh         # VACUUM + CALL maintain_database()
.venv/bin/python monitoring/monitor.py --markdown docs/monitoring_report.md
```

Скрипти в `scripts/` викликають `podman`. Якщо у вас Docker, задайте `alias podman=docker`.
Скинути все до початкового стану можна командою `docker compose down -v`.

### Облікові записи PostgreSQL

| Користувач | Пароль | Роль |
|---|---|---|
| postgres | password | суперкористувач |
| report_viewer | Rep0rt_Viewer!2026 | лише читання каталогу і двох представлень |
| olena_reader | Olena#Reader1 | lib_user |
| ivan_moder | Ivan#Moder1 | lib_moderator |
| petro_admin | Petro#Admin1 | lib_administrator |

## Структура

```
lab_5/
├── docker-compose.yml       PostgreSQL 17, порт 5433, pg_stat_statements
├── init/00_lab4_base.sh     розгортання бази лабораторної 4 + розширення
├── database/01…14_*.sql     кроки лабораторної по порядку
├── scripts/                 backup_restore.sh, maintenance.sh, test_roles.sh, test_report_viewer.sql
├── monitoring/              monitor.py, monitoring.sql, workload.sql (навантаження для pgbench)
└── docs/                    report.md, monitoring_report.md, screenshots/
```
