package com.mycompany.asset_management_system_ams;

import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.Statement;
import java.util.ArrayList;
import java.util.List;

public class AssetRequestDAO {

    public List<AssetRequest> getAllRequests() {
        List<AssetRequest> requestList = new ArrayList<>();

        String sql = "SELECT ar.request_id, "
                + "COALESCE(e.employee_code, CONCAT('EMP-', ar.employee_id)) AS employee_code, "
                + "COALESCE(e.employee_name, 'Unknown Employee') AS employee_name, "
                + "COALESCE(ac.category_name, CONCAT('Category #', ar.category_id)) AS category_name, "
                + "ar.request_date, ar.request_status, "
                + "COALESCE(u.username, '') AS approved_by_name, ar.remarks, "
                + "COALESCE(d.department_name, '') AS department_name, "
                + "ar.dept_head_action, COALESCE(dh.username, '') AS dept_head_by_name, "
                + "ar.dept_head_date, ar.dept_head_remarks "
                + "FROM asset_requests ar "
                + "LEFT JOIN employees e ON ar.employee_id = e.employee_id "
                + "LEFT JOIN asset_categories ac ON ar.category_id = ac.category_id "
                + "LEFT JOIN users u ON ar.approved_by = u.user_id "
                + "LEFT JOIN departments d ON ar.department_id = d.department_id "
                + "LEFT JOIN users dh ON ar.dept_head_by = dh.user_id "
                + "ORDER BY ar.request_date DESC, ar.request_id DESC";

        try (Connection con = DBConnection.getConnection();
             PreparedStatement ps = con.prepareStatement(sql);
             ResultSet rs = ps.executeQuery()) {

            while (rs.next()) {
                AssetRequest req = new AssetRequest();
                req.setRequestId(rs.getInt("request_id"));
                req.setEmployeeCode(rs.getString("employee_code"));
                req.setEmployeeName(rs.getString("employee_name"));
                req.setCategoryName(rs.getString("category_name"));
                req.setRequestDate(rs.getString("request_date"));
                req.setRequestStatus(rs.getString("request_status"));
                req.setApprovedBy(rs.getString("approved_by_name"));
                req.setRemarks(rs.getString("remarks"));
                req.setDepartmentName(rs.getString("department_name"));
                req.setDeptHeadAction(rs.getString("dept_head_action"));
                req.setDeptHeadByName(rs.getString("dept_head_by_name"));
                req.setDeptHeadDate(rs.getString("dept_head_date"));
                req.setDeptHeadRemarks(rs.getString("dept_head_remarks"));
                requestList.add(req);
            }
        } catch (Exception e) {
            System.err.println("[AssetRequestDAO] getAllRequests failed: " + e.getMessage());
            e.printStackTrace();
        }

        return requestList;
    }

    public boolean addAssetRequest(int employeeId, int categoryId, String requestDate,
            String requestStatus, String approvedBy, String remarks) {
        return addAssetRequestAndReturnId(employeeId, categoryId, requestDate, requestStatus, approvedBy, remarks) > 0;
    }

    // Original signature kept for source compatibility (no other caller found
    // in the codebase besides addAssetRequest() above, but keeping it avoids
    // ripple changes for anything outside this file). Never routes through a
    // Department Head - equivalent to routeThroughDeptHead=false below.
    public int addAssetRequestAndReturnId(int employeeId, int categoryId, String requestDate,
            String requestStatus, String approvedBy, String remarks) {
        return addAssetRequestAndReturnId(employeeId, categoryId, requestDate, requestStatus,
                approvedBy, remarks, false);
    }

    /**
     * @param routeThroughDeptHead true for an employee's own self-service
     *        request (AddAssetRequestServlet's EMPLOYEE branch); false for a
     *        request an ops role (Admin/Asset Manager/Department
     *        Head/Super Admin) raises on an employee's behalf, which goes
     *        straight to the existing Asset Manager stage exactly as it
     *        always has - the person recording it is already trusted staff,
     *        not the requesting employee acting alone. When true, the actual
     *        routing still depends on whether the employee's department has
     *        an active department head: resolveActiveDepartmentHeadUserId()
     *        is the single source of truth for "is a department head
     *        assigned/available", reusing the same
     *        employees-JOIN-departments-WHERE-status='ACTIVE' shape already
     *        used by EmployeeDAO.getDepartmentHeadEmailByEmployeeId() and
     *        NotificationRecipientResolver, rather than a second, divergent
     *        definition of "available".
     */
    public int addAssetRequestAndReturnId(int employeeId, int categoryId, String requestDate,
            String requestStatus, String approvedBy, String remarks, boolean routeThroughDeptHead) {

        int generatedRequestId = 0;

        String sql = "INSERT INTO asset_requests "
                + "(employee_id, department_id, division_id, location_id, category_id, request_type, "
                + "request_date, request_status, priority, approved_by, approved_date, request_reason, remarks) "
                + "SELECT e.employee_id, e.department_id, e.division_id, e.location_id, ac.category_id, 'NEW_ASSET', "
                + "?, ?, 'NORMAL', ?, CASE WHEN ? IS NULL THEN NULL ELSE CURDATE() END, ?, ? "
                + "FROM employees e "
                + "JOIN asset_categories ac ON ac.category_id = ? AND ac.is_active = 'YES' "
                + "WHERE e.employee_id = ? "
                + "AND e.employee_status = 'ACTIVE' "
                + "AND COALESCE(e.is_deleted, 0) = 0";

        try (Connection con = DBConnection.getConnection();
             PreparedStatement ps = con.prepareStatement(sql, Statement.RETURN_GENERATED_KEYS)) {

            Integer approvedByUserId = getUserIdByUsername(con, approvedBy);
            String status = normalizeRequestStatus(requestStatus);

            if (routeThroughDeptHead && "PENDING".equals(status)
                    && resolveActiveDepartmentHeadUserId(con, employeeId) != null) {
                status = "PENDING_DEPT_HEAD";
            }

            ps.setString(1, emptyToToday(requestDate));
            ps.setString(2, status);
            if (approvedByUserId == null) {
                ps.setNull(3, java.sql.Types.INTEGER);
                ps.setNull(4, java.sql.Types.INTEGER);
            } else {
                ps.setInt(3, approvedByUserId);
                ps.setInt(4, approvedByUserId);
            }
            ps.setString(5, clean(remarks));
            ps.setString(6, clean(remarks));
            ps.setInt(7, categoryId);
            ps.setInt(8, employeeId);

            if (ps.executeUpdate() > 0) {
                try (ResultSet keys = ps.getGeneratedKeys()) {
                    if (keys.next()) {
                        generatedRequestId = keys.getInt(1);
                    }
                }
            }
        } catch (Exception e) {
            System.err.println("[AssetRequestDAO] addAssetRequestAndReturnId failed: " + e.getMessage());
            e.printStackTrace();
        }

        return generatedRequestId;
    }

    /** Whether this request currently needs Department Head review at all. */
    public boolean requestStartsAtDeptHead(int employeeId) {
        try (Connection con = DBConnection.getConnection()) {
            return resolveActiveDepartmentHeadUserId(con, employeeId) != null;
        } catch (Exception e) {
            System.err.println("[AssetRequestDAO] requestStartsAtDeptHead failed: " + e.getMessage());
            return false;
        }
    }

    /**
     * Resolves the active department head's user_id for the department the
     * given employee belongs to, or null if the department has none assigned
     * (department_head_user_id IS NULL) or isn't itself ACTIVE. This is the
     * single, authoritative "is a department head assigned/available" check
     * for the whole request-routing/RBAC flow - do not reimplement this join
     * elsewhere; call this (or the public requestStartsAtDeptHead()
     * convenience wrapper) instead, matching this codebase's own
     * documented preference for one canonical resolution over a second,
     * divergent copy (see EmployeeDAO.isEmployeeUnderDepartmentHead()'s
     * equivalent role in Modules 2/19/20).
     */
    private Integer resolveActiveDepartmentHeadUserId(Connection con, int employeeId) throws Exception {
        String sql = "SELECT d.department_head_user_id "
                + "FROM employees e "
                + "JOIN departments d ON e.department_id = d.department_id "
                + "WHERE e.employee_id = ? AND d.status = 'ACTIVE' AND d.department_head_user_id IS NOT NULL";
        try (PreparedStatement ps = con.prepareStatement(sql)) {
            ps.setInt(1, employeeId);
            try (ResultSet rs = ps.executeQuery()) {
                if (rs.next()) {
                    int headUserId = rs.getInt(1);
                    return rs.wasNull() ? null : headUserId;
                }
            }
        }
        return null;
    }

    /**
     * Department Head forwards (-> PENDING, awaiting Asset Manager/Admin/
     * Super Admin) or rejects (-> REJECTED, ends the request) a request
     * currently sitting at their review stage.
     *
     * The caller's ownership of this request is enforced structurally in the
     * WHERE clause itself - ar.department_id must match a department this
     * exact user_id heads - rather than as a separate check-then-act step,
     * closing the TOCTOU window that pattern would otherwise leave open, and
     * matching the codebase's preferred style for its strongest-guarded
     * writes (Modules 5/6/12's row-locked or WHERE-clause-guarded updates).
     * The existing request_status='PENDING_DEPT_HEAD' precondition doubles as
     * the same idempotency/concurrency guard already used by
     * updateRequestStatus() - a stale or replayed forward/reject becomes a
     * safe no-op (0 rows) rather than double-processing.
     *
     * @param action "FORWARD" or "REJECT"
     */
    public boolean forwardOrRejectByDeptHead(int requestId, String action, int deptHeadUserId, String remarks) {
        boolean forward = "FORWARD".equalsIgnoreCase(clean(action));
        String newStatus = forward ? "PENDING" : "REJECTED";
        String deptHeadAction = forward ? "FORWARDED" : "REJECTED";

        String sql = "UPDATE asset_requests ar "
                + "JOIN departments d ON ar.department_id = d.department_id AND d.department_head_user_id = ? "
                + "SET ar.request_status = ?, ar.dept_head_action = ?, ar.dept_head_by = ?, "
                + "ar.dept_head_date = CURDATE(), ar.dept_head_remarks = ? "
                + "WHERE ar.request_id = ? AND ar.request_status = 'PENDING_DEPT_HEAD'";

        try (Connection con = DBConnection.getConnection();
             PreparedStatement ps = con.prepareStatement(sql)) {
            ps.setInt(1, deptHeadUserId);
            ps.setString(2, newStatus);
            ps.setString(3, deptHeadAction);
            ps.setInt(4, deptHeadUserId);
            ps.setString(5, clean(remarks));
            ps.setInt(6, requestId);
            return ps.executeUpdate() > 0;
        } catch (Exception e) {
            System.err.println("[AssetRequestDAO] forwardOrRejectByDeptHead failed: " + e.getMessage());
            e.printStackTrace();
            return false;
        }
    }

    /** Requests currently awaiting this Department Head's review. */
    public List<AssetRequest> getRequestsPendingForDeptHead(int deptHeadUserId) {
        List<AssetRequest> requestList = new ArrayList<>();

        String sql = "SELECT ar.request_id, "
                + "COALESCE(e.employee_code, CONCAT('EMP-', ar.employee_id)) AS employee_code, "
                + "COALESCE(e.employee_name, 'Unknown Employee') AS employee_name, "
                + "COALESCE(ac.category_name, CONCAT('Category #', ar.category_id)) AS category_name, "
                + "ar.request_date, ar.request_status, '' AS approved_by_name, ar.remarks "
                + "FROM asset_requests ar "
                + "JOIN departments d ON ar.department_id = d.department_id AND d.department_head_user_id = ? "
                + "LEFT JOIN employees e ON ar.employee_id = e.employee_id "
                + "LEFT JOIN asset_categories ac ON ar.category_id = ac.category_id "
                + "WHERE ar.request_status = 'PENDING_DEPT_HEAD' "
                + "ORDER BY ar.request_date DESC, ar.request_id DESC";

        try (Connection con = DBConnection.getConnection();
             PreparedStatement ps = con.prepareStatement(sql)) {

            ps.setInt(1, deptHeadUserId);

            try (ResultSet rs = ps.executeQuery()) {
                while (rs.next()) {
                    AssetRequest req = new AssetRequest();
                    req.setRequestId(rs.getInt("request_id"));
                    req.setEmployeeCode(rs.getString("employee_code"));
                    req.setEmployeeName(rs.getString("employee_name"));
                    req.setCategoryName(rs.getString("category_name"));
                    req.setRequestDate(rs.getString("request_date"));
                    req.setRequestStatus(rs.getString("request_status"));
                    req.setApprovedBy(rs.getString("approved_by_name"));
                    req.setRemarks(rs.getString("remarks"));
                    requestList.add(req);
                }
            }
        } catch (Exception e) {
            System.err.println("[AssetRequestDAO] getRequestsPendingForDeptHead failed: " + e.getMessage());
            e.printStackTrace();
        }

        return requestList;
    }

    public boolean updateRequestStatus(int requestId, String requestStatus, String approvedBy, String remarks) {
        return updateRequestStatus(requestId, requestStatus, approvedBy, remarks, 0);
    }

    /**
     * @param fulfilledAllocationId when requestStatus is FULFILLED, the
     *        asset_allocation row that actually satisfied this request (0/
     *        negative = not provided). Closes the Future Scope traceability
     *        gap: fulfilled_asset_id existed on this table already but was
     *        never actually populated anywhere in the codebase - "FULFILLED"
     *        was a bare status flip with no asset or allocation ever linked.
     *        Ownership is enforced structurally in the WHERE clause itself
     *        (the allocation must belong to this exact request's employee_id
     *        and still be ALLOCATED), the same WHERE-clause-guard style
     *        already used for this table's dept-head review guard, rather
     *        than a separate check-then-act step. fulfilled_asset_id is
     *        derived from the allocation and kept in sync for backward
     *        compatibility with existing reads (view_request.jsp).
     */
    public boolean updateRequestStatus(int requestId, String requestStatus, String approvedBy, String remarks,
            int fulfilledAllocationId) {
        String status = normalizeRequestStatus(requestStatus);

        // Idempotency / concurrency guard: only apply the transition when the
        // request is still in the status that transition expects (PENDING ->
        // APPROVED/REJECTED, APPROVED -> FULFILLED). Without this, two asset
        // managers acting on the same request at nearly the same time (or a
        // stale/replayed form re-submit) could silently re-process a request
        // that was already finalized - e.g. re-rejecting an already-fulfilled
        // request, or a delayed double-click re-approving one that was just
        // rejected by someone else. Adding the precondition to the WHERE
        // clause turns the second/stale action into a safe no-op (0 rows
        // affected -> returns false, UpdateRequestStatusServlet already shows
        // "could not be updated, please refresh" on that path) instead of a
        // silent overwrite. Same pattern as RoleAssignmentDAO.deactivateAssignment().
        String requiredCurrentStatus = null;
        if ("APPROVED".equals(status) || "REJECTED".equals(status)) {
            requiredCurrentStatus = "PENDING";
        } else if ("FULFILLED".equals(status)) {
            requiredCurrentStatus = "APPROVED";
        }

        boolean linkAllocation = "FULFILLED".equals(status) && fulfilledAllocationId > 0;

        String sql = "UPDATE asset_requests "
                + "SET request_status = ?, approved_by = ?, approved_date = ?, remarks = ?"
                + (linkAllocation ? ", fulfilled_allocation_id = ?, "
                        + "fulfilled_asset_id = (SELECT asset_id FROM asset_allocation WHERE allocation_id = ?)" : "")
                + " WHERE request_id = ?"
                + (requiredCurrentStatus != null ? " AND request_status = ?" : "")
                + (linkAllocation ? " AND EXISTS (SELECT 1 FROM asset_allocation aa WHERE aa.allocation_id = ? "
                        + "AND aa.employee_id = asset_requests.employee_id AND aa.allocation_status = 'ALLOCATED')" : "");

        try (Connection con = DBConnection.getConnection();
             PreparedStatement ps = con.prepareStatement(sql)) {

            Integer approvedByUserId = getUserIdByUsername(con, approvedBy);
            int idx = 1;

            ps.setString(idx++, status);
            if (approvedByUserId == null || "PENDING".equals(status)) {
                ps.setNull(idx++, java.sql.Types.INTEGER);
                ps.setNull(idx++, java.sql.Types.DATE);
            } else {
                ps.setInt(idx++, approvedByUserId);
                ps.setDate(idx++, new java.sql.Date(System.currentTimeMillis()));
            }
            ps.setString(idx++, clean(remarks));
            if (linkAllocation) {
                ps.setInt(idx++, fulfilledAllocationId);
                ps.setInt(idx++, fulfilledAllocationId);
            }
            ps.setInt(idx++, requestId);
            if (requiredCurrentStatus != null) {
                ps.setString(idx++, requiredCurrentStatus);
            }
            if (linkAllocation) {
                ps.setInt(idx++, fulfilledAllocationId);
            }

            return ps.executeUpdate() > 0;
        } catch (Exception e) {
            System.err.println("[AssetRequestDAO] updateRequestStatus failed: " + e.getMessage());
            e.printStackTrace();
        }

        return false;
    }

    /**
     * The employee's currently active allocations - backs the "which
     * allocation fulfilled this request" picker shown when marking a request
     * FULFILLED. Deliberately not filtered by category: an Asset Manager may
     * legitimately fulfil a request with a close substitute, and the DAO-level
     * ownership guard in updateRequestStatus() only requires the allocation
     * to belong to the same employee and be ALLOCATED, not an exact category
     * match.
     */
    public List<java.util.Map<String, String>> getActiveAllocationsForEmployee(int employeeId) {
        List<java.util.Map<String, String>> out = new ArrayList<>();
        String sql = "SELECT aa.allocation_id, a.asset_code, a.asset_name, "
                + "DATE_FORMAT(aa.allocation_date, '%d %b %Y') AS allocation_date "
                + "FROM asset_allocation aa "
                + "JOIN assets a ON aa.asset_id = a.asset_id "
                + "WHERE aa.employee_id = ? AND aa.allocation_status = 'ALLOCATED' "
                + "ORDER BY aa.allocation_date DESC";

        try (Connection con = DBConnection.getConnection();
             PreparedStatement ps = con.prepareStatement(sql)) {

            ps.setInt(1, employeeId);
            try (ResultSet rs = ps.executeQuery()) {
                while (rs.next()) {
                    java.util.Map<String, String> row = new java.util.HashMap<>();
                    row.put("allocation_id", String.valueOf(rs.getInt("allocation_id")));
                    row.put("asset_code", rs.getString("asset_code"));
                    row.put("asset_name", rs.getString("asset_name"));
                    row.put("allocation_date", rs.getString("allocation_date"));
                    out.add(row);
                }
            }
        } catch (Exception e) {
            System.err.println("[AssetRequestDAO] getActiveAllocationsForEmployee failed: " + e.getMessage());
            e.printStackTrace();
        }

        return out;
    }

    public AssetRequest getRequestById(int requestId) {
        AssetRequest req = null;

        String sql = "SELECT ar.request_id, "
                + "COALESCE(e.employee_code, CONCAT('EMP-', ar.employee_id)) AS employee_code, "
                + "COALESCE(e.employee_name, 'Unknown Employee') AS employee_name, "
                + "COALESCE(ac.category_name, CONCAT('Category #', ar.category_id)) AS category_name, "
                + "ar.request_date, ar.request_status, "
                + "COALESCE(u.username, '') AS approved_by_name, ar.remarks, "
                + "COALESCE(d.department_name, '') AS department_name, "
                + "ar.dept_head_action, COALESCE(dh.username, '') AS dept_head_by_name, "
                + "ar.dept_head_date, ar.dept_head_remarks "
                + "FROM asset_requests ar "
                + "LEFT JOIN employees e ON ar.employee_id = e.employee_id "
                + "LEFT JOIN asset_categories ac ON ar.category_id = ac.category_id "
                + "LEFT JOIN users u ON ar.approved_by = u.user_id "
                + "LEFT JOIN departments d ON ar.department_id = d.department_id "
                + "LEFT JOIN users dh ON ar.dept_head_by = dh.user_id "
                + "WHERE ar.request_id = ?";

        try (Connection con = DBConnection.getConnection();
             PreparedStatement ps = con.prepareStatement(sql)) {

            ps.setInt(1, requestId);

            try (ResultSet rs = ps.executeQuery()) {
                if (rs.next()) {
                    req = new AssetRequest();
                    req.setRequestId(rs.getInt("request_id"));
                    req.setEmployeeCode(rs.getString("employee_code"));
                    req.setEmployeeName(rs.getString("employee_name"));
                    req.setCategoryName(rs.getString("category_name"));
                    req.setRequestDate(rs.getString("request_date"));
                    req.setRequestStatus(rs.getString("request_status"));
                    req.setApprovedBy(rs.getString("approved_by_name"));
                    req.setRemarks(rs.getString("remarks"));
                    req.setDepartmentName(rs.getString("department_name"));
                    req.setDeptHeadAction(rs.getString("dept_head_action"));
                    req.setDeptHeadByName(rs.getString("dept_head_by_name"));
                    req.setDeptHeadDate(rs.getString("dept_head_date"));
                    req.setDeptHeadRemarks(rs.getString("dept_head_remarks"));
                }
            }
        } catch (Exception e) {
            System.err.println("[AssetRequestDAO] getRequestById failed: " + e.getMessage());
            e.printStackTrace();
        }

        return req;
    }

    public String[] getRequestNotificationDetails(int requestId) {
        String[] details = null;

        String sql = "SELECT ar.request_id, ar.request_date, ar.request_status, ar.priority, ar.remarks, "
                + "e.email AS employee_email, COALESCE(e.employee_name, 'Unknown Employee') AS employee_name, "
                + "COALESCE(e.employee_code, CONCAT('EMP-', ar.employee_id)) AS employee_code, "
                + "COALESCE(ac.category_name, CONCAT('Category #', ar.category_id)) AS category_name, "
                + "COALESCE(d.department_name, 'Unassigned Department') AS department_name "
                + "FROM asset_requests ar "
                + "LEFT JOIN employees e ON ar.employee_id = e.employee_id "
                + "LEFT JOIN asset_categories ac ON ar.category_id = ac.category_id "
                + "LEFT JOIN departments d ON ar.department_id = d.department_id "
                + "WHERE ar.request_id = ?";

        try (Connection con = DBConnection.getConnection();
             PreparedStatement ps = con.prepareStatement(sql)) {

            ps.setInt(1, requestId);

            try (ResultSet rs = ps.executeQuery()) {
                if (rs.next()) {
                    details = new String[10];
                    details[0] = rs.getString("employee_email");
                    details[1] = rs.getString("employee_name");
                    details[2] = rs.getString("employee_code");
                    details[3] = rs.getString("category_name");
                    details[4] = rs.getString("request_date");
                    details[5] = rs.getString("request_status");
                    details[6] = rs.getString("priority");
                    details[7] = rs.getString("remarks");
                    details[8] = String.valueOf(rs.getInt("request_id"));
                    details[9] = rs.getString("department_name");
                }
            }
        } catch (Exception e) {
            System.err.println("[AssetRequestDAO] getRequestById failed: " + e.getMessage());
            e.printStackTrace();
        }

        return details;
    }

    public int getEmployeeIdByRequestId(int requestId) {
        int employeeId = 0;
        String sql = "SELECT employee_id FROM asset_requests WHERE request_id = ?";
        try (Connection con = DBConnection.getConnection();
             PreparedStatement ps = con.prepareStatement(sql)) {
            ps.setInt(1, requestId);
            try (ResultSet rs = ps.executeQuery()) {
                if (rs.next()) {
                    employeeId = rs.getInt("employee_id");
                }
            }
        } catch (Exception e) {
            e.printStackTrace();
        }
        return employeeId;
    }

    private Integer getUserIdByUsername(Connection con, String username) throws Exception {
        String cleanUsername = clean(username);
        if (cleanUsername.isEmpty()) {
            return null;
        }

        String sql = "SELECT user_id FROM users WHERE username = ? LIMIT 1";
        try (PreparedStatement ps = con.prepareStatement(sql)) {
            ps.setString(1, cleanUsername);
            try (ResultSet rs = ps.executeQuery()) {
                if (rs.next()) {
                    return rs.getInt("user_id");
                }
            }
        }

        return null;
    }

    private String normalizeRequestStatus(String status) {
        String value = clean(status).toUpperCase();
        if ("APPROVED".equals(value) || "REJECTED".equals(value) || "FULFILLED".equals(value) || "CANCELLED".equals(value)) {
            return value;
        }
        return "PENDING";
    }

    private String emptyToToday(String value) {
        String text = clean(value);
        if (!text.isEmpty()) {
            return text;
        }
        return new java.sql.Date(System.currentTimeMillis()).toString();
    }

    private String clean(String value) {
        return value == null ? "" : value.trim();
    }
}
