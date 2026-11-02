SET FOREIGN_KEY_CHECKS = 0;
DROP DATABASE IF EXISTS `asset_management_system`;
CREATE DATABASE `asset_management_system`;
USE `asset_management_system`;
SOURCE schema.sql;
SOURCE seed_data.sql;
SET FOREIGN_KEY_CHECKS = 1;
