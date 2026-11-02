package com.mycompany.asset_management_system_ams;

import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.Statement;
import java.util.ArrayList;
import java.util.List;

public class AssetAllocationDAO {

    public List<AssetAllocation> getAllAllocations() {
        return getAllocationList(0);
    }

    public List<AssetAllocation> getAllocationsByEmployeeId(int employeeId) {
        return getAllocationList(employeeId);
    }

    private List<AssetAllocation> getAllocationList(int employeeId) {
        List<AssetAllocation> allocationList = new ArrayList<>();

        String sql = "SELECT aa.allocation_id, aa.asset_id, aa.employee_id, "
                + "COALESCE(a.asset_code, CONCAT('AST-', aa.asset_id)) AS asset_code, "
                + "COALESCE(a.asset_name, 'Unknown Asset') AS asset_name, "
                + "COALESCE(e.employee_code, CONCAT('EMP-', aa.employee_id)) AS employee_code, "
                + "COALESCE(e.employee_name, 'Unknown Employee') AS employee_name, "
                + "COALESCE(d.department_name, 'Unassigned Department') AS department_name, "
                + "aa.allocation_date, aa.return_date, aa.allocation_status, aa.remarks, "
                + "aa.employee_transfer_preference, aa.employee_transfer_note, aa.employee_transfer_requested_at "
                + "FROM asset_allocation aa "
                + "LEFT JOIN assets a ON aa.asset_id = a.asset_id "
                + "LEFT JOIN employees e ON aa.employee_id = e.employee_id "
                + "LEFT JOIN departments d ON e.department_id = d.department_id ";

        if (employeeId > 0) {
            sql += "WHERE e.employee_id = ? ";
        }

        sql += "ORDER BY aa.allocation_id ASC";

        try (Connection con = DBConnection.getConnection();
             PreparedStatement ps = con.prepareStatement(sql)) {

            if (employeeId > 0) {
                ps.setInt(1, employeeId);
            }

            try (ResultSet rs = ps.executeQuery()) {
                while (rs.next()) {
                    AssetAllocation allocation = new AssetAllocation();

                    allocation.setAllocationId(rs.getInt("allocation_id"));
                    allocation.setAssetId(rs.getInt("asset_id"));
                    allocation.setEmployeeId(rs.getInt("employee_id"));
                    allocation.setAssetCode(rs.getString("asset_code"));
                    allocation.setAssetName(rs.getString("asset_name"));
                    allocation.setEmployeeCode(rs.getString("employee_code"));
                    allocation.setEmployeeName(rs.getString("employee_name"));
                    allocation.setDepartmentName(rs.getString("department_name"));
                    allocation.setAllocationDate(rs.getString("allocation_date"));
                    allocation.setReturnDate(rs.getString("return_date"));
                    allocation.setAllocationStatus(rs.getString("allocation_status"));
                    allocation.setRemarks(rs.getString("remarks"));
                    allocation.setEmployeeTransferPreference(rs.getString("employee_transfer_preference"));
                    allocation.setEmployeeTransferNote(rs.getString("employee_transfer_note"));
                    allocation.setEmployeeTransferRequestedAt(rs.getString("employee_transfer_requested_at"));

                    allocationList.add(allocation);
                }
            }
        } catch (Exception e) {
            System.err.println("[AssetAllocationDAO] getAllocationsByEmployeeId failed: " + e.getMessage());
            e.printStackTrace();
        }

        return allocationList;
    }

    public boolean addAllocation(int assetId, int employeeId, String allocationDate,
            String returnDate, String allocationStatus, String remarks) {
        return addAllocationAndReturnId(assetId, employeeId, allocationDate, returnDate, allocationStatus, remarks, 0) > 0;
    }

    // Overload retained for any caller that genuinely doesn't have an acting
    // user id available (issued_by is then left NULL, same as before this fix).
    public int addAllocationAndReturnId(int assetId, int employeeId, String allocationDate,
            String returnDate, String allocationStatus, String remarks) {
        return addAllocationAndReturnId(assetId, employeeId, allocationDate, returnDate, allocationStatus, remarks, 0);
    }

    // Fault (Medium, fixed): issued_by - a dedicated column + FK to users.user_id
    // specifically for "who issued this asset" - was never populated by this
    // method, the only one AddAllocationServlet (the real Allocate Asset screen)
    // calls. Every allocation made through the actual UI had issued_by = NULL,
    // even though the acting user's id was already available in the servlet -
    // it just wasn't threaded through. See audit/05-asset-allocation.md Finding E1.
    public int addAllocationAndReturnId(int assetId, int employeeId, String allocationDate,
            String returnDate, String allocationStatus, String remarks, int issuedBy) {

        int allocationId = 0;
        Connection con = null;

        try {
            con = DBConnection.getConnection();
            con.setAutoCommit(false);

            if (!isActiveEmployee(con, employeeId) || !isAvailableAsset(con, assetId)) {
                con.rollback();
                return 0;
            }

            int issueLocationId = getAssetLocationId(con, assetId);

            String insertSql = "INSERT INTO asset_allocation "
                    + "(asset_id, employee_id, allocation_date, expected_return_date, return_date, "
                    + "allocation_status, issue_condition, issue_location_id, issued_by, remarks) "
                    + "VALUES (?, ?, ?, NULL, ?, ?, 'GOOD', ?, ?, ?)";

            try (PreparedStatement ps = con.prepareStatement(insertSql, Statement.RETURN_GENERATED_KEYS)) {
                ps.setInt(1, assetId);
                ps.setInt(2, employeeId);
                ps.setString(3, emptyToNull(allocationDate));
                ps.setString(4, emptyToNull(returnDate));
                ps.setString(5, normalizeAllocationStatus(allocationStatus));
                if (issueLocationId > 0) {
                    ps.setInt(6, issueLocationId);
                } else {
                    ps.setNull(6, java.sql.Types.INTEGER);
                }
                if (issuedBy > 0) {
                    ps.setInt(7, issuedBy);
                } else {
                    ps.setNull(7, java.sql.Types.INTEGER);
                }
                ps.setString(8, clean(remarks));

                if (ps.executeUpdate() > 0) {
                    try (ResultSet keys = ps.getGeneratedKeys()) {
                        if (keys.next()) {
                            allocationId = keys.getInt(1);
                        }
                    }
                }
            }

            if (allocationId <= 0) {
                con.rollback();
                return 0;
            }

            try (PreparedStatement ps = con.prepareStatement("UPDATE assets SET asset_status = 'ALLOCATED' WHERE asset_id = ?")) {
                ps.setInt(1, assetId);
                ps.executeUpdate();
            }

            con.commit();
        } catch (Exception e) {
            System.err.println("[AssetAllocationDAO] addAllocationAndReturnId failed: " + e.getMessage());
            allocationId = 0;
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
                System.err.println("[AssetAllocationDAO] addAllocationAndReturnId failed: " + e.getMessage());
                e.printStackTrace();
            }
        }

        return allocationId;
    }

    public String[] getAllocationNotificationDetails(int allocationId) {
        String[] details = null;

        String sql = "SELECT aa.allocation_id, aa.allocation_date, aa.return_date, aa.allocation_status, aa.remarks, "
                + "e.email AS employee_email, COALESCE(e.employee_name, 'Unknown Employee') AS employee_name, "
                + "COALESCE(e.employee_code, CONCAT('EMP-', aa.employee_id)) AS employee_code, "
                + "COALESCE(d.department_name, 'Unassigned Department') AS department_name, "
                + "COALESCE(a.asset_code, CONCAT('AST-', aa.asset_id)) AS asset_code, "
                + "COALESCE(a.asset_name, 'Unknown Asset') AS asset_name, "
                + "COALESCE(a.serial_number, '') AS serial_number, "
                + "COALESCE(l.location_name, a.location, 'N/A') AS location "
                + "FROM asset_allocation aa "
                + "LEFT JOIN employees e ON aa.employee_id = e.employee_id "
                + "LEFT JOIN departments d ON e.department_id = d.department_id "
                + "LEFT JOIN assets a ON aa.asset_id = a.asset_id "
                + "LEFT JOIN railway_locations l ON a.location_id = l.location_id "
                + "WHERE aa.allocation_id = ?";

        try (Connection con = DBConnection.getConnection();
             PreparedStatement ps = con.prepareStatement(sql)) {

            ps.setInt(1, allocationId);

            try (ResultSet rs = ps.executeQuery()) {
                if (rs.next()) {
                    details = new String[13];
                    details[0] = rs.getString("employee_email");
                    details[1] = rs.getString("employee_name");
                    details[2] = rs.getString("employee_code");
                    details[3] = rs.getString("department_name");
                    details[4] = rs.getString("asset_code");
                    details[5] = rs.getString("asset_name");
                    details[6] = rs.getString("serial_number");
                    details[7] = rs.getString("location");
                    details[8] = rs.getString("allocation_date");
                    details[9] = rs.getString("return_date");
                    details[10] = rs.getString("allocation_status");
                    details[11] = rs.getString("remarks");
                    details[12] = String.valueOf(rs.getInt("allocation_id"));
                }
            }
        } catch (Exception e) {
            System.err.println("[AssetAllocationDAO] addAllocationAndReturnId failed: " + e.getMessage());
            e.printStackTrace();
        }

        return details;
    }

    public boolean returnAllocation(int allocationId) {
        boolean returned = false;
        Connection con = null;

        try {
            con = DBConnection.getConnection();
            con.setAutoCommit(false);

            int assetId = 0;
            String status = "";

            try (PreparedStatement ps = con.prepareStatement(
                    "SELECT asset_id, allocation_status FROM asset_allocation WHERE allocation_id = ? FOR UPDATE")) {
                ps.setInt(1, allocationId);
                try (ResultSet rs = ps.executeQuery()) {
                    if (rs.next()) {
                        assetId = rs.getInt("asset_id");
                        status = rs.getString("allocation_status");
                    }
                }
            }

            if (assetId <= 0 || !"ALLOCATED".equalsIgnoreCase(status)) {
                con.rollback();
                return false;
            }

            try (PreparedStatement ps = con.prepareStatement(
                    "UPDATE asset_allocation SET allocation_status = 'RETURNED', return_date = CURDATE() WHERE allocation_id = ?")) {
                ps.setInt(1, allocationId);
                ps.executeUpdate();
            }

            try (PreparedStatement ps = con.prepareStatement(
                    "UPDATE assets SET asset_status = 'AVAILABLE' WHERE asset_id = ? AND asset_status = 'ALLOCATED'")) {
                ps.setInt(1, assetId);
                ps.executeUpdate();
            }

            con.commit();
            returned = true;
        } catch (Exception e) {
            System.err.println("[AssetAllocationDAO] returnAllocation failed: " + e.getMessage());
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
                System.err.println("[AssetAllocationDAO] returnAllocation failed: " + e.getMessage());
                e.printStackTrace();
            }
        }

        return returned;
    }

    public AssetAllocation getAllocationById(int allocationId) {
        AssetAllocation allocation = null;

        String sql = "SELECT aa.allocation_id, aa.asset_id, aa.employee_id, "
                + "COALESCE(a.asset_code, CONCAT('AST-', aa.asset_id)) AS asset_code, "
                + "COALESCE(a.asset_name, 'Unknown Asset') AS asset_name, "
                + "COALESCE(e.employee_code, CONCAT('EMP-', aa.employee_id)) AS employee_code, "
                + "COALESCE(e.employee_name, 'Unknown Employee') AS employee_name, "
                + "COALESCE(d.department_name, 'Unassigned Department') AS department_name, "
                + "aa.allocation_date, aa.return_date, aa.allocation_status, aa.remarks, "
                + "aa.employee_transfer_preference, aa.employee_transfer_note, aa.employee_transfer_requested_at "
                + "FROM asset_allocation aa "
                + "LEFT JOIN assets a ON aa.asset_id = a.asset_id "
                + "LEFT JOIN employees e ON aa.employee_id = e.employee_id "
                + "LEFT JOIN departments d ON e.department_id = d.department_id "
                + "WHERE aa.allocation_id = ?";

        try (Connection con = DBConnection.getConnection();
             PreparedStatement ps = con.prepareStatement(sql)) {

            ps.setInt(1, allocationId);

            try (ResultSet rs = ps.executeQuery()) {
                if (rs.next()) {
                    allocation = new AssetAllocation();
                    allocation.setAllocationId(rs.getInt("allocation_id"));
                    allocation.setAssetId(rs.getInt("asset_id"));
                    allocation.setEmployeeId(rs.getInt("employee_id"));
                    allocation.setAssetCode(rs.getString("asset_code"));
                    allocation.setAssetName(rs.getString("asset_name"));
                    allocation.setEmployeeCode(rs.getString("employee_code"));
                    allocation.setEmployeeName(rs.getString("employee_name"));
                    allocation.setDepartmentName(rs.getString("department_name"));
                    allocation.setAllocationDate(rs.getString("allocation_date"));
                    allocation.setReturnDate(rs.getString("return_date"));
                    allocation.setAllocationStatus(rs.getString("allocation_status"));
                    allocation.setRemarks(rs.getString("remarks"));
                    allocation.setEmployeeTransferPreference(rs.getString("employee_transfer_preference"));
                    allocation.setEmployeeTransferNote(rs.getString("employee_transfer_note"));
                    allocation.setEmployeeTransferRequestedAt(rs.getString("employee_transfer_requested_at"));
                }
            }
        } catch (Exception e) {
            System.err.println("[AssetAllocationDAO] getAllocationById failed: " + e.getMessage());
            e.printStackTrace();
        }

        return allocation;
    }

    private boolean isActiveEmployee(Connection con, int employeeId) throws Exception {
        String sql = "SELECT employee_id FROM employees WHERE employee_id = ? AND employee_status = 'ACTIVE' FOR UPDATE";
        try (PreparedStatement ps = con.prepareStatement(sql)) {
            ps.setInt(1, employeeId);
            try (ResultSet rs = ps.executeQuery()) {
                return rs.next();
            }
        }
    }

    private boolean isAvailableAsset(Connection con, int assetId) throws Exception {
        String sql = "SELECT asset_id FROM assets WHERE asset_id = ? AND asset_status = 'AVAILABLE' FOR UPDATE";
        try (PreparedStatement ps = con.prepareStatement(sql)) {
            ps.setInt(1, assetId);
            try (ResultSet rs = ps.executeQuery()) {
                return rs.next();
            }
        }
    }

    private int getAssetLocationId(Connection con, int assetId) throws Exception {
        String sql = "SELECT COALESCE(location_id, 0) AS location_id FROM assets WHERE asset_id = ?";
        try (PreparedStatement ps = con.prepareStatement(sql)) {
            ps.setInt(1, assetId);
            try (ResultSet rs = ps.executeQuery()) {
                return rs.next() ? rs.getInt("location_id") : 0;
            }
        }
    }

    private String normalizeAllocationStatus(String status) {
        return "RETURNED".equalsIgnoreCase(clean(status)) ? "RETURNED" : "ALLOCATED";
    }

    private String emptyToNull(String value) {
        String text = clean(value);
        return text.isEmpty() ? null : text;
    }

    private String clean(String value) {
        return value == null ? "" : value.trim();
    }

    // The WHERE clause deliberately checks employee_id and allocation_status
    // itself rather than trusting the caller to have already verified them -
    // this is the actual ownership control that stops an employee from
    // setting a transfer preference on an allocation that isn't theirs (or
    // isn't currently active), even if a spoofed allocationId is submitted.
    public boolean submitEmployeeTransferPreference(int allocationId, int employeeId, String preference, String note) {
        String normalizedPreference = "RETURN".equalsIgnoreCase(clean(preference)) ? "RETURN" : "RETAIN";

        String sql = "UPDATE asset_allocation SET "
                + "employee_transfer_preference = ?, employee_transfer_note = ?, employee_transfer_requested_at = NOW() "
                + "WHERE allocation_id = ? AND employee_id = ? AND allocation_status = 'ALLOCATED'";

        try (Connection con = DBConnection.getConnection();
             PreparedStatement ps = con.prepareStatement(sql)) {

            ps.setString(1, normalizedPreference);
            ps.setString(2, clean(note));
            ps.setInt(3, allocationId);
            ps.setInt(4, employeeId);

            return ps.executeUpdate() > 0;
        } catch (Exception e) {
            System.err.println("[AssetAllocationDAO] submitEmployeeTransferPreference failed: " + e.getMessage());
            e.printStackTrace();
        }

        return false;
    }

    // Called by TransferEmployeeServlet after an allocation has actually been
    // processed (retained or returned) as part of a finalized transfer, so a
    // stale "employee requested X" badge doesn't linger and confuse a future
    // transfer cycle.
    public void clearEmployeeTransferPreference(int allocationId) {
        String sql = "UPDATE asset_allocation SET "
                + "employee_transfer_preference = NULL, employee_transfer_note = NULL, employee_transfer_requested_at = NULL "
                + "WHERE allocation_id = ?";

        try (Connection con = DBConnection.getConnection();
             PreparedStatement ps = con.prepareStatement(sql)) {

            ps.setInt(1, allocationId);
            ps.executeUpdate();
        } catch (Exception e) {
            System.err.println("[AssetAllocationDAO] clearEmployeeTransferPreference failed: " + e.getMessage());
            e.printStackTrace();
        }
    }
}
