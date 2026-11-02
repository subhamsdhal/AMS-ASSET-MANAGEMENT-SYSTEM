-- Migration: 004_sync_department_head_column.sql
-- Purpose:
--   One-time backfill for departments.department_head_user_id, which was
--   found to be NULL for every department in the live database despite
--   active DEPARTMENT_HEAD duty assignments existing in
--   employee_role_assignments (the newer, dynamic role-assignment system
--   role_assignment.jsp uses, and what RoleAssignmentDAO.
--   resolveEffectiveRoleForUser() reads to grant the DEPARTMENT_HEAD
--   session role at login).
--
--   department_head_user_id was, until now, only ever written by
--   add_department.jsp/edit_department.jsp's "Department Head" dropdown -
--   a second, disconnected mechanism. Every department-head-scoped query in
--   the app (employees.jsp, EmployeeDAO.isEmployeeUnderDepartmentHead(),
--   MaintenanceRequestDAO, NotificationRecipientResolver,
--   TransferEmployeeServlet, UpdateEmployeeServlet, user_profile_requests.jsp)
--   reads this column, not employee_role_assignments directly - so a
--   department head assigned via role_assignment.jsp logged in with the
--   correct role label but saw zero employees/requests/etc scoped to them.
--
--   RoleAssignmentDAO.assignRoleToEmployee()/deactivateAssignment()/
--   deactivateAllRolesForEmployee() now keep this column in sync going
--   forward (see RoleAssignmentDAO.syncDepartmentHeadColumn()'s doc
--   comment) - this migration is only the one-time catch-up for
--   assignments that already existed before that fix shipped.
--
--   Deliberately does NOT read employee_role_assignments.user_id directly -
--   that column is a snapshot taken when the duty was assigned, and goes
--   stale if the employee's login account is ever recreated (same root
--   cause as the login-role-resolution bug fixed earlier: see
--   RoleAssignmentDAO.getAssignmentsByEmployeeId()'s doc comment).
--   Confirmed live: employee_id=3's active DEPARTMENT_HEAD assignment
--   stores user_id=20, an orphaned id with no matching users row - the
--   employee's real, current account is users.user_id=10400. Always
--   re-resolves the CURRENT user_id via employees/users joined on
--   employee_id instead.
--
-- Run this once against the live AMS database (mysql -u root -p asset_management_system
-- < 004_sync_department_head_column.sql) after deploying the updated app.
-- Idempotent: safe to re-run - each run just recomputes the same "most
-- recently assigned active DEPARTMENT_HEAD duty-holder's current user_id,
-- per department" result from the current state of the database.

UPDATE departments d
JOIN (
    SELECT era.department_id, era.employee_id
    FROM employee_role_assignments era
    INNER JOIN (
        SELECT department_id, MAX(created_at) AS latest_created_at
        FROM employee_role_assignments
        WHERE role_code = 'DEPARTMENT_HEAD' AND assignment_status = 'ACTIVE' AND department_id IS NOT NULL
        GROUP BY department_id
    ) latest ON era.department_id = latest.department_id AND era.created_at = latest.latest_created_at
    WHERE era.role_code = 'DEPARTMENT_HEAD' AND era.assignment_status = 'ACTIVE'
) active_head ON d.department_id = active_head.department_id
-- Two paths to the employee's current user_id, matching
-- RoleAssignmentDAO.resolveUserIdForEmployee()'s exact fallback order:
-- prefer employees.user_id (joined forward to a real users row), fall back
-- to users.employee_id (joined backward) if that's null/unset.
JOIN employees e ON e.employee_id = active_head.employee_id
LEFT JOIN users u_fwd ON u_fwd.user_id = e.user_id
    AND u_fwd.username NOT IN ('super_admin', 'admin', 'assetmgr', 'depthead', 'auditor', 'employee')
LEFT JOIN users u_back ON u_back.employee_id = active_head.employee_id
    AND u_back.username NOT IN ('super_admin', 'admin', 'assetmgr', 'depthead', 'auditor', 'employee')
SET d.department_head_user_id = COALESCE(u_fwd.user_id, u_back.user_id)
WHERE COALESCE(u_fwd.user_id, u_back.user_id) IS NOT NULL;
