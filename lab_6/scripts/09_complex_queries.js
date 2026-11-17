// Крок 8. Складні запити з $and, $or, $in, $regex та іншими операторами.

// $and — дві умови на те саме поле не можна записати одним об'єктом, тому явний $and:
// книги, що мають жанр «романтизм» І жанр, відмінний від «поезії»
db.books.find(
  { $and: [ { genres: "романтизм" }, { genres: { $nin: ["поезія"] } } ] },
  { _id: 0, title: 1, genres: 1 }
)

// $or — короткі (до 100 сторінок) АБО видані після 1940 року
db.books.find(
  { $or: [ { pages: { $lte: 100 } }, { publication_year: { $gt: 1940 } } ] },
  { _id: 0, title: 1, pages: 1, publication_year: 1 }
)

// $in — книги кількох авторів; $nin — читачі з усіх міст, крім Луцька
db.books.find({ author: { $in: ["Леся Українка", "Ліна Костенко", "Сергій Жадан"] } }, { _id: 0, title: 1, author: 1 })

db.users.find({ "address.city": { $nin: ["Луцьк"] } }, { _id: 0, username: 1, address: 1 })

// $regex — назва починається на «Т» (без урахування регістру) і опис містить «кохан»
db.books.find(
  { title: { $regex: "^т", $options: "i" }, description: { $regex: /кохан/ } },
  { _id: 0, title: 1, description: 1 }
)

// $regex для пошти: читачі з поштою на email.com, у яких логін містить цифру або «ko»
db.users.find({ email: /@email\.com$/, username: { $regex: "ko|\\d" } }, { _id: 0, username: 1, email: 1 })

// Комбінація $and + $or + $in + $elemMatch: доступні книги жанру роман/повість,
// що мають хоча б одну оцінку 5 від читача ivan_petrov або anna_melnyk
db.books.find({
  $and: [
    { available: true },
    { genres: { $in: ["роман", "повість"] } },
    { $or: [
        { ratings: { $elemMatch: { user: "ivan_petrov", score: 5 } } },
        { ratings: { $elemMatch: { user: "anna_melnyk", score: 5 } } }
    ] }
  ]
}, { _id: 0, title: 1, "ratings.user": 1 })

// $all, $size і $not: книги, що мають одночасно жанри «повість» і «романтизм»; книги не з трьома жанрами
db.books.find({ genres: { $all: ["повість", "романтизм"] } }, { _id: 0, title: 1, genres: 1 })

db.books.find({ genres: { $not: { $size: 3 } }, pages: { $not: { $lt: 200 } } }, { _id: 0, title: 1, pages: 1 })
