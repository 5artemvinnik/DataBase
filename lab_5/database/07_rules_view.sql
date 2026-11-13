-- =====================================================================
-- 07_rules_view.sql — складне представлення, що оновлюється через правила (рівень 2)
--
-- v_reader_cards — «картка читача»: дані з readers + обліковий запис з
-- app_users + обчислені поля (книг на руках, борг). Через JOIN, підзапити
-- та обчислення PostgreSQL не вважає таке представлення автоматично
-- оновлюваним, тому поведінку INSERT / UPDATE / DELETE задають правила
-- (RULE ... DO INSTEAD), які переписують запит до базових таблиць.
-- =====================================================================

DROP VIEW IF EXISTS v_reader_cards CASCADE;

CREATE VIEW v_reader_cards AS
SELECT r.reader_id,
       r.ticket_number,
       r.last_name,
       r.first_name,
       r.email,
       r.phone,
       r.address,
       r.is_active,
       u.username,                                              -- з таблиці app_users
       u.role,
       (SELECT COUNT(*) FROM loans l
        WHERE l.reader_id = r.reader_id AND l.return_date IS NULL)      AS books_on_hand,
       (SELECT COALESCE(SUM(GREATEST(CURRENT_DATE - l.due_date, 0)), 0) * 5.00
        FROM loans l
        WHERE l.reader_id = r.reader_id AND l.return_date IS NULL)      AS current_debt
FROM readers r
LEFT JOIN app_users u ON u.reader_id = r.reader_id;

COMMENT ON VIEW v_reader_cards IS 'Картка читача; оновлюється через правила (RULES)';

-- ---------------------------------------------------------------------
-- UPDATE: змінювати можна лише контактні дані та статус; обчислювані
-- поля (books_on_hand, current_debt), квиток і логін змінити не можна.
-- Блокування читача одночасно блокує і його обліковий запис.
-- ---------------------------------------------------------------------
CREATE RULE r_reader_cards_update AS
ON UPDATE TO v_reader_cards
DO INSTEAD (
    UPDATE app_users
       SET is_active = NEW.is_active
     WHERE reader_id = OLD.reader_id
       AND is_active IS DISTINCT FROM NEW.is_active;
    -- остання команда правила визначає статус «UPDATE n», який бачить клієнт
    UPDATE readers
       SET first_name = NEW.first_name,
           last_name  = NEW.last_name,
           email      = NEW.email,
           phone      = NEW.phone,
           address    = NEW.address,
           is_active  = NEW.is_active
     WHERE reader_id = OLD.reader_id;
);

-- ---------------------------------------------------------------------
-- INSERT: новий читач. Номер квитка генерується автоматично, якщо не вказано.
-- ---------------------------------------------------------------------
CREATE RULE r_reader_cards_insert AS
ON INSERT TO v_reader_cards
DO INSTEAD
    INSERT INTO readers (ticket_number, first_name, last_name, email, phone, address, is_active)
    VALUES (COALESCE(NEW.ticket_number,
                     'LIB-' || (SELECT COALESCE(MAX(SUBSTRING(ticket_number FROM 5)::INT), 0) + 1
                                FROM readers)),
            NEW.first_name, NEW.last_name, NEW.email, NEW.phone, NEW.address,
            COALESCE(NEW.is_active, TRUE));

-- ---------------------------------------------------------------------
-- DELETE: «м'яке» видалення — історія видач має зберігатися, тому
-- читача не видаляємо фізично, а лише блокуємо разом з акаунтом.
-- Особливість правил: клієнт побачить «DELETE 0», бо статус береться з
-- останньої команди правила того ж типу (DELETE), а тут їх немає — лише UPDATE.
-- ---------------------------------------------------------------------
CREATE RULE r_reader_cards_delete AS
ON DELETE TO v_reader_cards
DO INSTEAD (
    UPDATE app_users SET is_active = FALSE WHERE reader_id = OLD.reader_id;
    UPDATE readers   SET is_active = FALSE WHERE reader_id = OLD.reader_id;
);

-- ---------------------------------------------------------------------
-- Перевірка
-- ---------------------------------------------------------------------
-- Стан до змін: читач 1 (має обліковий запис kovalenko)
SELECT reader_id, ticket_number, last_name, first_name, phone, is_active, username,
       books_on_hand, current_debt
FROM v_reader_cards WHERE reader_id = 1;

-- 1) UPDATE через представлення — змінюється таблиця readers
UPDATE v_reader_cards SET phone = '+380501112233', address = 'м. Луцьк, вул. Волі, 1'
WHERE reader_id = 1;

-- 2) INSERT через представлення — квиток згенеровано автоматично
INSERT INTO v_reader_cards (first_name, last_name, email, phone)
VALUES ('Артем', 'Тестовий', 'artem.test@example.com', '+380671234567');

-- 3) DELETE через представлення — читач 2 лише блокується (разом з акаунтом)
DELETE FROM v_reader_cards WHERE reader_id = 2;

SELECT reader_id, ticket_number, last_name, first_name, phone, address, is_active, username
FROM v_reader_cards
WHERE reader_id IN (1, 2) OR email = 'artem.test@example.com'
ORDER BY reader_id;

-- Перевіряємо базові таблиці напряму
SELECT r.reader_id, r.is_active AS reader_active, u.username, u.is_active AS account_active
FROM readers r LEFT JOIN app_users u USING (reader_id)
WHERE r.reader_id = 2;

-- Список правил представлення (_RETURN — це сам SELECT представлення)
SELECT r.rulename AS "Правило",
       CASE r.ev_type WHEN '1' THEN 'SELECT' WHEN '2' THEN 'UPDATE'
                      WHEN '3' THEN 'INSERT' WHEN '4' THEN 'DELETE' END AS "Подія",
       r.is_instead AS "INSTEAD"
FROM pg_rewrite r
JOIN pg_class c ON c.oid = r.ev_class
WHERE c.relname = 'v_reader_cards'
ORDER BY r.ev_type;
