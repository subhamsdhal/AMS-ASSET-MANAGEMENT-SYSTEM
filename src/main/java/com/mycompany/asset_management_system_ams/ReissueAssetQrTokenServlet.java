package com.mycompany.asset_management_system_ams;

import jakarta.servlet.ServletException;
import jakarta.servlet.annotation.WebServlet;
import jakarta.servlet.http.HttpServlet;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import jakarta.servlet.http.HttpSession;

import java.io.IOException;
import java.security.SecureRandom;
import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;

@WebServlet(name = "ReissueAssetQrTokenServlet", urlPatterns = {"/ReissueAssetQrTokenServlet"})
public class ReissueAssetQrTokenServlet extends HttpServlet {

    private static final SecureRandom RANDOM = new SecureRandom();
    private static final String TOKEN_CHARS = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";

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
        String reason = request.getParameter("reason");

        if (assetIdText == null || assetIdText.trim().isEmpty()) {
            response.sendRedirect("qr_token_reissue.jsp?error=failed");
            return;
        }

        if (reason == null || reason.trim().isEmpty()) {
            response.sendRedirect("qr_token_reissue.jsp?error=missing_reason");
            return;
        }

        int assetId;

        try {
            assetId = Integer.parseInt(assetIdText.trim());
        } catch (Exception e) {
            response.sendRedirect("qr_token_reissue.jsp?error=failed");
            return;
        }

        if (!QrUrlUtil.isPublicBaseUrlReady()) {
            response.sendRedirect("qr_token_reissue.jsp?error=public_base_url");
            return;
        }

        try (Connection con = DBConnection.getConnection()) {
            ensureHistoryTable(con);

            AssetQrInfo oldInfo = getAssetQrInfo(con, assetId);

            if (oldInfo == null || oldInfo.assetCode == null || oldInfo.assetCode.trim().isEmpty()) {
                response.sendRedirect("qr_token_reissue.jsp?error=failed");
                return;
            }

            String newToken = generateUniqueToken(con);
            String newUrl = buildPublicUrl(request, newToken);

            insertHistory(con, oldInfo, newToken, newUrl, reason.trim(), session);
            QrSnapshotService.invalidateSnapshotQuietly(con, assetId, oldInfo.oldToken);

            String updateSql =
                    "UPDATE assets "
                    + "SET qr_public_token = ?, qr_code = ?, updated_by = ?, updated_at = CURRENT_TIMESTAMP "
                    + "WHERE asset_id = ?";

            try (PreparedStatement ps = con.prepareStatement(updateSql)) {
                ps.setString(1, newToken);
                ps.setString(2, newUrl);
                ps.setInt(3, getSessionUserId(session));
                ps.setInt(4, assetId);
                ps.executeUpdate();
            }

            QrSnapshotService.syncAssetQuietly(con, assetId);

            writeAuditCompat(con, session, assetId, "QR_TOKEN_REISSUE",
                    "QR token reissued for asset " + oldInfo.assetCode
                    + ". Old token: " + safe(oldInfo.oldToken)
                    + ". New token: " + newToken
                    + ". Reason: " + reason.trim());

            response.sendRedirect("qr_token_reissue.jsp?msg=reissued");

        } catch (Exception e) {
            System.err.println("QR Module DB Error: " + e.getMessage());
            response.sendRedirect("qr_token_reissue.jsp?error=failed");
        }
    }

    private static class AssetQrInfo {
        int assetId;
        String assetCode;
        String assetName;
        String oldToken;
        String oldUrl;
    }

    private AssetQrInfo getAssetQrInfo(Connection con, int assetId) throws Exception {
        String sql =
                "SELECT asset_id, asset_code, asset_name, qr_public_token, qr_code "
                + "FROM assets WHERE asset_id = ? LIMIT 1";

        try (PreparedStatement ps = con.prepareStatement(sql)) {
            ps.setInt(1, assetId);

            try (ResultSet rs = ps.executeQuery()) {
                if (rs.next()) {
                    AssetQrInfo info = new AssetQrInfo();

                    info.assetId = rs.getInt("asset_id");
                    info.assetCode = rs.getString("asset_code");
                    info.assetName = rs.getString("asset_name");
                    info.oldToken = rs.getString("qr_public_token");
                    info.oldUrl = rs.getString("qr_code");

                    return info;
                }
            }
        }

        return null;
    }

    private void ensureHistoryTable(Connection con) throws Exception {
        String sql =
                "CREATE TABLE IF NOT EXISTS asset_qr_token_history ("
                + "history_id INT AUTO_INCREMENT PRIMARY KEY, "
                + "asset_id INT NOT NULL, "
                + "asset_code VARCHAR(100), "
                + "asset_name VARCHAR(255), "
                + "old_qr_public_token VARCHAR(120), "
                + "new_qr_public_token VARCHAR(120), "
                + "old_qr_code TEXT, "
                + "new_qr_code TEXT, "
                + "reissue_reason VARCHAR(500), "
                + "reissued_by_user_id INT, "
                + "reissued_by_username VARCHAR(100), "
                + "reissued_by_role VARCHAR(80), "
                + "created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP, "
                + "INDEX idx_asset_qr_token_history_asset (asset_id), "
                + "INDEX idx_asset_qr_token_history_old_token (old_qr_public_token), "
                + "INDEX idx_asset_qr_token_history_new_token (new_qr_public_token)"
                + ") ENGINE=InnoDB DEFAULT CHARSET=utf8mb4";

        try (PreparedStatement ps = con.prepareStatement(sql)) {
            ps.executeUpdate();
        }
    }

    private void insertHistory(Connection con, AssetQrInfo oldInfo, String newToken, String newUrl,
            String reason, HttpSession session) throws Exception {

        String sql =
                "INSERT INTO asset_qr_token_history "
                + "(asset_id, asset_code, asset_name, old_qr_public_token, new_qr_public_token, "
                + "old_qr_code, new_qr_code, reissue_reason, reissued_by_user_id, reissued_by_username, reissued_by_role) "
                + "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)";

        try (PreparedStatement ps = con.prepareStatement(sql)) {
            ps.setInt(1, oldInfo.assetId);
            ps.setString(2, oldInfo.assetCode);
            ps.setString(3, oldInfo.assetName);
            ps.setString(4, oldInfo.oldToken);
            ps.setString(5, newToken);
            ps.setString(6, oldInfo.oldUrl);
            ps.setString(7, newUrl);
            ps.setString(8, reason);
            ps.setInt(9, getSessionUserId(session));
            ps.setString(10, String.valueOf(session.getAttribute("username")));
            ps.setString(11, String.valueOf(session.getAttribute("role")));

            ps.executeUpdate();
        }
    }

    private String generateUniqueToken(Connection con) throws Exception {
        String token;

        do {
            token = "ECORQR" + randomString(20);
        } while (tokenExists(con, token));

        return token;
    }

    private String randomString(int length) {
        StringBuilder sb = new StringBuilder();

        for (int i = 0; i < length; i++) {
            sb.append(TOKEN_CHARS.charAt(RANDOM.nextInt(TOKEN_CHARS.length())));
        }

        return sb.toString();
    }

    private boolean tokenExists(Connection con, String token) throws Exception {
        String sql =
                "SELECT COUNT(*) FROM assets WHERE qr_public_token = ? "
                + "UNION ALL "
                + "SELECT COUNT(*) FROM asset_qr_token_history WHERE old_qr_public_token = ? OR new_qr_public_token = ?";

        int total = 0;

        try (PreparedStatement ps = con.prepareStatement(sql)) {
            ps.setString(1, token);
            ps.setString(2, token);
            ps.setString(3, token);

            try (ResultSet rs = ps.executeQuery()) {
                while (rs.next()) {
                    total += rs.getInt(1);
                }
            }
        }

        return total > 0;
    }

    private String buildPublicUrl(HttpServletRequest request, String token) {
        return QrUrlUtil.buildPublicAssetUrl(request, token);
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

    private String safe(String value) {
        return value == null ? "" : value;
    }

    private void writeAuditCompat(Connection con, HttpSession session, int recordId, String action, String details) {
        try {
            if (tableHasColumn(con, "audit_logs", "module_name")) {
                String sql =
                        "INSERT INTO audit_logs "
                        + "(user_id, username, user_role, module_name, action_type, record_id, action_details, ip_address, user_agent) "
                        + "VALUES (?, ?, ?, 'assets', ?, ?, ?, 'SYSTEM', 'ReissueAssetQrTokenServlet')";

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
                        + "VALUES (?, ?, 'assets', ?, ?)";

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
