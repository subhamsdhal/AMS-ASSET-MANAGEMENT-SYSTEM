package com.mycompany.asset_management_system_ams;

import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.util.ArrayList;
import java.util.List;

public class EmployeeDAO {

    public List<Employee> getAllEmployees() {
        List<Employee> employeeList = new ArrayList<>();

        String sql = "SELECT e.employee_id, e.employee_code, e.employee_name, "
                + "e.email, e.phone, e.department_id, d.department_name, e.designation, "
                + "e.joining_date, e.employee_status, e.profile_image_path, "
                + "COUNT(aa.allocation_id) AS assigned_asset_count "
                + "FROM employees e "
                + "LEFT JOIN departments d ON e.department_id = d.department_id "
                + "LEFT JOIN asset_allocation aa ON e.employee_id = aa.employee_id "
                + "AND aa.allocation_status = 'ALLOCATED' "
                + "GROUP BY e.employee_id, e.employee_code, e.employee_name, "
                + "e.email, e.phone, e.department_id, d.department_name, e.designation, e.joining_date, e.employee_status, e.profile_image_path "
                + "ORDER BY e.employee_id ASC";

        try (Connection con = DBConnection.getConnection();
             PreparedStatement ps = con.prepareStatement(sql);
             ResultSet rs = ps.executeQuery()) {

            while (rs.next()) {
                Employee emp = new Employee();
                emp.setEmployeeId(rs.getInt("employee_id"));
                emp.setEmployeeCode(rs.getString("employee_code"));
                emp.setEmployeeName(rs.getString("employee_name"));
                emp.setEmail(rs.getString("email"));
                emp.setPhone(rs.getString("phone"));
                emp.setDepartmentId(rs.getInt("department_id"));
                emp.setDepartmentName(rs.getString("department_name"));
                emp.setDesignation(rs.getString("designation"));
                emp.setJoiningDate(rs.getString("joining_date"));
                emp.setStatus(rs.getString("employee_status"));
                emp.setProfileImagePath(rs.getString("profile_image_path"));
                emp.setAssignedAssetCount(rs.getInt("assigned_asset_count"));

                employeeList.add(emp);
            }
        } catch (Exception e) {
            System.err.println("[EmployeeDAO] getAllEmployees failed: " + e.getMessage());
            e.printStackTrace();
        }

        return employeeList;
    }

    public boolean addEmployee(String employeeCode, String employeeName,
            String email, String phone, int departmentId,
            String designation, String joiningDate, String status) {

        String sql = "INSERT INTO employees "
                + "(employee_code, employee_name, email, phone, department_id, designation, joining_date, employee_status, status) "
                + "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)";

        try (Connection con = DBConnection.getConnection();
             PreparedStatement ps = con.prepareStatement(sql)) {

            ps.setString(1, clean(employeeCode));
            ps.setString(2, clean(employeeName));
            ps.setString(3, clean(email));
            ps.setString(4, clean(phone));
            ps.setInt(5, departmentId);
            ps.setString(6, clean(designation));
            ps.setString(7, emptyToNull(joiningDate));
            ps.setString(8, normalizeEmployeeStatus(status));
            ps.setString(9, normalizeLegacyStatus(status));

            return ps.executeUpdate() > 0;
        } catch (Exception e) {
            System.err.println("[EmployeeDAO] addEmployee failed: " + e.getMessage());
            e.printStackTrace();
        }

        return false;
    }

    public int addEmployeeReturnId(Connection con, String employeeCode, String employeeName,
            String email, String phone, int departmentId,
            String designation, String joiningDate, String status) throws java.sql.SQLException {

        String sql = "INSERT INTO employees "
                + "(employee_code, employee_name, email, phone, department_id, designation, joining_date, employee_status, status) "
                + "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)";

        try (PreparedStatement ps = con.prepareStatement(sql, java.sql.Statement.RETURN_GENERATED_KEYS)) {
            ps.setString(1, clean(employeeCode));
            ps.setString(2, clean(employeeName));
            ps.setString(3, clean(email));
            ps.setString(4, clean(phone));
            ps.setInt(5, departmentId);
            ps.setString(6, clean(designation));
            ps.setString(7, emptyToNull(joiningDate));
            ps.setString(8, normalizeEmployeeStatus(status));
            ps.setString(9, normalizeLegacyStatus(status));

            ps.executeUpdate();
            try (ResultSet rs = ps.getGeneratedKeys()) {
                if (rs.next()) {
                    return rs.getInt(1);
                }
            }
        }
        return -1;
    }

    public Employee getEmployeeById(int employeeId) {
        Employee employee = null;

        String sql = "SELECT e.employee_id, e.employee_code, e.employee_name, e.email, e.phone, "
                + "e.department_id, d.department_name, e.designation, e.joining_date, e.employee_status, e.profile_image_path "
                + "FROM employees e "
                + "LEFT JOIN departments d ON e.department_id = d.department_id "
                + "WHERE e.employee_id = ?";

        try (Connection con = DBConnection.getConnection();
             PreparedStatement ps = con.prepareStatement(sql)) {

            ps.setInt(1, employeeId);

            try (ResultSet rs = ps.executeQuery()) {
                if (rs.next()) {
                    employee = new Employee();
                    employee.setEmployeeId(rs.getInt("employee_id"));
                    employee.setEmployeeCode(rs.getString("employee_code"));
                    employee.setEmployeeName(rs.getString("employee_name"));
                    employee.setEmail(rs.getString("email"));
                    employee.setPhone(rs.getString("phone"));
                    employee.setDepartmentId(rs.getInt("department_id"));
                    employee.setDepartmentName(rs.getString("department_name"));
                    employee.setDesignation(rs.getString("designation"));
                    employee.setJoiningDate(rs.getString("joining_date"));
                    employee.setStatus(rs.getString("employee_status"));
                    employee.setProfileImagePath(rs.getString("profile_image_path"));
                }
            }
        } catch (Exception e) {
            System.err.println("[EmployeeDAO] getEmployeeById failed: " + e.getMessage());
            e.printStackTrace();
        }

        return employee;
    }

    public boolean updateEmployee(int employeeId, String employeeCode,
            String employeeName, String email, String phone,
            int departmentId, String designation,
            String joiningDate, String status) {

        String sql = "UPDATE employees SET "
                + "employee_code = ?, employee_name = ?, email = ?, phone = ?, "
                + "department_id = ?, designation = ?, joining_date = ?, employee_status = ?, status = ? "
                + "WHERE employee_id = ?";

        try (Connection con = DBConnection.getConnection();
             PreparedStatement ps = con.prepareStatement(sql)) {

            ps.setString(1, clean(employeeCode));
            ps.setString(2, clean(employeeName));
            ps.setString(3, clean(email));
            ps.setString(4, clean(phone));
            ps.setInt(5, departmentId);
            ps.setString(6, clean(designation));
            ps.setString(7, emptyToNull(joiningDate));
            ps.setString(8, normalizeEmployeeStatus(status));
            ps.setString(9, normalizeLegacyStatus(status));
            ps.setInt(10, employeeId);

            return ps.executeUpdate() > 0;
        } catch (Exception e) {
            System.err.println("[EmployeeDAO] updateEmployee failed: " + e.getMessage());
            e.printStackTrace();
        }

        return false;
    }

    public boolean disableEmployee(int employeeId) {
        String sql = "UPDATE employees SET employee_status = 'INACTIVE', status = 'INACTIVE' WHERE employee_id = ?";

        try (Connection con = DBConnection.getConnection();
             PreparedStatement ps = con.prepareStatement(sql)) {

            ps.setInt(1, employeeId);
            return ps.executeUpdate() > 0;
        } catch (Exception e) {
            System.err.println("[EmployeeDAO] disableEmployee failed: " + e.getMessage());
            e.printStackTrace();
        }

        return false;
    }

    // Transfer only ever changes department_id - employee_status/status are left
    // untouched (deliberately). A transferred employee is still an active
    // employee, just relocated; they must stay eligible for new allocations in
    // their new department (AssetAllocationDAO.isActiveEmployee() checks
    // employee_status = 'ACTIVE'). The transfer itself is captured as an
    // AuditDAO log entry by the caller, not as a persistent status value.
    public boolean updateEmployeeDepartment(int employeeId, int newDepartmentId) {
        String sql = "UPDATE employees SET department_id = ? WHERE employee_id = ?";

        try (Connection con = DBConnection.getConnection();
             PreparedStatement ps = con.prepareStatement(sql)) {

            ps.setInt(1, newDepartmentId);
            ps.setInt(2, employeeId);
            return ps.executeUpdate() > 0;
        } catch (Exception e) {
            System.err.println("[EmployeeDAO] updateEmployeeDepartment failed: " + e.getMessage());
            e.printStackTrace();
        }

        return false;
    }

    // Unlike disableEmployee(), retirement is a distinct, permanent status -
    // shown as RETIRED everywhere rather than folded into INACTIVE - but still
    // treated as non-active for every existing ACTIVE-only check (new
    // allocations, active-employee counts, etc.), since the legacy `status`
    // column only has ACTIVE/INACTIVE and is set to INACTIVE here.
    public boolean retireEmployee(int employeeId) {
        String sql = "UPDATE employees SET employee_status = 'RETIRED', status = 'INACTIVE' WHERE employee_id = ?";

        try (Connection con = DBConnection.getConnection();
             PreparedStatement ps = con.prepareStatement(sql)) {

            ps.setInt(1, employeeId);
            return ps.executeUpdate() > 0;
        } catch (Exception e) {
            System.err.println("[EmployeeDAO] retireEmployee failed: " + e.getMessage());
            e.printStackTrace();
        }

        return false;
    }

    public boolean isEmployeeUnderDepartmentHead(int employeeId, int departmentHeadUserId) {
        String sql = "SELECT COUNT(*) AS total "
                + "FROM employees e "
                + "JOIN departments d ON e.department_id = d.department_id "
                + "WHERE e.employee_id = ? AND d.department_head_user_id = ?";

        return getCount(sql, employeeId, departmentHeadUserId) > 0;
    }

    public String getDepartmentHeadEmailByEmployeeId(int employeeId) {
        String email = "";

        String sql = "SELECT u.email "
                + "FROM employees e "
                + "JOIN departments d ON e.department_id = d.department_id "
                + "JOIN users u ON d.department_head_user_id = u.user_id "
                + "WHERE e.employee_id = ? "
                + "LIMIT 1";

        try (Connection con = DBConnection.getConnection();
             PreparedStatement ps = con.prepareStatement(sql)) {

            ps.setInt(1, employeeId);

            try (ResultSet rs = ps.executeQuery()) {
                if (rs.next()) {
                    email = safe(rs.getString("email"));
                }
            }
        } catch (Exception e) {
            System.err.println("[EmployeeDAO] getDepartmentHeadEmailByEmployeeId failed: " + e.getMessage());
            e.printStackTrace();
        }

        if (email.trim().isEmpty()) {
            email = NotificationHelper.getEmailByRoleName("DEPARTMENT_HEAD");
        }

        return email;
    }

    public String getEmployeeDeleteBlockReason(int employeeId) {
        Employee employee = getEmployeeById(employeeId);

        if (employee == null) {
            return "Employee record not found.";
        }

        if ("ACTIVE".equalsIgnoreCase(employee.getStatus())) {
            return "Active employee records cannot be deleted. Deactivate the employee first.";
        }

        int activeAllocationCount = getCount(
                "SELECT COUNT(*) FROM asset_allocation WHERE employee_id = ? AND allocation_status = 'ALLOCATED'",
                employeeId
        );

        if (activeAllocationCount > 0) {
            return "Employee has active asset allocation records. Return all allocated assets first.";
        }

        int activeRequestCount = getCount(
                "SELECT COUNT(*) FROM asset_requests WHERE employee_id = ? AND request_status IN ('PENDING', 'APPROVED')",
                employeeId
        );

        if (activeRequestCount > 0) {
            return "Employee has pending or approved asset request records. Close those requests first.";
        }

        return "";
    }

    // Fault (Medium, fixed): this accepted deletedByUserId/deleteReason but never
    // referenced either, and never touched is_deleted/deleted_at/deleted_by/
    // delete_reason - the dedicated soft-delete columns the schema (and this
    // method's own name) exist specifically for. "Deleting" an employee was
    // functionally identical to disabling them a second time - no row was ever
    // distinguishably marked deleted vs. merely deactivated, and other code
    // (getAssignableEmployeesForDropdown, AddAssetRequestServlet) that filters on
    // is_deleted=0 to make exactly that distinction could never actually see it.
    // See audit/09-employees.md Finding 1.
    public boolean deleteEmployeePermanently(int employeeId, int deletedByUserId, String deleteReason) {
        String sql = "UPDATE employees SET employee_status = 'INACTIVE', status = 'INACTIVE', "
                + "is_deleted = 1, deleted_at = NOW(), deleted_by = ?, delete_reason = ? "
                + "WHERE employee_id = ? AND employee_status <> 'ACTIVE'";

        try (Connection con = DBConnection.getConnection();
             PreparedStatement ps = con.prepareStatement(sql)) {

            if (deletedByUserId > 0) {
                ps.setInt(1, deletedByUserId);
            } else {
                ps.setNull(1, java.sql.Types.INTEGER);
            }
            ps.setString(2, deleteReason);
            ps.setInt(3, employeeId);
            return ps.executeUpdate() > 0;
        } catch (Exception e) {
            System.err.println("[EmployeeDAO] deleteEmployeePermanently failed: " + e.getMessage());
            e.printStackTrace();
        }

        return false;
    }

    private int getCount(String sql, int value) {
        return getCount(sql, value, null);
    }

    private int getCount(String sql, int value1, Integer value2) {
        int count = 0;

        try (Connection con = DBConnection.getConnection();
             PreparedStatement ps = con.prepareStatement(sql)) {

            ps.setInt(1, value1);
            if (value2 != null) {
                ps.setInt(2, value2);
            }

            try (ResultSet rs = ps.executeQuery()) {
                if (rs.next()) {
                    count = rs.getInt(1);
                }
            }
        } catch (Exception e) {
            // Fault: copy-pasted from a neighboring method - this is the generic
            // getCount() helper shared by isEmployeeUnderDepartmentHead() and
            // getEmployeeDeleteBlockReason()'s two count queries, none of which
            // are deleteEmployeePermanently() - logged the wrong (and, for two
            // of the three callers, actively misleading) method name on failure.
            System.err.println("[EmployeeDAO] getCount failed: " + e.getMessage());
            e.printStackTrace();
        }

        return count;
    }

    private String normalizeEmployeeStatus(String status) {
        String value = clean(status).toUpperCase();
        if ("INACTIVE".equals(value) || "TRANSFERRED".equals(value) || "RETIRED".equals(value)) {
            return value;
        }
        return "ACTIVE";
    }

    private String normalizeLegacyStatus(String status) {
        String value = normalizeEmployeeStatus(status);
        return "ACTIVE".equals(value) ? "ACTIVE" : "INACTIVE";
    }

    private String emptyToNull(String value) {
        String text = clean(value);
        return text.isEmpty() ? null : text;
    }

    private String clean(String value) {
        return value == null ? "" : value.trim();
    }

    private String safe(String status) {
        return status == null || status.trim().isEmpty() ? null : status.trim();
    }

    public boolean updateEmployeeProfileImage(int employeeId, String profileImagePath) {
        String sql = "UPDATE employees SET profile_image_path = ? WHERE employee_id = ?";
        try (Connection con = DBConnection.getConnection();
             PreparedStatement ps = con.prepareStatement(sql)) {
            ps.setString(1, profileImagePath);
            ps.setInt(2, employeeId);
            return ps.executeUpdate() > 0;
        } catch (Exception e) {
            System.err.println("[EmployeeDAO] updateEmployeeProfileImage failed: " + e.getMessage());
            e.printStackTrace();
        }
        return false;
    }


    public int getEmployeeIdByUserId(int userId) {
        String sql = "SELECT employee_id FROM employees WHERE user_id = ?";
        try (Connection con = DBConnection.getConnection();
             PreparedStatement ps = con.prepareStatement(sql)) {
            ps.setInt(1, userId);
            try (ResultSet rs = ps.executeQuery()) {
                if (rs.next()) {
                    return rs.getInt("employee_id");
                }
            }
        } catch (Exception e) {
            System.err.println("[EmployeeDAO] getEmployeeIdByUserId failed: " + e.getMessage());
            e.printStackTrace();
        }
        return -1;
    }

    public List<java.util.Map<String, String>> getEmployeesByDepartmentId(int departmentId) {
        List<java.util.Map<String, String>> empList = new ArrayList<>();
        String listSql = "SELECT employee_id, employee_code, employee_name, designation, email, phone, employee_status FROM employees WHERE department_id = ? ORDER BY employee_name ASC";
        try (Connection con = DBConnection.getConnection();
             PreparedStatement ps = con.prepareStatement(listSql)) {
            ps.setInt(1, departmentId);
            try (ResultSet rs = ps.executeQuery()) {
                while (rs.next()) {
                    java.util.Map<String, String> emp = new java.util.HashMap<>();
                    emp.put("employee_id", rs.getString("employee_id"));
                    emp.put("employee_code", rs.getString("employee_code"));
                    emp.put("employee_name", rs.getString("employee_name"));
                    emp.put("designation", rs.getString("designation"));
                    emp.put("email", rs.getString("email"));
                    emp.put("phone", rs.getString("phone"));
                    emp.put("status", rs.getString("employee_status"));
                    empList.add(emp);
                }
            }
        } catch (Exception e) {
            System.err.println("[EmployeeDAO] getEmployeesByDepartmentId failed: " + e.getMessage());
            e.printStackTrace();
        }
        return empList;
    }
}
