-- Migration: 009_asset_request_fulfillment_traceability.sql
-- Purpose:
--   Closes a confirmed Future Scope gap: marking an asset request FULFILLED
--   (UpdateRequestStatusServlet -> AssetRequestDAO.updateRequestStatus) was a
--   bare status flip - fulfilled_asset_id was never actually populated
--   anywhere in the codebase, despite already existing on the table, and
--   there was no link at all to the specific asset_allocation record that
--   satisfied the request.
--
--   Adds fulfilled_allocation_id. Both fulfilled_allocation_id and
--   fulfilled_asset_id are now set together when a request is marked
--   FULFILLED: the actor picks one of the employee's active allocations,
--   fulfilled_asset_id is derived from it and kept in sync for backward
--   compatibility with existing reads (view_request.jsp already joins on it).
--
-- Run this once against the live AMS database
--   (mysql -u root -p asset_management_system < 009_asset_request_fulfillment_traceability.sql)
-- Idempotent: safe to re-run.

SET @col_exists = (
    SELECT COUNT(*) FROM information_schema.COLUMNS
    WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'asset_requests' AND COLUMN_NAME = 'fulfilled_allocation_id'
);
SET @ddl = IF(@col_exists = 0,
    "ALTER TABLE `asset_requests` ADD COLUMN `fulfilled_allocation_id` int DEFAULT NULL AFTER `fulfilled_asset_id`",
    'SELECT 1');
PREPARE stmt FROM @ddl; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @idx_exists = (
    SELECT COUNT(*) FROM information_schema.STATISTICS
    WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'asset_requests' AND INDEX_NAME = 'idx_requests_fulfilled_allocation_id'
);
SET @ddl = IF(@idx_exists = 0,
    'ALTER TABLE `asset_requests` ADD KEY `idx_requests_fulfilled_allocation_id` (`fulfilled_allocation_id`)',
    'SELECT 1');
PREPARE stmt FROM @ddl; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @fk_exists = (
    SELECT COUNT(*) FROM information_schema.TABLE_CONSTRAINTS
    WHERE CONSTRAINT_SCHEMA = DATABASE()
      AND TABLE_NAME = 'asset_requests'
      AND CONSTRAINT_NAME = 'fk_requests_fulfilled_allocation'
);
SET @ddl = IF(@fk_exists = 0,
    'ALTER TABLE `asset_requests` ADD CONSTRAINT `fk_requests_fulfilled_allocation` FOREIGN KEY (`fulfilled_allocation_id`) REFERENCES `asset_allocation` (`allocation_id`) ON DELETE SET NULL ON UPDATE CASCADE',
    'SELECT 1');
PREPARE stmt FROM @ddl; EXECUTE stmt; DEALLOCATE PREPARE stmt;
