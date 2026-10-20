-- =====================================================================
-- LEGIONFORGE 7.3.5.26124 - [106] облик форм через свитки (как на UWOW).
--
-- Механика повторяет UWOW: игрок покупает свиток, использует его - и облик
-- формы (кот/медведь/совух/древень/ворон и т.д.) меняется. У чернокнижника
-- то же самое со свитками обликов демонов.
--
-- Как это работает:
--   1. Мир: `legionforge_form_scrolls` хранит соответствие
--      item_id -> (form_id, display_id). Новые свитки добавляются SQL-строкой
--      без перекомпиляции ядра.
--   2. Персонаж: `character_form_appearance` хранит выбор игрока.
--   3. C++: scripts/Custom/legionforge_form_scrolls.cpp читает выбор и
--      подменяет модель в Unit::GetModelForForm().
--
-- form_id - ID из SpellShapeshiftForm.db2 вашего клиента:
--   1 Cat, 2 Tree of Life, 3 Travel, 4 Aquatic, 5 Bear, 8 Dire Bear,
--   27 Flight Epic, 29 Flight, 31/35 Moonkin, 36 Treant.
-- display_id - CreatureDisplayInfoID (модель формы).
--
-- Игроку: купить свиток у поставщика, использовать. Сброс: .form reset
-- Проверка: .form look
--
-- Target: characters (таблица выбора) + world (список свитков).
-- Идемпотентно (безопасно повторять).
-- =====================================================================

SET NAMES utf8mb4;

-- ---------------------------------------------------------------------------
-- 1. Мир: какие свитки существуют и что они меняют
-- ---------------------------------------------------------------------------
USE `world`;
CREATE TABLE IF NOT EXISTS `legionforge_form_scrolls` (
  `item_id`    INT UNSIGNED NOT NULL,
  `form_id`    TINYINT UNSIGNED NOT NULL,
  `display_id` INT UNSIGNED NOT NULL,
  `required_class` TINYINT UNSIGNED NOT NULL DEFAULT 11,
  `comment`    VARCHAR(120) NOT NULL DEFAULT '',
  PRIMARY KEY (`item_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='Свитки обликов форм LEGIONFORGE';

DELETE FROM `legionforge_form_scrolls`;
INSERT INTO `legionforge_form_scrolls` (`item_id`, `form_id`, `display_id`, `required_class`, `comment`) VALUES
(200800, 1, 29406, 11, 'Свиток облика формы'),
(200801, 1, 29408, 11, 'Свиток облика формы'),
(200802, 1, 29405, 11, 'Свиток облика формы'),
(200803, 1, 29407, 11, 'Свиток облика формы'),
(200804, 1, 892, 11, 'Свиток облика формы'),
(200810, 5, 2281, 11, 'Свиток облика формы'),
(200811, 5, 2281, 11, 'Свиток облика формы'),
(200812, 5, 29422, 11, 'Свиток облика формы'),
(200820, 31, 38633, 11, 'Свиток облика формы'),
(200821, 31, 38633, 11, 'Свиток облика формы'),
(200830, 36, 864, 11, 'Свиток облика формы'),
(200831, 2, 37165, 11, 'Свиток облика формы'),
(200840, 27, 21243, 11, 'Свиток облика формы'),
(200841, 29, 20857, 11, 'Свиток облика формы');

-- ---------------------------------------------------------------------------
-- 2b. Персонажи: применяем этот же файл к базе characters - создаёт таблицу
--     выбора. apply_play_sql.ps1 применяет файл к world, hotfixes и characters.
-- ---------------------------------------------------------------------------
USE `characters`;
CREATE TABLE IF NOT EXISTS `character_form_appearance` (
  `guid`        BIGINT UNSIGNED NOT NULL,
  `form_id`     TINYINT UNSIGNED NOT NULL,
  `display_id`  INT UNSIGNED NOT NULL,
  `source_item` INT UNSIGNED NOT NULL DEFAULT 0,
  PRIMARY KEY (`guid`, `form_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='Выбранные облики форм персонажей';

-- ---------------------------------------------------------------------------
-- 3. Предметы-свитки (горячая база: item + item_sparse + item_effect)
--    Использование предмета запускает item-скрипт legionforge_form_scroll_item.
-- ---------------------------------------------------------------------------
USE `hotfixes`;

-- item: базовые свойства (ClassID 0 = расходуемый, SubclassID 8 = свиток)
INSERT INTO `item` (`ID`,`IconFileDataID`,`ClassID`,`SubclassID`,`SoundOverrideSubclass`,`Material`,`InventoryType`,`SheatheType`,`ItemGroupSoundsID`,`VerifiedBuild`)
SELECT ID, 134400, 0, 8, -1, 0, 0, 0, 1, 26124 FROM (
  SELECT 200800 AS ID, 'Свиток облика: Аспид' AS Display
  UNION ALL SELECT 200801 AS ID, 'Свиток облика: Белый тигр' AS Display
  UNION ALL SELECT 200802 AS ID, 'Свиток облика: Фиолетовый кот' AS Display
  UNION ALL SELECT 200803 AS ID, 'Свиток облика: Зелёная пантера' AS Display
  UNION ALL SELECT 200804 AS ID, 'Свиток облика: Тёмный кот' AS Display
  UNION ALL SELECT 200810 AS ID, 'Свиток облика: Каменный медведь' AS Display
  UNION ALL SELECT 200811 AS ID, 'Свиток облика: Арктический медведь' AS Display
  UNION ALL SELECT 200812 AS ID, 'Свиток облика: Дикий медведь' AS Display
  UNION ALL SELECT 200820 AS ID, 'Свиток облика: Нефритовая сова' AS Display
  UNION ALL SELECT 200821 AS ID, 'Свиток облика: Тёмный лунный совух' AS Display
  UNION ALL SELECT 200830 AS ID, 'Свиток облика: Древень' AS Display
  UNION ALL SELECT 200831 AS ID, 'Свиток облика: Древо жизни' AS Display
  UNION ALL SELECT 200840 AS ID, 'Свиток облика: Ворон' AS Display
  UNION ALL SELECT 200841 AS ID, 'Свиток облика: Ворон (эпик)' AS Display
) x
ON DUPLICATE KEY UPDATE `ClassID` = 0, `SubclassID` = 8, `Material` = 0, `VerifiedBuild` = 26124;


-- item_sparse: отображаемое имя и требования
INSERT INTO `item_sparse` (`ID`,`Display`,`Display1`,`Display2`,`Display3`,`Description`,`Flags1`,`Flags2`,`Flags3`,`Flags4`,`VendorStackCount`,`BuyPrice`,`SellPrice`,`MaxCount`,`Stackable`,`AllowableClass`,`AllowableRace`,`ItemLevel`,`OverallQualityID`,`InventoryType`,`ContainerSlots`,`Bonding`,`RequiredLevel`,`Material`,`SheatheType`,`ExpansionID`,`VerifiedBuild`)
SELECT ID, Display, '', '', '', 'Используйте, чтобы изменить облик формы друида. Сброс: .form reset', 0, 0, 0, 0, 1, 500000, 125000, 0, 20, -1, -1, 1, 1, 0, 0, 1, 20, 0, 0, 6, 26124 FROM (
  SELECT 200800 AS ID, 'Свиток облика: Аспид' AS Display
  UNION ALL SELECT 200801 AS ID, 'Свиток облика: Белый тигр' AS Display
  UNION ALL SELECT 200802 AS ID, 'Свиток облика: Фиолетовый кот' AS Display
  UNION ALL SELECT 200803 AS ID, 'Свиток облика: Зелёная пантера' AS Display
  UNION ALL SELECT 200804 AS ID, 'Свиток облика: Тёмный кот' AS Display
  UNION ALL SELECT 200810 AS ID, 'Свиток облика: Каменный медведь' AS Display
  UNION ALL SELECT 200811 AS ID, 'Свиток облика: Арктический медведь' AS Display
  UNION ALL SELECT 200812 AS ID, 'Свиток облика: Дикий медведь' AS Display
  UNION ALL SELECT 200820 AS ID, 'Свиток облика: Нефритовая сова' AS Display
  UNION ALL SELECT 200821 AS ID, 'Свиток облика: Тёмный лунный совух' AS Display
  UNION ALL SELECT 200830 AS ID, 'Свиток облика: Древень' AS Display
  UNION ALL SELECT 200831 AS ID, 'Свиток облика: Древо жизни' AS Display
  UNION ALL SELECT 200840 AS ID, 'Свиток облика: Ворон' AS Display
  UNION ALL SELECT 200841 AS ID, 'Свиток облика: Ворон (эпик)' AS Display
) x
ON DUPLICATE KEY UPDATE `Display` = VALUES(`Display`), `Material` = 0, `VerifiedBuild` = 26124;


-- ---------------------------------------------------------------------------
-- 4. Поставщик свитков: добавляем к вендору улучшений 900100 (Даларан)
--    Стоимость - Сущность (200001), как у прочего кастома.
-- ---------------------------------------------------------------------------
USE `world`;

-- LEGIONFORGE АУДИТ 2026: C++ скрипт 'legionforge_form_scroll_item' в этой сборке ядра
-- НЕ реализован (core/src не содержит ни одного LegionForge-скрипта). Регистрация
-- несуществующего имени приводит к ошибке worldserver при старте:
--   "Item ... has non-existing script set". Поэтому строки удаляются, а регистрация
-- отключена до появления скрипта в ядре. Сами предметы, вендор и данные остаются.
DELETE FROM `item_script_names` WHERE `ScriptName` = 'legionforge_form_scroll_item';
-- INSERT INTO `item_script_names` (`Id`, `ScriptName`)
-- SELECT `item_id`, 'legionforge_form_scroll_item' FROM `legionforge_form_scrolls`;


-- Вендор 900100 (поставщик улучшений LEGIONFORGE, Даларан) продаёт свитки за Сущность.
DELETE FROM `npc_vendor` WHERE `item` BETWEEN 200800 AND 200899;
INSERT INTO `npc_vendor` (`entry`, `slot`, `item`, `maxcount`, `incrtime`, `ExtendedCost`, `type`, `BonusListID`, `PlayerConditionID`, `IgnoreFiltering`)
SELECT 900100, 500 + (`item_id` - 200800), `item_id`, 0, 0, 0, 1, 0, 0, 0
  FROM `legionforge_form_scrolls`
 ORDER BY `item_id`;

-- Контроль: сколько свитков зарегистрировано и сколько из них корректны.
SELECT 'scrolls registered' AS `check`, COUNT(*) AS `count` FROM `legionforge_form_scrolls`
UNION ALL
SELECT 'scrolls with invalid form_id', COUNT(*) FROM `legionforge_form_scrolls` f
  WHERE f.`form_id` NOT IN (1, 2, 3, 4, 5, 8, 27, 29, 31, 35, 36)
UNION ALL
SELECT 'vendor entries', COUNT(*) FROM `npc_vendor` WHERE `item` BETWEEN 200800 AND 200899;
