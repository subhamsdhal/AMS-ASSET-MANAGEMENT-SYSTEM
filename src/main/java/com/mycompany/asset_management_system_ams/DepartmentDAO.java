package com.mycompany.asset_management_system_ams;

import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.util.ArrayList;
import java.util.List;
import java.util.logging.Level;
import java.util.logging.Logger;

public class DepartmentDAO {

    private static final Logger LOGGER = Logger.getLogger(DepartmentDAO.class.getName());

    public static List<Department> getAllDepartments() {
        List<Department> list = new ArrayList<>();
        String sql = "SELECT d.*, " +
                     "u.username AS head_name, " +
                     "(SELECT COUNT(*) FROM assets a WHERE a.department_id = d.department_id) AS asset_count, " +
                     "(SELECT COUNT(*) FROM employees e WHERE e.department_id = d.department_id) AS employee_count " +
                     "FROM departments d " +
                     "LEFT JOIN users u ON d.department_head_user_id = u.user_id " +
                     "ORDER BY d.department_name ASC";
        
        try (Connection conn = DBConnection.getConnection();
             PreparedStatement ps = conn.prepareStatement(sql);
             ResultSet rs = ps.executeQuery()) {
             
            while (rs.next()) {
                list.add(mapResultSetToDepartment(rs, true));
            }
        } catch (SQLException e) {
            LOGGER.log(Level.SEVERE, "getAllDepartments failed", e);
        }
        return list;
    }

    public static Department getDepartmentById(int departmentId) {
        String sql = "SELECT d.*, u.username AS head_name, " +
                     "(SELECT COUNT(*) FROM assets a WHERE a.department_id = d.department_id) AS asset_count, " +
                     "(SELECT COUNT(*) FROM employees e WHERE e.department_id = d.department_id) AS employee_count " +
                     "FROM departments d " +
                     "LEFT JOIN users u ON d.department_head_user_id = u.user_id " +
                     "WHERE d.department_id = ?";
                     
        try (Connection conn = DBConnection.getConnection();
             PreparedStatement ps = conn.prepareStatement(sql)) {
            ps.setInt(1, departmentId);
            try (ResultSet rs = ps.executeQuery()) {
                if (rs.next()) {
                    return mapResultSetToDepartment(rs, true);
                }
            }
        } catch (SQLException e) {
            LOGGER.log(Level.SEVERE, "getDepartmentById failed", e);
        }
        return null;
    }

    public static boolean isDepartmentCodeExists(String departmentCode, int excludeId) {
        String sql = "SELECT 1 FROM departments WHERE department_code = ? AND department_id != ?";
        try (Connection conn = DBConnection.getConnection();
             PreparedStatement ps = conn.prepareStatement(sql)) {
            ps.setString(1, departmentCode);
            ps.setInt(2, excludeId);
            try (ResultSet rs = ps.executeQuery()) {
                return rs.next();
            }
        } catch (SQLException e) {
            LOGGER.log(Level.SEVERE, "isDepartmentCodeExists failed", e);
        }
        return false;
    }

    public static boolean isDepartmentNameExists(String departmentName, int excludeId) {
        String sql = "SELECT 1 FROM departments WHERE department_name = ? AND department_id != ?";
        try (Connection conn = DBConnection.getConnection();
             PreparedStatement ps = conn.prepareStatement(sql)) {
            ps.setString(1, departmentName);
            ps.setInt(2, excludeId);
            try (ResultSet rs = ps.executeQuery()) {
                return rs.next();
            }
        } catch (SQLException e) {
            LOGGER.log(Level.SEVERE, "isDepartmentNameExists failed", e);
        }
        return false;
    }

    public static boolean addDepartment(Department d) {
        String sql = "INSERT INTO departments (department_code, department_name, description, department_head_user_id, status) VALUES (?, ?, ?, ?, ?)";
        try (Connection conn = DBConnection.getConnection();
             PreparedStatement ps = conn.prepareStatement(sql)) {
            ps.setString(1, d.getDepartmentCode());
            ps.setString(2, d.getDepartmentName());
            ps.setString(3, d.getDescription());
            if (d.getDepartmentHeadUserId() > 0) {
                ps.setInt(4, d.getDepartmentHeadUserId());
            } else {
                ps.setNull(4, java.sql.Types.INTEGER);
            }
            ps.setString(5, d.getStatus());
            
            return ps.executeUpdate() > 0;
        } catch (SQLException e) {
            LOGGER.log(Level.SEVERE, "addDepartment failed", e);
        }
        return false;
    }

    public static boolean updateDepartment(Department d) {
        String sql = "UPDATE departments SET department_code = ?, department_name = ?, description = ?, department_head_user_id = ?, status = ? WHERE department_id = ?";
        try (Connection conn = DBConnection.getConnection();
             PreparedStatement ps = conn.prepareStatement(sql)) {
            ps.setString(1, d.getDepartmentCode());
            ps.setString(2, d.getDepartmentName());
            ps.setString(3, d.getDescription());
            if (d.getDepartmentHeadUserId() > 0) {
                ps.setInt(4, d.getDepartmentHeadUserId());
            } else {
                ps.setNull(4, java.sql.Types.INTEGER);
            }
            ps.setString(5, d.getStatus());
            ps.setInt(6, d.getDepartmentId());
            
            return ps.executeUpdate() > 0;
        } catch (SQLException e) {
            LOGGER.log(Level.SEVERE, "updateDepartment failed", e);
        }
        return false;
    }

    public static boolean deleteDepartment(int departmentId) {
        String sql = "DELETE FROM departments WHERE department_id = ?";
        try (Connection conn = DBConnection.getConnection();
             PreparedStatement ps = conn.prepareStatement(sql)) {
            ps.setInt(1, departmentId);
            return ps.executeUpdate() > 0;
        } catch (SQLException e) {
            LOGGER.log(Level.SEVERE, "deleteDepartment failed", e);
        }
        return false;
    }

    private static Department mapResultSetToDepartment(ResultSet rs, boolean includeExtras) throws SQLException {
        Department d = new Department();
        d.setDepartmentId(rs.getInt("department_id"));
        d.setDepartmentCode(rs.getString("department_code"));
        d.setDepartmentName(rs.getString("department_name"));
        d.setDescription(rs.getString("description"));
        d.setDepartmentHeadUserId(rs.getInt("department_head_user_id"));
        d.setStatus(rs.getString("status"));
        d.setCreatedAt(rs.getTimestamp("created_at"));
        d.setUpdatedAt(rs.getTimestamp("updated_at"));
        
        if (includeExtras) {
            d.setDepartmentHeadName(rs.getString("head_name"));
            d.setAssetCount(rs.getInt("asset_count"));
            d.setEmployeeCount(rs.getInt("employee_count"));
        }
        return d;
    }

    public static class UserSnippet {
        public int userId;
        public String username;
        public String roleName;
    }

    public static List<UserSnippet> getPotentialHeadUsers() {
        List<UserSnippet> list = new ArrayList<>();
        String sql = "SELECT u.user_id, u.username, r.role_name FROM users u JOIN roles r ON u.role_id = r.role_id " +
                     "WHERE r.role_name IN ('SUPER_ADMIN', 'ADMIN', 'DEPARTMENT_HEAD', 'ASSET_MANAGER', 'EMPLOYEE') ORDER BY u.username";
        try (Connection conn = DBConnection.getConnection();
             PreparedStatement ps = conn.prepareStatement(sql);
             ResultSet rs = ps.executeQuery()) {
            while (rs.next()) {
                UserSnippet u = new UserSnippet();
                u.userId = rs.getInt("user_id");
                u.username = rs.getString("username");
                u.roleName = rs.getString("role_name");
                list.add(u);
            }
        } catch (SQLException e) {
            LOGGER.log(Level.SEVERE, "getPotentialHeadUsers failed", e);
        }
        return list;
    }
    // Fault: DeleteDepartmentServlet only ever checked asset_count/employee_count
    // (both already SET NULL or RESTRICT at the DB level) before attempting a
    // real, hard DELETE - but departments.department_id is referenced by five
    // tables total, not two. asset_requests.department_id and
    // railway_locations.department_id are also ON DELETE SET NULL, so a
    // department with old/historical requests or mapped locations - but zero
    // *current* assets/employees - deleted silently, quietly orphaning those
    // records' department reference with no warning. Worse,
    // employee_role_assignments.department_id has NO ACTION (behaves like
    // RESTRICT, but isn't caught by name the way a friendly check would be) -
    // a department still referenced there would make the DELETE throw a raw
    // FK-constraint SQLException, caught generically and surfaced to the admin
    // as a bare "Server error. Please try again." with no indication why.
    // This mirrors EmployeeDAO.getEmployeeDeleteBlockReason() - same pattern,
    // same reasoning - checked against the real, complete set of foreign keys
    // (confirmed via information_schema, not assumed) rather than just the two
    // most obvious ones.
    public static String getDepartmentDeleteBlockReason(int departmentId) {
        Department department = getDepartmentById(departmentId);

        if (department == null) {
            return "Department record not found.";
        }

        if (department.getAssetCount() > 0) {
            return "Department has assets currently assigned to it. Reassign or remove them first.";
        }

        if (department.getEmployeeCount() > 0) {
            return "Department has employees currently assigned to it. Reassign them first.";
        }

        if (getCount("SELECT COUNT(*) FROM employee_role_assignments WHERE department_id = ?", departmentId) > 0) {
            return "Department is referenced by existing role/duty assignment records. Those must be cleared first.";
        }

        if (getCount("SELECT COUNT(*) FROM asset_requests WHERE department_id = ?", departmentId) > 0) {
            return "Department has asset request history linked to it. Historical records must be preserved - disable the department instead of deleting it.";
        }

        if (getCount("SELECT COUNT(*) FROM railway_locations WHERE department_id = ?", departmentId) > 0) {
            return "Department has railway locations mapped to it. Reassign those locations first.";
        }

        return "";
    }

    private static int getCount(String sql, int id) {
        try (Connection conn = DBConnection.getConnection();
             PreparedStatement ps = conn.prepareStatement(sql)) {
            ps.setInt(1, id);
            try (ResultSet rs = ps.executeQuery()) {
                return rs.next() ? rs.getInt(1) : 0;
            }
        } catch (SQLException e) {
            LOGGER.log(Level.SEVERE, "getCount failed", e);
        }
        return 0;
    }

    public static boolean isDepartmentUnderDepartmentHead(int departmentId, int departmentHeadUserId) {
        String sql = "SELECT 1 FROM departments WHERE department_id = ? AND department_head_user_id = ?";
        try (Connection conn = DBConnection.getConnection();
             PreparedStatement ps = conn.prepareStatement(sql)) {
            ps.setInt(1, departmentId);
            ps.setInt(2, departmentHeadUserId);
            try (ResultSet rs = ps.executeQuery()) {
                return rs.next();
            }
        } catch (SQLException e) {
            LOGGER.log(Level.SEVERE, "isDepartmentUnderDepartmentHead failed", e);
        }
        return false;
    }
}
