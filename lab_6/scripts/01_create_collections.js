// Крок 3. Створення бази library і колекцій books, authors, users.
// База створюється автоматично під час першого запису в неї.

// books — з базовою валідацією (на рівні 3 її буде розширено)
db.createCollection("books", {
  validator: {
    $jsonSchema: {
      bsonType: "object",
      required: ["title", "author", "publication_year"],
      properties: {
        title: { bsonType: "string" },
        author: { bsonType: "string" },
        publication_year: { bsonType: "int", minimum: 1000 },
        pages: { bsonType: "int", minimum: 1 },
        genres: { bsonType: "array", items: { bsonType: "string" } },
        available: { bsonType: "bool" }
      }
    }
  }
})

db.createCollection("authors")

db.createCollection("users")

db.getCollectionInfos({}, { nameOnly: true }).map(c => c.name)
