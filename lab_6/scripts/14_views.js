// Крок 13. Представлення (view) для часто використовуваних запитів.
// View зберігає лише pipeline; дані обчислюються під час кожного звернення.

// 1. Доступні книги (каталог для читачів)
db.createView("available_books", "books", [
  { $match: { available: true } },
  { $project: { _id: 0, title: 1, author: 1, publication_year: 1, pages: 1, hall: "$location.hall" } }
])

// 2. Картка книги з автором і середньою оцінкою (використовує $lookup)
db.createView("book_cards", "books", [
  { $lookup: { from: "authors", localField: "author_id", foreignField: "_id", as: "a" } },
  { $project: { _id: 0, isbn: 1, title: 1, author: { $first: "$a.name" }, available: 1,
                genres: 1, avg_score: { $round: [{ $avg: "$ratings.score" }, 1] }, votes: { $size: "$ratings" } } }
])

// 3. Активність читачів: скільки книг на руках
db.createView("reader_activity", "users", [
  { $project: { _id: 0, username: 1, status: 1, on_hand: { $size: "$borrowed_books" },
                full_name: { $concat: ["$profile.first_name", " ", "$profile.last_name"] } } },
  { $sort: { on_hand: -1, username: 1 } }
])

// Представлення використовується як колекція: find, sort, aggregate
db.available_books.find({ publication_year: { $lt: 1900 } }).sort({ publication_year: 1 })

db.book_cards.find({ votes: { $gte: 2 } }).sort({ avg_score: -1 })

db.reader_activity.find({ on_hand: { $gt: 0 } }).limit(4)

// View доступне лише для читання — запис у нього заборонено
db.available_books.insertOne({ title: "Спроба запису" })

db.getCollectionInfos({ type: "view" }).map(v => ({ view: v.name, source: v.options.viewOn, stages: v.options.pipeline.length }))
