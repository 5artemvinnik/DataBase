"""Модуль роботи з базою даних для консольного застосунку «Електронна бібліотека».

Інкапсулює підключення до PostgreSQL (psycopg2) і надає прості методи
для виконання параметризованих запитів. Усі значення передаються через
параметри (%s), тому SQL-ін'єкції неможливі.
"""
import os

import psycopg2
import psycopg2.extras

# Параметри підключення: беруться зі змінних середовища або за замовчуванням
# відповідають docker-compose.yml
DB_CONFIG = {
    "host": os.getenv("DB_HOST", "localhost"),
    "port": int(os.getenv("DB_PORT", "5432")),
    "dbname": os.getenv("DB_NAME", "library"),
    "user": os.getenv("DB_USER", "postgres"),
    "password": os.getenv("DB_PASSWORD", "password"),
}


class DatabaseError(Exception):
    """Помилка бази даних з зрозумілим для користувача повідомленням."""


class Database:
    """Обгортка над з'єднанням psycopg2."""

    def __init__(self, config=None, app_user="console"):
        self.config = config or DB_CONFIG
        self.app_user = app_user          # ім'я, яке потрапить у журнал аудиту
        self.conn = None

    # --- керування з'єднанням -------------------------------------------
    def connect(self):
        """Відкриває з'єднання з базою даних."""
        try:
            self.conn = psycopg2.connect(**self.config)
        except psycopg2.OperationalError as exc:
            raise DatabaseError(f"Не вдалося підключитися до БД: {exc}".strip()) from exc
        return self

    def close(self):
        """Закриває з'єднання."""
        if self.conn is not None:
            self.conn.close()
            self.conn = None

    def __enter__(self):
        return self.connect()

    def __exit__(self, exc_type, exc, tb):
        self.close()

    def server_version(self):
        """Повертає версію сервера PostgreSQL."""
        return self.fetch_value("SHOW server_version")

    # --- виконання запитів ---------------------------------------------
    def _run(self, sql, params, fetch):
        """Виконує запит в окремій транзакції; при помилці робить ROLLBACK."""
        try:
            with self.conn:                                   # COMMIT або ROLLBACK автоматично
                with self.conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
                    # передаємо користувача в тригери аудиту (лише в межах транзакції)
                    cur.execute("SELECT set_config('app.username', %s, true)", (self.app_user,))
                    cur.execute(sql, params)
                    if fetch == "all":
                        return cur.fetchall()
                    if fetch == "one":
                        return cur.fetchone()
                    return cur.rowcount
        except psycopg2.Error as exc:
            # беремо основне повідомлення СУБД (наприклад, з RAISE EXCEPTION)
            message = exc.diag.message_primary if exc.diag and exc.diag.message_primary else str(exc)
            raise DatabaseError(message) from exc

    def fetch_all(self, sql, params=None):
        """Повертає список рядків (словників)."""
        return self._run(sql, params, "all")

    def fetch_one(self, sql, params=None):
        """Повертає один рядок або None."""
        return self._run(sql, params, "one")

    def fetch_value(self, sql, params=None):
        """Повертає перше значення першого рядка."""
        row = self.fetch_one(sql, params)
        return next(iter(row.values())) if row else None

    def execute(self, sql, params=None):
        """Виконує INSERT/UPDATE/DELETE і повертає кількість змінених рядків."""
        return self._run(sql, params, None)
