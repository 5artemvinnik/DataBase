"""Графічна візуалізація статистики (matplotlib -> PNG)."""
import io

import matplotlib

matplotlib.use("Agg")                      # рендер без графічного інтерфейсу
import matplotlib.pyplot as plt            # noqa: E402
from flask import Blueprint, abort, send_file  # noqa: E402

import database as db                      # noqa: E402
from auth import roles_required            # noqa: E402

bp = Blueprint("charts", __name__, url_prefix="/charts")

PALETTE = ["#2F5597", "#4E9A6B", "#E0A030", "#C0504D", "#8064A2", "#4BACC6", "#F79646", "#7F7F7F",
           "#9BBB59", "#1F497D"]
plt.rcParams.update({"font.family": "DejaVu Sans", "font.size": 10, "axes.spines.top": False,
                     "axes.spines.right": False})


def _png(fig):
    buffer = io.BytesIO()
    fig.tight_layout()
    fig.savefig(buffer, format="png", dpi=110)
    plt.close(fig)
    buffer.seek(0)
    return send_file(buffer, mimetype="image/png", max_age=0)


def monthly_loans():
    rows = db.query("SELECT TO_CHAR(month, 'MM.YYYY') AS m, loans_count FROM v_monthly_loans")
    fig, ax = plt.subplots(figsize=(7, 3.6))
    months = [r["m"] for r in rows]
    values = [r["loans_count"] for r in rows]
    ax.bar(months, values, color=PALETTE[0])
    ax.plot(months, values, color=PALETTE[2], marker="o")
    for x, y in zip(months, values):
        ax.annotate(str(y), (x, y), textcoords="offset points", xytext=(0, 5), ha="center")
    ax.set_title("Динаміка видач по місяцях")
    ax.set_ylabel("Кількість видач")
    ax.tick_params(axis="x", rotation=45)
    return fig


def genres():
    rows = db.query("SELECT genre, loans_count FROM v_genre_statistics WHERE loans_count > 0 "
                    "ORDER BY loans_count")
    fig, ax = plt.subplots(figsize=(7, 3.6))
    ax.barh([r["genre"] for r in rows], [r["loans_count"] for r in rows], color=PALETTE[1])
    ax.set_title("Популярність жанрів (кількість видач)")
    ax.set_xlabel("Видач")
    return fig


def loan_status():
    rows = db.query("""SELECT CASE WHEN return_date IS NOT NULL AND fine_amount = 0 THEN 'Повернено вчасно'
                                   WHEN return_date IS NOT NULL THEN 'Повернено із запізненням'
                                   WHEN due_date < CURRENT_DATE THEN 'Прострочено'
                                   ELSE 'На руках' END AS state, COUNT(*) AS cnt
                       FROM loans GROUP BY 1 ORDER BY 2 DESC""")
    fig, ax = plt.subplots(figsize=(7, 3.6))
    counts = [r["cnt"] for r in rows]
    wedges, _, autotexts = ax.pie(counts, autopct=lambda p: f"{p:.0f}%" if p >= 5 else "",
                                  colors=[PALETTE[1], PALETTE[2], PALETTE[3], PALETTE[0]][: len(rows)],
                                  startangle=90, pctdistance=0.72,
                                  wedgeprops={"linewidth": 1.5, "edgecolor": "white", "width": 0.55})
    for t in autotexts:
        t.set_color("white")
        t.set_fontweight("bold")
    ax.legend(wedges, [f"{r['state']} — {r['cnt']}" for r in rows], loc="center left",
              bbox_to_anchor=(1.0, 0.5), frameon=False)
    ax.set_title("Структура видач")
    ax.axis("equal")
    return fig


def top_books():
    rows = db.query("""SELECT title, times_borrowed, COALESCE(avg_rating, 0) AS rating FROM v_books_catalog
                       ORDER BY times_borrowed DESC, avg_rating DESC NULLS LAST LIMIT 7""")[::-1]
    fig, ax = plt.subplots(figsize=(7, 3.6))
    titles = [r["title"] if len(r["title"]) < 28 else r["title"][:26] + "…" for r in rows]
    bars = ax.barh(titles, [r["times_borrowed"] for r in rows], color=PALETTE[4])
    for bar, r in zip(bars, rows):
        ax.text(bar.get_width() + 0.05, bar.get_y() + bar.get_height() / 2, f"★ {float(r['rating']):.1f}",
                va="center", fontsize=9)
    ax.set_title("ТОП книг за кількістю видач (★ — середній рейтинг)")
    ax.set_xlabel("Видач")
    return fig


CHARTS = {"monthly": monthly_loans, "genres": genres, "status": loan_status, "top": top_books}


@bp.route("/<name>.png")
@roles_required("admin", "librarian")
def chart(name):
    builder = CHARTS.get(name) or abort(404)
    return _png(builder())
