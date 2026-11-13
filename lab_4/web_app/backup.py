"""Резервне копіювання та відновлення бази даних (pg_dump / psql).

Якщо pg_dump встановлено на хост-машині — використовується він. Інакше
команда виконується всередині контейнера PostgreSQL через docker або
podman (назва контейнера — змінна BACKUP_CONTAINER, за замовчуванням library_db).

Також доступно з командного рядка:
    python backup.py            — створити резервну копію
    python backup.py --list     — перелік копій
"""
import os
import re
import shutil
import subprocess
import sys
from datetime import datetime

from flask import Blueprint, abort, flash, redirect, render_template, request, send_from_directory, url_for

import database as db
from auth import roles_required

BACKUP_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "backups")
CONTAINER = os.getenv("BACKUP_CONTAINER", "library_db")
NAME_RE = re.compile(r"^library_\d{8}_\d{6}\.sql$")

bp = Blueprint("backup", __name__, url_prefix="/admin/backup")


def _command(tool, *args):
    """Формує команду pg_dump/psql: локально або через контейнер."""
    cfg = db.DB_CONFIG
    if shutil.which(tool):
        env = {**os.environ, "PGPASSWORD": cfg["password"]}
        return [tool, "-h", cfg["host"], "-p", str(cfg["port"]), "-U", cfg["user"], *args, cfg["dbname"]], env
    for engine in ("docker", "podman"):
        if shutil.which(engine):
            return [engine, "exec", "-i", CONTAINER, tool, "-U", cfg["user"], *args, cfg["dbname"]], None
    raise RuntimeError("Не знайдено pg_dump, docker або podman")


def create_backup():
    """Створює SQL-дамп і повертає ім'я файлу."""
    os.makedirs(BACKUP_DIR, exist_ok=True)
    filename = f"library_{datetime.now():%Y%m%d_%H%M%S}.sql"
    cmd, env = _command("pg_dump", "--clean", "--if-exists", "--no-owner", "--encoding=UTF8")
    with open(os.path.join(BACKUP_DIR, filename), "wb") as out:
        result = subprocess.run(cmd, stdin=subprocess.DEVNULL, stdout=out, stderr=subprocess.PIPE, env=env, timeout=120)
    if result.returncode != 0:
        os.remove(os.path.join(BACKUP_DIR, filename))
        raise RuntimeError(result.stderr.decode(errors="replace").strip())
    return filename


def restore_backup(filename):
    """Відновлює базу з дампу (дамп містить DROP ... IF EXISTS, тому БД перезаписується)."""
    cmd, env = _command("psql", "-v", "ON_ERROR_STOP=1", "-q")
    with open(os.path.join(BACKUP_DIR, filename), "rb") as src:
        result = subprocess.run(cmd, stdin=src, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE,
                                env=env, timeout=300)
    if result.returncode != 0:
        raise RuntimeError(result.stderr.decode(errors="replace").strip()[-500:])


def list_backups():
    if not os.path.isdir(BACKUP_DIR):
        return []
    items = []
    for name in sorted(os.listdir(BACKUP_DIR), reverse=True):
        if NAME_RE.match(name):
            path = os.path.join(BACKUP_DIR, name)
            items.append({"name": name, "size_kb": round(os.path.getsize(path) / 1024, 1),
                          "created": datetime.fromtimestamp(os.path.getmtime(path))})
    return items


def _checked(name):
    if not NAME_RE.match(name) or not os.path.exists(os.path.join(BACKUP_DIR, name)):
        abort(404)
    return name


@bp.route("/", methods=["GET", "POST"])
@roles_required("admin")
def index():
    if request.method == "POST":
        try:
            name = create_backup()
            db.log_event("BACKUP", f"Створено резервну копію {name}")
            flash(f"Резервну копію {name} створено", "success")
        except (RuntimeError, OSError, subprocess.TimeoutExpired) as exc:
            flash(f"Помилка резервного копіювання: {exc}", "danger")
        return redirect(url_for("backup.index"))
    return render_template("admin/backup.html", backups=list_backups())


@bp.route("/<name>")
@roles_required("admin")
def download(name):
    return send_from_directory(BACKUP_DIR, _checked(name), as_attachment=True)


@bp.route("/<name>/restore", methods=["POST"])
@roles_required("admin")
def restore(name):
    try:
        restore_backup(_checked(name))
        db.log_event("RESTORE", f"Базу відновлено з копії {name}")
        flash(f"Базу даних відновлено з {name}", "success")
    except (RuntimeError, OSError, subprocess.TimeoutExpired) as exc:
        flash(f"Помилка відновлення: {exc}", "danger")
    return redirect(url_for("backup.index"))


@bp.route("/<name>/delete", methods=["POST"])
@roles_required("admin")
def delete(name):
    os.remove(os.path.join(BACKUP_DIR, _checked(name)))
    flash(f"Копію {name} видалено", "info")
    return redirect(url_for("backup.index"))


if __name__ == "__main__":
    if "--list" in sys.argv:
        for item in list_backups():
            print(f"{item['name']}  {item['size_kb']} КБ  {item['created']:%d.%m.%Y %H:%M}")
    else:
        print("Створено:", create_backup())
