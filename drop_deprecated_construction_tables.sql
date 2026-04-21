-- Drops deprecated/optional construction tables.
-- Safe to run multiple times.

SET @OLD_FK_CHECKS = @@FOREIGN_KEY_CHECKS;
SET FOREIGN_KEY_CHECKS = 0;

DROP TABLE IF EXISTS construction_contract_change_history;
DROP TABLE IF EXISTS construction_contract_summary;

SET FOREIGN_KEY_CHECKS = @OLD_FK_CHECKS;

