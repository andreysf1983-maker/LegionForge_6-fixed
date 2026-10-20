-- =====================================================================
-- LEGIONFORGE 7.3.5.26124 - [107] свитки обликов демонов + облики друида
--                                 по умолчанию (модели Legion).
--
-- ЧАСТЬ 1. Свитки демонов чернокнижника (механика UWOW).
--   Покупаешь свиток -> используешь -> облик демона меняется навсегда.
--   Каждому демону своя красивая модель из контента Legion/Анторуса.
--   Все display_id ПРОВЕРЕНЫ по CreatureDisplayInfo.db2 этого клиента,
--   а pet_entry - по константам ядра (TemporarySummon.h).
--
--   scale - размер модели. Модели рейдовых демонов огромные, поэтому для
--   Ф'арга стоит 0.45: получается чуть крупнее обычного Охотника Скверны,
--   как и просили. Хотите больше/меньше - поменяйте одно число здесь,
--   перезапуск ядра не нужен (значение читается при использовании свитка).
--
-- ЧАСТЬ 2. Облики форм друида по умолчанию.
--   Раньше у друида были старые модели (лось, пантера, рыба). Теперь при
--   создании персонажа сразу используются модели Legion. Это не свиток:
--   таблица `legionforge_form_defaults` задаёт облик для ВСЕХ персонажей,
--   а свиток из SQL 106 перекрывает его индивидуально.
--
-- Приоритет моделей: свиток игрока -> default этой расы -> default для всех
--   -> облик артефакта -> стандартная модель ядра.
--
-- Target: world + characters + hotfixes. Идемпотентно.
-- =====================================================================

SET NAMES utf8mb4;

-- ---------------------------------------------------------------------------
-- 1. Мир: каталог свитков демонов
-- ---------------------------------------------------------------------------
USE `world`;

CREATE TABLE IF NOT EXISTS `legionforge_demon_scrolls` (
  `item_id`    INT UNSIGNED NOT NULL,
  `pet_entry`  INT UNSIGNED NOT NULL,
  `display_id` INT UNSIGNED NOT NULL,
  `scale`      FLOAT NOT NULL DEFAULT 0,
  `comment`    VARCHAR(160) NOT NULL DEFAULT '',
  PRIMARY KEY (`item_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='Свитки обликов демонов LEGIONFORGE';

DELETE FROM `legionforge_demon_scrolls`;
INSERT INTO `legionforge_demon_scrolls` (`item_id`, `pet_entry`, `display_id`, `scale`, `comment`) VALUES
(200700, 417, 77004, 0.45, 'Охотник Скверны -> Ф''арг (Анторус), чуть крупнее обычного'),
(200701, 417, 76990, 0.45, 'Охотник Скверны -> Шатуг (Анторус)'),
(200710, 17252, 64051, 1.00, 'Страж Скверны -> Повелитель Скверны'),
(200711, 17252, 71050, 1.00, 'Страж Скверны -> Повелитель Скверны Каз'),
(200720, 1863, 74896, 1.00, 'Суккуб -> Шиварра'),
(200721, 1863, 75907, 1.00, 'Суккуб -> Шиварра (альт.)'),
(200730, 1860, 71758, 0.90, 'Пустотник -> Владыка Пустоты'),
(200740, 416, 72942, 0.55, 'Бес -> Мать бесов Лаглат, чуть крупнее беса'),
(200750, 78217, 76008, 0.85, 'Инфернал -> Инфернал Бездны'),
(200751, 78217, 62261, 0.85, 'Инфернал -> Пламенный инфернал'),
(200760, 78158, 20865, 0.95, 'Думгард -> Анторусский думгард');

-- ---------------------------------------------------------------------------
-- 2. Мир: облики форм по умолчанию (модели Legion вместо старых)
--    race_id = 0 означает "для всех рас".
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `legionforge_form_defaults` (
  `form_id`    TINYINT UNSIGNED NOT NULL,
  `race_id`    TINYINT UNSIGNED NOT NULL DEFAULT 0,
  `display_id` INT UNSIGNED NOT NULL,
  `comment`    VARCHAR(160) NOT NULL DEFAULT '',
  PRIMARY KEY (`form_id`, `race_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='Облики форм по умолчанию LEGIONFORGE';

DELETE FROM `legionforge_form_defaults`;
INSERT INTO `legionforge_form_defaults` (`form_id`, `race_id`, `display_id`, `comment`) VALUES
(1, 0, 66775, 'Кошка: облик артефакта Legion (вместо старой пантеры)'),
(5, 0, 66682, 'Медведь: облик артефакта Legion'),
(3, 0, 77204, 'Походная форма: Олень-разрушитель (вместо старого лося)'),
(4, 0, 78989, 'Водная форма: Призрачная акула (вместо старой рыбы)');

-- LEGIONFORGE АУДИТ 2026: C++ скрипт 'legionforge_demon_scroll_item' в этой сборке ядра
-- НЕ реализован (core/src не содержит ни одного LegionForge-скрипта). Регистрация
-- несуществующего имени приводит к ошибке worldserver при старте:
--   "Item ... has non-existing script set". Поэтому строки удаляются, а регистрация
-- отключена до появления скрипта в ядре. Сами предметы, вендор и данные остаются.
DELETE FROM `item_script_names` WHERE `ScriptName` = 'legionforge_demon_scroll_item';
-- INSERT INTO `item_script_names` (`Id`, `ScriptName`)
-- SELECT `item_id`, 'legionforge_demon_scroll_item' FROM `legionforge_demon_scrolls`;


-- Вендор 900100 продаёт свитки демонов.
DELETE FROM `npc_vendor` WHERE `item` BETWEEN 200700 AND 200799;
INSERT INTO `npc_vendor` (`entry`, `slot`, `item`, `maxcount`, `incrtime`, `ExtendedCost`, `type`, `BonusListID`, `PlayerConditionID`, `IgnoreFiltering`)
SELECT 900100, 600 + (`item_id` - 200700), `item_id`, 0, 0, 0, 1, 0, 0, 0
  FROM `legionforge_demon_scrolls`
 ORDER BY `item_id`;

-- ---------------------------------------------------------------------------
-- 3. Персонажи: выбранные облики демонов
-- ---------------------------------------------------------------------------
USE `characters`;

CREATE TABLE IF NOT EXISTS `character_demon_appearance` (
  `guid`        BIGINT UNSIGNED NOT NULL,
  `pet_entry`   INT UNSIGNED NOT NULL,
  `display_id`  INT UNSIGNED NOT NULL,
  `scale`       FLOAT NOT NULL DEFAULT 0,
  `source_item` INT UNSIGNED NOT NULL DEFAULT 0,
  PRIMARY KEY (`guid`, `pet_entry`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='Выбранные облики демонов персонажей';

-- ---------------------------------------------------------------------------
-- 4. Предметы-свитки демонов
-- ---------------------------------------------------------------------------
USE `hotfixes`;

INSERT INTO `item` (`ID`,`IconFileDataID`,`ClassID`,`SubclassID`,`SoundOverrideSubclass`,`Material`,`InventoryType`,`SheatheType`,`ItemGroupSoundsID`,`VerifiedBuild`)
SELECT ID, 134336, 0, 8, -1, 0, 0, 0, 1, 26124 FROM (
  SELECT 200700 AS ID, 'Свиток демона: Ф''арг' AS Display
  UNION ALL SELECT 200701 AS ID, 'Свиток демона: Шатуг' AS Display
  UNION ALL SELECT 200710 AS ID, 'Свиток демона: Повелитель Скверны' AS Display
  UNION ALL SELECT 200711 AS ID, 'Свиток демона: Повелитель Каз' AS Display
  UNION ALL SELECT 200720 AS ID, 'Свиток демона: Шиварра' AS Display
  UNION ALL SELECT 200721 AS ID, 'Свиток демона: Шиварра-разрушительница' AS Display
  UNION ALL SELECT 200730 AS ID, 'Свиток демона: Владыка Пустоты' AS Display
  UNION ALL SELECT 200740 AS ID, 'Свиток демона: Мать бесов' AS Display
  UNION ALL SELECT 200750 AS ID, 'Свиток демона: Инфернал Бездны' AS Display
  UNION ALL SELECT 200751 AS ID, 'Свиток демона: Пламенный инфернал' AS Display
  UNION ALL SELECT 200760 AS ID, 'Свиток демона: Анторусский думгард' AS Display
) x
ON DUPLICATE KEY UPDATE `ClassID` = 0, `SubclassID` = 8, `Material` = 0, `VerifiedBuild` = 26124;

INSERT INTO `item_sparse` (`ID`,`Display`,`Display1`,`Display2`,`Display3`,`Description`,`Flags1`,`Flags2`,`Flags3`,`Flags4`,`VendorStackCount`,`BuyPrice`,`SellPrice`,`MaxCount`,`Stackable`,`AllowableClass`,`AllowableRace`,`ItemLevel`,`OverallQualityID`,`InventoryType`,`ContainerSlots`,`Bonding`,`RequiredLevel`,`Material`,`SheatheType`,`ExpansionID`,`VerifiedBuild`)
SELECT ID, Display, '', '', '', 'Используйте, чтобы изменить облик демона. Сброс: .demon reset', 0, 0, 0, 0, 1, 750000, 187500, 0, 20, 256, -1, 1, 1, 0, 0, 1, 20, 0, 0, 6, 26124 FROM (
  SELECT 200700 AS ID, 'Свиток демона: Ф''арг' AS Display
  UNION ALL SELECT 200701 AS ID, 'Свиток демона: Шатуг' AS Display
  UNION ALL SELECT 200710 AS ID, 'Свиток демона: Повелитель Скверны' AS Display
  UNION ALL SELECT 200711 AS ID, 'Свиток демона: Повелитель Каз' AS Display
  UNION ALL SELECT 200720 AS ID, 'Свиток демона: Шиварра' AS Display
  UNION ALL SELECT 200721 AS ID, 'Свиток демона: Шиварра-разрушительница' AS Display
  UNION ALL SELECT 200730 AS ID, 'Свиток демона: Владыка Пустоты' AS Display
  UNION ALL SELECT 200740 AS ID, 'Свиток демона: Мать бесов' AS Display
  UNION ALL SELECT 200750 AS ID, 'Свиток демона: Инфернал Бездны' AS Display
  UNION ALL SELECT 200751 AS ID, 'Свиток демона: Пламенный инфернал' AS Display
  UNION ALL SELECT 200760 AS ID, 'Свиток демона: Анторусский думгард' AS Display
) x
ON DUPLICATE KEY UPDATE `Display` = VALUES(`Display`), `Material` = 0, `VerifiedBuild` = 26124;

-- ---------------------------------------------------------------------------
-- 5. Контроль: всё должно быть 0, кроме первых двух строк
-- ---------------------------------------------------------------------------
USE `world`;
SELECT 'demon scrolls registered' AS `check`, COUNT(*) AS `count` FROM `legionforge_demon_scrolls`
UNION ALL
SELECT 'default form models', COUNT(*) FROM `legionforge_form_defaults`
UNION ALL
SELECT 'demon scrolls without script', COUNT(*) FROM `legionforge_demon_scrolls` s
  WHERE NOT EXISTS (SELECT 1 FROM `item_script_names` n WHERE n.`Id` = s.`item_id`)
UNION ALL
SELECT 'demon scrolls with unknown pet entry', COUNT(*) FROM `legionforge_demon_scrolls` s
  WHERE s.`pet_entry` NOT IN (416, 417, 1860, 1863, 17252, 11859, 78158, 89, 78217, 108452)
UNION ALL
SELECT 'vendor entries for demon scrolls', COUNT(*) FROM `npc_vendor` WHERE `item` BETWEEN 200700 AND 200799;
