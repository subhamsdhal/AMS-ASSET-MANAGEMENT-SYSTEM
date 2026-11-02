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

    private String rowValue(Map<String, String> row, String key) {
        if (row == null) {
            return "";
        }

        String value = row.get(key);
        return value == null ? "" : value;
    }

    private String statusClass(String value) {
        if (value == null || value.trim().isEmpty()) {
            return "UNKNOWN";
        }

        return value.trim().toUpperCase(Locale.ENGLISH).replace(" ", "_");
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

    boolean canViewScanLog = ("SUPER_ADMIN".equals(role) || "ADMIN".equals(role))
            || "ASSET_MANAGER".equals(role)
            || "AUDITOR".equals(role);

    if (!canViewScanLog) {
        response.sendRedirect("dashboard.jsp?access=denied");
        return;
    }

    String scanId = request.getParameter("id");

    if (scanId == null || scanId.trim().isEmpty()) {
        scanId = request.getParameter("scan_id");
    }

    if (scanId == null || scanId.trim().isEmpty()) {
        response.sendRedirect("qr_scan_logs.jsp?error=invalid_scan");
        return;
    }

    scanId = scanId.trim();

    Map<String, String> scan = singleRow(
            "SELECT "
            + "q.scan_id, q.asset_id, q.qr_public_token, q.scan_source, q.scan_ip, "
            + "q.scan_user_agent, q.scan_status, q.remarks, "
            + "DATE_FORMAT(q.scanned_at, '%d %b %Y, %h:%i %p') AS scanned_at, "
            + "COALESCE(a.asset_code, 'No Linked Asset') AS asset_code, "
            + "COALESCE(a.asset_name, 'Asset not linked') AS asset_name, "
            + "COALESCE(a.asset_status, '') AS asset_status, "
            + "COALESCE(a.condition_status, '') AS condition_status, "
            + "COALESCE(a.service_status, '') AS service_status, "
            + "COALESCE(ac.category_name, '') AS category_name, "
            + "COALESCE(d.department_name, '') AS department_name, "
            + "COALESCE(v.vendor_name, '') AS vendor_name, "
            + "COALESCE(rl.location_name, a.location, '') AS location_name, "
            + "COALESCE(u.username, 'Public / System') AS scanned_by_user, "
            + "COALESCE(e.employee_name, 'Not Applicable') AS scanned_by_employee, "
            + "COALESCE(e.employee_code, '') AS employee_code "
            + "FROM asset_qr_scan_logs q "
            + "LEFT JOIN assets a ON q.asset_id = a.asset_id "
            + "LEFT JOIN asset_categories ac ON a.category_id = ac.category_id "
            + "LEFT JOIN departments d ON a.department_id = d.department_id "
            + "LEFT JOIN vendors v ON a.vendor_id = v.vendor_id "
            + "LEFT JOIN railway_locations rl ON a.location_id = rl.location_id "
            + "LEFT JOIN users u ON q.scanned_by_user_id = u.user_id "
            + "LEFT JOIN employees e ON q.scanned_by_employee_id = e.employee_id "
            + "WHERE q.scan_id = ? "
            + "LIMIT 1",
            scanId
    );

    if (scan.isEmpty()) {
        response.sendRedirect("qr_scan_logs.jsp?error=scan_notfound");
        return;
    }

    String token = rowValue(scan, "qr_public_token");
    String publicUrl = "";

    String publicBaseUrl = QrUrlUtil.getConfiguredPublicBaseUrl();

    if (token != null && !token.trim().isEmpty() && !publicBaseUrl.trim().isEmpty()) {
        publicUrl = publicBaseUrl + "/public_asset_view.jsp?token=" + token.trim();
    }

    String userInitial = username.substring(0, Math.min(2, username.length())).toUpperCase(Locale.ENGLISH);
%>

<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>View QR Scan Log - IR-AMS</title>

    <link rel="stylesheet"
          href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.0/css/all.min.css">

    <link rel="stylesheet" href="css/ir-glass.css?v=28000">
    <link rel="stylesheet" href="css/ams-pro.css?v=28000">
    <link rel="stylesheet" href="css/ir-ams-railway-ui.css?v=28000">
<link rel="stylesheet" href="css/view_qr_scan_log.css?v=topbarfix1">
</head>

<body class="railway-ui">
<div class="app ams-shell">

        <jsp:include page="sidebar.jsp" />

    <main class="main railway-main">
                <jsp:include page="topbar.jsp" />

        <div class="main-scroll-content scan-view-board">

            <section class="view-hero">
                <div>
                    <h1>QR Scan Log #<%= safeText(rowValue(scan, "scan_id")) %></h1>
                    <p>
                        <strong><%= safeText(rowValue(scan, "asset_code")) %></strong>
                        &middot; <%= safeText(rowValue(scan, "asset_name")) %>
                        &middot; <%= safeText(rowValue(scan, "scanned_at")) %>
                    </p>
                </div>

                <div class="hero-actions">
                    <a href="qr_scan_logs.jsp" class="action-btn">
                        <i class="fa-solid fa-arrow-left"></i>
                        Back to Logs
                    </a>

                    <% if (rowValue(scan, "asset_id") != null && !rowValue(scan, "asset_id").trim().isEmpty()) { %>
                        <a href="view_asset.jsp?id=<%= safeText(rowValue(scan, "asset_id")) %>" class="action-btn primary">
                            <i class="fa-solid fa-cubes"></i>
                            Open Asset
                        </a>
                    <% } %>

                    <% if (!publicUrl.trim().isEmpty()) { %>
                        <a href="<%= safeText(publicUrl) %>" target="_blank" class="action-btn green">
                            <i class="fa-solid fa-globe"></i>
                            Public View
                        </a>
                    <% } %>
                </div>
            </section>

            <section class="status-row">
                <div class="status-card">
                    <span>Scan Status</span>
                    <strong>
                        <span class="status-badge status-<%= safeText(statusClass(rowValue(scan, "scan_status"))) %>">
                            <%= safeText(cleanLabel(rowValue(scan, "scan_status"))) %>
                        </span>
                    </strong>
                </div>

                <div class="status-card">
                    <span>Scan Source</span>
                    <strong><%= safeText(cleanLabel(rowValue(scan, "scan_source"))) %></strong>
                </div>

                <div class="status-card">
                    <span>IP Address</span>
                    <strong><%= safeText(rowValue(scan, "scan_ip")) %></strong>
                </div>

                <div class="status-card">
                    <span>Scanned At</span>
                    <strong><%= safeText(rowValue(scan, "scanned_at")) %></strong>
                </div>
            </section>

            <section class="view-grid">
                <div class="info-panel">
                    <h2>Scan Information</h2>

                    <table class="detail-table">
                        <tr><th>Scan ID</th><td><%= safeText(rowValue(scan, "scan_id")) %></td></tr>
                        <tr><th>QR Token Used</th><td><%= safeText(rowValue(scan, "qr_public_token")) %></td></tr>
                        <tr><th>Scan Status</th><td><%= safeText(cleanLabel(rowValue(scan, "scan_status"))) %></td></tr>
                        <tr><th>Scan Source</th><td><%= safeText(cleanLabel(rowValue(scan, "scan_source"))) %></td></tr>
                        <tr><th>IP Address</th><td><%= safeText(rowValue(scan, "scan_ip")) %></td></tr>
                        <tr><th>Scanned By User</th><td><%= safeText(rowValue(scan, "scanned_by_user")) %></td></tr>
                        <tr><th>Scanned By Employee</th><td><%= safeText(rowValue(scan, "employee_code")) %> &middot; <%= safeText(rowValue(scan, "scanned_by_employee")) %></td></tr>
                        <tr><th>Remarks</th><td><%= safeText(rowValue(scan, "remarks")) %></td></tr>
                    </table>
                </div>

                <div class="info-panel">
                    <h2>Linked Asset Information</h2>

                    <table class="detail-table">
                        <tr><th>Asset ID</th><td><%= safeText(rowValue(scan, "asset_id")) %></td></tr>
                        <tr><th>Asset Code</th><td><%= safeText(rowValue(scan, "asset_code")) %></td></tr>
                        <tr><th>Asset Name</th><td><%= safeText(rowValue(scan, "asset_name")) %></td></tr>
                        <tr><th>Category</th><td><%= safeText(rowValue(scan, "category_name")) %></td></tr>
                        <tr><th>Department</th><td><%= safeText(rowValue(scan, "department_name")) %></td></tr>
                        <tr><th>Vendor</th><td><%= safeText(rowValue(scan, "vendor_name")) %></td></tr>
                        <tr><th>Location</th><td><%= safeText(rowValue(scan, "location_name")) %></td></tr>
                        <tr><th>Asset Status</th><td><%= safeText(cleanLabel(rowValue(scan, "asset_status"))) %></td></tr>
                    </table>
                </div>
            </section>

            <section class="info-panel">
                <h2>Browser / Mobile Device Details</h2>

                <div class="url-box">
                    <%= safeText(rowValue(scan, "scan_user_agent")) %>
                </div>
            </section>

            <section class="info-panel">
                <h2>Public QR URL</h2>

                <% if (!publicUrl.trim().isEmpty()) { %>
                    <%-- Fault: used to print the raw token-laden publicUrl as
                         plain text here - same issue fixed in view_asset.jsp:
                         shows the asset code instead (clean, matches how the
                         code already appears in the table above), wrapped as a
                         real link to the exact same publicUrl so it still opens
                         correctly - only the displayed text changed. --%>
                    <div class="url-box">
                        <a href="<%= safeText(publicUrl) %>" target="_blank" class="qr-url-code" title="<%= safeText(publicUrl) %>">
                            <%= safeText(rowValue(scan, "asset_code")) %>
                            <i class="fa-solid fa-up-right-from-square"></i>
                        </a>
                    </div>
                <% } else { %>
                    <div class="url-box">
                        Not available
                    </div>
                <% } %>
            </section>

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
