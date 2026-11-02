package com.mycompany.asset_management_system_ams;

import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.Statement;
import java.util.ArrayList;
import java.util.List;

public class AssetReturnDAO {

    public List<AssetReturn> getAllReturns() {
        List<AssetReturn> returnList = new ArrayList<>();

        String sql = "SELECT ar.return_id, ar.allocation_id, "
                + "COALESCE(a.asset_code, CONCAT('AST-', ar.asset_id)) AS asset_code, "
                + "COALESCE(a.asset_name, 'Unknown Asset') AS asset_name, "
                + "COALESCE(e.employee_code, CONCAT('EMP-', ar.employee_id)) AS employee_code, "
                + "COALESCE(e.employee_name, 'Unknown Employee') AS employee_name, "
                + "COALESCE(d.department_name, 'Unassigned Department') AS department_name, "
                + "ar.return_date, ar.return_condition, "
                + "COALESCE(u.username, '') AS received_by_name, ar.remarks "
                + "FROM asset_returns ar "
                + "LEFT JOIN assets a ON ar.asset_id = a.asset_id "
                + "LEFT JOIN employees e ON ar.employee_id = e.employee_id "
                + "LEFT JOIN departments d ON e.department_id = d.department_id "
                + "LEFT JOIN users u ON ar.received_by = u.user_id "
                + "ORDER BY ar.return_id DESC";

        try (Connection con = DBConnection.getConnection();
             PreparedStatement ps = con.prepareStatement(sql);
             ResultSet rs = ps.executeQuery()) {

            while (rs.next()) {
                AssetReturn assetReturn = new AssetReturn();
                assetReturn.setReturnId(rs.getInt("return_id"));
                assetReturn.setAllocationId(rs.getInt("allocation_id"));
                assetReturn.setAssetCode(rs.getString("asset_code"));
                assetReturn.setAssetName(rs.getString("asset_name"));
                assetReturn.setEmployeeCode(rs.getString("employee_code"));
                assetReturn.setEmployeeName(rs.getString("employee_name"));
                assetReturn.setDepartmentName(rs.getString("department_name"));
                assetReturn.setReturnDate(rs.getString("return_date"));
                assetReturn.setReturnCondition(rs.getString("return_condition"));
                assetReturn.setReceivedBy(rs.getString("received_by_name"));
                assetReturn.setRemarks(rs.getString("remarks"));
                returnList.add(assetReturn);
            }
        } catch (Exception e) {
            System.err.println("[AssetReturnDAO] getAllReturns failed: " + e.getMessage());
            e.printStackTrace();
        }

        return returnList;
    }

    public boolean addReturn(int allocationId, String returnDate, String returnCondition, String receivedBy, String remarks) {
        return addReturnAndReturnId(allocationId, returnDate, returnCondition, receivedBy, remarks) > 0;
    }

    public int addReturnAndReturnId(int allocationId, String returnDate, String returnCondition, String receivedBy, String remarks) {
        int returnId = 0;
        Connection con = null;

        try {
            con = DBConnection.getConnection();
            con.setAutoCommit(false);

            AllocationInfo info = getActiveAllocation(con, allocationId);
            if (info == null) {
                con.rollback();
                return 0;
            }

            if (hasExistingReturn(con, allocationId)) {
                con.rollback();
                return 0;
            }

            String cleanCondition = normalizeReturnCondition(returnCondition);
            int receivedByUserId = getUserIdByUsernameOrDefault(con, receivedBy);
            int returnLocationId = getReturnLocationId(con, info.assetId);
            String actionAfterReturn = getActionAfterReturn(cleanCondition);

            String insertSql = "INSERT INTO asset_returns "
                    + "(allocation_id, asset_id, employee_id, return_date, return_condition, "
                    + "received_by, return_location_id, action_after_return, remarks) "
                    + "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)";

            try (PreparedStatement ps = con.prepareStatement(insertSql, Statement.RETURN_GENERATED_KEYS)) {
                ps.setInt(1, allocationId);
                ps.setInt(2, info.assetId);
                ps.setInt(3, info.employeeId);
                ps.setString(4, emptyToToday(returnDate));
                ps.setString(5, cleanCondition);
                if (receivedByUserId > 0) {
                    ps.setInt(6, receivedByUserId);
                } else {
                    ps.setNull(6, java.sql.Types.INTEGER);
                }
                if (returnLocationId > 0) {
                    ps.setInt(7, returnLocationId);
                } else {
                    ps.setNull(7, java.sql.Types.INTEGER);
                }
                ps.setString(8, actionAfterReturn);
                ps.setString(9, clean(remarks));

                if (ps.executeUpdate() > 0) {
                    try (ResultSet keys = ps.getGeneratedKeys()) {
                        if (keys.next()) {
                            returnId = keys.getInt(1);
                        }
                    }
                }
            }

            if (returnId <= 0) {
                con.rollback();
                return 0;
            }

            try (PreparedStatement ps = con.prepareStatement(
                    "UPDATE asset_allocation SET return_date = ?, allocation_status = 'RETURNED', received_by = ? "
                    + "WHERE allocation_id = ? AND allocation_status = 'ALLOCATED'")) {
                ps.setString(1, emptyToToday(returnDate));
                if (receivedByUserId > 0) {
                    ps.setInt(2, receivedByUserId);
                } else {
                    ps.setNull(2, java.sql.Types.INTEGER);
                }
                ps.setInt(3, allocationId);
                if (ps.executeUpdate() <= 0) {
                    con.rollback();
                    return 0;
                }
            }

            String newAssetStatus = "GOOD".equals(cleanCondition) ? "AVAILABLE"
                    : ("DAMAGED".equals(cleanCondition) ? "DAMAGED" : "UNDER_MAINTENANCE");
            String newConditionStatus = "GOOD".equals(cleanCondition) ? "GOOD"
                    : ("DAMAGED".equals(cleanCondition) ? "DAMAGED" : "NEEDS_REPAIR");
            String newServiceStatus = "GOOD".equals(cleanCondition) ? "SERVICEABLE"
                    : ("DAMAGED".equals(cleanCondition) ? "NEEDS_ATTENTION" : "UNDER_REPAIR");

            try (PreparedStatement ps = con.prepareStatement(
                    "UPDATE assets SET asset_status = ?, condition_status = ?, service_status = ? WHERE asset_id = ?")) {
                ps.setString(1, newAssetStatus);
                ps.setString(2, newConditionStatus);
                ps.setString(3, newServiceStatus);
                ps.setInt(4, info.assetId);
                ps.executeUpdate();
            }

            con.commit();
        } catch (Exception e) {
            System.err.println("[AssetReturnDAO] addReturnAndReturnId failed: " + e.getMessage());
            returnId = 0;
            try {
                if (con != null) {
                    con.rollback();
                }
            } catch (Exception ignored) {
            }
            e.printStackTrace();
        } finally {
            try {
                if (con != null) {
                    con.setAutoCommit(true);
                    con.close();
                }
            } catch (Exception e) {
                System.err.println("[AssetReturnDAO] addReturnAndReturnId failed: " + e.getMessage());
                e.printStackTrace();
            }
        }

        return returnId;
    }

    public String[] getReturnNotificationDetails(int returnId) {
        String[] details = null;

        String sql = "SELECT ar.return_id, ar.allocation_id, ar.return_date, ar.return_condition, "
                + "COALESCE(u.username, '') AS received_by_name, ar.remarks, "
                + "COALESCE(a.asset_code, CONCAT('AST-', ar.asset_id)) AS asset_code, "
                + "COALESCE(a.asset_name, 'Unknown Asset') AS asset_name, "
                + "COALESCE(a.serial_number, '') AS serial_number, "
                + "COALESCE(l.location_name, a.location, 'N/A') AS location, "
                + "e.email AS employee_email, COALESCE(e.employee_name, 'Unknown Employee') AS employee_name, "
                + "COALESCE(e.employee_code, CONCAT('EMP-', ar.employee_id)) AS employee_code, "
                + "COALESCE(d.department_name, 'Unassigned Department') AS department_name "
                + "FROM asset_returns ar "
                + "LEFT JOIN assets a ON ar.asset_id = a.asset_id "
                + "LEFT JOIN railway_locations l ON ar.return_location_id = l.location_id "
                + "LEFT JOIN employees e ON ar.employee_id = e.employee_id "
                + "LEFT JOIN departments d ON e.department_id = d.department_id "
                + "LEFT JOIN users u ON ar.received_by = u.user_id "
                + "WHERE ar.return_id = ?";

        try (Connection con = DBConnection.getConnection();
             PreparedStatement ps = con.prepareStatement(sql)) {

            ps.setInt(1, returnId);

            try (ResultSet rs = ps.executeQuery()) {
                if (rs.next()) {
                    details = new String[14];
                    details[0] = rs.getString("employee_email");
                    details[1] = rs.getString("employee_name");
                    details[2] = rs.getString("employee_code");
                    details[3] = rs.getString("department_name");
                    details[4] = rs.getString("asset_code");
                    details[5] = rs.getString("asset_name");
                    details[6] = rs.getString("serial_number");
                    details[7] = rs.getString("location");
                    details[8] = rs.getString("return_date");
                    details[9] = rs.getString("return_condition");
                    details[10] = rs.getString("received_by_name");
                    details[11] = rs.getString("remarks");
                    details[12] = String.valueOf(rs.getInt("return_id"));
                    details[13] = String.valueOf(rs.getInt("allocation_id"));
                }
            }
        } catch (Exception e) {
            System.err.println("[AssetReturnDAO] addReturnAndReturnId failed: " + e.getMessage());
            e.printStackTrace();
        }

        return details;
    }

    public AssetReturn getReturnById(int returnId) {
        AssetReturn assetReturn = null;

        String sql = "SELECT ar.return_id, ar.allocation_id, "
                + "COALESCE(a.asset_code, CONCAT('AST-', ar.asset_id)) AS asset_code, "
                + "COALESCE(a.asset_name, 'Unknown Asset') AS asset_name, "
                + "COALESCE(e.employee_code, CONCAT('EMP-', ar.employee_id)) AS employee_code, "
                + "COALESCE(e.employee_name, 'Unknown Employee') AS employee_name, "
                + "COALESCE(d.department_name, 'Unassigned Department') AS department_name, "
                + "ar.return_date, ar.return_condition, "
                + "COALESCE(u.username, '') AS received_by_name, ar.remarks "
                + "FROM asset_returns ar "
                + "LEFT JOIN assets a ON ar.asset_id = a.asset_id "
                + "LEFT JOIN employees e ON ar.employee_id = e.employee_id "
                + "LEFT JOIN departments d ON e.department_id = d.department_id "
                + "LEFT JOIN users u ON ar.received_by = u.user_id "
                + "WHERE ar.return_id = ?";

        try (Connection con = DBConnection.getConnection();
             PreparedStatement ps = con.prepareStatement(sql)) {

            ps.setInt(1, returnId);

            try (ResultSet rs = ps.executeQuery()) {
                if (rs.next()) {
                    assetReturn = new AssetReturn();
                    assetReturn.setReturnId(rs.getInt("return_id"));
                    assetReturn.setAllocationId(rs.getInt("allocation_id"));
                    assetReturn.setAssetCode(rs.getString("asset_code"));
                    assetReturn.setAssetName(rs.getString("asset_name"));
                    assetReturn.setEmployeeCode(rs.getString("employee_code"));
                    assetReturn.setEmployeeName(rs.getString("employee_name"));
                    assetReturn.setDepartmentName(rs.getString("department_name"));
                    assetReturn.setReturnDate(rs.getString("return_date"));
                    assetReturn.setReturnCondition(rs.getString("return_condition"));
                    assetReturn.setReceivedBy(rs.getString("received_by_name"));
                    assetReturn.setRemarks(rs.getString("remarks"));
                }
            }
        } catch (Exception e) {
            System.err.println("[AssetReturnDAO] getReturnById failed: " + e.getMessage());
            e.printStackTrace();
        }

        return assetReturn;
    }

    private AllocationInfo getActiveAllocation(Connection con, int allocationId) throws Exception {
        String sql = "SELECT asset_id, employee_id FROM asset_allocation "
                + "WHERE allocation_id = ? AND allocation_status = 'ALLOCATED' FOR UPDATE";

        try (PreparedStatement ps = con.prepareStatement(sql)) {
            ps.setInt(1, allocationId);
            try (ResultSet rs = ps.executeQuery()) {
                if (rs.next()) {
                    AllocationInfo info = new AllocationInfo();
                    info.assetId = rs.getInt("asset_id");
                    info.employeeId = rs.getInt("employee_id");
                    return info;
                }
            }
        }

        return null;
    }

    private boolean hasExistingReturn(Connection con, int allocationId) throws Exception {
        String sql = "SELECT COUNT(*) FROM asset_returns WHERE allocation_id = ?";
        try (PreparedStatement ps = con.prepareStatement(sql)) {
            ps.setInt(1, allocationId);
            try (ResultSet rs = ps.executeQuery()) {
                return rs.next() && rs.getInt(1) > 0;
            }
        }
    }

    private int getReturnLocationId(Connection con, int assetId) throws Exception {
        String sql = "SELECT COALESCE(location_id, 0) AS location_id FROM assets WHERE asset_id = ?";
        try (PreparedStatement ps = con.prepareStatement(sql)) {
            ps.setInt(1, assetId);
            try (ResultSet rs = ps.executeQuery()) {
                return rs.next() ? rs.getInt("location_id") : 0;
            }
        }
    }

    // Fault (Medium, fixed): this used to silently fall back to the hardcoded
    // literal username "admin" if receivedBy was blank, and further fall back
    // to hardcoded user_id=1 if that (or whatever was typed) didn't match any
    // real username. Any typo in the free-text receivedBy field recorded the
    // return as received by whichever real account happens to be user_id 1,
    // with no error or warning - the exact "silently misattribute to user_id 1"
    // anti-pattern this codebase deliberately avoids in ~5 other places
    // (default changed from 1 to 0/"unknown" elsewhere). received_by is a
    // nullable column (schema.sql: DEFAULT NULL, ON DELETE SET NULL) - an
    // unmatched name now correctly resolves to "unknown" (0, written as NULL
    // by the caller) instead of a real, wrong, misleading account. See
    // audit/12-asset-returns.md Finding 1.
    private int getUserIdByUsernameOrDefault(Connection con, String username) throws Exception {
        String cleanUsername = clean(username);
        if (cleanUsername.isEmpty()) {
            return 0;
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

        return 0;
    }

    private String normalizeReturnCondition(String returnCondition) {
        String value = clean(returnCondition).toUpperCase();
        if ("DAMAGED".equals(value) || "NEEDS_REPAIR".equals(value)) {
            return value;
        }
        return "GOOD";
    }

    private String getActionAfterReturn(String condition) {
        if ("DAMAGED".equals(condition)) {
            return "MARK_DAMAGED";
        }
        if ("NEEDS_REPAIR".equals(condition)) {
            return "SEND_TO_MAINTENANCE";
        }
        return "MARK_AVAILABLE";
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

    private static class AllocationInfo {
        int assetId;
        int employeeId;
    }

    public int getEmployeeIdByReturnId(int returnId) {
        String sql = "SELECT aa.employee_id " +
                     "FROM asset_returns ar " +
                     "JOIN asset_allocation aa ON ar.allocation_id = aa.allocation_id " +
                     "WHERE ar.return_id = ?";

        try (Connection conn = DBConnection.getConnection();
             PreparedStatement ps = conn.prepareStatement(sql)) {

            ps.setInt(1, returnId);

            try (ResultSet rs = ps.executeQuery()) {
                if (rs.next()) {
                    return rs.getInt("employee_id");
                }
            }
        } catch (Exception e) {
            e.printStackTrace();
        }

        return 0;
    }
}
