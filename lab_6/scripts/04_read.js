// Крок 5.2. Пошук документів з різними умовами.

// Рівність: книги Івана Франка (проєкція — лише потрібні поля)
db.books.find({ author: "Іван Франко" }, { _id: 0, title: 1, publication_year: 1 })

// Порівняння: книги, що мають понад 200 сторінок, від найбільшої
db.books.find({ pages: { $gt: 200 } }, { _id: 0, title: 1, pages: 1 }).sort({ pages: -1 })

// Діапазон: видані у XX столітті ($gte і $lt разом)
db.books.find({ publication_year: { $gte: 1900, $lt: 2000 } }, { _id: 0, title: 1, publication_year: 1 })

// Пошук в масиві: книги жанру «поезія»
db.books.find({ genres: "поезія" }, { _id: 0, title: 1, genres: 1 })

// Вкладений документ (крапкова нотація): книги видавництва з Харкова в залі B
db.books.find({ "publisher.city": "Харків", "location.hall": "B" }, { _id: 0, title: 1, location: 1 })

// Логічні оператори: доступні книги, але не романи ($ne для масиву — жодного елемента «роман»)
db.books.find({ available: true, genres: { $ne: "роман" } }, { _id: 0, title: 1, genres: 1 })

// $exists і масив документів: читачі, у яких на руках понад одна книга
db.users.find({ "borrowed_books.1": { $exists: true } }, { _id: 0, username: 1, "borrowed_books.title": 1 })

// Сортування й обмеження: дві найновіші книги
db.books.find({}, { _id: 0, title: 1, publication_year: 1 }).sort({ publication_year: -1 }).limit(2)

// findOne — один документ цілком (з вкладеними документами і масивами)
db.books.findOne({ isbn: "978-966-03-3527-6" })
