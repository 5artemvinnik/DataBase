"""REST API (JSON) для інтеграції з іншими системами. Префікс /api/v1.

Аутентифікація — HTTP Basic (логін/пароль користувача застосунку).
Для GET-запитів також приймається сесія браузера. Операції запису
доступні лише ролям admin та librarian.

Приклади:
    curl -u librarian:lib12345 http://127.0.0.1:5000/api/v1/books?q=жадан
    curl -u librarian:lib12345 -X POST -H "Content-Type: application/json" \
         -d '{"book_id": 3, "reader_id": 2}' http://127.0.0.1:5000/api/v1/loans
"""
from functools import wraps

from flask import Blueprint, g, jsonify, request, session
from werkzeug.datastructures import MultiDict
from werkzeug.security import check_password_hash

import database as db
from validators import validate_book

bp = Blueprint("api", __name__, url_prefix="/api/v1")


def _error(message, status):
    return jsonify({"error": message}), status


def api_auth(*roles):
    """Перевіряє Basic-аутентифікацію (або сесію для GET) і роль."""
    def decorator(view):
        @wraps(view)
        def wrapper(*args, **kwargs):
            role = None
            auth = request.authorization
            if auth and auth.type == "basic":
                user = db.query_one("SELECT username, password_hash, role, is_active FROM app_users "
                                    "WHERE username = %s", (auth.username.lower(),))
                if user and user["is_active"] and check_password_hash(user["password_hash"], auth.password or ""):
                    g.api_user, role = user["username"], user["role"]
            elif request.method == "GET" and "user_id" in session:
                g.api_user, role = session["username"], session["role"]
            if role is None:
                resp = _error("Потрібна аутентифікація", 401)
                resp[0].headers["WWW-Authenticate"] = 'Basic realm="library-api"'
                return resp
            if roles and role not in roles:
                return _error("Недостатньо прав", 403)
            return view(*args, **kwargs)
        return wrapper
    return decorator


@bp.errorhandler(db.DatabaseError)
def api_db_error(exc):
    return _error(str(exc), 409)


@bp.route("/")
def index():
    """Перелік доступних кінцевих точок."""
    return jsonify({
        "name": "Електронна бібліотека API", "version": "1.0",
        "endpoints": {
            "GET /api/v1/books": "каталог (?q=, genre=, available=1, limit=, offset=)",
            "GET /api/v1/books/<id>": "картка книги",
            "POST /api/v1/books": "створити книгу (librarian, admin)",
            "PUT /api/v1/books/<id>": "оновити книгу (librarian, admin)",
            "DELETE /api/v1/books/<id>": "видалити книгу (librarian, admin)",
            "GET /api/v1/genres": "жанри",
            "GET /api/v1/readers": "читачі (librarian, admin)",
            "GET /api/v1/loans/active": "книги на руках (librarian, admin)",
            "POST /api/v1/loans": "видати книгу {book_id, reader_id, days}",
            "POST /api/v1/loans/<id>/return": "повернути книгу",
            "GET /api/v1/stats": "загальна статистика",
        },
    })


@bp.route("/books", methods=["GET"])
@api_auth()
def books():
    limit = min(request.args.get("limit", 50, type=int), 200)
    offset = max(request.args.get("offset", 0, type=int), 0)
    q = (request.args.get("q") or "").lower()
    rows = db.query("""SELECT book_id, title, isbn, authors, genre, publisher, publish_year, price,
                              total_copies, available_copies, avg_rating
                       FROM v_books_catalog
                       WHERE (%(q)s = '' OR LOWER(title) LIKE %(like)s OR LOWER(authors) LIKE %(like)s)
                         AND (%(genre)s IS NULL OR genre_id = %(genre)s)
                         AND (NOT %(available)s OR available_copies > 0)
                       ORDER BY title LIMIT %(limit)s OFFSET %(offset)s""",
                    {"q": q, "like": f"%{q}%", "genre": request.args.get("genre", type=int),
                     "available": request.args.get("available") == "1", "limit": limit, "offset": offset})
    return jsonify({"count": len(rows), "limit": limit, "offset": offset, "items": rows})


@bp.route("/books/<int:book_id>", methods=["GET"])
@api_auth()
def book(book_id):
    row = db.query_one("SELECT * FROM v_books_catalog WHERE book_id = %s", (book_id,))
    return jsonify(row) if row else _error("Книгу не знайдено", 404)


def _book_payload():
    """Перетворює JSON у MultiDict, щоб використати ту саму серверну валідацію, що й у формах."""
    payload = request.get_json(silent=True) or {}
    form = MultiDict({k: str(v) for k, v in payload.items() if k != "author_ids" and v is not None})
    for author_id in payload.get("author_ids", []):
        form.add("author_ids", str(author_id))
    return validate_book(form)


@bp.route("/books", methods=["POST"])
@api_auth("admin", "librarian")
def book_create():
    data, errors = _book_payload()
    if errors:
        return jsonify({"error": "Помилки валідації", "fields": errors}), 422
    with db.transaction() as cur:
        cur.execute("""INSERT INTO books (title, isbn, genre_id, publisher_id, publish_year, pages, language, price,
                                          total_copies, available_copies, description)
                       VALUES (%(title)s, %(isbn)s, %(genre_id)s, %(publisher_id)s, %(publish_year)s, %(pages)s,
                               %(language)s, %(price)s, %(total_copies)s, %(total_copies)s, %(description)s)
                       RETURNING book_id""", data)
        book_id = cur.fetchone()["book_id"]
        for order, author_id in enumerate(data["author_ids"], 1):
            cur.execute("INSERT INTO book_authors VALUES (%s, %s, %s)", (book_id, author_id, order))
    return jsonify(db.query_one("SELECT * FROM v_books_catalog WHERE book_id = %s", (book_id,))), 201


@bp.route("/books/<int:book_id>", methods=["PUT"])
@api_auth("admin", "librarian")
def book_update(book_id):
    data, errors = _book_payload()
    if errors:
        return jsonify({"error": "Помилки валідації", "fields": errors}), 422
    data["book_id"] = book_id
    with db.transaction() as cur:
        cur.execute("""UPDATE books SET title=%(title)s, isbn=%(isbn)s, genre_id=%(genre_id)s,
                           publisher_id=%(publisher_id)s, publish_year=%(publish_year)s, pages=%(pages)s,
                           language=%(language)s, price=%(price)s, total_copies=%(total_copies)s,
                           description=%(description)s
                       WHERE book_id=%(book_id)s""", data)
        if cur.rowcount == 0:
            return _error("Книгу не знайдено", 404)
        cur.execute("DELETE FROM book_authors WHERE book_id = %s", (book_id,))
        for order, author_id in enumerate(data["author_ids"], 1):
            cur.execute("INSERT INTO book_authors VALUES (%s, %s, %s)", (book_id, author_id, order))
    return jsonify(db.query_one("SELECT * FROM v_books_catalog WHERE book_id = %s", (book_id,)))


@bp.route("/books/<int:book_id>", methods=["DELETE"])
@api_auth("admin", "librarian")
def book_delete(book_id):
    if db.execute("DELETE FROM books WHERE book_id = %s", (book_id,)) == 0:
        return _error("Книгу не знайдено", 404)
    return "", 204


@bp.route("/genres")
@api_auth()
def genres():
    return jsonify(db.query("SELECT * FROM v_genre_statistics ORDER BY genre"))


@bp.route("/readers")
@api_auth("admin", "librarian")
def readers():
    return jsonify(db.query("SELECT * FROM v_reader_statistics ORDER BY reader_name"))


@bp.route("/loans/active")
@api_auth("admin", "librarian")
def active_loans():
    return jsonify(db.query("SELECT * FROM v_active_loans ORDER BY due_date"))


@bp.route("/loans", methods=["POST"])
@api_auth("admin", "librarian")
def loan_create():
    payload = request.get_json(silent=True) or {}
    try:
        book_id, reader_id = int(payload["book_id"]), int(payload["reader_id"])
        days = int(payload.get("days", 14))
    except (KeyError, TypeError, ValueError):
        return _error("Потрібні цілі поля book_id і reader_id (days — необов'язкове)", 422)
    loan_id = db.scalar("SELECT issue_book(%s, %s, %s)", (book_id, reader_id, days))
    return jsonify(db.query_one("SELECT * FROM loans WHERE loan_id = %s", (loan_id,))), 201


@bp.route("/loans/<int:loan_id>/return", methods=["POST"])
@api_auth("admin", "librarian")
def loan_return(loan_id):
    fine = db.scalar("SELECT return_book(%s)", (loan_id,))
    return jsonify({"loan_id": loan_id, "returned": True, "fine": float(fine)})


@bp.route("/stats")
@api_auth()
def stats():
    return jsonify(db.query_one(
        """SELECT (SELECT COUNT(*) FROM books) AS books,
                  (SELECT COUNT(*) FROM readers WHERE is_active) AS active_readers,
                  (SELECT COUNT(*) FROM v_active_loans) AS books_on_hand,
                  (SELECT COUNT(*) FROM v_active_loans WHERE state = 'overdue') AS overdue,
                  (SELECT COALESCE(SUM(fine_amount), 0) FROM loans) AS fines_total"""))
