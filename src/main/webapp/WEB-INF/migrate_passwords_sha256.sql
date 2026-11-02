-- ============================================================
-- IR-AMS Batch 1 — Password Migration Script
-- Purpose: Hash all existing plain-text passwords to SHA-256
-- Run ONCE against your MySQL database before deploying the
-- updated application. After running, all passwords will be
-- stored as 64-char hex SHA-256 hashes.
--
-- WARNING: This is a one-time irreversible operation.
--   - Take a database backup BEFORE running this script.
--   - Do NOT run this script more than once (it will double-hash already hashed passwords).
--   - After running, all users must log in with their existing plain-text password.
--     LoginServlet will use PasswordUtil.matches() to verify correctly.
-- ============================================================

-- Safety check: show count of plain-text passwords (non 64-hex-char values) before migration
SELECT COUNT(*) AS plaintext_count
FROM users
WHERE LENGTH(password) != 64
   OR password REGEXP '[^0-9a-f]';

-- Migrate all plain-text passwords to SHA-256 hex digest
-- MySQL's SHA2(text, 256) returns the same output as Java's SHA-256 MessageDigest
UPDATE users
SET password = SHA2(password, 256)
WHERE LENGTH(password) != 64
   OR password REGEXP '[^0-9a-f]';

-- Verify: after migration all passwords should be 64 chars
SELECT COUNT(*) AS remaining_plaintext
FROM users
WHERE LENGTH(password) != 64;

-- Show all user accounts (for verification, do NOT share this output)
SELECT user_id, username, email, LENGTH(password) AS pwd_length
FROM users
ORDER BY user_id;
