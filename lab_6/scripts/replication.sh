#!/bin/bash
# Крок 18. Реплікація: набір реплік rs0 з трьох вузлів (mongo1, mongo2, mongo3).
#  1. Стан набору і ролі вузлів.
#  2. Запис з writeConcern majority на первинний вузол і читання з вторинного.
#  3. Автоматичне перемикання (failover): зупиняємо первинний вузол і дивимось вибори.
#  4. Повернення вузла: він наздоганяє зміни і знову стає первинним (priority 2).
# Запуск з папки lab_6:  bash scripts/replication.sh
ENGINE=${ENGINE:-$(command -v podman >/dev/null 2>&1 && echo podman || echo docker)}   # Podman або Docker
RS="mongodb://mongo1,mongo2,mongo3/library?replicaSet=rs0"
m() { $ENGINE exec "$1" mongosh --quiet "${@:2}"; }              # m <контейнер> <параметри mongosh>
members='rs.status().members.map(x => ({ node: x.name, state: x.stateStr, health: x.health, optime: x.health ? x.optimeDate.toLocaleTimeString("uk-UA") : "—" }))'

echo "=== 1. Стан набору реплік"
m library_mongo1 --eval "console.table($members)"

echo "=== 2. Запис з підтвердженням більшості вузлів (w: majority) через рядок підключення до набору"
m library_mongo1 "$RS" --eval '
  db.replication_test.drop();
  printjson(db.replication_test.insertOne({ msg: "запис для перевірки реплікації", at: new Date() }, { writeConcern: { w: "majority", wtimeout: 5000 } }));'
echo "--- Читання того самого документа безпосередньо з вторинного вузла mongo3"
m library_mongo3 --eval 'db.getMongo().setReadPref("secondary");
  printjson(db.getSiblingDB("library").replication_test.findOne({}, { _id: 0 }));
  print("книг на mongo3: " + db.getSiblingDB("library").books.countDocuments() + ", вузол: " + db.hello().me + ", первинний: " + db.hello().isWritablePrimary)'
echo "--- Спроба запису напряму у вторинний вузол"
m library_mongo3 --eval 'try { db.getSiblingDB("library").replication_test.insertOne({ x: 1 }) } catch (e) { print(e.name + ": " + e.message) }'

echo
echo "=== 3. Аварія: зупиняємо первинний вузол mongo1 ($(date +%T))"
$ENGINE stop -t 30 library_mongo1 >/dev/null 2>&1
sleep 15
m library_mongo2 --eval "console.table($members)"
echo "--- Запис через рядок підключення до набору: драйвер сам знаходить новий первинний вузол"
m library_mongo2 "$RS" --eval '
  const r = db.replication_test.insertOne({ msg: "запис під час аварії mongo1", at: new Date() }, { writeConcern: { w: "majority" } });
  print("вставлено " + r.insertedId + " на вузол " + db.hello().primary)'

echo
echo "=== 4. Запускаємо mongo1 знову ($(date +%T))"
$ENGINE start library_mongo1 >/dev/null
sleep 25
m library_mongo1 --eval "console.table($members)"
m library_mongo1 --eval 'db.getMongo().setReadPref("primaryPreferred");
  print("документів у replication_test на mongo1 після повернення: " + db.getSiblingDB("library").replication_test.countDocuments())'
