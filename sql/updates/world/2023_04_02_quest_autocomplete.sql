DELETE FROM command WHERE `name` = 'quest autocomplete';
INSERT INTO command (`name`, `security`, `help`) VALUES
('quest autocomplete', 3, 'Syntax: .quest autocomplete #questid\r\nMark all unfinished quest objectives as bugged for target character active quest. After this when this player pick up this quest these bugged quest objectives will automatically be completed.');

DELETE FROM trinity_string WHERE `entry` = 600032;
INSERT INTO trinity_string (`entry`, `content_default`) VALUES
(600032, 'Quest with ID: %u is (partially) set to autocomplete based the quest state of player: %s');
SET @lf := (SELECT COUNT(*) FROM `information_schema`.`COLUMNS` WHERE `TABLE_SCHEMA`=DATABASE() AND `TABLE_NAME`='quest_objectives' AND `COLUMN_NAME`='Bugged');
SET @lf_sql := IF(@lf = 0, 'ALTER TABLE `quest_objectives` ADD COLUMN `Bugged` TINYINT(3) UNSIGNED NOT NULL DEFAULT 0 AFTER `VerifiedBuild`', 'DO 0');
PREPARE lf FROM @lf_sql; EXECUTE lf; DEALLOCATE PREPARE lf;
