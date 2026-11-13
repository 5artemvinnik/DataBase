# Звіт з лабораторної роботи №4. Розробка реляційної бази даних з простою інтеграцією

## Загальна інформація

- **ПІБ студента:** Віннік Артем
- **Група:** ІПЗ-31
- **Варіант (предметна область):** Електронна бібліотека
- **Рівень виконання:** 3 (усі вимоги рівнів 1, 2 і 3)
- **Програмне забезпечення:** PostgreSQL 17 (контейнер `postgres:17-alpine`, Podman 6.1 + podman-compose), Python 3.15, psycopg2, Flask 3.1, openpyxl, reportlab, matplotlib

## Мета роботи

Здобути практичні навички повного циклу розробки реляційної бази даних: аналіз предметної області, проєктування нормалізованої структури, реалізація в PostgreSQL та інтеграція з консольним і вебзастосунком.

---

## Опис предметної області

Інформаційна система автоматизує роботу бібліотеки.

**Фонд бібліотеки.** Бібліотека зберігає книги, кожна в кількох примірниках. Книга належить до одного жанру, може мати видавництво і одного або кількох авторів. Автор може написати багато книг. Для кожної книги відомі ISBN, рік видання, кількість сторінок, ціна та кількість примірників: загальна і доступна зараз.

**Читачі.** Читач реєструється в бібліотеці й отримує квиток у форматі `LIB-0001`.

**Видачі.** Бібліотекар видає читачу книгу на певний термін, 14 днів за замовчуванням. Діють такі правила:

* читач може мати на руках не більше **5 книг**;
* читач із **простроченими** книгами не може отримати нову;
* заблокованому читачу книги не видаються;
* термін можна **продовжити** не більше 2 разів по 7 днів, якщо книгу не чекають інші читачі;
* за кожен день прострочення нараховується **штраф 5 грн**.

**Бронювання та відгуки.** Читач може забронювати книгу на 3 дні. Заброньовані примірники не видаються іншим читачам. Також читач може залишити відгук з оцінкою від 1 до 5.

**Ролі в системі:**

* **адміністратор** — керує користувачами, переглядає журнал операцій, робить резервні копії;
* **бібліотекар** — працює з фондом, читачами, видачами та звітами;
* **читач** — переглядає каталог, свої видачі та бронювання.

Усі зміни даних автоматично записуються в журнал аудиту.

---

## Рівень 1

### Крок 0. Налаштування Docker (Podman)

Docker на робочій машині не встановлений, тому використано **Podman**, сумісний з Docker. Файл `docker-compose.yml` запускається утилітою `podman-compose` без змін, а з `docker compose` теж працюватиме.

```yaml
services:
  postgres:
    image: docker.io/library/postgres:17-alpine
    container_name: library_db
    environment:
      POSTGRES_DB: library
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: password
      TZ: Europe/Kyiv
      PGTZ: Europe/Kyiv
    ports:
      - "5432:5432"
    volumes:
      - postgres_data:/var/lib/postgresql/data
      - ./database:/docker-entrypoint-initdb.d:ro,Z
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U postgres -d library"]
      interval: 5s
    restart: unless-stopped

volumes:
  postgres_data:
```

Як працює ця конфігурація:

* Каталог `database/` змонтовано в `/docker-entrypoint-initdb.d`, тому під час першого запуску контейнер сам виконує всі SQL-скрипти в алфавітному порядку: `01_…` → `07_…` → `queries.sql`.
* Прапорець `Z` потрібен для SELinux у Fedora.
* `healthcheck` повідомляє, коли сервер готовий приймати з'єднання.

```bash
podman --version
.venv/bin/podman-compose up -d
podman ps
podman logs library_db | grep docker-entrypoint
```

**Результат:**

![Запуск контейнера PostgreSQL](screenshots/sql_01_docker.png)

Контейнер `library_db` має статус `healthy`. У журналі видно, що всі 8 скриптів ініціалізації виконані без помилок.

---

### Крок 1. Аналіз предметної області та вибір теми

Обрано тему **«Електронна бібліотека»** зі списку. Виділено основні сутності:

* **Жанр** та **Видавництво** — довідники;
* **Автор**, **Книга**, **Читач**;
* **Видача**, **Бронювання**, **Відгук**.

Для рівня 3 додано ще дві сутності: **Користувач** (обліковий запис застосунку) та **Журнал операцій**.

---

### Крок 2. Концептуальна модель (ER-діаграма)

ER-діаграма містить **10 пов'язаних сутностей**, що більше за мінімальні 5. Окремо від них існує журнал аудиту. Діаграму побудовано в нотації Crow's Foot («воронячі лапки»): біля кожного зв'язку видно кардинальність (1 або N) і обов'язковість участі. Вихідний код діаграми (Mermaid) лежить у файлі [conceptual_model.mmd](conceptual_model.mmd).

![ER-діаграма](conceptual_model.png)

Основні зв'язки:

| Зв'язок | Тип |
|---|---|
| Жанр → Книга | 1 : N |
| Видавництво → Книга | 1 : N, необов'язковий |
| Книга ↔ Автор | **M : N** через `book_authors` |
| Читач → Видача ← Книга | 1 : N та N : 1 |
| Читач → Бронювання ← Книга | 1 : N та N : 1 |
| Читач → Відгук ← Книга | 1 : N та N : 1 |
| Читач — Користувач | 1 : 1, необов'язковий |

---

### Крок 3. Логічне проєктування (3НФ)

Повний опис таблиць, ключів і зв'язків наведено в [logical_schema.md](logical_schema.md). Коротко про відповідність нормальним формам:

* **1НФ.** Усі значення атомарні. Наприклад, кілька авторів книги зберігаються окремими рядками таблиці `book_authors`, а не списком в одному полі.
* **2НФ.** У таблиці зі складеним ключем `book_authors (book_id, author_id)` атрибут `author_order` залежить від усього ключа.
* **3НФ.** Транзитивних залежностей немає. Назва жанру, дані видавництва та контакти читача зберігаються лише у своїх таблицях, а в інших таблицях на них посилаються зовнішні ключі.
* **Свідома денормалізація.** Поле `books.available_copies` дозволяє швидко перевірити наявність книги. Його узгодженість з видачами гарантує тригер.

---

### Крок 4. Реалізація бази даних у PostgreSQL

Скрипт `database/01_create_tables.sql` створює 9 основних таблиць з такими обмеженнями цілісності:

* `PRIMARY KEY`, `FOREIGN KEY` з різними політиками `ON DELETE` (`RESTRICT`, `CASCADE`, `SET NULL`);
* `UNIQUE`, `NOT NULL`, `DEFAULT`;
* `CHECK`, зокрема з регулярними виразами для ISBN, email, телефону та номера квитка;
* міжстовпцеві обмеження: `available_copies <= total_copies`, `death_year >= birth_year`, `due_date > loan_date`, «повернена видача обов'язково має дату повернення».

Фрагмент для таблиць `books` і `loans`:

```sql
CREATE TABLE books (
    book_id          SERIAL PRIMARY KEY,
    title            VARCHAR(200) NOT NULL,
    isbn             VARCHAR(17)  NOT NULL UNIQUE
                     CHECK (isbn ~ '^(97[89]-?)?[0-9-]{9,13}[0-9X]$'),
    genre_id         INTEGER NOT NULL REFERENCES genres(genre_id)
                     ON UPDATE CASCADE ON DELETE RESTRICT,
    publisher_id     INTEGER REFERENCES publishers(publisher_id)
                     ON UPDATE CASCADE ON DELETE SET NULL,
    publish_year     INTEGER CHECK (publish_year BETWEEN 1450 AND 2026),
    pages            INTEGER CHECK (pages > 0),
    language         VARCHAR(30)  NOT NULL DEFAULT 'українська',
    price            NUMERIC(8,2) NOT NULL DEFAULT 0 CHECK (price >= 0),
    total_copies     INTEGER NOT NULL DEFAULT 1 CHECK (total_copies >= 0),
    available_copies INTEGER NOT NULL DEFAULT 1 CHECK (available_copies >= 0),
    description      TEXT,
    created_at       TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at       TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT chk_copies CHECK (available_copies <= total_copies)
);

CREATE TABLE book_authors (
    book_id      INTEGER NOT NULL REFERENCES books(book_id)   ON DELETE CASCADE,
    author_id    INTEGER NOT NULL REFERENCES authors(author_id) ON DELETE CASCADE,
    author_order SMALLINT NOT NULL DEFAULT 1 CHECK (author_order > 0),
    PRIMARY KEY (book_id, author_id)
);

CREATE TABLE loans (
    loan_id          SERIAL PRIMARY KEY,
    book_id          INTEGER NOT NULL REFERENCES books(book_id)    ON DELETE RESTRICT,
    reader_id        INTEGER NOT NULL REFERENCES readers(reader_id) ON DELETE RESTRICT,
    loan_date        DATE NOT NULL DEFAULT CURRENT_DATE,
    due_date         DATE NOT NULL,
    return_date      DATE,
    status           VARCHAR(10) NOT NULL DEFAULT 'active'
                     CHECK (status IN ('active', 'returned', 'overdue', 'lost')),
    extensions_count SMALLINT NOT NULL DEFAULT 0 CHECK (extensions_count BETWEEN 0 AND 2),
    fine_amount      NUMERIC(8,2) NOT NULL DEFAULT 0 CHECK (fine_amount >= 0),
    CONSTRAINT chk_due_date    CHECK (due_date > loan_date),
    CONSTRAINT chk_return_date CHECK (return_date IS NULL OR return_date >= loan_date),
    CONSTRAINT chk_returned    CHECK (status <> 'returned' OR return_date IS NOT NULL)
);
```

Перелік таблиць і представлень у базі:

```bash
podman exec library_db psql -U postgres -d library -c '\dt'
podman exec library_db psql -U postgres -d library -c '\dv'
```

**Результат:**

![Таблиці та представлення](screenshots/sql_02_tables.png)

Структура таблиці `books` з індексами, обмеженнями, зовнішніми ключами і тригерами:

![Структура таблиці books](screenshots/sql_03_books_struct.png)

Структура таблиці `loans`:

![Структура таблиці loans](screenshots/sql_04_loans_struct.png)

---

### Крок 5. Наповнення тестовими даними

Скрипт `database/02_insert_data.sql` наповнює таблиці реалістичними даними: українська та світова література, справжні видавництва, читачі з Волинської області.

**Дати відносні.** Дати видач задаються відносно `CURRENT_DATE`, наприклад `CURRENT_DATE - 25`. Тому серед видач завжди є повернені, активні й прострочені, незалежно від дня запуску.

**Узгодження примірників.** Наприкінці скрипта кількість доступних примірників перераховується за активними видачами:

```sql
UPDATE books b
SET available_copies = b.total_copies - (
    SELECT COUNT(*) FROM loans l
    WHERE l.book_id = b.book_id AND l.return_date IS NULL
);
```

**Результат:**

![Кількість записів у таблицях](screenshots/sql_05_counts.png)

У кожній таблиці щонайменше 10 записів:

| Таблиця | Записів |
|---|---|
| genres, publishers | 10 |
| authors, readers | 15 |
| books | 20 |
| book_authors | 23 |
| loans | 25 |
| reservations | 10 |
| reviews | 15 |
| app_users | 13 |

---

### Крок 6. SQL-запити різної складності

Усі запити зібрано у файлі `database/queries.sql`. Для знімків кожен запит вирізається з файлу командою `sed` і виконується в `psql` з ключем `-a`, тож на екрані видно і текст запиту, і результат.

#### Запит 1. Проста фільтрація

Доступні книги дешевші за 300 грн, відсортовані за ціною.

```sql
SELECT title, publish_year, price, available_copies
FROM books
WHERE available_copies > 0 AND price < 300
ORDER BY price;
```

**Результат:**

![Запит 1](screenshots/sql_10_query.png)

#### Запит 2. З'єднання чотирьох таблиць (JOIN)

Книги з авторами, жанром і видавництвом. `LEFT JOIN` з видавництвами зберігає книги без видавництва.

```sql
SELECT b.title, a.first_name || ' ' || a.last_name AS author,
       g.name AS genre, p.name AS publisher
FROM books b
JOIN book_authors ba ON ba.book_id = b.book_id
JOIN authors a       ON a.author_id = ba.author_id
JOIN genres g        ON g.genre_id = b.genre_id
LEFT JOIN publishers p ON p.publisher_id = b.publisher_id
ORDER BY b.title, ba.author_order;
```

**Результат:**

![Запит 2](screenshots/sql_11_query.png)

«Антологія українського модернізму» має чотирьох авторів. Так виглядає зв'язок M:N на практиці.

#### Запит 3. Агрегація (GROUP BY, HAVING)

Кількість книг і примірників та середня ціна в кожному жанрі.

```sql
SELECT g.name AS genre, COUNT(b.book_id) AS books,
       COALESCE(SUM(b.total_copies), 0) AS copies, ROUND(AVG(b.price), 2) AS avg_price
FROM genres g LEFT JOIN books b ON b.genre_id = g.genre_id
GROUP BY g.name
HAVING COUNT(b.book_id) > 0
ORDER BY books DESC, genre;
```

**Результат:**

![Запит 3](screenshots/sql_12_query.png)

#### Запит 4. Підзапит у HAVING

Читачі, які брали книг більше, ніж у середньому брав один читач.

```sql
SELECT r.ticket_number, r.last_name, r.first_name, COUNT(l.loan_id) AS loans
FROM readers r JOIN loans l ON l.reader_id = r.reader_id
GROUP BY r.reader_id
HAVING COUNT(l.loan_id) > (
    SELECT AVG(cnt) FROM (SELECT COUNT(*) AS cnt FROM loans GROUP BY reader_id) t
)
ORDER BY loans DESC;
```

**Результат:**

![Запит 4](screenshots/sql_13_query.png)

#### Запит 5. Корельований підзапит NOT EXISTS

Книги, які жодного разу не видавались.

```sql
SELECT b.title, b.publish_year
FROM books b
WHERE NOT EXISTS (SELECT 1 FROM loans l WHERE l.book_id = b.book_id)
ORDER BY b.title;
```

**Результат:**

![Запит 5](screenshots/sql_14_query.png)

#### Запит 6. Боржники

Прострочені видачі з кількістю днів прострочення та штрафом, що очікується.

```sql
SELECT r.last_name || ' ' || r.first_name AS reader, r.phone, b.title,
       l.due_date, CURRENT_DATE - l.due_date AS days_late,
       (CURRENT_DATE - l.due_date) * 5 AS fine_uah
FROM loans l
JOIN readers r ON r.reader_id = l.reader_id
JOIN books b   ON b.book_id   = l.book_id
WHERE l.return_date IS NULL AND l.due_date < CURRENT_DATE
ORDER BY days_late DESC;
```

**Результат:**

![Запит 6](screenshots/sql_15_query.png)

---

### Крок 7. Консольний застосунок (Python + psycopg2)

Консольний застосунок складається з двох модулів:

* **`console_app/database.py`** — клас `Database`, який інкапсулює роботу з базою:
  * з'єднання через `psycopg2.connect()` з параметрами зі змінних середовища;
  * кожен запит виконується в окремій транзакції `with self.conn:`, тобто COMMIT при успіху і ROLLBACK при помилці;
  * усі значення передаються **параметрами** `%s` / `%(name)s`, що унеможливлює SQL-ін'єкції;
  * перед кожним запитом виконується `set_config('app.username', 'console', true)`, тож журнал аудиту знає, хто зробив зміну;
  * помилки СУБД, зокрема з `RAISE EXCEPTION`, перетворюються на зрозумілі повідомлення `DatabaseError`.
* **`console_app/main.py`** — меню з підменю для книг, авторів, читачів, видач і звітів:
  * кожне поле введення перевіряється (тип, діапазон, регулярний вираз), при помилці значення запитується знову;
  * помилка бази даних не закриває застосунок: користувач повертається в те саме меню.

```python
def _run(self, sql, params, fetch):
    try:
        with self.conn:                                   # COMMIT або ROLLBACK автоматично
            with self.conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
                cur.execute("SELECT set_config('app.username', %s, true)", (self.app_user,))
                cur.execute(sql, params)
                ...
    except psycopg2.Error as exc:
        message = exc.diag.message_primary if exc.diag and exc.diag.message_primary else str(exc)
        raise DatabaseError(message) from exc
```

#### Підключення до БД та головне меню

![Запуск застосунку](screenshots/console_c01_start.png)

#### Read: список книг (представлення `v_books_catalog`)

![Список книг](screenshots/console_c02_list.png)

#### Read: пошук за назвою або автором

![Пошук](screenshots/console_c03_search.png)

#### Create: додавання книги з перевіркою введення

Невірний ISBN і нечислову ціну відхилено, після чого книгу додано разом з двома авторами. Вставка книги та її авторів виконується одним запитом:

```sql
WITH new_book AS (
    INSERT INTO books (...) VALUES (...) RETURNING book_id
)
INSERT INTO book_authors (book_id, author_id, author_order)
SELECT new_book.book_id, a.id, a.ord
FROM new_book, UNNEST(%(authors)s::int[]) WITH ORDINALITY AS a(id, ord)
```

![Додавання книги](screenshots/console_c04_add.png)

#### Update: редагування книги

Якщо натиснути Enter, поле зберігає поточне значення. Після оновлення тригер змінив `updated_at`, а доступні примірники перераховано автоматично.

![Редагування книги](screenshots/console_c05_edit.png)

#### Delete: видалення книги

Нову книгу видалено. Книгу «Кобзар» видалити не можна, бо в неї є історія видач (`ON DELETE RESTRICT`).

![Видалення книги](screenshots/console_c06_delete.png)

#### CRUD для авторів і читачів

![Додавання автора](screenshots/console_c07_authors.png)

![Реєстрація читача з перевіркою email](screenshots/console_c08_reader_add.png)

Видалення читача працює так:

* якщо в читача є історія видач, застосунок виконує «м'яке видалення»: блокує квиток;
* якщо в читача є неповернені книги, видалення заборонене.

![Видалення читача](screenshots/console_c09_reader_del.png)

#### Видача та повернення книг через збережені функції

Нижче видно три дії:

1. Читач №9 має прострочену книгу, тому функція `issue_book` відмовила у видачі.
2. Читачу №10 книгу видано на 21 день.
3. Наприкінці виведено книги, які зараз на руках.

![Видача книги](screenshots/console_c10_issue.png)

Повернення прострочених книг: нараховано штраф 30 грн. Також продемонстровано продовження терміну і спробу повернути книгу вдруге.

![Повернення та продовження](screenshots/console_c11_return.png)

#### Звіти

![Звіти](screenshots/console_c12_reports.png)

![Історія читача](screenshots/console_c13_history.png)

---

## Рівень 2

### Крок 8. Збережені процедури та функції

Файл `database/03_create_procedures.sql` містить 6 об'єктів:

| Назва | Тип | Призначення |
|---|---|---|
| `issue_book(book, reader, days)` | FUNCTION → INTEGER | видача книги з перевіркою всіх правил |
| `return_book(loan)` | FUNCTION → NUMERIC | повернення книги та розрахунок штрафу |
| `extend_loan(loan, days)` | FUNCTION → DATE | продовження терміну видачі |
| `reserve_book(book, reader)` | FUNCTION → INTEGER | бронювання книги |
| `update_overdue_status()` | PROCEDURE (`CALL`) | позначає прострочені видачі та закриває протерміновані бронювання |
| `get_reader_history(reader)` | FUNCTION → TABLE | історія видач читача зі штрафами |

Помилки обробляються через `RAISE EXCEPTION` з текстом українською. Для конкурентного доступу рядок книги блокується `SELECT … FOR UPDATE`, щоб два бібліотекарі одночасно не видали останній примірник.

```sql
CREATE OR REPLACE FUNCTION issue_book(p_book_id INTEGER, p_reader_id INTEGER, p_days INTEGER DEFAULT 14)
RETURNS INTEGER LANGUAGE plpgsql AS $$
DECLARE
    v_available INTEGER; v_reader_active BOOLEAN; v_open_loans INTEGER;
    v_overdue INTEGER; v_foreign_reserv INTEGER; v_loan_id INTEGER;
BEGIN
    IF p_days NOT BETWEEN 1 AND 60 THEN
        RAISE EXCEPTION 'Термін видачі має бути від 1 до 60 днів (отримано %)', p_days;
    END IF;

    SELECT available_copies INTO v_available FROM books WHERE book_id = p_book_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Книгу з ID % не знайдено', p_book_id; END IF;

    SELECT is_active INTO v_reader_active FROM readers WHERE reader_id = p_reader_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Читача з ID % не знайдено', p_reader_id;
    ELSIF NOT v_reader_active THEN RAISE EXCEPTION 'Читацький квиток читача % заблоковано', p_reader_id;
    END IF;

    SELECT COUNT(*) FILTER (WHERE return_date IS NULL),
           COUNT(*) FILTER (WHERE return_date IS NULL AND due_date < CURRENT_DATE)
    INTO v_open_loans, v_overdue FROM loans WHERE reader_id = p_reader_id;

    IF v_overdue > 0 THEN
        RAISE EXCEPTION 'Читач має % прострочених книг — спочатку їх треба повернути', v_overdue;
    END IF;
    IF v_open_loans >= 5 THEN
        RAISE EXCEPTION 'Перевищено ліміт: читач уже має % книг на руках (максимум 5)', v_open_loans;
    END IF;

    SELECT COUNT(*) INTO v_foreign_reserv FROM reservations
    WHERE book_id = p_book_id AND status = 'pending'
      AND reader_id <> p_reader_id AND expires_at > CURRENT_TIMESTAMP;
    IF v_available - v_foreign_reserv <= 0 THEN
        RAISE EXCEPTION 'Немає вільних примірників книги (доступно %, заброньовано іншими %)',
            v_available, v_foreign_reserv;
    END IF;

    INSERT INTO loans (book_id, reader_id, loan_date, due_date)
    VALUES (p_book_id, p_reader_id, CURRENT_DATE, CURRENT_DATE + p_days)
    RETURNING loan_id INTO v_loan_id;

    UPDATE reservations SET status = 'fulfilled'
    WHERE book_id = p_book_id AND reader_id = p_reader_id AND status = 'pending';
    RETURN v_loan_id;
END;
$$;
```

Список функцій і тригерів у базі:

![Функції та тригери](screenshots/sql_20_functions.png)

#### Демонстрація `issue_book`

Після видачі доступних примірників «Лісової пісні» стало менше на 1: 3 → 2. Це зробив тригер. Три наступні виклики завершились контрольованими помилками:

* у читача є прострочена книга;
* квиток заблоковано;
* книги не існує.

![issue_book](screenshots/sql_21_issue.png)

#### Демонстрація `return_book` та `extend_loan`

* Повернення книги з простроченням 11 днів нарахувало штраф **55 грн**.
* Видачу продовжено двічі, а третю спробу заблоковано, бо максимум — 2 продовження.
* Повторне повернення тієї самої книги відхилено.

![return_book та extend_loan](screenshots/sql_22_return.png)

#### Процедура `update_overdue_status` та функція `get_reader_history`

![Представлення, процедура та функція](screenshots/sql_25_views2.png)

---

### Крок 9. Тригери

Файл `database/04_create_triggers.sql` містить чотири тригери:

| Тригер | Подія | Що робить |
|---|---|---|
| `trg_loans_sync_availability` | AFTER INSERT / UPDATE OF return_date / DELETE ON loans | змінює `books.available_copies` (−1 при видачі, +1 при поверненні) |
| `trg_loans_validate` | BEFORE INSERT ON loans | ставить термін за замовчуванням (14 днів) і забороняє видачу заблокованому читачу або коли немає примірників |
| `trg_books_updated_at` | BEFORE UPDATE ON books | оновлює `updated_at` |
| `trg_books_adjust_copies` | BEFORE UPDATE OF total_copies ON books | при зміні кількості примірників перераховує доступні; не дає встановити менше, ніж зараз видано |

```sql
CREATE OR REPLACE FUNCTION fn_adjust_copies() RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE v_on_hand INTEGER;
BEGIN
    IF NEW.total_copies <> OLD.total_copies THEN
        v_on_hand := OLD.total_copies - OLD.available_copies;
        IF NEW.total_copies < v_on_hand THEN
            RAISE EXCEPTION 'Не можна встановити % примірників: % зараз видано читачам',
                NEW.total_copies, v_on_hand;
        END IF;
        NEW.available_copies := NEW.total_copies - v_on_hand;
    END IF;
    RETURN NEW;
END;
$$;
```

**Результат:**

![Робота тригерів](screenshots/sql_23_triggers.png)

На знімку видно три спрацювання:

1. Кількість примірників «1984» змінено з 6 на 8. Тригер сам перерахував доступні примірники й оновив `updated_at`.
2. Спробу встановити 0 примірників відхилено, бо одна книга зараз на руках.
3. Прямий `INSERT` видачі заблокованому читачу зупинив тригер `trg_loans_validate`.

---

### Крок 10. Представлення

Файл `database/05_create_views.sql` містить 5 представлень:

| Представлення | Призначення |
|---|---|
| `v_books_catalog` | повний каталог: автори через `STRING_AGG`, жанр, видавництво, рейтинг, кількість видач |
| `v_active_loans` | книги на руках: дні прострочення, штраф, що очікується, стан |
| `v_reader_statistics` | статистика читача: усього видач, на руках, прострочено, штрафи |
| `v_genre_statistics` | аналітика за жанрами (для діаграм і звітів) |
| `v_monthly_loans` | кількість видач по місяцях (для графіка динаміки) |

```sql
CREATE OR REPLACE VIEW v_active_loans AS
SELECT l.loan_id, l.book_id, b.title, l.reader_id, r.ticket_number,
       r.last_name || ' ' || r.first_name            AS reader_name, r.phone,
       l.loan_date, l.due_date, l.extensions_count,
       GREATEST(CURRENT_DATE - l.due_date, 0)        AS days_overdue,
       GREATEST(CURRENT_DATE - l.due_date, 0) * 5.00 AS expected_fine,
       CASE WHEN l.due_date < CURRENT_DATE THEN 'overdue' ELSE 'active' END AS state
FROM loans l
JOIN books   b ON b.book_id   = l.book_id
JOIN readers r ON r.reader_id = l.reader_id
WHERE l.return_date IS NULL;
```

**Результат:**

![Представлення v_active_loans та v_reader_statistics](screenshots/sql_24_views.png)

Представлення використовуються і в консольному, і у вебзастосунку, тож складні JOIN не дублюються в коді Python.

---

### Крок 11. Складні аналітичні запити з агрегацією

#### Аналітика 1. ТОП-5 книг: віконні функції `RANK()` і частка від загальної кількості

```sql
SELECT RANK() OVER (ORDER BY COUNT(l.loan_id) DESC) AS place, b.title,
       COUNT(l.loan_id) AS loans, ROUND(AVG(rv.rating), 2) AS avg_rating,
       ROUND(100.0 * COUNT(l.loan_id) / SUM(COUNT(l.loan_id)) OVER (), 1) AS share_percent
FROM books b
LEFT JOIN loans l ON l.book_id = b.book_id
LEFT JOIN (SELECT book_id, AVG(rating) AS rating FROM reviews GROUP BY book_id) rv ON rv.book_id = b.book_id
GROUP BY b.book_id, b.title
ORDER BY loans DESC, b.title LIMIT 5;
```

![Аналітика 1](screenshots/sql_16_query.png)

#### Аналітика 2. Динаміка видач по місяцях: накопичувальний підсумок і різниця з попереднім місяцем (`LAG`)

```sql
SELECT TO_CHAR(DATE_TRUNC('month', loan_date), 'YYYY-MM') AS month, COUNT(*) AS loans,
       SUM(COUNT(*)) OVER (ORDER BY DATE_TRUNC('month', loan_date)) AS running_total,
       COUNT(*) - LAG(COUNT(*), 1, 0::BIGINT) OVER (ORDER BY DATE_TRUNC('month', loan_date)) AS diff_prev
FROM loans GROUP BY DATE_TRUNC('month', loan_date) ORDER BY month;
```

![Аналітика 2](screenshots/sql_17_query.png)

#### Аналітика 3. Автори: кількість видач, повернення із запізненням, штрафи (`COUNT … FILTER`)

```sql
SELECT a.last_name || ' ' || a.first_name AS author,
       COUNT(DISTINCT b.book_id) AS books, COUNT(l.loan_id) AS loans,
       COUNT(l.loan_id) FILTER (WHERE l.fine_amount > 0) AS late_returns,
       COALESCE(SUM(l.fine_amount), 0) AS fines_uah
FROM authors a
JOIN book_authors ba ON ba.author_id = a.author_id
JOIN books b ON b.book_id = ba.book_id
LEFT JOIN loans l ON l.book_id = b.book_id
GROUP BY a.author_id ORDER BY loans DESC, author;
```

![Аналітика 3](screenshots/sql_18_query.png)

#### Аналітика 4. Улюблений жанр кожної вікової групи (`CTE` + `DISTINCT ON`)

![Аналітика 4](screenshots/sql_19_query.png)

---

### Крок 12. Вебзастосунок (Flask)

Структура `web_app/`:

| Модуль | Призначення |
|---|---|
| `app.py` | маршрути: головна, каталог, книги, автори, читачі, видачі, бронювання, статистика, адміністрування |
| `database.py` | пул з'єднань `ThreadedConnectionPool`, транзакції, перетворення помилок СУБД на зрозумілі повідомлення |
| `auth.py` | вхід, вихід, реєстрація, декоратори `login_required` і `roles_required` |
| `validators.py` | серверна валідація форм |
| `api.py`, `reports.py`, `charts.py`, `backup.py` | функціональність рівня 3 |
| `templates/`, `static/` | 22 HTML-шаблони Jinja2 (з макросами), CSS, JavaScript |

Захист від CSRF зроблено так: кожна POST-форма містить токен із сесії, а запит без правильного токена отримує відповідь 400.

#### Головна сторінка (бібліотекар)

![Головна](screenshots/web_04_dashboard.png)

#### Каталог (Read)

![Каталог](screenshots/web_05_catalog.png)

#### Картка книги: історія видач і відгуки

![Картка книги](screenshots/web_08_book_detail.png)

#### Create: форма нової книги

Автори вибираються зі списку з множинним вибором. Тригер сам встановлює доступні примірники.

![Форма книги](screenshots/web_10_book_form_filled.png)

![Книгу створено](screenshots/web_11_book_created.png)

#### Автори та читачі

![Автори](screenshots/web_12_authors.png)

![Читачі](screenshots/web_13_readers.png)

Фільтр «лише боржники»:

![Боржники](screenshots/web_14_readers_debtors.png)

![Картка читача](screenshots/web_15_reader_detail.png)

#### Видачі (Update: повернення, продовження) та бронювання

![Видачі](screenshots/web_16_loans.png)

Помилки з функції `issue_book` показуються у вебінтерфейсі. Нижче — спроба видати книгу заблокованому читачу:

![Помилка видачі](screenshots/web_17_loan_error.png)

![Успішна видача](screenshots/web_18_loan_ok.png)

![Бронювання](screenshots/web_19_reservations.png)

#### Валідація на стороні сервера

Цей знімок зроблено з **вимкненим JavaScript**, тому дані дійшли до сервера без перевірки в браузері. Модуль `validators.py` повернув помилки по кожному полю.

![Серверна валідація](screenshots/web_22_server_validation.png)

Унікальність email перевіряє вже сама база даних. Помилку `UniqueViolation` перехоплено й показано біля поля:

![Дублікат email](screenshots/web_23_server_validation_email.png)

---

## Рівень 3

### Крок 13. Аутентифікація та ролі

Як це влаштовано:

* **Зберігання паролів.** Таблиця `app_users` зберігає лише хеші паролів PBKDF2-SHA256 (`werkzeug.security`).
* **Реєстрація.** Вона створює читача і його обліковий запис **в одній транзакції**.
* **Сесія.** Після входу в сесії зберігаються роль і `reader_id`.
* **Захист від підбору пароля.** Після 5 невдалих спроб вхід блокується.
* **Права доступу.** Декоратор `roles_required("admin", "librarian")` повертає 403 для інших ролей.
* **Ролі в СУБД.** Додатково створено ролі PostgreSQL `library_reader`, `library_librarian`, `library_admin` з різними правами `GRANT` (`06_create_users.sql`).

```python
def roles_required(*roles):
    def decorator(view):
        @wraps(view)
        @login_required
        def wrapper(*args, **kwargs):
            if session.get("role") not in roles:
                abort(403)
            return view(*args, **kwargs)
        return wrapper
    return decorator
```

![Сторінка входу](screenshots/web_01_login.png)

![Невдалий вхід](screenshots/web_02_login_fail.png)

Користувачі (хеші паролів обрізано) та ролі PostgreSQL:

![Користувачі та ролі БД](screenshots/sql_29_roles.png)

Що бачить **читач**:

* у меню лише каталог, автори та «Мій кабінет»;
* може бронювати книги та залишати відгуки;
* сторінки бібліотекаря для нього недоступні.

![Головна читача](screenshots/web_24_reader_home.png)

![Бронювання читачем](screenshots/web_25_reader_reserve.png)

![Відгук](screenshots/web_26_reader_review.png)

![Кабінет читача](screenshots/web_27_reader_cabinet.png)

![403 для читача](screenshots/web_28_reader_forbidden.png)

**Адміністратор** змінює ролі користувачів і блокує їх:

![Керування користувачами](screenshots/web_29_admin_users.png)

### Крок 14. Логування всіх операцій

Логування працює на двох рівнях.

**1. У базі даних.** Універсальна тригерна функція `fn_audit()` (`07_create_audit.sql`) підключена до 8 таблиць. Вона записує в `audit_log`:

* тип операції;
* ID запису;
* старі та нові значення у форматі JSONB (для UPDATE — **лише змінені поля**);
* користувача.

Ім'я користувача застосунок передає через `SET LOCAL`-змінну `app.username`, тому журнал показує не «postgres», а реального користувача. Хеші паролів у журнал не потрапляють.

**2. У застосунку.** Окремо записуються події, яких немає в таблицях: `LOGIN`, `LOGIN_FAIL`, `LOGOUT`, `REPORT`, `BACKUP`, `RESTORE`. Крім того, усі POST-запити пишуться у файл `logs/app.log` (`RotatingFileHandler`).

```sql
v_user := COALESCE(NULLIF(current_setting('app.username', TRUE), ''), session_user);
...
IF TG_OP = 'UPDATE' THEN            -- зберігаємо лише змінені поля
    SELECT jsonb_object_agg(n.key, n.value), jsonb_object_agg(n.key, v_old -> n.key)
    INTO v_new, v_old
    FROM jsonb_each(v_new) n
    WHERE n.value IS DISTINCT FROM v_old -> n.key;
END IF;
INSERT INTO audit_log (table_name, operation, record_id, old_data, new_data, changed_by)
VALUES (TG_TABLE_NAME, TG_OP, v_id, v_old, v_new, v_user);
```

![Журнал у psql](screenshots/sql_26_audit.png)

Сторінка журналу у вебзастосунку: фільтри за таблицею, операцією та користувачем, посторінковий перегляд.

![Журнал операцій](screenshots/web_31_admin_logs.png)

![Фільтр: лише входи в систему](screenshots/web_32_admin_logs_login.png)

### Крок 15. Звіти у PDF та Excel

Модуль `reports.py` формує 4 звіти: каталог, боржники, статистика читачів, аналітика за жанрами.

* **Excel** (`openpyxl`): оформлений заголовок, закріплений рядок заголовків, автофільтр, ширина колонок під вміст, друк в альбомній орієнтації на ширину сторінки.
* **PDF** (`reportlab`): вбудовано шрифт Liberation Sans з підтримкою кирилиці, рядки таблиці мають чергування кольорів, ширина колонок пропорційна вмісту.

Генерація кожного звіту записується в журнал.

![Сторінка звітів](screenshots/web_21_reports.png)

![PDF-звіт](screenshots/web_33_pdf_catalog.png)

![Excel-звіт](screenshots/web_34_excel_catalog.png)

### Крок 16. Пошук із фільтрацією та сортуванням

У каталозі можна шукати за назвою, автором або ISBN і фільтрувати за жанром, роками та наявністю. Сортування доступне за 6 полями в обох напрямках: через форму або натисканням на заголовок колонки. Каталог розбито на сторінки по 10 книг. Пошук читачів і видач також має фільтри: боржники, заблоковані, статус видачі.

Захист від SQL-ін'єкцій:

* значення фільтрів передаються параметрами;
* поле сортування вибирається зі **«білого списку»** `BOOK_SORTS`, бо назву колонки не можна передати параметром.

```python
BOOK_SORTS = {"title": "title", "year": "publish_year", "price": "price", "rating": "avg_rating",
              "popular": "times_borrowed", "available": "available_copies"}
order_sql = f"{BOOK_SORTS.get(sort, 'title')} {order} NULLS LAST, title"   # лише з білого списку
```

Фільтр: сучасна проза, видана з 2005 року, лише доступні, сортування за рейтингом у спадному порядку.

![Фільтрація](screenshots/web_06_catalog_filter.png)

Друга сторінка, сортування за популярністю:

![Пагінація](screenshots/web_07_catalog_page2.png)

### Крок 17. Графічна візуалізація

Модуль `charts.py` будує 4 діаграми за допомогою matplotlib і віддає їх як PNG:

* динаміка видач по місяцях;
* популярність жанрів;
* ТОП книг із рейтингом;
* структура видач (кільцева діаграма).

Поруч на сторінці виведено таблиці аналітичних запитів.

![Статистика](screenshots/web_20_stats.png)

### Крок 18. API для інтеграції з іншими системами

REST API працює з префіксом `/api/v1` і повертає JSON (`api.py`).

* **Аутентифікація** — HTTP Basic.
* **Права:** читати дані можуть усі ролі, змінювати — лише бібліотекар і адміністратор.
* **Валідація:** API використовує ті самі функції, що й вебформи.
* **Коди помилок:** `401` (не автентифіковано), `403` (немає прав), `404` (не знайдено), `409` (конфлікт з обмеженнями БД), `422` (помилки валідації).

| Метод | Адреса | Дія |
|---|---|---|
| GET | `/api/v1/books?q=&genre=&available=1&limit=&offset=` | пошук у каталозі |
| GET | `/api/v1/books/<id>` | картка книги |
| POST / PUT / DELETE | `/api/v1/books[/<id>]` | створити, оновити, видалити книгу |
| GET | `/api/v1/genres`, `/readers`, `/loans/active`, `/stats` | довідники та статистика |
| POST | `/api/v1/loans`, `/api/v1/loans/<id>/return` | видача та повернення (через збережені функції) |

![API: пошук і статистика](screenshots/cli_api1.png)

![API: створення книги, валідація, 403](screenshots/cli_api2.png)

![API: видача та повернення](screenshots/cli_api3.png)

### Крок 19. Резервне копіювання

Модуль `backup.py` робить повну копію бази через `pg_dump --clean --if-exists`. Якщо утиліти `pg_dump` на комп'ютері немає, команда автоматично виконується всередині контейнера через `docker exec` або `podman exec`.

Відновлення з копії виконує `psql`. Перевірено так: після видалення відгуків і відновлення з копії дані повернулися, а функції й тригери продовжили працювати.

Резервну копію можна створити двома способами:

* з командного рядка;
* у розділі адміністратора, де копію також можна завантажити, відновити або видалити.

![Резервна копія з командного рядка](screenshots/cli_backup.png)

![Резервні копії у вебзастосунку](screenshots/web_30_admin_backup.png)

### Крок 20. Валідація на стороні клієнта (JavaScript)

Файл `static/js/validation.js` перевіряє форми, позначені атрибутом `data-validate`. Правила задаються атрибутами полів:

* `required`;
* `data-pattern` — регулярний вираз;
* `data-min` / `data-max` — діапазон чисел;
* `data-match` — збіг паролів;
* `data-after` — рік смерті не раніше року народження;
* `data-past` — дата не в майбутньому;
* `data-min-selected` — мінімум вибраних авторів.

Помилки показуються біля поля одразу після виходу з нього і при спробі надіслати форму. Під полем пароля є індикатор надійності. Небезпечні дії (видалення, відновлення бази) потребують підтвердження.

![Реєстрація: помилки JavaScript](screenshots/web_03_register_js.png)

![Форма книги: помилки JavaScript](screenshots/web_09_book_form_js.png)

### Крок 21. Оптимізація: індекси

Створено 11 індексів для типових запитів, а також 3 індекси для журналу. Серед них:

* функціональний індекс `LOWER(title)` для пошуку без урахування регістру;
* **частковий** індекс `idx_loans_open (due_date) WHERE return_date IS NULL`. Він містить лише невидані книги, тому малий і швидкий для пошуку боржників.

![Індекси](screenshots/sql_27_explain.png)

Перевірка планів виконання через `EXPLAIN ANALYZE`. У таблицях лише десятки рядків, і на таких обсягах планувальник обирає послідовне сканування як дешевше. Тому для демонстрації його вимкнено командою `SET enable_seqscan = off`. Плани показують, що запити використовують `idx_books_title_lower` та частковий `idx_loans_open`.

![EXPLAIN ANALYZE](screenshots/sql_28_explain2.png)

Інші заходи оптимізації:

* пул з'єднань у вебзастосунку;
* посторінковий вивід (`LIMIT`/`OFFSET`);
* агрегати рахуються в СУБД, а не в Python;
* представлення замість повторюваних JOIN.

---

## Висновки

У ході лабораторної роботи пройдено повний цикл розробки інформаційної системи «Електронна бібліотека».

**Проєктування.** Проаналізовано предметну область, побудовано ER-діаграму з 10 пов'язаними сутностями та логічну схему у третій нормальній формі. Зв'язок M:N між книгами й авторами реалізовано через проміжну таблицю.

**Реалізація в PostgreSQL.** База розгорнута в контейнері PostgreSQL 17 через `docker-compose.yml`, а SQL-скрипти виконуються автоматично при першому запуску. Цілісність даних забезпечують первинні та зовнішні ключі з різними політиками `ON DELETE`, обмеження `UNIQUE`, `NOT NULL`, `CHECK` (зокрема з регулярними виразами та міжстовпцевими умовами) і частковий унікальний індекс.

**Бізнес-логіка в базі.** Правила бібліотеки (ліміт книг, заборона видачі боржникам, штрафи, продовження, бронювання) реалізовано у збережених функціях з обробкою помилок і блокуванням рядків. Тригери підтримують узгодженість кількості примірників. Представлення спрощують доступ до даних. Написано прості, з'єднувальні, агрегатні запити та запити з підзапитами, а також аналітичні запити з віконними функціями, `FILTER`, CTE і `DISTINCT ON`.

**Застосунки:**

* консольний застосунок на Python (psycopg2) з CRUD-операціями та параметризованими запитами;
* вебзастосунок на Flask з вебінтерфейсом, двосторонньою валідацією та CSRF-захистом;
* три ролі користувачів, журнал аудиту на тригерах з JSONB, звіти PDF та Excel, діаграми, REST API, резервне копіювання і відновлення, індекси, перевірені через `EXPLAIN ANALYZE`.

**Труднощі та їх розв'язання:**

* Docker на системі відсутній, тому використано сумісний Podman. Для SELinux у Fedora до тому зі скриптами довелося додати прапорець `:Z`.
* `current_user` у PostgreSQL є зарезервованим словом, тому змінну сесії для аудиту названо `app.username`.
* Для кирилиці в PDF довелося вбудувати TTF-шрифт, бо стандартні шрифти reportlab не містять українських літер.
* На маленьких таблицях планувальник ігнорує індекси, тому для демонстрації планів з індексами вимкнено послідовне сканування.

---

## Контрольні запитання

1. **Етапи розробки БД.**
   * Аналіз вимог — що зберігати і які операції потрібні.
   * Концептуальне проєктування — ER-модель, незалежна від СУБД.
   * Логічне проєктування — таблиці, ключі, нормалізація.
   * Фізичне проєктування — типи даних, індекси, обмеження конкретної СУБД.
   * Реалізація і наповнення даними.
   * Тестування, експлуатація та супровід.
2. **Концептуальна, логічна, фізична моделі.**
   * Концептуальна описує сутності й зв'язки предметної області.
   * Логічна — це відношення (таблиці), атрибути, первинні та зовнішні ключі без прив'язки до СУБД.
   * Фізична — це DDL конкретної СУБД: типи (`VARCHAR(200)`, `NUMERIC(8,2)`), індекси, табличні простори, тригери.
3. **Нормалізація.** Це процес усунення надлишковості та аномалій вставки, оновлення й видалення через декомпозицію таблиць. Вимоги нормальних форм:
   * 1НФ — значення атомарні;
   * 2НФ — 1НФ і немає часткових залежностей від складеного ключа;
   * 3НФ — 2НФ і жоден неключовий атрибут не залежить транзитивно від ключа через інший неключовий атрибут.
4. **Обмеження цілісності.**
   * Сутнісна цілісність — `PRIMARY KEY`.
   * Посилальна — `FOREIGN KEY` з діями `ON DELETE`/`ON UPDATE`.
   * Доменна — типи, `NOT NULL`, `CHECK`, `DEFAULT`.
   * Унікальність — `UNIQUE`.
   * Складніші бізнес-правила — тригери.

   Разом вони не дають записати в базу некоректні або суперечливі дані.
5. **PK і FK.** Первинний ключ однозначно ідентифікує рядок, він унікальний і не NULL (наприклад, `books.book_id`). Зовнішній ключ посилається на PK іншої таблиці й задає зв'язок (`loans.book_id → books.book_id`). FK може повторюватися і, якщо дозволено, бути NULL (`books.publisher_id`).
6. **Типи зв'язків.**
   * 1:1 — FK з `UNIQUE` (`app_users.reader_id`).
   * 1:N — FK у таблиці на боці «багато» (`books.genre_id`).
   * M:N — проміжна таблиця з двома FK (`book_authors`).
7. **Збережена процедура.** Це програмний код, який зберігається і виконується на сервері БД. Переваги:
   * бізнес-логіка в одному місці для всіх застосунків;
   * менше обмінів даними з клієнтом;
   * атомарність разом із транзакцією;
   * повторне використання планів;
   * можна дати право на виконання процедури без прямого доступу до таблиць.
8. **Тригери.** Тригер — код, що автоматично виконується при INSERT, UPDATE або DELETE. Застосування: аудит змін (`fn_audit`), підтримка похідних значень (`available_copies`), складні перевірки (`trg_loans_validate`), автоматичні мітки часу (`updated_at`).
9. **JOIN.**
   * `INNER JOIN` — лише рядки, для яких є відповідність.
   * `LEFT JOIN` — усі рядки лівої таблиці (наприклад, книги без видавництва).
   * `RIGHT JOIN` — усі рядки правої таблиці.
   * `FULL JOIN` — усі рядки обох таблиць.
   * `CROSS JOIN` — декартів добуток.
   * `SELF JOIN` — з'єднання таблиці з собою.
10. **VIEW.** Це збережений запит, до якого звертаються як до таблиці. Доцільний, щоб приховати складні JOIN (`v_books_catalog`), обмежити доступ до колонок, повторно використовувати аналітику і давати стабільний інтерфейс для застосунків.
11. **Захист від SQL-ін'єкцій.**
    * Значення передаються параметрами (`cur.execute(sql, params)`), а не через конкатенацію рядків.
    * Ідентифікатори (наприклад, поле сортування) вибираються з «білого списку».
    * Дані перевіряються на сервері.
    * Застосунок працює під обліковим записом з мінімальними правами.
12. **ORM чи «чистий» SQL.**
    * Переваги ORM: менше шаблонного коду, незалежність від СУБД, робота з об'єктами, міграції.
    * Недоліки ORM: прихований і часом неефективний SQL (проблема N+1), складно використовувати специфічні можливості СУБД (віконні функції, процедури, JSONB).
    * Чистий SQL дає повний контроль і продуктивність, але потребує більше коду.
13. **Індекси.** B-дерево дозволяє знаходити рядки за O(log n) замість повного перегляду таблиці, а також прискорює JOIN і сортування. Індекси не завжди виправдані: вони займають місце, сповільнюють INSERT/UPDATE/DELETE і марні для малих таблиць та полів з низькою селективністю.
14. **Транзакція та ACID.** Транзакція — логічна одиниця роботи, яка виконується повністю або не виконується зовсім.
    * Atomicity — атомарність.
    * Consistency — узгодженість з обмеженнями.
    * Isolation — ізольованість паралельних транзакцій.
    * Durability — зафіксовані зміни не втрачаються навіть після збою.
15. **Оптимізація запитів.**
    * Аналізувати плани через `EXPLAIN ANALYZE`.
    * Створювати потрібні індекси, зокрема складені, часткові та функціональні.
    * Вибирати лише потрібні колонки.
    * Уникати функцій над індексованими полями в `WHERE` (або створювати функціональні індекси).
    * Замінювати корельовані підзапити на JOIN або EXISTS, де це доречно.
    * Розбивати вивід на сторінки.
    * Оновлювати статистику (`ANALYZE`).
    * Використовувати пул з'єднань і кешування.
16. **Переваги Docker.**
    * Швидке розгортання однаковою командою.
    * Ізоляція від системи.
    * Однакове середовище в усіх розробників.
    * Легко змінювати версію PostgreSQL.
    * Автоматична ініціалізація схеми скриптами.
    * Просте очищення (`down -v`).
17. **Підключення до PostgreSQL у контейнері.** Порт пробрасується (`"5432:5432"`), а застосунок підключається до `localhost:5432` з обліковими даними зі змінних `POSTGRES_*`. Інший контейнер у тій самій мережі compose підключається за іменем сервісу (`postgres:5432`). Також можна відкрити консоль у контейнері: `docker exec -it library_db psql -U postgres -d library`.
