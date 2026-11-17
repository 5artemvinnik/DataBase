// Крок 5.3. Оновлення документів.

// $set — книгу «Кобзар» видано читачеві, вона недоступна
db.books.updateOne({ title: "Кобзар" }, { $set: { available: false, "location.shelf": 4 } })

// $push — новий відгук у масив документів
db.books.updateOne(
  { title: "Лісова пісня" },
  { $push: { ratings: { user: "ivan_petrov", score: 5, date: new Date() } } }
)

// updateMany — категорія для всіх книг, виданих до 1900 року
db.books.updateMany({ publication_year: { $lt: 1900 } }, { $set: { category: "класика XIX століття" } })

// $inc — лічильник видач (поле створюється, якщо його немає)
db.books.updateOne({ title: "Тіні забутих предків" }, { $inc: { borrowed_count: 1 } })

// $addToSet — жанр додається лише якщо його ще немає (повторний виклик нічого не змінить)
db.books.updateOne({ title: "Тигролови" }, { $addToSet: { genres: "трилер" } })

// $unset і $rename — видалення та перейменування полів
db.users.updateOne({ username: "maksym_polishchuk" }, { $unset: { interests: "" }, $rename: { "profile.telegram": "profile.messenger" } })

// Результат змін
db.books.find(
  { title: { $in: ["Кобзар", "Лісова пісня", "Тіні забутих предків", "Тигролови"] } },
  { _id: 0, title: 1, available: 1, genres: 1, borrowed_count: 1, ratings: { $slice: -1 } }
)

db.books.countDocuments({ category: "класика XIX століття" })
