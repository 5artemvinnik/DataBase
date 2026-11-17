"""Крок 20. Порівняльний аналіз реляційного (PostgreSQL) і документного (MongoDB) підходів.

Однаковий набір даних бібліотеки (автори, жанри, 50 000 книг) завантажується:
  * у PostgreSQL — нормалізована схема 3НФ: authors, genres, books, book_genres;
  * у MongoDB — дві моделі:
      emb — денормалізована: автор і жанри вкладені в документ книги;
      ref — посилання: author_id і genre_ids, дані автора в окремій колекції.
Для кожної операції вимірюється медіана часу з кількох запусків.

Запуск з папки lab_6:  .venv/bin/python compare/compare.py
"""
import random
import statistics
import time
from pathlib import Path

import psycopg2
import psycopg2.extras
from pymongo import ASCENDING, MongoClient
from pymongo.errors import PyMongoError

N_AUTHORS, N_BOOKS, RUNS = 2000, 50_000, 15
GENRES = ["роман", "поезія", "повість", "драма", "новела", "фантастика", "детектив", "історична проза",
          "пригоди", "сучасна проза", "наукова література", "дитяча література", "біографія", "есеїстика", "гумор"]
REPORT = Path(__file__).resolve().parent.parent / "docs" / "comparison_results.md"

pg = psycopg2.connect(host="localhost", port=5434, dbname="library", user="postgres", password="password")
pg.autocommit = True
cur = pg.cursor()
mongo = MongoClient("mongodb://localhost:27017/?directConnection=true")
mdb = mongo["compare"]


def median_ms(fn, runs=RUNS):
    fn()                                               # прогрів
    times = []
    for _ in range(runs):
        t = time.perf_counter()
        fn()
        times.append((time.perf_counter() - t) * 1000)
    return round(statistics.median(times), 3)


def once_ms(fn):
    t = time.perf_counter()
    fn()
    return round((time.perf_counter() - t) * 1000, 1)


# ---------------------------------------------------------------- дані
rnd = random.Random(2026)
authors = [(i, f"Автор {i}", rnd.randint(1800, 2000)) for i in range(1, N_AUTHORS + 1)]
books = []
for i in range(1, N_BOOKS + 1):
    books.append({
        "id": i, "title": f"Книга {i}", "author_id": rnd.randint(1, N_AUTHORS),
        "year": rnd.randint(1850, 2026), "pages": rnd.randint(40, 900),
        "isbn": f"978-617-{i % 90 + 10}-{100000 + i}-{i % 10}", "available": rnd.random() < 0.7,
        "genres": sorted(rnd.sample(range(1, len(GENRES) + 1), rnd.randint(1, 3))),
    })
author_by_id = {a[0]: a for a in authors}

# ---------------------------------------------------------------- схеми
cur.execute("""
DROP TABLE IF EXISTS book_genres, books, genres, authors CASCADE;
CREATE TABLE authors (author_id INT PRIMARY KEY, name VARCHAR(100) NOT NULL, birth_year INT);
CREATE TABLE genres  (genre_id INT PRIMARY KEY, name VARCHAR(50) UNIQUE NOT NULL);
CREATE TABLE books   (book_id INT PRIMARY KEY, title VARCHAR(200) NOT NULL,
                      author_id INT NOT NULL REFERENCES authors(author_id),
                      publication_year INT, pages INT, isbn VARCHAR(20) UNIQUE NOT NULL, available BOOLEAN);
CREATE TABLE book_genres (book_id INT REFERENCES books(book_id), genre_id INT REFERENCES genres(genre_id),
                          PRIMARY KEY (book_id, genre_id));
""")
mongo.drop_database("compare")


def load_pg():
    psycopg2.extras.execute_values(cur, "INSERT INTO authors VALUES %s", authors, page_size=5000)
    psycopg2.extras.execute_values(cur, "INSERT INTO genres VALUES %s", list(enumerate(GENRES, 1)))
    psycopg2.extras.execute_values(cur, "INSERT INTO books VALUES %s",
                                   [(b["id"], b["title"], b["author_id"], b["year"], b["pages"], b["isbn"], b["available"])
                                    for b in books], page_size=5000)
    psycopg2.extras.execute_values(cur, "INSERT INTO book_genres VALUES %s",
                                   [(b["id"], g) for b in books for g in b["genres"]], page_size=5000)
    cur.execute("CREATE INDEX ON books(author_id); CREATE INDEX ON book_genres(genre_id); ANALYZE;")


def load_emb():
    mdb.books_emb.insert_many([{
        "_id": b["id"], "title": b["title"], "isbn": b["isbn"], "publication_year": b["year"],
        "pages": b["pages"], "available": b["available"],
        "author": {"id": b["author_id"], "name": author_by_id[b["author_id"]][1], "birth_year": author_by_id[b["author_id"]][2]},
        "genres": [GENRES[g - 1] for g in b["genres"]]} for b in books])
    mdb.books_emb.create_index("isbn", unique=True)
    mdb.books_emb.create_index("author.id")
    mdb.books_emb.create_index("genres")


def load_ref():
    mdb.authors_ref.insert_many([{"_id": a[0], "name": a[1], "birth_year": a[2]} for a in authors])
    mdb.genres_ref.insert_many([{"_id": i, "name": g} for i, g in enumerate(GENRES, 1)])
    mdb.books_ref.insert_many([{
        "_id": b["id"], "title": b["title"], "isbn": b["isbn"], "publication_year": b["year"], "pages": b["pages"],
        "available": b["available"], "author_id": b["author_id"], "genre_ids": b["genres"]} for b in books])
    mdb.books_ref.create_index("isbn", unique=True)
    mdb.books_ref.create_index("author_id")


rows = []   # (операція, PostgreSQL, MongoDB emb, MongoDB ref, примітка)
rows.append(("Завантаження 50 000 книг (мс, 1 раз)", once_ms(load_pg), once_ms(load_emb), once_ms(load_ref),
             "PG: 4 таблиці + ~100 тис. рядків book_genres; emb: 1 колекція"))

# ---------------------------------------------------------------- читання
ISBN = books[31_337]["isbn"]
AUTHOR = books[31_337]["author_id"]


def pg_card():
    cur.execute("""SELECT b.title, a.name, b.publication_year, array_agg(g.name ORDER BY g.name)
                   FROM books b JOIN authors a USING (author_id)
                   JOIN book_genres bg USING (book_id) JOIN genres g USING (genre_id)
                   WHERE b.isbn = %s GROUP BY b.book_id, a.name""", (ISBN,))
    return cur.fetchone()


def emb_card():
    return mdb.books_emb.find_one({"isbn": ISBN}, {"title": 1, "author.name": 1, "publication_year": 1, "genres": 1})


def ref_card():
    return list(mdb.books_ref.aggregate([
        {"$match": {"isbn": ISBN}},
        {"$lookup": {"from": "authors_ref", "localField": "author_id", "foreignField": "_id", "as": "a"}},
        {"$lookup": {"from": "genres_ref", "localField": "genre_ids", "foreignField": "_id", "as": "g"}},
        {"$project": {"title": 1, "author": {"$first": "$a.name"}, "publication_year": 1, "genres": "$g.name"}}]))


assert pg_card()[1] == emb_card()["author"]["name"] == ref_card()[0]["author"]
rows.append(("Картка книги за ISBN з автором і жанрами", median_ms(pg_card), median_ms(emb_card), median_ms(ref_card),
             "PG: 3 JOIN; emb: 1 документ; ref: 2 × $lookup"))


def pg_author_books():
    cur.execute("""SELECT b.title, b.publication_year, a.name FROM books b JOIN authors a USING (author_id)
                   WHERE b.author_id = %s ORDER BY b.publication_year""", (AUTHOR,))
    return cur.fetchall()


def emb_author_books():
    return list(mdb.books_emb.find({"author.id": AUTHOR}, {"title": 1, "publication_year": 1, "author.name": 1})
                .sort("publication_year", ASCENDING))


def ref_author_books():
    return list(mdb.books_ref.aggregate([
        {"$match": {"author_id": AUTHOR}}, {"$sort": {"publication_year": 1}},
        {"$lookup": {"from": "authors_ref", "localField": "author_id", "foreignField": "_id", "as": "a"}},
        {"$project": {"title": 1, "publication_year": 1, "author": {"$first": "$a.name"}}}]))


assert len(pg_author_books()) == len(emb_author_books()) == len(ref_author_books())
rows.append((f"Книги одного автора ({len(pg_author_books())} шт.) з іменем автора",
             median_ms(pg_author_books), median_ms(emb_author_books), median_ms(ref_author_books),
             "індекс за автором у всіх варіантах"))


def pg_genre_stats():
    cur.execute("""SELECT g.name, COUNT(*), ROUND(AVG(b.pages)) FROM book_genres bg
                   JOIN genres g USING (genre_id) JOIN books b USING (book_id) GROUP BY g.name ORDER BY 2 DESC""")
    return cur.fetchall()


def emb_genre_stats():
    return list(mdb.books_emb.aggregate([{"$unwind": "$genres"},
                                         {"$group": {"_id": "$genres", "n": {"$sum": 1}, "avg": {"$avg": "$pages"}}},
                                         {"$sort": {"n": -1}}]))


def ref_genre_stats():
    return list(mdb.books_ref.aggregate([{"$unwind": "$genre_ids"},
                                         {"$group": {"_id": "$genre_ids", "n": {"$sum": 1}, "avg": {"$avg": "$pages"}}},
                                         {"$lookup": {"from": "genres_ref", "localField": "_id", "foreignField": "_id", "as": "g"}},
                                         {"$sort": {"n": -1}}]))


assert pg_genre_stats()[0][1] == emb_genre_stats()[0]["n"] == ref_genre_stats()[0]["n"]
rows.append(("Статистика за жанрами (усі 50 000 книг)", median_ms(pg_genre_stats, 7), median_ms(emb_genre_stats, 7),
             median_ms(ref_genre_stats, 7), "аналітика по всій колекції"))

# ---------------------------------------------------------------- зміни
n_docs = mdb.books_emb.count_documents({"author.id": AUTHOR})
counter = iter(range(10_000))


def pg_rename():
    cur.execute("UPDATE authors SET name = %s WHERE author_id = %s", (f"Автор {AUTHOR} (ред. {next(counter)})", AUTHOR))


def emb_rename():
    mdb.books_emb.update_many({"author.id": AUTHOR}, {"$set": {"author.name": f"Автор {AUTHOR} (ред. {next(counter)})"}})


def ref_rename():
    mdb.authors_ref.update_one({"_id": AUTHOR}, {"$set": {"name": f"Автор {AUTHOR} (ред. {next(counter)})"}})


rows.append(("Перейменування автора", median_ms(pg_rename), median_ms(emb_rename), median_ms(ref_rename),
             f"PG і ref: 1 рядок/документ; emb: {n_docs} копій імені в книгах"))


def pg_add_genre():
    cur.execute("INSERT INTO book_genres VALUES (%s, 15) ON CONFLICT DO NOTHING", (rnd.randint(1, N_BOOKS),))


def emb_add_genre():
    mdb.books_emb.update_one({"_id": rnd.randint(1, N_BOOKS)}, {"$addToSet": {"genres": "гумор"}})


def ref_add_genre():
    mdb.books_ref.update_one({"_id": rnd.randint(1, N_BOOKS)}, {"$addToSet": {"genre_ids": 15}})


rows.append(("Додати жанр книзі", median_ms(pg_add_genre), median_ms(emb_add_genre), median_ms(ref_add_genre),
             "PG: рядок у book_genres; Mongo: $addToSet у масив"))

# ---------------------------------------------------------------- обсяг і цілісність
cur.execute("SELECT SUM(pg_total_relation_size(t)) FROM unnest(ARRAY['authors','genres','books','book_genres']) t")
pg_size = cur.fetchone()[0]


mongo.admin.command("fsync")          # скинути дані на диск, щоб розмір був точним
cur.execute("CHECKPOINT")


def coll_size(*names):
    return sum(mdb.command("collStats", n)["storageSize"] + mdb.command("collStats", n)["totalIndexSize"] for n in names)


rows.append(("Обсяг на диску з індексами, МБ", round(pg_size / 2**20, 1), round(coll_size("books_emb") / 2**20, 1),
             round(coll_size("books_ref", "authors_ref", "genres_ref") / 2**20, 1),
             "Mongo стискає дані (snappy), але дублює імена авторів і жанрів"))

try:
    cur.execute("INSERT INTO books VALUES (999999, 'Сирота', 99999, 2000, 10, '978-0-0-0-0', true)")
    pg_fk = "вставлено"
except psycopg2.Error as e:
    pg_fk = f"відхилено (порушено зовнішній ключ {e.diag.constraint_name})"
try:
    mdb.books_ref.insert_one({"_id": 999999, "title": "Сирота", "author_id": 99999, "isbn": "978-0-0-0-0"})
    mongo_fk = "вставлено (зовнішніх ключів немає)"
except PyMongoError as e:
    mongo_fk = str(e)

# ---------------------------------------------------------------- звіт
head = ("Операція", "PostgreSQL", "MongoDB emb", "MongoDB ref", "Примітка")
widths = [max(len(str(r[i])) for r in rows + [head]) for i in range(4)]
print(f"Набір даних: {N_AUTHORS} авторів, {len(GENRES)} жанрів, {N_BOOKS} книг; час — медіана з {RUNS} запусків, мс\n")
print("  ".join(str(h).ljust(widths[i]) if i == 0 else str(h).rjust(widths[i]) for i, h in enumerate(head[:4])))
print("-" * (sum(widths) + 6))
for r in rows:
    print("  ".join(str(v).ljust(widths[i]) if i == 0 else str(v).rjust(widths[i]) for i, v in enumerate(r[:4])))
print(f"\nКнига з неіснуючим автором: PostgreSQL — {pg_fk}; MongoDB ref — {mongo_fk}")

md = ["| " + " | ".join(head) + " |", "|" + "---|" * len(head)]
md += ["| " + " | ".join(str(v) for v in r) + " |" for r in rows]
REPORT.write_text(
    f"# Результати порівняння PostgreSQL і MongoDB\n\n"
    f"Набір даних: {N_AUTHORS} авторів, {len(GENRES)} жанрів, {N_BOOKS} книг. Час операцій — медіана з {RUNS} запусків, мс "
    f"(завантаження — один запуск). Скрипт: `compare/compare.py`.\n\n" + "\n".join(md) +
    f"\n\nКнига з неіснуючим автором: PostgreSQL — {pg_fk}; MongoDB (ref) — {mongo_fk}.\n", encoding="utf-8")
print(f"Таблицю збережено: docs/{REPORT.name}")
