-- Migration script to move existing users from role_id to current_role ENUM

-- Step 1: Add the new column `current_role` to the `users` table
ALTER TABLE users ADD COLUMN current_role ENUM('super_admin', 'admin', 'asset_manager', 'auditor', 'dept_head', 'employee') NOT NULL DEFAULT 'employee';

-- Step 2: Migrate data with fail-closed logic
-- Assuming role_id = 1 was super_admin, role_id = 2 was admin
-- For safety, we only migrate users matching the known super_admin and admin usernames, and default everyone else to employee.
UPDATE users 
SET current_role = CASE
    WHEN username = 'super_admin' THEN 'super_admin'
    WHEN username = 'admin' THEN 'admin'
    ELSE 'employee'
END;

-- Step 3: Create the role_assignment_log table
CREATE TABLE `role_assignment_log` (
  `log_id` int NOT NULL AUTO_INCREMENT,
  `assigned_to` int NOT NULL,
  `assigned_by` int NOT NULL,
  `old_role` varchar(50) DEFAULT NULL,
  `new_role` varchar(50) NOT NULL,
  `timestamp` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `is_emergency` boolean DEFAULT FALSE,
  PRIMARY KEY (`log_id`),
  KEY `idx_log_assigned_to` (`assigned_to`),
  KEY `idx_log_assigned_by` (`assigned_by`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Step 4: (Optional) Drop the old `role_id` column and the `roles` table if no longer used.
-- ALTER TABLE users DROP FOREIGN KEY `fk_users_role`; (If a foreign key exists)
-- ALTER TABLE users DROP COLUMN role_id;
-- DROP TABLE roles;
