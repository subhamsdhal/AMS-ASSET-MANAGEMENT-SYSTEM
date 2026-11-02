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

    public static class ScanLogRow {
        String scanId = "";
        String assetId = "";
        String assetCode = "";
        String assetName = "";
        String qrPublicToken = "";
        String scanSource = "";
        String scanIp = "";
        String scanUserAgent = "";
        String scanStatus = "";
        String remarks = "";
        String scannedAt = "";
        String scannedByUser = "";
        String scannedByEmployee = "";
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
        String sql = "SELECT COUNT(*) FROM information_schema.tables "
                + "WHERE table_schema = DATABASE() AND table_name = ?";

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

    boolean canViewQrLogs = ("SUPER_ADMIN".equals(role) || "ADMIN".equals(role))
            || "ASSET_MANAGER".equals(role)
            || "AUDITOR".equals(role);

    if (!canViewQrLogs) {
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

    String exportUrl = "export_qr_scan_logs.jsp?status="
            + URLEncoder.encode(statusFilter, "UTF-8");

    if (!q.isEmpty()) {
        exportUrl += "&q=" + URLEncoder.encode(q, "UTF-8");
    }

    String userInitial = username.substring(0, Math.min(2, username.length())).toUpperCase(Locale.ENGLISH);

    int totalLogs = 0;
    int todayLogs = 0;
    int successLogs = 0;
    int invalidLogs = 0;
    int publicLogs = 0;
    int filteredCount = 0;

    List<ScanLogRow> rows = new ArrayList<ScanLogRow>();
    boolean scanTableExists = false;

    try (Connection con = DBConnection.getConnection()) {
        scanTableExists = tableExists(con, "asset_qr_scan_logs");

        if (scanTableExists) {
            totalLogs = countRows(con, "SELECT COUNT(*) FROM asset_qr_scan_logs");
            todayLogs = countRows(con, "SELECT COUNT(*) FROM asset_qr_scan_logs WHERE DATE(scanned_at) = CURDATE()");
            successLogs = countRows(con, "SELECT COUNT(*) FROM asset_qr_scan_logs WHERE scan_status = 'SUCCESS'");
            invalidLogs = countRows(con, "SELECT COUNT(*) FROM asset_qr_scan_logs WHERE scan_status = 'INVALID_TOKEN'");
            publicLogs = countRows(con, "SELECT COUNT(*) FROM asset_qr_scan_logs WHERE scan_source = 'PUBLIC_SCAN'");

            StringBuilder sql = new StringBuilder();

            sql.append("SELECT ")
                    .append("q.scan_id, q.asset_id, q.qr_public_token, q.scan_source, q.scan_ip, ")
                    .append("q.scan_user_agent, q.scan_status, q.remarks, ")
                    .append("DATE_FORMAT(q.scanned_at, '%d %b %Y, %h:%i %p') AS scanned_at, ")
                    .append("COALESCE(a.asset_code, 'Unknown Asset') AS asset_code, ")
                    .append("COALESCE(a.asset_name, 'Asset not linked') AS asset_name, ")
                    .append("COALESCE(u.username, 'Public / System') AS scanned_by_user, ")
                    .append("COALESCE(e.employee_name, 'Not Applicable') AS scanned_by_employee ")
                    .append("FROM asset_qr_scan_logs q ")
                    .append("LEFT JOIN assets a ON q.asset_id = a.asset_id ")
                    .append("LEFT JOIN users u ON q.scanned_by_user_id = u.user_id ")
                    .append("LEFT JOIN employees e ON q.scanned_by_employee_id = e.employee_id ")
                    .append("WHERE 1 = 1 ");

            List<String> params = new ArrayList<String>();

            if (!"ALL".equals(statusFilter)) {
                sql.append("AND q.scan_status = ? ");
                params.add(statusFilter);
            }

            if (!q.isEmpty()) {
                sql.append("AND (")
                        .append("a.asset_code LIKE ? ")
                        .append("OR a.asset_name LIKE ? ")
                        .append("OR q.qr_public_token LIKE ? ")
                        .append("OR q.scan_ip LIKE ? ")
                        .append("OR q.scan_user_agent LIKE ? ")
                        .append("OR q.remarks LIKE ? ")
                        .append("OR q.scan_source LIKE ? ")
                        .append("OR q.scan_status LIKE ? ")
                        .append(") ");

                String searchValue = "%" + q + "%";

                for (int i = 0; i < 8; i++) {
                    params.add(searchValue);
                }
            }

            sql.append("ORDER BY q.scan_id DESC LIMIT 250");

            try (PreparedStatement ps = con.prepareStatement(sql.toString())) {
                for (int i = 0; i < params.size(); i++) {
                    ps.setString(i + 1, params.get(i));
                }

                try (ResultSet rs = ps.executeQuery()) {
                    while (rs.next()) {
                        ScanLogRow row = new ScanLogRow();

                        row.scanId = rs.getString("scan_id");
                        row.assetId = rs.getString("asset_id");
                        row.assetCode = rs.getString("asset_code");
                        row.assetName = rs.getString("asset_name");
                        row.qrPublicToken = rs.getString("qr_public_token");
                        row.scanSource = rs.getString("scan_source");
                        row.scanIp = rs.getString("scan_ip");
                        row.scanUserAgent = rs.getString("scan_user_agent");
                        row.scanStatus = rs.getString("scan_status");
                        row.remarks = rs.getString("remarks");
                        row.scannedAt = rs.getString("scanned_at");
                        row.scannedByUser = rs.getString("scanned_by_user");
                        row.scannedByEmployee = rs.getString("scanned_by_employee");

                        rows.add(row);
                    }
                }
            }

            filteredCount = rows.size();
        }

    } catch (Exception e) {
        System.err.println("QR Module DB Error: " + e.getMessage());
    }
%>

<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>QR Scan Logs - IR-AMS</title>

    <link rel="stylesheet"
          href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.0/css/all.min.css">

    <link rel="stylesheet" href="css/ir-glass.css?v=28000">
    <link rel="stylesheet" href="css/ams-pro.css?v=28000">
    <link rel="stylesheet" href="css/ir-ams-railway-ui.css?v=28000">
<link rel="stylesheet" href="css/qr_scan_logs.css?v=topbarfix1">
        </head>

<body class="railway-ui">
<div class="app ams-shell">

    
    <jsp:include page="sidebar.jsp" />

    <main class="main railway-main">
        
        <jsp:include page="topbar.jsp" />

        <div class="main-scroll-content qr-log-board">

            <section class="qr-log-hero">
                <div>
                    <h1>QR Scan Logs</h1>
                    <p>
                        Official audit register of public QR scans, invalid token attempts, IP address,
                        scan source, browser/mobile details and linked asset information.
                    </p>
                </div>

                <div class="hero-actions">
                    <a href="<%= safeText(exportUrl) %>" class="action-btn green">
                        <i class="fa-solid fa-file-excel"></i>
                        Export Excel
                    </a>

                    <a href="qr_scanner.jsp" class="action-btn">
                        <i class="fa-solid fa-qrcode"></i>
                        QR Scanner
                    </a>

                    <a href="assets.jsp" class="action-btn">
                        <i class="fa-solid fa-cubes"></i>
                        Assets
                    </a>

                    <a href="reports.jsp" class="action-btn primary">
                        <i class="fa-solid fa-chart-line"></i>
                        Reports
                    </a>
                </div>
            </section>

            <section class="kpi-grid">
                <div class="kpi-card">
                    <div class="kpi-icon"><i class="fa-solid fa-list-check"></i></div>
                    <h3>Total Scans</h3>
                    <p><%= totalLogs %></p>
                </div>

                <div class="kpi-card">
                    <div class="kpi-icon"><i class="fa-solid fa-calendar-day"></i></div>
                    <h3>Today</h3>
                    <p><%= todayLogs %></p>
                </div>

                <div class="kpi-card">
                    <div class="kpi-icon"><i class="fa-solid fa-circle-check"></i></div>
                    <h3>Successful</h3>
                    <p><%= successLogs %></p>
                </div>

                <div class="kpi-card">
                    <div class="kpi-icon"><i class="fa-solid fa-triangle-exclamation"></i></div>
                    <h3>Invalid</h3>
                    <p><%= invalidLogs %></p>
                </div>

                <div class="kpi-card">
                    <div class="kpi-icon"><i class="fa-solid fa-globe"></i></div>
                    <h3>Public Scan</h3>
                    <p><%= publicLogs %></p>
                </div>
            </section>

            <section class="log-panel">
                <div class="log-toolbar">
                    <div>
                        <h2>QR Scan Audit Register</h2>
                        <p class="table-subtext">
                            Showing <%= filteredCount %> latest matching scan records. Maximum 250 records shown.
                        </p>
                    </div>

                    <form class="filter-form" method="get" action="qr_scan_logs.jsp">
                        <input class="filter-input"
                               type="text"
                               name="q"
                               value="<%= q.isEmpty() ? "" : safeText(q) %>"
                               placeholder="Search asset, token, IP, source, remarks...">

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

                        <a class="action-btn" href="qr_scan_logs.jsp">
                            <i class="fa-solid fa-rotate-right"></i>
                            Reset
                        </a>
                    </form>
                </div>

                <% if (!scanTableExists) { %>
                    <div class="empty-box">
                        <i class="fa-solid fa-database"></i>
                        <strong>QR scan log table not found</strong>
                        <span>Please create/import asset_qr_scan_logs table first.</span>
                    </div>
                <% } else if (rows.isEmpty()) { %>
                    <div class="empty-box">
                        <i class="fa-solid fa-folder-open"></i>
                        <strong>No QR scan log found</strong>
                        <span>Scan an asset QR or open a public QR link to create scan history.</span>
                    </div>
                <% } else { %>
                    <div class="log-table-wrap">
                        <table class="log-table" id="scanLogsTable">
                            <thead>
                                <tr>
                                    <th onclick="sortTable(0)" style="cursor: pointer;" title="Click to sort">Scan ID <i class="fa-solid fa-sort" style="color: #cbd5e1; margin-left: 4px;"></i></th>
                                    <th onclick="sortTable(1)" style="cursor: pointer;" title="Click to sort">Asset <i class="fa-solid fa-sort" style="color: #cbd5e1; margin-left: 4px;"></i></th>
                                    <th onclick="sortTable(2)" style="cursor: pointer;" title="Click to sort">Token Used <i class="fa-solid fa-sort" style="color: #cbd5e1; margin-left: 4px;"></i></th>
                                    <th onclick="sortTable(3)" style="cursor: pointer;" title="Click to sort">Status <i class="fa-solid fa-sort" style="color: #cbd5e1; margin-left: 4px;"></i></th>
                                    <th onclick="sortTable(4)" style="cursor: pointer;" title="Click to sort">Source <i class="fa-solid fa-sort" style="color: #cbd5e1; margin-left: 4px;"></i></th>
                                    <th onclick="sortTable(5)" style="cursor: pointer;" title="Click to sort">IP Address <i class="fa-solid fa-sort" style="color: #cbd5e1; margin-left: 4px;"></i></th>
                                    <th onclick="sortTable(6)" style="cursor: pointer;" title="Click to sort">Scanned By <i class="fa-solid fa-sort" style="color: #cbd5e1; margin-left: 4px;"></i></th>
                                    <th onclick="sortTable(7)" style="cursor: pointer;" title="Click to sort">Browser / Device <i class="fa-solid fa-sort" style="color: #cbd5e1; margin-left: 4px;"></i></th>
                                    <th onclick="sortTable(8)" style="cursor: pointer;" title="Click to sort">Remarks <i class="fa-solid fa-sort" style="color: #cbd5e1; margin-left: 4px;"></i></th>
                                    <th onclick="sortTable(9)" style="cursor: pointer;" title="Click to sort">Scanned At <i class="fa-solid fa-sort" style="color: #cbd5e1; margin-left: 4px;"></i></th>
                                    <th>Open</th>
                                </tr>
                            </thead>

                            <tbody>
                                <% for (ScanLogRow row : rows) { %>
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
                                            <span class="token-pill" title="<%= safeText(row.qrPublicToken) %>">
                                                <i class="fa-solid fa-key"></i>
                                                <%= safeText(row.qrPublicToken) %>
                                            </span>
                                        </td>

                                        <td>
                                            <span class="status-badge status-<%= safeText(statusClass(row.scanStatus)) %>">
                                                <%= safeText(cleanLabel(row.scanStatus)) %>
                                            </span>
                                        </td>

                                        <td>
                                            <span class="source-pill">
                                                <i class="fa-solid fa-globe"></i>
                                                <%= safeText(cleanLabel(row.scanSource)) %>
                                            </span>
                                        </td>

                                        <td><%= safeText(row.scanIp) %></td>

                                        <td>
                                            <div class="asset-title">
                                                <strong><%= safeText(row.scannedByUser) %></strong>
                                                <span><%= safeText(row.scannedByEmployee) %></span>
                                            </div>
                                        </td>

                                        <td>
                                            <div class="ua-box" title="<%= safeText(row.scanUserAgent) %>">
                                                <%= safeText(limitText(row.scanUserAgent, 120)) %>
                                            </div>
                                        </td>

                                        <td>
                                            <div class="ua-box">
                                                <%= safeText(limitText(row.remarks, 100)) %>
                                            </div>
                                        </td>

                                        <td><%= safeText(row.scannedAt) %></td>

                                        <td>
                                            <% if (row.assetId != null && !row.assetId.trim().isEmpty()) { %>
                                                <a class="action-btn" href="view_asset.jsp?id=<%= safeText(row.assetId) %>">
                                                    <i class="fa-solid fa-up-right-from-square"></i>
                                                    Asset
                                                </a>
                                            <% } else { %>
                                                <span class="source-pill">No Link</span>
                                            <% } %>
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
<script>
    var sortDirections = [true, true, true, true, true, true, true, true, true, true, true];
    
    function sortTable(columnIndex) {
        var table = document.getElementById("scanLogsTable");
        var tbody = table.querySelector("tbody");
        var rows = Array.from(tbody.querySelectorAll("tr"));
        
        if (rows.length === 0) return;
        if (rows.length === 1 && rows[0].querySelector("td[colspan]")) return;

        var asc = sortDirections[columnIndex];
        sortDirections[columnIndex] = !asc;

        rows.sort(function(a, b) {
            var cellA = a.querySelectorAll("td")[columnIndex];
            var cellB = b.querySelectorAll("td")[columnIndex];

            if (!cellA || !cellB) return 0;
            
            var valA = cellA.innerText || cellA.textContent;
            var valB = cellB.innerText || cellB.textContent;
            
            valA = valA.trim().toLowerCase();
            valB = valB.trim().toLowerCase();
            
            if (valA < valB) return asc ? -1 : 1;
            if (valA > valB) return asc ? 1 : -1;
            return 0;
        });

        rows.forEach(function(row) {
            tbody.appendChild(row);
        });
        
        var headers = table.querySelectorAll("thead th");
        headers.forEach(function(th, idx) {
            var icon = th.querySelector("i.fa-sort, i.fa-sort-up, i.fa-sort-down");
            if (icon) {
                icon.className = "fa-solid fa-sort";
                if (idx === columnIndex) {
                    icon.className = asc ? "fa-solid fa-sort-up" : "fa-solid fa-sort-down";
                }
            }
        });
    }
</script>

</body>
</html>
