-- Migration: adds users.role_id, referenced but never created.
--
-- audit/01-auth-session.md's P0 finding: ~13 call sites across this codebase
-- (LoginServlet, GenerateEmployeeLoginServlet, AuditDAO, RoleAssignmentDAO,
-- DepartmentDAO, NotificationHelper/NotificationRecipientResolver,
-- TransferEmployeeServlet, UpdateEmployeeServlet, AddEmployeeServlet, and
-- both seed/setup SQL scripts) read or write users.role_id and JOIN it
-- against roles.role_id, but this column was missing from schema.sql - a
-- fresh install built strictly from that file would fail every one of those
-- call sites (most swallowed into a silently-wrong default by a try/catch,
-- GenerateEmployeeLoginServlet's INSERT hitting a hard 500).
--
-- schema.sql itself has since been corrected to define this column for
-- FRESH installs (see its own users table definition and the fk_users_role
-- constraint added right after). This migration is that same fix for an
-- ALREADY-DEPLOYED database that was built from schema.sql before this was
-- added - confirmed live against this project's own database that the
-- column and its foreign key already exist there, so this file exists for
-- any OTHER deployment schema.sql's own comment already promised it to.
--
-- current_role (the enum column) remains the actual authorization source -
-- RoleAuthorizationFilter/RoleAccessUtil key off it, not role_id. role_id
-- exists only so the application's own `roles` lookup-table joins resolve,
-- and is kept in sync with current_role by the application layer (see
-- UpdateUserRoleServlet, RoleAssignmentDAO) - nullable, no default, so this
-- can be added to a table with existing rows before any backfill runs.

ALTER TABLE users
  ADD COLUMN role_id INT DEFAULT NULL,
  ADD KEY idx_users_role_id (role_id);

ALTER TABLE users
  ADD CONSTRAINT fk_users_role FOREIGN KEY (role_id) REFERENCES roles (role_id)
  ON DELETE SET NULL ON UPDATE CASCADE;

-- Optional, one-time backfill: sets role_id from current_role for every
-- existing user, so joins against `roles` resolve correctly immediately
-- rather than only for users touched after this migration runs. Safe to run
-- repeatedly - only ever affects rows where role_id is still NULL.
--
-- Uses an explicit CASE, not a plain `roles.role_name = users.current_role`
-- join: confirmed live against this project's own database that this is not
-- just a case-sensitivity concern (utf8mb4_unicode_ci already handles
-- that) - `current_role`'s enum literal is `dept_head`, but `roles.role_name`
-- for that same role is spelled `DEPARTMENT_HEAD`, a genuinely different
-- string. A naive join silently fails to resolve role_id for every real
-- department head account, which is exactly what had happened here before
-- this was traced to its root cause (see RoleIdResolver.java).
UPDATE users u
  JOIN roles r ON r.role_name = (
    CASE u.current_role
      WHEN 'dept_head' THEN 'DEPARTMENT_HEAD'
      ELSE UPPER(u.current_role)
    END
  )
  SET u.role_id = r.role_id
  WHERE u.role_id IS NULL;
