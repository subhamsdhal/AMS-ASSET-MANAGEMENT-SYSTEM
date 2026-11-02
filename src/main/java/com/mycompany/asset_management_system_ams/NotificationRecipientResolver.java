package com.mycompany.asset_management_system_ams;

import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.util.ArrayList;
import java.util.List;

public class NotificationRecipientResolver {

    /**
     * Resolves all active emails for a given role by joining users and employees.
     */
    public static List<String> getEmailsByRole(String roleName) {
        List<String> emails = new ArrayList<>();
        String sql = "SELECT e.email "
                + "FROM users u "
                + "JOIN roles r ON u.role_id = r.role_id "
                + "JOIN employees e ON u.employee_id = e.employee_id "
                + "WHERE r.role_name = ? "
                + "AND u.status = 'ACTIVE' "
                + "AND e.employee_status = 'ACTIVE' "
                + "AND e.email IS NOT NULL "
                + "AND e.email <> '' "
                + "ORDER BY u.user_id ASC";

        try (Connection con = DBConnection.getConnection();
             PreparedStatement ps = con.prepareStatement(sql)) {
            ps.setString(1, roleName.trim());
            try (ResultSet rs = ps.executeQuery()) {
                while (rs.next()) {
                    emails.add(rs.getString("email").trim());
                }
            }
        } catch (Exception e) {
            System.err.println("Error resolving emails for role " + roleName + ": " + e.getMessage());
        }
        return emails;
    }

    /**
     * Returns the first active email for a given role.
     */
    public static String getPrimaryEmailByRole(String roleName) {
        List<String> emails = getEmailsByRole(roleName);
        if (emails != null && !emails.isEmpty()) {
            return emails.get(0);
        }
        return "";
    }

    /**
     * Returns the linked employee email for a specific employee ID.
     */
    public static String getEmployeeEmailByEmployeeId(int employeeId) {
        if (employeeId <= 0) return "";
        String sql = "SELECT email FROM employees WHERE employee_id = ? AND employee_status = 'ACTIVE' AND email IS NOT NULL AND email <> ''";
        try (Connection con = DBConnection.getConnection();
             PreparedStatement ps = con.prepareStatement(sql)) {
            ps.setInt(1, employeeId);
            try (ResultSet rs = ps.executeQuery()) {
                if (rs.next()) {
                    return rs.getString("email").trim();
                }
            }
        } catch (Exception e) {
            System.err.println("Error resolving email for employee " + employeeId + ": " + e.getMessage());
        }
        return "";
    }

    /**
     * Returns the linked employee email for a specific user ID.
     */
    public static String getEmployeeEmailByUserId(int userId) {
        if (userId <= 0) return "";
        String sql = "SELECT e.email "
                + "FROM users u "
                + "JOIN employees e ON u.employee_id = e.employee_id "
                + "WHERE u.user_id = ? AND u.status = 'ACTIVE' AND e.employee_status = 'ACTIVE' AND e.email IS NOT NULL AND e.email <> ''";
        try (Connection con = DBConnection.getConnection();
             PreparedStatement ps = con.prepareStatement(sql)) {
            ps.setInt(1, userId);
            try (ResultSet rs = ps.executeQuery()) {
                if (rs.next()) {
                    return rs.getString("email").trim();
                }
            }
        } catch (Exception e) {
            System.err.println("Error resolving email for user " + userId + ": " + e.getMessage());
        }
        return "";
    }

    /**
     * Returns the linked employee name for a specific employee ID.
     */
    public static String getRecipientNameByEmployeeId(int employeeId) {
        if (employeeId <= 0) return "Officer";
        String sql = "SELECT employee_name FROM employees WHERE employee_id = ?";
        try (Connection con = DBConnection.getConnection();
             PreparedStatement ps = con.prepareStatement(sql)) {
            ps.setInt(1, employeeId);
            try (ResultSet rs = ps.executeQuery()) {
                if (rs.next()) {
                    String name = rs.getString("employee_name");
                    return name != null && !name.trim().isEmpty() ? name.trim() : "Officer";
                }
            }
        } catch (Exception e) {
            System.err.println("Error resolving name for employee " + employeeId + ": " + e.getMessage());
        }
        return "Officer";
    }

    /**
     * Returns the department head email for a specific department ID.
     */
    public static String getDepartmentHeadEmailByDepartmentId(int departmentId) {
        if (departmentId <= 0) return "";
        String sql = "SELECT department_head_user_id FROM departments WHERE department_id = ? AND status = 'ACTIVE'";
        try (Connection con = DBConnection.getConnection();
             PreparedStatement ps = con.prepareStatement(sql)) {
            ps.setInt(1, departmentId);
            try (ResultSet rs = ps.executeQuery()) {
                if (rs.next()) {
                    int headUserId = rs.getInt("department_head_user_id");
                    if (headUserId > 0) {
                        return getEmployeeEmailByUserId(headUserId);
                    }
                }
            }
        } catch (Exception e) {
            System.err.println("Error resolving department head email for department " + departmentId + ": " + e.getMessage());
        }
        return "";
    }

    /**
     * Returns the department head email for a specific employee ID by looking up their department.
     */
    public static String getDepartmentHeadEmailByEmployeeId(int employeeId) {
        if (employeeId <= 0) return "";
        String sql = "SELECT department_id FROM employees WHERE employee_id = ?";
        try (Connection con = DBConnection.getConnection();
             PreparedStatement ps = con.prepareStatement(sql)) {
            ps.setInt(1, employeeId);
            try (ResultSet rs = ps.executeQuery()) {
                if (rs.next()) {
                    int departmentId = rs.getInt("department_id");
                    if (departmentId > 0) {
                        return getDepartmentHeadEmailByDepartmentId(departmentId);
                    }
                }
            }
        } catch (Exception e) {
            System.err.println("Error resolving department head email for employee " + employeeId + ": " + e.getMessage());
        }
        return "";
    }

    /**
     * Returns the department head email for a specific asset ID by looking up its assigned department.
     */
    public static String getDepartmentHeadEmailByAssetId(int assetId) {
        if (assetId <= 0) return "";
        String sql = "SELECT department_id FROM assets WHERE asset_id = ?";
        try (Connection con = DBConnection.getConnection();
             PreparedStatement ps = con.prepareStatement(sql)) {
            ps.setInt(1, assetId);
            try (ResultSet rs = ps.executeQuery()) {
                if (rs.next()) {
                    int departmentId = rs.getInt("department_id");
                    if (departmentId > 0) {
                        return getDepartmentHeadEmailByDepartmentId(departmentId);
                    }
                }
            }
        } catch (Exception e) {
            System.err.println("Error resolving department head email for asset " + assetId + ": " + e.getMessage());
        }
        return "";
    }
}
