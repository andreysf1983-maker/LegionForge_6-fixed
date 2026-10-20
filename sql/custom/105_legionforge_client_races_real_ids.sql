-- =====================================================================
-- LEGIONFORGE 7.3.5.26124 - [105] custom client races: REAL ids from the client.
--
-- Source of truth: ChrRaces.db2 of THIS client (server/data/dbc/<locale>).
-- The new races are NOT at 31..44 in that file. They occupy the free slots:
--   12 Haranir  13 Dracthyr Visage  14 Broken  15 Vulpera  16 Vrykul
--   17 Dark Iron Dwarf  18 Kul Tiran  19 Taunka  20 Mag'har Orc
--   21 Zandalari Troll  33 ThinHuman
-- and 38..44 are enemy-only races (Fel Orc, Naga, Skeleton, Tuskarr,
-- Forest Troll, Northrend Skeleton, Ice Troll) with no CharSections.
--
-- The slot MUST equal the race id in the client: the client sends that id in
-- the character creation packet, so moving a race to another slot makes the
-- server reject the character. The previous patch (52) assumed 31..44 and
-- therefore created nothing for this client.
--
-- Server reads the same ChrRaces.db2, so display ids, factions and team come
-- from the client automatically; only the start data has to be cloned.
--
-- Target: WORLD database. Idempotent (safe to re-run).
-- =====================================================================

SET NAMES utf8mb4;

-- ---------------------------------------------------------------------------
-- 1. Table of new races: id -> donor race (vanilla race with the same faction)
-- ---------------------------------------------------------------------------
DROP TEMPORARY TABLE IF EXISTS `lf_race_client`;
CREATE TEMPORARY TABLE `lf_race_client` (
  `race` TINYINT UNSIGNED NOT NULL PRIMARY KEY,
  `base` TINYINT UNSIGNED NOT NULL,
  `team` VARCHAR(10)  NOT NULL,
  `name` VARCHAR(64)  NOT NULL
) ENGINE = MEMORY;

INSERT INTO `lf_race_client` (`race`, `base`, `team`, `name`) VALUES
  (12, 8, 'HORDE', 'Haranir (Harronir), Horde, donor Troll'),
  (13, 1, 'ALLIANCE', 'Dracthyr Visage, Alliance, donor Human'),
  (14, 1, 'NEUTRAL', 'Broken, neutral, donor Human'),
  (15, 9, 'HORDE', 'Vulpera, Horde, donor Goblin'),
  (16, 1, 'NEUTRAL', 'Vrykul, neutral, donor Human'),
  (17, 3, 'ALLIANCE', 'Dark Iron Dwarf, Alliance, donor Dwarf'),
  (18, 1, 'ALLIANCE', 'Kul Tiran, Alliance, donor Human'),
  (19, 1, 'NEUTRAL', 'Taunka, neutral, donor Human'),
  (20, 2, 'HORDE', 'Mag''har Orc, Horde, donor Orc'),
  (21, 8, 'HORDE', 'Zandalari Troll, Horde, donor Troll'),
  (33, 1, 'NEUTRAL', 'ThinHuman, neutral, donor Human'),
  (38, 1, 'NEUTRAL', 'Fel Orc (no CharSections), neutral, donor Human'),
  (39, 1, 'NEUTRAL', 'Naga (no CharSections), neutral, donor Human'),
  (40, 1, 'NEUTRAL', 'Skeleton (no CharSections), neutral, donor Human'),
  (41, 1, 'NEUTRAL', 'Tuskarr (no CharSections), neutral, donor Human'),
  (42, 1, 'NEUTRAL', 'Forest Troll (no CharSections), neutral, donor Human'),
  (43, 1, 'NEUTRAL', 'Northrend Skeleton (no CharSections), neutral, donor Human'),
  (44, 1, 'NEUTRAL', 'Ice Troll (no CharSections), neutral, donor Human');

-- ---------------------------------------------------------------------------
-- 2. LEGIONFORGE FIX 2026: LegionCore 7.3.5 (build 26124) does NOT use the
--    TrinityCore-master tables `playercreateinfo_cast_spell` /
--    `playercreateinfo_spell_custom`.  Start spells are read from
--    `playercreateinfo_spell` (race, class, spell) - see
--    ObjectMgr::LoadPlayerInfo() in core/src/server/game/Globals/ObjectMgr.cpp.
--    No 64-bit racemask columns are needed any more: the race id is stored
--    directly, so races 33..44 work without any ALTER TABLE.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `playercreateinfo_spell` (
  `race`  TINYINT(3) UNSIGNED NOT NULL DEFAULT '0',
  `class` TINYINT(3) UNSIGNED NOT NULL DEFAULT '0',
  `spell` INT(10) UNSIGNED NOT NULL DEFAULT '0',
  `Note`  VARCHAR(255) NULL DEFAULT NULL,
  PRIMARY KEY (`race`,`class`,`spell`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

-- ---------------------------------------------------------------------------
-- 3. Tables the core reads at startup
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `player_levelstats` (
  `race` TINYINT(3) UNSIGNED NOT NULL DEFAULT '0',
  `class` TINYINT(3) UNSIGNED NOT NULL DEFAULT '0',
  `level` TINYINT(3) UNSIGNED NOT NULL DEFAULT '0',
  `str` SMALLINT(5) UNSIGNED NOT NULL DEFAULT '0',
  `agi` SMALLINT(5) UNSIGNED NOT NULL DEFAULT '0',
  `sta` SMALLINT(5) UNSIGNED NOT NULL DEFAULT '0',
  `inte` SMALLINT(5) UNSIGNED NOT NULL DEFAULT '0',
  PRIMARY KEY (`race`,`class`,`level`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

CREATE TABLE IF NOT EXISTS `race_unlock_requirement` (
  `raceID` TINYINT(3) UNSIGNED NOT NULL DEFAULT '0',
  `expansion` TINYINT(3) UNSIGNED NOT NULL DEFAULT '0',
  `achievementId` INT(10) UNSIGNED NOT NULL DEFAULT '0',
  PRIMARY KEY (`raceID`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

-- ---------------------------------------------------------------------------
-- 4. Start data cloned from the donor race
-- ---------------------------------------------------------------------------
INSERT IGNORE INTO `playercreateinfo`
  (`race`, `class`, `map`, `zone`, `position_x`, `position_y`, `position_z`, `orientation`)
SELECT m.`race`, p.`class`, p.`map`, p.`zone`, p.`position_x`, p.`position_y`, p.`position_z`, p.`orientation`
  FROM `lf_race_client` m
  JOIN `playercreateinfo` p ON p.`race` = m.`base`;

INSERT IGNORE INTO `player_levelstats` (`race`, `class`, `level`, `str`, `agi`, `sta`, `inte`)
SELECT m.`race`, s.`class`, s.`level`, s.`str`, s.`agi`, s.`sta`, s.`inte`
  FROM `lf_race_client` m
  JOIN `player_levelstats` s ON s.`race` = m.`base`;

INSERT IGNORE INTO `playercreateinfo_item` (`race`, `class`, `itemid`, `amount`)
SELECT m.`race`, i.`class`, i.`itemid`, i.`amount`
  FROM `lf_race_client` m
  JOIN `playercreateinfo_item` i ON i.`race` = m.`base`;

INSERT IGNORE INTO `playercreateinfo_action` (`race`, `class`, `button`, `action`, `type`)
SELECT m.`race`, a.`class`, a.`button`, a.`action`, a.`type`
  FROM `lf_race_client` m
  JOIN `playercreateinfo_action` a ON a.`race` = m.`base`;

INSERT IGNORE INTO `playercreateinfo_spell` (`race`, `class`, `spell`, `Note`)
SELECT m.`race`, s.`class`, s.`spell`,
       CONCAT('[LF client race ', m.`name`, ']')
  FROM `lf_race_client` m
  JOIN `playercreateinfo_spell` s ON s.`race` = m.`base`;

-- ---------------------------------------------------------------------------
-- 5. Unlock: expansion 6 (Legion). expansion 7 (BfA) gives CHAR_CREATE_EXPANSION,
--    and GetMaxLevelForExpansion(7) is 0 in this core.
-- ---------------------------------------------------------------------------
INSERT INTO `race_unlock_requirement` (`raceID`, `expansion`, `achievementId`)
SELECT m.`race`, 6, 0
  FROM `lf_race_client` m
 WHERE NOT EXISTS (SELECT 1 FROM `race_unlock_requirement` x WHERE x.`raceID` = m.`race`);

UPDATE `race_unlock_requirement`
   SET `expansion` = 6, `achievementId` = 0
 WHERE `raceID` IN (SELECT `race` FROM `lf_race_client`);

-- ---------------------------------------------------------------------------
-- 6. Stale rows of the old assumption (races 31..44 that this client does not
--    have) must not stay: the client never sends them, and they confuse audits.
-- ---------------------------------------------------------------------------
DELETE FROM `playercreateinfo`      WHERE `race` IN (31, 32, 34, 35, 36, 37);
DELETE FROM `player_levelstats`     WHERE `race` IN (31, 32, 34, 35, 36, 37);
DELETE FROM `playercreateinfo_item` WHERE `race` IN (31, 32, 34, 35, 36, 37);
DELETE FROM `playercreateinfo_action` WHERE `race` IN (31, 32, 34, 35, 36, 37);
DELETE FROM `playercreateinfo_spell`  WHERE `race` IN (31, 32, 34, 35, 36, 37);
DELETE FROM `race_unlock_requirement` WHERE `raceID` IN (31, 32, 34, 35, 36, 37);

-- ---------------------------------------------------------------------------
-- 7. Control output: createInfoRows = 0 => the race cannot be created.
-- ---------------------------------------------------------------------------
SELECT m.`race`                                                        AS raceId,
       m.`name`                                                        AS raceName,
       m.`base`                                                        AS donorRace,
       m.`team`                                                        AS team,
       (SELECT COUNT(*) FROM `playercreateinfo`         p WHERE p.`race` = m.`race`) AS createInfoRows,
       (SELECT COUNT(*) FROM `player_levelstats`        s WHERE s.`race` = m.`race`) AS levelStatRows,
       (SELECT COUNT(*) FROM `playercreateinfo_item`    i WHERE i.`race` = m.`race`) AS startItemRows,
       (SELECT COUNT(*) FROM `playercreateinfo_action`  a WHERE a.`race` = m.`race`) AS actionBarRows,
       (SELECT COUNT(*) FROM `race_unlock_requirement`  r WHERE r.`raceID` = m.`race`) AS unlockRows
  FROM `lf_race_client` m
 ORDER BY m.`race`;

DROP TEMPORARY TABLE IF EXISTS `lf_race_client`;
