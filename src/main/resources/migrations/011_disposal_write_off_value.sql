-- Migration: 011_disposal_write_off_value.sql
-- Purpose:
--   Part of the Future Scope "Financial and Accounting Integration" item.
--   Adds asset_disposal.calculated_book_value - the asset's own
--   DepreciationUtil-computed book value as of its disposal date, populated
--   automatically by AssetDAO.reviewDisposal() at approval time, never
--   user-entered. Deliberately separate from disposal_value (whatever
--   salvage/resale figure the maker manually typed in when submitting the
--   proposal) - this is the system's own independent accounting figure,
--   giving a genuine reconciliation point between "what we recorded as
--   recovered" and "what the books said this asset was actually worth" -
--   closing the "recording only a disposal value with no downstream
--   reconciliation" gap the project report's Future Scope flagged.
--
-- Run this once against the live AMS database
--   (mysql -u root -p asset_management_system < 011_disposal_write_off_value.sql)
-- Idempotent: safe to re-run.

SET @col_exists = (
    SELECT COUNT(*) FROM information_schema.COLUMNS
    WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'asset_disposal' AND COLUMN_NAME = 'calculated_book_value'
);
SET @ddl = IF(@col_exists = 0,
    "ALTER TABLE `asset_disposal` ADD COLUMN `calculated_book_value` decimal(12,2) DEFAULT NULL AFTER `remarks`",
    'SELECT 1');
PREPARE stmt FROM @ddl; EXECUTE stmt; DEALLOCATE PREPARE stmt;
