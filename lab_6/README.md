# Лабораторна робота №6. Робота з СУБД MongoDB та реалізація операцій

Тема: «Електронна бібліотека». Виконано всі три рівні.

**Виконав:** Віннік Артем, група ІПЗ-31
**Звіт:** [docs/report.md](docs/report.md) · **Порівняння з PostgreSQL:** [docs/comparison_results.md](docs/comparison_results.md)

## Що зроблено

| Рівень | Завдання | Файл |
|---|---|---|
| 1 | Встановлення MongoDB 8.0 (Docker) і MongoDB Compass | `docker-compose.yml` |
| 1 | База `library`, колекції `books`, `authors`, `users` | `scripts/01_create_collections.js` |
| 1 | По 10 документів з вкладеними документами й масивами | `scripts/02_insert_data.js` |
| 1 | CRUD: вставка, пошук, оновлення, видалення | `scripts/03_insert.js` … `06_delete.js` |
| 1 | Три індекси (простий, складений, унікальний) | `scripts/07_indexes.js` |
| 1 | Порівняння швидкості з індексами і без (200 000 книг) | `scripts/08_index_benchmark.js`, `scripts/lib/bench.js` |
| 2 | Складні запити `$and`, `$or`, `$in`, `$regex` | `scripts/09_complex_queries.js` |
| 2 | Агрегації: підрахунок, середні, групування, `$facet`, `$bucket` | `scripts/10_aggregation.js` |
| 2 | Складені індекси (правило ESR, покривний запит) | `scripts/11_compound_indexes.js` |
| 2 | Текстовий пошук з індексом `text` | `scripts/12_text_search.js` |
| 2 | `$lookup` (аналог JOIN) | `scripts/13_lookup.js` |
| 2 | Представлення (views) | `scripts/14_views.js` |
| 3 | Валідація схеми JSON Schema | `scripts/15_schema_validation.js` |
| 3 | Геопросторові індекси `2dsphere` і TTL-індекс | `scripts/16_geo_ttl.js` |
| 3 | Версіонування документів з історією змін (транзакції) | `scripts/17_versioning.js`, `scripts/lib/versioning.js` |
| 3 | Повнотекстовий пошук з підтримкою української мови | `scripts/18_ukrainian_search.js`, `scripts/lib/uk_search.js` |
| 3 | Реплікація: набір реплік з 3 вузлів, перемикання при аварії | `docker-compose.yml`, `scripts/replication.sh` |
| 3 | Автоматизоване резервне копіювання `mongodump` | `scripts/backup.sh` |
| 3 | Порівняльний аналіз PostgreSQL і MongoDB | `compare/compare.py`, звіт, крок 20 |

## Запуск

Потрібен лише **Docker Desktop** (Windows, macOS) або Docker/Podman (Linux). Команди однакові для PowerShell, cmd і bash.
Виконувати з папки `lab_6`:

```bash
# 1. Набір реплік MongoDB з трьох вузлів і PostgreSQL для порівняння (перший запуск ~30 с)
docker compose up -d

# 2. Кожен скрипт показується «як у консолі»: блок коду, потім результат
docker exec -it library_mongo1 bash /lab6/scripts/run.sh 04_read.js
docker exec -it library_mongo1 bash /lab6/scripts/run.sh 04_read.js 2-3   # лише блоки 2–3

# Усі кроки 01…18 по черзі на чистій базі (крок 16 чекає ~1,5 хв на TTL)
docker exec library_mongo1 bash /lab6/scripts/run_all.sh

# 3. Консоль mongosh
docker exec -it library_mongo1 mongosh library
```

Скрипти виконуються по черзі на чистій базі: деякі кроки спираються на результати попередніх
(наприклад, валідація рівня 3 вимагає ISBN, а тимчасові книги кроку 5.4 його не мають).

Реплікація, резервне копіювання і порівняння запускаються з хоста. Скрипти `.sh` написані для bash
(на Windows — Git Bash або WSL) і самі визначають, що встановлено: Docker чи Podman.

```bash
bash scripts/replication.sh        # стан набору реплік, failover і повернення вузла
bash scripts/backup.sh             # mongodump + ротація + перевірне відновлення

python -m venv .venv
.venv/bin/pip install -r requirements.txt          # Windows: .venv\Scripts\pip ...
.venv/bin/python compare/compare.py                # Windows: .venv\Scripts\python ...
```

**MongoDB Compass:** підключення `mongodb://localhost:27017/?directConnection=true`.

Скинути все до початкового стану: `docker compose down -v`.

## Структура

```
lab_6/
├── docker-compose.yml       mongo1, mongo2, mongo3 (набір реплік rs0) + PostgreSQL 17 (порт 5434)
├── scripts/
│   ├── 00_init_replica.js   ініціалізація rs0 (виконує healthcheck контейнера mongo1)
│   ├── 01…18_*.js           кроки лабораторної по порядку
│   ├── lib/                 bench.js, versioning.js, uk_search.js
│   ├── run.sh, run_all.sh   показ і виконання скриптів
│   ├── replication.sh       демонстрація реплікації
│   └── backup.sh            резервне копіювання з ротацією і перевіркою
├── compare/compare.py       порівняльний аналіз PostgreSQL / MongoDB
└── docs/                    report.md, comparison_results.md, screenshots/
```
