<%@page contentType="text/html" pageEncoding="UTF-8"%>
<%@page import="com.mycompany.asset_management_system_ams.DBConnection"%>
<%@page import="com.mycompany.asset_management_system_ams.QrUrlUtil"%>
<%@page import="java.sql.*"%>
<%@page import="java.util.*"%>
<%@page import="java.net.URLEncoder"%>

<%!
    private String safeText(String value) {
        if (value == null || value.trim().isEmpty()) return "N/A";
        return value.trim()
                .replace("&", "&amp;")
                .replace("<", "&lt;")
                .replace(">", "&gt;")
                .replace("\"", "&quot;")
                .replace("'", "&#39;");
    }

    private String cleanLabel(String value) {
        if (value == null || value.trim().isEmpty()) return "N/A";

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

    private String rowValue(Map<String, String> row, String key) {
        if (row == null) return "";
        String value = row.get(key);
        return value == null ? "" : value;
    }

    private Map<String, String> singleRow(String sql, String id) {
        Map<String, String> row = new HashMap<String, String>();

        try (Connection con = DBConnection.getConnection();
             PreparedStatement ps = con.prepareStatement(sql)) {

            ps.setString(1, id);

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

    String assetId = request.getParameter("id");

    if (assetId == null || assetId.trim().isEmpty()) {
        assetId = request.getParameter("asset_id");
    }

    if (assetId == null || assetId.trim().isEmpty()) {
        response.sendRedirect("assets.jsp?error=invalid_qr_asset");
        return;
    }

    assetId = assetId.trim();

    boolean canGenerateQr = ("SUPER_ADMIN".equals(role) || "ADMIN".equals(role)) || "ASSET_MANAGER".equals(role);
    String userInitial = username.substring(0, Math.min(2, username.length())).toUpperCase(Locale.ENGLISH);

    Map<String, String> asset = singleRow(
            "SELECT "
            + "a.asset_id, a.asset_code, a.asset_name, a.serial_number, a.model_number, "
            + "a.asset_status, a.condition_status, a.service_status, a.location, "
            + "a.qr_code, a.qr_public_token, "
            + "DATE_FORMAT(a.updated_at, '%d %b %Y, %h:%i %p') AS updated_at, "
            + "COALESCE(ac.category_name, 'Uncategorized') AS category_name, "
            + "COALESCE(v.vendor_name, 'No Vendor') AS vendor_name, "
            + "COALESCE(d.department_name, 'Unassigned') AS department_name, "
            + "COALESCE(rl.location_name, a.location, '') AS location_name, "
            + "COALESCE(rl.location_code, '') AS location_code "
            + "FROM assets a "
            + "LEFT JOIN asset_categories ac ON a.category_id = ac.category_id "
            + "LEFT JOIN vendors v ON a.vendor_id = v.vendor_id "
            + "LEFT JOIN departments d ON a.department_id = d.department_id "
            + "LEFT JOIN railway_locations rl ON a.location_id = rl.location_id "
            + "WHERE a.asset_id = ? LIMIT 1",
            assetId
    );

    if (asset.isEmpty()) {
        response.sendRedirect("assets.jsp?error=asset_notfound");
        return;
    }

    String token = rowValue(asset, "qr_public_token");
    String liveUrl = "";

    String publicBaseUrl = QrUrlUtil.getConfiguredPublicBaseUrl();

    if (token != null && !token.trim().isEmpty() && !publicBaseUrl.trim().isEmpty()) {
        liveUrl = publicBaseUrl + "/public_asset_view.jsp?token=" + token;
    }

    String qrImageUrl = "";

    if (!liveUrl.trim().isEmpty()) {
        qrImageUrl = "https://api.qrserver.com/v1/create-qr-code/?size=360x360&margin=12&data="
                + URLEncoder.encode(liveUrl, "UTF-8");
    }

    String msg = request.getParameter("msg");
    String error = request.getParameter("error");
%>

<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>Asset QR Card - IR-AMS</title>

    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.0/css/all.min.css">

    <link rel="stylesheet" href="css/ir-glass.css?v=28000">
    <link rel="stylesheet" href="css/ams-pro.css?v=28000">
    <link rel="stylesheet" href="css/ir-ams-railway-ui.css?v=28000">

    <link rel="stylesheet" href="css/asset_qr_card.css?v=28000">
</head>

<body class="railway-ui">
<div class="app ams-shell">

    <jsp:include page="sidebar.jsp" />

    <main class="main railway-main">
        <jsp:include page="topbar.jsp" />

        <div class="main-scroll-content qr-board">

            <section class="qr-hero">
                <div>
                    <h1>Dynamic QR Card</h1>
                    <p>
                        QR stores only live URL. After printing, any database update will automatically appear on scan.
                    </p>
                </div>

                <div class="qr-actions">
                    <a class="link-btn" href="view_asset.jsp?id=<%= safeText(assetId) %>">
                        <i class="fa-solid fa-eye"></i>
                        View Asset
                    </a>

                    <a class="link-btn" href="qr_print.jsp?id=<%= safeText(assetId) %>">
                        <i class="fa-solid fa-print"></i>
                        Print QR
                    </a>
                </div>
            </section>

            <% if ("qrgenerated".equalsIgnoreCase(msg)) { %>
                <div class="success-box">
                    <i class="fa-solid fa-circle-check"></i>
                    Dynamic QR token generated successfully.
                </div>
            <% } %>

            <% if ("public_base_url".equalsIgnoreCase(error)) { %>
                <div class="warning-box">
                    <i class="fa-solid fa-triangle-exclamation"></i>
                    Set a public QR base URL in Settings or QR Control Center before generating QR codes.
                    QR codes must not encode localhost.
                </div>
            <% } %>

            <section class="qr-layout">
                <div class="qr-panel">
                    <div class="qr-box">
                        <% if (liveUrl.trim().isEmpty()) { %>
                            <i class="fa-solid fa-qrcode"></i>
                            <% if (token != null && !token.trim().isEmpty()) { %>
                                <strong>Public QR base URL not configured</strong>
                                <span>Set a non-localhost public QR base URL before printing the asset QR label.</span>
                            <% } else { %>
                                <strong>QR token not generated</strong>
                                <span>Generate QR token first, then print the asset QR label.</span>
                            <% } %>
                        <% } else { %>
                            <img src="<%= qrImageUrl %>" alt="Asset QR Code">
                            <span>Scan this QR to open live asset details.</span>
                        <% } %>
                    </div>

                    <% if (!liveUrl.trim().isEmpty()) { %>
                        <%-- Same fix as view_asset.jsp's "Dynamic QR Identity" panel:
                             asset code as the visible link text instead of the raw,
                             token-laden URL - href still opens the real liveUrl. --%>
                        <div class="qr-url">
                            <a href="<%= safeText(liveUrl) %>" target="_blank" class="qr-url-code" title="<%= safeText(liveUrl) %>">
                                <%= safeText(rowValue(asset, "asset_code")) %>
                                <i class="fa-solid fa-up-right-from-square"></i>
                            </a>
                        </div>
                    <% } %>

                    <div class="btn-row">
                        <% if (canGenerateQr) { %>
                            <form method="post" action="GenerateAssetQrServlet" style="margin:0;">
                                <input type="hidden" name="asset_id" value="<%= safeText(assetId) %>">
                                <button type="submit" class="link-btn primary">
                                    <i class="fa-solid fa-arrows-rotate"></i>
                                    Generate / Refresh QR
                                </button>
                            </form>
                        <% } %>

                        <% if (!liveUrl.trim().isEmpty()) { %>
                            <a class="link-btn" href="<%= safeText(liveUrl) %>" target="_blank">
                                <i class="fa-solid fa-up-right-from-square"></i>
                                Open Public View
                            </a>
                        <% } %>
                    </div>
                </div>

                <div class="qr-panel">
                    <table class="detail-table">
                        <tr><th>Asset Code</th><td><%= safeText(rowValue(asset, "asset_code")) %></td></tr>
                        <tr><th>Asset Name</th><td><%= safeText(rowValue(asset, "asset_name")) %></td></tr>
                        <tr><th>Category</th><td><%= safeText(rowValue(asset, "category_name")) %></td></tr>
                        <tr><th>Vendor</th><td><%= safeText(rowValue(asset, "vendor_name")) %></td></tr>
                        <tr><th>Department</th><td><%= safeText(rowValue(asset, "department_name")) %></td></tr>
                        <tr><th>Location</th><td><%= safeText(rowValue(asset, "location_name")) %> &middot; <%= safeText(rowValue(asset, "location_code")) %></td></tr>
                        <tr><th>Asset Status</th><td><%= safeText(cleanLabel(rowValue(asset, "asset_status"))) %></td></tr>
                        <tr><th>Condition</th><td><%= safeText(cleanLabel(rowValue(asset, "condition_status"))) %></td></tr>
                        <tr><th>Service Status</th><td><%= safeText(cleanLabel(rowValue(asset, "service_status"))) %></td></tr>
                        <tr><th>QR Token</th><td><%= safeText(rowValue(asset, "qr_public_token")) %></td></tr>
                        <tr><th>Last Updated</th><td><%= safeText(rowValue(asset, "updated_at")) %></td></tr>
                    </table>
                </div>
            </section>

        </div>
    </main>
</div>

<script src="js/user-dropdown.js?v=28000"></script>
<script src="js/sidebar-role.js?v=28000"></script>
<script src="js/topbar-search.js?v=28000"></script>
<script src="js/dashboard-actions.js?v=28000"></script>
</body>
</html>
