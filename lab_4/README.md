# Лабораторна робота №4. Електронна бібліотека

Реляційна база даних PostgreSQL з консольним застосунком і вебзастосунком на Flask.
Виконано всі три рівні.

**Виконав:** Віннік Артем, група ІПЗ-31
**Звіт:** [docs/report.md](docs/report.md) · **Логічна схема:** [docs/logical_schema.md](docs/logical_schema.md)

## Можливості

* **База даних.** 11 таблиць у 3НФ з обмеженнями цілісності, 6 збережених функцій і процедур, 4 тригери (та ще 8 тригерів аудиту), 5 представлень, індекси, ролі PostgreSQL.
* **Консольний застосунок** (`console_app/`). CRUD для книг, авторів і читачів, видача та повернення книг через збережені функції, звіти.
* **Вебзастосунок** (`web_app/`):
  * вхід, реєстрація і три ролі (адміністратор, бібліотекар, читач);
  * каталог з пошуком, фільтрами, сортуванням і посторінковим переглядом;
  * CRUD для всіх основних сутностей; видачі, повернення, продовження та бронювання;
  * валідація форм на сервері та в браузері (JavaScript);
  * журнал усіх операцій;
  * звіти у PDF та Excel;
  * діаграми (matplotlib);
  * REST API (`/api/v1`);
  * резервне копіювання та відновлення бази.

## Запуск

### Варіант 1. Усе в Docker (Windows, macOS, Linux)

Потрібен лише **Docker Desktop** (або Docker/Podman у Linux). З папки `lab_4`:

```bash
docker compose up -d --build
```

Перший запуск триває 1–2 хвилини: збирається образ вебзастосунку, створюється база.
Після цього сайт відкривається за адресою **http://localhost:8080**.
Порт 8080 обрано тому, що 5000 у macOS зайнятий службою AirPlay.

```bash
docker exec -it library_web python ../console_app/main.py    # консольний застосунок
docker exec -it library_db psql -U postgres -d library       # консоль psql
docker compose down -v                                       # зупинити й видалити разом із даними
```

### Варіант 2. Вебзастосунок локально, база в контейнері

```bash
docker compose up -d postgres
python -m venv .venv
.venv/bin/pip install -r web_app/requirements.txt         # Windows: .venv\Scripts\pip ...
cd console_app && ../.venv/bin/python main.py              # консольний застосунок
cd web_app && ../.venv/bin/python app.py                   # сайт → http://127.0.0.1:5000
```

Щоб відкрити сайт з телефону в тій самій Wi-Fi мережі, запустіть його з `HOST=0.0.0.0`.

Параметри підключення задаються змінними `DB_HOST`, `DB_PORT`, `DB_NAME`, `DB_USER`, `DB_PASSWORD`.
За замовчуванням це `localhost:5432/library`, користувач `postgres`, пароль `password`.

### Демо-облікові записи

| Логін | Пароль | Роль |
|---|---|---|
| admin | admin123 | Адміністратор |
| librarian | lib12345 | Бібліотекар |
| kovalenko | reader123 | Читач |

### Корисні команди

```bash
python web_app/backup.py                                         # резервна копія з командного рядка
docker exec -i library_db psql -U postgres -d library < web_app/backups/<файл>.sql   # відновлення
```

## Структура

```
lab_4/
├── README.md
├── docker-compose.yml   база (library_db) + вебзастосунок (library_web)
├── Dockerfile           образ вебзастосунку: Python 3.12 + клієнт PostgreSQL 17
├── docs/            conceptual_model.png, logical_schema.md, report.md, screenshots/
├── database/        01_create_tables … 07_create_audit.sql, queries.sql
├── console_app/     main.py, database.py, requirements.txt
└── web_app/         app.py, database.py, auth.py, validators.py, api.py, reports.py,
                     charts.py, backup.py, templates/, static/, requirements.txt
```
