package com.mycompany.asset_management_system_ams;

import jakarta.servlet.ServletException;
import jakarta.servlet.annotation.WebServlet;
import jakarta.servlet.http.HttpServlet;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import jakarta.servlet.http.HttpSession;

import java.io.IOException;
import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;

@WebServlet(name = "UpdateQrTaggingStatusServlet", urlPatterns = {"/UpdateQrTaggingStatusServlet"})
public class UpdateQrTaggingStatusServlet extends HttpServlet {

    @Override
    protected void doPost(HttpServletRequest request, HttpServletResponse response)
            throws ServletException, IOException {

        HttpSession session = request.getSession(false);

        if (session == null
                || session.getAttribute("username") == null
                || session.getAttribute("role") == null) {
            response.sendRedirect("login.jsp");
            return;
        }

        String role = String.valueOf(session.getAttribute("role"));

        if (!("SUPER_ADMIN".equals(role) || "ADMIN".equals(role)) && !"ASSET_MANAGER".equalsIgnoreCase(role)) {
            response.sendRedirect("dashboard.jsp?access=denied");
            return;
        }

        String assetIdText = request.getParameter("asset_id");
        String printStatus = normalize(request.getParameter("print_status"), "PENDING");
        String tagStatus = normalize(request.getParameter("tag_status"), "PENDING");
        String remarks = request.getParameter("remarks");

        if (assetIdText == null || assetIdText.trim().isEmpty()) {
            response.sendRedirect("qr_tagging_status.jsp?error=failed");
            return;
        }

        int assetId;

        try {
            assetId = Integer.parseInt(assetIdText.trim());
        } catch (Exception e) {
            response.sendRedirect("qr_tagging_status.jsp?error=failed");
            return;
        }

        if (!isAllowedPrintStatus(printStatus) || !isAllowedTagStatus(tagStatus)) {
            response.sendRedirect("qr_tagging_status.jsp?error=failed");
            return;
        }

        if (remarks == null) {
            remarks = "";
        }

        try (Connection con = DBConnection.getConnection()) {
            ensureTaggingTable(con);

            String token = getAssetToken(con, assetId);

            if (token == null || token.trim().isEmpty()) {
                response.sendRedirect("qr_tagging_status.jsp?error=failed");
                return;
            }

            int userId = getSessionUserId(session);

            String sql =
                    "INSERT INTO asset_qr_tagging_status "
                    + "(asset_id, qr_public_token, print_status, tag_status, printed_by_user_id, tagged_by_user_id, "
                    + "printed_at, tagged_at, remarks) "
                    + "VALUES (?, ?, ?, ?, "
                    + "CASE WHEN ? = 'PRINTED' THEN ? ELSE NULL END, "
                    + "CASE WHEN ? = 'TAGGED' THEN ? ELSE NULL END, "
                    + "CASE WHEN ? = 'PRINTED' THEN CURRENT_TIMESTAMP ELSE NULL END, "
                    + "CASE WHEN ? = 'TAGGED' THEN CURRENT_TIMESTAMP ELSE NULL END, "
                    + "?) "
                    + "ON DUPLICATE KEY UPDATE "
                    + "qr_public_token = VALUES(qr_public_token), "
                    + "print_status = VALUES(print_status), "
                    + "tag_status = VALUES(tag_status), "
                    + "printed_by_user_id = CASE WHEN VALUES(print_status) = 'PRINTED' THEN ? ELSE printed_by_user_id END, "
                    + "tagged_by_user_id = CASE WHEN VALUES(tag_status) = 'TAGGED' THEN ? ELSE tagged_by_user_id END, "
                    + "printed_at = CASE WHEN VALUES(print_status) = 'PRINTED' THEN COALESCE(printed_at, CURRENT_TIMESTAMP) ELSE printed_at END, "
                    + "tagged_at = CASE WHEN VALUES(tag_status) = 'TAGGED' THEN COALESCE(tagged_at, CURRENT_TIMESTAMP) ELSE tagged_at END, "
                    + "remarks = VALUES(remarks), "
                    + "updated_at = CURRENT_TIMESTAMP";

            try (PreparedStatement ps = con.prepareStatement(sql)) {
                ps.setInt(1, assetId);
                ps.setString(2, token);
                ps.setString(3, printStatus);
                ps.setString(4, tagStatus);

                ps.setString(5, printStatus);
                ps.setInt(6, userId);

                ps.setString(7, tagStatus);
                ps.setInt(8, userId);

                ps.setString(9, printStatus);
                ps.setString(10, tagStatus);
                ps.setString(11, remarks.trim());

                ps.setInt(12, userId);
                ps.setInt(13, userId);

                ps.executeUpdate();
            }

            writeAuditCompat(con, session, assetId, "QR_TAGGING_STATUS_UPDATE",
                    "QR tagging status updated. Print Status: " + printStatus
                    + ", Tag Status: " + tagStatus
                    + ", Remarks: " + remarks.trim());

            response.sendRedirect("qr_tagging_status.jsp?msg=updated");

        } catch (Exception e) {
            System.err.println("QR Module DB Error: " + e.getMessage());
            response.sendRedirect("qr_tagging_status.jsp?error=failed");
        }
    }

    private void ensureTaggingTable(Connection con) throws Exception {
        String sql =
                "CREATE TABLE IF NOT EXISTS asset_qr_tagging_status ("
                + "tagging_id INT AUTO_INCREMENT PRIMARY KEY, "
                + "asset_id INT NOT NULL UNIQUE, "
                + "qr_public_token VARCHAR(120), "
                + "print_status VARCHAR(40) DEFAULT 'PENDING', "
                + "tag_status VARCHAR(40) DEFAULT 'PENDING', "
                + "printed_by_user_id INT, "
                + "tagged_by_user_id INT, "
                + "printed_at TIMESTAMP NULL, "
                + "tagged_at TIMESTAMP NULL, "
                + "remarks VARCHAR(500), "
                + "created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP, "
                + "updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP, "
                + "INDEX idx_qr_tagging_asset (asset_id), "
                + "INDEX idx_qr_tagging_print_status (print_status), "
                + "INDEX idx_qr_tagging_tag_status (tag_status)"
                + ") ENGINE=InnoDB DEFAULT CHARSET=utf8mb4";

        try (PreparedStatement ps = con.prepareStatement(sql)) {
            ps.executeUpdate();
        }
    }

    private String getAssetToken(Connection con, int assetId) throws Exception {
        String sql =
                "SELECT qr_public_token FROM assets "
                + "WHERE asset_id = ? "
                + "AND qr_public_token IS NOT NULL "
                + "AND TRIM(qr_public_token) <> '' "
                + "LIMIT 1";

        try (PreparedStatement ps = con.prepareStatement(sql)) {
            ps.setInt(1, assetId);

            try (ResultSet rs = ps.executeQuery()) {
                if (rs.next()) {
                    return rs.getString("qr_public_token");
                }
            }
        }

        return "";
    }

    private String normalize(String value, String fallback) {
        if (value == null || value.trim().isEmpty()) {
            return fallback;
        }

        return value.trim().toUpperCase().replace(" ", "_");
    }

    private boolean isAllowedPrintStatus(String value) {
        return "PENDING".equals(value)
                || "PRINTED".equals(value)
                || "REPRINT_REQUIRED".equals(value);
    }

    private boolean isAllowedTagStatus(String value) {
        return "PENDING".equals(value)
                || "TAGGED".equals(value)
                || "DAMAGED".equals(value)
                || "REMOVED".equals(value);
    }

    private int getSessionUserId(HttpSession session) {
        // Default of 0 (not 1) on a missing session attribute - see the same
        // fix applied across the Asset Requests and Physical Verification modules.
        Object value = session.getAttribute("user_id");

        if (value == null) {
            value = session.getAttribute("userId");
        }

        if (value == null) {
            return 0;
        }

        try {
            return Integer.parseInt(String.valueOf(value));
        } catch (Exception e) {
            return 0;
        }
    }

    private void writeAuditCompat(Connection con, HttpSession session, int recordId, String action, String details) {
        try {
            if (tableHasColumn(con, "audit_logs", "module_name")) {
                String sql =
                        "INSERT INTO audit_logs "
                        + "(user_id, username, user_role, module_name, action_type, record_id, action_details, ip_address, user_agent) "
                        + "VALUES (?, ?, ?, 'QR_TAGGING', ?, ?, ?, 'SYSTEM', 'UpdateQrTaggingStatusServlet')";

                try (PreparedStatement ps = con.prepareStatement(sql)) {
                    ps.setInt(1, getSessionUserId(session));
                    ps.setString(2, String.valueOf(session.getAttribute("username")));
                    ps.setString(3, String.valueOf(session.getAttribute("role")));
                    ps.setString(4, action);
                    ps.setInt(5, recordId);
                    ps.setString(6, details);

                    ps.executeUpdate();
                }

            } else if (tableHasColumn(con, "audit_logs", "table_name")) {
                String sql =
                        "INSERT INTO audit_logs "
                        + "(user_id, action, table_name, record_id, remarks) "
                        + "VALUES (?, ?, 'asset_qr_tagging_status', ?, ?)";

                try (PreparedStatement ps = con.prepareStatement(sql)) {
                    ps.setInt(1, getSessionUserId(session));
                    ps.setString(2, action);
                    ps.setInt(3, recordId);
                    ps.setString(4, details);

                    ps.executeUpdate();
                }
            }

        } catch (Exception e) {
            System.err.println("QR Module DB Error: " + e.getMessage());
        }
    }

    private boolean tableHasColumn(Connection con, String tableName, String columnName) {
        String sql =
                "SELECT COUNT(*) FROM information_schema.columns "
                + "WHERE table_schema = DATABASE() AND table_name = ? AND column_name = ?";

        try (PreparedStatement ps = con.prepareStatement(sql)) {
            ps.setString(1, tableName);
            ps.setString(2, columnName);

            try (ResultSet rs = ps.executeQuery()) {
                return rs.next() && rs.getInt(1) > 0;
            }

        } catch (Exception e) {
            System.err.println("QR Module DB Error: " + e.getMessage());
        }

        return false;
    }
}