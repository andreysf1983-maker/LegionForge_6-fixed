-- =====================================================================================
-- LEGIONFORGE 7.3.5.26124 - [111] remove start data for races this client does NOT have.
--
-- Verified against the client's own ChrRaces.db2 (610-table dbc dump, 2026-10-17):
--   playable custom races  = 12..21, 33 (all have CharSections)
--   enemy-only races       = 38..44 (FelOrc..IceTroll, no CharSections)
--   races 31, 32, 34..37   = DO NOT EXIST in the client at all.
--
-- 50_uwow_custom_races.sql and 52_custom_races_31_44.sql were written for a DIFFERENT
-- (BfA-numbering) client and cloned start data into slots 31..44. They run BEFORE the
-- correct 105_..._real_ids.sql and use INSERT IGNORE, so they also poisoned race 33:
-- 52 made it "Custom race 33 (Alliance, donor: Night Elf)", while the client has
-- ThinHuman (NEUTRAL, donor Human). Both patches are now disabled in apply_play_sql.ps1;
-- this file removes what they already wrote and re-creates race 33 correctly.
--
-- Runs AFTER 105 (its column widenings for 64-bit racemasks are prerequisites).
-- Idempotent. Target: WORLD database.
-- =====================================================================================

SET NAMES utf8mb4;

-- 1. Races that do not exist in the client: 31, 32, 34, 35, 36, 37 ---------------------
DELETE FROM `playercreateinfo`        WHERE `race`   IN (31, 32, 34, 35, 36, 37);
DELETE FROM `playercreateinfo_item`   WHERE `race`   IN (31, 32, 34, 35, 36, 37);
DELETE FROM `playercreateinfo_action` WHERE `race`   IN (31, 32, 34, 35, 36, 37);
DELETE FROM `player_levelstats`       WHERE `race`   IN (31, 32, 34, 35, 36, 37);
DELETE FROM `race_unlock_requirement` WHERE `raceID` IN (31, 32, 34, 35, 36, 37);
-- LEGIONFORGE FIX 2026: LegionCore 7.3.5 does NOT have playercreateinfo_cast_spell /
-- playercreateinfo_spell_custom (those are TrinityCore-master tables). The core reads
-- `playercreateinfo_spell` (race, class, spell) - see ObjectMgr::LoadPlayerInfo.
DELETE FROM `playercreateinfo_spell` WHERE `race` IN (31, 32, 34, 35, 36, 37);

-- 2. Race 33 is ThinHuman (NEUTRAL, donor Human) in this client: rebuild from race 1 ---
DELETE FROM `playercreateinfo`        WHERE `race` = 33;
DELETE FROM `playercreateinfo_item`   WHERE `race` = 33;
DELETE FROM `playercreateinfo_action` WHERE `race` = 33;
DELETE FROM `player_levelstats`       WHERE `race` = 33;
DELETE FROM `playercreateinfo_spell`  WHERE `race` = 33;

INSERT IGNORE INTO `playercreateinfo`
  (`race`, `class`, `map`, `zone`, `position_x`, `position_y`, `position_z`, `orientation`)
SELECT 33, p.`class`, p.`map`, p.`zone`, p.`position_x`, p.`position_y`, p.`position_z`, p.`orientation`
  FROM `playercreateinfo` p WHERE p.`race` = 1;

INSERT IGNORE INTO `player_levelstats` (`race`, `class`, `level`, `str`, `agi`, `sta`, `inte`)
SELECT 33, s.`class`, s.`level`, s.`str`, s.`agi`, s.`sta`, s.`inte`
  FROM `player_levelstats` s WHERE s.`race` = 1;

INSERT IGNORE INTO `playercreateinfo_item` (`race`, `class`, `itemid`, `amount`)
SELECT 33, i.`class`, i.`itemid`, i.`amount`
  FROM `playercreateinfo_item` i WHERE i.`race` = 1;

INSERT IGNORE INTO `playercreateinfo_action` (`race`, `class`, `button`, `action`, `type`)
SELECT 33, a.`class`, a.`button`, a.`action`, a.`type`
  FROM `playercreateinfo_action` a WHERE a.`race` = 1;

INSERT IGNORE INTO `playercreateinfo_spell` (`race`, `class`, `spell`)
SELECT 33, s.`class`, s.`spell`
  FROM `playercreateinfo_spell` s WHERE s.`race` = 1;

INSERT INTO `race_unlock_requirement` (`raceID`, `expansion`, `achievementId`)
VALUES (33, 6, 0)
ON DUPLICATE KEY UPDATE `expansion` = 6, `achievementId` = 0;

-- 3. Verification ----------------------------------------------------------------------
SELECT 'playercreateinfo rows for non-client races 31,32,34-37' AS `check`, COUNT(*) AS remaining
  FROM `playercreateinfo` WHERE `race` IN (31, 32, 34, 35, 36, 37)
UNION ALL
SELECT 'race_unlock rows for non-client races', COUNT(*)
  FROM `race_unlock_requirement` WHERE `raceID` IN (31, 32, 34, 35, 36, 37)
UNION ALL
SELECT 'playercreateinfo rows for race 33 (ThinHuman)', COUNT(*)
  FROM `playercreateinfo` WHERE `race` = 33
UNION ALL
SELECT 'player_levelstats rows for race 33', COUNT(*)
  FROM `player_levelstats` WHERE `race` = 33;
