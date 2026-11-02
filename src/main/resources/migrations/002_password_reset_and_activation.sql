-- Migration: 002_password_reset_and_activation.sql
-- Purpose:
--   1. Add the token table backing the new "Forgot password?" email-reset
--      flow and the "Sign up" self-activation flow (both reuse the same
--      table; token_type distinguishes them).
--   2. Redact any plaintext passwords already sitting in users.password_plaintext
--      as part of closing the Login-2 finding in CHANGELOG-fixes.md. The column
--      itself is left in place (still NOT NULL) because it is still written to
--      (as an empty string) by AddEmployeeServlet, ChangePasswordServlet and
--      GenerateEmployeeLoginServlet; dropping it outright is a separate,
--      larger change left for a follow-up once nothing else references it.
--
-- Run this once against the live AMS database (mysql -u root -p asset_management_system
-- < 002_password_reset_and_activation.sql) before deploying the updated app.
-- Idempotent: safe to re-run.

CREATE TABLE IF NOT EXISTS password_reset_tokens (
  token_id      INT AUTO_INCREMENT PRIMARY KEY,
  user_id       INT NOT NULL,
  token_hash    VARCHAR(128) NOT NULL,
  token_type    ENUM('RESET','ACTIVATION') NOT NULL DEFAULT 'RESET',
  expires_at    TIMESTAMP NOT NULL,
  used_at       TIMESTAMP NULL DEFAULT NULL,
  requested_ip  VARCHAR(100) NULL,
  created_at    TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY uk_prt_token_hash (token_hash),
  KEY idx_prt_user (user_id),
  KEY idx_prt_user_type_time (user_id, token_type, created_at),
  CONSTRAINT fk_prt_user FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

UPDATE users
SET password_plaintext = ''
WHERE password_plaintext IS NOT NULL AND password_plaintext <> '';
