"""Консольний застосунок «Електронна бібліотека» (лабораторна робота 4, рівень 1).

Реалізує CRUD-операції для книг, авторів і читачів, видачу/повернення
книг через збережені функції PostgreSQL та набір аналітичних запитів.
Запуск:  python main.py
"""
import re
import sys
from datetime import date

from database import Database, DatabaseError

# ----------------------------------------------------------------------
# Допоміжні функції виводу та введення
# ----------------------------------------------------------------------
RESET, BOLD, GREEN, RED, CYAN, YELLOW = "\033[0m", "\033[1m", "\033[32m", "\033[31m", "\033[36m", "\033[33m"


def ok(msg):
    print(f"{GREEN}✔ {msg}{RESET}")


def err(msg):
    print(f"{RED}✘ {msg}{RESET}")


def title(text):
    print(f"\n{BOLD}{CYAN}=== {text} ==={RESET}")


def print_table(rows, columns=None, max_width=34):
    """Друкує список словників у вигляді таблиці."""
    if not rows:
        print(f"{YELLOW}(немає записів){RESET}")
        return
    columns = columns or list(rows[0].keys())

    def cell(value):
        text = "—" if value is None else str(value)
        return text if len(text) <= max_width else text[: max_width - 1] + "…"

    widths = {c: max(len(c), *(len(cell(r[c])) for r in rows)) for c in columns}
    line = "+" + "+".join("-" * (widths[c] + 2) for c in columns) + "+"
    print(line)
    print("| " + " | ".join(f"{BOLD}{c:<{widths[c]}}{RESET}" for c in columns) + " |")
    print(line)
    for r in rows:
        print("| " + " | ".join(f"{cell(r[c]):<{widths[c]}}" for c in columns) + " |")
    print(line)
    print(f"Усього записів: {len(rows)}")


def ask(prompt, default=None, required=True, pattern=None, hint=""):
    """Запитує рядок. Порожнє введення -> default. Перевіряє regex-шаблон."""
    suffix = f" [{default}]" if default not in (None, "") else ""
    while True:
        value = input(f"{prompt}{suffix}: ").strip()
        if not value:
            if default is not None:
                return default
            if not required:
                return None
            err("Поле обов'язкове")
            continue
        if pattern and not re.fullmatch(pattern, value):
            err(f"Невірний формат. {hint}")
            continue
        return value


def ask_int(prompt, default=None, required=True, min_value=None, max_value=None):
    """Запитує ціле число з перевіркою діапазону."""
    while True:
        raw = ask(prompt, None if default is None else str(default), required)
        if raw is None:
            return None
        try:
            value = int(raw)
        except ValueError:
            err("Потрібно ввести ціле число")
            continue
        if (min_value is not None and value < min_value) or (max_value is not None and value > max_value):
            err(f"Значення має бути в межах {min_value}..{max_value}")
            continue
        return value


def ask_float(prompt, default=None):
    while True:
        raw = ask(prompt, None if default is None else str(default))
        try:
            value = float(raw.replace(",", "."))
            if value < 0:
                raise ValueError
            return value
        except ValueError:
            err("Потрібно ввести невід'ємне число")


def confirm(prompt):
    return input(f"{prompt} (т/н): ").strip().lower() in ("т", "так", "y", "yes")


def choose(options):
    """Друкує меню і повертає вибраний пункт."""
    for key, label in options:
        print(f"  {BOLD}{key}{RESET}. {label}")
    return input("Ваш вибір: ").strip()


def run_menu(name, items):
    """Цикл підменю: items = [(клавіша, назва, функція)]. Помилки БД не виводять з меню."""
    while True:
        title(name)
        c = choose([(k, label) for k, label, _ in items] + [("0", "Назад")])
        if c == "0":
            return
        action = next((fn for k, _, fn in items if k == c), None)
        if action is None:
            err("Невідомий пункт меню")
            continue
        try:
            action()
        except DatabaseError as exc:          # обмеження цілісності, RAISE EXCEPTION
            err(f"Помилка БД: {exc}")


# ----------------------------------------------------------------------
# Книги
# ----------------------------------------------------------------------
class BooksMenu:
    def __init__(self, db):
        self.db = db

    def list(self, search=None):
        sql = """SELECT book_id AS id, title AS назва, authors AS автори, genre AS жанр,
                        publish_year AS рік, price AS ціна,
                        available_copies || '/' || total_copies AS наявн
                 FROM v_books_catalog
                 WHERE %(q)s IS NULL OR LOWER(title) LIKE %(q)s OR LOWER(authors) LIKE %(q)s
                 ORDER BY book_id"""
        q = f"%{search.lower()}%" if search else None
        print_table(self.db.fetch_all(sql, {"q": q}))

    def show_reference(self):
        print_table(self.db.fetch_all("SELECT genre_id AS id, name AS жанр FROM genres ORDER BY genre_id"))
        print_table(self.db.fetch_all("SELECT publisher_id AS id, name AS видавництво FROM publishers ORDER BY 1"))

    def _form(self, book=None):
        """Збирає дані книги (для створення або редагування)."""
        b = book or {}
        self.show_reference()
        data = {
            "title": ask("Назва", b.get("title")),
            "isbn": ask("ISBN (978-...)", b.get("isbn"), pattern=r"(97[89]-?)?[0-9-]{9,13}[0-9X]",
                        hint="Приклад: 978-966-03-1234-5"),
            "genre_id": ask_int("ID жанру", b.get("genre_id"), min_value=1),
            "publisher_id": ask_int("ID видавництва (Enter — немає)", b.get("publisher_id"), required=False, min_value=1),
            "publish_year": ask_int("Рік видання", b.get("publish_year"), min_value=1450, max_value=date.today().year),
            "pages": ask_int("Кількість сторінок", b.get("pages"), min_value=1),
            "price": ask_float("Ціна, грн", b.get("price")),
            "total_copies": ask_int("Кількість примірників", b.get("total_copies", 1), min_value=0, max_value=1000),
        }
        return data

    def create(self):
        title("Додавання книги")
        data = self._form()
        print_table(self.db.fetch_all("SELECT author_id AS id, first_name || ' ' || last_name AS автор FROM authors ORDER BY 1"))
        author_ids = ask("ID авторів через кому", pattern=r"\d+(\s*,\s*\d+)*", hint="Наприклад: 2, 3")
        book_id = self.db.fetch_value(
            """WITH new_book AS (
                   INSERT INTO books (title, isbn, genre_id, publisher_id, publish_year, pages, price,
                                      total_copies, available_copies)
                   VALUES (%(title)s, %(isbn)s, %(genre_id)s, %(publisher_id)s, %(publish_year)s,
                           %(pages)s, %(price)s, %(total_copies)s, %(total_copies)s)
                   RETURNING book_id)
               INSERT INTO book_authors (book_id, author_id, author_order)
               SELECT new_book.book_id, a.id, a.ord
               FROM new_book, UNNEST(%(authors)s::int[]) WITH ORDINALITY AS a(id, ord)
               RETURNING book_id""",
            {**data, "authors": [int(x) for x in author_ids.split(",")]},
        )
        ok(f"Книгу додано з ID {book_id}")

    def update(self):
        title("Редагування книги")
        book_id = ask_int("ID книги", min_value=1)
        book = self.db.fetch_one("SELECT * FROM books WHERE book_id = %s", (book_id,))
        if not book:
            err("Книгу не знайдено")
            return
        print("Enter — залишити поточне значення")
        data = self._form(book)
        data["book_id"] = book_id
        self.db.execute(
            """UPDATE books SET title=%(title)s, isbn=%(isbn)s, genre_id=%(genre_id)s,
                   publisher_id=%(publisher_id)s, publish_year=%(publish_year)s, pages=%(pages)s,
                   price=%(price)s, total_copies=%(total_copies)s
               WHERE book_id=%(book_id)s""", data)
        ok("Книгу оновлено")
        self.list_one(book_id)

    def list_one(self, book_id):
        print_table(self.db.fetch_all(
            """SELECT book_id AS id, title AS назва, isbn, price AS ціна, available_copies AS доступно,
                      total_copies AS усього, updated_at AS оновлено
               FROM books WHERE book_id = %s""", (book_id,)))

    def delete(self):
        title("Видалення книги")
        book_id = ask_int("ID книги", min_value=1)
        book = self.db.fetch_one("SELECT title FROM books WHERE book_id = %s", (book_id,))
        if not book:
            err("Книгу не знайдено")
            return
        if not confirm(f"Видалити «{book['title']}»?"):
            print("Скасовано")
            return
        try:
            self.db.execute("DELETE FROM books WHERE book_id = %s", (book_id,))
            ok("Книгу видалено")
        except DatabaseError as exc:
            err(f"Неможливо видалити: книга має історію видач ({exc})")

    def menu(self):
        run_menu("КНИГИ", [("1", "Список книг", self.list),
                               ("2", "Пошук за назвою/автором", lambda: self.list(ask("Текст для пошуку"))),
                               ("3", "Додати книгу", self.create), ("4", "Редагувати книгу", self.update),
                               ("5", "Видалити книгу", self.delete)])


# ----------------------------------------------------------------------
# Автори
# ----------------------------------------------------------------------
class AuthorsMenu:
    def __init__(self, db):
        self.db = db

    def list(self):
        print_table(self.db.fetch_all(
            """SELECT a.author_id AS id, a.last_name AS прізвище, a.first_name AS імя,
                      a.birth_year AS нар, a.death_year AS пом, a.country AS країна,
                      COUNT(ba.book_id) AS книг
               FROM authors a LEFT JOIN book_authors ba ON ba.author_id = a.author_id
               GROUP BY a.author_id ORDER BY a.author_id"""))

    def _form(self, a=None):
        a = a or {}
        return {
            "first_name": ask("Ім'я", a.get("first_name")),
            "last_name": ask("Прізвище", a.get("last_name")),
            "birth_year": ask_int("Рік народження", a.get("birth_year"), min_value=1000, max_value=date.today().year),
            "death_year": ask_int("Рік смерті (Enter — немає)", a.get("death_year"), required=False,
                                  min_value=1000, max_value=date.today().year),
            "country": ask("Країна", a.get("country", "Україна")),
            "biography": ask("Коротка біографія", a.get("biography"), required=False),
        }

    def create(self):
        title("Додавання автора")
        data = self._form()
        new_id = self.db.fetch_value(
            """INSERT INTO authors (first_name, last_name, birth_year, death_year, country, biography)
               VALUES (%(first_name)s, %(last_name)s, %(birth_year)s, %(death_year)s, %(country)s, %(biography)s)
               RETURNING author_id""", data)
        ok(f"Автора додано з ID {new_id}")

    def update(self):
        title("Редагування автора")
        author_id = ask_int("ID автора", min_value=1)
        author = self.db.fetch_one("SELECT * FROM authors WHERE author_id = %s", (author_id,))
        if not author:
            err("Автора не знайдено")
            return
        data = self._form(author)
        data["author_id"] = author_id
        self.db.execute(
            """UPDATE authors SET first_name=%(first_name)s, last_name=%(last_name)s, birth_year=%(birth_year)s,
                   death_year=%(death_year)s, country=%(country)s, biography=%(biography)s
               WHERE author_id=%(author_id)s""", data)
        ok("Дані автора оновлено")

    def delete(self):
        title("Видалення автора")
        author_id = ask_int("ID автора", min_value=1)
        books = self.db.fetch_value("SELECT COUNT(*) FROM book_authors WHERE author_id = %s", (author_id,))
        if books and not confirm(f"Автор пов'язаний з {books} книгами. Зв'язки буде видалено. Продовжити?"):
            return
        if self.db.execute("DELETE FROM authors WHERE author_id = %s", (author_id,)):
            ok("Автора видалено")
        else:
            err("Автора не знайдено")

    def menu(self):
        run_menu("АВТОРИ", [("1", "Список авторів", self.list), ("2", "Додати автора", self.create),
                                ("3", "Редагувати автора", self.update), ("4", "Видалити автора", self.delete)])


# ----------------------------------------------------------------------
# Читачі
# ----------------------------------------------------------------------
class ReadersMenu:
    EMAIL = r"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}"
    PHONE = r"\+?[0-9 ()-]{7,20}"

    def __init__(self, db):
        self.db = db

    def list(self):
        print_table(self.db.fetch_all(
            """SELECT reader_id AS id, ticket_number AS квиток, reader_name AS читач, email,
                      books_on_hand AS на_руках, overdue_now AS простр, total_fines AS штрафи,
                      CASE WHEN is_active THEN 'так' ELSE 'ні' END AS активний
               FROM v_reader_statistics ORDER BY reader_id"""))

    def _form(self, r=None):
        r = r or {}
        return {
            "first_name": ask("Ім'я", r.get("first_name")),
            "last_name": ask("Прізвище", r.get("last_name")),
            "email": ask("Email", r.get("email"), pattern=self.EMAIL, hint="Приклад: name@gmail.com"),
            "phone": ask("Телефон", r.get("phone"), required=False, pattern=self.PHONE, hint="Приклад: +380671234567"),
            "birth_date": ask("Дата народження (РРРР-ММ-ДД)", str(r["birth_date"]) if r.get("birth_date") else None,
                              required=False, pattern=r"\d{4}-\d{2}-\d{2}", hint="Формат РРРР-ММ-ДД"),
            "address": ask("Адреса", r.get("address"), required=False),
        }

    def create(self):
        title("Реєстрація читача")
        data = self._form()
        # номер квитка генерується як наступний за максимальним
        row = self.db.fetch_one(
            """INSERT INTO readers (ticket_number, first_name, last_name, email, phone, birth_date, address)
               VALUES ((SELECT 'LIB-' || LPAD((COALESCE(MAX(SUBSTRING(ticket_number FROM 5)::INT), 0) + 1)::TEXT, 4, '0')
                        FROM readers),
                       %(first_name)s, %(last_name)s, %(email)s, %(phone)s, %(birth_date)s, %(address)s)
               RETURNING reader_id, ticket_number""", data)
        ok(f"Читача зареєстровано: ID {row['reader_id']}, квиток {row['ticket_number']}")

    def update(self):
        title("Редагування читача")
        reader_id = ask_int("ID читача", min_value=1)
        reader = self.db.fetch_one("SELECT * FROM readers WHERE reader_id = %s", (reader_id,))
        if not reader:
            err("Читача не знайдено")
            return
        data = self._form(reader)
        data["reader_id"] = reader_id
        data["is_active"] = confirm("Квиток активний?")
        self.db.execute(
            """UPDATE readers SET first_name=%(first_name)s, last_name=%(last_name)s, email=%(email)s,
                   phone=%(phone)s, birth_date=%(birth_date)s, address=%(address)s, is_active=%(is_active)s
               WHERE reader_id=%(reader_id)s""", data)
        ok("Дані читача оновлено")

    def delete(self):
        title("Видалення читача")
        reader_id = ask_int("ID читача", min_value=1)
        on_hand = self.db.fetch_value(
            "SELECT COUNT(*) FROM loans WHERE reader_id = %s AND return_date IS NULL", (reader_id,))
        if on_hand:
            err(f"Читач має {on_hand} неповернених книг — видалення заборонене")
            return
        if not confirm("Підтвердити видалення читача?"):
            return
        try:
            if self.db.execute("DELETE FROM readers WHERE reader_id = %s", (reader_id,)):
                ok("Читача видалено")
            else:
                err("Читача не знайдено")
        except DatabaseError:
            # якщо є історія видач — замість видалення блокуємо квиток
            self.db.execute("UPDATE readers SET is_active = FALSE WHERE reader_id = %s", (reader_id,))
            ok("Читач має історію видач, тому його квиток заблоковано (м'яке видалення)")

    def menu(self):
        run_menu("ЧИТАЧІ", [("1", "Список читачів", self.list), ("2", "Зареєструвати читача", self.create),
                                ("3", "Редагувати читача", self.update), ("4", "Видалити читача", self.delete)])


# ----------------------------------------------------------------------
# Видачі (через збережені функції)
# ----------------------------------------------------------------------
class LoansMenu:
    def __init__(self, db):
        self.db = db

    def active(self):
        print_table(self.db.fetch_all(
            """SELECT loan_id AS id, title AS книга, reader_name AS читач, loan_date AS видано,
                      due_date AS повернути, days_overdue AS простр_днів, expected_fine AS штраф
               FROM v_active_loans ORDER BY due_date"""))

    def issue(self):
        title("Видача книги")
        book_id = ask_int("ID книги", min_value=1)
        reader_id = ask_int("ID читача", min_value=1)
        days = ask_int("Термін, днів", 14, min_value=1, max_value=60)
        loan_id = self.db.fetch_value("SELECT issue_book(%s, %s, %s)", (book_id, reader_id, days))
        ok(f"Книгу видано, номер видачі {loan_id}")

    def give_back(self):
        title("Повернення книги")
        loan_id = ask_int("ID видачі", min_value=1)
        fine = self.db.fetch_value("SELECT return_book(%s)", (loan_id,))
        ok("Книгу повернено" + (f". Нараховано штраф: {fine} грн" if fine else " вчасно, без штрафу"))

    def extend(self):
        title("Продовження видачі")
        loan_id = ask_int("ID видачі", min_value=1)
        new_due = self.db.fetch_value("SELECT extend_loan(%s)", (loan_id,))
        ok(f"Термін продовжено до {new_due}")

    def menu(self):
        run_menu("ВИДАЧІ", [("1", "Книги на руках", self.active), ("2", "Видати книгу", self.issue),
                                ("3", "Повернути книгу", self.give_back), ("4", "Продовжити термін", self.extend)])


# ----------------------------------------------------------------------
# Звіти та запити
# ----------------------------------------------------------------------
REPORTS = {
    "1": ("ТОП-5 популярних книг",
          """SELECT title AS книга, authors AS автори, times_borrowed AS видач, avg_rating AS рейтинг
             FROM v_books_catalog ORDER BY times_borrowed DESC, avg_rating DESC NULLS LAST LIMIT 5"""),
    "2": ("Боржники (прострочені книги)",
          """SELECT reader_name AS читач, phone AS телефон, title AS книга, due_date AS термін,
                    days_overdue AS днів, expected_fine AS штраф
             FROM v_active_loans WHERE state = 'overdue' ORDER BY days_overdue DESC"""),
    "3": ("Статистика за жанрами",
          """SELECT genre AS жанр, books_count AS книг, copies_count AS примірників,
                    loans_count AS видач, avg_rating AS рейтинг
             FROM v_genre_statistics ORDER BY loans_count DESC, genre"""),
    "4": ("Книги, які ще не видавались",
          """SELECT b.title AS книга, b.publish_year AS рік FROM books b
             WHERE NOT EXISTS (SELECT 1 FROM loans l WHERE l.book_id = b.book_id) ORDER BY 1"""),
}


def reports_menu(db):
    def show(key):
        title(REPORTS[key][0])
        print_table(db.fetch_all(REPORTS[key][1]))

    def history():
        reader_id = ask_int("ID читача", min_value=1)
        print_table(db.fetch_all(
            """SELECT loan_id AS id, book_title AS книга, loan_date AS видано, due_date AS термін,
                      return_date AS повернено, status AS статус, fine AS штраф
               FROM get_reader_history(%s)""", (reader_id,)))

    items = [(k, v[0], lambda k=k: show(k)) for k, v in REPORTS.items()]
    run_menu("ЗВІТИ ТА ЗАПИТИ", items + [("5", "Історія читача (функція)", history)])


# ----------------------------------------------------------------------
# Головне меню
# ----------------------------------------------------------------------
def main():
    db = Database(app_user="console")
    try:
        db.connect()
    except DatabaseError as exc:
        err(str(exc))
        sys.exit(1)

    ok(f"Підключено до PostgreSQL {db.server_version()} (база «{db.config['dbname']}»)")
    menus = {"1": BooksMenu(db).menu, "2": AuthorsMenu(db).menu, "3": ReadersMenu(db).menu,
             "4": LoansMenu(db).menu, "5": lambda: reports_menu(db)}
    try:
        while True:
            title("ЕЛЕКТРОННА БІБЛІОТЕКА — ГОЛОВНЕ МЕНЮ")
            c = choose([("1", "Книги"), ("2", "Автори"), ("3", "Читачі"), ("4", "Видачі"),
                        ("5", "Звіти та запити"), ("0", "Вихід")])
            if c == "0":
                break
            action = menus.get(c)
            if action is None:
                err("Невідомий пункт меню")
                continue
            try:
                action()
            except DatabaseError as exc:          # помилки СУБД (обмеження, RAISE EXCEPTION)
                err(f"Помилка БД: {exc}")
    except (KeyboardInterrupt, EOFError):
        print()
    finally:
        db.close()
        print("До побачення!")


if __name__ == "__main__":
    main()
