// Крок 12. Об'єднання колекцій з $lookup (аналог JOIN).

// Зв'язок «посиланням»: додаємо до книг author_id з колекції authors
db.authors.find().forEach(a => db.books.updateMany({ author: a.name }, { $set: { author_id: a._id } }));
db.books.countDocuments({ author_id: { $exists: true } })

// books → authors: книга з даними автора (рівність полів localField/foreignField)
db.books.aggregate([
  { $match: { publication_year: { $gte: 1900 } } },
  { $lookup: { from: "authors", localField: "author_id", foreignField: "_id", as: "author_info" } },
  { $unwind: "$author_info" },
  { $project: { _id: 0, title: 1, publication_year: 1, author: "$author_info.name",
                author_years: { $concat: [ { $toString: "$author_info.birth_year" }, "–",
                                           { $ifNull: [ { $toString: "$author_info.death_year" }, "" ] } ] } } },
  { $sort: { publication_year: 1 } }
])

// authors → books (один-до-багатьох): кількість книг кожного автора в бібліотеці та їх назви
db.authors.aggregate([
  { $lookup: { from: "books", localField: "_id", foreignField: "author_id", as: "books" } },
  { $project: { _id: 0, name: 1, books_in_library: { $size: "$books" }, titles: "$books.title" } },
  { $sort: { books_in_library: -1, name: 1 } },
  { $limit: 5 }
])

// users → books → authors: $lookup з pipeline і змінними (let) — що саме читає кожен читач
db.users.aggregate([
  { $match: { "borrowed_books.0": { $exists: true }, status: "active" } },
  { $sort: { username: 1 } },
  { $limit: 4 },
  { $lookup: {
      from: "books",
      let: { isbns: "$borrowed_books.isbn" },
      pipeline: [
        { $match: { $expr: { $in: ["$isbn", "$$isbns"] } } },
        { $lookup: { from: "authors", localField: "author_id", foreignField: "_id", as: "a" } },
        { $project: { _id: 0, book: { $concat: ["$title", " (", { $first: "$a.name" }, ")"] } } }
      ],
      as: "reading"
  } },
  { $project: { _id: 0, reader: { $concat: ["$profile.first_name", " ", "$profile.last_name"] }, reading: "$reading.book" } }
])

// Анти-JOIN: автори, чиїх книг немає в бібліотеці (порожній результат $lookup)
db.authors.aggregate([
  { $lookup: { from: "books", localField: "_id", foreignField: "author_id", as: "b" } },
  { $match: { b: { $size: 0 } } },
  { $project: { _id: 0, name: 1 } }
])
