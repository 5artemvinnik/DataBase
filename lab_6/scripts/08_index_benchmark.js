// Крок 7. Порівняння швидкості запитів без індексів і з ними.
// На 11 документах різниці не видно, тому генеруємо колекцію books_big на 200 000 книг
// (детермінований генератор, щоб результати можна було повторити).

db.books_big.drop(); db.perf_results.deleteMany({});
let seed = 42; const rnd = () => (seed = (seed * 1103515245 + 12345) % 2147483648) / 2147483648;
const genres = ["роман", "поезія", "повість", "драма", "новела", "фантастика", "детектив", "історична проза",
                "пригоди", "сучасна проза", "наукова література", "дитяча література"];
const words = ["Тіні", "Вогонь", "Сад", "Ріка", "Дорога", "Місто", "Зоря", "Тиша", "Пісня", "Вітер"];
for (let b = 0; b < 20; b++) {
  const batch = [];
  for (let i = b * 10000; i < (b + 1) * 10000; i++) {
    const g = new Set([genres[Math.floor(rnd() * 12)], genres[Math.floor(rnd() * 12)]]);
    batch.push({ title: words[i % 10] + " " + words[(i * 7) % 10] + ". Книга " + (i + 1),
                 author: "Автор " + (1 + Math.floor(rnd() * 2000)),
                 publication_year: 1800 + Math.floor(rnd() * 226), pages: 50 + Math.floor(rnd() * 900),
                 isbn: "978-617-" + String(10 + i % 90) + "-" + String(100000 + i) + "-" + (i % 10),
                 genres: [...g], available: rnd() < 0.7, rating: Math.round(rnd() * 40 + 10) / 10 });
  }
  db.books_big.insertMany(batch, { ordered: false });
}
({ books_big: db.books_big.countDocuments(), size_mb: Math.round(db.books_big.stats().size / 1048576) })

// Вимірювання БЕЗ індексів: кожен запит повністю сканує колекцію (COLLSCAN)
load("/lab6/scripts/lib/bench.js");
[
  record("before", "Q1 title = ...", bench("books_big", { title: "Вітер Ріка. Книга 150000" })),
  record("before", "Q2 author + year", bench("books_big", { author: "Автор 777", publication_year: { $gte: 1950 } }, { sort: { publication_year: -1 } })),
  record("before", "Q3 isbn = ...", bench("books_big", { isbn: "978-617-29-119999-9" }))
]

// Створюємо ті самі три індекси, що й для books
db.books_big.createIndexes([ { title: 1 }, { author: 1, publication_year: -1 } ]);
db.books_big.createIndex({ isbn: 1 }, { unique: true })

// Вимірювання З індексами: IXSCAN, переглядаються лише потрібні документи
load("/lab6/scripts/lib/bench.js");
[
  record("after", "Q1 title = ...", bench("books_big", { title: "Вітер Ріка. Книга 150000" })),
  record("after", "Q2 author + year", bench("books_big", { author: "Автор 777", publication_year: { $gte: 1950 } }, { sort: { publication_year: -1 } })),
  record("after", "Q3 isbn = ...", bench("books_big", { isbn: "978-617-29-119999-9" }))
]

// Підсумкове порівняння
load("/lab6/scripts/lib/bench.js");
console.table(compare(["Q1 title = ...", "Q2 author + year", "Q3 isbn = ..."]))
