DROP DATABASE IF EXISTS `@gua_db_name@`;

DROP USER IF EXISTS `@gua_db_user@`@`@ip@`;

CREATE USER `@gua_db_user@`@`@ip@` IDENTIFIED BY '@gua_db_pass@';
GRANT SELECT,INSERT,UPDATE,DELETE ON `@gua_db_name@`.* TO `@gua_db_user@`@`@ip@`;
FLUSH PRIVILEGES;

CREATE DATABASE `@gua_db_name@`;
USE `@gua_db_name@`;
