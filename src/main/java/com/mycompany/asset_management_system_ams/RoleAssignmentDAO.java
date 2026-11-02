package com.mycompany.asset_management_system_ams;

import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.sql.Statement;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Arrays;
import java.util.HashSet;
import java.util.Set;

public class RoleAssignmentDAO {

    // Fault (Critical, fixed): every "protected account" check in this class
    // used to rely solely on this username list - fragile, because it stops
    // protecting the real account the moment it's renamed, or the moment a
    // second account legitimately holds the same role under a different
    // username (nothing in the schema prevents either). SUPER_ADMIN and
    // ADMIN specifically are now identified by their actual current_role
    // wherever it matters (see each method below), matching the same
    // role-based protection already used in UpdateUserRoleServlet and in
    // this class's own deactivateAssignment()/isLastActiveAdmin(). This
    // username list is kept only as the identity signal for the four
    // remaining seed/reference accounts (assetmgr/depthead/auditor/
    // employee) - those roles are legitimately held by real employees too,
    // so they must stay identified by which specific account they are, not
    // by role, unlike SUPER_ADMIN/ADMIN.
    public static final List<String> PROTECTED_ACCOUNTS = Arrays.asList("super_admin", "admin", "assetmgr", "depthead", "auditor", "employee");

    public static List<Map<String, Object>> getActiveAssignments(Integer departmentIdScope) {
        List<Map<String, Object>> assignments = new ArrayList<>();
        String sql = "SELECT a.assignment_id, a.employee_id, a.user_id, a.role_code, a.department_id, "
                + "e.designation AS designation, a.effective_from, a.effective_to, a.remarks, a.assigned_by_user_id, "
                + "e.employee_code, e.employee_name, emp_dept.department_name AS department_name "
                + "FROM employee_role_assignments a "
                + "JOIN employees e ON a.employee_id = e.employee_id "
                + "LEFT JOIN departments emp_dept ON e.department_id = emp_dept.department_id "
                + "LEFT JOIN departments role_dept ON a.department_id = role_dept.department_id "
                + "LEFT JOIN users u ON a.employee_id = u.employee_id "
                + "WHERE a.assignment_status = 'ACTIVE' "
                + "AND (u.username IS NULL OR u.username NOT IN ('super_admin', 'admin', 'assetmgr', 'depthead', 'auditor', 'employee')) "
                + "AND (u.current_role IS NULL OR u.current_role NOT IN ('super_admin', 'admin')) ";
        if (departmentIdScope != null) {
            sql += " AND e.department_id = ? ";
        }
        sql += "ORDER BY a.role_code, emp_dept.department_name, e.employee_name";
        try (Connection con = DBConnection.getConnection();
             PreparedStatement ps = con.prepareStatement(sql)) {
            if (departmentIdScope != null) {
                ps.setInt(1, departmentIdScope);
            }
            try (ResultSet rs = ps.executeQuery()) {
                while (rs.next()) {
                    assignments.add(mapAssignment(rs));
                }
            }
        } catch (Exception e) {
            e.printStackTrace();
        }
        return assignments;
    }

    public static List<Map<String, Object>> getAssignmentHistory(Integer departmentIdScope) {
        List<Map<String, Object>> assignments = new ArrayList<>();
        String sql = "SELECT a.assignment_id, a.employee_id, a.user_id, a.role_code, a.department_id, "
                + "e.designation AS designation, a.effective_from, a.effective_to, a.remarks, a.assigned_by_user_id, "
                + "a.assignment_status, e.employee_code, e.employee_name, emp_dept.department_name AS department_name "
                + "FROM employee_role_assignments a "
                + "JOIN employees e ON a.employee_id = e.employee_id "
                + "LEFT JOIN departments emp_dept ON e.department_id = emp_dept.department_id "
                + "LEFT JOIN departments role_dept ON a.department_id = role_dept.department_id ";
        if (departmentIdScope != null) {
            sql += " WHERE e.department_id = ? ";
        }
        sql += "ORDER BY a.created_at DESC";
        try (Connection con = DBConnection.getConnection();
             PreparedStatement ps = con.prepareStatement(sql)) {
            if (departmentIdScope != null) {
                ps.setInt(1, departmentIdScope);
            }
            try (ResultSet rs = ps.executeQuery()) {
                while (rs.next()) {
                    Map<String, Object> map = mapAssignment(rs);
                    map.put("assignment_status", rs.getString("assignment_status"));
                    assignments.add(map);
                }
            }
        } catch (Exception e) {
            e.printStackTrace();
        }
        return assignments;
    }

    public static List<Map<String, Object>> getAssignmentsByUserId(int userId) {
        List<Map<String, Object>> assignments = new ArrayList<>();
        String sql = "SELECT * FROM employee_role_assignments "
                + "WHERE user_id = ? AND assignment_status = 'ACTIVE'";
        try (Connection con = DBConnection.getConnection();
             PreparedStatement ps = con.prepareStatement(sql)) {
            ps.setInt(1, userId);
            try (ResultSet rs = ps.executeQuery()) {
                while (rs.next()) {
                    Map<String, Object> map = new HashMap<>();
                    map.put("assignment_id", rs.getInt("assignment_id"));
                    map.put("role_code", rs.getString("role_code"));
                    map.put("department_id", rs.getObject("department_id"));
                    map.put("designation_title", rs.getString("designation_title"));
                    assignments.add(map);
                }
            }
        } catch (Exception e) {
            e.printStackTrace();
        }
        return assignments;
    }

    // Fault (Critical): resolveEffectiveRoleForUser() below used to look up
    // active duty assignments via getAssignmentsByUserId(userId), keyed on
    // employee_role_assignments.user_id - a snapshot of the user account id
    // taken at the moment the assignment was created (see
    // assignRoleToEmployee()'s resolveUserIdForEmployee() call). If that
    // employee's user account is ever recreated/re-seeded (getting a new
    // auto-increment user_id) while the employee record and the assignment
    // itself are untouched, the assignment's stored user_id goes stale and
    // silently stops matching - getAssignmentsByUserId() then returns empty,
    // and resolveEffectiveRoleForUser() falls back to plain "EMPLOYEE" even
    // though users.current_role and an ACTIVE employee_role_assignments row
    // both say otherwise. Confirmed live: emp002 (users.current_role =
    // 'asset_manager', an ACTIVE ASSET_MANAGER duty on employee_id=2) was
    // silently logged in as EMPLOYEE on every login because its
    // employee_role_assignments row still referenced a stale user_id=19
    // while the live users row is user_id=10399 - a real account, not a
    // seed-script leftover, permanently losing its actual role every single
    // login with zero visible error. employee_id doesn't have this failure
    // mode (it's the assignment's actual stable subject, unlike the snapshot
    // user_id), so look up by that instead.
    public static List<Map<String, Object>> getAssignmentsByEmployeeId(int employeeId) {
        List<Map<String, Object>> assignments = new ArrayList<>();
        String sql = "SELECT * FROM employee_role_assignments "
                + "WHERE employee_id = ? AND assignment_status = 'ACTIVE'";
        try (Connection con = DBConnection.getConnection();
             PreparedStatement ps = con.prepareStatement(sql)) {
            ps.setInt(1, employeeId);
            try (ResultSet rs = ps.executeQuery()) {
                while (rs.next()) {
                    Map<String, Object> map = new HashMap<>();
                    map.put("assignment_id", rs.getInt("assignment_id"));
                    map.put("role_code", rs.getString("role_code"));
                    map.put("department_id", rs.getObject("department_id"));
                    map.put("designation_title", rs.getString("designation_title"));
                    assignments.add(map);
                }
            }
        } catch (Exception e) {
            e.printStackTrace();
        }
        return assignments;
    }

    public static boolean assignRoleToEmployee(int employeeId, String roleCode, Integer departmentId, String designationTitle, int assignedBy, String remarks) throws Exception {
        if (!isValidRole(roleCode)) {
            throw new Exception("Invalid role code");
        }

        if ("SUPER_ADMIN".equals(roleCode)) {
            throw new Exception("SUPER_ADMIN role cannot be assigned dynamically.");
        }

        Connection con = null;
        try {
            con = DBConnection.getConnection();
            con.setAutoCommit(false);

            // Fault (see syncDepartmentHeadColumn()'s doc comment): capture which
            // department(s), if any, this employee currently heads BEFORE step 1.8
            // deactivates that duty below - needed so those departments'
            // departments.department_head_user_id can be recomputed afterward
            // (e.g. an employee moved from heading Dept A to Dept B should leave
            // Dept A's column pointing at whoever else heads it, or NULL, not
            // stale pointing at this employee).
            Set<Integer> previousHeadedDepartmentIds = new HashSet<>();
            String previousHeadSql = "SELECT department_id FROM employee_role_assignments "
                    + "WHERE employee_id = ? AND role_code = 'DEPARTMENT_HEAD' AND assignment_status = 'ACTIVE' AND department_id IS NOT NULL";
            try (PreparedStatement ps = con.prepareStatement(previousHeadSql)) {
                ps.setInt(1, employeeId);
                try (ResultSet rs = ps.executeQuery()) {
                    while (rs.next()) {
                        previousHeadedDepartmentIds.add(rs.getInt("department_id"));
                    }
                }
            }

            // 1. Check for duplicates
            if (!"EMPLOYEE".equals(roleCode)) {
                if (isDuplicateActiveAssignment(con, employeeId, roleCode, departmentId)) {
                    throw new Exception("This employee already has an active assignment for this role and department.");
                }
            }

            // 1.5 Handle ADMIN uniqueness
            if ("ADMIN".equals(roleCode)) {
                List<Integer> oldAdminAssignmentIds = new ArrayList<>();
                String findOldAdminSql = "SELECT a.assignment_id FROM employee_role_assignments a "
                        + "JOIN users u ON a.employee_id = u.employee_id "
                        + "WHERE a.role_code = 'ADMIN' AND a.assignment_status = 'ACTIVE' "
                        + "AND u.username NOT IN ('super_admin', 'admin', 'assetmgr', 'depthead', 'auditor', 'employee') "
                        + "AND u.current_role NOT IN ('super_admin', 'admin')";
                try (PreparedStatement ps = con.prepareStatement(findOldAdminSql);
                     ResultSet rs = ps.executeQuery()) {
                    while (rs.next()) {
                        oldAdminAssignmentIds.add(rs.getInt("assignment_id"));
                    }
                }
                
                if (!oldAdminAssignmentIds.isEmpty()) {
                    String updateSql = "UPDATE employee_role_assignments SET assignment_status = 'INACTIVE', effective_to = CURRENT_DATE, remarks = CONCAT(IFNULL(remarks,''), ' [Replaced by new Admin duty assigned to another employee]') WHERE assignment_id = ?";
                    try (PreparedStatement psUpdate = con.prepareStatement(updateSql)) {
                        for (Integer oldId : oldAdminAssignmentIds) {
                            psUpdate.setInt(1, oldId);
                            psUpdate.executeUpdate();
                            AuditDAO.log(assignedBy, "ROLE_DUTY_ASSIGNMENT", "employee_role_assignments", oldId, "Old dynamic ADMIN duty deactivated because new ADMIN duty was assigned.");
                        }
                    }
                }
            }
            
            // 1.8 Deactivate any existing active elevated duty for the target employee
            String deactivateTargetSql = "UPDATE employee_role_assignments SET assignment_status = 'INACTIVE', effective_to = CURRENT_DATE, remarks = CONCAT(IFNULL(remarks,''), ' [Deactivated due to new role assignment]') WHERE employee_id = ? AND assignment_status = 'ACTIVE'";
            try (PreparedStatement psDeactivate = con.prepareStatement(deactivateTargetSql)) {
                psDeactivate.setInt(1, employeeId);
                int rows = psDeactivate.executeUpdate();
                if (rows > 0) {
                    AuditDAO.log(assignedBy, "ROLE_DUTY_ASSIGNMENT", "employee_role_assignments", employeeId, "Deactivated " + rows + " old active duty for employee before assigning new role " + roleCode);
                }
            }

            // 2. Resolve user_id mapping
            Integer userId = resolveUserIdForEmployee(con, employeeId);
            if (userId == null) {
                throw new Exception("Employee has no login user account linked. Please create a user account first.");
            }

            // 3. Insert assignment
            if (!"EMPLOYEE".equals(roleCode)) {
                String sql = "INSERT INTO employee_role_assignments (employee_id, user_id, role_code, department_id, designation_title, assigned_by_user_id, remarks) "
                        + "VALUES (?, ?, ?, ?, ?, ?, ?)";
                try (PreparedStatement ps = con.prepareStatement(sql)) {
                    ps.setInt(1, employeeId);
                    ps.setInt(2, userId);
                    ps.setString(3, roleCode);
                    if (departmentId != null) {
                        ps.setInt(4, departmentId);
                    } else {
                        ps.setNull(4, java.sql.Types.INTEGER);
                    }
                    ps.setString(5, designationTitle);
                    ps.setInt(6, assignedBy);
                    ps.setString(7, remarks);
                    ps.executeUpdate();
                    
                    try (PreparedStatement lastIdPs = con.prepareStatement("SELECT LAST_INSERT_ID()")) {
                        try (ResultSet rsId = lastIdPs.executeQuery()) {
                            if (rsId.next()) {
                                int newId = rsId.getInt(1);
                                AuditDAO.log(assignedBy, "ROLE_DUTY_ASSIGNMENT", "employee_role_assignments", newId, "Assigned new dynamic duty " + roleCode + " to employee " + employeeId);
                            }
                        }
                    }
                }
            } else {
                AuditDAO.log(assignedBy, "ROLE_DUTY_ASSIGNMENT", "employee_role_assignments", employeeId, "Reset employee " + employeeId + " to standard Employee role (removed elevated duties).");
            }
            
            // 4. Update employee designation officially in employees table
            if (designationTitle != null && !designationTitle.trim().isEmpty()) {
                String updateDesignation = "UPDATE employees SET designation = ? WHERE employee_id = ?";
                try (PreparedStatement ps2 = con.prepareStatement(updateDesignation)) {
                    ps2.setString(1, designationTitle);
                    ps2.setInt(2, employeeId);
                    ps2.executeUpdate();
                }
            }

            // 5. Keep departments.department_head_user_id in sync with this
            // change - see syncDepartmentHeadColumn()'s doc comment for why.
            if ("DEPARTMENT_HEAD".equals(roleCode) && departmentId != null) {
                previousHeadedDepartmentIds.remove(departmentId);
                syncDepartmentHeadColumn(con, departmentId);
            }
            for (Integer oldDeptId : previousHeadedDepartmentIds) {
                syncDepartmentHeadColumn(con, oldDeptId);
            }

            con.commit();
            return true;
        } catch (Exception e) {
            if (con != null) {
                con.rollback();
            }
            throw e;
        } finally {
            if (con != null) {
                con.setAutoCommit(true);
                con.close();
            }
        }
    }

    public static boolean deactivateAssignment(int assignmentId, int performedBy) throws Exception {
        Connection con = null;
        try {
            con = DBConnection.getConnection();
            con.setAutoCommit(false);

            // Fetch assignment details to check for Super Admin protection
            String roleCode = null;
            Integer userId = null;
            Integer departmentId = null;
            String sqlCheck = "SELECT role_code, user_id, department_id FROM employee_role_assignments WHERE assignment_id = ?";
            try (PreparedStatement ps = con.prepareStatement(sqlCheck)) {
                ps.setInt(1, assignmentId);
                try (ResultSet rs = ps.executeQuery()) {
                    if (rs.next()) {
                        roleCode = rs.getString("role_code");
                        userId = (Integer) rs.getObject("user_id");
                        departmentId = (Integer) rs.getObject("department_id");
                    }
                }
            }

            if ("SUPER_ADMIN".equals(roleCode) || "ADMIN".equals(roleCode)) {
                if (isLastActiveAdmin(con, userId)) {
                    throw new Exception("Cannot deactivate the last active SUPER_ADMIN/ADMIN.");
                }
            }

            // AND assignment_status = 'ACTIVE' makes this idempotent: if two
            // different people (e.g. an Admin and the relevant Department Head)
            // both submit "Deactivate" on the exact same assignment_id at close
            // to the same time, only the first one actually flips the status and
            // logs an audit entry - the second is a harmless no-op (0 rows
            // affected) instead of re-appending a duplicate "[Deactivated by
            // user X]" remark and a duplicate audit-log line for a state change
            // that already happened.
            String sql = "UPDATE employee_role_assignments SET assignment_status = 'INACTIVE', effective_to = CURRENT_DATE, remarks = CONCAT(IFNULL(remarks,''), ' [Deactivated by user ', ?, ']') WHERE assignment_id = ? AND assignment_status = 'ACTIVE'";
            int rowsUpdated;
            try (PreparedStatement ps = con.prepareStatement(sql)) {
                ps.setInt(1, performedBy);
                ps.setInt(2, assignmentId);
                rowsUpdated = ps.executeUpdate();
            }

            // Keep departments.department_head_user_id in sync - see
            // syncDepartmentHeadColumn()'s doc comment.
            if (rowsUpdated > 0 && "DEPARTMENT_HEAD".equals(roleCode) && departmentId != null) {
                syncDepartmentHeadColumn(con, departmentId);
            }

            con.commit();
            return rowsUpdated > 0;
        } catch (Exception e) {
            if (con != null) {
                con.rollback();
            }
            throw e;
        } finally {
            if (con != null) {
                con.setAutoCommit(true);
                con.close();
            }
        }
    }

    private static boolean isDuplicateActiveAssignment(Connection con, int employeeId, String roleCode, Integer departmentId) throws SQLException {
        String sql = "SELECT COUNT(*) FROM employee_role_assignments WHERE employee_id = ? AND role_code = ? AND assignment_status = 'ACTIVE'";
        if (departmentId != null) {
            sql += " AND department_id = ?";
        } else {
            sql += " AND department_id IS NULL";
        }
        
        try (PreparedStatement ps = con.prepareStatement(sql)) {
            ps.setInt(1, employeeId);
            ps.setString(2, roleCode);
            if (departmentId != null) {
                ps.setInt(3, departmentId);
            }
            try (ResultSet rs = ps.executeQuery()) {
                if (rs.next()) {
                    return rs.getInt(1) > 0;
                }
            }
        }
        return false;
    }

    /**
     * Fault: departments.department_head_user_id (a single-value column set
     * only via add_department.jsp/edit_department.jsp's "Department Head"
     * dropdown) and employee_role_assignments (the dynamic duty system this
     * class manages - what role_assignment.jsp actually uses, and what
     * resolveEffectiveRoleForUser() reads to grant the DEPARTMENT_HEAD
     * session role at login) were two entirely disconnected mechanisms -
     * assigning a DEPARTMENT_HEAD duty here never touched that column.
     * Confirmed live: department_head_user_id was NULL for every department
     * in the database despite active dynamic DEPARTMENT_HEAD assignments
     * existing, because nothing had ever written to it going that direction.
     * Effect: every department-head-scoped query in the app that reads
     * department_head_user_id (employees.jsp, EmployeeDAO.
     * isEmployeeUnderDepartmentHead(), MaintenanceRequestDAO,
     * NotificationRecipientResolver, TransferEmployeeServlet,
     * UpdateEmployeeServlet, and now user_profile_requests.jsp) saw zero
     * scoped employees/requests for a department head assigned through this
     * class - the role label was correct, but everything actually scoped by
     * it silently wasn't.
     *
     * Fix: called after every assign/deactivate that touches a
     * DEPARTMENT_HEAD duty, so department_head_user_id is recomputed from
     * whatever's now the most-recently-assigned active DEPARTMENT_HEAD
     * duty-holder for that department. employee_role_assignments can support
     * multiple concurrent department heads per department (see
     * getDepartmentHeadsByDepartmentId(), which returns a List); this single
     * column structurally cannot represent that, so "most recent active
     * assignment wins" is a deliberate, pragmatic best-effort bridge between
     * the two systems - not a full reconciliation of two different data
     * models, which would be a much larger change.
     */
    private static void syncDepartmentHeadColumn(Connection con, int departmentId) throws SQLException {
        Integer headEmployeeId = null;
        String sql = "SELECT employee_id FROM employee_role_assignments "
                + "WHERE department_id = ? AND role_code = 'DEPARTMENT_HEAD' AND assignment_status = 'ACTIVE' "
                + "ORDER BY created_at DESC LIMIT 1";
        try (PreparedStatement ps = con.prepareStatement(sql)) {
            ps.setInt(1, departmentId);
            try (ResultSet rs = ps.executeQuery()) {
                if (rs.next()) {
                    headEmployeeId = rs.getInt("employee_id");
                }
            }
        }

        // Fault: this used to read employee_role_assignments.user_id directly -
        // the same stale-snapshot column resolveEffectiveRoleForUser() was
        // fixed to stop trusting earlier this session (see
        // getAssignmentsByEmployeeId()'s doc comment). Confirmed live: the
        // active DEPARTMENT_HEAD assignment for department_id=10 stores
        // user_id=20, an orphaned id with no matching users row (the FK from
        // departments.department_head_user_id to users.user_id rejected it
        // outright) - the employee's actual current user_id is 10399+. Always
        // re-resolve the CURRENT user_id from employee_id instead of trusting
        // the assignment row's stored snapshot.
        Integer headUserId = headEmployeeId != null ? resolveUserIdForEmployee(con, headEmployeeId) : null;

        String updateSql = "UPDATE departments SET department_head_user_id = ? WHERE department_id = ?";
        try (PreparedStatement ps = con.prepareStatement(updateSql)) {
            if (headUserId != null) {
                ps.setInt(1, headUserId);
            } else {
                ps.setNull(1, java.sql.Types.INTEGER);
            }
            ps.setInt(2, departmentId);
            ps.executeUpdate();
        }
    }

    private static Integer resolveUserIdForEmployee(Connection con, int employeeId) throws SQLException {
        // According to schema, employees table has user_id and users table has employee_id.
        // We will check employees first, then users, but always exclude protected reference accounts.
        // Excludes both by username (the four non-singleton seed accounts)
        // and by current_role (SUPER_ADMIN/ADMIN, regardless of which
        // username holds them) - see the class-level PROTECTED_ACCOUNTS
        // comment for why the two need different identification.
        String sql1 = "SELECT e.user_id FROM employees e JOIN users u ON e.user_id = u.user_id "
                + "WHERE e.employee_id = ? AND u.username NOT IN ('super_admin', 'admin', 'assetmgr', 'depthead', 'auditor', 'employee') "
                + "AND u.current_role NOT IN ('super_admin', 'admin')";
        try (PreparedStatement ps = con.prepareStatement(sql1)) {
            ps.setInt(1, employeeId);
            try (ResultSet rs = ps.executeQuery()) {
                if (rs.next()) {
                    return rs.getInt("user_id");
                }
            }
        }

        String sql2 = "SELECT user_id FROM users WHERE employee_id = ? "
                + "AND username NOT IN ('super_admin', 'admin', 'assetmgr', 'depthead', 'auditor', 'employee') "
                + "AND current_role NOT IN ('super_admin', 'admin')";
        try (PreparedStatement ps = con.prepareStatement(sql2)) {
            ps.setInt(1, employeeId);
            try (ResultSet rs = ps.executeQuery()) {
                if (rs.next()) {
                    return rs.getInt("user_id");
                }
            }
        }
        return null;
    }

    private static boolean isLastActiveAdmin(Connection con, Integer excludingUserId) throws SQLException {
        // Count ACTIVE SUPER_ADMIN/ADMIN in roles + dynamic assignments
        int count = 0;
        
        // Count from employee_role_assignments
        String sqlDynamic = "SELECT COUNT(DISTINCT user_id) FROM employee_role_assignments "
                + "WHERE role_code IN ('SUPER_ADMIN', 'ADMIN') AND assignment_status = 'ACTIVE' "
                + "AND user_id != ?";
        try (PreparedStatement ps = con.prepareStatement(sqlDynamic)) {
            ps.setInt(1, excludingUserId != null ? excludingUserId : -1);
            try (ResultSet rs = ps.executeQuery()) {
                if (rs.next()) {
                    count += rs.getInt(1);
                }
            }
        }
        
        if (count > 0) return false;
        
        // Count from users table fallback (users with role_id for SUPER_ADMIN/ADMIN)
        // Assume roles table has SUPER_ADMIN/ADMIN
        String sqlStatic = "SELECT COUNT(u.user_id) FROM users u "
                + "JOIN roles r ON u.role_id = r.role_id "
                + "WHERE r.role_name IN ('SUPER_ADMIN', 'ADMIN') AND u.status = 'ACTIVE' "
                + "AND u.user_id != ?";
        try (PreparedStatement ps = con.prepareStatement(sqlStatic)) {
            ps.setInt(1, excludingUserId != null ? excludingUserId : -1);
            try (ResultSet rs = ps.executeQuery()) {
                if (rs.next()) {
                    count += rs.getInt(1);
                }
            }
        }
        
        return count == 0;
    }

    private static boolean isValidRole(String role) {
        String[] allowed = {"SUPER_ADMIN", "ADMIN", "ASSET_MANAGER", "DEPARTMENT_HEAD", "AUDITOR", "EMPLOYEE"};
        for (String r : allowed) {
            if (r.equals(role)) return true;
        }
        return false;
    }

    private static Map<String, Object> mapAssignment(ResultSet rs) throws SQLException {
        Map<String, Object> map = new HashMap<>();
        map.put("assignment_id", rs.getInt("assignment_id"));
        map.put("employee_id", rs.getInt("employee_id"));
        map.put("user_id", rs.getObject("user_id"));
        map.put("role_code", rs.getString("role_code"));
        map.put("department_id", rs.getObject("department_id"));
        
        // Use designation instead of designation_title
        String designation = null;
        try { designation = rs.getString("designation"); } catch (Exception ignore) {}
        if (designation == null) {
            try { designation = rs.getString("designation_title"); } catch (Exception ignore) {}
        }
        map.put("designation", designation);
        map.put("effective_from", rs.getDate("effective_from"));
        map.put("effective_to", rs.getDate("effective_to"));
        map.put("remarks", rs.getString("remarks"));
        map.put("assigned_by_user_id", rs.getInt("assigned_by_user_id"));
        map.put("employee_code", rs.getString("employee_code"));
        map.put("employee_name", rs.getString("employee_name"));
        map.put("department_name", rs.getString("department_name"));
        return map;
    }

    public static Map<Integer, String> getActiveDutySummaryForEmployees() {
        Map<Integer, String> summary = new HashMap<>();
        // Fault: this was "r.role_code" - the roles table has no such column
        // (it's role_name; role_code only exists on the different
        // employee_role_assignments table, aliased era below). Every call threw
        // a SQLSyntaxErrorException, silently caught wherever this method's
        // result was consumed, so employees.jsp rendered but with every
        // employee's "base role" / duty summary silently blank.
        String sql = "SELECT e.employee_id, " +
                     "r.role_name as base_role, " +
                     "era.role_code as dynamic_role, " +
                     "d.department_name " +
                     "FROM employees e " +
                     "LEFT JOIN users u ON e.employee_id = u.employee_id " +
                     "      AND u.username NOT IN ('super_admin', 'admin', 'assetmgr', 'depthead', 'auditor', 'employee') " +
                     "      AND u.current_role NOT IN ('super_admin', 'admin') " +
                     "LEFT JOIN roles r ON u.role_id = r.role_id " +
                     "LEFT JOIN employee_role_assignments era ON e.employee_id = era.employee_id " +
                     "      AND era.assignment_status = 'ACTIVE' " +
                     "      AND (era.effective_to IS NULL OR era.effective_to >= CURDATE()) " +
                     "LEFT JOIN departments d ON era.department_id = d.department_id " +
                     "WHERE e.status = 'ACTIVE' " +
                     "ORDER BY e.employee_id, era.role_code";
                     
        try (Connection con = DBConnection.getConnection();
             PreparedStatement ps = con.prepareStatement(sql);
             ResultSet rs = ps.executeQuery()) {
             
            Map<Integer, List<String>> dynamicRolesMap = new HashMap<>();
            Map<Integer, String> baseRoleMap = new HashMap<>();
            Set<Integer> allEmpIds = new HashSet<>();
             
            while (rs.next()) {
                int empId = rs.getInt("employee_id");
                allEmpIds.add(empId);
                String dynamicRole = rs.getString("dynamic_role");
                String deptName = rs.getString("department_name");
                String baseRole = rs.getString("base_role");
                
                if (baseRole != null && !baseRoleMap.containsKey(empId)) {
                    baseRoleMap.put(empId, baseRole);
                }
                
                if (dynamicRole != null) {
                    dynamicRolesMap.putIfAbsent(empId, new ArrayList<>());
                    String display = getTitleCaseRole(dynamicRole);
                    if ("DEPARTMENT_HEAD".equals(dynamicRole) && deptName != null) {
                        display += " - " + deptName;
                    }
                    if (!dynamicRolesMap.get(empId).contains(display)) {
                        dynamicRolesMap.get(empId).add(display);
                    }
                }
            }
            
            for (Integer empId : allEmpIds) {
                if (dynamicRolesMap.containsKey(empId) && !dynamicRolesMap.get(empId).isEmpty()) {
                    summary.put(empId, String.join(", ", dynamicRolesMap.get(empId)));
                } else {
                    String bRole = baseRoleMap.get(empId);
                    if (bRole != null && isValidRole(bRole)) {
                        summary.put(empId, getTitleCaseRole(bRole));
                    } else {
                        summary.put(empId, "Employee");
                    }
                }
            }
        } catch (Exception e) {
            e.printStackTrace();
        }
        return summary;
    }
    
    private static String getTitleCaseRole(String roleCode) {
        if ("ADMIN".equals(roleCode)) return "Admin";
        if ("SUPER_ADMIN".equals(roleCode) || "ADMIN".equals(roleCode)) return "Super Admin";
        if ("ASSET_MANAGER".equals(roleCode)) return "Asset Manager";
        if ("DEPARTMENT_HEAD".equals(roleCode)) return "Department Head";
        if ("AUDITOR".equals(roleCode)) return "Auditor";
        return "Employee";
    }

    public static List<Map<String, String>> getActiveRolesByEmployeeId(int employeeId) {
        List<Map<String, String>> roles = new ArrayList<>();
        String sql = "SELECT era.role_code, era.designation_title, era.department_id, d.department_name, era.effective_from " +
                     "FROM employee_role_assignments era " +
                     "LEFT JOIN departments d ON era.department_id = d.department_id " +
                     "WHERE era.employee_id = ? AND era.assignment_status = 'ACTIVE' " +
                     "AND (era.effective_to IS NULL OR era.effective_to >= CURDATE()) " +
                     "ORDER BY era.role_code";
                     
        try (Connection con = DBConnection.getConnection();
             PreparedStatement ps = con.prepareStatement(sql)) {
            ps.setInt(1, employeeId);
            try (ResultSet rs = ps.executeQuery()) {
                while (rs.next()) {
                    Map<String, String> roleMap = new HashMap<>();
                    roleMap.put("role_code", rs.getString("role_code"));
                    roleMap.put("department_name", rs.getString("department_name"));
                    roleMap.put("designation_title", rs.getString("designation_title"));
                    
                    java.sql.Date date = rs.getDate("effective_from");
                    roleMap.put("effective_from", date != null ? date.toString() : "");
                    
                    roles.add(roleMap);
                }
            }
        } catch (Exception e) {
            e.printStackTrace();
        }
        return roles;
    }

    public static List<String> getDepartmentHeadsByDepartmentId(int departmentId) {
        List<String> heads = new ArrayList<>();
        String sql = "SELECT e.employee_name " +
                     "FROM employee_role_assignments era " +
                     "JOIN employees e ON era.employee_id = e.employee_id " +
                     "WHERE era.department_id = ? AND era.role_code = 'DEPARTMENT_HEAD' " +
                     "AND era.assignment_status = 'ACTIVE' " +
                     "AND (era.effective_to IS NULL OR era.effective_to >= CURDATE())";
                     
        try (Connection con = DBConnection.getConnection();
             PreparedStatement ps = con.prepareStatement(sql)) {
            ps.setInt(1, departmentId);
            try (ResultSet rs = ps.executeQuery()) {
                while (rs.next()) {
                    heads.add(rs.getString("employee_name"));
                }
            }
        } catch (Exception e) {
            e.printStackTrace();
        }
        return heads;
    }

    public static boolean deactivateAllRolesForEmployee(int employeeId, int performedBy) throws Exception {
        Connection con = null;
        try {
            con = DBConnection.getConnection();
            con.setAutoCommit(false);

            // Check if user is trying to deactivate the last SUPER_ADMIN
            Integer userId = resolveUserIdForEmployee(con, employeeId);
            if (userId != null) {
                // Check if they have an active ADMIN/SUPER_ADMIN role
                String checkSql = "SELECT COUNT(*) FROM employee_role_assignments WHERE employee_id = ? AND role_code IN ('SUPER_ADMIN', 'ADMIN') AND assignment_status = 'ACTIVE'";
                try (PreparedStatement ps = con.prepareStatement(checkSql)) {
                    ps.setInt(1, employeeId);
                    try (ResultSet rs = ps.executeQuery()) {
                        if (rs.next() && rs.getInt(1) > 0) {
                            if (isLastActiveAdmin(con, userId)) {
                                throw new Exception("Cannot deactivate roles. This employee is the last active SUPER_ADMIN/ADMIN in the system.");
                            }
                        }
                    }
                }
            }

            // Keep departments.department_head_user_id in sync - see
            // syncDepartmentHeadColumn()'s doc comment. Captured before the
            // deactivation below flips assignment_status away from ACTIVE.
            Set<Integer> headedDepartmentIds = new HashSet<>();
            String headedSql = "SELECT department_id FROM employee_role_assignments "
                    + "WHERE employee_id = ? AND role_code = 'DEPARTMENT_HEAD' AND assignment_status = 'ACTIVE' AND department_id IS NOT NULL";
            try (PreparedStatement ps = con.prepareStatement(headedSql)) {
                ps.setInt(1, employeeId);
                try (ResultSet rs = ps.executeQuery()) {
                    while (rs.next()) {
                        headedDepartmentIds.add(rs.getInt("department_id"));
                    }
                }
            }

            String sql = "UPDATE employee_role_assignments SET assignment_status = 'INACTIVE', effective_to = CURRENT_DATE, remarks = CONCAT(IFNULL(remarks,''), ' [Reset to EMPLOYEE by user ', ?, ']') WHERE employee_id = ? AND assignment_status = 'ACTIVE'";
            try (PreparedStatement ps = con.prepareStatement(sql)) {
                ps.setInt(1, performedBy);
                ps.setInt(2, employeeId);
                ps.executeUpdate();
            }

            for (Integer deptId : headedDepartmentIds) {
                syncDepartmentHeadColumn(con, deptId);
            }

            con.commit();
            return true;
        } catch (Exception e) {
            if (con != null) {
                con.rollback();
            }
            throw e;
        } finally {
            if (con != null) {
                con.setAutoCommit(true);
                con.close();
            }
        }
    }

    public static boolean isEmployeeProtected(int employeeId) {
        // Protected if EITHER signal fires: the account is one of the four
        // named seed/reference accounts, OR it currently holds SUPER_ADMIN/
        // ADMIN (checked by role so this can't be bypassed by renaming that
        // account or seeding a second one under a different username - see
        // the class-level PROTECTED_ACCOUNTS comment).
        String sql = "SELECT 1 FROM users WHERE employee_id = ? "
                + "AND (username IN ('super_admin', 'admin', 'assetmgr', 'depthead', 'auditor', 'employee') "
                + "     OR current_role IN ('super_admin', 'admin'))";
        try (Connection con = DBConnection.getConnection();
             PreparedStatement ps = con.prepareStatement(sql)) {
            ps.setInt(1, employeeId);
            try (ResultSet rs = ps.executeQuery()) {
                if (rs.next()) return true;
            }
        } catch (Exception e) {
            e.printStackTrace();
        }
        return false;
    }
    
    public static boolean isAssignmentForProtected(int assignmentId) {
        // Same OR'd role-or-username protection as isEmployeeProtected() above.
        String sql = "SELECT 1 FROM employee_role_assignments era JOIN users u ON era.user_id = u.user_id "
                + "WHERE era.assignment_id = ? "
                + "AND (u.username IN ('super_admin', 'admin', 'assetmgr', 'depthead', 'auditor', 'employee') "
                + "     OR u.current_role IN ('super_admin', 'admin'))";
        try (Connection con = DBConnection.getConnection();
             PreparedStatement ps = con.prepareStatement(sql)) {
            ps.setInt(1, assignmentId);
            try (ResultSet rs = ps.executeQuery()) {
                if (rs.next()) return true;
            }
        } catch (Exception e) {
            e.printStackTrace();
        }
        return false;
    }
    public static java.util.Map<String, Object> resolveEffectiveRoleForUser(String username, int userId, Integer employeeId, String loggedRole) {
        java.util.Map<String, Object> result = new java.util.HashMap<>();
        java.util.List<String> activeRoles = new java.util.ArrayList<>();
        java.util.List<Integer> departmentIds = new java.util.ArrayList<>();
        String primaryRole = "EMPLOYEE";

        String normalizedLoggedRole = loggedRole == null ? "" : loggedRole.trim().toUpperCase(java.util.Locale.ENGLISH);

        // Fault (Critical, fixed): SUPER_ADMIN/ADMIN used to be recognized
        // here only via the literal username "super_admin" or membership in
        // PROTECTED_ACCOUNTS - both username-based. That protects the real
        // Super Admin/Admin only as long as those accounts keep those exact
        // usernames; rename either, or seed a second account with
        // current_role='super_admin'/'admin' under a different username
        // (nothing in the schema prevents it), and this method fell through
        // to the dynamic-duty lookup below for them instead. Since SUPER_ADMIN
        // is never dynamically assignable and ADMIN is a managed singleton
        // (see assignRoleToEmployee()), that lookup finds no
        // employee_role_assignments row for them and silently resolves their
        // session role to plain EMPLOYEE on every login - a real account
        // permanently losing its actual privilege with zero visible error.
        // Checking current_role directly closes that gap and matches the
        // same role-based (not username-based) protection already used in
        // UpdateUserRoleServlet and in this class's own
        // deactivateAssignment()/isLastActiveAdmin().
        if ("SUPER_ADMIN".equals(normalizedLoggedRole) || "ADMIN".equals(normalizedLoggedRole)) {
            primaryRole = loggedRole;
            activeRoles.add(loggedRole);
        } else if (PROTECTED_ACCOUNTS.contains(username)) {
            // Preserve original/reference role behavior for the remaining
            // seed accounts (assetmgr/depthead/auditor/employee) - identified
            // by username, not role, since ASSET_MANAGER/DEPARTMENT_HEAD/
            // AUDITOR/EMPLOYEE are legitimately held by real employees too
            // and must not be blanket role-matched the way SUPER_ADMIN/ADMIN
            // are above.
            primaryRole = loggedRole;
            activeRoles.add(loggedRole);
        } else {
            // Fix: look up by employeeId, not userId - see getAssignmentsByEmployeeId()'s
            // doc comment for why the userId-keyed lookup silently drops real accounts.
            java.util.List<java.util.Map<String, Object>> assignments =
                    employeeId != null ? getAssignmentsByEmployeeId(employeeId) : getAssignmentsByUserId(userId);

            if (assignments != null && !assignments.isEmpty()) {
                for (java.util.Map<String, Object> map : assignments) {
                    String rCode = (String) map.get("role_code");
                    if (rCode != null && !activeRoles.contains(rCode)) {
                        activeRoles.add(rCode);
                    }
                    if ("DEPARTMENT_HEAD".equals(rCode) && map.get("department_id") != null) {
                        departmentIds.add((Integer) map.get("department_id"));
                    }
                }
                
                String[] priority = {"ADMIN", "ASSET_MANAGER", "DEPARTMENT_HEAD", "AUDITOR", "EMPLOYEE"};
                for (String p : priority) {
                    if (activeRoles.contains(p)) {
                        primaryRole = p;
                        break;
                    }
                }
            } else {
                // Fallback to standard employee if no active elevated duty exists
                primaryRole = "EMPLOYEE";
                activeRoles.add("EMPLOYEE");
            }
        }
        
        result.put("role", primaryRole);
        result.put("roles", activeRoles);
        result.put("departmentIds", departmentIds);
        return result;
    }

    public static List<Map<String, Object>> getAssignableEmployeesForDropdown(Integer departmentIdScope) {
        List<Map<String, Object>> list = new ArrayList<>();
        String sql = "SELECT e.employee_id, e.employee_code, e.employee_name, e.designation, "
                + "u.user_id, u.username, era.role_code AS current_role_code, "
                + "era.department_id, d.department_name "
                + "FROM employees e " +
                     "LEFT JOIN users u ON u.employee_id = e.employee_id " +
                     "   AND u.username REGEXP '^emp[0-9]+$' " +
                     "   AND u.username NOT IN ('super_admin','admin','assetmgr','depthead','auditor','employee') " +
                     "LEFT JOIN employee_role_assignments era ON era.employee_id = e.employee_id " +
                     "   AND era.assignment_status = 'ACTIVE' " +
                     "LEFT JOIN departments d ON era.department_id = d.department_id " +
                     "WHERE e.is_deleted = 0 "
                     + "  AND e.status = 'ACTIVE' ";
        if (departmentIdScope != null) {
            sql += "  AND e.department_id = ? ";
        }
        sql += "ORDER BY e.employee_code";
                     
        try (Connection con = DBConnection.getConnection();
             PreparedStatement ps = con.prepareStatement(sql)) {
            if (departmentIdScope != null) {
                ps.setInt(1, departmentIdScope);
            }
            try (ResultSet rs = ps.executeQuery()) {
             
                while (rs.next()) {
                Map<String, Object> map = new HashMap<>();
                map.put("employee_id", rs.getInt("employee_id"));
                map.put("employee_code", rs.getString("employee_code"));
                map.put("employee_name", rs.getString("employee_name"));
                String designation = rs.getString("designation");
                map.put("designation", designation == null || designation.trim().isEmpty() ? "N/A" : designation);
                
                String roleCode = rs.getString("current_role_code");
                String deptName = rs.getString("department_name");
                
                String currentRoleLabel = "Employee";
                if (roleCode != null) {
                    if ("ADMIN".equals(roleCode) || "SUPER_ADMIN".equals(roleCode)) {
                        currentRoleLabel = "Admin";
                    } else if ("ASSET_MANAGER".equals(roleCode)) {
                        currentRoleLabel = "Asset Manager";
                    } else if ("DEPARTMENT_HEAD".equals(roleCode)) {
                        currentRoleLabel = "Department Head";
                        if (deptName != null) {
                            currentRoleLabel += " - " + deptName;
                        }
                    } else if ("AUDITOR".equals(roleCode)) {
                        currentRoleLabel = "Auditor";
                    }
                }
                map.put("current_role_label", currentRoleLabel);
                map.put("has_login", rs.getObject("user_id") != null);

                list.add(map);
                }
            }
        } catch (Exception e) {
            e.printStackTrace();
        }
        return list;
    }
}

