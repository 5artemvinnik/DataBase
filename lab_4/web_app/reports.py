"""Генерація звітів у форматах Excel (openpyxl) та PDF (reportlab)."""
import io
import os
from datetime import datetime

from flask import Blueprint, abort, render_template, send_file
from openpyxl import Workbook
from openpyxl.styles import Alignment, Border, Font, PatternFill, Side
from openpyxl.utils import get_column_letter
from reportlab.lib import colors
from reportlab.lib.pagesizes import A4, landscape
from reportlab.lib.styles import ParagraphStyle
from reportlab.lib.units import mm
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.platypus import Paragraph, SimpleDocTemplate, Spacer, Table, TableStyle

import database as db
from auth import roles_required

bp = Blueprint("reports", __name__, url_prefix="/reports")

# Шрифт з підтримкою кирилиці для PDF
FONT_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "static", "fonts")
pdfmetrics.registerFont(TTFont("LibSans", os.path.join(FONT_DIR, "LiberationSans-Regular.ttf")))
pdfmetrics.registerFont(TTFont("LibSans-Bold", os.path.join(FONT_DIR, "LiberationSans-Bold.ttf")))

# Опис звітів: назва, SQL, заголовки колонок
REPORTS = {
    "catalog": {
        "title": "Каталог книг бібліотеки",
        "sql": """SELECT book_id, title, authors, genre, publisher, publish_year, price,
                         available_copies || ' / ' || total_copies, COALESCE(avg_rating::TEXT, '—'), times_borrowed
                  FROM v_books_catalog ORDER BY title""",
        "headers": ["ID", "Назва", "Автори", "Жанр", "Видавництво", "Рік", "Ціна, грн", "Наявн.", "Рейтинг", "Видач"],
    },
    "debtors": {
        "title": "Боржники: прострочені видачі",
        "sql": """SELECT ticket_number, reader_name, phone, title, loan_date, due_date, days_overdue, expected_fine
                  FROM v_active_loans WHERE state = 'overdue' ORDER BY days_overdue DESC""",
        "headers": ["Квиток", "Читач", "Телефон", "Книга", "Видано", "Термін", "Днів простр.", "Штраф, грн"],
    },
    "readers": {
        "title": "Статистика читачів",
        "sql": """SELECT ticket_number, reader_name, email, total_loans, books_on_hand, overdue_now, total_fines,
                         CASE WHEN is_active THEN 'активний' ELSE 'заблокований' END
                  FROM v_reader_statistics ORDER BY total_loans DESC, reader_name""",
        "headers": ["Квиток", "Читач", "Email", "Усього видач", "На руках", "Простр.", "Штрафи, грн", "Статус"],
    },
    "genres": {
        "title": "Аналітика за жанрами",
        "sql": """SELECT genre, books_count, copies_count, loans_count, COALESCE(avg_rating::TEXT, '—')
                  FROM v_genre_statistics ORDER BY loans_count DESC, genre""",
        "headers": ["Жанр", "Книг", "Примірників", "Видач", "Середній рейтинг"],
    },
}


def _rows(name):
    report = REPORTS.get(name) or abort(404)
    rows = [list(r.values()) for r in db.query(report["sql"])]
    return report, rows


def build_excel(name):
    report, rows = _rows(name)
    wb = Workbook()
    ws = wb.active
    ws.title = name
    ws.append([report["title"]])
    ws.append([f"Сформовано: {datetime.now():%d.%m.%Y %H:%M}"])
    ws.append([])
    ws.append(report["headers"])
    for row in rows:
        ws.append([float(v) if hasattr(v, "as_tuple") else v for v in row])   # Decimal -> число

    ws["A1"].font = Font(size=14, bold=True)
    thin = Side(style="thin", color="999999")
    header_fill = PatternFill("solid", fgColor="2F5597")
    for cell in ws[4]:
        cell.font = Font(bold=True, color="FFFFFF")
        cell.fill = header_fill
        cell.alignment = Alignment(horizontal="center", vertical="center", wrap_text=True)
    for row in ws.iter_rows(min_row=4, max_row=ws.max_row):
        for cell in row:
            cell.border = Border(top=thin, bottom=thin, left=thin, right=thin)
    for idx, header in enumerate(report["headers"], 1):
        width = max([len(str(header)) + 4] + [len(str(r[idx - 1])) for r in rows]) + 2
        ws.column_dimensions[get_column_letter(idx)].width = min(width, 45)
    ws.freeze_panes = "A5"
    # друк: альбомна орієнтація, усі колонки на ширину однієї сторінки
    ws.page_setup.orientation = "landscape"
    ws.page_setup.paperSize = ws.PAPERSIZE_A4
    ws.sheet_properties.pageSetUpPr.fitToPage = True
    ws.page_setup.fitToWidth = 1
    ws.page_setup.fitToHeight = 0
    ws.auto_filter.ref = f"A4:{get_column_letter(len(report['headers']))}{ws.max_row}"

    buffer = io.BytesIO()
    wb.save(buffer)
    buffer.seek(0)
    return buffer


def build_pdf(name):
    report, rows = _rows(name)
    buffer = io.BytesIO()
    doc = SimpleDocTemplate(buffer, pagesize=landscape(A4), leftMargin=12 * mm, rightMargin=12 * mm,
                            topMargin=12 * mm, bottomMargin=12 * mm, title=report["title"])
    title_style = ParagraphStyle("t", fontName="LibSans-Bold", fontSize=16, leading=20, spaceBefore=2, spaceAfter=6)
    small = ParagraphStyle("s", fontName="LibSans", fontSize=9, textColor=colors.grey)
    cell_style = ParagraphStyle("c", fontName="LibSans", fontSize=8, leading=10)

    data = [[Paragraph(f"<b>{h}</b>", ParagraphStyle("h", parent=cell_style, fontName="LibSans-Bold",
                                                      textColor=colors.white)) for h in report["headers"]]]
    data += [[Paragraph("—" if v is None else str(v), cell_style) for v in row] for row in rows]
    # ширина колонок пропорційна довжині вмісту (заголовок або найдовше значення, не більше 40 символів)
    weights = [max(8, len(h), *(min(len(str(r[i])), 40) for r in rows)) if rows else max(8, len(h))
               for i, h in enumerate(report["headers"])]
    available = landscape(A4)[0] - 24 * mm
    table = Table(data, repeatRows=1, colWidths=[available * w / sum(weights) for w in weights])
    table.setStyle(TableStyle([
        ("BACKGROUND", (0, 0), (-1, 0), colors.HexColor("#2F5597")),
        ("GRID", (0, 0), (-1, -1), 0.4, colors.HexColor("#999999")),
        ("ROWBACKGROUNDS", (0, 1), (-1, -1), [colors.white, colors.HexColor("#EEF2F9")]),
        ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
    ]))
    story = [Paragraph("Електронна бібліотека", small), Paragraph(report["title"], title_style),
             Paragraph(f"Сформовано: {datetime.now():%d.%m.%Y %H:%M} · записів: {len(rows)}", small),
             Spacer(1, 6 * mm), table]
    doc.build(story)
    buffer.seek(0)
    return buffer


@bp.route("/")
@roles_required("admin", "librarian")
def index():
    return render_template("reports.html", reports=REPORTS)


@bp.route("/<name>.<fmt>")
@roles_required("admin", "librarian")
def download(name, fmt):
    if fmt == "xlsx":
        buffer, mime = build_excel(name), "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
    elif fmt == "pdf":
        buffer, mime = build_pdf(name), "application/pdf"
    else:
        abort(404)
    db.log_event("REPORT", f"Згенеровано звіт «{REPORTS[name]['title']}» ({fmt.upper()})")
    filename = f"{name}_{datetime.now():%Y%m%d_%H%M}.{fmt}"
    return send_file(buffer, mimetype=mime, as_attachment=True, download_name=filename)
