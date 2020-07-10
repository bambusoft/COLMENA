DROP DATABASE IF EXISTS colmena;
DROP USER IF EXISTS 'colmenausr'@'localhost';
FLUSH PRIVILEGES;
CREATE USER 'colmenausr'@'localhost' IDENTIFIED WITH 'mysql_native_password' BY '%%PASS%%';
-- If you get error: ER_NOT_SUPPORTED_AUTH_MODE
-- ALTER USER 'colmenausr'@'localhost' IDENTIFIED WITH 'mysql_native_password' BY '%%PASS%%';
FLUSH PRIVILEGES;
CREATE DATABASE colmena CHARACTER SET utf8 COLLATE utf8_general_ci;
GRANT ALL PRIVILEGES ON colmena.* to 'colmenausr'@'localhost';
FLUSH PRIVILEGES;
