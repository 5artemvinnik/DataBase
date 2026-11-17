// Крок 10. Складені (compound) індекси для складних запитів.
// Запит каталогу: доступні книги жанру «фантастика» з рейтингом від 4.5, найновіші першими.
// Правило ESR: спочатку поля рівності (Equality), потім сортування (Sort), наприкінці діапазону (Range).

// Варіант 1: лише простий індекс за жанром — потрібне окреме сортування в пам'яті (SORT)
db.books_big.createIndex({ genres: 1 })

load("/lab6/scripts/lib/bench.js");
record("before", "C1 genre+available+rating, sort year",
  bench("books_big", { genres: "фантастика", available: true, rating: { $gte: 4.5 } },
        { sort: { publication_year: -1 }, limit: 20, hint: { genres: 1 } }))

// Варіант 2: складений індекс у порядку ESR — без SORT, переглядаються лише потрібні ключі
db.books_big.createIndex({ genres: 1, available: 1, publication_year: -1, rating: 1 }, { name: "genre_avail_year_rating" })

load("/lab6/scripts/lib/bench.js");
record("after", "C1 genre+available+rating, sort year",
  bench("books_big", { genres: "фантастика", available: true, rating: { $gte: 4.5 } },
        { sort: { publication_year: -1 }, limit: 20 }))

// Другий складений індекс для звіту «книги автора за роками з обсягом» — покривний запит:
// усі поля є в індексі, тому документи взагалі не читаються (docsExamined = 0).
// Для порівняння «до» примусово беремо індекс author+year з кроку 7, який не містить pages.
db.books_big.createIndex({ author: 1, publication_year: 1, pages: 1 }, { name: "author_year_pages" })

load("/lab6/scripts/lib/bench.js");
record("before", "C2 author report (covered)",
  bench("books_big", { author: "Автор 1500" }, { projection: { _id: 0, publication_year: 1, pages: 1 }, sort: { publication_year: 1 }, hint: "author_1_publication_year_-1" }));
record("after", "C2 author report (covered)",
  bench("books_big", { author: "Автор 1500" }, { projection: { _id: 0, publication_year: 1, pages: 1 }, sort: { publication_year: 1 }, hint: "author_year_pages" }))

load("/lab6/scripts/lib/bench.js");
console.table(compare(["C1 genre+available+rating, sort year", "C2 author report (covered)"]))
