-- Migration: 003_employee_transfer_asset_preferences.sql
-- Purpose:
--   Support employee self-service transfer preferences: when an employee
--   knows they are being transferred, they can state which currently
--   allocated asset(s) they'd like to keep vs return, before an
--   Admin/Super Admin/Department Head reviews and finalizes the actual
--   transfer (TransferEmployeeServlet). The employee's submission is only
--   ever a request/preference - it never changes allocation_status or
--   asset_status by itself, and the admin can override it when finalizing.
--
-- Run this once against the live AMS database (mysql -u root -p asset_management_system
-- < 003_employee_transfer_asset_preferences.sql) before deploying the updated app.
-- Idempotent-safe guard included per column via information_schema check.

SET @col_exists := (
  SELECT COUNT(*) FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'asset_allocation'
    AND COLUMN_NAME = 'employee_transfer_preference'
);

SET @sql := IF(@col_exists = 0,
  'ALTER TABLE asset_allocation
     ADD COLUMN employee_transfer_preference ENUM(''RETAIN'',''RETURN'') NULL DEFAULT NULL AFTER remarks,
     ADD COLUMN employee_transfer_note VARCHAR(255) NULL DEFAULT NULL AFTER employee_transfer_preference,
     ADD COLUMN employee_transfer_requested_at TIMESTAMP NULL DEFAULT NULL AFTER employee_transfer_note',
  'SELECT ''employee_transfer_preference already present, skipping'' AS notice'
);

PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;
