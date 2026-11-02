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

@WebServlet(name = "GenerateAssetQrServlet", urlPatterns = {"/GenerateAssetQrServlet"})
public class GenerateAssetQrServlet extends HttpServlet {

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

        if (assetIdText == null || assetIdText.trim().isEmpty()) {
            assetIdText = request.getParameter("id");
        }

        int assetId;

        try {
            assetId = Integer.parseInt(assetIdText);
        } catch (Exception e) {
            response.sendRedirect("assets.jsp?error=invalid_qr_asset");
            return;
        }

        if (!QrUrlUtil.isPublicBaseUrlReady()) {
            response.sendRedirect("asset_qr_card.jsp?id=" + assetId + "&error=public_base_url");
            return;
        }

        try (Connection con = DBConnection.getConnection()) {

            String assetCode = getAssetCode(con, assetId);

            if (assetCode == null || assetCode.trim().isEmpty()) {
                response.sendRedirect("assets.jsp?error=asset_notfound");
                return;
            }

            String token = generateUniqueToken(con);
            String publicUrl = buildPublicUrl(request, token);

            String sql = "UPDATE assets SET qr_public_token = ?, qr_code = ?, updated_by = ?, updated_at = CURRENT_TIMESTAMP WHERE asset_id = ?";

            try (PreparedStatement ps = con.prepareStatement(sql)) {
                ps.setString(1, token);
                ps.setString(2, publicUrl);
                ps.setInt(3, getSessionUserId(session));
                ps.setInt(4, assetId);

                ps.executeUpdate();
            }

            QrSnapshotService.syncAssetQuietly(con, assetId);

            writeAuditCompat(con, session, assetId, "QR_GENERATE",
                    "Dynamic QR token generated/refreshed for asset " + assetCode + ". Token: " + token);

            response.sendRedirect("asset_qr_card.jsp?id=" + assetId + "&msg=qrgenerated");

        } catch (Exception e) {
            System.err.println("QR Module DB Error: " + e.getMessage());
            response.sendRedirect("asset_qr_card.jsp?id=" + assetId + "&error=qrgeneratefailed");
        }
    }

    private String getAssetCode(Connection con, int assetId) throws Exception {
        String sql = "SELECT asset_code FROM assets WHERE asset_id = ? LIMIT 1";

        try (PreparedStatement ps = con.prepareStatement(sql)) {
            ps.setInt(1, assetId);

            try (ResultSet rs = ps.executeQuery()) {
                if (rs.next()) {
                    return rs.getString("asset_code");
                }
            }
        }

        return "";
    }

    private String generateUniqueToken(Connection con) throws Exception {
        String token;

        do {
            token = "ECORQR" + randomString(18);
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
        String sql = "SELECT COUNT(*) FROM assets WHERE qr_public_token = ?";

        try (PreparedStatement ps = con.prepareStatement(sql)) {
            ps.setString(1, token);

            try (ResultSet rs = ps.executeQuery()) {
                return rs.next() && rs.getInt(1) > 0;
            }
        }
    }

    private String buildPublicUrl(HttpServletRequest request, String token) {
        return QrUrlUtil.buildPublicAssetUrl(request, token);
    }

    private int getSessionUserId(HttpSession session) {
        // Default of 0 (not 1) on a missing session attribute - defaulting to 1
        // would silently mis-attribute assets.updated_by and the audit log entry
        // to whichever real account happens to be user_id 1. Same fix applied
        // across the Asset Requests and Physical Verification modules.
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
                        + "VALUES (?, ?, ?, 'assets', ?, ?, ?, 'SYSTEM', 'GenerateAssetQrServlet')";

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
