// Система версіонування документів books (підключається через load()).
// Кожна зміна виконується в транзакції: попередній стан книги зберігається
// в books_history з номером версії, автором і коментарем, а в книзі
// збільшується version (оптимістичне блокування від одночасних змін).

const VERSION_FIELDS = ["_id", "version", "updated_at", "updated_by"];

function versionedUpdate(isbn, update, user, comment, expectedVersion) {
  const session = db.getMongo().startSession();
  const sdb = session.getDatabase("library");
  session.startTransaction({ readConcern: { level: "snapshot" }, writeConcern: { w: "majority" } });
  try {
    const cur = sdb.books.findOne({ isbn });
    if (!cur) throw new Error("Книгу " + isbn + " не знайдено");
    const v = cur.version || 1;
    if (expectedVersion !== undefined && expectedVersion !== v)
      throw new Error("Конфлікт версій: очікувалась v" + expectedVersion + ", у базі вже v" + v);
    const snapshot = Object.fromEntries(Object.entries(cur).filter(([k]) => !VERSION_FIELDS.includes(k)));
    sdb.books_history.insertOne({ book_id: cur._id, isbn, version: v, snapshot,
                                  valid_from: cur.updated_at || cur._id.getTimestamp(), valid_to: new Date(),
                                  changed_by: user, comment });
    const set = Object.assign({}, update.$set, { updated_at: new Date(), updated_by: user });
    const res = sdb.books.updateOne({ _id: cur._id, version: cur.version },   // умова = оптимістичне блокування
                                    Object.assign({}, update, { $set: set, $inc: { version: 1 } }));
    if (res.matchedCount !== 1) throw new Error("Книгу змінив інший користувач, повторіть спробу");
    session.commitTransaction();
    return "v" + v + " → v" + (v + 1);
  } catch (e) {
    session.abortTransaction();                                    // відкат: ні історії, ні зміни
    throw e;
  } finally { session.endSession(); }
}

// Історія версій книги: від першої до поточної
function bookHistory(isbn) {
  const cur = db.books.findOne({ isbn });
  return db.books_history.find({ isbn }, { _id: 0, version: 1, changed_by: 1, comment: 1, valid_to: 1 })
           .sort({ version: 1 }).toArray()
           .concat([{ version: cur.version, changed_by: cur.updated_by, comment: "(поточна версія)" }]);
}

// Повний документ певної версії
function getVersion(isbn, version) {
  const cur = db.books.findOne({ isbn });
  if (version === cur.version) return cur;
  return (db.books_history.findOne({ isbn, version }) || {}).snapshot;
}

// Різниця між двома версіями: лише поля, що змінились
function diffVersions(isbn, v1, v2) {
  const a = getVersion(isbn, v1), b = getVersion(isbn, v2), out = {};
  new Set([...Object.keys(a), ...Object.keys(b)]).forEach(k => {
    if (VERSION_FIELDS.includes(k)) return;
    if (JSON.stringify(a[k]) !== JSON.stringify(b[k])) out[k] = { ["v" + v1]: a[k], ["v" + v2]: b[k] };
  });
  return out;
}

// Відновлення старої версії — теж нова версія (історія не переписується)
function restoreVersion(isbn, version, user) {
  const old = getVersion(isbn, version), cur = db.books.findOne({ isbn });
  const unset = {};
  Object.keys(cur).forEach(k => { if (!(k in old) && !VERSION_FIELDS.includes(k)) unset[k] = ""; });
  const upd = { $set: Object.fromEntries(Object.entries(old).filter(([k]) => !VERSION_FIELDS.includes(k))) };
  if (Object.keys(unset).length) upd.$unset = unset;
  return versionedUpdate(isbn, upd, user, "відновлено версію v" + version);
}
