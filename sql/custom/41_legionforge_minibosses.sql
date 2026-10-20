-- ==========================================================================
--   LEGIONFORGE 7.3.5 - 100 мировых мини-боссов
--   Файл: sql/41_legionforge_minibosses.sql
--   Идентификаторы: creature_template 900000-900099, creature.guid 9100000-9100099
-- ==========================================================================
-- Файл сгенерирован автоматически: tools/legion_db2/generate_legionforge_content.py
-- Билд клиента: 26124. Изменяйте данные в генераторе, а не в этом файле.
-- Запросы идемпотентны, повторное применение безопасно.
-- ==========================================================================

SET NAMES utf8mb4;
SET FOREIGN_KEY_CHECKS = 0;


-- --------------------------------------------------------------------------
-- 1. Очистка зарезервированного диапазона
-- --------------------------------------------------------------------------

USE `world`;
DELETE FROM `creature` WHERE `guid` BETWEEN 9100000 AND 9100099;
DELETE FROM `creature_template_addon` WHERE `entry` BETWEEN 900000 AND 900099;
DELETE FROM `creature_loot_template` WHERE `entry` BETWEEN 900000 AND 900099;
DELETE FROM `creature_template` WHERE `entry` BETWEEN 900000 AND 900099;
DELETE FROM `creature_template_wdb` WHERE `Entry` BETWEEN 900000 AND 900099;

-- --------------------------------------------------------------------------
-- 2. Описание мини-боссов
-- --------------------------------------------------------------------------

DROP TEMPORARY TABLE IF EXISTS `tmp_legionforge_bosses`;
CREATE TEMPORARY TABLE `tmp_legionforge_bosses` (
  `rn` INT NOT NULL,
  `name` VARCHAR(200) NOT NULL,
  `subname` VARCHAR(200) NOT NULL,
  `rank` TINYINT NOT NULL,
  `hp` FLOAT NOT NULL,
  `dmg` FLOAT NOT NULL,
  `gold` INT NOT NULL,
  PRIMARY KEY (`rn`)
) ENGINE=Memory DEFAULT CHARSET=utf8mb4;

INSERT INTO `tmp_legionforge_bosses` (`rn`,`name`,`subname`,`rank`,`hp`,`dmg`,`gold`) VALUES
(1,'Пепельный Пожиратель','Мини-босс LEGIONFORGE',3,35.0,2.50,2500),
(2,'Хранитель Гнилой Короны','Мини-босс LEGIONFORGE',2,39.5,2.95,2850),
(3,'Матерь Паучьей Тьмы','Мини-босс LEGIONFORGE',2,44.0,3.40,3200),
(4,'Глашатай Бездны','Мини-босс LEGIONFORGE',2,48.5,3.85,3550),
(5,'Костяной Жнец','Мини-босс LEGIONFORGE',2,53.0,4.30,3900),
(6,'Владыка Пылающих Углей','Мини-босс LEGIONFORGE',3,57.5,4.75,4250),
(7,'Страж Забытых Врат','Мини-босс LEGIONFORGE',2,62.0,5.20,4600),
(8,'Колдун Багрового Тумана','Мини-босс LEGIONFORGE',2,66.5,5.65,4950),
(9,'Пожиратель Душ','Мини-босс LEGIONFORGE',2,71.0,2.50,5300),
(10,'Надзиратель Пепла','Мини-босс LEGIONFORGE',2,75.5,2.95,5650),
(11,'Осквернённый Друид','Мини-босс LEGIONFORGE',3,80.0,3.40,6000),
(12,'Хозяин Болотного Тумана','Мини-босс LEGIONFORGE',2,84.5,3.85,6350),
(13,'Шепчущий Ужас','Мини-босс LEGIONFORGE',2,35.0,4.30,6700),
(14,'Мясник Тёмного Обелиска','Мини-босс LEGIONFORGE',2,39.5,4.75,7050),
(15,'Повелитель Костяных Волн','Мини-босс LEGIONFORGE',2,44.0,5.20,7400),
(16,'Чумной Кузнец','Мини-босс LEGIONFORGE',3,48.5,5.65,7750),
(17,'Тень Ночной Владычицы','Мини-босс LEGIONFORGE',2,53.0,2.50,8100),
(18,'Разрушитель Рассвета','Мини-босс LEGIONFORGE',2,57.5,2.95,8450),
(19,'Владыка Ледяных Пустошей','Мини-босс LEGIONFORGE',2,62.0,3.40,8800),
(20,'Смотритель Пламени','Мини-босс LEGIONFORGE',2,66.5,3.85,9150),
(21,'Жрец Безмолвия','Мини-босс LEGIONFORGE',3,71.0,4.30,2500),
(22,'Ворон Пепельного Неба','Мини-босс LEGIONFORGE',2,75.5,4.75,2850),
(23,'Громовержец Скал','Мини-босс LEGIONFORGE',2,80.0,5.20,3200),
(24,'Мастер Забытого Ремесла','Мини-босс LEGIONFORGE',2,84.5,5.65,3550),
(25,'Сектант Алого Рассвета','Мини-босс LEGIONFORGE',2,35.0,2.50,3900),
(26,'Кровавый Страж','Мини-босс LEGIONFORGE',3,39.5,2.95,4250),
(27,'Гниющий Полководец','Мини-босс LEGIONFORGE',2,44.0,3.40,4600),
(28,'Древень Чёрного Корня','Мини-босс LEGIONFORGE',2,48.5,3.85,4950),
(29,'Призрак Утраченной Клятвы','Мини-босс LEGIONFORGE',2,53.0,4.30,5300),
(30,'Ловчий Бездны','Мини-босс LEGIONFORGE',2,57.5,4.75,5650),
(31,'Хозяин Стального Капкана','Мини-босс LEGIONFORGE',3,62.0,5.20,6000),
(32,'Певчий Тёмной Зари','Мини-босс LEGIONFORGE',2,66.5,5.65,6350),
(33,'Сторож Глубин','Мини-босс LEGIONFORGE',2,71.0,2.50,6700),
(34,'Палач Пепельного Легиона','Мини-босс LEGIONFORGE',2,75.5,2.95,7050),
(35,'Хранительница Лунного Колодца','Мини-босс LEGIONFORGE',2,80.0,3.40,7400),
(36,'Разоритель Надежды','Мини-босс LEGIONFORGE',3,84.5,3.85,7750),
(37,'Тотемист Пепла','Мини-босс LEGIONFORGE',2,35.0,4.30,8100),
(38,'Некромант Чёрного Холма','Мини-босс LEGIONFORGE',2,39.5,4.75,8450),
(39,'Страж Тихого Пролива','Мини-босс LEGIONFORGE',2,44.0,5.20,8800),
(40,'Властелин Бурь','Мини-босс LEGIONFORGE',2,48.5,5.65,9150),
(41,'Искатель Забытых Истин','Мини-босс LEGIONFORGE',3,53.0,2.50,2500),
(42,'Гвардеец Тёмного Владыки','Мини-босс LEGIONFORGE',2,57.5,2.95,2850),
(43,'Плакальщица Ночи','Мини-босс LEGIONFORGE',2,62.0,3.40,3200),
(44,'Клинок Рассвета','Мини-босс LEGIONFORGE',2,66.5,3.85,3550),
(45,'Мастер Ядовитых Клинков','Мини-босс LEGIONFORGE',2,71.0,4.30,3900),
(46,'Носитель Проклятия','Мини-босс LEGIONFORGE',3,75.5,4.75,4250),
(47,'Огненный Левиафан','Мини-босс LEGIONFORGE',2,80.0,5.20,4600),
(48,'Ледяной Крушитель','Мини-босс LEGIONFORGE',2,84.5,5.65,4950),
(49,'Повелитель Болотной Топи','Мини-босс LEGIONFORGE',2,35.0,2.50,5300),
(50,'Ткач Теней','Мини-босс LEGIONFORGE',2,39.5,2.95,5650),
(51,'Служитель Пепла','Мини-босс LEGIONFORGE',3,44.0,3.40,6000),
(52,'Костолом Северных Башен','Мини-босс LEGIONFORGE',2,48.5,3.85,6350),
(53,'Владыка Грозовой Гряды','Мини-босс LEGIONFORGE',2,53.0,4.30,6700),
(54,'Жнец Тёмного Железа','Мини-босс LEGIONFORGE',2,57.5,4.75,7050),
(55,'Хозяин Скалистого Пика','Мини-босс LEGIONFORGE',2,62.0,5.20,7400),
(56,'Хранитель Забытого Света','Мини-босс LEGIONFORGE',3,66.5,5.65,7750),
(57,'Мститель Глубин','Мини-босс LEGIONFORGE',2,71.0,2.50,8100),
(58,'Повелитель Пылающих Песков','Мини-босс LEGIONFORGE',2,75.5,2.95,8450),
(59,'Тень Над Пустошью','Мини-босс LEGIONFORGE',2,80.0,3.40,8800),
(60,'Паладин Забытого Света','Мини-босс LEGIONFORGE',2,84.5,3.85,9150),
(61,'Госпожа Чёрного Шёлка','Мини-босс LEGIONFORGE',3,35.0,4.30,2500),
(62,'Тихий Убийца','Мини-босс LEGIONFORGE',2,39.5,4.75,2850),
(63,'Разрушитель Каменных Врат','Мини-босс LEGIONFORGE',2,44.0,5.20,3200),
(64,'Страж Утраченного Храма','Мини-босс LEGIONFORGE',2,48.5,5.65,3550),
(65,'Мастер Стального Круга','Мини-босс LEGIONFORGE',2,53.0,2.50,3900),
(66,'Пожиратель Пламени','Мини-босс LEGIONFORGE',3,57.5,2.95,4250),
(67,'Костяной Жрец','Мини-босс LEGIONFORGE',2,62.0,3.40,4600),
(68,'Глашатай Тёмного Легиона','Мини-босс LEGIONFORGE',2,66.5,3.85,4950),
(69,'Владыка Лунного Клинка','Мини-босс LEGIONFORGE',2,71.0,4.30,5300),
(70,'Тотемный Страж','Мини-босс LEGIONFORGE',2,75.5,4.75,5650),
(71,'Хозяин Чёрного Котла','Мини-босс LEGIONFORGE',3,80.0,5.20,6000),
(72,'Смотритель Тёмных Залов','Мини-босс LEGIONFORGE',2,84.5,5.65,6350),
(73,'Разоритель Древних Стен','Мини-босс LEGIONFORGE',2,35.0,2.50,6700),
(74,'Чумной Владыка','Мини-босс LEGIONFORGE',2,39.5,2.95,7050),
(75,'Повелитель Каменных Духов','Мини-босс LEGIONFORGE',2,44.0,3.40,7400),
(76,'Тень Над Башней','Мини-босс LEGIONFORGE',3,48.5,3.85,7750),
(77,'Хранитель Кристальных Скал','Мини-босс LEGIONFORGE',2,53.0,4.30,8100),
(78,'Певец Тёмных Глубин','Мини-босс LEGIONFORGE',2,57.5,4.75,8450),
(79,'Грозовой Жрец','Мини-босс LEGIONFORGE',2,62.0,5.20,8800),
(80,'Пепельный Жнец','Мини-босс LEGIONFORGE',2,66.5,5.65,9150),
(81,'Мясник Тёмного Оброка','Мини-босс LEGIONFORGE',3,71.0,2.50,2500),
(82,'Владыка Огненного Круга','Мини-босс LEGIONFORGE',2,75.5,2.95,2850),
(83,'Хозяин Ледяной Цитадели','Мини-босс LEGIONFORGE',2,80.0,3.40,3200),
(84,'Колдун Чёрного Пламени','Мини-босс LEGIONFORGE',2,84.5,3.85,3550),
(85,'Страж Ночных Пустошей','Мини-босс LEGIONFORGE',2,35.0,4.30,3900),
(86,'Ткач Пепельной Судьбы','Мини-босс LEGIONFORGE',3,39.5,4.75,4250),
(87,'Повелитель Костяного Трона','Мини-босс LEGIONFORGE',2,44.0,5.20,4600),
(88,'Разрушитель Звёздного Печатя','Мини-босс LEGIONFORGE',2,48.5,5.65,4950),
(89,'Хранитель Грёзного Ключа','Мини-босс LEGIONFORGE',2,53.0,2.50,5300),
(90,'Тень Забытого Владыки','Мини-босс LEGIONFORGE',2,57.5,2.95,5650),
(91,'Мастер Проклятых Клинков','Мини-босс LEGIONFORGE',3,62.0,3.40,6000),
(92,'Глашатай Багрового Рассвета','Мини-босс LEGIONFORGE',2,66.5,3.85,6350),
(93,'Владыка Тихого Холма','Мини-босс LEGIONFORGE',2,71.0,4.30,6700),
(94,'Костяной Страж','Мини-босс LEGIONFORGE',2,75.5,4.75,7050),
(95,'Хозяин Багрового Знамени','Мини-босс LEGIONFORGE',2,80.0,5.20,7400),
(96,'Смотритель Тёмного Пламени','Мини-босс LEGIONFORGE',3,84.5,5.65,7750),
(97,'Последний Страж Легиона','Мини-босс LEGIONFORGE',2,35.0,2.50,8100),
(98,'Вечный Пепельный Хранитель','Мини-босс LEGIONFORGE',2,39.5,2.95,8450),
(99,'Повелитель Забытой Бездны','Мини-босс LEGIONFORGE',2,44.0,3.40,8800),
(100,'Матерь Тёмного Гнезда','Мини-босс LEGIONFORGE',2,48.5,3.85,9150);

-- --------------------------------------------------------------------------
-- 3. Шаблоны существ
-- --------------------------------------------------------------------------

-- LEGIONFORGE FIX 2026: в LegionCore 7.3.5 (build 26124) таблица `creature_template`
-- НЕ содержит колонок name/subname/rank/type/modelid*/HealthModifier - всё это
-- живёт в `creature_template_wdb` (ObjectMgr::LoadWDBCreatureTemplates).
-- Ниже данные разложены по двум таблицам так, как их читает ядро.
INSERT INTO `creature_template`
  (`entry`,`minlevel`,`maxlevel`,`exp`,`faction`,`npcflag`,`speed_walk`,`speed_run`,`speed_fly`,`scale`,
   `dmgschool`,`dmg_multiplier`,`baseattacktime`,`rangeattacktime`,`unit_class`,`lootid`,`mingold`,`maxgold`,
   `AIName`,`MovementType`,`InhabitType`,`RegenHealth`,`mechanic_immune_mask`,`flags_extra`,`ScriptName`)
SELECT 900000 + `rn` - 1, 110, 110, 6, 14, 0, 1, 1.14286, 1, 1.35,
       0, `dmg`, 2000, 2000, 1, 900000 + `rn` - 1, `gold`, `gold` * 2,
       '', 1, 3, 1, 0, 0, ''
FROM `tmp_legionforge_bosses`;

INSERT INTO `creature_template_wdb`
  (`Entry`,`Name1`,`Name2`,`Name3`,`Name4`,`NameAlt1`,`NameAlt2`,`NameAlt3`,`NameAlt4`,`Title`,`TitleAlt`,
   `CursorName`,`Type`,`TypeFlags`,`TypeFlags2`,`RequiredExpansion`,`Family`,`Classification`,`MovementInfoID`,
   `HpMulti`,`PowerMulti`,`Leader`,`KillCredit1`,`KillCredit2`,`VignetteID`,
   `DisplayId1`,`DisplayId2`,`DisplayId3`,`DisplayId4`,`FlagQuest`,`VerifiedBuild`)
SELECT 900000 + `rn` - 1, `name`, `name`, `name`, `name`, '', '', '', '', `subname`, '',
       '', 7, 0, 0, 6, 0, `rank`, 0,
       `hp`, 1, 0, 0, 0, 0,
       0, 0, 0, 0, 0, 26124
FROM `tmp_legionforge_bosses`;

-- Подстановка моделей и визуальных параметров существующих существ (DisplayId живёт в creature_template_wdb).
UPDATE `creature_template_wdb` w
JOIN (
  SELECT ROW_NUMBER() OVER (ORDER BY `Entry`) AS `rn`, `DisplayId1`, `DisplayId2`, `DisplayId3`, `DisplayId4`, `Family`, `TypeFlags`
  FROM `creature_template_wdb`
  WHERE `Entry` < 900000 AND `DisplayId1` > 0
) src ON src.`rn` = w.`Entry` - 899999
SET w.`DisplayId1` = src.`DisplayId1`, w.`DisplayId2` = src.`DisplayId2`, w.`DisplayId3` = src.`DisplayId3`,
    w.`DisplayId4` = src.`DisplayId4`, w.`Family` = src.`Family`, w.`TypeFlags` = src.`TypeFlags`
WHERE w.`Entry` BETWEEN 900000 AND 900099;

-- Страховка: ни одна запись не должна остаться без модели (иначе "does not have any existing display id").
UPDATE `creature_template_wdb`
   SET `DisplayId1` = 3167
 WHERE `Entry` BETWEEN 900000 AND 900099 AND (`DisplayId1` IS NULL OR `DisplayId1` = 0);

-- --------------------------------------------------------------------------
-- 4. Дополнения шаблонов
-- --------------------------------------------------------------------------

INSERT INTO `creature_template_addon` (`entry`,`path_id`,`mount`,`bytes1`,`bytes2`,`emote`,`auras`)
SELECT `entry`, 0, 0, 0, 1, 0, ''
FROM `creature_template` WHERE `entry` BETWEEN 900000 AND 900099;

-- --------------------------------------------------------------------------
-- 5. Расстановка по миру
-- --------------------------------------------------------------------------

-- Координаты берутся из таблицы game_tele: это проверенные точки с корректной высотой Z.
INSERT INTO `creature` (`guid`,`id`,`map`,`zoneId`,`areaId`,`spawnMask`,`phaseMask`,`PhaseId`,`modelid`,`equipment_id`,`position_x`,`position_y`,`position_z`,`orientation`,`spawntimesecs`,`spawndist`,`currentwaypoint`,`curhealth`,`curmana`,`MovementType`,`ScriptName`)
SELECT 9100000 + `rn` - 1, 900000 + `rn` - 1, `map`, 0, 0, 1, 1, 0, 0, 0,
       `position_x`, `position_y`, `position_z`, `orientation`, 7200, 20, 0, 1, 0, 1, ''
FROM (
  SELECT ROW_NUMBER() OVER (ORDER BY `id`) AS `rn`, `map`, `position_x`, `position_y`, `position_z`, `orientation`
  FROM `game_tele`
  WHERE `map` IN (0, 1, 530, 571, 870, 1220)
    AND `name` NOT LIKE '%City%'
    AND `name` NOT LIKE '%Stormwind%'
    AND `name` NOT LIKE '%Orgrimmar%'
) tele
WHERE `rn` <= 100;

DROP TEMPORARY TABLE IF EXISTS `tmp_legionforge_bosses`;

SET FOREIGN_KEY_CHECKS = 1;
