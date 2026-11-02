package com.mycompany.asset_management_system_ams;

import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

public class EmployeeDashboardDAO {

    public Map<String, Integer> getDashboardStats(int employeeId) {
        Map<String, Integer> stats = new HashMap<>();
        stats.put("total_allocations", 0);
        stats.put("active_allocations", 0);
        stats.put("total_requests", 0);
        stats.put("pending_requests", 0);

        String sqlAlloc = "SELECT "
                + "COUNT(*) AS total_alloc, "
                + "SUM(CASE WHEN allocation_status <> 'RETURNED' THEN 1 ELSE 0 END) AS active_alloc "
                + "FROM asset_allocation WHERE employee_id = ?";

        // PENDING_DEPT_HEAD counts as "pending" from the employee's own point of
        // view too - it just hasn't reached the Asset Manager stage yet. Without
        // this, an employee's own request would silently drop out of their
        // "Pending Requests" count the moment it started at Department Head
        // review, understating it until forwarded.
        String sqlReq = "SELECT "
                + "COUNT(*) AS total_req, "
                + "SUM(CASE WHEN request_status IN ('PENDING', 'PENDING_DEPT_HEAD') THEN 1 ELSE 0 END) AS pending_req "
                + "FROM asset_requests WHERE employee_id = ?";

        try (Connection con = DBConnection.getConnection()) {
            try (PreparedStatement ps = con.prepareStatement(sqlAlloc)) {
                ps.setInt(1, employeeId);
                try (ResultSet rs = ps.executeQuery()) {
                    if (rs.next()) {
                        stats.put("total_allocations", rs.getInt("total_alloc"));
                        stats.put("active_allocations", rs.getInt("active_alloc"));
                    }
                }
            }
            try (PreparedStatement ps = con.prepareStatement(sqlReq)) {
                ps.setInt(1, employeeId);
                try (ResultSet rs = ps.executeQuery()) {
                    if (rs.next()) {
                        stats.put("total_requests", rs.getInt("total_req"));
                        stats.put("pending_requests", rs.getInt("pending_req"));
                    }
                }
            }
        } catch (Exception e) {
            e.printStackTrace();
        }

        return stats;
    }

    public List<Map<String, String>> getRecentAllocations(int employeeId, int limit) {
        List<Map<String, String>> list = new ArrayList<>();
        String sql = "SELECT aa.allocation_id, a.asset_code, a.asset_name, aa.allocation_status, "
                + "DATE_FORMAT(aa.allocation_date, '%d %b %Y') AS allocation_date, "
                + "c.category_name "
                + "FROM asset_allocation aa "
                + "JOIN assets a ON aa.asset_id = a.asset_id "
                + "LEFT JOIN asset_categories c ON a.category_id = c.category_id "
                + "WHERE aa.employee_id = ? "
                + "ORDER BY aa.allocation_id DESC LIMIT ?";

        try (Connection con = DBConnection.getConnection();
             PreparedStatement ps = con.prepareStatement(sql)) {
            ps.setInt(1, employeeId);
            ps.setInt(2, limit);
            try (ResultSet rs = ps.executeQuery()) {
                while (rs.next()) {
                    Map<String, String> map = new HashMap<>();
                    map.put("allocation_id", rs.getString("allocation_id"));
                    map.put("asset_code", rs.getString("asset_code"));
                    map.put("asset_name", rs.getString("asset_name"));
                    map.put("allocation_status", rs.getString("allocation_status"));
                    map.put("allocation_date", rs.getString("allocation_date"));
                    map.put("category_name", rs.getString("category_name"));
                    list.add(map);
                }
            }
        } catch (Exception e) {
            e.printStackTrace();
        }
        return list;
    }

    public List<Map<String, String>> getRecentRequests(int employeeId, int limit) {
        List<Map<String, String>> list = new ArrayList<>();
        String sql = "SELECT ar.request_id, ar.request_type, ar.request_status, "
                + "DATE_FORMAT(ar.request_date, '%d %b %Y') AS request_date, "
                + "c.category_name, ar.request_reason "
                + "FROM asset_requests ar "
                + "LEFT JOIN asset_categories c ON ar.category_id = c.category_id "
                + "WHERE ar.employee_id = ? "
                + "ORDER BY ar.request_id DESC LIMIT ?";

        try (Connection con = DBConnection.getConnection();
             PreparedStatement ps = con.prepareStatement(sql)) {
            ps.setInt(1, employeeId);
            ps.setInt(2, limit);
            try (ResultSet rs = ps.executeQuery()) {
                while (rs.next()) {
                    Map<String, String> map = new HashMap<>();
                    map.put("request_id", rs.getString("request_id"));
                    map.put("request_type", rs.getString("request_type"));
                    map.put("request_status", rs.getString("request_status"));
                    map.put("request_date", rs.getString("request_date"));
                    map.put("category_name", rs.getString("category_name"));
                    map.put("request_reason", rs.getString("request_reason"));
                    list.add(map);
                }
            }
        } catch (Exception e) {
            e.printStackTrace();
        }
        return list;
    }

    public List<Map<String, String>> getRecentReturns(int employeeId, int limit) {
        List<Map<String, String>> list = new ArrayList<>();
        String sql = "SELECT r.return_id, a.asset_code, a.asset_name, "
                + "DATE_FORMAT(r.return_date, '%d %b %Y') AS return_date, "
                + "r.return_condition, r.remarks, c.category_name, "
                + "DATE_FORMAT(aa.allocation_date, '%d %b %Y') AS allocation_date, "
                + "COALESCE(u.username, 'N/A') AS received_by "
                + "FROM asset_returns r "
                + "JOIN asset_allocation aa ON r.allocation_id = aa.allocation_id "
                + "JOIN assets a ON aa.asset_id = a.asset_id "
                + "LEFT JOIN asset_categories c ON a.category_id = c.category_id "
                + "LEFT JOIN users u ON r.received_by = u.user_id "
                + "WHERE aa.employee_id = ? OR r.employee_id = ? "
                + "ORDER BY r.return_id DESC LIMIT ?";

        try (Connection con = DBConnection.getConnection();
             PreparedStatement ps = con.prepareStatement(sql)) {
            ps.setInt(1, employeeId);
            ps.setInt(2, employeeId);
            ps.setInt(3, limit);
            try (ResultSet rs = ps.executeQuery()) {
                while (rs.next()) {
                    Map<String, String> map = new HashMap<>();
                    map.put("return_id", rs.getString("return_id"));
                    map.put("asset_code", rs.getString("asset_code"));
                    map.put("asset_name", rs.getString("asset_name"));
                    map.put("return_date", rs.getString("return_date"));
                    map.put("return_condition", rs.getString("return_condition"));
                    map.put("remarks", rs.getString("remarks"));
                    map.put("category_name", rs.getString("category_name"));
                    map.put("allocation_date", rs.getString("allocation_date"));
                    map.put("received_by", rs.getString("received_by"));
                    list.add(map);
                }
            }
        } catch (Exception e) {
            e.printStackTrace();
        }
        return list;
    }
}
