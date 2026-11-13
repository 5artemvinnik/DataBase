#!/usr/bin/env python3
"""Моніторинг продуктивності PostgreSQL для бази «Електронна бібліотека» (рівень 3).

Звіт містить:
  1. загальний стан сервера (розмір БД, підключення, cache hit ratio, транзакції);
  2. таблиці: розмір, «мертві» рядки, частку звернень через індекси;
  3. використання індексів і невикористані індекси;
  4. найповільніші запити (розширення pg_stat_statements);
  5. довгі запити та блокування в цей момент;
  6. автоматичні рекомендації.

Приклади:
  python monitor.py                       # звіт у термінал
  python monitor.py --top 5 --markdown ../docs/monitoring_report.md
  python monitor.py --watch 30            # оновлювати кожні 30 секунд
  python monitor.py --reset               # обнулити статистику перед навантаженням
"""
import argparse
import os
import sys
import time
from datetime import datetime

import psycopg2
import psycopg2.extras

# ---------------------------------------------------------------- SQL-запити

SQL_OVERVIEW = """
SELECT current_database()                                         AS db,
       split_part(version(), ' on ', 1)                           AS version,
       pg_size_pretty(pg_database_size(current_database()))       AS db_size,
       date_trunc('second', now() - pg_postmaster_start_time())   AS uptime,
       (SELECT count(*) FROM pg_stat_activity WHERE datname = current_database()) AS connections,
       current_setting('max_connections')::int                    AS max_connections,
       round(100.0 * blks_hit / nullif(blks_hit + blks_read, 0), 2)  AS cache_hit_pct,
       xact_commit, xact_rollback,
       round(100.0 * xact_rollback / nullif(xact_commit + xact_rollback, 0), 2) AS rollback_pct,
       deadlocks, temp_files, pg_size_pretty(temp_bytes)          AS temp_size
FROM pg_stat_database WHERE datname = current_database()
"""

SQL_TABLES = """
SELECT relname                                                     AS table,
       n_live_tup                                                  AS live,
       n_dead_tup                                                  AS dead,
       round(100.0 * n_dead_tup / nullif(n_live_tup + n_dead_tup, 0), 1) AS dead_pct,
       seq_scan, idx_scan,
       round(100.0 * idx_scan / nullif(seq_scan + idx_scan, 0), 1) AS idx_pct,
       pg_size_pretty(pg_total_relation_size(relid))               AS total_size,
       coalesce(greatest(last_vacuum, last_autovacuum)::timestamp(0)::text, '—')   AS last_vacuum,
       coalesce(greatest(last_analyze, last_autoanalyze)::timestamp(0)::text, '—') AS last_analyze
FROM pg_stat_user_tables
ORDER BY pg_total_relation_size(relid) DESC
LIMIT %(top)s
"""

SQL_INDEXES = """
SELECT s.relname AS table, s.indexrelname AS index, s.idx_scan AS scans,
       s.idx_tup_read AS tup_read, s.idx_tup_fetch AS tup_fetch,
       pg_size_pretty(pg_relation_size(s.indexrelid)) AS size,
       pg_relation_size(s.indexrelid) AS bytes,
       i.indisunique AS is_unique, i.indisprimary AS is_pk,
       i.indpred IS NOT NULL AS is_partial
FROM pg_stat_user_indexes s
JOIN pg_index i ON i.indexrelid = s.indexrelid
ORDER BY s.idx_scan DESC
"""

SQL_SLOW = """
SELECT calls,
       round(total_exec_time::numeric, 1)                          AS total_ms,
       round(mean_exec_time::numeric, 2)                           AS mean_ms,
       round(max_exec_time::numeric, 2)                            AS max_ms,
       rows,
       round((100.0 * total_exec_time / nullif(sum(total_exec_time) OVER (), 0))::numeric, 1) AS pct_total,
       round(100.0 * shared_blks_hit / nullif(shared_blks_hit + shared_blks_read, 0), 1) AS hit_pct,
       regexp_replace(query, '\\s+', ' ', 'g')                     AS query
FROM pg_stat_statements
WHERE dbid = (SELECT oid FROM pg_database WHERE datname = current_database())
  AND query !~* '^\\s*(BEGIN|COMMIT|ROLLBACK|SET|SHOW|RESET|DISCARD|ANALYZE|VACUUM|REINDEX|CREATE|DROP|ALTER)'
  AND query !~* 'pg_stat_|pg_catalog|pg_index|pg_database'      -- без запитів самого моніторингу
ORDER BY mean_exec_time DESC
LIMIT %(top)s
"""

SQL_ACTIVITY = """
SELECT pid, usename AS user, state,
       date_trunc('second', now() - query_start) AS duration,
       wait_event_type, left(regexp_replace(query, '\\s+', ' ', 'g'), 70) AS query
FROM pg_stat_activity
WHERE datname = current_database() AND pid <> pg_backend_pid()
  AND state <> 'idle' AND now() - query_start > interval '%(long)s seconds'
ORDER BY query_start
"""

SQL_LOCKS = """
SELECT blocked.pid AS blocked_pid, blocked.usename AS blocked_user,
       blocking.pid AS blocking_pid, blocking.usename AS blocking_user,
       left(blocked.query, 60) AS blocked_query
FROM pg_stat_activity blocked
JOIN pg_stat_activity blocking ON blocking.pid = ANY (pg_blocking_pids(blocked.pid))
"""

SQL_MAINTENANCE = """
SELECT run_id, max(executed_at)::timestamp(0) AS finished,
       max(duration_ms) FILTER (WHERE operation = 'TOTAL') AS total_ms,
       string_agg(DISTINCT operation, ', ') FILTER (WHERE operation <> 'TOTAL') AS operations
FROM maintenance_log GROUP BY run_id ORDER BY run_id DESC LIMIT 3
"""

# ---------------------------------------------------------------- виведення

USE_COLOR = sys.stdout.isatty()
C = {"h": "\033[1;36m", "w": "\033[33m", "e": "\033[31m", "ok": "\033[32m", "dim": "\033[2m", "0": "\033[0m"}


def color(text, kind):
    return f"{C[kind]}{text}{C['0']}" if USE_COLOR else text


def shorten(value, width):
    text = "—" if value is None else str(value)
    return text if len(text) <= width else text[: width - 1] + "…"


def table(rows, columns, widths=None):
    """Друк таблиці: columns — список (ключ, заголовок, ширина|None, вирівнювання)."""
    if not rows:
        print(color("  (немає даних)", "dim"))
        return
    cols = []
    for key, title, width, align in columns:
        w = width or max(len(title), *(len(shorten(r[key], 200)) for r in rows))
        cols.append((key, title, w, align))
    line = "  " + " │ ".join(t.ljust(w) if a == "<" else t.rjust(w) for _, t, w, a in cols)
    print(color(line, "h"))
    print("  " + "─┼─".join("─" * w for *_, w, _ in cols))
    for r in rows:
        print("  " + " │ ".join(shorten(r[k], w).ljust(w) if a == "<" else shorten(r[k], w).rjust(w)
                                for k, _, w, a in cols))


def section(title):
    print()
    print(color(f"■ {title}", "h"))


class Report:
    """Збирає дані один раз і вміє вивести їх у термінал або Markdown."""

    def __init__(self, conn, top, long_seconds):
        cur = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)
        params = {"top": top, "long": long_seconds}
        cur.execute(SQL_OVERVIEW)
        self.overview = cur.fetchone()
        cur.execute(SQL_TABLES, params)
        self.tables = cur.fetchall()
        cur.execute(SQL_INDEXES)
        self.indexes = cur.fetchall()
        cur.execute("SELECT 1 FROM pg_extension WHERE extname = 'pg_stat_statements'")
        self.has_pss = cur.fetchone() is not None
        self.slow = []
        if self.has_pss:
            cur.execute(SQL_SLOW, params)
            self.slow = cur.fetchall()
        cur.execute(SQL_ACTIVITY % params)
        self.activity = cur.fetchall()
        cur.execute(SQL_LOCKS)
        self.locks = cur.fetchall()
        cur.execute("SELECT to_regclass('maintenance_log') IS NOT NULL AS ok")
        self.maintenance = []
        if cur.fetchone()["ok"]:
            cur.execute(SQL_MAINTENANCE)
            self.maintenance = cur.fetchall()
        self.unused = [i for i in self.indexes
                       if i["scans"] == 0 and not i["is_unique"] and not i["is_pk"]]
        self.recommendations = self._recommend()

    def _recommend(self):
        rec = []
        o = self.overview
        if o["cache_hit_pct"] is not None and o["cache_hit_pct"] < 99:
            rec.append(("w", f"Cache hit ratio {o['cache_hit_pct']}% < 99%: збільшити shared_buffers "
                             "або перевірити запити з великою кількістю читань з диска"))
        for t in self.tables:
            if t["dead_pct"] and t["dead_pct"] > 10:
                rec.append(("w", f"Таблиця {t['table']}: {t['dead_pct']}% мертвих рядків — "
                                 "виконати VACUUM / scripts/maintenance.sh"))
            if t["live"] > 10000 and t["seq_scan"] > 100 and t["idx_pct"] is not None and t["idx_pct"] < 80:
                rec.append(("w", f"Таблиця {t['table']} ({t['live']} рядків): {t['seq_scan']} повних "
                                 f"сканувань, лише {t['idx_pct']}% звернень через індекси — знайти запит "
                                 "з Seq Scan і додати індекс"))
        if self.unused:
            total = sum(i["bytes"] for i in self.unused) / 1024 / 1024
            rec.append(("w", f"{len(self.unused)} індексів ({total:.1f} MB) не використовувались з моменту "
                             "скидання статистики. Кожен сповільнює INSERT/UPDATE; перед видаленням "
                             "переконатися, що вони не потрібні рідкісним звітам"))
        for q in self.slow:
            if q["mean_ms"] and q["mean_ms"] > 100:
                rec.append(("e", f"Повільний запит ({q['mean_ms']} мс у середньому, {q['calls']} викл.): "
                                 f"{shorten(q['query'], 70)} — проаналізувати EXPLAIN ANALYZE"))
        if self.locks:
            rec.append(("e", f"Заблоковано процесів: {len(self.locks)}"))
        if not self.has_pss:
            rec.append(("w", "Розширення pg_stat_statements не встановлено — немає статистики запитів"))
        if not rec:
            rec.append(("ok", "Проблем не виявлено"))
        return rec

    # ------------------------------------------------------------ термінал
    def print(self):
        o = self.overview
        print(color(f"Моніторинг PostgreSQL · {datetime.now():%d.%m.%Y %H:%M:%S}", "h"))
        section("1. Загальний стан")
        hit = o["cache_hit_pct"]
        hit_txt = color(f"{hit}%", "ok" if hit and hit >= 99 else "w")
        print(f"  База: {o['db']} · {o['version']} · розмір {o['db_size']} · працює {o['uptime']}")
        print(f"  Підключень: {o['connections']}/{o['max_connections']} · cache hit ratio: {hit_txt}")
        print(f"  Транзакцій: {o['xact_commit']} commit / {o['xact_rollback']} rollback "
              f"({o['rollback_pct']}%) · deadlocks: {o['deadlocks']} · тимчасові файли: "
              f"{o['temp_files']} ({o['temp_size']})")

        section("2. Таблиці (за розміром)")
        table(self.tables, [("table", "Таблиця", None, "<"), ("live", "Рядків", None, ">"),
                            ("dead_pct", "Мертвих %", None, ">"), ("seq_scan", "Seq scan", None, ">"),
                            ("idx_scan", "Idx scan", None, ">"), ("idx_pct", "Через індекс %", None, ">"),
                            ("total_size", "Розмір", None, ">"), ("last_analyze", "ANALYZE", None, "<")])

        section("3. Використання індексів (топ за кількістю сканувань)")
        top_idx = [dict(i, kind=("PK" if i["is_pk"] else "UNIQUE" if i["is_unique"] else
                                 "частковий" if i["is_partial"] else ""))
                   for i in self.indexes[:12]]
        table(top_idx, [("index", "Індекс", None, "<"), ("table", "Таблиця", None, "<"),
                        ("scans", "Сканувань", None, ">"), ("tup_read", "Прочитано", None, ">"),
                        ("size", "Розмір", None, ">"), ("kind", "Тип", None, "<")])
        print(color(f"  Невикористаних індексів (без PK/UNIQUE): {len(self.unused)}", "w" if self.unused else "ok"))
        for i in self.unused[:6]:
            print(f"    · {i['index']} на {i['table']} ({i['size']})")
        if len(self.unused) > 6:
            print(f"    · … ще {len(self.unused) - 6} (повний список: --markdown)")

        section("4. Найповільніші запити (pg_stat_statements, середній час)")
        table(self.slow, [("mean_ms", "Сер., мс", None, ">"), ("max_ms", "Макс., мс", None, ">"),
                          ("calls", "Викликів", None, ">"), ("pct_total", "% часу", None, ">"),
                          ("hit_pct", "Кеш %", None, ">"), ("query", "Запит", 62, "<")])

        section("5. Довгі запити та блокування зараз")
        if not self.activity and not self.locks:
            print(color("  Довгих запитів і блокувань немає", "ok"))
        table(self.activity, [("pid", "PID", None, ">"), ("user", "Користувач", None, "<"),
                              ("duration", "Триває", None, "<"), ("query", "Запит", 60, "<")]) if self.activity else None
        table(self.locks, [("blocked_pid", "Заблок. PID", None, ">"), ("blocking_pid", "Блокує PID", None, ">"),
                           ("blocked_query", "Запит", 60, "<")]) if self.locks else None
        if self.maintenance:
            last = self.maintenance[0]
            print(f"  Останнє обслуговування: № {last['run_id']} о {last['finished']} "
                  f"({last['total_ms']} мс): {last['operations']}")

        section("6. Рекомендації")
        for kind, text in self.recommendations:
            mark = {"ok": "✔", "w": "!", "e": "✖"}[kind]
            print("  " + color(f"{mark} {text}", kind))
        print()

    # ------------------------------------------------------------ Markdown
    def markdown(self, path):
        o = self.overview

        def md_table(rows, cols):
            if not rows:
                return "_немає даних_\n"
            out = ["| " + " | ".join(t for _, t in cols) + " |", "|" + "---|" * len(cols)]
            for r in rows:
                out.append("| " + " | ".join(shorten(r[k], 90).replace("|", "\\|") for k, _ in cols) + " |")
            return "\n".join(out) + "\n"

        text = [f"# Звіт моніторингу PostgreSQL\n",
                f"Сформовано: {datetime.now():%d.%m.%Y %H:%M:%S}\n",
                "## 1. Загальний стан\n",
                f"* База **{o['db']}**, {o['version']}, розмір {o['db_size']}, працює {o['uptime']}",
                f"* Підключень: {o['connections']} з {o['max_connections']}",
                f"* Cache hit ratio: **{o['cache_hit_pct']}%**",
                f"* Транзакцій: {o['xact_commit']} commit / {o['xact_rollback']} rollback, deadlocks: {o['deadlocks']}\n",
                "## 2. Таблиці\n",
                md_table(self.tables, [("table", "Таблиця"), ("live", "Рядків"), ("dead_pct", "Мертвих %"),
                                       ("seq_scan", "Seq scan"), ("idx_scan", "Idx scan"),
                                       ("idx_pct", "Через індекс %"), ("total_size", "Розмір")]),
                "## 3. Індекси\n",
                md_table(self.indexes, [("index", "Індекс"), ("table", "Таблиця"), ("scans", "Сканувань"),
                                        ("tup_read", "Прочитано"), ("size", "Розмір")]),
                f"Невикористаних індексів: **{len(self.unused)}** "
                + ", ".join(f"`{i['index']}`" for i in self.unused) + "\n",
                "## 4. Найповільніші запити\n",
                md_table(self.slow, [("mean_ms", "Сер., мс"), ("max_ms", "Макс., мс"), ("calls", "Викликів"),
                                     ("pct_total", "% часу"), ("query", "Запит")]),
                "## 5. Рекомендації\n"]
        text += [f"* {t}" for _, t in self.recommendations]
        with open(path, "w", encoding="utf-8") as f:
            f.write("\n".join(text) + "\n")
        print(color(f"Markdown-звіт збережено: {path}", "ok"))


def main():
    p = argparse.ArgumentParser(description="Моніторинг продуктивності PostgreSQL")
    p.add_argument("--host", default=os.getenv("DB_HOST", "localhost"))
    p.add_argument("--port", type=int, default=int(os.getenv("DB_PORT", "5433")))
    p.add_argument("--db", default=os.getenv("DB_NAME", "library"))
    p.add_argument("--user", default=os.getenv("DB_USER", "postgres"))
    p.add_argument("--password", default=os.getenv("DB_PASSWORD", "password"))
    p.add_argument("--top", type=int, default=8, help="скільки рядків показувати в рейтингах")
    p.add_argument("--long", type=int, default=60, help="поріг «довгого» запиту, секунд")
    p.add_argument("--markdown", metavar="FILE", help="також зберегти звіт у Markdown")
    p.add_argument("--watch", type=int, metavar="SEC", help="оновлювати звіт кожні SEC секунд")
    p.add_argument("--reset", action="store_true", help="обнулити статистику і вийти")
    args = p.parse_args()

    try:
        conn = psycopg2.connect(host=args.host, port=args.port, dbname=args.db,
                                user=args.user, password=args.password,
                                application_name="lab5_monitor")
    except psycopg2.OperationalError as e:
        sys.exit(f"Не вдалося підключитися до БД: {e}")
    conn.autocommit = True

    if args.reset:
        with conn.cursor() as cur:
            cur.execute("SELECT pg_stat_reset()")
            cur.execute("ANALYZE")           # pg_stat_reset обнуляє й кількість рядків — відновлюємо
            cur.execute("SELECT pg_stat_statements_reset()")
        print("Статистику pg_stat_statements та pg_stat_* обнулено")
        return

    while True:
        report = Report(conn, args.top, args.long)
        if args.watch:
            print("\033[2J\033[H", end="")              # очистити екран
        report.print()
        if args.markdown:
            report.markdown(args.markdown)
        if not args.watch:
            break
        time.sleep(args.watch)


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        pass
