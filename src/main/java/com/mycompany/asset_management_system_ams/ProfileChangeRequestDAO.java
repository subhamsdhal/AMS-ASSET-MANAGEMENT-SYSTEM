package com.mycompany.asset_management_system_ams;

import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.HashSet;
import java.util.List;
import java.util.Set;
import java.util.logging.Level;
import java.util.logging.Logger;

/**
 * ProfileChangeRequestDAO - reads and writes profile_change_requests, the
 * employee-initiated / admin-approved profile field change workflow.
 *
 * Deliberately whitelisted to a small, fixed set of self-service-appropriate
 * fields (email, phone) rather than an arbitrary column name - name,
 * designation, and department stay administrator-only edits, matching how
 * the rest of this app already separates "employee can request" from
 * "admin decides" (compare: employee_returns.jsp submits a return request,
 * an admin/asset-manager approves it - same shape of workflow, applied here
 * to profile fields instead of asset returns).
 */
public class ProfileChangeRequestDAO {

    private static final Logger LOGGER = Logger.getLogger(ProfileChangeRequestDAO.class.getName());
    private static volatile boolean tableEnsured = false;

    public static final Set<String> ALLOWED_FIELDS = new HashSet<>(Arrays.asList("email", "phone"));

    private static void ensureTable(Connection con) {
        if (tableEnsured) {
            return;
        }
        String sql = "CREATE TABLE IF NOT EXISTS profile_change_requests ("
                + "request_id INT AUTO_INCREMENT PRIMARY KEY, "
                + "employee_id INT NOT NULL, "
                + "field_name VARCHAR(30) NOT NULL, "
                + "current_value VARCHAR(255) DEFAULT NULL, "
                + "requested_value VARCHAR(255) NOT NULL, "
                + "reason VARCHAR(500) DEFAULT NULL, "
                + "status ENUM('PENDING','APPROVED','REJECTED') NOT NULL DEFAULT 'PENDING', "
                + "reviewed_by INT DEFAULT NULL, "
                + "review_note VARCHAR(500) DEFAULT NULL, "
                + "created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP, "
                + "reviewed_at TIMESTAMP NULL DEFAULT NULL, "
                + "KEY idx_profile_change_requests_employee (employee_id), "
                + "KEY idx_profile_change_requests_status (status)"
                + ") ENGINE=InnoDB DEFAULT CHARSET=utf8mb4";
        try (PreparedStatement ps = con.prepareStatement(sql)) {
            ps.executeUpdate();
            tableEnsured = true;
        } catch (Exception e) {
            LOGGER.log(Level.WARNING, "Unable to ensure profile_change_requests table exists", e);
        }
    }

    /** True if this employee already has a PENDING request for this field - blocks duplicate spam submissions. */
    public boolean hasPendingRequest(int employeeId, String fieldName) {
        String sql = "SELECT COUNT(*) FROM profile_change_requests WHERE employee_id = ? AND field_name = ? AND status = 'PENDING'";
        try (Connection con = DBConnection.getConnection();
             PreparedStatement ps = con.prepareStatement(sql)) {
            ensureTable(con);
            ps.setInt(1, employeeId);
            ps.setString(2, fieldName);
            try (ResultSet rs = ps.executeQuery()) {
                return rs.next() && rs.getInt(1) > 0;
            }
        } catch (Exception e) {
            LOGGER.log(Level.WARNING, "hasPendingRequest failed", e);
            return false;
        }
    }

    public boolean submitRequest(int employeeId, String fieldName, String currentValue, String requestedValue, String reason) {
        if (!ALLOWED_FIELDS.contains(fieldName)) {
            return false;
        }
        String sql = "INSERT INTO profile_change_requests "
                + "(employee_id, field_name, current_value, requested_value, reason) "
                + "VALUES (?, ?, ?, ?, ?)";
        try (Connection con = DBConnection.getConnection();
             PreparedStatement ps = con.prepareStatement(sql)) {
            ensureTable(con);
            ps.setInt(1, employeeId);
            ps.setString(2, fieldName);
            ps.setString(3, currentValue == null ? "" : currentValue);
            ps.setString(4, requestedValue);
            ps.setString(5, reason == null ? "" : reason);
            return ps.executeUpdate() > 0;
        } catch (Exception e) {
            LOGGER.log(Level.WARNING, "submitRequest failed for employee " + employeeId, e);
            return false;
        }
    }

    public List<ProfileChangeRequest> listForEmployee(int employeeId) {
        return listWhere("pcr.employee_id = ?", employeeId, null);
    }

    /** status may be null/"ALL" for every request, or PENDING/APPROVED/REJECTED. */
    public List<ProfileChangeRequest> listByStatus(String status) {
        if (status == null || status.isEmpty() || "ALL".equalsIgnoreCase(status)) {
            return listWhere(null, 0, null);
        }
        return listWhere("pcr.status = ?", 0, status.toUpperCase());
    }

    private List<ProfileChangeRequest> listWhere(String whereClause, int employeeIdParam, String statusParam) {
        List<ProfileChangeRequest> list = new ArrayList<>();

        String sql = "SELECT pcr.request_id, pcr.employee_id, e.employee_code, e.employee_name, "
                + "pcr.field_name, pcr.current_value, pcr.requested_value, pcr.reason, pcr.status, "
                + "COALESCE(u.username, '') AS reviewed_by_username, pcr.review_note, "
                + "pcr.created_at, pcr.reviewed_at, d.department_name "
                + "FROM profile_change_requests pcr "
                + "JOIN employees e ON pcr.employee_id = e.employee_id "
                + "LEFT JOIN departments d ON e.department_id = d.department_id "
                + "LEFT JOIN users u ON pcr.reviewed_by = u.user_id "
                + (whereClause != null ? "WHERE " + whereClause + " " : "")
                + "ORDER BY pcr.created_at DESC, pcr.request_id DESC";

        try (Connection con = DBConnection.getConnection();
             PreparedStatement ps = con.prepareStatement(sql)) {
            ensureTable(con);

            int paramIndex = 1;
            if (whereClause != null && whereClause.contains("employee_id")) {
                ps.setInt(paramIndex++, employeeIdParam);
            } else if (whereClause != null && whereClause.contains("status")) {
                ps.setString(paramIndex++, statusParam);
            }

            try (ResultSet rs = ps.executeQuery()) {
                while (rs.next()) {
                    ProfileChangeRequest req = new ProfileChangeRequest();
                    req.setRequestId(rs.getInt("request_id"));
                    req.setEmployeeId(rs.getInt("employee_id"));
                    req.setEmployeeCode(rs.getString("employee_code"));
                    req.setEmployeeName(rs.getString("employee_name"));
                    req.setFieldName(rs.getString("field_name"));
                    req.setCurrentValue(rs.getString("current_value"));
                    req.setRequestedValue(rs.getString("requested_value"));
                    req.setReason(rs.getString("reason"));
                    req.setStatus(rs.getString("status"));
                    req.setReviewedByUsername(rs.getString("reviewed_by_username"));
                    req.setReviewNote(rs.getString("review_note"));
                    req.setCreatedAt(rs.getString("created_at"));
                    req.setReviewedAt(rs.getString("reviewed_at"));
                    req.setDepartmentName(rs.getString("department_name"));
                    list.add(req);
                }
            }
        } catch (Exception e) {
            LOGGER.log(Level.WARNING, "listWhere failed", e);
        }

        return list;
    }

    /**
     * The employee_id a pending request belongs to, or null if the request
     * doesn't exist. Used by ReviewProfileChangeRequestServlet to check a
     * DEPARTMENT_HEAD reviewer's scope before approving/rejecting - the JSP
     * only lists requests already filtered to the reviewer's own department,
     * but that's a display-layer filter, not an authorization boundary; a
     * DEPARTMENT_HEAD could otherwise POST an arbitrary requestId for an
     * employee outside their department directly to the servlet.
     */
    public Integer getEmployeeIdForRequest(int requestId) {
        String sql = "SELECT employee_id FROM profile_change_requests WHERE request_id = ?";
        try (Connection con = DBConnection.getConnection();
             PreparedStatement ps = con.prepareStatement(sql)) {
            ensureTable(con);
            ps.setInt(1, requestId);
            try (ResultSet rs = ps.executeQuery()) {
                return rs.next() ? rs.getInt("employee_id") : null;
            }
        } catch (Exception e) {
            LOGGER.log(Level.WARNING, "getEmployeeIdForRequest failed for request " + requestId, e);
            return null;
        }
    }

    public int countPending() {
        String sql = "SELECT COUNT(*) FROM profile_change_requests WHERE status = 'PENDING'";
        try (Connection con = DBConnection.getConnection();
             PreparedStatement ps = con.prepareStatement(sql)) {
            ensureTable(con);
            try (ResultSet rs = ps.executeQuery()) {
                return rs.next() ? rs.getInt(1) : 0;
            }
        } catch (Exception e) {
            LOGGER.log(Level.WARNING, "countPending failed", e);
            return 0;
        }
    }

    /**
     * Approves a request: applies the requested value to the employee record
     * and marks the request APPROVED, in one transaction. Returns a result
     * that distinguishes "not found/already reviewed" from "the update
     * itself failed" (e.g. the requested email collides with
     * employees.email's UNIQUE constraint) so the caller can show an
     * accurate message instead of a generic failure.
     */
    public ApprovalResult approve(int requestId, int reviewerUserId, String reviewNote) {
        Connection con = null;
        try {
            con = DBConnection.getConnection();
            if (con == null) {
                return ApprovalResult.SERVER_ERROR;
            }
            ensureTable(con);
            con.setAutoCommit(false);

            String fieldName = null;
            String requestedValue = null;
            int employeeId = 0;

            String fetchSql = "SELECT employee_id, field_name, requested_value FROM profile_change_requests "
                    + "WHERE request_id = ? AND status = 'PENDING' FOR UPDATE";
            try (PreparedStatement ps = con.prepareStatement(fetchSql)) {
                ps.setInt(1, requestId);
                try (ResultSet rs = ps.executeQuery()) {
                    if (!rs.next()) {
                        con.rollback();
                        return ApprovalResult.NOT_FOUND_OR_ALREADY_REVIEWED;
                    }
                    employeeId = rs.getInt("employee_id");
                    fieldName = rs.getString("field_name");
                    requestedValue = rs.getString("requested_value");
                }
            }

            if (!ALLOWED_FIELDS.contains(fieldName)) {
                con.rollback();
                return ApprovalResult.SERVER_ERROR;
            }

            // fieldName is whitelist-checked above (only ever "email" or
            // "phone" can reach this point), so this string-built column
            // name is never attacker/user-controlled despite not being a
            // bind parameter - JDBC has no placeholder syntax for identifiers.
            String updateEmployeeSql = "UPDATE employees SET " + fieldName + " = ? WHERE employee_id = ?";
            try (PreparedStatement ps = con.prepareStatement(updateEmployeeSql)) {
                ps.setString(1, requestedValue);
                ps.setInt(2, employeeId);
                ps.executeUpdate();
            }

            String updateRequestSql = "UPDATE profile_change_requests "
                    + "SET status = 'APPROVED', reviewed_by = ?, review_note = ?, reviewed_at = CURRENT_TIMESTAMP "
                    + "WHERE request_id = ?";
            try (PreparedStatement ps = con.prepareStatement(updateRequestSql)) {
                if (reviewerUserId > 0) {
                    ps.setInt(1, reviewerUserId);
                } else {
                    ps.setNull(1, java.sql.Types.INTEGER);
                }
                ps.setString(2, reviewNote == null ? "" : reviewNote);
                ps.setInt(3, requestId);
                ps.executeUpdate();
            }

            con.commit();
            return ApprovalResult.SUCCESS;

        } catch (java.sql.SQLIntegrityConstraintViolationException dupEx) {
            // e.g. requested email already belongs to another employee
            // (employees.email UNIQUE) - leave the request PENDING so the
            // admin can reject it with an explanation instead of it
            // silently vanishing.
            rollbackQuietly(con);
            return ApprovalResult.CONFLICT;
        } catch (Exception e) {
            LOGGER.log(Level.SEVERE, "approve failed for request " + requestId, e);
            rollbackQuietly(con);
            return ApprovalResult.SERVER_ERROR;
        } finally {
            closeQuietly(con);
        }
    }

    public boolean reject(int requestId, int reviewerUserId, String reviewNote) {
        String sql = "UPDATE profile_change_requests "
                + "SET status = 'REJECTED', reviewed_by = ?, review_note = ?, reviewed_at = CURRENT_TIMESTAMP "
                + "WHERE request_id = ? AND status = 'PENDING'";
        try (Connection con = DBConnection.getConnection();
             PreparedStatement ps = con.prepareStatement(sql)) {
            ensureTable(con);
            if (reviewerUserId > 0) {
                ps.setInt(1, reviewerUserId);
            } else {
                ps.setNull(1, java.sql.Types.INTEGER);
            }
            ps.setString(2, reviewNote == null ? "" : reviewNote);
            ps.setInt(3, requestId);
            return ps.executeUpdate() > 0;
        } catch (Exception e) {
            LOGGER.log(Level.WARNING, "reject failed for request " + requestId, e);
            return false;
        }
    }

    private void rollbackQuietly(Connection con) {
        try {
            if (con != null) {
                con.rollback();
            }
        } catch (Exception e) {
            LOGGER.log(Level.WARNING, "Rollback failed", e);
        }
    }

    private void closeQuietly(Connection con) {
        try {
            if (con != null) {
                con.setAutoCommit(true);
                con.close();
            }
        } catch (Exception e) {
            LOGGER.log(Level.WARNING, "Unable to close connection", e);
        }
    }

    public enum ApprovalResult {
        SUCCESS, NOT_FOUND_OR_ALREADY_REVIEWED, CONFLICT, SERVER_ERROR
    }
}
