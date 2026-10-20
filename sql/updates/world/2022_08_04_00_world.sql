SET @lf := (SELECT COUNT(*) FROM `information_schema`.`COLUMNS` WHERE `TABLE_SCHEMA`=DATABASE() AND `TABLE_NAME`='creature' AND `COLUMN_NAME`='ScriptName');
SET @lf_sql := IF(@lf = 0, 'ALTER TABLE `creature` ADD COLUMN `ScriptName` CHAR(64) NULL DEFAULT "" AFTER `dynamicflags`', 'DO 0');
PREPARE lf FROM @lf_sql; EXECUTE lf; DEALLOCATE PREPARE lf;
SET @lf := (SELECT COUNT(*) FROM `information_schema`.`COLUMNS` WHERE `TABLE_SCHEMA`=DATABASE() AND `TABLE_NAME`='gameobject' AND `COLUMN_NAME`='ScriptName');
SET @lf_sql := IF(@lf = 0, 'ALTER TABLE `gameobject` ADD COLUMN `ScriptName` CHAR(64) NULL DEFAULT "" AFTER `state`', 'DO 0');
PREPARE lf FROM @lf_sql; EXECUTE lf; DEALLOCATE PREPARE lf;
