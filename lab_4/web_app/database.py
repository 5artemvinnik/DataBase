"""Шар доступу до даних вебзастосунку.

Використовується пул з'єднань psycopg2. Кожен виклик query()/execute()
виконується в окремій транзакції; перед запитом у сесію передається ім'я
поточного користувача (app.username), яке записують тригери аудиту.
"""
import os
from contextlib import contextmanager

import psycopg2
import psycopg2.extras
import psycopg2.pool
from flask import g, has_request_context, session

DB_CONFIG = {
    "host": os.getenv("DB_HOST", "localhost"),
    "port": int(os.getenv("DB_PORT", "5432")),
    "dbname": os.getenv("DB_NAME", "library"),
    "user": os.getenv("DB_USER", "postgres"),
    "password": os.getenv("DB_PASSWORD", "password"),
}

_pool = None


class DatabaseError(Exception):
    """Помилка БД з повідомленням, яке можна показати користувачу."""


def get_pool():
    """Лінива ініціалізація пулу з'єднань."""
    global _pool
    if _pool is None:
        _pool = psycopg2.pool.ThreadedConnectionPool(1, 10, **DB_CONFIG)
    return _pool


def _current_username():
    if has_request_context():
        return getattr(g, "api_user", None) or session.get("username") or "anonymous"
    return "system"


@contextmanager
def transaction():
    """Контекстний менеджер транзакції: COMMIT при успіху, ROLLBACK при помилці."""
    conn = get_pool().getconn()
    try:
        with conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
            cur.execute("SELECT set_config('app.username', %s, true)", (_current_username(),))
            yield cur
        conn.commit()
    except psycopg2.Error as exc:
        conn.rollback()
        message = exc.diag.message_primary if exc.diag and exc.diag.message_primary else str(exc)
        raise DatabaseError(_humanize(exc, message)) from exc
    except Exception:
        conn.rollback()
        raise
    finally:
        get_pool().putconn(conn)


def _humanize(exc, message):
    """Перекладає типові помилки обмежень цілісності на зрозумілу мову."""
    code = getattr(exc, "pgcode", None)
    constraint = getattr(exc.diag, "constraint_name", None) if exc.diag else None
    if code == "23505":
        return f"Запис з таким значенням уже існує ({constraint})"
    if code == "23503":
        return "Операцію заборонено: запис пов'язаний з іншими даними (зовнішній ключ)"
    if code == "23514":
        return f"Дані не пройшли перевірку обмеження {constraint}"
    return message


def query(sql, params=None):
    """SELECT -> список словників."""
    with transaction() as cur:
        cur.execute(sql, params)
        return cur.fetchall()


def query_one(sql, params=None):
    """SELECT -> один рядок або None."""
    with transaction() as cur:
        cur.execute(sql, params)
        return cur.fetchone()


def scalar(sql, params=None):
    """SELECT -> одне значення."""
    row = query_one(sql, params)
    return next(iter(row.values())) if row else None


def execute(sql, params=None):
    """INSERT/UPDATE/DELETE -> кількість змінених рядків."""
    with transaction() as cur:
        cur.execute(sql, params)
        return cur.rowcount


def log_event(operation, details, table_name=None, record_id=None):
    """Записує подію застосунку (вхід, звіт, резервна копія) в журнал audit_log."""
    execute(
        """INSERT INTO audit_log (table_name, operation, record_id, details, changed_by)
           VALUES (%s, %s, %s, %s, %s)""",
        (table_name, operation, record_id, details, _current_username()),
    )
