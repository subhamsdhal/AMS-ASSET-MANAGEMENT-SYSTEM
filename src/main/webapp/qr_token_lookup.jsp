<%@page contentType="text/html" pageEncoding="UTF-8"%>
<%@page import="com.mycompany.asset_management_system_ams.DBConnection"%>
<%@page import="com.mycompany.asset_management_system_ams.QrUrlUtil"%>
<%@page import="java.sql.*"%>
<%@page import="java.util.*"%>
<%@page import="jakarta.servlet.http.HttpServletRequest"%>

<%!
    private String safeText(String value) {
        if (value == null || value.trim().isEmpty()) {
            return "N/A";
        }

        return value.trim()
                .replace("&", "&amp;")
                .replace("<", "&lt;")
                .replace(">", "&gt;")
                .replace("\"", "&quot;")
                .replace("'", "&#39;");
    }

    private String cleanLabel(String value) {
        if (value == null || value.trim().isEmpty()) {
            return "N/A";
        }

        String text = value.trim().replace("_", " ").toLowerCase(Locale.ENGLISH);
        String[] parts = text.split("\\s+");
        StringBuilder out = new StringBuilder();

        for (String part : parts) {
            if (part.length() > 0) {
                out.append(Character.toUpperCase(part.charAt(0))).append(part.substring(1)).append(" ");
            }
        }

        return out.toString().trim();
    }

    private String appBaseUrl(HttpServletRequest request) {
        String scheme = request.getHeader("X-Forwarded-Proto");

        if (scheme == null || scheme.trim().isEmpty()) {
            scheme = request.getScheme();
        }

        String host = request.getHeader("X-Forwarded-Host");

        if (host == null || host.trim().isEmpty()) {
            host = request.getServerName();

            int port = request.getServerPort();

            if (!("http".equalsIgnoreCase(scheme) && port == 80)
                    && !("https".equalsIgnoreCase(scheme) && port == 443)) {
                host = host + ":" + port;
            }
        }

        return scheme + "://" + host + request.getContextPath();
    }

    private String rowValue(Map<String, String> row, String key) {
        if (row == null) {
            return "";
        }

        String value = row.get(key);
        return value == null ? "" : value;
    }

    private Integer extractOldSeedAssetId(String token) {
        if (token == null) {
            return null;
        }

        String cleaned = token.trim().toUpperCase(Locale.ENGLISH);

        if (!cleaned.startsWith("ECORQR")) {
            return null;
        }

        String digits = cleaned.replaceAll("[^0-9]", "");

        if (digits.isEmpty()) {
            return null;
        }

        try {
            int value = Integer.parseInt(digits);

            if (value > 0) {
                return value;
            }

        } catch (Exception e) {
            return null;
        }

        return null;
    }

    private boolean tableExists(Connection con, String tableName) {
        String sql = "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = DATABASE() AND table_name = ?";

        try (PreparedStatement ps = con.prepareStatement(sql)) {
            ps.setString(1, tableName);

            try (ResultSet rs = ps.executeQuery()) {
                return rs.next() && rs.getInt(1) > 0;
            }

        } catch (Exception e) {
            System.err.println("QR Module DB Error: " + e.getMessage());
        }

        return false;
    }

    private int countScans(Connection con, String assetId) {
        if (assetId == null || assetId.trim().isEmpty()) {
            return 0;
        }

        try {
            if (!tableExists(con, "asset_qr_scan_logs")) {
                return 0;
            }

            String sql = "SELECT COUNT(*) FROM asset_qr_scan_logs WHERE asset_id = ?";

            try (PreparedStatement ps = con.prepareStatement(sql)) {
                ps.setString(1, assetId);

                try (ResultSet rs = ps.executeQuery()) {
                    if (rs.next()) {
                        return rs.getInt(1);
                    }
                }
            }

        } catch (Exception e) {
            System.err.println("QR Module DB Error: " + e.getMessage());
        }

        return 0;
    }

    private Map<String, String> lookupAsset(Connection con, String token) {
        Map<String, String> row = new HashMap<String, String>();

        Integer oldSeedAssetId = extractOldSeedAssetId(token);

        String sql =
                "SELECT "
                + "a.asset_id, a.asset_code, a.asset_name, a.serial_number, a.model_number, "
                + "a.asset_status, a.condition_status, a.service_status, "
                + "a.qr_public_token, a.qr_code, "
                + "DATE_FORMAT(a.updated_at, '%d %b %Y, %h:%i %p') AS updated_at, "
                + "COALESCE(ac.category_name, 'Uncategorized') AS category_name, "
                + "COALESCE(d.department_name, 'Unassigned') AS department_name, "
                + "COALESCE(v.vendor_name, 'No Vendor') AS vendor_name, "
                + "COALESCE(rl.location_name, a.location, 'Not Mentioned') AS location_name "
                + "FROM assets a "
                + "LEFT JOIN asset_categories ac ON a.category_id = ac.category_id "
                + "LEFT JOIN departments d ON a.department_id = d.department_id "
                + "LEFT JOIN vendors v ON a.vendor_id = v.vendor_id "
                + "LEFT JOIN railway_locations rl ON a.location_id = rl.location_id "
                + "WHERE "
                + "TRIM(COALESCE(a.qr_public_token, '')) = ? "
                + "OR TRIM(COALESCE(a.qr_code, '')) = ? "
                + "OR TRIM(COALESCE(a.asset_code, '')) = ? ";

        if (oldSeedAssetId != null) {
            sql += "OR a.asset_id = ? ";
        }

        sql += "LIMIT 1";

        try (PreparedStatement ps = con.prepareStatement(sql)) {
            ps.setString(1, token.trim());
            ps.setString(2, token.trim());
            ps.setString(3, token.trim());

            if (oldSeedAssetId != null) {
                ps.setInt(4, oldSeedAssetId);
            }

            try (ResultSet rs = ps.executeQuery()) {
                ResultSetMetaData meta = rs.getMetaData();
                int count = meta.getColumnCount();

                if (rs.next()) {
                    for (int i = 1; i <= count; i++) {
                        row.put(meta.getColumnLabel(i), rs.getString(i));
                    }
                }
            }

        } catch (Exception e) {
            System.err.println("QR Module DB Error: " + e.getMessage());
        }

        return row;
    }
%>

<%
    String username = (String) session.getAttribute("username");
    String role = (String) session.getAttribute("role");

    response.setHeader("Cache-Control", "no-cache, no-store, must-revalidate");
    response.setHeader("Pragma", "no-cache");
    response.setDateHeader("Expires", 0);

    if (username == null || role == null) {
        response.sendRedirect("login.jsp");
        return;
    }

    boolean canLookupToken = ("SUPER_ADMIN".equals(role) || "ADMIN".equals(role))
            || "ASSET_MANAGER".equals(role)
            || "AUDITOR".equals(role);

    if (!canLookupToken) {
        response.sendRedirect("dashboard.jsp?access=denied");
        return;
    }

    String token = request.getParameter("token");

    if (token == null) {
        token = "";
    }

    token = token.trim();

    String baseUrl = QrUrlUtil.getConfiguredPublicBaseUrl();
    String userInitial = username.substring(0, Math.min(2, username.length())).toUpperCase(Locale.ENGLISH);

    Map<String, String> asset = new HashMap<String, String>();
    int scanCount = 0;

    if (!token.isEmpty()) {
        try (Connection con = DBConnection.getConnection()) {
            asset = lookupAsset(con, token);
            scanCount = countScans(con, rowValue(asset, "asset_id"));

        } catch (Exception e) {
            System.err.println("QR Module DB Error: " + e.getMessage());
        }
    }

    boolean found = !asset.isEmpty();

    String finalToken = "";

    if (found) {
        finalToken = rowValue(asset, "qr_public_token");

        if (finalToken == null || finalToken.trim().isEmpty()) {
            finalToken = token;
        }
    }

    String publicUrl = "";

    if (found && finalToken != null && !finalToken.trim().isEmpty() && !baseUrl.trim().isEmpty()) {
        publicUrl = baseUrl + "/public_asset_view.jsp?token=" + finalToken.trim();
    }
%>

<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>QR Token Lookup - IR-AMS</title>

    <link rel="stylesheet"
          href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.0/css/all.min.css">

    <link rel="stylesheet" href="css/ir-glass.css?v=28000">
    <link rel="stylesheet" href="css/ams-pro.css?v=28000">
    <link rel="stylesheet" href="css/ir-ams-railway-ui.css?v=28000">
<link rel="stylesheet" href="css/qr_token_lookup.css?v=topbarfix1">
</head>

<body class="railway-ui">
<div class="app ams-shell">

        <jsp:include page="sidebar.jsp" />

    <main class="main railway-main">
                <jsp:include page="topbar.jsp" />

        <div class="main-scroll-content lookup-board">

            <section class="lookup-hero">
                <div>
                    <h1>QR Token Lookup</h1>
                    <p>
                        Search and test any QR token, QR URL, asset code, or old seeded token.
                        Useful before printing labels or after deployment URL change.
                    </p>
                </div>

                <div class="hero-actions">
                    <a href="qr_exception_report.jsp" class="action-btn">
                        <i class="fa-solid fa-triangle-exclamation"></i>
                        Exception Report
                    </a>

                    <a href="qr_asset_register.jsp" class="action-btn">
                        <i class="fa-solid fa-table-list"></i>
                        QR Register
                    </a>

                    <a href="qr_control_center.jsp" class="action-btn primary">
                        <i class="fa-solid fa-arrow-left"></i>
                        Control Center
                    </a>
                </div>
            </section>

            <section class="panel">
                <h2>Search QR Token / Asset Code</h2>

                <form class="lookup-form" method="get" action="qr_token_lookup.jsp">
                    <input class="lookup-input"
                           type="text"
                           name="token"
                           value="<%= token.isEmpty() ? "" : safeText(token) %>"
                           placeholder="Paste QR token, public URL field, asset code, or ECORQR000001...">

                    <button class="action-btn primary" type="submit">
                        <i class="fa-solid fa-magnifying-glass"></i>
                        Lookup
                    </button>

                    <a href="qr_token_lookup.jsp" class="action-btn">
                        <i class="fa-solid fa-rotate-right"></i>
                        Reset
                    </a>
                </form>
            </section>

            <% if (token.isEmpty()) { %>
                <section class="panel">
                    <div class="empty-box">
                        <i class="fa-solid fa-qrcode"></i>
                        <strong>Enter a QR token to test</strong>
                        <span>You can paste QR public token, full stored QR URL, old ECORQR token, or asset code.</span>
                    </div>
                </section>
            <% } else if (!found) { %>
                <section class="panel">
                    <div class="empty-box">
                        <i class="fa-solid fa-circle-xmark"></i>
                        <strong>No asset found for this token</strong>
                        <span>Token checked: <%= safeText(token) %></span>
                    </div>
                </section>
            <% } else { %>

                <section class="result-grid">
                    <div class="panel">
                        <h2>Matched Asset</h2>

                        <table class="detail-table">
                            <tr><th>Asset ID</th><td><%= safeText(rowValue(asset, "asset_id")) %></td></tr>
                            <tr><th>Asset Code</th><td><%= safeText(rowValue(asset, "asset_code")) %></td></tr>
                            <tr><th>Asset Name</th><td><%= safeText(rowValue(asset, "asset_name")) %></td></tr>
                            <tr><th>Category</th><td><%= safeText(rowValue(asset, "category_name")) %></td></tr>
                            <tr><th>Department</th><td><%= safeText(rowValue(asset, "department_name")) %></td></tr>
                            <tr><th>Vendor</th><td><%= safeText(rowValue(asset, "vendor_name")) %></td></tr>
                            <tr><th>Location</th><td><%= safeText(rowValue(asset, "location_name")) %></td></tr>
                            <tr><th>Asset Status</th><td><span class="pill good"><%= safeText(cleanLabel(rowValue(asset, "asset_status"))) %></span></td></tr>
                            <tr><th>Condition</th><td><%= safeText(cleanLabel(rowValue(asset, "condition_status"))) %></td></tr>
                            <tr><th>Service</th><td><%= safeText(cleanLabel(rowValue(asset, "service_status"))) %></td></tr>
                            <tr><th>Total Scans</th><td><%= scanCount %></td></tr>
                            <tr><th>Last Updated</th><td><%= safeText(rowValue(asset, "updated_at")) %></td></tr>
                        </table>
                    </div>

                    <div class="panel">
                        <h2>QR Verification</h2>

                        <table class="detail-table">
                            <tr><th>Token Entered</th><td><%= safeText(token) %></td></tr>
                            <tr><th>QR Public Token</th><td><%= safeText(rowValue(asset, "qr_public_token")) %></td></tr>
                            <tr><th>Stored QR URL</th><td><%= safeText(rowValue(asset, "qr_code")) %></td></tr>
                            <tr><th>Generated Public URL</th><td><%= safeText(publicUrl) %></td></tr>
                        </table>

                        <% if (!publicUrl.trim().isEmpty()) { %>
                            <%-- Full comparison detail (Token Entered / Stored QR URL /
                                 Generated Public URL) stays in the diagnostic table above,
                                 unchanged - this box is just the "go use it" action, so it
                                 gets the same clean-asset-code-as-link treatment as
                                 view_asset.jsp instead of repeating the raw URL a third time. --%>
                            <div class="url-box" style="margin-top:14px;">
                                <strong>Recommended Live URL:</strong><br>
                                <a href="<%= safeText(publicUrl) %>" target="_blank" class="qr-url-code" title="<%= safeText(publicUrl) %>">
                                    <%= safeText(rowValue(asset, "asset_code")) %>
                                    <i class="fa-solid fa-up-right-from-square"></i>
                                </a>
                            </div>
                        <% } %>

                        <div class="hero-actions" style="justify-content:flex-start;margin-top:14px;">
                            <a class="action-btn primary" href="view_asset.jsp?id=<%= safeText(rowValue(asset, "asset_id")) %>">
                                <i class="fa-solid fa-up-right-from-square"></i>
                                Open Asset
                            </a>

                            <a class="action-btn" href="asset_qr_card.jsp?id=<%= safeText(rowValue(asset, "asset_id")) %>">
                                <i class="fa-solid fa-id-card"></i>
                                QR Card
                            </a>

                            <a class="action-btn green" href="qr_print.jsp?id=<%= safeText(rowValue(asset, "asset_id")) %>">
                                <i class="fa-solid fa-print"></i>
                                Print QR
                            </a>

                            <a class="action-btn primary" target="_blank" href="<%= safeText(publicUrl) %>">
                                <i class="fa-solid fa-globe"></i>
                                Public View
                            </a>
                        </div>
                    </div>
                </section>

            <% } %>

        </div>
    </main>
</div>

<script src="js/topbar-search.js?v=28000"></script>
<script src="js/user-dropdown.js?v=28000"></script>
<script src="js/sidebar-role.js?v=28000"></script>
<script src="js/ir-body-watermark.js?v=28000"></script>
<script src="js/dashboard-actions.js?v=28000"></script>

</body>
</html>
