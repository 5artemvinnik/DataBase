// Крок 11. Текстовий пошук з індексом типу text.
// Української серед мов стемінгу MongoDB немає, тому default_language: "none" — лише
// розбиття на слова без стемінгу. Ваги: збіг у назві важить у 5 разів більше, ніж в описі.

db.books.createIndex(
  { title: "text", description: "text" },
  { name: "books_text", default_language: "none", weights: { title: 5, description: 1 } }
)

// Пошук за кількома словами (логічне АБО) з оцінкою релевантності
db.books.find(
  { $text: { $search: "кохання Карпатах" } },
  { _id: 0, title: 1, score: { $meta: "textScore" } }
).sort({ score: { $meta: "textScore" } })

// Точна фраза в лапках і виключення слова мінусом
db.books.find({ $text: { $search: "\"українського фольклору\"" } }, { _id: 0, title: 1 })

db.books.find({ $text: { $search: "роман -віршах" } }, { _id: 0, title: 1, description: 1 })

// Текстовий пошук разом з іншими умовами: повісті, де згадано «повість» або «новела»
db.books.find(
  { $text: { $search: "повість новела" }, publication_year: { $lt: 1915 } },
  { _id: 0, title: 1, publication_year: 1, score: { $meta: "textScore" } }
).sort({ score: { $meta: "textScore" } })

// Обмеження без стемінгу: «Карпати» не знаходить «Карпатах», а «кохання» не знаходить «коханням».
// Цю проблему розв'язано на рівні 3 (крок 17).
db.books.countDocuments({ $text: { $search: "Карпати" } });

// План запиту: використовується текстовий індекс books_text
(function stages(p) { return p ? [p.stage + (p.indexName ? "(" + p.indexName + ")" : "")].concat(stages(p.inputStage)) : []; })
  (db.books.find({ $text: { $search: "кохання" } }).explain().queryPlanner.winningPlan).join(" <- ")
