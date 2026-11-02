-- Migration: 008_maintenance_request_log_linkage.sql
-- Purpose:
--   Closes a confirmed Future Scope gap: an employee-reported maintenance
--   request (maintenance_requests) and the maintenance log that actually
--   resolved it (maintenance_logs) had no structural link at all - marking a
--   request COMPLETED was a bare status flip
--   (MaintenanceRequestDAO.updateMaintenanceRequestStatus), so the two tables
--   only ever connected by timing coincidence.
--
--   Adds resolved_maintenance_id, populated when a request is marked
--   COMPLETED (UpdateMaintenanceRequestStatusServlet), making "which log
--   resolved this request" a directly queryable fact. Nullable: a request
--   can still be completed with nothing to link to if no maintenance_logs
--   row exists yet for that asset.
--
-- Run this once against the live AMS database
--   (mysql -u root -p asset_management_system < 008_maintenance_request_log_linkage.sql)
-- Idempotent: safe to re-run.

SET @col_exists = (
    SELECT COUNT(*) FROM information_schema.COLUMNS
    WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'maintenance_requests' AND COLUMN_NAME = 'resolved_maintenance_id'
);
SET @ddl = IF(@col_exists = 0,
    "ALTER TABLE `maintenance_requests` ADD COLUMN `resolved_maintenance_id` int DEFAULT NULL AFTER `remarks`",
    'SELECT 1');
PREPARE stmt FROM @ddl; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @idx_exists = (
    SELECT COUNT(*) FROM information_schema.STATISTICS
    WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'maintenance_requests' AND INDEX_NAME = 'idx_maintenance_requests_resolved_id'
);
SET @ddl = IF(@idx_exists = 0,
    'ALTER TABLE `maintenance_requests` ADD KEY `idx_maintenance_requests_resolved_id` (`resolved_maintenance_id`)',
    'SELECT 1');
PREPARE stmt FROM @ddl; EXECUTE stmt; DEALLOCATE PREPARE stmt;

-- ON DELETE SET NULL: this is a soft backreference to the log that happened
-- to resolve the request, not an ownership relationship, so removing the
-- log should not block or cascade-delete the request record.
SET @fk_exists = (
    SELECT COUNT(*) FROM information_schema.TABLE_CONSTRAINTS
    WHERE CONSTRAINT_SCHEMA = DATABASE()
      AND TABLE_NAME = 'maintenance_requests'
      AND CONSTRAINT_NAME = 'fk_maintenance_requests_resolved_id'
);
SET @ddl = IF(@fk_exists = 0,
    'ALTER TABLE `maintenance_requests` ADD CONSTRAINT `fk_maintenance_requests_resolved_id` FOREIGN KEY (`resolved_maintenance_id`) REFERENCES `maintenance_logs` (`maintenance_id`) ON DELETE SET NULL ON UPDATE CASCADE',
    'SELECT 1');
PREPARE stmt FROM @ddl; EXECUTE stmt; DEALLOCATE PREPARE stmt;
