// Крок 6. Три різні індекси для оптимізації пошуку в колекції books.

// 1. Простий індекс за назвою — пошук і сортування за title
db.books.createIndex({ title: 1 })

// 2. Складений індекс: автор + рік видання (спадання) — книги автора від найновішої
db.books.createIndex({ author: 1, publication_year: -1 })

// 3. Унікальний індекс за ISBN — швидкий пошук і заборона дублікатів
db.books.createIndex({ isbn: 1 }, { unique: true })

db.books.getIndexes().map(i => ({ name: i.name, key: i.key, unique: i.unique || false }))

// Унікальний індекс не дає вставити книгу з наявним ISBN
db.books.insertOne({ title: "Дублікат", author: "Тест", publication_year: 2000, isbn: "978-966-03-4421-6" })

// План запиту тепер використовує індекс (IXSCAN), переглянуто лише 2 документи
db.books.find({ author: "Іван Франко" }).sort({ publication_year: -1 }).explain("executionStats").executionStats
