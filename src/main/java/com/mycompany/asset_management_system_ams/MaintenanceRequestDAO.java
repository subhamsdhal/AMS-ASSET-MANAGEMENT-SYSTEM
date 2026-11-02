package com.mycompany.asset_management_system_ams;

import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

public class MaintenanceRequestDAO {

    public List<Map<String, String>> getAllMaintenanceRequests() {
        List<Map<String, String>> requests = new ArrayList<>();
        String sql = "SELECT mr.request_id, mr.asset_id, a.asset_code, a.asset_name, "
                + "mr.employee_id, e.employee_code, e.employee_name, "
                + "DATE_FORMAT(mr.request_date, '%Y-%m-%d %H:%i:%s') AS request_date, "
                + "mr.issue_description, mr.priority, mr.request_status, mr.remarks "
                + "FROM maintenance_requests mr "
                + "JOIN assets a ON mr.asset_id = a.asset_id "
                + "JOIN employees e ON mr.employee_id = e.employee_id "
                + "ORDER BY mr.request_date DESC";

        try (Connection con = DBConnection.getConnection();
             PreparedStatement ps = con.prepareStatement(sql);
             ResultSet rs = ps.executeQuery()) {

            while (rs.next()) {
                Map<String, String> row = new HashMap<>();
                row.put("request_id", String.valueOf(rs.getInt("request_id")));
                row.put("asset_id", String.valueOf(rs.getInt("asset_id")));
                row.put("asset_code", rs.getString("asset_code"));
                row.put("asset_name", rs.getString("asset_name"));
                row.put("employee_id", String.valueOf(rs.getInt("employee_id")));
                row.put("employee_code", rs.getString("employee_code"));
                row.put("employee_name", rs.getString("employee_name"));
                row.put("request_date", rs.getString("request_date"));
                row.put("issue_description", rs.getString("issue_description"));
                row.put("priority", rs.getString("priority"));
                row.put("request_status", rs.getString("request_status"));
                row.put("remarks", rs.getString("remarks"));
                requests.add(row);
            }
        } catch (Exception e) {
            e.printStackTrace();
        }
        return requests;
    }

    public List<Map<String, String>> getEmployeeMaintenanceRequestsForRole(String role, int userId) {
        List<Map<String, String>> requests = new ArrayList<>();
        
        try (Connection con = DBConnection.getConnection()) {
            
            boolean filterByDepartment = "DEPARTMENT_HEAD".equalsIgnoreCase(role);
            Integer departmentId = null;

            if (filterByDepartment && userId > 0) {
                String deptSql = "SELECT department_id FROM employees WHERE user_id = ?";
                try (PreparedStatement dps = con.prepareStatement(deptSql)) {
                    dps.setInt(1, userId);
                    try (ResultSet drs = dps.executeQuery()) {
                        if (drs.next()) {
                            departmentId = drs.getInt("department_id");
                        }
                    }
                } catch (Exception ex) {
                    ex.printStackTrace();
                }
                
                if (departmentId == null || departmentId == 0) {
                    String headSql = "SELECT department_id FROM departments WHERE department_head_user_id = ?";
                    try (PreparedStatement dps = con.prepareStatement(headSql)) {
                        dps.setInt(1, userId);
                        try (ResultSet drs = dps.executeQuery()) {
                            if (drs.next()) {
                                departmentId = drs.getInt("department_id");
                            }
                        }
                    } catch (Exception ex) {
                        ex.printStackTrace();
                    }
                }
            }

            String sql = "SELECT mr.request_id, mr.asset_id, a.asset_code, a.asset_name, "
                    + "mr.employee_id, e.employee_code, e.employee_name, "
                    + "DATE_FORMAT(mr.request_date, '%Y-%m-%d %H:%i:%s') AS request_date, "
                    + "mr.issue_description, mr.priority, mr.request_status, mr.remarks, "
                    + "mr.resolved_maintenance_id, ml.maintenance_type AS resolved_maintenance_type, "
                    + "DATE_FORMAT(ml.maintenance_date, '%Y-%m-%d') AS resolved_maintenance_date "
                    + "FROM maintenance_requests mr "
                    + "JOIN assets a ON mr.asset_id = a.asset_id "
                    + "JOIN employees e ON mr.employee_id = e.employee_id "
                    + "LEFT JOIN maintenance_logs ml ON mr.resolved_maintenance_id = ml.maintenance_id ";

            if ("EMPLOYEE".equalsIgnoreCase(role)) {
                sql += "WHERE mr.employee_id = (SELECT employee_id FROM users WHERE user_id = ?) ";
            } else if (filterByDepartment && departmentId != null && departmentId > 0) {
                sql += "WHERE e.department_id = ? OR a.department_id = ? ";
            }

            sql += "ORDER BY mr.request_date DESC";

            try (PreparedStatement ps = con.prepareStatement(sql)) {
                if ("EMPLOYEE".equalsIgnoreCase(role)) {
                    ps.setInt(1, userId);
                } else if (filterByDepartment && departmentId != null && departmentId > 0) {
                    ps.setInt(1, departmentId);
                    ps.setInt(2, departmentId);
                }

                try (ResultSet rs = ps.executeQuery()) {
                    while (rs.next()) {
                        Map<String, String> row = new HashMap<>();
                        row.put("request_id", String.valueOf(rs.getInt("request_id")));
                        row.put("asset_id", String.valueOf(rs.getInt("asset_id")));
                        row.put("asset_code", rs.getString("asset_code"));
                        row.put("asset_name", rs.getString("asset_name"));
                        row.put("employee_id", String.valueOf(rs.getInt("employee_id")));
                        row.put("employee_code", rs.getString("employee_code"));
                        row.put("employee_name", rs.getString("employee_name"));
                        row.put("request_date", rs.getString("request_date"));
                        row.put("issue_description", rs.getString("issue_description"));
                        row.put("priority", rs.getString("priority"));
                        row.put("request_status", rs.getString("request_status"));
                        row.put("remarks", rs.getString("remarks"));
                        int resolvedId = rs.getInt("resolved_maintenance_id");
                        row.put("resolved_maintenance_id", resolvedId > 0 ? String.valueOf(resolvedId) : "");
                        row.put("resolved_maintenance_type", rs.getString("resolved_maintenance_type"));
                        row.put("resolved_maintenance_date", rs.getString("resolved_maintenance_date"));
                        requests.add(row);
                    }
                }
            }
        } catch (Exception e) {
            e.printStackTrace();
        }
        return requests;
    }

    public List<Map<String, String>> getMaintenanceRequestsByEmployeeId(int employeeId) {
        List<Map<String, String>> requests = new ArrayList<>();
        String sql = "SELECT mr.request_id, mr.asset_id, a.asset_code, a.asset_name, "
                + "DATE_FORMAT(mr.request_date, '%Y-%m-%d %H:%i:%s') AS request_date, "
                + "mr.issue_description, mr.priority, mr.request_status, mr.remarks "
                + "FROM maintenance_requests mr "
                + "JOIN assets a ON mr.asset_id = a.asset_id "
                + "WHERE mr.employee_id = ? "
                + "ORDER BY mr.request_date DESC";

        try (Connection con = DBConnection.getConnection();
             PreparedStatement ps = con.prepareStatement(sql)) {

            ps.setInt(1, employeeId);
            try (ResultSet rs = ps.executeQuery()) {
                while (rs.next()) {
                    Map<String, String> row = new HashMap<>();
                    row.put("request_id", String.valueOf(rs.getInt("request_id")));
                    row.put("asset_id", String.valueOf(rs.getInt("asset_id")));
                    row.put("asset_code", rs.getString("asset_code"));
                    row.put("asset_name", rs.getString("asset_name"));
                    row.put("request_date", rs.getString("request_date"));
                    row.put("issue_description", rs.getString("issue_description"));
                    row.put("priority", rs.getString("priority"));
                    row.put("request_status", rs.getString("request_status"));
                    row.put("remarks", rs.getString("remarks"));
                    requests.add(row);
                }
            }
        } catch (Exception e) {
            e.printStackTrace();
        }
        return requests;
    }

    public boolean createMaintenanceRequest(int assetId, int employeeId, String issueDescription, String priority) {
        String sql = "INSERT INTO maintenance_requests (asset_id, employee_id, issue_description, priority, request_status) "
                   + "VALUES (?, ?, ?, ?, 'PENDING')";

        try (Connection con = DBConnection.getConnection();
             PreparedStatement ps = con.prepareStatement(sql)) {

            ps.setInt(1, assetId);
            ps.setInt(2, employeeId);
            ps.setString(3, issueDescription != null ? issueDescription.trim() : "");
            ps.setString(4, priority != null ? priority.trim() : "MEDIUM");

            return ps.executeUpdate() > 0;
        } catch (Exception e) {
            e.printStackTrace();
            return false;
        }
    }

    public boolean updateMaintenanceRequestStatus(int requestId, String status, String remarks) {
        return updateMaintenanceRequestStatus(requestId, status, remarks, 0);
    }

    /**
     * @param resolvedMaintenanceId when status is COMPLETED, the
     *        maintenance_logs row that actually resolved this request (0/
     *        negative = none available to link, e.g. no maintenance_logs row
     *        exists yet for the asset). Closes the Future Scope gap where the
     *        two tables only ever connected by timing coincidence - see
     *        migration 008's comment for the full rationale. Ignored for any
     *        status other than COMPLETED, since the link only makes sense at
     *        the point of resolution.
     */
    // Fault (Medium, fixed): this had no transition-legality guard at all, the
    // one workflow-approval DAO method in the codebase that lacked the
    // "WHERE request_status = <expected current>" precondition already
    // established as this codebase's own standard (AssetRequestDAO.
    // updateRequestStatus / RoleAssignmentDAO.deactivateAssignment /
    // ReviewPhysicalVerificationServlet). Two concurrent status changes on the
    // same requestId both silently succeeded, last-write-wins, and an already-
    // COMPLETED/REJECTED request could be freely flipped to any other status.
    // Matches maintenance.jsp's own button logic: PENDING shows Approve/Reject,
    // APPROVED/IN_PROGRESS shows Complete - so those are the only legal
    // "current status" preconditions for each target. See
    // audit/11-maintenance-requests.md Finding 1.
    public boolean updateMaintenanceRequestStatus(int requestId, String status, String remarks, int resolvedMaintenanceId) {
        boolean linking = "COMPLETED".equalsIgnoreCase(status) && resolvedMaintenanceId > 0;

        String requiredCurrentStatusClause = null;
        if ("APPROVED".equalsIgnoreCase(status) || "REJECTED".equalsIgnoreCase(status)) {
            requiredCurrentStatusClause = " AND request_status = 'PENDING'";
        } else if ("COMPLETED".equalsIgnoreCase(status)) {
            requiredCurrentStatusClause = " AND request_status IN ('APPROVED', 'IN_PROGRESS')";
        }

        String sql = (linking
                ? "UPDATE maintenance_requests SET request_status = ?, remarks = ?, resolved_maintenance_id = ? WHERE request_id = ?"
                : "UPDATE maintenance_requests SET request_status = ?, remarks = ? WHERE request_id = ?")
                + (requiredCurrentStatusClause != null ? requiredCurrentStatusClause : "");

        try (Connection con = DBConnection.getConnection();
             PreparedStatement ps = con.prepareStatement(sql)) {

            ps.setString(1, status);
            ps.setString(2, remarks != null ? remarks.trim() : "");

            if (linking) {
                ps.setInt(3, resolvedMaintenanceId);
                ps.setInt(4, requestId);
            } else {
                ps.setInt(3, requestId);
            }

            return ps.executeUpdate() > 0;
        } catch (Exception e) {
            e.printStackTrace();
            return false;
        }
    }

    public boolean isAssetCurrentlyAllottedToEmployee(int assetId, int employeeId) {
        String sql = "SELECT COUNT(*) FROM asset_allocation "
                   + "WHERE asset_id = ? AND employee_id = ? AND allocation_status = 'ALLOCATED'";

        try (Connection con = DBConnection.getConnection();
             PreparedStatement ps = con.prepareStatement(sql)) {

            ps.setInt(1, assetId);
            ps.setInt(2, employeeId);
            try (ResultSet rs = ps.executeQuery()) {
                if (rs.next()) {
                    return rs.getInt(1) > 0;
                }
            }
        } catch (Exception e) {
            e.printStackTrace();
        }
        return false;
    }

    /**
     * maintenance_logs entries for the given asset, most recent first - backs
     * the "resolved by" picker shown when marking a maintenance_requests row
     * COMPLETED. Deliberately scoped to a single asset rather than listing
     * every log system-wide: a request can only sensibly be resolved by a
     * log against the same asset it was raised for.
     */
    public List<Map<String, String>> getMaintenanceLogsForAsset(int assetId) {
        List<Map<String, String>> logs = new ArrayList<>();
        String sql = "SELECT maintenance_id, maintenance_type, "
                + "DATE_FORMAT(maintenance_date, '%d %b %Y') AS maintenance_date, work_done "
                + "FROM maintenance_logs WHERE asset_id = ? ORDER BY maintenance_date DESC, maintenance_id DESC";

        try (Connection con = DBConnection.getConnection();
             PreparedStatement ps = con.prepareStatement(sql)) {

            ps.setInt(1, assetId);
            try (ResultSet rs = ps.executeQuery()) {
                while (rs.next()) {
                    Map<String, String> row = new HashMap<>();
                    row.put("maintenance_id", String.valueOf(rs.getInt("maintenance_id")));
                    row.put("maintenance_type", rs.getString("maintenance_type"));
                    row.put("maintenance_date", rs.getString("maintenance_date"));
                    row.put("work_done", rs.getString("work_done"));
                    logs.add(row);
                }
            }
        } catch (Exception e) {
            e.printStackTrace();
        }
        return logs;
    }

    public List<Map<String, String>> getAllottedAssetsByEmployeeId(int employeeId) {
        List<Map<String, String>> assets = new ArrayList<>();
        String sql = "SELECT a.asset_id, a.asset_code, a.asset_name "
                   + "FROM asset_allocation aa "
                   + "JOIN assets a ON aa.asset_id = a.asset_id "
                   + "WHERE aa.employee_id = ? AND aa.allocation_status = 'ALLOCATED' "
                   + "ORDER BY a.asset_code ASC";

        try (Connection con = DBConnection.getConnection();
             PreparedStatement ps = con.prepareStatement(sql)) {

            ps.setInt(1, employeeId);
            try (ResultSet rs = ps.executeQuery()) {
                while (rs.next()) {
                    Map<String, String> row = new HashMap<>();
                    row.put("asset_id", String.valueOf(rs.getInt("asset_id")));
                    row.put("asset_code", rs.getString("asset_code"));
                    row.put("asset_name", rs.getString("asset_name"));
                    assets.add(row);
                }
            }
        } catch (Exception e) {
            e.printStackTrace();
        }
        return assets;
    }
}
