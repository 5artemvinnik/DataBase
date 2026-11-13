"""Серверна валідація даних форм.

Кожна функція приймає request.form і повертає кортеж (data, errors):
data — очищені значення для SQL, errors — словник {поле: повідомлення}.
"""
import re
from datetime import date, datetime

ISBN_RE = re.compile(r"^(97[89]-?)?[0-9-]{9,13}[0-9X]$")
EMAIL_RE = re.compile(r"^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$")
PHONE_RE = re.compile(r"^\+?[0-9 ()-]{7,20}$")
USERNAME_RE = re.compile(r"^[a-z0-9_]{3,30}$")


def _text(form, name, errors, label, required=True, max_len=200):
    value = (form.get(name) or "").strip()
    if not value:
        if required:
            errors[name] = f"Поле «{label}» обов'язкове"
        return None
    if len(value) > max_len:
        errors[name] = f"«{label}»: не більше {max_len} символів"
    return value


def _int(form, name, errors, label, required=True, min_value=None, max_value=None):
    raw = (form.get(name) or "").strip()
    if not raw:
        if required:
            errors[name] = f"Поле «{label}» обов'язкове"
        return None
    try:
        value = int(raw)
    except ValueError:
        errors[name] = f"«{label}» має бути цілим числом"
        return None
    if min_value is not None and value < min_value or max_value is not None and value > max_value:
        errors[name] = f"«{label}» має бути в межах {min_value}–{max_value}"
    return value


def _date(form, name, errors, label, required=False):
    raw = (form.get(name) or "").strip()
    if not raw:
        if required:
            errors[name] = f"Поле «{label}» обов'язкове"
        return None
    try:
        return datetime.strptime(raw, "%Y-%m-%d").date()
    except ValueError:
        errors[name] = f"«{label}»: дата у форматі РРРР-ММ-ДД"
        return None


def validate_book(form):
    errors = {}
    year_now = date.today().year
    data = {
        "title": _text(form, "title", errors, "Назва"),
        "isbn": _text(form, "isbn", errors, "ISBN", max_len=17),
        "genre_id": _int(form, "genre_id", errors, "Жанр", min_value=1),
        "publisher_id": _int(form, "publisher_id", errors, "Видавництво", required=False, min_value=1),
        "publish_year": _int(form, "publish_year", errors, "Рік видання", min_value=1450, max_value=year_now),
        "pages": _int(form, "pages", errors, "Сторінок", min_value=1, max_value=10000),
        "language": _text(form, "language", errors, "Мова", required=False, max_len=30) or "українська",
        "total_copies": _int(form, "total_copies", errors, "Примірників", min_value=0, max_value=1000),
        "description": _text(form, "description", errors, "Опис", required=False, max_len=2000),
    }
    if data["isbn"] and not ISBN_RE.match(data["isbn"]):
        errors["isbn"] = "ISBN має формат 978-966-03-1234-5"
    raw_price = (form.get("price") or "").replace(",", ".").strip()
    try:
        data["price"] = round(float(raw_price), 2)
        if data["price"] < 0 or data["price"] > 100000:
            errors["price"] = "Ціна має бути від 0 до 100 000 грн"
    except ValueError:
        errors["price"] = "Ціна має бути числом"
    try:
        data["author_ids"] = sorted({int(a) for a in form.getlist("author_ids")})
    except ValueError:
        data["author_ids"] = []
    if not data["author_ids"]:
        errors["author_ids"] = "Оберіть принаймні одного автора"
    return data, errors


def validate_author(form):
    errors = {}
    year_now = date.today().year
    data = {
        "first_name": _text(form, "first_name", errors, "Ім'я", max_len=50),
        "last_name": _text(form, "last_name", errors, "Прізвище", max_len=50),
        "birth_year": _int(form, "birth_year", errors, "Рік народження", required=False, min_value=1000, max_value=year_now),
        "death_year": _int(form, "death_year", errors, "Рік смерті", required=False, min_value=1000, max_value=year_now),
        "country": _text(form, "country", errors, "Країна", required=False, max_len=50),
        "biography": _text(form, "biography", errors, "Біографія", required=False, max_len=2000),
    }
    if data["birth_year"] and data["death_year"] and data["death_year"] < data["birth_year"]:
        errors["death_year"] = "Рік смерті не може бути раніше року народження"
    return data, errors


def validate_reader(form):
    errors = {}
    data = {
        "first_name": _text(form, "first_name", errors, "Ім'я", max_len=50),
        "last_name": _text(form, "last_name", errors, "Прізвище", max_len=50),
        "email": _text(form, "email", errors, "Email", max_len=100),
        "phone": _text(form, "phone", errors, "Телефон", required=False, max_len=20),
        "birth_date": _date(form, "birth_date", errors, "Дата народження"),
        "address": _text(form, "address", errors, "Адреса", required=False),
        "is_active": form.get("is_active", "on") == "on",
    }
    if data["email"] and not EMAIL_RE.match(data["email"]):
        errors["email"] = "Невірний формат email"
    if data["phone"] and not PHONE_RE.match(data["phone"]):
        errors["phone"] = "Телефон: цифри, пробіли, дужки, від 7 до 20 символів"
    if data["birth_date"] and not (date(1900, 1, 1) < data["birth_date"] <= date.today()):
        errors["birth_date"] = "Дата народження поза допустимим діапазоном"
    return data, errors


def validate_registration(form):
    data, errors = validate_reader(form)
    data["username"] = (form.get("username") or "").strip().lower()
    password = form.get("password") or ""
    if not USERNAME_RE.match(data["username"]):
        errors["username"] = "Логін: 3–30 символів, малі латинські літери, цифри, _"
    if len(password) < 8 or not re.search(r"\d", password) or not re.search(r"[A-Za-zА-Яа-яІіЇїЄє]", password):
        errors["password"] = "Пароль: щонайменше 8 символів, літери та цифри"
    if password != form.get("password2"):
        errors["password2"] = "Паролі не збігаються"
    data["password"] = password
    return data, errors
