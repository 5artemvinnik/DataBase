// Крок 16. Система версіонування документів зі збереженням історії змін.
// Функції — у lib/versioning.js; зміни виконуються в багатодокументних транзакціях
// (їх підтримує набір реплік rs0).

// Підготовка: усі книги отримують version: 1; історія — окрема колекція з унікальним ключем
db.books.updateMany({ version: { $exists: false } }, { $set: { version: 1 } });
db.books_history.drop();
db.books_history.createIndex({ isbn: 1, version: 1 }, { unique: true })

// Три зміни книги «Тигролови» різними користувачами
load("/lab6/scripts/lib/versioning.js");
[
  versionedUpdate("978-966-03-3527-6", { $set: { pages: 432 } }, "librarian", "нове видання, більше сторінок"),
  versionedUpdate("978-966-03-3527-6", { $set: { available: false, "location.shelf": 5 } }, "librarian", "книгу видано читачу"),
  versionedUpdate("978-966-03-3527-6", { $set: { description: "Пригодницький роман-втеча про Григорія Многогрішного та родину Сірків у тайзі" } }, "anna_melnyk", "уточнено опис")
]

// Історія версій
load("/lab6/scripts/lib/versioning.js");
bookHistory("978-966-03-3527-6")

// Що змінилося між першою і поточною версією
load("/lab6/scripts/lib/versioning.js");
diffVersions("978-966-03-3527-6", 1, 4)

// Відновлення версії 1 — створює версію 5, історія зберігається повністю
load("/lab6/scripts/lib/versioning.js");
restoreVersion("978-966-03-3527-6", 1, "admin")

load("/lab6/scripts/lib/versioning.js");
({ current: db.books.findOne({ isbn: "978-966-03-3527-6" }, { _id: 0, title: 1, pages: 1, available: 1, version: 1, updated_by: 1 }),
   history_rows: db.books_history.countDocuments({ isbn: "978-966-03-3527-6" }),
   diff_v1_v5: diffVersions("978-966-03-3527-6", 1, 5) })

// Оптимістичне блокування: зміна на основі застарілої версії 3 відхиляється, транзакція відкочується
load("/lab6/scripts/lib/versioning.js");
try { versionedUpdate("978-966-03-3527-6", { $set: { pages: 1 } }, "ivan_petrov", "зміна застарілої копії", 3) }
catch (e) { "Помилка: " + e.message }

({ pages: db.books.findOne({ isbn: "978-966-03-3527-6" }).pages, history_rows: db.books_history.countDocuments() })
