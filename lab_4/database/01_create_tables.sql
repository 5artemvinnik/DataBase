-- =====================================================================
-- Лабораторна робота 4. Електронна бібліотека
-- 01_create_tables.sql — фізична структура бази даних (3НФ)
-- =====================================================================

-- Видаляємо таблиці у зворотному порядку залежностей (для повторного запуску)
DROP TABLE IF EXISTS reviews, reservations, loans, book_authors, books,
                     readers, authors, publishers, genres CASCADE;

-- ---------------------------------------------------------------------
-- Жанри книг (довідник)
-- ---------------------------------------------------------------------
CREATE TABLE genres (
    genre_id    SERIAL PRIMARY KEY,
    name        VARCHAR(50)  NOT NULL UNIQUE,
    description TEXT
);

-- ---------------------------------------------------------------------
-- Видавництва (довідник)
-- ---------------------------------------------------------------------
CREATE TABLE publishers (
    publisher_id SERIAL PRIMARY KEY,
    name         VARCHAR(100) NOT NULL UNIQUE,
    city         VARCHAR(50)  NOT NULL,
    country      VARCHAR(50)  NOT NULL DEFAULT 'Україна',
    phone        VARCHAR(20)  CHECK (phone ~ '^\+?[0-9 ()-]{7,20}$'),
    website      VARCHAR(100)
);

-- ---------------------------------------------------------------------
-- Автори
-- ---------------------------------------------------------------------
CREATE TABLE authors (
    author_id  SERIAL PRIMARY KEY,
    first_name VARCHAR(50) NOT NULL,
    last_name  VARCHAR(50) NOT NULL,
    birth_year INTEGER CHECK (birth_year BETWEEN 1000 AND 2025),
    death_year INTEGER,
    country    VARCHAR(50),
    biography  TEXT,
    -- рік смерті не може бути меншим за рік народження
    CONSTRAINT chk_author_years CHECK (death_year IS NULL OR death_year >= birth_year)
);

-- ---------------------------------------------------------------------
-- Книги
-- ---------------------------------------------------------------------
CREATE TABLE books (
    book_id          SERIAL PRIMARY KEY,
    title            VARCHAR(200) NOT NULL,
    isbn             VARCHAR(17)  NOT NULL UNIQUE
                     CHECK (isbn ~ '^(97[89]-?)?[0-9-]{9,13}[0-9X]$'),
    genre_id         INTEGER NOT NULL REFERENCES genres(genre_id)
                     ON UPDATE CASCADE ON DELETE RESTRICT,
    publisher_id     INTEGER REFERENCES publishers(publisher_id)
                     ON UPDATE CASCADE ON DELETE SET NULL,
    publish_year     INTEGER CHECK (publish_year BETWEEN 1450 AND 2026),
    pages            INTEGER CHECK (pages > 0),
    language         VARCHAR(30)  NOT NULL DEFAULT 'українська',
    price            NUMERIC(8,2) NOT NULL DEFAULT 0 CHECK (price >= 0),
    total_copies     INTEGER NOT NULL DEFAULT 1 CHECK (total_copies >= 0),
    available_copies INTEGER NOT NULL DEFAULT 1 CHECK (available_copies >= 0),
    description      TEXT,
    created_at       TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at       TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    -- доступних примірників не може бути більше, ніж усього
    CONSTRAINT chk_copies CHECK (available_copies <= total_copies)
);

-- ---------------------------------------------------------------------
-- Зв'язок «багато-до-багатьох» між книгами та авторами
-- ---------------------------------------------------------------------
CREATE TABLE book_authors (
    book_id      INTEGER NOT NULL REFERENCES books(book_id)   ON DELETE CASCADE,
    author_id    INTEGER NOT NULL REFERENCES authors(author_id) ON DELETE CASCADE,
    author_order SMALLINT NOT NULL DEFAULT 1 CHECK (author_order > 0),
    PRIMARY KEY (book_id, author_id)
);

-- ---------------------------------------------------------------------
-- Читачі
-- ---------------------------------------------------------------------
CREATE TABLE readers (
    reader_id         SERIAL PRIMARY KEY,
    ticket_number     VARCHAR(10)  NOT NULL UNIQUE CHECK (ticket_number ~ '^LIB-[0-9]{4,6}$'),
    first_name        VARCHAR(50)  NOT NULL,
    last_name         VARCHAR(50)  NOT NULL,
    email             VARCHAR(100) NOT NULL UNIQUE
                      CHECK (email ~* '^[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}$'),
    phone             VARCHAR(20)  CHECK (phone ~ '^\+?[0-9 ()-]{7,20}$'),
    birth_date        DATE CHECK (birth_date > DATE '1900-01-01'),
    address           VARCHAR(200),
    registration_date DATE    NOT NULL DEFAULT CURRENT_DATE,
    is_active         BOOLEAN NOT NULL DEFAULT TRUE
);

-- ---------------------------------------------------------------------
-- Видачі книг
-- ---------------------------------------------------------------------
CREATE TABLE loans (
    loan_id          SERIAL PRIMARY KEY,
    book_id          INTEGER NOT NULL REFERENCES books(book_id)    ON DELETE RESTRICT,
    reader_id        INTEGER NOT NULL REFERENCES readers(reader_id) ON DELETE RESTRICT,
    loan_date        DATE NOT NULL DEFAULT CURRENT_DATE,
    due_date         DATE NOT NULL,
    return_date      DATE,
    status           VARCHAR(10) NOT NULL DEFAULT 'active'
                     CHECK (status IN ('active', 'returned', 'overdue', 'lost')),
    extensions_count SMALLINT NOT NULL DEFAULT 0 CHECK (extensions_count BETWEEN 0 AND 2),
    fine_amount      NUMERIC(8,2) NOT NULL DEFAULT 0 CHECK (fine_amount >= 0),
    CONSTRAINT chk_due_date    CHECK (due_date > loan_date),
    CONSTRAINT chk_return_date CHECK (return_date IS NULL OR return_date >= loan_date),
    -- повернена книга обов'язково має дату повернення
    CONSTRAINT chk_returned    CHECK (status <> 'returned' OR return_date IS NOT NULL)
);

-- ---------------------------------------------------------------------
-- Бронювання книг
-- ---------------------------------------------------------------------
CREATE TABLE reservations (
    reservation_id   SERIAL PRIMARY KEY,
    book_id          INTEGER NOT NULL REFERENCES books(book_id)    ON DELETE CASCADE,
    reader_id        INTEGER NOT NULL REFERENCES readers(reader_id) ON DELETE CASCADE,
    reservation_date TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    expires_at       TIMESTAMP NOT NULL DEFAULT (CURRENT_TIMESTAMP + INTERVAL '3 days'),
    status           VARCHAR(10) NOT NULL DEFAULT 'pending'
                     CHECK (status IN ('pending', 'fulfilled', 'cancelled', 'expired')),
    CONSTRAINT chk_expires CHECK (expires_at > reservation_date)
);

-- Один читач може мати лише одне активне бронювання на конкретну книгу
CREATE UNIQUE INDEX uq_reservation_pending
    ON reservations (book_id, reader_id) WHERE status = 'pending';

-- ---------------------------------------------------------------------
-- Відгуки читачів
-- ---------------------------------------------------------------------
CREATE TABLE reviews (
    review_id  SERIAL PRIMARY KEY,
    book_id    INTEGER  NOT NULL REFERENCES books(book_id)    ON DELETE CASCADE,
    reader_id  INTEGER  NOT NULL REFERENCES readers(reader_id) ON DELETE CASCADE,
    rating     SMALLINT NOT NULL CHECK (rating BETWEEN 1 AND 5),
    comment    TEXT,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uq_review UNIQUE (book_id, reader_id)   -- один відгук на книгу від читача
);

-- ---------------------------------------------------------------------
-- Індекси для прискорення типових запитів (рівень 3, оптимізація)
-- ---------------------------------------------------------------------
CREATE INDEX idx_books_genre        ON books (genre_id);
CREATE INDEX idx_books_publisher    ON books (publisher_id);
CREATE INDEX idx_books_title_lower  ON books (LOWER(title));              -- пошук за назвою
CREATE INDEX idx_book_authors_author ON book_authors (author_id);
CREATE INDEX idx_readers_last_name  ON readers (LOWER(last_name));
CREATE INDEX idx_loans_reader       ON loans (reader_id);
CREATE INDEX idx_loans_book         ON loans (book_id);
CREATE INDEX idx_loans_open         ON loans (due_date) WHERE return_date IS NULL;  -- частковий індекс
CREATE INDEX idx_loans_loan_date    ON loans (loan_date);
CREATE INDEX idx_reservations_book  ON reservations (book_id, status);
CREATE INDEX idx_reviews_book       ON reviews (book_id);

COMMENT ON TABLE books        IS 'Каталог книг бібліотеки';
COMMENT ON TABLE book_authors IS 'Зв''язок M:N між книгами та авторами';
COMMENT ON TABLE loans        IS 'Видачі книг читачам';
COMMENT ON TABLE reservations IS 'Бронювання книг';
