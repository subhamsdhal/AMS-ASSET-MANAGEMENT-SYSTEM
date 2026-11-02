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
import java.util.ArrayList;
import java.util.List;

@WebServlet(name = "BulkGenerateAssetQrServlet", urlPatterns = {"/BulkGenerateAssetQrServlet"})
public class BulkGenerateAssetQrServlet extends HttpServlet {

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

        String mode = request.getParameter("mode");

        if (mode == null || mode.trim().isEmpty()) {
            mode = "selected";
        }

        mode = mode.trim().toLowerCase();

        if (!QrUrlUtil.isPublicBaseUrlReady()) {
            response.sendRedirect("qr_bulk_generate.jsp?error=public_base_url");
            return;
        }

        List<Integer> assetIds = new ArrayList<>();

        try (Connection con = DBConnection.getConnection()) {

            if ("missing".equals(mode)) {
                assetIds = getMissingQrAssetIds(con);
            } else {
                String[] selectedIds = request.getParameterValues("asset_ids");

                if (selectedIds != null) {
                    for (String idText : selectedIds) {
                        try {
                            int assetId = Integer.parseInt(idText);

                            if (assetId > 0) {
                                assetIds.add(assetId);
                            }

                        } catch (Exception ignored) {
                        }
                    }
                }
            }

            if (assetIds.isEmpty()) {
                response.sendRedirect("qr_bulk_generate.jsp?error=none_selected");
                return;
            }

            int generatedCount = 0;

            for (Integer assetId : assetIds) {
                String assetCode = getAssetCode(con, assetId);

                if (assetCode == null || assetCode.trim().isEmpty()) {
                    continue;
                }

                String token = generateUniqueToken(con);
                String publicUrl = buildPublicUrl(request, token);

                String updateSql =
                        "UPDATE assets "
                        + "SET qr_public_token = ?, qr_code = ?, updated_by = ?, updated_at = CURRENT_TIMESTAMP "
                        + "WHERE asset_id = ?";

                try (PreparedStatement ps = con.prepareStatement(updateSql)) {
                    ps.setString(1, token);
                    ps.setString(2, publicUrl);
                    ps.setInt(3, getSessionUserId(session));
                    ps.setInt(4, assetId);

                    int updated = ps.executeUpdate();

                    if (updated > 0) {
                        QrSnapshotService.syncAssetQuietly(con, assetId);
                        generatedCount++;
                        writeAuditCompat(con, session, assetId, "QR_BULK_GENERATE",
                                "Bulk QR generated/refreshed for asset " + assetCode + ". Token: " + token);
                    }
                }
            }

            response.sendRedirect("qr_bulk_generate.jsp?msg=bulk_generated&count=" + generatedCount);

        } catch (Exception e) {
            System.err.println("QR Module DB Error: " + e.getMessage());
            response.sendRedirect("qr_bulk_generate.jsp?error=bulk_failed");
        }
    }

    private List<Integer> getMissingQrAssetIds(Connection con) throws Exception {
        List<Integer> ids = new ArrayList<>();

        String sql =
                "SELECT asset_id FROM assets "
                + "WHERE qr_public_token IS NULL OR TRIM(qr_public_token) = '' "
                + "ORDER BY asset_id ASC "
                + "LIMIT 500";

        try (PreparedStatement ps = con.prepareStatement(sql);
             ResultSet rs = ps.executeQuery()) {

            while (rs.next()) {
                ids.add(rs.getInt("asset_id"));
            }
        }

        return ids;
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
                        + "VALUES (?, ?, ?, 'assets', ?, ?, ?, 'SYSTEM', 'BulkGenerateAssetQrServlet')";

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
