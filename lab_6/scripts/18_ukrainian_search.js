// Крок 17. Повнотекстовий пошук з підтримкою української мови.
// Функції стемера — у lib/uk_search.js.

// Як працює стемер: різні відмінкові форми зводяться до однієї основи
load("/lab6/scripts/lib/uk_search.js");
["Карпати", "Карпатах", "кохання", "коханням", "відьма", "відьми", "селян", "селянам", "повість", "повісті", "Основ’яненко"]
  .map(w => w + " → " + ukStem(ukNormalize(w).trim())).join(" | ")

// Обчислюємо основи для всіх книг; назва повторюється двічі, щоб мати більшу вагу
load("/lab6/scripts/lib/uk_search.js");
ukIndexBooks()

db.books.findOne({ title: "Тіні забутих предків" }, { _id: 0, title: 1, search_terms: 1 })

// У колекції може бути лише один text-індекс: замінюємо books_text індексом за основами
db.books.dropIndex("books_text");
db.books.createIndex({ search_terms: "text" }, { name: "books_uk_text", default_language: "none" })

// Порівняння зі звичайним текстовим пошуком: тепер слово в будь-якій формі знаходить книгу
load("/lab6/scripts/lib/uk_search.js");
[ "Карпати", "коханням", "відьми", "селянам", "війною", "Франка" ].map(q => ({ query: q, found: ukSearch(q, 3).map(r => r.title) }))

// Пошук за кількома словами з оцінкою релевантності
load("/lab6/scripts/lib/uk_search.js");
ukSearch("історичні романи про боротьбу")

// Апостроф у будь-якому написанні (', ’, ʼ) і регістр не впливають на результат
load("/lab6/scripts/lib/uk_search.js");
[ukSearch("Квітки-Основ'яненка", 1), ukSearch("КВІТКИ-ОСНОВ’ЯНЕНКА", 1)]
