// Крок 9. Агрегаційні запити (aggregation pipeline).

// Підрахунок кількості книг за жанрами: $unwind розгортає масив, $group рахує
db.books.aggregate([
  { $unwind: "$genres" },
  { $group: { _id: "$genres", books: { $sum: 1 } } },
  { $sort: { books: -1, _id: 1 } },
  { $limit: 8 }
])

// Середні значення: середня кількість сторінок і кількість книг за автором
db.books.aggregate([
  { $group: { _id: "$author", books: { $sum: 1 }, avg_pages: { $avg: "$pages" } } },
  { $project: { _id: 0, author: "$_id", books: "$books", avg_pages: { $round: ["$avg_pages", 0] } } },
  { $sort: { books: -1, avg_pages: -1 } }
])

// Середня оцінка читачів для кожної книги ($avg по масиву ratings.score), лише книги з оцінками
db.books.aggregate([
  { $match: { "ratings.0": { $exists: true } } },
  { $project: { _id: 0, title: 1, votes: { $size: "$ratings" }, avg_score: { $round: [{ $avg: "$ratings.score" }, 2] } } },
  { $sort: { avg_score: -1, votes: -1 } }
])

// Групування за століттям видання з переліком авторів і сортуванням
db.books.aggregate([
  { $group: { _id: { $ceil: { $divide: ["$publication_year", 100] } },
              books: { $sum: 1 }, pages_total: { $sum: "$pages" }, authors: { $addToSet: "$author" } } },
  { $project: { _id: 0, century: { $concat: [{ $toString: "$_id" }, " ст."] }, books: "$books",
                pages_total: "$pages_total", authors: "$authors" } },
  { $sort: { century: 1 } }
])

// Читачі: кількість книг на руках і статистика за статусом ($facet — кілька звітів за один прохід)
db.users.aggregate([
  { $project: { username: 1, status: 1, on_hand: { $size: "$borrowed_books" } } },
  { $facet: {
      top_readers: [ { $sort: { on_hand: -1, username: 1 } }, { $limit: 3 }, { $project: { _id: 0, username: 1, on_hand: 1 } } ],
      by_status:   [ { $group: { _id: "$status", users: { $sum: 1 }, books: { $sum: "$on_hand" } } }, { $sort: { users: -1 } } ]
  } }
])

// На великій колекції: середній рейтинг і частка доступних книг за жанрами ($bucket за обсягом)
db.books_big.aggregate([
  { $unwind: "$genres" },
  { $group: { _id: "$genres", books: { $sum: 1 }, avg_rating: { $avg: "$rating" },
              available_pct: { $avg: { $cond: ["$available", 100, 0] } } } },
  { $project: { books: 1, avg_rating: { $round: ["$avg_rating", 2] }, available_pct: { $round: ["$available_pct", 1] } } },
  { $sort: { books: -1 } },
  { $limit: 6 }
])

db.books_big.aggregate([
  { $bucket: { groupBy: "$pages", boundaries: [50, 200, 400, 700, 1000], default: "інше",
               output: { books: { $sum: 1 }, avg_year: { $avg: "$publication_year" } } } },
  { $project: { books: 1, avg_year: { $round: ["$avg_year", 0] } } }
])
