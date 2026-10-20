-- ==========================================================================
--   LEGIONFORGE 7.3.5 - стартовая панель умений союзных рас (27-30)
--   Файл: sql/49_legion_allied_races_hotbar.sql   (идемпотентен)
--
--   В ADB_735.10 для рас 27-30 нет строк playercreateinfo_action: новый
--   персонаж появляется с пустой панелью умений. Заполняем её кнопками
--   "родительской" расы того же класса:
--     27 Ночнорождённые    <- 10 Эл'рейские (Blood Elf)
--     28 Таурены Крутогорья <- 6  Таурены
--     29 Эл'рейские Void    <- 10 Эл'рейские (Blood Elf)
--     30 Озарённые дренеи   <- 11 Дренеи
--
--   Копируются только классы, доступные новой расе (проверка по playercreateinfo).
--   РАСОВЫЕ УМЕНИЯ РОДИТЕЛЯ ИСКЛЮЧАЮТСЯ: их список берётся из
--   playercreateinfo_spell по race родителя (LegionCore 7.3.5), поэтому
--   на панель не попадает чужая расовая кнопка (например Arcane Torrent
--   у Nightborne). Никакие ID не выдуманы - только данные из той же БД.
-- ==========================================================================

SET NAMES utf8mb4;

DELETE FROM `playercreateinfo_action` WHERE `race` IN (27, 28, 29, 30);

INSERT INTO `playercreateinfo_action` (`race`, `class`, `button`, `action`, `type`)
SELECT m.new_race, a.class, a.button, a.action, a.type
  FROM `playercreateinfo_action` a
  JOIN (SELECT 27 AS new_race, 10 AS parent_race UNION ALL
        SELECT 28, 6  UNION ALL
        SELECT 29, 10 UNION ALL
        SELECT 30, 11) m ON m.parent_race = a.race
  -- только те классы, которые у новой расы действительно можно создать
  JOIN `playercreateinfo` pci ON pci.race = m.new_race AND pci.class = a.class
 WHERE NOT EXISTS (
         SELECT 1 FROM `playercreateinfo_spell` cs
          WHERE cs.`race` = m.parent_race AND cs.`spell` = a.action
       );
