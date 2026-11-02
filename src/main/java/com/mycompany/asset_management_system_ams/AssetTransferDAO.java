package com.mycompany.asset_management_system_ams;

import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.Statement;
import java.sql.Types;
import java.time.LocalDate;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

/**
 * Employee-to-employee asset transfer workflow. Maker-checker, same shape as
 * AssetDAO's disposal workflow: an employee (or Asset Manager/Admin/Super
 * Admin on their behalf) proposes transferring one of the employee's
 * allocated assets to a named colleague via submitTransfer(); a Super Admin/
 * Admin/Asset Manager separately approves or rejects it via reviewTransfer().
 *
 * asset_transfer_requests is the workflow state machine (PENDING/REJECTED/
 * COMPLETED). asset_transfers - a pre-existing, previously-unpopulated table
 * confirmed live on this database (see migration 010's own comment for how
 * that was discovered) - is the append-only completed-transfer log that
 * CopilotToolExecutor.getAssetTransferHistory() already reads; approval is
 * the only path that ever writes to it, and its own shape is left completely
 * untouched by this class.
 */
public class AssetTransferDAO {

    /**
     * Maker stage. Validates the allocation is currently ALLOCATED to
     * fromEmployeeId (derived from the allocation itself, not trusted from
     * the caller), the target is a different, active employee, and no other
     * PENDING request already exists for this exact allocation.
     */
    public int submitTransfer(int allocationId, int toEmployeeId, String transferReason, int requestedByUserId) {
        Connection con = null;

        try {
            con = DBConnection.getConnection();
            con.setAutoCommit(false);

            int assetId = 0, fromEmployeeId = 0;
            try (PreparedStatement ps = con.prepareStatement(
                    "SELECT asset_id, employee_id FROM asset_allocation WHERE allocation_id = ? "
                    + "AND allocation_status = 'ALLOCATED' FOR UPDATE")) {
                ps.setInt(1, allocationId);
                try (ResultSet rs = ps.executeQuery()) {
                    if (rs.next()) {
                        assetId = rs.getInt(1);
                        fromEmployeeId = rs.getInt(2);
                    }
                }
            }

            if (assetId <= 0 || fromEmployeeId <= 0 || fromEmployeeId == toEmployeeId) {
                con.rollback();
                return 0;
            }

            if (!isActiveEmployee(con, toEmployeeId)) {
                con.rollback();
                return 0;
            }

            try (PreparedStatement ps = con.prepareStatement(
                    "SELECT COUNT(*) FROM asset_transfer_requests WHERE allocation_id = ? AND request_status = 'PENDING'")) {
                ps.setInt(1, allocationId);
                try (ResultSet rs = ps.executeQuery()) {
                    if (rs.next() && rs.getInt(1) > 0) {
                        con.rollback();
                        return 0;
                    }
                }
            }

            int requestId = 0;
            String insertSql = "INSERT INTO asset_transfer_requests "
                    + "(allocation_id, asset_id, from_employee_id, to_employee_id, transfer_reason, "
                    + "request_status, requested_by, requested_date) "
                    + "VALUES (?, ?, ?, ?, ?, 'PENDING', ?, ?)";

            try (PreparedStatement ps = con.prepareStatement(insertSql, Statement.RETURN_GENERATED_KEYS)) {
                ps.setInt(1, allocationId);
                ps.setInt(2, assetId);
                ps.setInt(3, fromEmployeeId);
                ps.setInt(4, toEmployeeId);
                ps.setString(5, limitText(transferReason, 255));
                if (requestedByUserId <= 0) {
                    ps.setNull(6, Types.INTEGER);
                } else {
                    ps.setInt(6, requestedByUserId);
                }
                ps.setString(7, LocalDate.now().toString());

                if (ps.executeUpdate() > 0) {
                    try (ResultSet keys = ps.getGeneratedKeys()) {
                        if (keys.next()) {
                            requestId = keys.getInt(1);
                        }
                    }
                }
            }

            if (requestId <= 0) {
                con.rollback();
                return 0;
            }

            con.commit();
            return requestId;
        } catch (Exception e) {
            System.err.println("[AssetTransferDAO] submitTransfer failed: " + e.getMessage());
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
                System.err.println("[AssetTransferDAO] submitTransfer failed: " + e.getMessage());
                e.printStackTrace();
            }
        }

        return 0;
    }

    /**
     * Checker stage. Approving executes the transfer atomically: closes the
     * source allocation (RETURNED), opens a new ALLOCATED row for the
     * receiving employee (assets.asset_status is never touched - it stays
     * ALLOCATED throughout, the asset moves directly from one holder to the
     * other rather than passing through AVAILABLE), and appends the outcome
     * to the asset_transfers log. Rejecting only updates the request row.
     *
     * requiredCurrentStatus='PENDING' in the source-allocation lookup and in
     * the request UPDATE's WHERE clause is the same idempotency/concurrency
     * guard pattern used throughout this codebase - a stale or replayed
     * review action becomes a safe no-op instead of double-processing.
     *
     * @param action "APPROVE" or "REJECT"
     */
    public boolean reviewTransfer(int requestId, String action, int reviewerUserId, String remarks) {
        boolean approve = "APPROVE".equalsIgnoreCase(clean(action));
        Connection con = null;

        try {
            con = DBConnection.getConnection();
            con.setAutoCommit(false);

            int allocationId = 0, assetId = 0, fromEmployeeId = 0, toEmployeeId = 0;
            String transferReason = null;

            try (PreparedStatement ps = con.prepareStatement(
                    "SELECT allocation_id, asset_id, from_employee_id, to_employee_id, transfer_reason "
                    + "FROM asset_transfer_requests WHERE request_id = ? AND request_status = 'PENDING' FOR UPDATE")) {
                ps.setInt(1, requestId);
                try (ResultSet rs = ps.executeQuery()) {
                    if (rs.next()) {
                        allocationId = rs.getInt(1);
                        assetId = rs.getInt(2);
                        fromEmployeeId = rs.getInt(3);
                        toEmployeeId = rs.getInt(4);
                        transferReason = rs.getString(5);
                    }
                }
            }

            if (allocationId <= 0) {
                con.rollback();
                return false;
            }

            if (!approve) {
                try (PreparedStatement ps = con.prepareStatement(
                        "UPDATE asset_transfer_requests SET request_status = 'REJECTED', reviewed_by = ?, "
                        + "reviewed_date = ?, remarks = ? WHERE request_id = ? AND request_status = 'PENDING'")) {
                    if (reviewerUserId <= 0) {
                        ps.setNull(1, Types.INTEGER);
                    } else {
                        ps.setInt(1, reviewerUserId);
                    }
                    ps.setString(2, LocalDate.now().toString());
                    ps.setString(3, limitText(remarks, 255));
                    ps.setInt(4, requestId);

                    if (ps.executeUpdate() <= 0) {
                        con.rollback();
                        return false;
                    }
                }

                con.commit();
                return true;
            }

            // Approve: the source allocation must still be ALLOCATED and still
            // belong to fromEmployeeId - re-verified here (not just trusted
            // from the request row) in case it changed between submission and
            // review (e.g. a return processed in the meantime).
            int lockedAssetId = 0;
            try (PreparedStatement ps = con.prepareStatement(
                    "SELECT asset_id FROM asset_allocation WHERE allocation_id = ? AND employee_id = ? "
                    + "AND allocation_status = 'ALLOCATED' FOR UPDATE")) {
                ps.setInt(1, allocationId);
                ps.setInt(2, fromEmployeeId);
                try (ResultSet rs = ps.executeQuery()) {
                    if (rs.next()) {
                        lockedAssetId = rs.getInt(1);
                    }
                }
            }

            if (lockedAssetId <= 0) {
                con.rollback();
                return false;
            }

            try (PreparedStatement ps = con.prepareStatement(
                    "UPDATE asset_allocation SET allocation_status = 'RETURNED', return_date = ? "
                    + "WHERE allocation_id = ? AND allocation_status = 'ALLOCATED'")) {
                ps.setString(1, LocalDate.now().toString());
                ps.setInt(2, allocationId);
                if (ps.executeUpdate() <= 0) {
                    con.rollback();
                    return false;
                }
            }

            int issueLocationId = getAssetLocationId(con, assetId);
            int newAllocationId = 0;

            String insertAllocSql = "INSERT INTO asset_allocation "
                    + "(asset_id, employee_id, allocation_date, allocation_status, issue_condition, "
                    + "issue_location_id, issued_by, remarks) "
                    + "VALUES (?, ?, ?, 'ALLOCATED', 'GOOD', ?, ?, ?)";

            try (PreparedStatement ps = con.prepareStatement(insertAllocSql, Statement.RETURN_GENERATED_KEYS)) {
                ps.setInt(1, assetId);
                ps.setInt(2, toEmployeeId);
                ps.setString(3, LocalDate.now().toString());
                if (issueLocationId > 0) {
                    ps.setInt(4, issueLocationId);
                } else {
                    ps.setNull(4, Types.INTEGER);
                }
                if (reviewerUserId <= 0) {
                    ps.setNull(5, Types.INTEGER);
                } else {
                    ps.setInt(5, reviewerUserId);
                }
                ps.setString(6, "Received via employee-to-employee transfer (request #" + requestId + ")");

                if (ps.executeUpdate() > 0) {
                    try (ResultSet keys = ps.getGeneratedKeys()) {
                        if (keys.next()) {
                            newAllocationId = keys.getInt(1);
                        }
                    }
                }
            }

            if (newAllocationId <= 0) {
                con.rollback();
                return false;
            }
            // assets.asset_status is deliberately left untouched here - it was
            // 'ALLOCATED' before this transaction and stays 'ALLOCATED' after
            // it; the asset never passes through AVAILABLE mid-transfer.

            long transferLogId = 0;
            String insertLogSql = "INSERT INTO asset_transfers "
                    + "(asset_id, source_allocation_id, target_allocation_id, from_employee_id, to_employee_id, "
                    + "transfer_date, transfer_reason, authorized_by) "
                    + "VALUES (?, ?, ?, ?, ?, ?, ?, ?)";

            try (PreparedStatement ps = con.prepareStatement(insertLogSql, Statement.RETURN_GENERATED_KEYS)) {
                ps.setInt(1, assetId);
                ps.setInt(2, allocationId);
                ps.setInt(3, newAllocationId);
                ps.setInt(4, fromEmployeeId);
                ps.setInt(5, toEmployeeId);
                ps.setString(6, LocalDate.now().toString());
                ps.setString(7, limitText(transferReason == null || transferReason.trim().isEmpty()
                        ? "Employee-to-employee transfer" : transferReason, 255));
                if (reviewerUserId <= 0) {
                    ps.setNull(8, Types.INTEGER);
                } else {
                    ps.setInt(8, reviewerUserId);
                }

                if (ps.executeUpdate() > 0) {
                    try (ResultSet keys = ps.getGeneratedKeys()) {
                        if (keys.next()) {
                            transferLogId = keys.getLong(1);
                        }
                    }
                }
            }

            if (transferLogId <= 0) {
                con.rollback();
                return false;
            }

            try (PreparedStatement ps = con.prepareStatement(
                    "UPDATE asset_transfer_requests SET request_status = 'COMPLETED', reviewed_by = ?, "
                    + "reviewed_date = ?, remarks = ?, transfer_id = ? WHERE request_id = ? AND request_status = 'PENDING'")) {
                if (reviewerUserId <= 0) {
                    ps.setNull(1, Types.INTEGER);
                } else {
                    ps.setInt(1, reviewerUserId);
                }
                ps.setString(2, LocalDate.now().toString());
                ps.setString(3, limitText(remarks, 255));
                ps.setLong(4, transferLogId);
                ps.setInt(5, requestId);

                if (ps.executeUpdate() <= 0) {
                    con.rollback();
                    return false;
                }
            }

            con.commit();
            return true;
        } catch (Exception e) {
            System.err.println("[AssetTransferDAO] reviewTransfer failed: " + e.getMessage());
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
                System.err.println("[AssetTransferDAO] reviewTransfer failed: " + e.getMessage());
                e.printStackTrace();
            }
        }

        return false;
    }

    /** Transfer requests currently awaiting a checker's review, newest first. */
    public List<Map<String, String>> getPendingTransfers() {
        List<Map<String, String>> out = new ArrayList<>();
        String sql = "SELECT tr.request_id, tr.allocation_id, a.asset_code, a.asset_name, "
                + "fe.employee_code AS from_code, fe.employee_name AS from_name, "
                + "te.employee_code AS to_code, te.employee_name AS to_name, "
                + "tr.transfer_reason, DATE_FORMAT(tr.requested_date, '%d %b %Y') AS requested_date, "
                + "COALESCE(u.username, 'System') AS requested_by_name "
                + "FROM asset_transfer_requests tr "
                + "JOIN assets a ON tr.asset_id = a.asset_id "
                + "JOIN employees fe ON tr.from_employee_id = fe.employee_id "
                + "JOIN employees te ON tr.to_employee_id = te.employee_id "
                + "LEFT JOIN users u ON tr.requested_by = u.user_id "
                + "WHERE tr.request_status = 'PENDING' "
                + "ORDER BY tr.requested_date DESC, tr.request_id DESC";

        try (Connection con = DBConnection.getConnection();
             PreparedStatement ps = con.prepareStatement(sql);
             ResultSet rs = ps.executeQuery()) {

            while (rs.next()) {
                Map<String, String> row = new HashMap<>();
                row.put("request_id", String.valueOf(rs.getInt("request_id")));
                row.put("allocation_id", String.valueOf(rs.getInt("allocation_id")));
                row.put("asset_code", rs.getString("asset_code"));
                row.put("asset_name", rs.getString("asset_name"));
                row.put("from_code", rs.getString("from_code"));
                row.put("from_name", rs.getString("from_name"));
                row.put("to_code", rs.getString("to_code"));
                row.put("to_name", rs.getString("to_name"));
                row.put("transfer_reason", rs.getString("transfer_reason"));
                row.put("requested_date", rs.getString("requested_date"));
                row.put("requested_by_name", rs.getString("requested_by_name"));
                out.add(row);
            }
        } catch (Exception e) {
            System.err.println("[AssetTransferDAO] getPendingTransfers failed: " + e.getMessage());
            e.printStackTrace();
        }

        return out;
    }

    /** Every transfer request (all statuses), newest first - backs asset_transfers.jsp. */
    public List<Map<String, String>> getAllTransferRequests() {
        List<Map<String, String>> out = new ArrayList<>();
        String sql = "SELECT tr.request_id, a.asset_code, a.asset_name, "
                + "fe.employee_code AS from_code, fe.employee_name AS from_name, "
                + "te.employee_code AS to_code, te.employee_name AS to_name, "
                + "tr.transfer_reason, tr.request_status, "
                + "COALESCE(ru.username, '') AS requested_by_name, "
                + "COALESCE(rvu.username, '') AS reviewed_by_name "
                + "FROM asset_transfer_requests tr "
                + "JOIN assets a ON tr.asset_id = a.asset_id "
                + "JOIN employees fe ON tr.from_employee_id = fe.employee_id "
                + "JOIN employees te ON tr.to_employee_id = te.employee_id "
                + "LEFT JOIN users ru ON tr.requested_by = ru.user_id "
                + "LEFT JOIN users rvu ON tr.reviewed_by = rvu.user_id "
                + "ORDER BY tr.request_id DESC";

        try (Connection con = DBConnection.getConnection();
             PreparedStatement ps = con.prepareStatement(sql);
             ResultSet rs = ps.executeQuery()) {

            while (rs.next()) {
                Map<String, String> row = new HashMap<>();
                row.put("request_id", String.valueOf(rs.getInt("request_id")));
                row.put("asset_code", rs.getString("asset_code"));
                row.put("asset_name", rs.getString("asset_name"));
                row.put("from_code", rs.getString("from_code"));
                row.put("from_name", rs.getString("from_name"));
                row.put("to_code", rs.getString("to_code"));
                row.put("to_name", rs.getString("to_name"));
                row.put("transfer_reason", rs.getString("transfer_reason"));
                row.put("request_status", rs.getString("request_status"));
                row.put("requested_by_name", rs.getString("requested_by_name"));
                row.put("reviewed_by_name", rs.getString("reviewed_by_name"));
                out.add(row);
            }
        } catch (Exception e) {
            System.err.println("[AssetTransferDAO] getAllTransferRequests failed: " + e.getMessage());
            e.printStackTrace();
        }

        return out;
    }

    /** This employee's own transfer requests, as either sender or receiver - backs employee_assets.jsp. */
    public List<Map<String, String>> getTransferRequestsForEmployee(int employeeId) {
        List<Map<String, String>> out = new ArrayList<>();
        String sql = "SELECT tr.request_id, a.asset_code, a.asset_name, "
                + "fe.employee_name AS from_name, te.employee_name AS to_name, "
                + "tr.request_status, tr.transfer_reason, "
                + "DATE_FORMAT(tr.requested_date, '%d %b %Y') AS requested_date, "
                + "CASE WHEN tr.from_employee_id = ? THEN 'OUTGOING' ELSE 'INCOMING' END AS direction "
                + "FROM asset_transfer_requests tr "
                + "JOIN assets a ON tr.asset_id = a.asset_id "
                + "JOIN employees fe ON tr.from_employee_id = fe.employee_id "
                + "JOIN employees te ON tr.to_employee_id = te.employee_id "
                + "WHERE tr.from_employee_id = ? OR tr.to_employee_id = ? "
                + "ORDER BY tr.request_id DESC";

        try (Connection con = DBConnection.getConnection();
             PreparedStatement ps = con.prepareStatement(sql)) {

            ps.setInt(1, employeeId);
            ps.setInt(2, employeeId);
            ps.setInt(3, employeeId);

            try (ResultSet rs = ps.executeQuery()) {
                while (rs.next()) {
                    Map<String, String> row = new HashMap<>();
                    row.put("request_id", String.valueOf(rs.getInt("request_id")));
                    row.put("asset_code", rs.getString("asset_code"));
                    row.put("asset_name", rs.getString("asset_name"));
                    row.put("from_name", rs.getString("from_name"));
                    row.put("to_name", rs.getString("to_name"));
                    row.put("request_status", rs.getString("request_status"));
                    row.put("transfer_reason", rs.getString("transfer_reason"));
                    row.put("requested_date", rs.getString("requested_date"));
                    row.put("direction", rs.getString("direction"));
                    out.add(row);
                }
            }
        } catch (Exception e) {
            System.err.println("[AssetTransferDAO] getTransferRequestsForEmployee failed: " + e.getMessage());
            e.printStackTrace();
        }

        return out;
    }

    private boolean isActiveEmployee(Connection con, int employeeId) throws Exception {
        String sql = "SELECT employee_id FROM employees WHERE employee_id = ? AND employee_status = 'ACTIVE'";
        try (PreparedStatement ps = con.prepareStatement(sql)) {
            ps.setInt(1, employeeId);
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

    private String clean(String value) {
        return value == null ? "" : value.trim();
    }

    private String limitText(String value, int max) {
        String text = clean(value);
        return text.length() > max ? text.substring(0, max) : text;
    }
}
