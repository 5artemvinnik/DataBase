"""Аутентифікація та розмежування прав доступу.

Ролі:
    admin     — повний доступ, керування користувачами, журнал, резервні копії;
    librarian — каталог, читачі, видачі, бронювання, звіти, статистика;
    reader    — перегляд каталогу, власні видачі та бронювання, відгуки.
"""
from datetime import datetime
from functools import wraps

from flask import Blueprint, abort, flash, redirect, render_template, request, session, url_for
from werkzeug.security import check_password_hash, generate_password_hash

import database as db
from validators import validate_registration

bp = Blueprint("auth", __name__)

ROLE_NAMES = {"admin": "Адміністратор", "librarian": "Бібліотекар", "reader": "Читач"}

# Захист від підбору пароля: кількість невдалих спроб на логін
_failed_attempts = {}
MAX_ATTEMPTS = 5


def login_required(view):
    """Декоратор: сторінка доступна лише автентифікованим користувачам."""
    @wraps(view)
    def wrapper(*args, **kwargs):
        if "user_id" not in session:
            flash("Увійдіть, щоб продовжити", "warning")
            return redirect(url_for("auth.login", next=request.path))
        return view(*args, **kwargs)
    return wrapper


def roles_required(*roles):
    """Декоратор: доступ лише для вказаних ролей (інакше 403)."""
    def decorator(view):
        @wraps(view)
        @login_required
        def wrapper(*args, **kwargs):
            if session.get("role") not in roles:
                abort(403)
            return view(*args, **kwargs)
        return wrapper
    return decorator


def is_staff():
    return session.get("role") in ("admin", "librarian")


@bp.route("/login", methods=["GET", "POST"])
def login():
    if request.method == "POST":
        username = (request.form.get("username") or "").strip().lower()
        password = request.form.get("password") or ""

        if _failed_attempts.get(username, 0) >= MAX_ATTEMPTS:
            flash("Забагато невдалих спроб. Зверніться до адміністратора.", "danger")
            return render_template("login.html", username=username), 429

        user = db.query_one(
            "SELECT user_id, username, password_hash, role, reader_id, full_name, is_active "
            "FROM app_users WHERE username = %s", (username,))

        if user and user["is_active"] and check_password_hash(user["password_hash"], password):
            _failed_attempts.pop(username, None)
            session.clear()
            session.permanent = True
            session.update(user_id=user["user_id"], username=user["username"], role=user["role"],
                           reader_id=user["reader_id"], full_name=user["full_name"] or user["username"])
            db.execute("UPDATE app_users SET last_login = %s WHERE user_id = %s",
                       (datetime.now(), user["user_id"]))
            db.log_event("LOGIN", f"Успішний вхід ({ROLE_NAMES[user['role']]})", "app_users", user["user_id"])
            flash(f"Вітаємо, {session['full_name']}!", "success")
            next_url = request.args.get("next")
            # дозволяємо перенаправлення лише на внутрішні адреси
            if not next_url or not next_url.startswith("/") or next_url.startswith("//"):
                next_url = url_for("index")
            return redirect(next_url)

        _failed_attempts[username] = _failed_attempts.get(username, 0) + 1
        db.log_event("LOGIN_FAIL", f"Невдала спроба входу для «{username}»")
        flash("Невірний логін або пароль", "danger")
        return render_template("login.html", username=username), 401

    return render_template("login.html")


@bp.route("/logout")
def logout():
    if "user_id" in session:
        db.log_event("LOGOUT", "Вихід із системи", "app_users", session["user_id"])
    session.clear()
    flash("Ви вийшли з системи", "info")
    return redirect(url_for("auth.login"))


@bp.route("/register", methods=["GET", "POST"])
def register():
    """Реєстрація читача: створюються записи в readers та app_users в одній транзакції."""
    form, errors = {}, {}
    if request.method == "POST":
        form, errors = validate_registration(request.form)
        if not errors:
            try:
                with db.transaction() as cur:
                    cur.execute(
                        """INSERT INTO readers (ticket_number, first_name, last_name, email, phone, birth_date, address)
                           VALUES ((SELECT 'LIB-' || LPAD((COALESCE(MAX(SUBSTRING(ticket_number FROM 5)::INT), 0) + 1)::TEXT, 4, '0')
                                    FROM readers),
                                   %(first_name)s, %(last_name)s, %(email)s, %(phone)s, %(birth_date)s, %(address)s)
                           RETURNING reader_id, ticket_number""", form)
                    reader = cur.fetchone()
                    cur.execute(
                        """INSERT INTO app_users (username, password_hash, role, reader_id, full_name)
                           VALUES (%s, %s, 'reader', %s, %s)""",
                        (form["username"], generate_password_hash(form["password"], method="pbkdf2:sha256:200000"),
                         reader["reader_id"], f"{form['first_name']} {form['last_name']}"))
                flash(f"Реєстрація успішна! Ваш читацький квиток: {reader['ticket_number']}. Увійдіть у систему.",
                      "success")
                return redirect(url_for("auth.login"))
            except db.DatabaseError as exc:
                if "username" in str(exc):
                    errors["username"] = "Такий логін уже зайнятий"
                elif "email" in str(exc):
                    errors["email"] = "Цей email уже зареєстровано"
                else:
                    flash(str(exc), "danger")
    return render_template("register.html", form=form, errors=errors)
