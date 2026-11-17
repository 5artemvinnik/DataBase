// Повнотекстовий пошук з підтримкою української мови (підключається через load()).
// Вбудований текстовий індекс MongoDB не має українського стемінгу, тому
// застосунок сам зводить слова до основи (легкий стемер) і зберігає основи
// в полі search_terms, по якому побудовано text-індекс з default_language "none".

const UK_STOP = new Set(("і й та а але або в у на з із зі до від для по про при за над під через між " +
  "не ні що як це цей ця ці той та те ті його її їх він вона воно вони який яка яке які чи же ж б би " +
  "бо так також вже ще тут там де коли").split(" "));

// Закінчення (від довших до коротших). Відкидається перше, що підходить, якщо основа ≥ 3 літер.
const UK_ENDINGS = ["ями", "ами", "ові", "еві", "ого", "ому", "ими", "іми", "ій", "их", "іх", "ою", "ею",
  "ам", "ям", "ах", "ях", "ом", "ем", "ів", "їв", "ей", "ий", "ої", "ую", "юю", "у", "ю", "а", "я",
  "і", "и", "о", "е", "є", "ь", "ї"];

function ukNormalize(text) {
  return String(text).toLowerCase()
    .replace(/[’ʼ`‘]/g, "'")                       // різні апострофи → один
    .replace(/[^a-zа-яіїєґ0-9' ]+/g, " ");        // розділові знаки → пробіли
}

function ukStem(word) {
  word = word.replace(/'/g, "");
  if (word.length < 4) return word;
  for (const e of UK_ENDINGS)
    if (word.endsWith(e) && word.length - e.length >= 3) return word.slice(0, -e.length);
  return word;
}

function ukTerms(text) {
  return [...new Set(ukNormalize(text).split(/\s+/).filter(w => w && !UK_STOP.has(w)).map(ukStem))];
}

// Перебудова search_terms для однієї книги або для всіх (викликається після вставки/зміни книги)
function ukIndexBooks(filter = {}) {
  let n = 0;
  db.books.find(filter).forEach(b => {
    const text = [b.title, b.title, b.author, b.description, (b.genres || []).join(" ")].join(" ");
    db.books.updateOne({ _id: b._id }, { $set: { search_terms: ukTerms(text) } });
    n++;
  });
  return n;
}

// Пошук: запит теж зводиться до основ, результати сортуються за релевантністю
function ukSearch(query, limit = 5) {
  const terms = ukTerms(query);
  return db.books.find({ $text: { $search: terms.join(" ") } },
                       { _id: 0, title: 1, score: { $meta: "textScore" } })
           .sort({ score: { $meta: "textScore" } }).limit(limit).toArray()
           .map(r => ({ title: r.title, score: Math.round(r.score * 100) / 100 }));
}
