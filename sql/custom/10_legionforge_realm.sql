-- LegionForge: realm shown in the realm list.
--
-- 1. Name: the realm is called "LegionForge" (earlier packs renamed it to "Archmage").
-- 2. gamebuild MUST be 26124 - the build of the supported client (WoW Legion 7.3.5.26124).
--    sql/legionforge/auth/2018_04_06_00_auth.sql used to move the realm to 26365, so the
--    7.3.5.26124 client saw the realm as "Incompatible" and could not log in.
-- 3. The column default is fixed too, so realms added later get the right build.
--
-- Idempotent: safe to apply on every start (play.bat does exactly that).

UPDATE `realmlist` SET `gamebuild` = 26124 WHERE `gamebuild` <> 26124;

ALTER TABLE `realmlist` ALTER COLUMN `gamebuild` SET DEFAULT 26124;

UPDATE `realmlist` SET `name` = 'LegionForge' WHERE `id` = 1 AND `name` <> 'LegionForge';
