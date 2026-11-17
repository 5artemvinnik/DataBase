// Ініціалізація набору реплік rs0 з трьох вузлів (виконується healthcheck-ом контейнера mongo1).
// Якщо набір уже створено — лише перевіряє, що є первинний вузол.
try {
  rs.status();
} catch (e) {
  if (e.codeName === "NotYetInitialized") {
    rs.initiate({
      _id: "rs0",
      members: [
        { _id: 0, host: "mongo1:27017", priority: 2 },   // бажаний первинний вузол
        { _id: 1, host: "mongo2:27017", priority: 1 },
        { _id: 2, host: "mongo3:27017", priority: 1 }
      ]
    });
  } else {
    throw e;
  }
}
// healthcheck успішний, коли в наборі вже обрано первинний вузол
if (!rs.status().members.some(m => m.stateStr === "PRIMARY")) quit(1);
