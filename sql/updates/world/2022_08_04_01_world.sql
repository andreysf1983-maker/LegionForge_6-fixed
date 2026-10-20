SET @lf := (SELECT COUNT(*) FROM `information_schema`.`COLUMNS` WHERE `TABLE_SCHEMA`=DATABASE() AND `TABLE_NAME`='quest_template_addon' AND `COLUMN_NAME`='ScriptName');
SET @lf_sql := IF(@lf = 0, 'ALTER TABLE `quest_template_addon` ADD COLUMN `ScriptName` VARCHAR(64) DEFAULT '''' NOT NULL AFTER `SpecialFlags`', 'DO 0');
PREPARE lf FROM @lf_sql; EXECUTE lf; DEALLOCATE PREPARE lf;
