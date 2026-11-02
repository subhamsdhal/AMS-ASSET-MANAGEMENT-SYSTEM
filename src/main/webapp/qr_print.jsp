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

    private String rowValue(Map<String, String> row, String key) {
        if (row == null) return "";
        String value = row.get(key);
        return value == null ? "" : value;
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

    private List<Map<String, String>> listRows(String sql, String id) {
        List<Map<String, String>> rows = new ArrayList<Map<String, String>>();

        try (Connection con = DBConnection.getConnection();
             PreparedStatement ps = con.prepareStatement(sql)) {

            if (id != null) {
                ps.setString(1, id);
            }

            try (ResultSet rs = ps.executeQuery()) {
                ResultSetMetaData meta = rs.getMetaData();
                int count = meta.getColumnCount();

                while (rs.next()) {
                    Map<String, String> row = new HashMap<String, String>();

                    for (int i = 1; i <= count; i++) {
                        row.put(meta.getColumnLabel(i), rs.getString(i));
                    }

                    rows.add(row);
                }
            }

        } catch (Exception e) {
            System.err.println("QR Module DB Error: " + e.getMessage());
        }

        return rows;
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

    String id = request.getParameter("id");

    if (id == null || id.trim().isEmpty()) {
        id = request.getParameter("asset_id");
    }

    if (id != null) {
        id = id.trim();
    }

    String sql;

    if (id != null && !id.trim().isEmpty()) {
        sql =
                "SELECT "
                + "a.asset_id, a.asset_code, a.asset_name, a.qr_public_token, "
                + "a.serial_number, a.model_number, a.asset_status, "
                + "COALESCE(ac.category_name, 'Uncategorized') AS category_name, "
                + "COALESCE(d.department_name, 'Unassigned') AS department_name, "
                + "COALESCE(rl.location_name, a.location, '') AS location_name, "
                + "COALESCE(rl.location_code, '') AS location_code "
                + "FROM assets a "
                + "LEFT JOIN asset_categories ac ON a.category_id = ac.category_id "
                + "LEFT JOIN departments d ON a.department_id = d.department_id "
                + "LEFT JOIN railway_locations rl ON a.location_id = rl.location_id "
                + "WHERE a.asset_id = ? "
                + "LIMIT 1";
    } else {
        sql =
                "SELECT "
                + "a.asset_id, a.asset_code, a.asset_name, a.qr_public_token, "
                + "a.serial_number, a.model_number, a.asset_status, "
                + "COALESCE(ac.category_name, 'Uncategorized') AS category_name, "
                + "COALESCE(d.department_name, 'Unassigned') AS department_name, "
                + "COALESCE(rl.location_name, a.location, '') AS location_name, "
                + "COALESCE(rl.location_code, '') AS location_code "
                + "FROM assets a "
                + "LEFT JOIN asset_categories ac ON a.category_id = ac.category_id "
                + "LEFT JOIN departments d ON a.department_id = d.department_id "
                + "LEFT JOIN railway_locations rl ON a.location_id = rl.location_id "
                + "ORDER BY a.asset_id DESC "
                + "LIMIT 60";
    }

    List<Map<String, String>> assets = listRows(sql, (id != null && !id.trim().isEmpty()) ? id : null);

    String baseUrl = QrUrlUtil.getConfiguredPublicBaseUrl();
%>

<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>Print Asset QR Labels - IR-AMS</title>

    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.0/css/all.min.css">

    <link rel="stylesheet" href="css/qr_print.css?v=28000">
</head>

<body>
<div class="screen-bar">
    <h1><i class="fa-solid fa-qrcode"></i> Print Asset QR Labels</h1>

    <div class="screen-actions">
        <button class="screen-btn" onclick="window.print()">
            <i class="fa-solid fa-print"></i>
            Print
        </button>

        <a class="screen-btn" href="assets.jsp">
            <i class="fa-solid fa-arrow-left"></i>
            Assets
        </a>
    </div>
</div>

<div class="print-sheet">
    <% if (assets.isEmpty()) { %>
        <div class="qr-label">
            <div class="qr-side">
                <div class="missing">
                    <i class="fa-solid fa-circle-xmark"></i>
                    No Asset Found
                </div>
            </div>
            <div class="label-body">
                <div class="label-head">
                    <strong>No printable QR label available</strong>
                    <span>IR-AMS</span>
                </div>
            </div>
        </div>
    <% } else {
        for (Map<String, String> asset : assets) {
            String token = rowValue(asset, "qr_public_token");
            String liveUrl = (token.trim().isEmpty() || baseUrl.trim().isEmpty())
                    ? ""
                    : baseUrl + "/public_asset_view.jsp?token=" + token;
            String qrImage = liveUrl.trim().isEmpty() ? "" : "https://api.qrserver.com/v1/create-qr-code/?size=260x260&margin=10&data=" + URLEncoder.encode(liveUrl, "UTF-8");
    %>
        <div class="qr-label">
            <div class="qr-side">
                <% if (qrImage.trim().isEmpty()) { %>
                    <div class="missing">
                        <i class="fa-solid fa-triangle-exclamation"></i>
                        Generate QR first
                    </div>
                <% } else { %>
                    <img src="<%= qrImage %>" alt="Asset QR">
                <% } %>

                <div class="scan-note">
                    Scan for live AMS asset status
                </div>
            </div>

            <div class="label-body">
                <div class="label-head">
                    <strong><%= safeText(rowValue(asset, "asset_code")) %></strong>
                    <span><%= safeText(rowValue(asset, "asset_name")) %></span>
                </div>

                <table class="label-table">
                    <tr><th>Category</th><td><%= safeText(rowValue(asset, "category_name")) %></td></tr>
                    <tr><th>Serial No.</th><td><%= safeText(rowValue(asset, "serial_number")) %></td></tr>
                    <tr><th>Model</th><td><%= safeText(rowValue(asset, "model_number")) %></td></tr>
                    <tr><th>Department</th><td><%= safeText(rowValue(asset, "department_name")) %></td></tr>
                    <tr><th>Location</th><td><%= safeText(rowValue(asset, "location_name")) %> &middot; <%= safeText(rowValue(asset, "location_code")) %></td></tr>
                    <tr><th>Status</th><td><%= safeText(rowValue(asset, "asset_status")) %></td></tr>
                    <tr><th>QR Token</th><td><%= safeText(token) %></td></tr>
                </table>

                <div class="rail-mark">
                    East Coast Railway &middot; Indian Railways
                </div>
            </div>
        </div>
    <%  }
    } %>
</div>
</body>
</html>
