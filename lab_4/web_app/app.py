"""Вебзастосунок «Електронна бібліотека» (Flask). Лабораторна робота 4, рівні 2–3.

Запуск:  python app.py        (http://127.0.0.1:5000)
"""
import logging
import math
import os
import secrets
from datetime import date, datetime, timedelta
from decimal import Decimal
from logging.handlers import RotatingFileHandler

from flask import (Flask, abort, flash, g, redirect, render_template, request, session, url_for)
from flask.json.provider import DefaultJSONProvider

import database as db
from api import bp as api_bp
from auth import ROLE_NAMES, bp as auth_bp, is_staff, login_required, roles_required
from backup import bp as backup_bp
from charts import bp as charts_bp
from reports import bp as reports_bp
from validators import validate_author, validate_book, validate_reader

BASE_DIR = os.path.dirname(os.path.abspath(__file__))

class LibraryJSONProvider(DefaultJSONProvider):
    """JSON для API: дати у форматі ISO 8601, Decimal — як число."""
    ensure_ascii = False

    @staticmethod
    def default(o):
        if isinstance(o, (date, datetime)):
            return o.isoformat()
        if isinstance(o, Decimal):
            return float(o)
        return DefaultJSONProvider.default(o)


app = Flask(__name__)
app.json_provider_class = LibraryJSONProvider
app.json = LibraryJSONProvider(app)
app.config.update(
    SECRET_KEY=os.getenv("SECRET_KEY", "dev-secret-change-me-in-production"),
    PERMANENT_SESSION_LIFETIME=timedelta(hours=8),
    SESSION_COOKIE_HTTPONLY=True,
    SESSION_COOKIE_SAMESITE="Lax",
)

for blueprint in (auth_bp, api_bp, reports_bp, charts_bp, backup_bp):
    app.register_blueprint(blueprint)

# ----------------------------------------------------------------------
# Логування застосунку у файл logs/app.log (+ журнал audit_log у БД)
# ----------------------------------------------------------------------
os.makedirs(os.path.join(BASE_DIR, "logs"), exist_ok=True)
_handler = RotatingFileHandler(os.path.join(BASE_DIR, "logs", "app.log"), maxBytes=1_000_000,
                               backupCount=3, encoding="utf-8")
_handler.setFormatter(logging.Formatter("%(asctime)s %(levelname)s %(message)s"))
app.logger.addHandler(_handler)
app.logger.setLevel(logging.INFO)

PER_PAGE = 10


# ----------------------------------------------------------------------
# CSRF-захист форм та спільні змінні шаблонів
# ----------------------------------------------------------------------
def csrf_token():
    if "_csrf" not in session:
        session["_csrf"] = secrets.token_hex(16)
    return session["_csrf"]


@app.before_request
def before_request():
    if request.method == "POST" and not request.path.startswith("/api/"):
        if request.form.get("_csrf") != session.get("_csrf"):
            abort(400, description="Недійсний CSRF-токен. Оновіть сторінку.")


@app.after_request
def after_request(response):
    if request.method in ("POST", "PUT", "DELETE"):
        app.logger.info("%s %s %s -> %s", session.get("username", g.get("api_user", "anonymous")),
                        request.method, request.path, response.status_code)
    return response


@app.context_processor
def inject_globals():
    return {"csrf_token": csrf_token, "ROLE_NAMES": ROLE_NAMES, "is_staff": is_staff}


@app.template_filter("money")
def money(value):
    return f"{value or 0:,.2f} грн".replace(",", " ")


STATUS_NAMES = {"active": "Активна", "returned": "Повернена", "overdue": "Прострочена", "lost": "Втрачена",
                "pending": "Очікує", "fulfilled": "Виконано", "cancelled": "Скасовано", "expired": "Протерміновано"}


@app.template_filter("status")
def status_name(value):
    return STATUS_NAMES.get(value, value)


@app.errorhandler(403)
def forbidden(_):
    return render_template("error.html", code=403, message="Недостатньо прав для цієї дії"), 403


@app.errorhandler(404)
def not_found(_):
    return render_template("error.html", code=404, message="Сторінку не знайдено"), 404


@app.errorhandler(400)
def bad_request(e):
    return render_template("error.html", code=400, message=e.description), 400


@app.errorhandler(db.DatabaseError)
def database_error(e):
    flash(f"Помилка бази даних: {e}", "danger")
    return redirect(request.referrer or url_for("index"))


def paginate(total, page):
    pages = max(1, math.ceil(total / PER_PAGE))
    return {"page": page, "pages": pages, "total": total}


# ----------------------------------------------------------------------
# Головна сторінка
# ----------------------------------------------------------------------
@app.route("/")
@login_required
def index():
    stats = db.query_one(
        """SELECT (SELECT COUNT(*) FROM books)                       AS books,
                  (SELECT COALESCE(SUM(total_copies), 0) FROM books) AS copies,
                  (SELECT COUNT(*) FROM readers WHERE is_active)     AS readers,
                  (SELECT COUNT(*) FROM v_active_loans)              AS on_hand,
                  (SELECT COUNT(*) FROM v_active_loans WHERE state = 'overdue') AS overdue,
                  (SELECT COUNT(*) FROM reservations WHERE status = 'pending')  AS reservations""")
    popular = db.query("""SELECT book_id, title, authors, times_borrowed, avg_rating FROM v_books_catalog
                          ORDER BY times_borrowed DESC, avg_rating DESC NULLS LAST LIMIT 5""")
    recent = db.query("""SELECT l.loan_id, b.title, r.last_name || ' ' || r.first_name AS reader,
                                l.loan_date, l.status
                         FROM loans l JOIN books b USING (book_id) JOIN readers r USING (reader_id)
                         ORDER BY l.loan_id DESC LIMIT 5""") if is_staff() else []
    return render_template("index.html", stats=stats, popular=popular, recent=recent)


# ----------------------------------------------------------------------
# Книги: пошук, фільтрація, сортування, пагінація + CRUD
# ----------------------------------------------------------------------
BOOK_SORTS = {"title": "title", "year": "publish_year", "price": "price", "rating": "avg_rating",
              "popular": "times_borrowed", "available": "available_copies"}


@app.route("/books")
@login_required
def books_list():
    q = (request.args.get("q") or "").strip()
    genre = request.args.get("genre", type=int)
    available = request.args.get("available") == "1"
    year_from = request.args.get("year_from", type=int)
    year_to = request.args.get("year_to", type=int)
    sort = request.args.get("sort", "title")
    order = "DESC" if request.args.get("order") == "desc" else "ASC"
    page = max(1, request.args.get("page", 1, type=int))

    where, params = ["TRUE"], {}
    if q:
        where.append("(LOWER(title) LIKE %(q)s OR LOWER(authors) LIKE %(q)s OR isbn LIKE %(q)s)")
        params["q"] = f"%{q.lower()}%"
    if genre:
        where.append("genre_id = %(genre)s")
        params["genre"] = genre
    if available:
        where.append("available_copies > 0")
    if year_from:
        where.append("publish_year >= %(year_from)s")
        params["year_from"] = year_from
    if year_to:
        where.append("publish_year <= %(year_to)s")
        params["year_to"] = year_to
    where_sql = " AND ".join(where)
    order_sql = f"{BOOK_SORTS.get(sort, 'title')} {order} NULLS LAST, title"  # лише з білого списку

    total = db.scalar(f"SELECT COUNT(*) FROM v_books_catalog WHERE {where_sql}", params)
    params.update(limit=PER_PAGE, offset=(page - 1) * PER_PAGE)
    books = db.query(f"""SELECT * FROM v_books_catalog WHERE {where_sql}
                         ORDER BY {order_sql} LIMIT %(limit)s OFFSET %(offset)s""", params)
    genres = db.query("SELECT genre_id, name FROM genres ORDER BY name")
    return render_template("books/list.html", books=books, genres=genres, pager=paginate(total, page),
                           args=request.args)


@app.route("/books/<int:book_id>")
@login_required
def book_detail(book_id):
    book = db.query_one("""SELECT c.*, b.description, b.language, b.created_at, b.updated_at
                           FROM v_books_catalog c JOIN books b USING (book_id) WHERE book_id = %s""", (book_id,))
    if not book:
        abort(404)
    reviews = db.query("""SELECT rv.rating, rv.comment, rv.created_at, r.first_name || ' ' || r.last_name AS reader,
                                 rv.reader_id
                          FROM reviews rv JOIN readers r USING (reader_id)
                          WHERE book_id = %s ORDER BY rv.created_at DESC""", (book_id,))
    loans = db.query("""SELECT l.loan_id, r.last_name || ' ' || r.first_name AS reader, l.loan_date, l.due_date,
                               l.return_date, l.status
                        FROM loans l JOIN readers r USING (reader_id)
                        WHERE l.book_id = %s ORDER BY l.loan_date DESC LIMIT 10""", (book_id,)) if is_staff() else []
    pending = db.scalar("SELECT COUNT(*) FROM reservations WHERE book_id = %s AND status = 'pending'", (book_id,))
    my_review = any(rv["reader_id"] == session.get("reader_id") for rv in reviews)
    return render_template("books/detail.html", book=book, reviews=reviews, loans=loans,
                           pending=pending, my_review=my_review)


def _book_form_context(book=None, errors=None):
    return {
        "book": book or {}, "errors": errors or {},
        "genres": db.query("SELECT genre_id, name FROM genres ORDER BY name"),
        "publishers": db.query("SELECT publisher_id, name FROM publishers ORDER BY name"),
        "authors": db.query("SELECT author_id, last_name || ' ' || first_name AS name FROM authors ORDER BY 2"),
    }


def _save_book_authors(cur, book_id, author_ids):
    cur.execute("DELETE FROM book_authors WHERE book_id = %s", (book_id,))
    for order, author_id in enumerate(author_ids, start=1):
        cur.execute("INSERT INTO book_authors (book_id, author_id, author_order) VALUES (%s, %s, %s)",
                    (book_id, author_id, order))


@app.route("/books/new", methods=["GET", "POST"])
@roles_required("admin", "librarian")
def book_create():
    if request.method == "POST":
        data, errors = validate_book(request.form)
        if not errors:
            try:
                with db.transaction() as cur:
                    cur.execute("""INSERT INTO books (title, isbn, genre_id, publisher_id, publish_year, pages,
                                                      language, price, total_copies, available_copies, description)
                                   VALUES (%(title)s, %(isbn)s, %(genre_id)s, %(publisher_id)s, %(publish_year)s,
                                           %(pages)s, %(language)s, %(price)s, %(total_copies)s, %(total_copies)s,
                                           %(description)s)
                                   RETURNING book_id""", data)
                    book_id = cur.fetchone()["book_id"]
                    _save_book_authors(cur, book_id, data["author_ids"])
                flash(f"Книгу «{data['title']}» додано", "success")
                return redirect(url_for("book_detail", book_id=book_id))
            except db.DatabaseError as exc:
                flash(str(exc), "danger")
        return render_template("books/form.html", **_book_form_context(data, errors))
    return render_template("books/form.html", **_book_form_context({"author_ids": [], "language": "українська",
                                                                     "total_copies": 1}))


@app.route("/books/<int:book_id>/edit", methods=["GET", "POST"])
@roles_required("admin", "librarian")
def book_edit(book_id):
    book = db.query_one("""SELECT b.*, ARRAY(SELECT author_id FROM book_authors ba
                                             WHERE ba.book_id = b.book_id ORDER BY author_order) AS author_ids
                           FROM books b WHERE book_id = %s""", (book_id,))
    if not book:
        abort(404)
    if request.method == "POST":
        data, errors = validate_book(request.form)
        data["book_id"] = book_id
        if not errors:
            try:
                with db.transaction() as cur:
                    cur.execute("""UPDATE books SET title=%(title)s, isbn=%(isbn)s, genre_id=%(genre_id)s,
                                       publisher_id=%(publisher_id)s, publish_year=%(publish_year)s,
                                       pages=%(pages)s, language=%(language)s, price=%(price)s,
                                       total_copies=%(total_copies)s, description=%(description)s
                                   WHERE book_id=%(book_id)s""", data)
                    _save_book_authors(cur, book_id, data["author_ids"])
                flash("Зміни збережено", "success")
                return redirect(url_for("book_detail", book_id=book_id))
            except db.DatabaseError as exc:
                flash(str(exc), "danger")
        return render_template("books/form.html", **_book_form_context(data, errors))
    return render_template("books/form.html", **_book_form_context(book))


@app.route("/books/<int:book_id>/delete", methods=["POST"])
@roles_required("admin", "librarian")
def book_delete(book_id):
    try:
        db.execute("DELETE FROM books WHERE book_id = %s", (book_id,))
        flash("Книгу видалено", "success")
    except db.DatabaseError:
        flash("Книгу не можна видалити: у неї є історія видач", "danger")
        return redirect(url_for("book_detail", book_id=book_id))
    return redirect(url_for("books_list"))


@app.route("/books/<int:book_id>/reserve", methods=["POST"])
@roles_required("reader")
def book_reserve(book_id):
    try:
        db.scalar("SELECT reserve_book(%s, %s)", (book_id, session["reader_id"]))
        flash("Книгу заброньовано на 3 дні. Заберіть її в бібліотеці.", "success")
    except db.DatabaseError as exc:
        flash(str(exc), "danger")
    return redirect(url_for("book_detail", book_id=book_id))


@app.route("/books/<int:book_id>/review", methods=["POST"])
@roles_required("reader")
def book_review(book_id):
    rating = request.form.get("rating", type=int)
    comment = (request.form.get("comment") or "").strip()[:1000]
    if rating not in range(1, 6):
        flash("Оцінка має бути від 1 до 5", "danger")
    else:
        db.execute("""INSERT INTO reviews (book_id, reader_id, rating, comment) VALUES (%s, %s, %s, %s)
                      ON CONFLICT (book_id, reader_id) DO UPDATE SET rating = EXCLUDED.rating,
                                                                   comment = EXCLUDED.comment""",
                   (book_id, session["reader_id"], rating, comment or None))
        flash("Дякуємо за відгук!", "success")
    return redirect(url_for("book_detail", book_id=book_id))


# ----------------------------------------------------------------------
# Автори
# ----------------------------------------------------------------------
@app.route("/authors")
@login_required
def authors_list():
    q = (request.args.get("q") or "").strip()
    authors = db.query("""SELECT a.*, COUNT(ba.book_id) AS books
                          FROM authors a LEFT JOIN book_authors ba USING (author_id)
                          WHERE %(q)s = '' OR LOWER(a.last_name || ' ' || a.first_name) LIKE %(like)s
                          GROUP BY a.author_id ORDER BY a.last_name""", {"q": q, "like": f"%{q.lower()}%"})
    return render_template("authors/list.html", authors=authors, q=q)


@app.route("/authors/new", methods=["GET", "POST"], defaults={"author_id": None})
@app.route("/authors/<int:author_id>/edit", methods=["GET", "POST"])
@roles_required("admin", "librarian")
def author_form(author_id):
    author = {"country": "Україна"}
    if author_id:
        author = db.query_one("SELECT * FROM authors WHERE author_id = %s", (author_id,)) or abort(404)
    errors = {}
    if request.method == "POST":
        data, errors = validate_author(request.form)
        if not errors:
            if author_id:
                data["author_id"] = author_id
                db.execute("""UPDATE authors SET first_name=%(first_name)s, last_name=%(last_name)s,
                                  birth_year=%(birth_year)s, death_year=%(death_year)s, country=%(country)s,
                                  biography=%(biography)s WHERE author_id=%(author_id)s""", data)
                flash("Дані автора оновлено", "success")
            else:
                db.execute("""INSERT INTO authors (first_name, last_name, birth_year, death_year, country, biography)
                              VALUES (%(first_name)s, %(last_name)s, %(birth_year)s, %(death_year)s,
                                      %(country)s, %(biography)s)""", data)
                flash(f"Автора {data['first_name']} {data['last_name']} додано", "success")
            return redirect(url_for("authors_list"))
        author = data
    return render_template("authors/form.html", author=author, errors=errors, author_id=author_id)


@app.route("/authors/<int:author_id>/delete", methods=["POST"])
@roles_required("admin", "librarian")
def author_delete(author_id):
    db.execute("DELETE FROM authors WHERE author_id = %s", (author_id,))
    flash("Автора видалено", "success")
    return redirect(url_for("authors_list"))


# ----------------------------------------------------------------------
# Читачі
# ----------------------------------------------------------------------
@app.route("/readers")
@roles_required("admin", "librarian")
def readers_list():
    q = (request.args.get("q") or "").strip()
    only = request.args.get("only", "")
    where = ["(%(q)s = '' OR LOWER(reader_name) LIKE %(like)s OR ticket_number ILIKE %(like)s OR email ILIKE %(like)s)"]
    if only == "debtors":
        where.append("overdue_now > 0")
    elif only == "blocked":
        where.append("NOT is_active")
    readers = db.query(f"SELECT * FROM v_reader_statistics WHERE {' AND '.join(where)} ORDER BY reader_name",
                       {"q": q, "like": f"%{q.lower()}%"})
    return render_template("readers/list.html", readers=readers, q=q, only=only)


@app.route("/readers/<int:reader_id>")
@login_required
def reader_detail(reader_id):
    if not is_staff() and session.get("reader_id") != reader_id:
        abort(403)
    reader = db.query_one("SELECT r.*, s.total_loans, s.books_on_hand, s.total_fines FROM readers r "
                          "JOIN v_reader_statistics s USING (reader_id) WHERE reader_id = %s", (reader_id,))
    if not reader:
        abort(404)
    history = db.query("SELECT * FROM get_reader_history(%s)", (reader_id,))
    reservations = db.query("""SELECT rs.*, b.title FROM reservations rs JOIN books b USING (book_id)
                               WHERE reader_id = %s ORDER BY reservation_date DESC""", (reader_id,))
    return render_template("readers/detail.html", reader=reader, history=history, reservations=reservations)


@app.route("/my")
@roles_required("reader")
def my_cabinet():
    return redirect(url_for("reader_detail", reader_id=session["reader_id"]))


@app.route("/readers/new", methods=["GET", "POST"], defaults={"reader_id": None})
@app.route("/readers/<int:reader_id>/edit", methods=["GET", "POST"])
@roles_required("admin", "librarian")
def reader_form(reader_id):
    reader = {"is_active": True}
    if reader_id:
        reader = db.query_one("SELECT * FROM readers WHERE reader_id = %s", (reader_id,)) or abort(404)
    errors = {}
    if request.method == "POST":
        data, errors = validate_reader(request.form)
        if not errors:
            try:
                if reader_id:
                    data["reader_id"] = reader_id
                    db.execute("""UPDATE readers SET first_name=%(first_name)s, last_name=%(last_name)s,
                                      email=%(email)s, phone=%(phone)s, birth_date=%(birth_date)s,
                                      address=%(address)s, is_active=%(is_active)s
                                  WHERE reader_id=%(reader_id)s""", data)
                    flash("Дані читача оновлено", "success")
                else:
                    reader_id = db.scalar(
                        """INSERT INTO readers (ticket_number, first_name, last_name, email, phone, birth_date, address)
                           VALUES ((SELECT 'LIB-' || LPAD((COALESCE(MAX(SUBSTRING(ticket_number FROM 5)::INT), 0) + 1)::TEXT, 4, '0')
                                    FROM readers),
                                   %(first_name)s, %(last_name)s, %(email)s, %(phone)s, %(birth_date)s, %(address)s)
                           RETURNING reader_id""", data)
                    flash("Читача зареєстровано", "success")
                return redirect(url_for("reader_detail", reader_id=reader_id))
            except db.DatabaseError as exc:
                if "email" in str(exc):
                    errors["email"] = "Цей email уже використовується"
                else:
                    flash(str(exc), "danger")
        reader = data
    return render_template("readers/form.html", reader=reader, errors=errors, reader_id=reader_id)


@app.route("/readers/<int:reader_id>/delete", methods=["POST"])
@roles_required("admin", "librarian")
def reader_delete(reader_id):
    if db.scalar("SELECT COUNT(*) FROM loans WHERE reader_id = %s AND return_date IS NULL", (reader_id,)):
        flash("Читач має неповернені книги — видалення неможливе", "danger")
        return redirect(url_for("reader_detail", reader_id=reader_id))
    try:
        db.execute("DELETE FROM readers WHERE reader_id = %s", (reader_id,))
        flash("Читача видалено", "success")
    except db.DatabaseError:
        db.execute("UPDATE readers SET is_active = FALSE WHERE reader_id = %s", (reader_id,))
        flash("Читач має історію видач, тому квиток заблоковано (м'яке видалення)", "warning")
    return redirect(url_for("readers_list"))


# ----------------------------------------------------------------------
# Видачі та бронювання (через збережені функції БД)
# ----------------------------------------------------------------------
@app.route("/loans")
@roles_required("admin", "librarian")
def loans_list():
    status = request.args.get("status", "open")
    q = (request.args.get("q") or "").strip()
    where = {"open": "l.return_date IS NULL", "overdue": "l.return_date IS NULL AND l.due_date < CURRENT_DATE",
             "returned": "l.return_date IS NOT NULL", "all": "TRUE"}.get(status, "l.return_date IS NULL")
    loans = db.query(f"""SELECT l.*, b.title, r.last_name || ' ' || r.first_name AS reader, r.ticket_number,
                                GREATEST(CURRENT_DATE - l.due_date, 0) AS days_overdue
                         FROM loans l JOIN books b USING (book_id) JOIN readers r USING (reader_id)
                         WHERE {where} AND (%(q)s = '' OR LOWER(b.title || ' ' || r.last_name) LIKE %(like)s)
                         ORDER BY l.loan_date DESC, l.loan_id DESC LIMIT 200""",
                     {"q": q, "like": f"%{q.lower()}%"})
    return render_template("loans/list.html", loans=loans, status=status, q=q)


@app.route("/loans/new", methods=["GET", "POST"])
@roles_required("admin", "librarian")
def loan_create():
    form = {"book_id": request.args.get("book_id", type=int), "days": 14}
    if request.method == "POST":
        form = {"book_id": request.form.get("book_id", type=int), "reader_id": request.form.get("reader_id", type=int),
                "days": request.form.get("days", type=int)}
        if not all(form.values()):
            flash("Оберіть книгу, читача та термін", "danger")
        else:
            try:
                loan_id = db.scalar("SELECT issue_book(%(book_id)s, %(reader_id)s, %(days)s)", form)
                flash(f"Книгу видано (видача №{loan_id})", "success")
                return redirect(url_for("loans_list"))
            except db.DatabaseError as exc:
                flash(str(exc), "danger")
    books = db.query("SELECT book_id, title, available_copies FROM books ORDER BY title")
    readers = db.query("SELECT reader_id, ticket_number, last_name || ' ' || first_name AS name, is_active "
                       "FROM readers ORDER BY last_name")
    return render_template("loans/form.html", books=books, readers=readers, form=form)


@app.route("/loans/<int:loan_id>/return", methods=["POST"])
@roles_required("admin", "librarian")
def loan_return(loan_id):
    fine = db.scalar("SELECT return_book(%s)", (loan_id,))
    flash("Книгу повернено" + (f". Штраф за прострочення: {money(fine)}" if fine else " вчасно"),
          "warning" if fine else "success")
    return redirect(request.referrer or url_for("loans_list"))


@app.route("/loans/<int:loan_id>/extend", methods=["POST"])
@login_required
def loan_extend(loan_id):
    owner = db.scalar("SELECT reader_id FROM loans WHERE loan_id = %s", (loan_id,))
    if not is_staff() and owner != session.get("reader_id"):
        abort(403)
    try:
        new_due = db.scalar("SELECT extend_loan(%s)", (loan_id,))
        flash(f"Термін повернення продовжено до {new_due:%d.%m.%Y}", "success")
    except db.DatabaseError as exc:
        flash(str(exc), "danger")
    return redirect(request.referrer or url_for("index"))


@app.route("/reservations")
@roles_required("admin", "librarian")
def reservations_list():
    db.execute("CALL update_overdue_status()")      # протерміновані бронювання закриваються автоматично
    rows = db.query("""SELECT rs.*, b.title, b.available_copies, r.last_name || ' ' || r.first_name AS reader
                       FROM reservations rs JOIN books b USING (book_id) JOIN readers r USING (reader_id)
                       ORDER BY (rs.status = 'pending') DESC, rs.reservation_date DESC""")
    return render_template("loans/reservations.html", reservations=rows)


@app.route("/reservations/<int:reservation_id>/cancel", methods=["POST"])
@login_required
def reservation_cancel(reservation_id):
    owner = db.scalar("SELECT reader_id FROM reservations WHERE reservation_id = %s", (reservation_id,))
    if not is_staff() and owner != session.get("reader_id"):
        abort(403)
    db.execute("UPDATE reservations SET status = 'cancelled' WHERE reservation_id = %s AND status = 'pending'",
               (reservation_id,))
    flash("Бронювання скасовано", "info")
    return redirect(request.referrer or url_for("index"))


@app.route("/reservations/<int:reservation_id>/issue", methods=["POST"])
@roles_required("admin", "librarian")
def reservation_issue(reservation_id):
    res = db.query_one("SELECT book_id, reader_id FROM reservations WHERE reservation_id = %s", (reservation_id,))
    try:
        loan_id = db.scalar("SELECT issue_book(%s, %s)", (res["book_id"], res["reader_id"]))
        flash(f"Бронювання виконано, книгу видано (видача №{loan_id})", "success")
    except db.DatabaseError as exc:
        flash(str(exc), "danger")
    return redirect(url_for("reservations_list"))


# ----------------------------------------------------------------------
# Статистика (аналітичні запити + діаграми)
# ----------------------------------------------------------------------
@app.route("/stats")
@roles_required("admin", "librarian")
def stats():
    top_books = db.query("""SELECT RANK() OVER (ORDER BY COUNT(l.loan_id) DESC) AS place, b.title,
                                   COUNT(l.loan_id) AS loans,
                                   ROUND(100.0 * COUNT(l.loan_id) / SUM(COUNT(l.loan_id)) OVER (), 1) AS share
                            FROM books b LEFT JOIN loans l USING (book_id)
                            GROUP BY b.book_id ORDER BY loans DESC, b.title LIMIT 5""")
    monthly = db.query("""SELECT TO_CHAR(month, 'YYYY-MM') AS month, loans_count, unique_readers, fines,
                                 SUM(loans_count) OVER (ORDER BY month) AS running_total
                          FROM v_monthly_loans""")
    authors = db.query("""SELECT a.last_name || ' ' || a.first_name AS author, COUNT(DISTINCT ba.book_id) AS books,
                                 COUNT(l.loan_id) AS loans,
                                 (SELECT ROUND(AVG(rv.rating), 2) FROM reviews rv
                                  JOIN book_authors x USING (book_id) WHERE x.author_id = a.author_id) AS rating
                          FROM authors a JOIN book_authors ba USING (author_id)
                          LEFT JOIN loans l ON l.book_id = ba.book_id
                          GROUP BY a.author_id ORDER BY loans DESC, author LIMIT 8""")
    genres = db.query("SELECT * FROM v_genre_statistics ORDER BY loans_count DESC, genre")
    return render_template("stats.html", top_books=top_books, monthly=monthly, authors=authors, genres=genres)


# ----------------------------------------------------------------------
# Адміністрування: журнал операцій та користувачі
# ----------------------------------------------------------------------
@app.route("/admin/logs")
@roles_required("admin")
def audit_logs():
    filters = {k: (request.args.get(k) or "").strip() for k in ("table", "operation", "user")}
    page = max(1, request.args.get("page", 1, type=int))
    where = """(%(table)s = '' OR table_name = %(table)s) AND (%(operation)s = '' OR operation = %(operation)s)
               AND (%(user)s = '' OR changed_by = %(user)s)"""
    total = db.scalar(f"SELECT COUNT(*) FROM audit_log WHERE {where}", filters)
    logs = db.query(f"""SELECT * FROM audit_log WHERE {where} ORDER BY log_id DESC
                        LIMIT {PER_PAGE * 2} OFFSET %(offset)s""", {**filters, "offset": (page - 1) * PER_PAGE * 2})
    options = db.query_one("""SELECT ARRAY(SELECT DISTINCT table_name FROM audit_log WHERE table_name IS NOT NULL ORDER BY 1) AS tables,
                                     ARRAY(SELECT DISTINCT operation FROM audit_log ORDER BY 1) AS operations,
                                     ARRAY(SELECT DISTINCT changed_by FROM audit_log ORDER BY 1) AS users""")
    pager = {"page": page, "pages": max(1, math.ceil(total / (PER_PAGE * 2))), "total": total}
    return render_template("admin/logs.html", logs=logs, filters=filters, options=options, pager=pager)


@app.route("/admin/users", methods=["GET", "POST"])
@roles_required("admin")
def users_admin():
    if request.method == "POST":
        user_id = request.form.get("user_id", type=int)
        role = request.form.get("role")
        active = request.form.get("is_active") == "on"
        if user_id == session["user_id"]:
            flash("Не можна змінювати власну роль чи блокувати себе", "danger")
        elif role not in ROLE_NAMES:
            flash("Невідома роль", "danger")
        else:
            db.execute("UPDATE app_users SET role = %s, is_active = %s WHERE user_id = %s", (role, active, user_id))
            flash("Права користувача оновлено", "success")
        return redirect(url_for("users_admin"))
    users = db.query("""SELECT u.user_id, u.username, u.role, u.full_name, u.is_active, u.created_at, u.last_login,
                               r.ticket_number
                        FROM app_users u LEFT JOIN readers r USING (reader_id) ORDER BY u.user_id""")
    return render_template("admin/users.html", users=users)


if __name__ == "__main__":
    app.run(host="127.0.0.1", port=int(os.getenv("PORT", "5000")), debug=os.getenv("FLASK_DEBUG") == "1")
