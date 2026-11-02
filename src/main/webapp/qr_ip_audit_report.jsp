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

    public static class IpRow {
        String ip = "";
        String totalScans = "";
        String successScans = "";
        String invalidScans = "";
        String firstScan = "";
        String lastScan = "";
        String lastStatus = "";
        String lastToken = "";
        String riskLevel = "";
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

    private String riskClass(String risk) {
        if (risk == null || risk.trim().isEmpty()) {
            return "LOW";
        }

        return risk.trim().toUpperCase(Locale.ENGLISH);
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
    String riskFilter = request.getParameter("risk");

    if (q == null) {
        q = "";
    }

    if (riskFilter == null || riskFilter.trim().isEmpty()) {
        riskFilter = "ALL";
    }

    q = q.trim();
    riskFilter = riskFilter.trim().toUpperCase(Locale.ENGLISH);

    String exportUrl = "export_qr_ip_audit_excel.jsp?risk="
            + URLEncoder.encode(riskFilter, "UTF-8");

    if (!q.isEmpty()) {
        exportUrl += "&q=" + URLEncoder.encode(q, "UTF-8");
    }

    String userInitial = username.substring(0, Math.min(2, username.length())).toUpperCase(Locale.ENGLISH);

    boolean scanTableExists = false;
    int totalIps = 0;
    int highRiskIps = 0;
    int mediumRiskIps = 0;
    int invalidAttempts = 0;

    List<IpRow> rows = new ArrayList<IpRow>();

    try (Connection con = DBConnection.getConnection()) {
        scanTableExists = tableExists(con, "asset_qr_scan_logs");

        if (scanTableExists) {
            String baseSql =
                    "SELECT "
                    + "COALESCE(scan_ip, 'Unknown IP') AS ip, "
                    + "COUNT(*) AS total_scans, "
                    + "SUM(CASE WHEN scan_status = 'SUCCESS' THEN 1 ELSE 0 END) AS success_scans, "
                    + "SUM(CASE WHEN scan_status = 'INVALID_TOKEN' THEN 1 ELSE 0 END) AS invalid_scans, "
                    + "DATE_FORMAT(MIN(scanned_at), '%d %b %Y, %h:%i %p') AS first_scan, "
                    + "DATE_FORMAT(MAX(scanned_at), '%d %b %Y, %h:%i %p') AS last_scan, "
                    + "SUBSTRING_INDEX(GROUP_CONCAT(scan_status ORDER BY scanned_at DESC SEPARATOR '||'), '||', 1) AS last_status, "
                    + "SUBSTRING_INDEX(GROUP_CONCAT(COALESCE(qr_public_token, '') ORDER BY scanned_at DESC SEPARATOR '||'), '||', 1) AS last_token, "
                    + "CASE "
                    + "WHEN SUM(CASE WHEN scan_status = 'INVALID_TOKEN' THEN 1 ELSE 0 END) >= 5 THEN 'HIGH' "
                    + "WHEN SUM(CASE WHEN scan_status = 'INVALID_TOKEN' THEN 1 ELSE 0 END) BETWEEN 1 AND 4 THEN 'MEDIUM' "
                    + "ELSE 'LOW' "
                    + "END AS risk_level "
                    + "FROM asset_qr_scan_logs "
                    + "WHERE 1 = 1 ";

            List<String> params = new ArrayList<String>();

            if (!q.isEmpty()) {
                baseSql += "AND (scan_ip LIKE ? OR qr_public_token LIKE ? OR scan_status LIKE ? OR remarks LIKE ?) ";

                String searchValue = "%" + q + "%";

                for (int i = 0; i < 4; i++) {
                    params.add(searchValue);
                }
            }

            baseSql += "GROUP BY scan_ip ";

            if (!"ALL".equals(riskFilter)) {
                baseSql += "HAVING risk_level = ? ";
                params.add(riskFilter);
            }

            String sql = baseSql + "ORDER BY invalid_scans DESC, total_scans DESC LIMIT 300";

            try (PreparedStatement ps = con.prepareStatement(sql)) {
                for (int i = 0; i < params.size(); i++) {
                    ps.setString(i + 1, params.get(i));
                }

                try (ResultSet rs = ps.executeQuery()) {
                    while (rs.next()) {
                        IpRow row = new IpRow();

                        row.ip = rs.getString("ip");
                        row.totalScans = rs.getString("total_scans");
                        row.successScans = rs.getString("success_scans");
                        row.invalidScans = rs.getString("invalid_scans");
                        row.firstScan = rs.getString("first_scan");
                        row.lastScan = rs.getString("last_scan");
                        row.lastStatus = rs.getString("last_status");
                        row.lastToken = rs.getString("last_token");
                        row.riskLevel = rs.getString("risk_level");

                        rows.add(row);
                    }
                }
            }

            totalIps = countRows(con,
                    "SELECT COUNT(DISTINCT scan_ip) FROM asset_qr_scan_logs WHERE scan_ip IS NOT NULL AND TRIM(scan_ip) <> ''",
                    new ArrayList<String>());

            highRiskIps = countRows(con,
                    "SELECT COUNT(*) FROM ("
                    + "SELECT scan_ip FROM asset_qr_scan_logs GROUP BY scan_ip "
                    + "HAVING SUM(CASE WHEN scan_status='INVALID_TOKEN' THEN 1 ELSE 0 END) >= 5"
                    + ") t",
                    new ArrayList<String>());

            mediumRiskIps = countRows(con,
                    "SELECT COUNT(*) FROM ("
                    + "SELECT scan_ip FROM asset_qr_scan_logs GROUP BY scan_ip "
                    + "HAVING SUM(CASE WHEN scan_status='INVALID_TOKEN' THEN 1 ELSE 0 END) BETWEEN 1 AND 4"
                    + ") t",
                    new ArrayList<String>());

            invalidAttempts = countRows(con,
                    "SELECT COUNT(*) FROM asset_qr_scan_logs WHERE scan_status='INVALID_TOKEN'",
                    new ArrayList<String>());
        }

    } catch (Exception e) {
        System.err.println("QR Module DB Error: " + e.getMessage());
    }
%>

<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>QR IP Audit Report - IR-AMS</title>

    <link rel="stylesheet"
          href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.0/css/all.min.css">

    <link rel="stylesheet" href="css/ir-glass.css?v=28000">
    <link rel="stylesheet" href="css/ams-pro.css?v=28000">
    <link rel="stylesheet" href="css/ir-ams-railway-ui.css?v=28000">
<link rel="stylesheet" href="css/qr_ip_audit_report.css?v=topbarfix1">
</head>

<body class="railway-ui">
<div class="app ams-shell">

        <jsp:include page="sidebar.jsp" />

    <main class="main railway-main">
                <jsp:include page="topbar.jsp" />

        <div class="main-scroll-content ip-board">

            <section class="ip-hero">
                <div>
                    <h1>QR IP Audit Report</h1>
                    <p>
                        IP-wise QR scan audit report showing total scans, invalid token attempts, first/last scan time and risk level.
                    </p>
                </div>

                <div class="hero-actions">
                    <a href="<%= safeText(exportUrl) %>" class="action-btn green">
                        <i class="fa-solid fa-file-excel"></i>
                        Export Excel
                    </a>

                    <a href="qr_asset_scan_history.jsp" class="action-btn">
                        <i class="fa-solid fa-clock-rotate-left"></i>
                        Asset History
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

            <section class="kpi-grid">
                <div class="kpi-card">
                    <h3>Total IPs</h3>
                    <p title="<%= totalIps %>"><%= formatNumber(totalIps) %></p>
                    <span>Unique scan IP addresses</span>
                </div>

                <div class="kpi-card">
                    <h3>High Risk IPs</h3>
                    <p title="<%= highRiskIps %>"><%= formatNumber(highRiskIps) %></p>
                    <span>5 or more invalid scans</span>
                </div>

                <div class="kpi-card">
                    <h3>Medium Risk IPs</h3>
                    <p title="<%= mediumRiskIps %>"><%= formatNumber(mediumRiskIps) %></p>
                    <span>1 to 4 invalid scans</span>
                </div>

                <div class="kpi-card">
                    <h3>Invalid Attempts</h3>
                    <p title="<%= invalidAttempts %>"><%= formatNumber(invalidAttempts) %></p>
                    <span>Total invalid token scans</span>
                </div>
            </section>

            <section class="panel">
                <div class="toolbar">
                    <div>
                        <h2>IP-wise QR Scan Audit</h2>
                        <p class="table-subtext">Showing <%= rows.size() %> matching IP records. Maximum 300 records shown.</p>
                    </div>

                    <form class="filter-form" method="get" action="qr_ip_audit_report.jsp">
                        <input class="filter-input"
                               type="text"
                               name="q"
                               value="<%= q.isEmpty() ? "" : safeText(q) %>"
                               placeholder="Search IP, token, status, remarks...">

                        <select class="filter-select" name="risk">
                            <option value="ALL" <%= "ALL".equals(riskFilter) ? "selected" : "" %>>All Risk</option>
                            <option value="HIGH" <%= "HIGH".equals(riskFilter) ? "selected" : "" %>>High Risk</option>
                            <option value="MEDIUM" <%= "MEDIUM".equals(riskFilter) ? "selected" : "" %>>Medium Risk</option>
                            <option value="LOW" <%= "LOW".equals(riskFilter) ? "selected" : "" %>>Low Risk</option>
                        </select>

                        <button class="action-btn primary" type="submit">
                            <i class="fa-solid fa-filter"></i>
                            Filter
                        </button>

                        <a class="action-btn green" href="<%= safeText(exportUrl) %>">
                            <i class="fa-solid fa-file-excel"></i>
                            Export
                        </a>

                        <a class="action-btn" href="qr_ip_audit_report.jsp">
                            <i class="fa-solid fa-rotate-right"></i>
                            Reset
                        </a>
                    </form>
                </div>

                <% if (!scanTableExists) { %>
                    <span class="pill risk-HIGH">asset_qr_scan_logs table not found</span>
                <% } else { %>
                    <div class="table-wrap">
                        <table class="ip-table">
                            <thead>
                                <tr>
                                    <th>IP Address</th>
                                    <th>Total Scans</th>
                                    <th>Success</th>
                                    <th>Invalid</th>
                                    <th>Risk</th>
                                    <th>First Scan</th>
                                    <th>Last Scan</th>
                                    <th>Last Status</th>
                                    <th>Last Token</th>
                                    <th>Open Logs</th>
                                </tr>
                            </thead>

                            <tbody>
                                <% for (IpRow row : rows) { %>
                                    <tr>
                                        <td>
                                            <strong><%= safeText(row.ip) %></strong>
                                        </td>

                                        <td><%= safeText(row.totalScans) %></td>
                                        <td><%= safeText(row.successScans) %></td>
                                        <td><%= safeText(row.invalidScans) %></td>

                                        <td>
                                            <span class="pill risk-<%= safeText(riskClass(row.riskLevel)) %>">
                                                <%= safeText(row.riskLevel) %>
                                            </span>
                                        </td>

                                        <td><%= safeText(row.firstScan) %></td>
                                        <td><%= safeText(row.lastScan) %></td>
                                        <td><%= safeText(cleanLabel(row.lastStatus)) %></td>

                                        <td>
                                            <span class="pill" title="<%= safeText(row.lastToken) %>">
                                                <%= safeText(row.lastToken) %>
                                            </span>
                                        </td>

                                        <td>
                                            <a class="action-btn primary" href="qr_asset_scan_history.jsp?q=<%= URLEncoder.encode(row.ip, "UTF-8") %>">
                                                Logs
                                            </a>
                                        </td>
                                    </tr>
                                <% } %>

                                <% if (rows.isEmpty()) { %>
                                    <tr>
                                        <td colspan="10">
                                            <span class="pill">No IP audit record found for selected filter.</span>
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