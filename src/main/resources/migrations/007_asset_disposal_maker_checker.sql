-- Migration: 007_asset_disposal_maker_checker.sql
-- Purpose:
--   Closes a confirmed Future Scope gap: the database already modelled a
--   full maker-checker approval chain for asset disposal (asset_disposal.
--   disposal_status enum includes PENDING/APPROVED/COMPLETED/REJECTED) but
--   no code path ever used it - AssetDAO.disposeAsset() inserted a row as
--   'COMPLETED' and flipped assets.asset_status to DISPOSED in the same
--   single step, a single-actor action with no second-party authorization
--   for an inherently high-consequence, financially significant change.
--
--   Adds two new columns recording who proposed the disposal and when,
--   deliberately separate from approved_by/approved_date (which now
--   exclusively record the second-party reviewer's decision) - same
--   "X_by/X_date" attribution pairing already used throughout this schema.
--
-- Run this once against the live AMS database
--   (mysql -u root -p asset_management_system < 007_asset_disposal_maker_checker.sql)
-- Idempotent: safe to re-run.
--
-- Uses the information_schema.COLUMNS-guarded dynamic-SQL pattern (not
-- ADD COLUMN IF NOT EXISTS) - confirmed genuinely rejected as a syntax
-- error on this deployment's MySQL 9.7.0, per 006's fault note.

SET @col_exists = (
    SELECT COUNT(*) FROM information_schema.COLUMNS
    WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'asset_disposal' AND COLUMN_NAME = 'requested_by'
);
SET @ddl = IF(@col_exists = 0,
    "ALTER TABLE `asset_disposal` ADD COLUMN `requested_by` int DEFAULT NULL AFTER `disposal_value`",
    'SELECT 1');
PREPARE stmt FROM @ddl; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @col_exists = (
    SELECT COUNT(*) FROM information_schema.COLUMNS
    WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'asset_disposal' AND COLUMN_NAME = 'requested_date'
);
SET @ddl = IF(@col_exists = 0,
    "ALTER TABLE `asset_disposal` ADD COLUMN `requested_date` date DEFAULT NULL AFTER `requested_by`",
    'SELECT 1');
PREPARE stmt FROM @ddl; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @idx_exists = (
    SELECT COUNT(*) FROM information_schema.STATISTICS
    WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'asset_disposal' AND INDEX_NAME = 'idx_disposal_requested_by'
);
SET @ddl = IF(@idx_exists = 0,
    'ALTER TABLE `asset_disposal` ADD KEY `idx_disposal_requested_by` (`requested_by`)',
    'SELECT 1');
PREPARE stmt FROM @ddl; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @fk_exists = (
    SELECT COUNT(*) FROM information_schema.TABLE_CONSTRAINTS
    WHERE CONSTRAINT_SCHEMA = DATABASE()
      AND TABLE_NAME = 'asset_disposal'
      AND CONSTRAINT_NAME = 'fk_disposal_requested_by'
);
SET @ddl = IF(@fk_exists = 0,
    'ALTER TABLE `asset_disposal` ADD CONSTRAINT `fk_disposal_requested_by` FOREIGN KEY (`requested_by`) REFERENCES `users` (`user_id`) ON DELETE SET NULL ON UPDATE CASCADE',
    'SELECT 1');
PREPARE stmt FROM @ddl; EXECUTE stmt; DEALLOCATE PREPARE stmt;

-- Backfill: every disposal row that already exists was written by the old
-- single-actor disposeAsset() (disposal_status='COMPLETED', approved_by set
-- to whoever clicked Dispose). Copy that same actor/date into
-- requested_by/requested_date so historical rows aren't left with an empty
-- "requested by" field - they were, in effect, both maker and checker at once.
UPDATE `asset_disposal`
SET `requested_by` = `approved_by`, `requested_date` = COALESCE(`requested_date`, `approved_date`, `disposal_date`)
WHERE `requested_by` IS NULL AND `disposal_status` = 'COMPLETED';
