// Крок 5.1. Вставка одного та багатьох документів.

// insertOne — нова книга з вкладеними документами та масивом
db.books.insertOne({
  title: "Intermezzo", author: "Михайло Коцюбинський", publication_year: 1909, pages: 72,
  isbn: "978-966-03-6843-4", genres: ["новела", "імпресіонізм"], available: true,
  description: "Імпресіоністична новела про втомленого митця, що відпочиває серед природи",
  publisher: { name: "Фоліо", city: "Харків" }, location: { hall: "B", shelf: 1 }, ratings: []
})

// insertMany — два нові читачі різної структури (у другого немає адреси)
db.users.insertMany([
  { username: "sofia_tkachenko", email: "sofia.tkachenko@email.com", status: "active",
    profile: { first_name: "Софія", last_name: "Ткаченко" }, address: { city: "Луцьк", street: "вул. Глушець, 5" },
    registration_date: new Date(), roles: ["reader"], borrowed_books: [] },
  { username: "maksym_polishchuk", email: "maksym.polishchuk@email.com", status: "active",
    profile: { first_name: "Максим", last_name: "Поліщук", telegram: "@maks_reads" },
    registration_date: new Date(), roles: ["reader"], borrowed_books: [], interests: ["фантастика", "історія"] }
]);

({ books: db.books.countDocuments(), users: db.users.countDocuments() })
