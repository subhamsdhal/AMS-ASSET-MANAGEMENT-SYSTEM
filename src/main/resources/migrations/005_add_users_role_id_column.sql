-- Migration: 005_add_users_role_id_column.sql
-- Purpose:
--   Closes a confirmed schema-drift bug found across this codebase's audit
--   (audit/01-auth-session.md §4, audit/02-rbac-roles-permissions.md §4):
--   ~13 call sites (LoginServlet, GenerateEmployeeLoginServlet, AuditDAO,
--   RoleAssignmentDAO, DepartmentDAO, NotificationHelper/
--   NotificationRecipientResolver, TransferEmployeeServlet,
--   UpdateEmployeeServlet, AddEmployeeServlet, and both seed/setup SQL
--   scripts) read or write `users.role_id` and JOIN it against
--   `roles.role_id`, but schema.sql's `users` table never defined this
--   column until this fix. A fresh install built strictly from schema.sql
--   would fail every one of those call sites. If your live/deployed database
--   already has a `role_id` column (added out-of-band at some point, the
--   more likely scenario per the audit's evidence), this migration is a
--   no-op for step 1 and just re-confirms/backfills the data in step 3.
--
--   `current_role` remains the actual authorization source
--   (RoleAuthorizationFilter/RoleAccessUtil key off it, not role_id) -
--   role_id exists so the application's `roles`-table joins resolve
--   correctly, and is kept in sync with current_role by the application
--   layer going forward (UpdateUserRoleServlet, RoleAssignmentDAO).
--
-- Run this once against the live AMS database
--   (mysql -u root -p asset_management_system < 005_add_users_role_id_column.sql)
-- Idempotent: safe to re-run.
--
-- Fault (fixed): this originally used `ADD COLUMN IF NOT EXISTS` /
-- `ADD KEY IF NOT EXISTS`, documented below as "MySQL 8's IF NOT EXISTS
-- makes this safe to re-run" - never actually verified against a live
-- server, since `role_id` already existed on every database this was tested
-- against, so step 1 was always a documented-but-unexercised no-op. Running
-- 006_asset_request_dept_head_review.sql's equivalent step for the first
-- time surfaced that this exact syntax is rejected outright (a plain syntax
-- error, not a version-gate message) on this deployment's MySQL 9.7.0,
-- confirmed by direct isolation testing. Replaced with the
-- information_schema-guarded dynamic-SQL pattern 006 now uses, which never
-- depends on this MySQL server's own IF-NOT-EXISTS DDL support at all.

-- 1. Ensure the column exists.
SET @col_exists = (
    SELECT COUNT(*) FROM information_schema.COLUMNS
    WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'users' AND COLUMN_NAME = 'role_id'
);
SET @ddl = IF(@col_exists = 0,
    "ALTER TABLE `users` ADD COLUMN `role_id` int DEFAULT NULL AFTER `current_role`",
    'SELECT 1');
PREPARE stmt FROM @ddl; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @idx_exists = (
    SELECT COUNT(*) FROM information_schema.STATISTICS
    WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'users' AND INDEX_NAME = 'idx_users_role_id'
);
SET @ddl = IF(@idx_exists = 0,
    'ALTER TABLE `users` ADD KEY `idx_users_role_id` (`role_id`)',
    'SELECT 1');
PREPARE stmt FROM @ddl; EXECUTE stmt; DEALLOCATE PREPARE stmt;

-- 2. Ensure all six roles this application's RBAC model expects actually
--    exist (seed_data.sql only ever seeded a stale ('ADMIN'),('USER') pair;
--    super_admin_setup.sql only adds SUPER_ADMIN/ADMIN) - without this,
--    step 3's backfill would silently leave asset_manager/auditor/dept_head/
--    employee accounts with role_id still NULL.
INSERT IGNORE INTO `roles` (`role_name`) VALUES
    ('SUPER_ADMIN'), ('ADMIN'), ('ASSET_MANAGER'), ('AUDITOR'), ('DEPT_HEAD'), ('EMPLOYEE');

-- 3. Backfill role_id for every existing user from their current_role enum
--    value (case-insensitive match against roles.role_name).
UPDATE `users` u
JOIN `roles` r ON UPPER(r.role_name) = UPPER(u.current_role)
SET u.role_id = r.role_id
WHERE u.role_id IS NULL;

-- 4. Add the FK now that every row is backfilled (schema.sql adds this
--    inline for fresh installs; repeated here, guarded, for databases
--    migrated from an older schema.sql that predates it).
SET @fk_exists = (
    SELECT COUNT(*) FROM information_schema.TABLE_CONSTRAINTS
    WHERE CONSTRAINT_SCHEMA = DATABASE()
      AND TABLE_NAME = 'users'
      AND CONSTRAINT_NAME = 'fk_users_role'
);
SET @add_fk_sql = IF(@fk_exists = 0,
    'ALTER TABLE `users` ADD CONSTRAINT `fk_users_role` FOREIGN KEY (`role_id`) REFERENCES `roles` (`role_id`) ON DELETE SET NULL ON UPDATE CASCADE',
    'SELECT 1'
);
PREPARE stmt FROM @add_fk_sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;
