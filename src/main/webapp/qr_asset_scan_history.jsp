<%@page contentType="text/html" pageEncoding="UTF-8"%>
<%@page import="com.mycompany.asset_management_system_ams.DBConnection"%>
<%@page import="java.sql.*"%>
<%@page import="java.util.*"%>
<%@page import="java.net.URLEncoder"%>

<%!
    public String formatNumber(int number) {
        if (number >= 100000) {
            return String.format("%.1fL", number / 100000.0);
        } else if (number >= 1000) {
            return String.format("%.1fK", number / 1000.0);
        }
        return String.valueOf(number);
    }

    public static class HistoryRow {
        String scanId = "";
        String assetId = "";
        String assetCode = "";
        String assetName = "";
        String departmentName = "";
        String categoryName = "";
        String token = "";
        String scanStatus = "";
        String scanSource = "";
        String scanIp = "";
        String userAgent = "";
        String remarks = "";
        String scannedAt = "";
    }

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

    private int countRows(Connection con, String sql, List<String> params) {
        try (PreparedStatement ps = con.prepareStatement(sql)) {
            for (int i = 0; i < params.size(); i++) {
                ps.setString(i + 1, params.get(i));
            }

            try (ResultSet rs = ps.executeQuery()) {
                if (rs.next()) {
                    return rs.getInt(1);
                }
            }

        } catch (Exception e) {
            System.err.println("QR Module DB Error: " + e.getMessage());
        }

        return 0;
    }

    private String statusClass(String status) {
        if (status == null || status.trim().isEmpty()) {
            return "UNKNOWN";
        }

        return status.trim().toUpperCase(Locale.ENGLISH).replace(" ", "_");
    }

    private String limitText(String value, int max) {
        if (value == null || value.trim().isEmpty()) {
            return "N/A";
        }

        String text = value.trim();

        if (text.length() <= max) {
            return text;
        }

        return text.substring(0, max) + "...";
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

    boolean canView = ("SUPER_ADMIN".equals(role) || "ADMIN".equals(role))
            || "ASSET_MANAGER".equals(role)
            || "AUDITOR".equals(role);

    if (!canView) {
        response.sendRedirect("dashboard.jsp?access=denied");
        return;
    }

    String q = request.getParameter("q");
    String statusFilter = request.getParameter("status");

    if (q == null) {
        q = "";
    }

    if (statusFilter == null || statusFilter.trim().isEmpty()) {
        statusFilter = "ALL";
    }

    q = q.trim();
    statusFilter = statusFilter.trim().toUpperCase(Locale.ENGLISH);

    String exportUrl = "export_qr_asset_scan_history_excel.jsp?status="
            + URLEncoder.encode(statusFilter, "UTF-8");

    if (!q.isEmpty()) {
        exportUrl += "&q=" + URLEncoder.encode(q, "UTF-8");
    }

    String userInitial = username.substring(0, Math.min(2, username.length())).toUpperCase(Locale.ENGLISH);

    boolean scanTableExists = false;
    int totalRows = 0;
    int successRows = 0;
    int invalidRows = 0;
    int uniqueAssets = 0;

    List<HistoryRow> rows = new ArrayList<HistoryRow>();

    try (Connection con = DBConnection.getConnection()) {
        scanTableExists = tableExists(con, "asset_qr_scan_logs");

        if (scanTableExists) {
            StringBuilder where = new StringBuilder(" WHERE 1 = 1 ");
            List<String> params = new ArrayList<String>();

            if (!"ALL".equals(statusFilter)) {
                where.append("AND q.scan_status = ? ");
                params.add(statusFilter);
            }

            if (!q.isEmpty()) {
                where.append("AND (")
                        .append("a.asset_code LIKE ? ")
                        .append("OR a.asset_name LIKE ? ")
                        .append("OR q.qr_public_token LIKE ? ")
                        .append("OR q.scan_ip LIKE ? ")
                        .append("OR d.department_name LIKE ? ")
                        .append("OR ac.category_name LIKE ? ")
                        .append(") ");

                String searchValue = "%" + q + "%";

                for (int i = 0; i < 6; i++) {
                    params.add(searchValue);
                }
            }

            totalRows = countRows(con,
                    "SELECT COUNT(*) "
                    + "FROM asset_qr_scan_logs q "
                    + "LEFT JOIN assets a ON q.asset_id = a.asset_id "
                    + "LEFT JOIN departments d ON a.department_id = d.department_id "
                    + "LEFT JOIN asset_categories ac ON a.category_id = ac.category_id "
                    + where.toString(),
                    params);

            successRows = countRows(con,
                    "SELECT COUNT(*) "
                    + "FROM asset_qr_scan_logs q "
                    + "LEFT JOIN assets a ON q.asset_id = a.asset_id "
                    + "LEFT JOIN departments d ON a.department_id = d.department_id "
                    + "LEFT JOIN asset_categories ac ON a.category_id = ac.category_id "
                    + where.toString() + " AND q.scan_status = 'SUCCESS' ",
                    params);

            invalidRows = countRows(con,
                    "SELECT COUNT(*) "
                    + "FROM asset_qr_scan_logs q "
                    + "LEFT JOIN assets a ON q.asset_id = a.asset_id "
                    + "LEFT JOIN departments d ON a.department_id = d.department_id "
                    + "LEFT JOIN asset_categories ac ON a.category_id = ac.category_id "
                    + where.toString() + " AND q.scan_status = 'INVALID_TOKEN' ",
                    params);

            uniqueAssets = countRows(con,
                    "SELECT COUNT(DISTINCT q.asset_id) "
                    + "FROM asset_qr_scan_logs q "
                    + "LEFT JOIN assets a ON q.asset_id = a.asset_id "
                    + "LEFT JOIN departments d ON a.department_id = d.department_id "
                    + "LEFT JOIN asset_categories ac ON a.category_id = ac.category_id "
                    + where.toString() + " AND q.asset_id IS NOT NULL ",
                    params);

            String sql =
                    "SELECT "
                    + "q.scan_id, q.asset_id, q.qr_public_token, q.scan_status, q.scan_source, "
                    + "q.scan_ip, q.scan_user_agent, q.remarks, "
                    + "DATE_FORMAT(q.scanned_at, '%d %b %Y, %h:%i %p') AS scanned_at, "
                    + "COALESCE(a.asset_code, 'No Linked Asset') AS asset_code, "
                    + "COALESCE(a.asset_name, 'Asset not linked') AS asset_name, "
                    + "COALESCE(d.department_name, 'Not Available') AS department_name, "
                    + "COALESCE(ac.category_name, 'Not Available') AS category_name "
                    + "FROM asset_qr_scan_logs q "
                    + "LEFT JOIN assets a ON q.asset_id = a.asset_id "
                    + "LEFT JOIN departments d ON a.department_id = d.department_id "
                    + "LEFT JOIN asset_categories ac ON a.category_id = ac.category_id "
                    + where.toString()
                    + "ORDER BY q.scan_id DESC LIMIT 400";

            try (PreparedStatement ps = con.prepareStatement(sql)) {
                for (int i = 0; i < params.size(); i++) {
                    ps.setString(i + 1, params.get(i));
                }

                try (ResultSet rs = ps.executeQuery()) {
                    while (rs.next()) {
                        HistoryRow row = new HistoryRow();

                        row.scanId = rs.getString("scan_id");
                        row.assetId = rs.getString("asset_id");
                        row.assetCode = rs.getString("asset_code");
                        row.assetName = rs.getString("asset_name");
                        row.departmentName = rs.getString("department_name");
                        row.categoryName = rs.getString("category_name");
                        row.token = rs.getString("qr_public_token");
                        row.scanStatus = rs.getString("scan_status");
                        row.scanSource = rs.getString("scan_source");
                        row.scanIp = rs.getString("scan_ip");
                        row.userAgent = rs.getString("scan_user_agent");
                        row.remarks = rs.getString("remarks");
                        row.scannedAt = rs.getString("scanned_at");

                        rows.add(row);
                    }
                }
            }
        }

    } catch (Exception e) {
        System.err.println("QR Module DB Error: " + e.getMessage());
    }
%>

<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>QR Asset Scan History - IR-AMS</title>

    <link rel="stylesheet"
          href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.0/css/all.min.css">

    <link rel="stylesheet" href="css/ir-glass.css?v=28000">
    <link rel="stylesheet" href="css/ams-pro.css?v=28000">
    <link rel="stylesheet" href="css/ir-ams-railway-ui.css?v=28000">
<link rel="stylesheet" href="css/qr_asset_scan_history.css?v=topbarfix1">
</head>

<body class="railway-ui">
<div class="app ams-shell">

        <jsp:include page="sidebar.jsp" />

    <main class="main railway-main">
                <jsp:include page="topbar.jsp" />

        <div class="main-scroll-content history-board">

            <section class="history-hero">
                <div>
                    <h1>QR Asset Scan History</h1>
                    <p>
                        Asset-wise QR scan history with token, scan IP, status, source, browser/device details and linked asset information.
                    </p>
                </div>

                <div class="hero-actions">
                    <a href="<%= safeText(exportUrl) %>" class="action-btn green">
                        <i class="fa-solid fa-file-excel"></i>
                        Export Excel
                    </a>

                    <a href="qr_ip_audit_report.jsp" class="action-btn">
                        <i class="fa-solid fa-network-wired"></i>
                        IP Audit
                    </a>

                    <a href="qr_scan_logs.jsp" class="action-btn">
                        <i class="fa-solid fa-list-check"></i>
                        Scan Logs
                    </a>

                    <a href="qr_control_center.jsp" class="action-btn primary">
                        <i class="fa-solid fa-arrow-left"></i>
                        Control Center
                    </a>
                </div>
            </section>

            <section class="kpi-grid">
                <div class="kpi-card">
                    <h3>Total History Rows</h3>
                    <p title="<%= totalRows %>"><%= formatNumber(totalRows) %></p>
                    <span>Matching scan records</span>
                </div>

                <div class="kpi-card">
                    <h3>Success</h3>
                    <p title="<%= successRows %>"><%= formatNumber(successRows) %></p>
                    <span>Successful QR views</span>
                </div>

                <div class="kpi-card">
                    <h3>Invalid</h3>
                    <p title="<%= invalidRows %>"><%= formatNumber(invalidRows) %></p>
                    <span>Invalid token entries</span>
                </div>

                <div class="kpi-card">
                    <h3>Unique Assets</h3>
                    <p title="<%= uniqueAssets %>"><%= formatNumber(uniqueAssets) %></p>
                    <span>Assets in current result</span>
                </div>
            </section>

            <section class="panel">
                <div class="toolbar">
                    <div>
                        <h2>Asset-wise QR Scan History</h2>
                        <p class="table-subtext">Showing <%= rows.size() %> latest matching scan records. Maximum 400 records shown.</p>
                    </div>

                    <form class="filter-form" method="get" action="qr_asset_scan_history.jsp">
                        <input class="filter-input"
                               type="text"
                               name="q"
                               value="<%= q.isEmpty() ? "" : safeText(q) %>"
                               placeholder="Search asset, token, IP, department, category...">

                        <select class="filter-select" name="status">
                            <option value="ALL" <%= "ALL".equals(statusFilter) ? "selected" : "" %>>All Status</option>
                            <option value="SUCCESS" <%= "SUCCESS".equals(statusFilter) ? "selected" : "" %>>SUCCESS</option>
                            <option value="INVALID_TOKEN" <%= "INVALID_TOKEN".equals(statusFilter) ? "selected" : "" %>>INVALID_TOKEN</option>
                            <option value="FAILED" <%= "FAILED".equals(statusFilter) ? "selected" : "" %>>FAILED</option>
                            <option value="ERROR" <%= "ERROR".equals(statusFilter) ? "selected" : "" %>>ERROR</option>
                        </select>

                        <button class="action-btn primary" type="submit">
                            <i class="fa-solid fa-filter"></i>
                            Filter
                        </button>

                        <a class="action-btn green" href="<%= safeText(exportUrl) %>">
                            <i class="fa-solid fa-file-excel"></i>
                            Export
                        </a>

                        <a class="action-btn" href="qr_asset_scan_history.jsp">
                            <i class="fa-solid fa-rotate-right"></i>
                            Reset
                        </a>
                    </form>
                </div>

                <% if (!scanTableExists) { %>
                    <span class="pill status-ERROR">asset_qr_scan_logs table not found</span>
                <% } else { %>
                    <div class="table-wrap">
                        <table class="history-table">
                            <thead>
                                <tr>
                                    <th>Scan ID</th>
                                    <th>Asset</th>
                                    <th>Department / Category</th>
                                    <th>Token</th>
                                    <th>Status</th>
                                    <th>Source</th>
                                    <th>IP Address</th>
                                    <th>Browser / Device</th>
                                    <th>Remarks</th>
                                    <th>Scanned At</th>
                                    <th>Open</th>
                                </tr>
                            </thead>

                            <tbody>
                                <% for (HistoryRow row : rows) { %>
                                    <tr>
                                        <td>
                                            <strong>#<%= safeText(row.scanId) %></strong>
                                        </td>

                                        <td>
                                            <div class="asset-title">
                                                <strong><%= safeText(row.assetCode) %></strong>
                                                <span><%= safeText(row.assetName) %></span>
                                            </div>
                                        </td>

                                        <td>
                                            <div class="asset-title">
                                                <strong><%= safeText(row.departmentName) %></strong>
                                                <span><%= safeText(row.categoryName) %></span>
                                            </div>
                                        </td>

                                        <td>
                                            <span class="pill" title="<%= safeText(row.token) %>">
                                                <%= safeText(limitText(row.token, 36)) %>
                                            </span>
                                        </td>

                                        <td>
                                            <span class="pill status-<%= safeText(statusClass(row.scanStatus)) %>">
                                                <%= safeText(cleanLabel(row.scanStatus)) %>
                                            </span>
                                        </td>

                                        <td><%= safeText(cleanLabel(row.scanSource)) %></td>
                                        <td><%= safeText(row.scanIp) %></td>

                                        <td>
                                            <span class="pill" title="<%= safeText(row.userAgent) %>">
                                                <%= safeText(limitText(row.userAgent, 42)) %>
                                            </span>
                                        </td>

                                        <td>
                                            <span class="pill" title="<%= safeText(row.remarks) %>">
                                                <%= safeText(limitText(row.remarks, 42)) %>
                                            </span>
                                        </td>

                                        <td><%= safeText(row.scannedAt) %></td>

                                        <td>
                                            <div class="hero-actions" style="justify-content:flex-start;">
                                                <a class="action-btn" href="view_qr_scan_log.jsp?id=<%= safeText(row.scanId) %>">Scan</a>

                                                <% if (row.assetId != null && !row.assetId.trim().isEmpty()) { %>
                                                    <a class="action-btn primary" href="view_asset.jsp?id=<%= safeText(row.assetId) %>">Asset</a>
                                                <% } %>
                                            </div>
                                        </td>
                                    </tr>
                                <% } %>

                                <% if (rows.isEmpty()) { %>
                                    <tr>
                                        <td colspan="11">
                                            <span class="pill">No QR scan history found for selected filter.</span>
                                        </td>
                                    </tr>
                                <% } %>
                            </tbody>
                        </table>
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