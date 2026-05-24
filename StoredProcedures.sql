
-- 1. Получение списка изделий по их категории
CREATE OR REPLACE FUNCTION get_изделия_по_категории(
    p_номер_категории INT
)
RETURNS SETOF Изделие
LANGUAGE sql STABLE AS $$
    SELECT *
    FROM   Изделие
    WHERE  НомерКатегории = p_номер_категории;
$$;


-- 2. Получение данных изделия по его ID
CREATE OR REPLACE FUNCTION get_изделие_по_id(
    p_код_изделия INT
)
RETURNS SETOF Изделие
LANGUAGE sql STABLE AS $$
    SELECT *
    FROM   Изделие
    WHERE  КодИзделия = p_код_изделия;
$$;


-- 3. Незавершённые и неотменённые заказы заданного клиента
CREATE OR REPLACE FUNCTION get_активные_заказы_клиента(
    p_код_клиента INT
)
RETURNS SETOF Заказ
LANGUAGE sql STABLE AS $$
    WITH последний_статус AS (
        SELECT DISTINCT ON (НомерЗаказа)
            НомерЗаказа,
            КодСтатуса
        FROM  СменаСтатусовЗаказа
        ORDER BY НомерЗаказа, ДатаВремя DESC
    )
    SELECT з.*
    FROM   Заказ з
    LEFT JOIN последний_статус пс ON з.НомерЗаказа = пс.НомерЗаказа
    LEFT JOIN СтатусЗаказа    сс ON пс.КодСтатуса  = сс.КодСтатуса
    WHERE  з.КодКлиента = p_код_клиента
      AND  (сс.Название IS NULL
            OR сс.Название NOT IN ('Завершён', 'Отменён'));
$$;


-- 4. Получение состава заказа по его ID
CREATE OR REPLACE FUNCTION get_состав_заказа(
    p_номер_заказа INT
)
RETURNS TABLE (
    Код              INT,
    НомерЗаказа      INT,
    КодИзделия       INT,
    Количество       INT,
    НазваниеИзделия  VARCHAR(30),
    ТекущаяСтоимость FLOAT
)
LANGUAGE sql STABLE AS $$
    SELECT сз.Код,
           сз.НомерЗаказа,
           сз.КодИзделия,
           сз.Количество,
           и.Название        AS НазваниеИзделия,
           и.ТекущаяСтоимость
    FROM   СоставЗаказа сз
    JOIN   Изделие      и  ON сз.КодИзделия = и.КодИзделия
    WHERE  сз.НомерЗаказа = p_номер_заказа;
$$;


-- 5. Завершённые или отменённые заказы заданного клиента
CREATE OR REPLACE FUNCTION get_завершённые_заказы_клиента(
    p_код_клиента INT
)
RETURNS SETOF Заказ
LANGUAGE sql STABLE AS $$
    WITH последний_статус AS (
        SELECT DISTINCT ON (НомерЗаказа)
            НомерЗаказа,
            КодСтатуса
        FROM  СменаСтатусовЗаказа
        ORDER BY НомерЗаказа, ДатаВремя DESC
    )
    SELECT з.*
    FROM   Заказ з
    JOIN   последний_статус пс ON з.НомерЗаказа = пс.НомерЗаказа
    JOIN   СтатусЗаказа    сс ON пс.КодСтатуса  = сс.КодСтатуса
    WHERE  з.КодКлиента = p_код_клиента
      AND  сс.Название IN ('Завершён', 'Отменён');
$$;


-- 6. История смены статусов заказа по его ID
CREATE OR REPLACE FUNCTION get_история_статусов_заказа(
    p_номер_заказа INT
)
RETURNS TABLE (
    Код               INT,
    НомерЗаказа       INT,
    ДатаВремя         TIMESTAMP,
    КодСтатуса        INT,
    НазваниеСтатуса   VARCHAR(15),
    ОписаниеСтатуса   VARCHAR(50)
)
LANGUAGE sql STABLE AS $$
    SELECT сз.Код,
           сз.НомерЗаказа,
           сз.ДатаВремя,
           сз.КодСтатуса,
           сс.Название  AS НазваниеСтатуса,
           сс.Описание  AS ОписаниеСтатуса
    FROM   СменаСтатусовЗаказа сз
    JOIN   СтатусЗаказа        сс ON сз.КодСтатуса = сс.КодСтатуса
    WHERE  сз.НомерЗаказа = p_номер_заказа
    ORDER BY сз.ДатаВремя;
$$;


-- 7. Добавление нового статуса заказа по его ID
CREATE OR REPLACE PROCEDURE add_статус_заказа(
    p_номер_заказа INT,
    p_код_статуса  INT
)
LANGUAGE plpgsql AS $$
DECLARE
    v_код INT;
BEGIN
    SELECT COALESCE(MAX(Код), 0) + 1
    INTO   v_код
    FROM   СменаСтатусовЗаказа;

    INSERT INTO СменаСтатусовЗаказа(Код, НомерЗаказа, ДатаВремя, КодСтатуса)
    VALUES (v_код, p_номер_заказа, CURRENT_TIMESTAMP, p_код_статуса);
END;
$$;


-- 8. Добавление изделия и количества в состав заказа по его ID
CREATE OR REPLACE PROCEDURE add_изделие_в_заказ(
    p_номер_заказа INT,
    p_код_изделия  INT,
    p_количество   INT
)
LANGUAGE plpgsql AS $$
DECLARE
    v_код INT;
BEGIN
    SELECT COALESCE(MAX(Код), 0) + 1
    INTO   v_код
    FROM   СоставЗаказа;

    INSERT INTO СоставЗаказа(Код, НомерЗаказа, КодИзделия, Количество)
    VALUES (v_код, p_номер_заказа, p_код_изделия, p_количество);
END;
$$;


-- 9. Создание нового заказа с номером столика, без локатора
CREATE OR REPLACE FUNCTION create_заказ_со_столиком(
    p_код_клиента    INT,
    p_код_кассира    INT,
    p_номер_ресторана INT,
    p_стоимость      FLOAT,
    p_номер_столика  INT
)
RETURNS INT
LANGUAGE plpgsql AS $$
DECLARE
    v_номер_заказа INT;
BEGIN
    SELECT COALESCE(MAX(НомерЗаказа), 0) + 1
    INTO   v_номер_заказа
    FROM   Заказ;

    INSERT INTO Заказ(
        НомерЗаказа, КодКлиента, КодКассира,
        НомерРесторана, Стоимость,
        НомерСтолика, НомерЛокатора, ВремяОформления
    )
    VALUES (
        v_номер_заказа, p_код_клиента, p_код_кассира,
        p_номер_ресторана, p_стоимость,
        p_номер_столика, NULL, CURRENT_TIMESTAMP
    );

    RETURN v_номер_заказа;
END;
$$;


-- 10. Создание нового заказа с номером локатора, без столика
CREATE OR REPLACE FUNCTION create_заказ_с_локатором(
    p_код_клиента     INT,
    p_код_кассира     INT,
    p_номер_ресторана INT,
    p_стоимость       FLOAT,
    p_номер_локатора  INT
)
RETURNS INT
LANGUAGE plpgsql AS $$
DECLARE
    v_номер_заказа INT;
BEGIN
    SELECT COALESCE(MAX(НомерЗаказа), 0) + 1
    INTO   v_номер_заказа
    FROM   Заказ;

    INSERT INTO Заказ(
        НомерЗаказа, КодКлиента, КодКассира,
        НомерРесторана, Стоимость,
        НомерСтолика, НомерЛокатора, ВремяОформления
    )
    VALUES (
        v_номер_заказа, p_код_клиента, p_код_кассира,
        p_номер_ресторана, p_стоимость,
        NULL, p_номер_локатора, CURRENT_TIMESTAMP
    );

    RETURN v_номер_заказа;
END;
$$;


-- 11. Создание нового заказа без столика и без локатора
CREATE OR REPLACE FUNCTION create_заказ(
    p_код_клиента     INT,
    p_код_кассира     INT,
    p_номер_ресторана INT,
    p_стоимость       FLOAT
)
RETURNS INT
LANGUAGE plpgsql AS $$
DECLARE
    v_номер_заказа INT;
BEGIN
    SELECT COALESCE(MAX(НомерЗаказа), 0) + 1
    INTO   v_номер_заказа
    FROM   Заказ;

    INSERT INTO Заказ(
        НомерЗаказа, КодКлиента, КодКассира,
        НомерРесторана, Стоимость,
        НомерСтолика, НомерЛокатора, ВремяОформления
    )
    VALUES (
        v_номер_заказа, p_код_клиента, p_код_кассира,
        p_номер_ресторана, p_стоимость,
        NULL, NULL, CURRENT_TIMESTAMP
    );

    RETURN v_номер_заказа;
END;
$$;


-- 12. Незавершённые и неотменённые заказы заданного кассира
CREATE OR REPLACE FUNCTION get_активные_заказы_кассира(
    p_код_кассира INT
)
RETURNS SETOF Заказ
LANGUAGE sql STABLE AS $$
    WITH последний_статус AS (
        SELECT DISTINCT ON (НомерЗаказа)
            НомерЗаказа,
            КодСтатуса
        FROM  СменаСтатусовЗаказа
        ORDER BY НомерЗаказа, ДатаВремя DESC
    )
    SELECT з.*
    FROM   Заказ з
    LEFT JOIN последний_статус пс ON з.НомерЗаказа = пс.НомерЗаказа
    LEFT JOIN СтатусЗаказа    сс ON пс.КодСтатуса  = сс.КодСтатуса
    WHERE  з.КодКассира = p_код_кассира
      AND  (сс.Название IS NULL
            OR сс.Название NOT IN ('Завершён', 'Отменён'));
$$;


-- 13. Завершённые или отменённые заказы заданного кассира
CREATE OR REPLACE FUNCTION get_завершённые_заказы_кассира(
    p_код_кассира INT
)
RETURNS SETOF Заказ
LANGUAGE sql STABLE AS $$
    WITH последний_статус AS (
        SELECT DISTINCT ON (НомерЗаказа)
            НомерЗаказа,
            КодСтатуса
        FROM  СменаСтатусовЗаказа
        ORDER BY НомерЗаказа, ДатаВремя DESC
    )
    SELECT з.*
    FROM   Заказ з
    JOIN   последний_статус пс ON з.НомерЗаказа = пс.НомерЗаказа
    JOIN   СтатусЗаказа    сс ON пс.КодСтатуса  = сс.КодСтатуса
    WHERE  з.КодКассира = p_код_кассира
      AND  сс.Название IN ('Завершён', 'Отменён');
$$;


-- 14. Получение данных кассира по его ID
CREATE OR REPLACE FUNCTION get_кассир_по_id(
    p_код_кассира INT
)
RETURNS SETOF Кассир
LANGUAGE sql STABLE AS $$
    SELECT *
    FROM   Кассир
    WHERE  КодКассира = p_код_кассира;
$$;


-- 15. Получение списка всех кассиров
CREATE OR REPLACE FUNCTION get_все_кассиры()
RETURNS SETOF Кассир
LANGUAGE sql STABLE AS $$
    SELECT * FROM Кассир;
$$;


-- 16. Получение списка всех категорий
CREATE OR REPLACE FUNCTION get_все_категории()
RETURNS SETOF КатегорияИзделия
LANGUAGE sql STABLE AS $$
    SELECT * FROM КатегорияИзделия;
$$;


-- 17. Получение списка всех ресторанов
CREATE OR REPLACE FUNCTION get_все_рестораны()
RETURNS SETOF Ресторан
LANGUAGE sql STABLE AS $$
    SELECT * FROM Ресторан;
$$;


-- 18. Создание нового кассира
CREATE OR REPLACE PROCEDURE create_кассир(
    p_паспорт          CHAR(10),
    p_номер_ресторана  INT,
    p_фамилия          VARCHAR(20),
    p_имя              VARCHAR(15),
    p_номер_телефона   CHAR(11),
    p_инн              CHAR(12)
)
LANGUAGE plpgsql AS $$
DECLARE
    v_код INT;
BEGIN
    SELECT COALESCE(MAX(КодКассира), 0) + 1
    INTO   v_код
    FROM   Кассир;

    INSERT INTO Кассир(
        КодКассира, Паспорт, НомерРесторана,
        Фамилия, Имя, НомерТелефона, ИНН
    )
    VALUES (
        v_код, p_паспорт, p_номер_ресторана,
        p_фамилия, p_имя, p_номер_телефона, p_инн
    );
END;
$$;


-- 19. Изменение данных кассира
CREATE OR REPLACE PROCEDURE update_кассир(
    p_код_кассира      INT,
    p_паспорт          CHAR(10),
    p_номер_ресторана  INT,
    p_фамилия          VARCHAR(20),
    p_имя              VARCHAR(15),
    p_номер_телефона   CHAR(11),
    p_инн              CHAR(12)
)
LANGUAGE plpgsql AS $$
BEGIN
    UPDATE Кассир
    SET    Паспорт         = p_паспорт,
           НомерРесторана  = p_номер_ресторана,
           Фамилия         = p_фамилия,
           Имя             = p_имя,
           НомерТелефона   = p_номер_телефона,
           ИНН             = p_инн
    WHERE  КодКассира = p_код_кассира;
END;
$$;


-- 20. Получение списка всех изделий
CREATE OR REPLACE FUNCTION get_все_изделия()
RETURNS SETOF Изделие
LANGUAGE sql STABLE AS $$
    SELECT * FROM Изделие;
$$;


-- 21. Создание новой категории
CREATE OR REPLACE PROCEDURE create_категория(
    p_название  VARCHAR(15),
    p_описание  VARCHAR(50)
)
LANGUAGE plpgsql AS $$
DECLARE
    v_номер INT;
BEGIN
    SELECT COALESCE(MAX(НомерКатегории), 0) + 1
    INTO   v_номер
    FROM   КатегорияИзделия;

    INSERT INTO КатегорияИзделия(НомерКатегории, Название, Описание)
    VALUES (v_номер, p_название, p_описание);
END;
$$;


-- 22. Изменение данных категории
CREATE OR REPLACE PROCEDURE update_категория(
    p_номер_категории INT,
    p_название        VARCHAR(15),
    p_описание        VARCHAR(50)
)
LANGUAGE plpgsql AS $$
BEGIN
    UPDATE КатегорияИзделия
    SET    Название = p_название,
           Описание = p_описание
    WHERE  НомерКатегории = p_номер_категории;
END;
$$;


-- 23. Удаление категории, если она не указана ни у одного изделия
CREATE OR REPLACE PROCEDURE delete_категория(
    p_номер_категории INT
)
LANGUAGE plpgsql AS $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM Изделие WHERE НомерКатегории = p_номер_категории
    ) THEN
        RAISE EXCEPTION
            'Категория % не может быть удалена: на неё ссылаются изделия',
            p_номер_категории;
    END IF;

    DELETE FROM КатегорияИзделия WHERE НомерКатегории = p_номер_категории;
END;
$$;


-- 24. Получение списка всех ингредиентов
CREATE OR REPLACE FUNCTION get_все_ингредиенты()
RETURNS SETOF Ингредиент
LANGUAGE sql STABLE AS $$
    SELECT * FROM Ингредиент;
$$;


-- 25. Удаление ингредиента, если он не указан ни у одного изделия
CREATE OR REPLACE PROCEDURE delete_ингредиент(
    p_код_ингредиента INT
)
LANGUAGE plpgsql AS $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM СоставИзделия WHERE КодИнгредиента = p_код_ингредиента
    ) THEN
        RAISE EXCEPTION
            'Ингредиент % не может быть удалён: он входит в состав изделий',
            p_код_ингредиента;
    END IF;

    DELETE FROM Ингредиент WHERE КодИнгредиента = p_код_ингредиента;
END;
$$;


-- 26. Создание нового ингредиента
CREATE OR REPLACE PROCEDURE create_ингредиент(
    p_название      VARCHAR(15),
    p_описание      VARCHAR(50),
    p_аллергенность BOOLEAN
)
LANGUAGE plpgsql AS $$
DECLARE
    v_код INT;
BEGIN
    SELECT COALESCE(MAX(КодИнгредиента), 0) + 1
    INTO   v_код
    FROM   Ингредиент;

    INSERT INTO Ингредиент(КодИнгредиента, Название, Описание, Аллергенность)
    VALUES (v_код, p_название, p_описание, p_аллергенность);
END;
$$;


-- 27. Изменение данных ингредиента
CREATE OR REPLACE PROCEDURE update_ингредиент(
    p_код_ингредиента INT,
    p_название        VARCHAR(15),
    p_описание        VARCHAR(50),
    p_аллергенность   BOOLEAN
)
LANGUAGE plpgsql AS $$
BEGIN
    UPDATE Ингредиент
    SET    Название      = p_название,
           Описание      = p_описание,
           Аллергенность = p_аллергенность
    WHERE  КодИнгредиента = p_код_ингредиента;
END;
$$;


-- 28. Получение состава изделия
CREATE OR REPLACE FUNCTION get_состав_изделия(
    p_код_изделия INT
)
RETURNS TABLE (
    Код                   INT,
    КодИнгредиента        INT,
    КодИзделия            INT,
    НазваниеИнгредиента   VARCHAR(15),
    ОписаниеИнгредиента   VARCHAR(50),
    Аллергенность         BOOLEAN
)
LANGUAGE sql STABLE AS $$
    SELECT си.Код,
           си.КодИнгредиента,
           си.КодИзделия,
           и.Название      AS НазваниеИнгредиента,
           и.Описание       AS ОписаниеИнгредиента,
           и.Аллергенность
    FROM   СоставИзделия си
    JOIN   Ингредиент    и  ON си.КодИнгредиента = и.КодИнгредиента
    WHERE  си.КодИзделия = p_код_изделия;
$$;


-- 29. Получение меню изделия (рестораны, в которых оно есть)
CREATE OR REPLACE FUNCTION get_меню_изделия(
    p_код_изделия INT
)
RETURNS TABLE (
    Код             INT,
    НомерРесторана  INT,
    КодИзделия      INT,
    АдресРесторана  VARCHAR(50)
)
LANGUAGE sql STABLE AS $$
    SELECT мр.Код,
           мр.НомерРесторана,
           мр.КодИзделия,
           р.Адрес AS АдресРесторана
    FROM   МенюРесторана мр
    JOIN   Ресторан      р  ON мр.НомерРесторана = р.НомерРесторана
    WHERE  мр.КодИзделия = p_код_изделия;
$$;


-- 30. Создание нового изделия
CREATE OR REPLACE PROCEDURE create_изделие(
    p_номер_категории    INT,
    p_название           VARCHAR(30),
    p_описание           VARCHAR(200),
    p_пищевая_ценность   INT,
    p_текущая_стоимость  FLOAT
)
LANGUAGE plpgsql AS $$
DECLARE
    v_код INT;
BEGIN
    SELECT COALESCE(MAX(КодИзделия), 0) + 1
    INTO   v_код
    FROM   Изделие;

    INSERT INTO Изделие(
        КодИзделия, НомерКатегории, Название,
        Описание, ПищеваяЦенность, ТекущаяСтоимость
    )
    VALUES (
        v_код, p_номер_категории, p_название,
        p_описание, p_пищевая_ценность, p_текущая_стоимость
    );
END;
$$;


-- 31. Изменение данных изделия
CREATE OR REPLACE PROCEDURE update_изделие(
    p_код_изделия        INT,
    p_номер_категории    INT,
    p_название           VARCHAR(30),
    p_описание           VARCHAR(200),
    p_пищевая_ценность   INT,
    p_текущая_стоимость  FLOAT
)
LANGUAGE plpgsql AS $$
BEGIN
    UPDATE Изделие
    SET    НомерКатегории   = p_номер_категории,
           Название         = p_название,
           Описание         = p_описание,
           ПищеваяЦенность  = p_пищевая_ценность,
           ТекущаяСтоимость = p_текущая_стоимость
    WHERE  КодИзделия = p_код_изделия;
END;
$$;


-- 32. Добавление нового ингредиента в состав изделия
CREATE OR REPLACE PROCEDURE add_ингредиент_в_изделие(
    p_код_изделия     INT,
    p_код_ингредиента INT
)
LANGUAGE plpgsql AS $$
DECLARE
    v_код INT;
BEGIN
    SELECT COALESCE(MAX(Код), 0) + 1
    INTO   v_код
    FROM   СоставИзделия;

    INSERT INTO СоставИзделия(Код, КодИнгредиента, КодИзделия)
    VALUES (v_код, p_код_ингредиента, p_код_изделия);
END;
$$;


-- 33. Удаление ингредиента из состава изделия
CREATE OR REPLACE PROCEDURE delete_ингредиент_из_изделия(
    p_код_изделия     INT,
    p_код_ингредиента INT
)
LANGUAGE plpgsql AS $$
BEGIN
    DELETE FROM СоставИзделия
    WHERE  КодИзделия     = p_код_изделия
      AND  КодИнгредиента = p_код_ингредиента;
END;
$$;


-- 34. Удаление изделия из меню ресторана
CREATE OR REPLACE PROCEDURE delete_изделие_из_меню(
    p_номер_ресторана INT,
    p_код_изделия     INT
)
LANGUAGE plpgsql AS $$
BEGIN
    DELETE FROM МенюРесторана
    WHERE  НомерРесторана = p_номер_ресторана
      AND  КодИзделия     = p_код_изделия;
END;
$$;


-- 35. Добавление изделия в меню ресторана
CREATE OR REPLACE PROCEDURE add_изделие_в_меню(
    p_номер_ресторана INT,
    p_код_изделия     INT
)
LANGUAGE plpgsql AS $$
DECLARE
    v_код INT;
BEGIN
    SELECT COALESCE(MAX(Код), 0) + 1
    INTO   v_код
    FROM   МенюРесторана;

    INSERT INTO МенюРесторана(Код, НомерРесторана, КодИзделия)
    VALUES (v_код, p_номер_ресторана, p_код_изделия);
END;
$$;


-- 36. Добавление новой цены изделия + обновление текущей цены
CREATE OR REPLACE PROCEDURE add_цена_изделия(
    p_код_изделия INT,
    p_цена        FLOAT
)
LANGUAGE plpgsql AS $$
DECLARE
    v_код INT;
BEGIN
    -- Фиксируем смену цены в истории
    SELECT COALESCE(MAX(Код), 0) + 1
    INTO   v_код
    FROM   СменаЦенНаИзделие;

    INSERT INTO СменаЦенНаИзделие(Код, КодИзделия, ДатаВремя, Цена)
    VALUES (v_код, p_код_изделия, CURRENT_TIMESTAMP, p_цена);

    -- Обновляем текущую стоимость в карточке изделия
    UPDATE Изделие
    SET    ТекущаяСтоимость = p_цена
    WHERE  КодИзделия = p_код_изделия;
END;
$$;
