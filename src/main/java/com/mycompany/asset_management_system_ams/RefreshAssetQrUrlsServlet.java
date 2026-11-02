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
import java.util.ArrayList;
import java.util.List;

@WebServlet(name = "RefreshAssetQrUrlsServlet", urlPatterns = {"/RefreshAssetQrUrlsServlet"})
public class RefreshAssetQrUrlsServlet extends HttpServlet {

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
            response.sendRedirect("qr_url_refresh.jsp?error=public_base_url");
            return;
        }

        String baseUrl = buildBaseUrl(request);
        int userId = getSessionUserId(session);
        int refreshedCount = 0;

        try (Connection con = DBConnection.getConnection()) {

            if ("mismatch".equals(mode)) {
                refreshedCount = refreshAllMismatched(con, baseUrl, userId);

                writeAuditCompat(con, session, 1, "QR_URL_REFRESH_ALL",
                        "Refreshed stored QR URL field for all mismatched assets. Count: " + refreshedCount
                        + ". Base URL: " + baseUrl);

            } else {
                String[] selectedIds = request.getParameterValues("asset_ids");

                if (selectedIds == null || selectedIds.length == 0) {
                    response.sendRedirect("qr_url_refresh.jsp?error=none_selected");
                    return;
                }

                List<Integer> assetIds = new ArrayList<>();

                for (String idText : selectedIds) {
                    try {
                        int assetId = Integer.parseInt(idText);

                        if (assetId > 0) {
                            assetIds.add(assetId);
                        }

                    } catch (Exception ignored) {
                    }
                }

                if (assetIds.isEmpty()) {
                    response.sendRedirect("qr_url_refresh.jsp?error=none_selected");
                    return;
                }

                for (Integer assetId : assetIds) {
                    boolean refreshed = refreshOneAsset(con, baseUrl, userId, assetId);

                    if (refreshed) {
                        QrSnapshotService.syncAssetQuietly(con, assetId);
                        refreshedCount++;

                        writeAuditCompat(con, session, assetId, "QR_URL_REFRESH_SELECTED",
                                "Refreshed stored QR URL field for asset ID " + assetId
                                + ". Base URL: " + baseUrl);
                    }
                }
            }

            response.sendRedirect("qr_url_refresh.jsp?msg=refreshed&count=" + refreshedCount);

        } catch (Exception e) {
            System.err.println("QR Module DB Error: " + e.getMessage());
            response.sendRedirect("qr_url_refresh.jsp?error=failed");
        }
    }

    private int refreshAllMismatched(Connection con, String baseUrl, int userId) throws Exception {
        String sql =
                "UPDATE assets "
                + "SET qr_code = CONCAT(?, '/public_asset_view.jsp?token=', qr_public_token), "
                + "updated_by = ?, updated_at = CURRENT_TIMESTAMP "
                + "WHERE qr_public_token IS NOT NULL AND TRIM(qr_public_token) <> '' "
                + "AND (qr_code IS NULL OR TRIM(qr_code) = '' "
                + "OR qr_code <> CONCAT(?, '/public_asset_view.jsp?token=', qr_public_token))";

        try (PreparedStatement ps = con.prepareStatement(sql)) {
            ps.setString(1, baseUrl);
            ps.setInt(2, userId);
            ps.setString(3, baseUrl);

            return ps.executeUpdate();
        }
    }

    private boolean refreshOneAsset(Connection con, String baseUrl, int userId, int assetId) throws Exception {
        String token = getAssetToken(con, assetId);

        if (token == null || token.trim().isEmpty()) {
            return false;
        }

        String url = baseUrl + "/public_asset_view.jsp?token=" + token.trim();

        String sql =
                "UPDATE assets "
                + "SET qr_code = ?, updated_by = ?, updated_at = CURRENT_TIMESTAMP "
                + "WHERE asset_id = ?";

        try (PreparedStatement ps = con.prepareStatement(sql)) {
            ps.setString(1, url);
            ps.setInt(2, userId);
            ps.setInt(3, assetId);

            return ps.executeUpdate() > 0;
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

    private String buildBaseUrl(HttpServletRequest request) {
        return QrUrlUtil.resolveBaseUrl(request);
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
                        + "VALUES (?, ?, ?, 'assets', ?, ?, ?, 'SYSTEM', 'RefreshAssetQrUrlsServlet')";

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
