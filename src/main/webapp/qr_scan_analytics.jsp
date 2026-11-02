<%@page contentType="text/html" pageEncoding="UTF-8"%>
<%@page import="com.mycompany.asset_management_system_ams.DBConnection"%>
<%@page import="java.sql.*"%>
<%@page import="java.util.*"%>
<%@page import="java.text.DecimalFormat"%>

<%!
    public String formatNumber(int number) {
        if (number >= 100000) {
            return String.format("%.1fL", number / 100000.0);
        } else if (number >= 1000) {
            return String.format("%.1fK", number / 1000.0);
        }
        return String.valueOf(number);
    }

    public static class MetricRow {
        String label = "";
        String subLabel = "";
        String value = "";
        String extra = "";
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

    private int countRows(Connection con, String sql) {
        try (Statement st = con.createStatement();
             ResultSet rs = st.executeQuery(sql)) {

            if (rs.next()) {
                return rs.getInt(1);
            }

        } catch (Exception e) {
            System.err.println("QR Module DB Error: " + e.getMessage());
        }

        return 0;
    }

    private List<MetricRow> listRows(Connection con, String sql) {
        List<MetricRow> rows = new ArrayList<MetricRow>();

        try (PreparedStatement ps = con.prepareStatement(sql);
             ResultSet rs = ps.executeQuery()) {

            while (rs.next()) {
                MetricRow row = new MetricRow();

                row.label = rs.getString("label");
                row.subLabel = rs.getString("sub_label");
                row.value = rs.getString("value_text");
                row.extra = rs.getString("extra_text");

                rows.add(row);
            }

        } catch (Exception e) {
            System.err.println("QR Module DB Error: " + e.getMessage());
        }

        return rows;
    }

    private String percent(int part, int total) {
        if (total <= 0) {
            return "0.0";
        }

        DecimalFormat df = new DecimalFormat("0.0");
        return df.format(part * 100.0 / total);
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

    boolean canViewAnalytics = ("SUPER_ADMIN".equals(role) || "ADMIN".equals(role))
            || "ASSET_MANAGER".equals(role)
            || "AUDITOR".equals(role);

    if (!canViewAnalytics) {
        response.sendRedirect("dashboard.jsp?access=denied");
        return;
    }

    String userInitial = username.substring(0, Math.min(2, username.length())).toUpperCase(Locale.ENGLISH);

    boolean scanTableExists = false;

    int totalScans = 0;
    int todayScans = 0;
    int successScans = 0;
    int invalidScans = 0;
    int publicScans = 0;
    int uniqueAssets = 0;
    int uniqueIps = 0;

    List<MetricRow> statusRows = new ArrayList<MetricRow>();
    List<MetricRow> sourceRows = new ArrayList<MetricRow>();
    List<MetricRow> dailyRows = new ArrayList<MetricRow>();
    List<MetricRow> topAssetRows = new ArrayList<MetricRow>();
    List<MetricRow> topIpRows = new ArrayList<MetricRow>();

    try (Connection con = DBConnection.getConnection()) {
        scanTableExists = tableExists(con, "asset_qr_scan_logs");

        if (scanTableExists) {
            totalScans = countRows(con, "SELECT COUNT(*) FROM asset_qr_scan_logs");
            todayScans = countRows(con, "SELECT COUNT(*) FROM asset_qr_scan_logs WHERE DATE(scanned_at) = CURDATE()");
            successScans = countRows(con, "SELECT COUNT(*) FROM asset_qr_scan_logs WHERE scan_status = 'SUCCESS'");
            invalidScans = countRows(con, "SELECT COUNT(*) FROM asset_qr_scan_logs WHERE scan_status = 'INVALID_TOKEN'");
            publicScans = countRows(con, "SELECT COUNT(*) FROM asset_qr_scan_logs WHERE scan_source = 'PUBLIC_SCAN'");
            uniqueAssets = countRows(con, "SELECT COUNT(DISTINCT asset_id) FROM asset_qr_scan_logs WHERE asset_id IS NOT NULL");
            uniqueIps = countRows(con, "SELECT COUNT(DISTINCT scan_ip) FROM asset_qr_scan_logs WHERE scan_ip IS NOT NULL AND TRIM(scan_ip) <> ''");

            statusRows = listRows(con,
                    "SELECT "
                    + "COALESCE(scan_status, 'UNKNOWN') AS label, "
                    + "'Scan Status' AS sub_label, "
                    + "COUNT(*) AS value_text, "
                    + "CONCAT(ROUND(COUNT(*) * 100.0 / NULLIF((SELECT COUNT(*) FROM asset_qr_scan_logs),0), 1), '%') AS extra_text "
                    + "FROM asset_qr_scan_logs "
                    + "GROUP BY scan_status "
                    + "ORDER BY COUNT(*) DESC");

            sourceRows = listRows(con,
                    "SELECT "
                    + "COALESCE(scan_source, 'UNKNOWN') AS label, "
                    + "'Scan Source' AS sub_label, "
                    + "COUNT(*) AS value_text, "
                    + "CONCAT(ROUND(COUNT(*) * 100.0 / NULLIF((SELECT COUNT(*) FROM asset_qr_scan_logs),0), 1), '%') AS extra_text "
                    + "FROM asset_qr_scan_logs "
                    + "GROUP BY scan_source "
                    + "ORDER BY COUNT(*) DESC");

            dailyRows = listRows(con,
                    "SELECT "
                    + "DATE_FORMAT(DATE(scanned_at), '%d %b %Y') AS label, "
                    + "'Daily Scan Count' AS sub_label, "
                    + "COUNT(*) AS value_text, "
                    + "CONCAT(SUM(CASE WHEN scan_status='SUCCESS' THEN 1 ELSE 0 END), ' success') AS extra_text "
                    + "FROM asset_qr_scan_logs "
                    + "WHERE scanned_at >= DATE_SUB(CURDATE(), INTERVAL 14 DAY) "
                    + "GROUP BY DATE(scanned_at) "
                    + "ORDER BY DATE(scanned_at) DESC");

            topAssetRows = listRows(con,
                    "SELECT "
                    + "COALESCE(a.asset_code, 'No Linked Asset') AS label, "
                    + "COALESCE(a.asset_name, 'Invalid / Unlinked Token') AS sub_label, "
                    + "COUNT(*) AS value_text, "
                    + "CONCAT('Asset ID: ', COALESCE(CAST(q.asset_id AS CHAR), 'N/A')) AS extra_text "
                    + "FROM asset_qr_scan_logs q "
                    + "LEFT JOIN assets a ON q.asset_id = a.asset_id "
                    + "GROUP BY q.asset_id, a.asset_code, a.asset_name "
                    + "ORDER BY COUNT(*) DESC "
                    + "LIMIT 10");

            topIpRows = listRows(con,
                    "SELECT "
                    + "COALESCE(scan_ip, 'Unknown IP') AS label, "
                    + "'IP Address' AS sub_label, "
                    + "COUNT(*) AS value_text, "
                    + "CONCAT(SUM(CASE WHEN scan_status='INVALID_TOKEN' THEN 1 ELSE 0 END), ' invalid') AS extra_text "
                    + "FROM asset_qr_scan_logs "
                    + "GROUP BY scan_ip "
                    + "ORDER BY COUNT(*) DESC "
                    + "LIMIT 10");
        }

    } catch (Exception e) {
        System.err.println("QR Module DB Error: " + e.getMessage());
    }
%>

<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>QR Scan Analytics - IR-AMS</title>

    <link rel="stylesheet"
          href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.0/css/all.min.css">

    <link rel="stylesheet" href="css/ir-glass.css?v=28000">
    <link rel="stylesheet" href="css/ams-pro.css?v=28000">
    <link rel="stylesheet" href="css/ir-ams-railway-ui.css?v=28000">
<link rel="stylesheet" href="css/qr_scan_analytics.css?v=topbarfix1">
</head>

<body class="railway-ui">
<div class="app ams-shell">

        <jsp:include page="sidebar.jsp" />

    <main class="main railway-main">
                <jsp:include page="topbar.jsp" />

        <div class="main-scroll-content analytics-board">

            <section class="analytics-hero">
                <div>
                    <h1>QR Scan Analytics</h1>
                    <p>
                        Analysis of QR scan usage, success ratio, invalid attempts, daily activity,
                        top scanned assets and IP-wise QR scan behaviour.
                    </p>
                </div>

                <div class="hero-actions">
                    <a href="export_qr_scan_analytics_excel.jsp" class="action-btn green">
                        <i class="fa-solid fa-file-excel"></i>
                        Export Analytics
                    </a>

                    <a href="qr_scan_logs.jsp" class="action-btn">
                        <i class="fa-solid fa-list-check"></i>
                        Scan Logs
                    </a>

                    <a href="qr_exception_report.jsp" class="action-btn">
                        <i class="fa-solid fa-triangle-exclamation"></i>
                        Exceptions
                    </a>

                    <a href="qr_control_center.jsp" class="action-btn primary">
                        <i class="fa-solid fa-arrow-left"></i>
                        Control Center
                    </a>
                </div>
            </section>

            <% if (!scanTableExists) { %>
                <section class="panel">
                    <div class="empty-box">
                        <i class="fa-solid fa-database"></i>
                        <strong>QR scan log table not found</strong>
                        <span>Please create/import asset_qr_scan_logs table first.</span>
                    </div>
                </section>
            <% } else { %>

                <section class="kpi-grid">
                    <div class="kpi-card">
                        <h3>Total Scans</h3>
                        <p title="<%= totalScans %>"><%= formatNumber(totalScans) %></p>
                        <span>All QR scan records</span>
                    </div>

                    <div class="kpi-card">
                        <h3>Today</h3>
                        <p title="<%= todayScans %>"><%= formatNumber(todayScans) %></p>
                        <span>Scans recorded today</span>
                    </div>

                    <div class="kpi-card">
                        <h3>Success</h3>
                        <p title="<%= successScans %>"><%= formatNumber(successScans) %></p>
                        <span><%= percent(successScans, totalScans) %>% success ratio</span>
                    </div>

                    <div class="kpi-card">
                        <h3>Invalid</h3>
                        <p title="<%= invalidScans %>"><%= formatNumber(invalidScans) %></p>
                        <span><%= percent(invalidScans, totalScans) %>% invalid attempts</span>
                    </div>

                    <div class="kpi-card">
                        <h3>Public</h3>
                        <p title="<%= publicScans %>"><%= formatNumber(publicScans) %></p>
                        <span>Public QR view scans</span>
                    </div>

                    <div class="kpi-card">
                        <h3>Unique Assets</h3>
                        <p title="<%= uniqueAssets %>"><%= formatNumber(uniqueAssets) %></p>
                        <span>Assets scanned at least once</span>
                    </div>

                    <div class="kpi-card">
                        <h3>Unique IPs</h3>
                        <p title="<%= uniqueIps %>"><%= formatNumber(uniqueIps) %></p>
                        <span>Different scan IP addresses</span>
                    </div>
                </section>

                <section class="split-grid">
                    <div class="panel">
                        <h2>Status Distribution</h2>

                        <div class="metric-list">
                            <% for (MetricRow row : statusRows) { %>
                                <div class="metric-row">
                                    <div>
                                        <strong><%= safeText(cleanLabel(row.label)) %></strong>
                                        <span><%= safeText(row.subLabel) %></span>
                                    </div>
                                    <div class="metric-value">
                                        <b><%= safeText(row.value) %></b>
                                        <small><%= safeText(row.extra) %></small>
                                    </div>
                                </div>
                            <% } %>
                        </div>
                    </div>

                    <div class="panel">
                        <h2>Source Distribution</h2>

                        <div class="metric-list">
                            <% for (MetricRow row : sourceRows) { %>
                                <div class="metric-row">
                                    <div>
                                        <strong><%= safeText(cleanLabel(row.label)) %></strong>
                                        <span><%= safeText(row.subLabel) %></span>
                                    </div>
                                    <div class="metric-value">
                                        <b><%= safeText(row.value) %></b>
                                        <small><%= safeText(row.extra) %></small>
                                    </div>
                                </div>
                            <% } %>
                        </div>
                    </div>
                </section>

                <section class="split-grid">
                    <div class="panel">
                        <h2>Last 14 Days Scan Trend</h2>

                        <div class="metric-list">
                            <% for (MetricRow row : dailyRows) { %>
                                <div class="metric-row">
                                    <div>
                                        <strong><%= safeText(row.label) %></strong>
                                        <span><%= safeText(row.subLabel) %></span>
                                    </div>
                                    <div class="metric-value">
                                        <b><%= safeText(row.value) %></b>
                                        <small><%= safeText(row.extra) %></small>
                                    </div>
                                </div>
                            <% } %>
                        </div>
                    </div>

                    <div class="panel">
                        <h2>Top Scanned Assets</h2>

                        <div class="metric-list">
                            <% for (MetricRow row : topAssetRows) { %>
                                <div class="metric-row">
                                    <div>
                                        <strong><%= safeText(row.label) %></strong>
                                        <span><%= safeText(row.subLabel) %><br><%= safeText(row.extra) %></span>
                                    </div>
                                    <div class="metric-value">
                                        <b><%= safeText(row.value) %></b>
                                        <small>scans</small>
                                    </div>
                                </div>
                            <% } %>
                        </div>
                    </div>
                </section>

                <section class="panel">
                    <h2>Top IP Addresses</h2>

                    <div class="metric-list">
                        <% for (MetricRow row : topIpRows) { %>
                            <div class="metric-row">
                                <div>
                                    <strong><%= safeText(row.label) %></strong>
                                    <span><%= safeText(row.subLabel) %> &middot; <%= safeText(row.extra) %></span>
                                </div>
                                <div class="metric-value">
                                    <b><%= safeText(row.value) %></b>
                                    <small>scans</small>
                                </div>
                            </div>
                        <% } %>
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
