-- Migration: 010_asset_transfer_workflow.sql
-- Purpose:
--   Adds a genuine employee-to-employee asset transfer workflow, correcting
--   a Future Scope item in the project report - and a mistake made while
--   verifying it. The report claimed "a table for recording asset transfers
--   between employees already exists in the schema, unused by any core
--   workflow." A schema.sql-only search found no such table and the report
--   wording was corrected to say none existed - but a live-database check
--   (done while building this migration) found asset_transfers really does
--   exist, live, with exactly that purpose - it was just never captured in
--   schema.sql, the same class of drift already fixed once for
--   users.role_id (migration 005). CopilotToolExecutor.getAssetTransferHistory()
--   already reads it; nothing has ever written to it. The report's original
--   wording was correct; the "correction" was the actual mistake.
--
--   asset_transfers itself is left completely unchanged (it's an append-only
--   completed-transfer log; source_allocation_id/target_allocation_id are
--   both NOT NULL, so it structurally cannot hold a pending proposal).
--   asset_transfer_requests is new: the maker-checker workflow state machine,
--   same shape as asset_disposal (migration 007). On approval,
--   AssetTransferDAO.reviewTransfer() closes the source allocation, opens a
--   new one for the receiving employee, and inserts the resulting row into
--   asset_transfers - the first ever write to that table.
--
-- Run this once against the live AMS database
--   (mysql -u root -p asset_management_system < 010_asset_transfer_workflow.sql)
-- Idempotent: safe to re-run.

-- 1. asset_transfers - documents the table this migration found already live
--    on this database. CREATE TABLE IF NOT EXISTS is a no-op here (it
--    already exists) - kept only so a fresh install ends up with it too.
CREATE TABLE IF NOT EXISTS asset_transfers (
    transfer_id BIGINT AUTO_INCREMENT PRIMARY KEY,
    asset_id INT NOT NULL,
    source_allocation_id INT NOT NULL,
    target_allocation_id INT NOT NULL,
    from_employee_id INT NOT NULL,
    to_employee_id INT NOT NULL,
    transfer_date DATE NOT NULL,
    transfer_reason VARCHAR(255) NOT NULL,
    authorized_by INT DEFAULT NULL,
    created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY uk_asset_transfers_source_alloc (source_allocation_id),
    UNIQUE KEY uk_asset_transfers_target_alloc (target_allocation_id),
    KEY idx_asset_transfers_asset_id (asset_id),
    KEY idx_asset_transfers_from_emp (from_employee_id),
    KEY idx_asset_transfers_to_emp (to_employee_id),
    KEY idx_asset_transfers_date (transfer_date),
    KEY idx_asset_transfers_auth (authorized_by)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

SET @fk_exists = (SELECT COUNT(*) FROM information_schema.TABLE_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'asset_transfers' AND CONSTRAINT_NAME = 'fk_asset_transfers_asset');
SET @ddl = IF(@fk_exists = 0, 'ALTER TABLE `asset_transfers` ADD CONSTRAINT `fk_asset_transfers_asset` FOREIGN KEY (`asset_id`) REFERENCES `assets` (`asset_id`) ON DELETE RESTRICT ON UPDATE CASCADE', 'SELECT 1');
PREPARE stmt FROM @ddl; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @fk_exists = (SELECT COUNT(*) FROM information_schema.TABLE_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'asset_transfers' AND CONSTRAINT_NAME = 'fk_asset_transfers_auth');
SET @ddl = IF(@fk_exists = 0, 'ALTER TABLE `asset_transfers` ADD CONSTRAINT `fk_asset_transfers_auth` FOREIGN KEY (`authorized_by`) REFERENCES `users` (`user_id`) ON DELETE RESTRICT ON UPDATE CASCADE', 'SELECT 1');
PREPARE stmt FROM @ddl; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @fk_exists = (SELECT COUNT(*) FROM information_schema.TABLE_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'asset_transfers' AND CONSTRAINT_NAME = 'fk_asset_transfers_from_emp');
SET @ddl = IF(@fk_exists = 0, 'ALTER TABLE `asset_transfers` ADD CONSTRAINT `fk_asset_transfers_from_emp` FOREIGN KEY (`from_employee_id`) REFERENCES `employees` (`employee_id`) ON DELETE RESTRICT ON UPDATE CASCADE', 'SELECT 1');
PREPARE stmt FROM @ddl; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @fk_exists = (SELECT COUNT(*) FROM information_schema.TABLE_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'asset_transfers' AND CONSTRAINT_NAME = 'fk_asset_transfers_source_alloc');
SET @ddl = IF(@fk_exists = 0, 'ALTER TABLE `asset_transfers` ADD CONSTRAINT `fk_asset_transfers_source_alloc` FOREIGN KEY (`source_allocation_id`) REFERENCES `asset_allocation` (`allocation_id`) ON DELETE RESTRICT ON UPDATE CASCADE', 'SELECT 1');
PREPARE stmt FROM @ddl; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @fk_exists = (SELECT COUNT(*) FROM information_schema.TABLE_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'asset_transfers' AND CONSTRAINT_NAME = 'fk_asset_transfers_target_alloc');
SET @ddl = IF(@fk_exists = 0, 'ALTER TABLE `asset_transfers` ADD CONSTRAINT `fk_asset_transfers_target_alloc` FOREIGN KEY (`target_allocation_id`) REFERENCES `asset_allocation` (`allocation_id`) ON DELETE RESTRICT ON UPDATE CASCADE', 'SELECT 1');
PREPARE stmt FROM @ddl; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @fk_exists = (SELECT COUNT(*) FROM information_schema.TABLE_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'asset_transfers' AND CONSTRAINT_NAME = 'fk_asset_transfers_to_emp');
SET @ddl = IF(@fk_exists = 0, 'ALTER TABLE `asset_transfers` ADD CONSTRAINT `fk_asset_transfers_to_emp` FOREIGN KEY (`to_employee_id`) REFERENCES `employees` (`employee_id`) ON DELETE RESTRICT ON UPDATE CASCADE', 'SELECT 1');
PREPARE stmt FROM @ddl; EXECUTE stmt; DEALLOCATE PREPARE stmt;

-- 2. asset_transfer_requests - genuinely new, the maker-checker workflow.
CREATE TABLE IF NOT EXISTS asset_transfer_requests (
    request_id INT AUTO_INCREMENT PRIMARY KEY,
    allocation_id INT NOT NULL,
    asset_id INT NOT NULL,
    from_employee_id INT NOT NULL,
    to_employee_id INT NOT NULL,
    transfer_reason VARCHAR(255) DEFAULT NULL,
    request_status ENUM('PENDING','REJECTED','COMPLETED') DEFAULT 'PENDING',
    requested_by INT DEFAULT NULL,
    requested_date DATE DEFAULT NULL,
    reviewed_by INT DEFAULT NULL,
    reviewed_date DATE DEFAULT NULL,
    remarks VARCHAR(255) DEFAULT NULL,
    transfer_id BIGINT DEFAULT NULL,
    created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    KEY idx_transfer_requests_allocation_id (allocation_id),
    KEY idx_transfer_requests_asset_id (asset_id),
    KEY idx_transfer_requests_from_employee_id (from_employee_id),
    KEY idx_transfer_requests_to_employee_id (to_employee_id),
    KEY idx_transfer_requests_status (request_status),
    KEY idx_transfer_requests_requested_by (requested_by),
    KEY idx_transfer_requests_reviewed_by (reviewed_by),
    KEY idx_transfer_requests_transfer_id (transfer_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

SET @fk_exists = (SELECT COUNT(*) FROM information_schema.TABLE_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'asset_transfer_requests' AND CONSTRAINT_NAME = 'fk_transfer_requests_allocation');
SET @ddl = IF(@fk_exists = 0, 'ALTER TABLE `asset_transfer_requests` ADD CONSTRAINT `fk_transfer_requests_allocation` FOREIGN KEY (`allocation_id`) REFERENCES `asset_allocation` (`allocation_id`) ON DELETE RESTRICT ON UPDATE CASCADE', 'SELECT 1');
PREPARE stmt FROM @ddl; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @fk_exists = (SELECT COUNT(*) FROM information_schema.TABLE_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'asset_transfer_requests' AND CONSTRAINT_NAME = 'fk_transfer_requests_asset');
SET @ddl = IF(@fk_exists = 0, 'ALTER TABLE `asset_transfer_requests` ADD CONSTRAINT `fk_transfer_requests_asset` FOREIGN KEY (`asset_id`) REFERENCES `assets` (`asset_id`) ON DELETE RESTRICT ON UPDATE CASCADE', 'SELECT 1');
PREPARE stmt FROM @ddl; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @fk_exists = (SELECT COUNT(*) FROM information_schema.TABLE_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'asset_transfer_requests' AND CONSTRAINT_NAME = 'fk_transfer_requests_from_employee');
SET @ddl = IF(@fk_exists = 0, 'ALTER TABLE `asset_transfer_requests` ADD CONSTRAINT `fk_transfer_requests_from_employee` FOREIGN KEY (`from_employee_id`) REFERENCES `employees` (`employee_id`) ON DELETE RESTRICT ON UPDATE CASCADE', 'SELECT 1');
PREPARE stmt FROM @ddl; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @fk_exists = (SELECT COUNT(*) FROM information_schema.TABLE_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'asset_transfer_requests' AND CONSTRAINT_NAME = 'fk_transfer_requests_to_employee');
SET @ddl = IF(@fk_exists = 0, 'ALTER TABLE `asset_transfer_requests` ADD CONSTRAINT `fk_transfer_requests_to_employee` FOREIGN KEY (`to_employee_id`) REFERENCES `employees` (`employee_id`) ON DELETE RESTRICT ON UPDATE CASCADE', 'SELECT 1');
PREPARE stmt FROM @ddl; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @fk_exists = (SELECT COUNT(*) FROM information_schema.TABLE_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'asset_transfer_requests' AND CONSTRAINT_NAME = 'fk_transfer_requests_requested_by');
SET @ddl = IF(@fk_exists = 0, 'ALTER TABLE `asset_transfer_requests` ADD CONSTRAINT `fk_transfer_requests_requested_by` FOREIGN KEY (`requested_by`) REFERENCES `users` (`user_id`) ON DELETE SET NULL ON UPDATE CASCADE', 'SELECT 1');
PREPARE stmt FROM @ddl; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @fk_exists = (SELECT COUNT(*) FROM information_schema.TABLE_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'asset_transfer_requests' AND CONSTRAINT_NAME = 'fk_transfer_requests_reviewed_by');
SET @ddl = IF(@fk_exists = 0, 'ALTER TABLE `asset_transfer_requests` ADD CONSTRAINT `fk_transfer_requests_reviewed_by` FOREIGN KEY (`reviewed_by`) REFERENCES `users` (`user_id`) ON DELETE SET NULL ON UPDATE CASCADE', 'SELECT 1');
PREPARE stmt FROM @ddl; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @fk_exists = (SELECT COUNT(*) FROM information_schema.TABLE_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = 'asset_transfer_requests' AND CONSTRAINT_NAME = 'fk_transfer_requests_transfer');
SET @ddl = IF(@fk_exists = 0, 'ALTER TABLE `asset_transfer_requests` ADD CONSTRAINT `fk_transfer_requests_transfer` FOREIGN KEY (`transfer_id`) REFERENCES `asset_transfers` (`transfer_id`) ON DELETE SET NULL ON UPDATE CASCADE', 'SELECT 1');
PREPARE stmt FROM @ddl; EXECUTE stmt; DEALLOCATE PREPARE stmt;
