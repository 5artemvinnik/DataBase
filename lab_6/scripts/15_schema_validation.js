// Крок 14. Валідація схеми документів з JSON Schema.
// Розширюємо валідатор books (collMod) і додаємо валідатор для users.
// validationLevel "strict" — перевіряються всі вставки й оновлення; validationAction "error" — відхиляти.

db.runCommand({
  collMod: "books",
  validationLevel: "strict",
  validationAction: "error",
  validator: { $jsonSchema: {
    bsonType: "object",
    required: ["title", "author", "publication_year", "available", "isbn"],
    properties: {
      title:            { bsonType: "string", minLength: 1, maxLength: 200, description: "назва 1–200 символів" },
      author:           { bsonType: "string", minLength: 3, description: "автор обов'язковий" },
      publication_year: { bsonType: "int", minimum: 1000, maximum: 2026, description: "рік від 1000 до поточного" },
      pages:            { bsonType: "int", minimum: 1, maximum: 10000, description: "сторінок від 1 до 10000" },
      isbn:             { bsonType: "string", pattern: "^978-\\d{1,5}-\\d{1,7}-\\d{1,7}-\\d$", description: "ISBN-13 у форматі 978-…" },
      available:        { bsonType: "bool" },
      genres:           { bsonType: "array", minItems: 1, uniqueItems: true, items: { bsonType: "string" } },
      publisher:        { bsonType: "object", required: ["name"],
                          properties: { name: { bsonType: "string" }, city: { bsonType: "string" } } },
      ratings:          { bsonType: "array", items: { bsonType: "object", required: ["user", "score"],
                          properties: { user: { bsonType: "string" },
                                        score: { bsonType: "int", minimum: 1, maximum: 5, description: "оцінка 1–5" },
                                        date: { bsonType: "date" } } } }
    }
  } }
})

db.runCommand({
  collMod: "users",
  validationLevel: "strict",
  validator: { $jsonSchema: {
    bsonType: "object",
    required: ["username", "email", "status", "profile"],
    properties: {
      username: { bsonType: "string", pattern: "^[a-z][a-z0-9_]{2,31}$", description: "латиниця, цифри, _ (3–32)" },
      email:    { bsonType: "string", pattern: "^[^@\\s]+@[^@\\s]+\\.[a-z]{2,}$", description: "коректна email-адреса" },
      status:   { enum: ["active", "suspended", "blocked"], description: "лише active / suspended / blocked" },
      profile:  { bsonType: "object", required: ["first_name", "last_name"],
                  properties: { phone: { bsonType: "string", pattern: "^\\+380\\d{9}$" } } },
      borrowed_books: { bsonType: "array", maxItems: 5, description: "не більше 5 книг на руках" }
    }
  } }
});

// Валідатор не зачіпає вже збережені документи — перевіряємо, що всі вони відповідають новій схемі
({ books_invalid: db.books.countDocuments({ $nor: [ db.getCollectionInfos({ name: "books" })[0].options.validator ] }),
   users_invalid: db.users.countDocuments({ $nor: [ db.getCollectionInfos({ name: "users" })[0].options.validator ] }) })

// Некоректні документи відхиляються з поясненням, яке саме правило порушено
const tryInsert = (coll, doc) => {
  try { db[coll].insertOne(doc); return "вставлено"; }
  catch (e) {
    const d = e.errInfo.details.schemaRulesNotSatisfied[0];
    const p = (d.propertiesNotSatisfied || []).map(x => x.propertyName + ": " + (x.description || "елемент масиву не відповідає підсхемі"));
    return "відхилено (код " + e.code + ") → " + (p.length ? p.join("; ") : "відсутнє обов'язкове поле " + d.missingProperties);
  }
};
[
  tryInsert("books", { title: "Тестова книга", author: "Тестовий автор", publication_year: 3000, available: true, isbn: "978-966-03-0000-1" }),
  tryInsert("books", { title: "Без ISBN", author: "Тестовий автор", publication_year: 2020, available: true }),
  tryInsert("books", { title: "Поганий ISBN", author: "Тестовий автор", publication_year: 2020, available: true, isbn: "12345" }),
  tryInsert("books", { title: "Погана оцінка", author: "Тестовий автор", publication_year: 2020, available: true,
                       isbn: "978-966-03-0000-2", ratings: [ { user: "x", score: 10 } ] }),
  tryInsert("users", { username: "Bad User", email: "not-an-email", status: "vip", profile: { first_name: "А", last_name: "Б" } }),
  tryInsert("books", { title: "Коректна книга", author: "Тестовий автор", publication_year: 2024, available: true,
                       isbn: "978-966-03-9999-9", pages: 120, genres: ["тест"] })
]

// Оновлення також перевіряється: оцінка 7 і рік 2100 недопустимі
db.books.updateOne({ title: "Кобзар" }, { $push: { ratings: { user: "test", score: 7 } } })

db.books.updateOne({ title: "Кобзар" }, { $set: { publication_year: 2100 } })

// Прибираємо тестову книгу
db.books.deleteOne({ isbn: "978-966-03-9999-9" })
