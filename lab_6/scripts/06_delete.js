// Крок 5.4. Видалення документів за умовами.
// Щоб не втратити основні дані, спочатку додаємо тимчасові документи і видаляємо саме їх.

db.books.insertMany([
  { title: "Тимчасова книга 1", author: "Тест", publication_year: 2000, available: false, temp: true },
  { title: "Тимчасова книга 2", author: "Тест", publication_year: 2001, available: false, temp: true },
  { title: "Застарілий довідник", author: "Тест", publication_year: 1985, available: true, temp: true }
])

// deleteOne — один документ за назвою
db.books.deleteOne({ title: "Застарілий довідник" })

// deleteMany — усі тимчасові недоступні книги (умова з двох полів)
db.books.deleteMany({ temp: true, available: false })

// deleteOne з умовою на статус: заблокований читач без книг на руках (не підходить жоден — у Богдана є книга)
db.users.deleteOne({ status: "blocked", borrowed_books: { $size: 0 } })

// findOneAndDelete повертає видалений документ: прибираємо нового читача Максима
db.users.findOneAndDelete({ username: "maksym_polishchuk" }, { projection: { _id: 0, username: 1, profile: 1 } });

({ books: db.books.countDocuments(), users: db.users.countDocuments(), temp_left: db.books.countDocuments({ temp: true }) })
