-- =====================================================================
-- 06_create_users.sql — користувачі застосунку та ролі БД (рівень 3)
-- Паролі зберігаються лише як хеші PBKDF2-SHA256 (werkzeug.security).
-- Демо-облікові записи:
--   admin / admin123         — адміністратор (усе, журнал, резервні копії)
--   librarian / lib12345     — бібліотекар (CRUD каталогу, видачі, звіти)
--   kovalenko / reader123    — читач (каталог, свої видачі, бронювання)
-- =====================================================================

DROP TABLE IF EXISTS app_users CASCADE;

CREATE TABLE app_users (
    user_id       SERIAL PRIMARY KEY,
    username      VARCHAR(30)  NOT NULL UNIQUE CHECK (username ~ '^[a-z0-9_]{3,30}$'),
    password_hash VARCHAR(255) NOT NULL,
    role          VARCHAR(10)  NOT NULL DEFAULT 'reader'
                  CHECK (role IN ('admin', 'librarian', 'reader')),
    reader_id     INTEGER UNIQUE REFERENCES readers(reader_id) ON DELETE SET NULL,
    full_name     VARCHAR(100),
    is_active     BOOLEAN   NOT NULL DEFAULT TRUE,
    created_at    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    last_login    TIMESTAMP,
    -- обліковий запис читача обов'язково пов'язаний із читачем
    CONSTRAINT chk_reader_link CHECK (role <> 'reader' OR reader_id IS NOT NULL)
);

INSERT INTO app_users (username, password_hash, role, reader_id, full_name) VALUES
('admin', 'pbkdf2:sha256:200000$QEGHyDLciuWuPbri$2221ac95043dc23554b25ea1208b9943465b45effed021d5078f7fb5b5d863cf', 'admin', NULL, 'Головний адміністратор'),
('librarian', 'pbkdf2:sha256:200000$6oRzNJnZTqvs1kH1$10fde9a0c6c093b7ab66b760156e36333aab3902e3b2793a0e480a236711761f', 'librarian', NULL, 'Бібліотекар Ольга Петрук'),
('librarian2', 'pbkdf2:sha256:200000$zYUFpRIALRJiSvzr$dd9efc70ac1628b70d473931a800047bd85aea2e893d8fd1d748c8e232c2abfa', 'librarian', NULL, 'Бібліотекар Назар Сидорук'),
('kovalenko', 'pbkdf2:sha256:200000$gmrItssTNjBpug8E$d06afb43f551f348abde14e8b6899e2a7a64fc77e9c1ecee168ee7ff03295f8c', 'reader', 1, NULL),
('shevchuk', 'pbkdf2:sha256:200000$aQYGmI09kzhkPPHC$5b988e3b0738c1a73c924d3a716ad946fa73fca2ae5aba67eadb9dc1ea572e17', 'reader', 2, NULL),
('bondarenko', 'pbkdf2:sha256:200000$iomMkIn5hbUHTaJe$17ab7dc977f82204b16dfb18aa5016ba399b31a3f9bd6b252eb5083d6262a5e0', 'reader', 3, NULL),
('tkachenko', 'pbkdf2:sha256:200000$hZyzV9BcJPLuiFSE$141476598567065898ec1d307f2093fbe8416b5d9e87661afdbb25ae5fafb1c7', 'reader', 4, NULL),
('kravchenko', 'pbkdf2:sha256:200000$ZPcWdJQi6uBENjCO$167bacd6f7db7f5eec43cd4a35045b6adc8dab6e2d2cc77cea2b047d4d326b64', 'reader', 5, NULL),
('oliinyk', 'pbkdf2:sha256:200000$OUYDEK6T0PM5Fqzf$bf4ad8ebed47e9624d9c2253a3cd52b5967e1c92458e21d3086f9e4b97b00b77', 'reader', 6, NULL),
('melnyk', 'pbkdf2:sha256:200000$61GCijXdW7iohkg6$aaaaa0447591410c9938b718c983d049c61f9d6815a7d016da537659fcc34992', 'reader', 7, NULL),
('savchenko', 'pbkdf2:sha256:200000$y0vhATvzOpIkX2yT$b244dbe74b0bc681070fb8e327075c86ad7f7064483f11c55f4381cab30b4f99', 'reader', 8, NULL),
('polishchuk', 'pbkdf2:sha256:200000$TwLkeLn7AjLvzgYZ$8eba124eed5bc885257988e9044eeedb5999ad9449146e9188e3c4bba347aeb2', 'reader', 9, NULL),
('lysenko', 'pbkdf2:sha256:200000$DiEPpyNmIpT03HCi$d4410828525103a93039e0cdefeed1ad5288cdadbfbcea4d218fd9eff32f9d87', 'reader', 10, NULL);

-- ---------------------------------------------------------------------
-- Ролі PostgreSQL з розмежуванням прав (на рівні самої СУБД)
-- ---------------------------------------------------------------------
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'library_reader') THEN
        CREATE ROLE library_reader NOLOGIN;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'library_librarian') THEN
        CREATE ROLE library_librarian NOLOGIN;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'library_admin') THEN
        CREATE ROLE library_admin NOLOGIN;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'library_app') THEN
        CREATE ROLE library_app LOGIN PASSWORD 'app_password';
    END IF;
END
$$;

-- Читач: лише перегляд каталогу та представлень
GRANT USAGE ON SCHEMA public TO library_reader;
GRANT SELECT ON genres, publishers, authors, books, book_authors, reviews,
                v_books_catalog, v_genre_statistics TO library_reader;

-- Бібліотекар: права читача + робота з фондом, читачами, видачами
GRANT library_reader TO library_librarian;
GRANT SELECT, INSERT, UPDATE, DELETE
      ON genres, publishers, authors, books, book_authors, readers,
         loans, reservations, reviews TO library_librarian;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO library_librarian;
GRANT USAGE ON ALL SEQUENCES IN SCHEMA public TO library_librarian;

-- Адміністратор: усе, включно з користувачами
GRANT library_librarian TO library_admin;
GRANT ALL PRIVILEGES ON ALL TABLES    IN SCHEMA public TO library_admin;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO library_admin;

-- Обліковий запис вебзастосунку
GRANT library_admin TO library_app;

CREATE INDEX idx_app_users_role ON app_users (role);

-- Ім'я для облікових записів читачів беремо з таблиці readers
UPDATE app_users u
SET full_name = r.first_name || ' ' || r.last_name
FROM readers r
WHERE u.reader_id = r.reader_id AND u.full_name IS NULL;
