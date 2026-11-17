// Крок 15. Геопросторові індекси (2dsphere) і запити за координатами, а також TTL-індекс.
// Колекція branches — філії бібліотеки в Луцьку та області (координати умовні, GeoJSON: [довгота, широта]).

db.branches.drop();
db.branches.insertMany([
  { name: "Центральна бібліотека", address: "вул. Лесі Українки, 1, Луцьк", location: { type: "Point", coordinates: [25.3244, 50.7472] }, open_until: 19 },
  { name: "Філія №1 «Старе місто»", address: "вул. Кафедральна, 7, Луцьк", location: { type: "Point", coordinates: [25.3166, 50.7393] }, open_until: 18 },
  { name: "Філія №2 «33-й мікрорайон»", address: "просп. Відродження, 10, Луцьк", location: { type: "Point", coordinates: [25.3560, 50.7555] }, open_until: 18 },
  { name: "Філія №3 «Вересневе»", address: "вул. Володимирська, 85, Луцьк", location: { type: "Point", coordinates: [25.3050, 50.7680] }, open_until: 17 },
  { name: "Філія №4 «Гнідава»", address: "вул. Ківерцівська, 3, Луцьк", location: { type: "Point", coordinates: [25.3200, 50.7210] }, open_until: 17 },
  { name: "Бібліотека м. Ківерці", address: "вул. Грушевського, 2, Ківерці", location: { type: "Point", coordinates: [25.4916, 50.8335] }, open_until: 17 },
  { name: "Бібліотека с. Рокині", address: "вул. Незалежності, 14, Рокині", location: { type: "Point", coordinates: [25.2120, 50.7900] }, open_until: 16 }
]);
db.branches.createIndex({ location: "2dsphere" })

// Координати читачів (для запитів «найближча філія»)
db.users.updateOne({ username: "ivan_petrov" }, { $set: { "address.location": { type: "Point", coordinates: [25.3290, 50.7430] } } });
db.users.updateOne({ username: "oleksandr_sydorov" }, { $set: { "address.location": { type: "Point", coordinates: [25.4850, 50.8300] } } });
db.users.createIndex({ "address.location": "2dsphere" })

// $near: філії в радіусі 2 км від читача Івана, від найближчої (сортування за відстанню автоматичне)
db.branches.find(
  { location: { $near: { $geometry: db.users.findOne({ username: "ivan_petrov" }).address.location, $maxDistance: 2000 } } },
  { _id: 0, name: 1, address: 1 }
)

// $geoNear (агрегація): відстань у км до кожної філії від читача з Ківерців
db.branches.aggregate([
  { $geoNear: { near: db.users.findOne({ username: "oleksandr_sydorov" }).address.location,
                distanceField: "dist_m", spherical: true } },
  { $project: { _id: 0, name: 1, km: { $round: [{ $divide: ["$dist_m", 1000] }, 2] } } },
  { $limit: 4 }
])

// $geoWithin + $centerSphere: філії в межах 3 км від центру Луцька (радіус у радіанах = км / 6378.1)
db.branches.find(
  { location: { $geoWithin: { $centerSphere: [ [25.3254, 50.7472], 3 / 6378.1 ] } } },
  { _id: 0, name: 1 }
)

// $geoWithin + $polygon: які філії лежать у межах міста (спрощений полігон Луцька)
db.branches.countDocuments({ location: { $geoWithin: { $geometry: { type: "Polygon", coordinates: [[
  [25.27, 50.71], [25.39, 50.71], [25.39, 50.79], [25.27, 50.79], [25.27, 50.71] ]] } } } });

// План запиту: використовується геоіндекс
(function stages(p) { return p ? [p.stage + (p.indexName ? "(" + p.indexName + ")" : "")].concat(stages(p.inputStage)) : []; })
  (db.branches.find({ location: { $near: { $geometry: { type: "Point", coordinates: [25.32, 50.74] }, $maxDistance: 1500 } } })
     .explain().queryPlanner.winningPlan).join(" <- ")

// TTL-індекс: сесії входу автоматично видаляються через 30 с після created_at
db.sessions.drop();
db.sessions.createIndex({ created_at: 1 }, { expireAfterSeconds: 30 });
db.sessions.insertMany([
  { user: "ivan_petrov", token: "a1b2c3", created_at: new Date() },
  { user: "anna_melnyk", token: "d4e5f6", created_at: new Date() },
  { user: "librarian", token: "g7h8i9", created_at: new Date(Date.now() + 3600 * 1000) }
]);
({ sessions_now: db.sessions.countDocuments(), at: new Date().toLocaleTimeString("uk-UA") })

// Через ~1,5 хв дві старі сесії видалено автоматично; сесія з майбутньою датою ще жива
sleep(95000);   // TTL-монітор запускається раз на 60 с, тому чекаємо з запасом
({ sessions_left: db.sessions.find({}, { _id: 0, user: 1 }).toArray(), at: new Date().toLocaleTimeString("uk-UA") })
