-- =====================================================================
-- 08_validation_triggers.sql — тригери валідації перед вставкою (рівень 2)
--
-- BEFORE-тригер може змінити рядок (нормалізація) або відхилити його
-- через RAISE EXCEPTION. Помилки мають власний код SQLSTATE, DETAIL та
-- HINT, щоб застосунок міг показати користувачу зрозуміле повідомлення.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Читачі: нормалізація та перевірка даних
--    * пробіли на краях прибираються, ім'я та прізвище — з великої літери;
--    * email переводиться в нижній регістр, телефон — у формат +380XXXXXXXXX;
--    * ім'я без цифр, вік від 6 до 120 років, дата народження не в майбутньому.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_validate_reader()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE
    v_digits TEXT;
BEGIN
    -- нормалізація
    NEW.first_name := INITCAP(BTRIM(NEW.first_name));
    NEW.last_name  := INITCAP(BTRIM(NEW.last_name));
    NEW.email      := LOWER(BTRIM(NEW.email));

    IF NEW.first_name ~ '[0-9]' OR NEW.last_name ~ '[0-9]' THEN
        RAISE EXCEPTION 'Ім''я та прізвище не можуть містити цифр: "% %"', NEW.last_name, NEW.first_name
            USING ERRCODE = 'check_violation',
                  HINT    = 'Перевірте правильність введення ПІБ';
    END IF;

    IF NEW.phone IS NOT NULL THEN
        v_digits := regexp_replace(NEW.phone, '[^0-9]', '', 'g');   -- лише цифри
        IF v_digits ~ '^0[0-9]{9}$' THEN                             -- 0671234567
            v_digits := '38' || v_digits;
        END IF;
        IF v_digits !~ '^380[0-9]{9}$' THEN
            RAISE EXCEPTION 'Некоректний номер телефону: %', NEW.phone
                USING ERRCODE = 'check_violation',
                      DETAIL  = 'Очікується український номер з 12 цифр',
                      HINT    = 'Приклад: +380671234567 або 067 123 45 67';
        END IF;
        NEW.phone := '+' || v_digits;
    END IF;

    IF NEW.birth_date IS NOT NULL THEN
        IF NEW.birth_date > CURRENT_DATE THEN
            RAISE EXCEPTION 'Дата народження % у майбутньому', NEW.birth_date
                USING ERRCODE = 'check_violation';
        ELSIF AGE(NEW.birth_date) < INTERVAL '6 years' THEN
            RAISE EXCEPTION 'Читачу має бути щонайменше 6 років (вік: %)',
                            EXTRACT(YEAR FROM AGE(NEW.birth_date))
                USING ERRCODE = 'check_violation',
                      HINT    = 'Дітей до 6 років записують через батьків';
        ELSIF AGE(NEW.birth_date) > INTERVAL '120 years' THEN
            RAISE EXCEPTION 'Неправдоподібна дата народження: %', NEW.birth_date
                USING ERRCODE = 'check_violation';
        END IF;
    END IF;

    RETURN NEW;          -- повертаємо змінений (нормалізований) рядок
END;
$$;

DROP TRIGGER IF EXISTS trg_readers_validate ON readers;
CREATE TRIGGER trg_readers_validate
BEFORE INSERT OR UPDATE OF first_name, last_name, email, phone, birth_date ON readers
FOR EACH ROW EXECUTE FUNCTION fn_validate_reader();

-- ---------------------------------------------------------------------
-- 2. Відгуки: бізнес-правила
--    * залишити відгук може лише читач, який брав цю книгу;
--    * заблокований читач відгуків не залишає;
--    * коментар не довший за 1000 символів, порожній коментар -> NULL.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_validate_review()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    NEW.comment := NULLIF(BTRIM(NEW.comment), '');

    IF NOT (SELECT is_active FROM readers WHERE reader_id = NEW.reader_id) THEN
        RAISE EXCEPTION 'Читач % заблокований і не може залишати відгуки', NEW.reader_id
            USING ERRCODE = 'insufficient_privilege';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM loans
                   WHERE reader_id = NEW.reader_id AND book_id = NEW.book_id) THEN
        RAISE EXCEPTION 'Читач % не брав книгу % — відгук неможливий', NEW.reader_id, NEW.book_id
            USING ERRCODE = 'check_violation',
                  DETAIL  = 'Відгуки приймаються лише від читачів, які отримували книгу',
                  HINT    = 'Спочатку візьміть книгу в бібліотеці';
    END IF;

    IF length(NEW.comment) > 1000 THEN
        RAISE EXCEPTION 'Коментар задовгий: % символів (максимум 1000)', length(NEW.comment)
            USING ERRCODE = 'string_data_right_truncation';
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_reviews_validate ON reviews;
CREATE TRIGGER trg_reviews_validate
BEFORE INSERT ON reviews
FOR EACH ROW EXECUTE FUNCTION fn_validate_review();

-- ---------------------------------------------------------------------
-- Перевірка: коректні дані нормалізуються
-- ---------------------------------------------------------------------
INSERT INTO readers (ticket_number, first_name, last_name, email, phone, birth_date)
VALUES ('LIB-200001', '  олена ', 'ПЕТРЕНКО  ', '  Olena.Petrenko@Example.COM ', '067 555-44-33', '2001-05-20')
RETURNING reader_id, first_name, last_name, email, phone;

-- ---------------------------------------------------------------------
-- Перевірка: некоректні дані відхиляються. Кожна спроба виконується в
-- окремому блоці з обробником EXCEPTION, тож скрипт не зупиняється, а
-- ми бачимо код помилки (SQLSTATE), повідомлення та підказку.
-- ---------------------------------------------------------------------
DO $$
DECLARE
    v_tests TEXT[] := ARRAY[
        $t$INSERT INTO readers (ticket_number, first_name, last_name, email) VALUES ('LIB-200002', 'Іван2', 'Петров', 'ivan@example.com')$t$,
        $t$INSERT INTO readers (ticket_number, first_name, last_name, email, phone) VALUES ('LIB-200003', 'Іван', 'Петров', 'ivan@example.com', '12345')$t$,
        $t$INSERT INTO readers (ticket_number, first_name, last_name, email, birth_date) VALUES ('LIB-200004', 'Іван', 'Петров', 'ivan@example.com', CURRENT_DATE - 365)$t$,
        $t$INSERT INTO reviews (book_id, reader_id, rating, comment) VALUES (1, 15, 5, 'Чудова книга')$t$,
        $t$INSERT INTO reviews (book_id, reader_id, rating) VALUES (20, 3, 4)$t$
    ];
    v_sql TEXT; v_state TEXT; v_msg TEXT; v_hint TEXT;
BEGIN
    FOREACH v_sql IN ARRAY v_tests LOOP
        BEGIN
            EXECUTE v_sql;
            RAISE NOTICE 'УСПІХ (неочікувано): %', v_sql;
        EXCEPTION WHEN OTHERS THEN
            GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE,
                                    v_msg   = MESSAGE_TEXT,
                                    v_hint  = PG_EXCEPTION_HINT;
            RAISE NOTICE 'ВІДХИЛЕНО [%] % %', v_state, v_msg,
                         CASE WHEN v_hint <> '' THEN '(підказка: ' || v_hint || ')' ELSE '' END;
        END;
    END LOOP;
END
$$;
