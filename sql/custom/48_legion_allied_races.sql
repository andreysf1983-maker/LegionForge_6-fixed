-- ==========================================================================
--   LEGIONFORGE 7.3.5 - разблокировка союзных рас Legion (27-30)
--   Файл: sql/48_legion_allied_races.sql   (идемпотентен)
--
--   АУДИТ ПОКАЗАЛ (docs/FEATURE-AUDIT.md): данные для этих рас в ADB_735.10
--   ПОЛНЫЕ - стартовые позиции в их собственных зонах Legion, уровневая
--   статистика и стартовый маунт уже есть:
--     27 Ночнорождённые        map 1220 zone 7637 (Suramar)      7 классов
--     28 Таурены Крутогорья     map 1220 zone 7731 (Highmountain) 5 классов
--     29 Эл'рейские             map 1865                          7 классов
--     30 Озарённые дренеи       map 1860                          5 классов
--   Классы старта совпадают с player_levelstats (проверено), поэтому
--   worldserver не упадёт на "Level 1 does not have stats data!".
--
--   МЕШАЕТ ТОЛЬКО ГЕЙТ ДОПОЛНЕНИЯ:
--     race_unlock_requirement.expansion = 7 (BfA), а сервер Legion:
--     worldserver.conf Expansion = 6, аккаунт expansion = 6.
--     CharacterHandler.cpp: raceUnlock.HasExpansion = GetAccountExpansion() >= 7
--     -> клиент получает "раса не открыта".
--   Ставим 6 (Legion). Поднимать expansion аккаунта до 7 НЕЛЬЗЯ:
--   GetMaxLevelForExpansion(7) возвращает 0 (ветки BfA в ядре нет).
--
--   Вторая половина включения - одна строка ядра (см. docs/FEATURE-AUDIT.md):
--     core/src/server/game/Handlers/CharacterHandler.cpp
--     IsAlliedRacesCreationAllowed = GetAccountExpansion() >= EXPANSION_LEGION
--   Без перекомпиляции клиент не покажет раздел союзных рас.
-- ==========================================================================

SET NAMES utf8mb4;

UPDATE `race_unlock_requirement` SET `expansion` = 6, `achievementId` = 0
 WHERE `raceID` IN (27, 28, 29, 30) AND `expansion` <> 6;

INSERT INTO `race_unlock_requirement` (`raceID`, `expansion`, `achievementId`)
SELECT r.raceID, 6, 0
  FROM (SELECT 27 AS raceID UNION ALL SELECT 28 UNION ALL SELECT 29 UNION ALL SELECT 30) r
 WHERE NOT EXISTS (SELECT 1 FROM `race_unlock_requirement` x WHERE x.raceID = r.raceID);
