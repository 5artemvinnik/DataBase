-- =====================================================================
-- 02_insert_data.sql — тестові дані (мінімум 10 записів на таблицю)
-- Дати видач задаються відносно CURRENT_DATE, щоб статуси (активна,
-- прострочена, повернена) були правильними в будь-який день запуску.
-- =====================================================================

-- Жанри (10)
INSERT INTO genres (name, description) VALUES
('Поезія',              'Віршовані твори'),
('Історичний роман',    'Художні твори на історичну тематику'),
('Драматургія',         'П''єси та драматичні поеми'),
('Сучасна проза',       'Українська та світова проза XXI століття'),
('Антиутопія',          'Твори про небажане суспільство майбутнього'),
('Наукова фантастика',  'Твори про науку, технології та майбутнє'),
('Фентезі',             'Твори з елементами магії та вигаданих світів'),
('Жахи',                'Література жахів і трилери'),
('Науково-популярна',   'Нехудожня література про науку та історію'),
('Класична проза',      'Класичні прозові твори XIX–XX століть');

-- Видавництва (10)
INSERT INTO publishers (name, city, country, phone, website) VALUES
('А-БА-БА-ГА-ЛА-МА-ГА',        'Київ',   'Україна', '+380442345678', 'ababahalamaha.com.ua'),
('Видавництво Старого Лева',   'Львів',  'Україна', '+380322409876', 'starylev.com.ua'),
('Клуб Сімейного Дозвілля',    'Харків', 'Україна', '+380577834512', 'bookclub.ua'),
('Фоліо',                      'Харків', 'Україна', '+380577143322', 'folio.com.ua'),
('Наш Формат',                 'Київ',   'Україна', '+380443339911', 'nashformat.ua'),
('Віват',                      'Харків', 'Україна', '+380577001122', 'vivat.com.ua'),
('Laurus',                     'Київ',   'Україна', '+380445556677', 'laurus.ua'),
('Темпора',                    'Київ',   'Україна', '+380442223344', 'tempora.com.ua'),
('Ранок',                      'Харків', 'Україна', '+380577190000', 'ranok.com.ua'),
('Meridian Czernowitz',        'Чернівці','Україна', '+380372512233', 'meridiancz.com');

-- Автори (15)
INSERT INTO authors (first_name, last_name, birth_year, death_year, country, biography) VALUES
('Тарас',      'Шевченко',     1814, 1861, 'Україна',        'Поет, художник, основоположник нової української літератури'),
('Іван',       'Франко',       1856, 1916, 'Україна',        'Письменник, поет, науковець, громадський діяч'),
('Леся',       'Українка',     1871, 1913, 'Україна',        'Поетеса, драматургиня, перекладачка'),
('Михайло',    'Коцюбинський', 1864, 1913, 'Україна',        'Майстер імпресіоністичної прози'),
('Ліна',       'Костенко',     1930, NULL, 'Україна',        'Поетеса, лауреатка Шевченківської премії'),
('Сергій',     'Жадан',        1974, NULL, 'Україна',        'Поет, прозаїк, музикант'),
('Марія',      'Матіос',       1959, NULL, 'Україна',        'Письменниця, авторка «Солодкої Дарусі»'),
('Андрій',     'Курков',       1961, NULL, 'Україна',        'Прозаїк, автор понад 20 романів'),
('Юрій',       'Андрухович',   1960, NULL, 'Україна',        'Поет, прозаїк, співзасновник «Бу-Ба-Бу»'),
('Оксана',     'Забужко',      1960, NULL, 'Україна',        'Письменниця, філософиня, есеїстка'),
('Джордж',     'Орвелл',       1903, 1950, 'Велика Британія','Автор «1984» та «Колгоспу тварин»'),
('Рей',        'Бредбері',     1920, 2012, 'США',            'Класик наукової фантастики'),
('Джоан',      'Роулінг',      1965, NULL, 'Велика Британія','Авторка серії про Гаррі Поттера'),
('Стівен',     'Кінг',         1947, NULL, 'США',            'Король жахів, автор понад 60 романів'),
('Юваль Ной',  'Харарі',       1976, NULL, 'Ізраїль',        'Історик, автор «Sapiens»');

-- Книги (20). available_copies буде перераховано наприкінці скрипта
INSERT INTO books (title, isbn, genre_id, publisher_id, publish_year, pages, language, price, total_copies, available_copies, description) VALUES
('Кобзар',                                  '978-966-7047-39-1',  1,  1, 2019, 704, 'українська', 450.00, 5, 5, 'Повне зібрання поетичних творів'),
('Захар Беркут',                            '978-966-03-4528-0',  2,  4, 2018, 192, 'українська', 120.00, 4, 4, 'Історична повість про боротьбу громади Тухлі'),
('Лісова пісня',                            '978-617-09-1123-4',  3,  9, 2020, 160, 'українська', 140.00, 3, 3, 'Драма-феєрія у трьох діях'),
('Інтернат',                                '978-617-614-189-3',  4, 10, 2017, 336, 'українська', 280.00, 3, 3, 'Роман про війну на Донбасі'),
('Ворошиловград',                           '978-966-03-5140-3',  4,  4, 2010, 448, 'українська', 260.00, 2, 2, 'Роман, «Книга десятиліття» BBC'),
('Маруся Чурай',                            '978-966-7047-61-2',  1,  1, 2015, 240, 'українська', 220.00, 4, 4, 'Історичний роман у віршах'),
('Записки українського самашедшого',        '978-966-7047-88-9',  4,  1, 2011, 416, 'українська', 300.00, 3, 3, 'Перший прозовий роман Ліни Костенко'),
('Солодка Даруся',                          '978-966-441-330-4',  4,  7, 2004, 240, 'українська', 210.00, 3, 3, 'Драма на три життя'),
('Сірі бджоли',                             '978-966-03-8821-8',  4,  4, 2018, 384, 'українська', 290.00, 2, 2, 'Роман про сіру зону Донбасу'),
('Московіада',                              '978-966-2355-80-6',  4,  8, 1993, 256, 'українська', 230.00, 2, 2, 'Роман жахів'),
('Музей покинутих секретів',                '978-966-8314-67-6',  4,  3, 2009, 832, 'українська', 380.00, 2, 2, 'Епічний роман про три покоління'),
('1984',                                    '978-617-12-1543-0',  5,  3, 2021, 320, 'українська', 250.00, 6, 6, 'Класична антиутопія'),
('Колгосп тварин',                          '978-617-12-1578-2',  5,  3, 2021, 128, 'українська', 160.00, 4, 4, 'Політична алегорія'),
('451° за Фаренгейтом',                     '978-617-12-0244-7',  6,  3, 2020, 208, 'українська', 190.00, 4, 4, 'Роман про світ, де книги спалюють'),
('Гаррі Поттер і філософський камінь',      '978-966-7047-34-6',  7,  1, 2016, 320, 'українська', 395.00, 7, 7, 'Перша книга серії'),
('Воно',                                    '978-966-14-9813-0',  8,  3, 2016, 1104,'українська', 520.00, 2, 2, 'Роман жахів про місто Деррі'),
('Sapiens. Людина розумна',                 '978-617-7279-36-8',  9,  5, 2018, 432, 'українська', 360.00, 5, 5, 'Коротка історія людства'),
('Тіні забутих предків',                    '978-966-03-7712-0', 10,  4, 2019, 128, 'українська', 110.00, 4, 4, 'Повість про гуцульське кохання'),
('Fata Morgana',                            '978-966-03-7713-7', 10,  4, 2019, 176, 'українська', 115.00, 2, 2, 'Повість про село на зламі епох'),
('Антологія українського модернізму',       '978-617-679-922-0', 10,  2, 2022, 512, 'українська', 420.00, 3, 3, 'Твори Франка, Українки та Коцюбинського');

-- Авторство (M:N, 23 записи)
INSERT INTO book_authors (book_id, author_id, author_order) VALUES
(1, 1, 1), (2, 2, 1), (3, 3, 1), (4, 6, 1), (5, 6, 1), (6, 5, 1), (7, 5, 1),
(8, 7, 1), (9, 8, 1), (10, 9, 1), (11, 10, 1), (12, 11, 1), (13, 11, 1),
(14, 12, 1), (15, 13, 1), (16, 14, 1), (17, 15, 1), (18, 4, 1), (19, 4, 1),
(20, 2, 1), (20, 3, 2), (20, 4, 3), (20, 1, 4);

-- Читачі (15)
INSERT INTO readers (ticket_number, first_name, last_name, email, phone, birth_date, address, registration_date, is_active) VALUES
('LIB-0001', 'Олександр', 'Коваленко',  'o.kovalenko@gmail.com',   '+380671234501', '1995-03-12', 'м. Луцьк, вул. Лесі Українки, 12',     CURRENT_DATE - 720, TRUE),
('LIB-0002', 'Марія',     'Шевчук',     'maria.shevchuk@ukr.net',  '+380502345602', '2001-07-25', 'м. Луцьк, просп. Волі, 5',              CURRENT_DATE - 650, TRUE),
('LIB-0003', 'Андрій',    'Бондаренко', 'a.bondarenko@gmail.com',  '+380933456703', '1988-11-02', 'м. Луцьк, вул. Винниченка, 30',        CURRENT_DATE - 600, TRUE),
('LIB-0004', 'Олена',     'Ткаченко',   'olena.tk@gmail.com',      '+380674567804', '1999-01-17', 'м. Ковель, вул. Незалежності, 8',      CURRENT_DATE - 540, TRUE),
('LIB-0005', 'Дмитро',    'Кравченко',  'd.kravchenko@ukr.net',    '+380985678905', '2003-05-30', 'м. Луцьк, вул. Карпенка-Карого, 3',    CURRENT_DATE - 500, TRUE),
('LIB-0006', 'Наталія',   'Олійник',    'n.oliinyk@gmail.com',     '+380636789006', '1992-09-09', 'м. Луцьк, вул. Кривий Вал, 17',        CURRENT_DATE - 430, TRUE),
('LIB-0007', 'Ігор',      'Мельник',    'igor.melnyk@i.ua',        '+380667890107', '1985-12-21', 'м. Володимир, вул. Ковельська, 44',    CURRENT_DATE - 400, TRUE),
('LIB-0008', 'Юлія',      'Савченко',   'yulia.savchenko@gmail.com','+380678901208', '2004-02-14', 'м. Луцьк, вул. Рівненська, 101',      CURRENT_DATE - 350, TRUE),
('LIB-0009', 'Максим',    'Поліщук',    'max.polishchuk@ukr.net',  '+380509012309', '1997-06-06', 'м. Луцьк, вул. Гнідавська, 9',         CURRENT_DATE - 300, TRUE),
('LIB-0010', 'Анастасія', 'Лисенко',    'a.lysenko@gmail.com',     '+380931234510', '2002-10-01', 'м. Ківерці, вул. Грушевського, 2',     CURRENT_DATE - 250, TRUE),
('LIB-0011', 'Віктор',    'Гончаренко', 'v.honcharenko@i.ua',      '+380982345611', '1979-04-18', 'м. Луцьк, вул. Конякіна, 21',          CURRENT_DATE - 200, TRUE),
('LIB-0012', 'Софія',     'Руденко',    'sofia.rudenko@gmail.com', '+380633456712', '2005-08-27', 'м. Луцьк, вул. Шопена, 14',            CURRENT_DATE - 150, TRUE),
('LIB-0013', 'Богдан',    'Марченко',   'b.marchenko@ukr.net',     '+380664567813', '1990-12-03', 'м. Луцьк, вул. Глушець, 6',            CURRENT_DATE - 120, TRUE),
('LIB-0014', 'Ірина',     'Захарченко', 'iryna.z@gmail.com',       '+380675678914', '1998-03-29', 'м. Ковель, вул. Сагайдачного, 11',     CURRENT_DATE - 60,  TRUE),
('LIB-0015', 'Тарас',     'Ковальчук',  't.kovalchuk@i.ua',        '+380506789015', '1983-07-07', 'м. Луцьк, вул. Задворецька, 25',       CURRENT_DATE - 30,  FALSE);

-- Видачі (25): повернені, активні, прострочені
INSERT INTO loans (book_id, reader_id, loan_date, due_date, return_date, status, extensions_count, fine_amount) VALUES
-- повернені вчасно
( 1,  1, CURRENT_DATE - 200, CURRENT_DATE - 186, CURRENT_DATE - 190, 'returned', 0, 0),
(12,  2, CURRENT_DATE - 180, CURRENT_DATE - 166, CURRENT_DATE - 170, 'returned', 0, 0),
(15,  3, CURRENT_DATE - 170, CURRENT_DATE - 156, CURRENT_DATE - 160, 'returned', 0, 0),
(17,  4, CURRENT_DATE - 160, CURRENT_DATE - 146, CURRENT_DATE - 150, 'returned', 0, 0),
( 6,  5, CURRENT_DATE - 150, CURRENT_DATE - 136, CURRENT_DATE - 140, 'returned', 0, 0),
(14,  6, CURRENT_DATE - 140, CURRENT_DATE - 126, CURRENT_DATE - 128, 'returned', 0, 0),
(12,  7, CURRENT_DATE - 130, CURRENT_DATE - 116, CURRENT_DATE - 118, 'returned', 0, 0),
(15,  8, CURRENT_DATE - 120, CURRENT_DATE - 106, CURRENT_DATE - 110, 'returned', 1, 0),
( 4,  9, CURRENT_DATE - 100, CURRENT_DATE -  86, CURRENT_DATE -  90, 'returned', 0, 0),
( 8, 10, CURRENT_DATE -  90, CURRENT_DATE -  76, CURRENT_DATE -  80, 'returned', 0, 0),
(17,  1, CURRENT_DATE -  80, CURRENT_DATE -  66, CURRENT_DATE -  70, 'returned', 0, 0),
(13,  2, CURRENT_DATE -  70, CURRENT_DATE -  56, CURRENT_DATE -  60, 'returned', 0, 0),
-- повернені із запізненням (штраф 5 грн/день)
( 7,  3, CURRENT_DATE - 110, CURRENT_DATE -  96, CURRENT_DATE -  90, 'returned', 0, 30),
(16, 11, CURRENT_DATE -  75, CURRENT_DATE -  61, CURRENT_DATE -  51, 'returned', 0, 50),
(11, 12, CURRENT_DATE -  65, CURRENT_DATE -  51, CURRENT_DATE -  48, 'returned', 0, 15),
-- активні
(12,  1, CURRENT_DATE -  10, CURRENT_DATE +   4, NULL, 'active', 0, 0),
(15,  2, CURRENT_DATE -   7, CURRENT_DATE +   7, NULL, 'active', 0, 0),
( 2,  4, CURRENT_DATE -   5, CURRENT_DATE +   9, NULL, 'active', 0, 0),
(17,  5, CURRENT_DATE -  12, CURRENT_DATE +   9, NULL, 'active', 1, 0),
( 5,  6, CURRENT_DATE -   3, CURRENT_DATE +  11, NULL, 'active', 0, 0),
(18,  8, CURRENT_DATE -   2, CURRENT_DATE +  12, NULL, 'active', 0, 0),
( 1, 13, CURRENT_DATE -   1, CURRENT_DATE +  13, NULL, 'active', 0, 0),
-- прострочені
(16,  7, CURRENT_DATE -  25, CURRENT_DATE -  11, NULL, 'overdue', 0, 0),
( 9,  9, CURRENT_DATE -  20, CURRENT_DATE -   6, NULL, 'overdue', 0, 0),
(14, 11, CURRENT_DATE -  18, CURRENT_DATE -   4, NULL, 'overdue', 0, 0);

-- Бронювання (10)
INSERT INTO reservations (book_id, reader_id, reservation_date, expires_at, status) VALUES
( 5,  1, CURRENT_TIMESTAMP - INTERVAL '1 day',   CURRENT_TIMESTAMP + INTERVAL '2 days', 'pending'),
(16,  3, CURRENT_TIMESTAMP - INTERVAL '2 days',  CURRENT_TIMESTAMP + INTERVAL '1 day',  'pending'),
( 9, 10, CURRENT_TIMESTAMP - INTERVAL '5 hours', CURRENT_TIMESTAMP + INTERVAL '3 days', 'pending'),
(12, 14, CURRENT_TIMESTAMP - INTERVAL '3 hours', CURRENT_TIMESTAMP + INTERVAL '3 days', 'pending'),
(15,  6, CURRENT_TIMESTAMP - INTERVAL '30 days', CURRENT_TIMESTAMP - INTERVAL '27 days','fulfilled'),
(17,  5, CURRENT_TIMESTAMP - INTERVAL '14 days', CURRENT_TIMESTAMP - INTERVAL '11 days','fulfilled'),
( 3,  2, CURRENT_TIMESTAMP - INTERVAL '20 days', CURRENT_TIMESTAMP - INTERVAL '17 days','cancelled'),
(11,  4, CURRENT_TIMESTAMP - INTERVAL '40 days', CURRENT_TIMESTAMP - INTERVAL '37 days','expired'),
( 4, 12, CURRENT_TIMESTAMP - INTERVAL '10 days', CURRENT_TIMESTAMP - INTERVAL '7 days', 'expired'),
( 7,  8, CURRENT_TIMESTAMP - INTERVAL '6 hours', CURRENT_TIMESTAMP + INTERVAL '3 days', 'pending');

-- Відгуки (15)
INSERT INTO reviews (book_id, reader_id, rating, comment, created_at) VALUES
( 1,  1, 5, 'Вічна класика, кожен вірш — як молитва',          CURRENT_TIMESTAMP - INTERVAL '190 days'),
(12,  2, 5, 'Страшно, наскільки актуально',                    CURRENT_TIMESTAMP - INTERVAL '170 days'),
(15,  3, 5, 'Чудовий переклад, читав з дітьми',                CURRENT_TIMESTAMP - INTERVAL '160 days'),
(17,  4, 4, 'Цікаво, але місцями спірно',                      CURRENT_TIMESTAMP - INTERVAL '150 days'),
( 6,  5, 5, 'Неймовірна мова',                                 CURRENT_TIMESTAMP - INTERVAL '140 days'),
(14,  6, 4, 'Коротко і влучно',                                CURRENT_TIMESTAMP - INTERVAL '128 days'),
(12,  7, 4, 'Важка, але потрібна книга',                       CURRENT_TIMESTAMP - INTERVAL '118 days'),
(15,  8, 5, 'Повернулась у дитинство',                         CURRENT_TIMESTAMP - INTERVAL '110 days'),
( 4,  9, 5, 'Найсильніша книга про війну',                     CURRENT_TIMESTAMP - INTERVAL '90 days'),
( 8, 10, 5, 'Плакала на останніх сторінках',                   CURRENT_TIMESTAMP - INTERVAL '80 days'),
(17,  1, 5, 'Змінила погляд на історію',                       CURRENT_TIMESTAMP - INTERVAL '70 days'),
(13,  2, 4, 'Гостра сатира',                                   CURRENT_TIMESTAMP - INTERVAL '60 days'),
( 7,  3, 3, 'Цікава, але затягнута',                           CURRENT_TIMESTAMP - INTERVAL '90 days'),
(16, 11, 4, 'Страшно і довго, але варто',                      CURRENT_TIMESTAMP - INTERVAL '50 days'),
(11, 12, 5, 'Глибокий роман про пам''ять',                     CURRENT_TIMESTAMP - INTERVAL '48 days');

-- Узгоджуємо кількість доступних примірників з активними видачами
UPDATE books b
SET available_copies = b.total_copies - (
    SELECT COUNT(*) FROM loans l
    WHERE l.book_id = b.book_id AND l.return_date IS NULL
);
