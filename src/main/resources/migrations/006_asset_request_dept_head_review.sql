-- Migration: 006_asset_request_dept_head_review.sql
-- Purpose:
--   Introduces the Department Head review stage for employee-initiated asset
--   requests: Employee -> Department Head (forward or reject) -> Asset
--   Manager/Admin/Super Admin (final approve/reject/fulfill). If an employee's
--   department has no active department head assigned, the request skips
--   straight to the existing Asset Manager stage, exactly as it always has.
--
--   Adds a new request_status enum value ('PENDING_DEPT_HEAD') and four new
--   columns recording the Department Head's own decision, kept deliberately
--   separate from approved_by/approved_date/remarks (which remain the Asset
--   Manager/Admin/Super Admin's columns only) - same "X_by/X_date" pairing
--   convention already used throughout this schema.
--
--   Fault, found live while writing this migration: `ADD COLUMN IF NOT
--   EXISTS` - the syntax 005_add_users_role_id_column.sql relied on for the
--   same purpose - is rejected outright as a syntax error on this server
--   (confirmed: MySQL 9.7.0), even with no AFTER clause. Not a documented
--   version-gate issue found by research beforehand; found by this migration
--   actually failing when run. Uses the information_schema.COLUMNS guard
--   pattern instead (same technique 005 already used correctly for its FK,
--   just not for its column) - genuinely version-portable since it never
--   relies on this MySQL server's own IF-NOT-EXISTS DDL support at all.
--
-- Run this once against the live AMS database
--   (mysql -u root -p asset_management_system < 006_asset_request_dept_head_review.sql)
-- Idempotent: safe to re-run.

-- 1. Widen the status enum. MySQL requires a full MODIFY COLUMN (no
--    ADD-value-to-enum shorthand); existing rows keep their current value
--    since PENDING_DEPT_HEAD is only ever set by new code going forward.
--    MODIFY COLUMN with an enum that's a superset of the current one is
--    itself always safe to re-run.
ALTER TABLE `asset_requests`
  MODIFY COLUMN `request_status`
  enum('PENDING_DEPT_HEAD','PENDING','APPROVED','REJECTED','FULFILLED','CANCELLED')
  CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT 'PENDING';

-- 2. Add the four Department Head review columns, each guarded by an
--    information_schema existence check rather than ADD COLUMN IF NOT
--    EXISTS (see the fault note above).
SET @col_exists = (
    SELECT COUNT(*) FROM information_schema.COLUMNS
    WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'asset_requests' AND COLUMN_NAME = 'dept_head_action'
);
SET @ddl = IF(@col_exists = 0,
    "ALTER TABLE `asset_requests` ADD COLUMN `dept_head_action` enum('FORWARDED','REJECTED') CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL AFTER `remarks`",
    'SELECT 1');
PREPARE stmt FROM @ddl; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @col_exists = (
    SELECT COUNT(*) FROM information_schema.COLUMNS
    WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'asset_requests' AND COLUMN_NAME = 'dept_head_by'
);
SET @ddl = IF(@col_exists = 0,
    "ALTER TABLE `asset_requests` ADD COLUMN `dept_head_by` int DEFAULT NULL AFTER `dept_head_action`",
    'SELECT 1');
PREPARE stmt FROM @ddl; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @col_exists = (
    SELECT COUNT(*) FROM information_schema.COLUMNS
    WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'asset_requests' AND COLUMN_NAME = 'dept_head_date'
);
SET @ddl = IF(@col_exists = 0,
    "ALTER TABLE `asset_requests` ADD COLUMN `dept_head_date` date DEFAULT NULL AFTER `dept_head_by`",
    'SELECT 1');
PREPARE stmt FROM @ddl; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @col_exists = (
    SELECT COUNT(*) FROM information_schema.COLUMNS
    WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'asset_requests' AND COLUMN_NAME = 'dept_head_remarks'
);
SET @ddl = IF(@col_exists = 0,
    "ALTER TABLE `asset_requests` ADD COLUMN `dept_head_remarks` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL AFTER `dept_head_date`",
    'SELECT 1');
PREPARE stmt FROM @ddl; EXECUTE stmt; DEALLOCATE PREPARE stmt;

-- 3. Index (KEY ... IF NOT EXISTS has the identical portability problem as
--    ADD COLUMN, per the fault note above - same guard pattern).
SET @idx_exists = (
    SELECT COUNT(*) FROM information_schema.STATISTICS
    WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'asset_requests' AND INDEX_NAME = 'idx_requests_dept_head_by'
);
SET @ddl = IF(@idx_exists = 0,
    'ALTER TABLE `asset_requests` ADD KEY `idx_requests_dept_head_by` (`dept_head_by`)',
    'SELECT 1');
PREPARE stmt FROM @ddl; EXECUTE stmt; DEALLOCATE PREPARE stmt;

-- 4. FK (unchanged pattern from 005 - this guard style was already correct there).
SET @fk_exists = (
    SELECT COUNT(*) FROM information_schema.TABLE_CONSTRAINTS
    WHERE CONSTRAINT_SCHEMA = DATABASE()
      AND TABLE_NAME = 'asset_requests'
      AND CONSTRAINT_NAME = 'fk_requests_dept_head_by'
);
SET @ddl = IF(@fk_exists = 0,
    'ALTER TABLE `asset_requests` ADD CONSTRAINT `fk_requests_dept_head_by` FOREIGN KEY (`dept_head_by`) REFERENCES `users` (`user_id`) ON DELETE SET NULL ON UPDATE CASCADE',
    'SELECT 1');
PREPARE stmt FROM @ddl; EXECUTE stmt; DEALLOCATE PREPARE stmt;
