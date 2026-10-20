-- Переименование CriteriaID -> RelationshipData в garr_mission.
-- Выполняется только если старая колонка ещё существует (иначе апдейт уже применён).
SET @lf_old := (SELECT COUNT(*) FROM `information_schema`.`COLUMNS` WHERE `TABLE_SCHEMA`=DATABASE() AND `TABLE_NAME`='garr_mission' AND `COLUMN_NAME`='CriteriaID');
SET @lf_new := (SELECT COUNT(*) FROM `information_schema`.`COLUMNS` WHERE `TABLE_SCHEMA`=DATABASE() AND `TABLE_NAME`='garr_mission' AND `COLUMN_NAME`='RelationshipData');
SET @lf_sql := IF(@lf_old > 0 AND @lf_new = 0,
    'ALTER TABLE `garr_mission` CHANGE COLUMN `CriteriaID` `RelationshipData` INT(11) NOT NULL DEFAULT ''0'' AFTER `EnvGarrMechanicID`',
    'DO 0');
PREPARE lf FROM @lf_sql; EXECUTE lf; DEALLOCATE PREPARE lf;

-- Если колонки нет вовсе - создаём её, чтобы структура соответствовала ядру 7.3.5.26124.
SET @lf_any := (SELECT COUNT(*) FROM `information_schema`.`COLUMNS` WHERE `TABLE_SCHEMA`=DATABASE() AND `TABLE_NAME`='garr_mission' AND `COLUMN_NAME`='RelationshipData');
SET @lf_tbl := (SELECT COUNT(*) FROM `information_schema`.`TABLES` WHERE `TABLE_SCHEMA`=DATABASE() AND `TABLE_NAME`='garr_mission');
SET @lf_sql := IF(@lf_tbl > 0 AND @lf_any = 0,
    'ALTER TABLE `garr_mission` ADD COLUMN `RelationshipData` INT(11) NOT NULL DEFAULT ''0''',
    'DO 0');
PREPARE lf FROM @lf_sql; EXECUTE lf; DEALLOCATE PREPARE lf;
