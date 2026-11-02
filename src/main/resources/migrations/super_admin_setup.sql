-- Migration script: super_admin_setup.sql
-- Purpose: Create immutable super_admin account and configure operational admin account.

-- 1. Ensure SUPER_ADMIN and ADMIN roles exist
INSERT IGNORE INTO `roles` (`role_name`) VALUES ('SUPER_ADMIN'), ('ADMIN');

-- 2. Duplicate 'admin' to create 'super_admin' (preserving password hash)
-- Fault (Critical, fixed): force_password_change used to be copied straight
-- from the source 'admin' row, so if that row's flag was ever 0 (its schema
-- default, before the seed_data.sql fix above existed), the newly-created
-- super_admin account would inherit 'super_admin123' - a plaintext default
-- checked into this file - as a standing, never-expiring password. Forced to
-- 1 unconditionally here instead, independent of the source row's value.
INSERT IGNORE INTO `users` (`username`, `password_plaintext`, `password_crypt`, `email`, `role_id`, `employee_id`, `status`, `force_password_change`)
SELECT
    'super_admin',
    'super_admin123',
    '$2a$10$6SDVR9Lyw3qiQMvUN9vzUuiGv1borbrtJ7FGLUfO6nqeu7X6fIKJG',
    'superadmin@railway.gov',
    (SELECT role_id FROM roles WHERE role_name='SUPER_ADMIN' LIMIT 1),
    employee_id,
    status,
    1
FROM users
WHERE username='admin';

-- 2b. If super_admin already existed (e.g. created before this fix), force
-- the rotation flag on regardless - covers deployments that ran this script
-- prior to the fix above and never rotated the default password.
UPDATE `users`
SET force_password_change = 1
WHERE username = 'super_admin';

-- 3. In case super_admin already existed but had wrong role, fix it
UPDATE `users` 
SET role_id = (SELECT role_id FROM roles WHERE role_name='SUPER_ADMIN' LIMIT 1) 
WHERE username = 'super_admin';

-- 4. Ensure existing 'admin' is explicitly set to ADMIN role
UPDATE `users` 
SET role_id = (SELECT role_id FROM roles WHERE role_name='ADMIN' LIMIT 1) 
WHERE username = 'admin';
