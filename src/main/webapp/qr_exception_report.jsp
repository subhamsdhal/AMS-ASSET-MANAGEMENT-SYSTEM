<%@page contentType="text/html" pageEncoding="UTF-8"%>
<%@page import="com.mycompany.asset_management_system_ams.DBConnection"%>
<%@page import="java.sql.*"%>
<%@page import="java.util.*"%>
<%@page import="java.net.URLEncoder"%>
<%@page import="jakarta.servlet.http.HttpServletRequest"%>

<%!
    public String formatNumber(int number) {
        if (number >= 100000) {
            return String.format("%.1fL", number / 100000.0);
        } else if (number >= 1000) {
            return String.format("%.1fK", number / 1000.0);
        }
        return String.valueOf(number);
    }

    public static class ExceptionRow {
        String issueType = "";
        String severity = "";
        String assetId = "";
        String assetCode = "";
        String assetName = "";
        String departmentName = "";
        String assetStatus = "";
        String token = "";
        String storedUrl = "";
        String expectedUrl = "";
        String refTime = "";
        String details = "";
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

    private int countPrepared(Connection con, String sql, String value) {
        try (PreparedStatement ps = con.prepareStatement(sql)) {
            ps.setString(1, value);

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

    private String statusClass(String value) {
        if (value == null || value.trim().isEmpty()) {
            return "UNKNOWN";
        }

        return value.trim().toUpperCase(Locale.ENGLISH).replace(" ", "_");
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

    boolean canViewExceptionReport = ("SUPER_ADMIN".equals(role) || "ADMIN".equals(role))
            || "ASSET_MANAGER".equals(role)
            || "AUDITOR".equals(role);

    if (!canViewExceptionReport) {
        response.sendRedirect("dashboard.jsp?access=denied");
        return;
    }

    String q = request.getParameter("q");
    String issueFilter = request.getParameter("issue");

    if (q == null) {
        q = "";
    }

    if (issueFilter == null || issueFilter.trim().isEmpty()) {
        issueFilter = "ALL";
    }

    q = q.trim();
    issueFilter = issueFilter.trim().toUpperCase(Locale.ENGLISH);

    String baseUrl = appBaseUrl(request);

    String exportUrl = "export_qr_exception_report_excel.jsp?issue=" + URLEncoder.encode(issueFilter, "UTF-8");

    if (!q.isEmpty()) {
        exportUrl += "&q=" + URLEncoder.encode(q, "UTF-8");
    }

    String userInitial = username.substring(0, Math.min(2, username.length())).toUpperCase(Locale.ENGLISH);

    int totalAssets = 0;
    int missingTokenCount = 0;
    int urlMismatchCount = 0;
    int invalidTokenCount = 0;
    int filteredCount = 0;

    boolean scanTableExists = false;

    List<ExceptionRow> rows = new ArrayList<ExceptionRow>();

    try (Connection con = DBConnection.getConnection()) {
        totalAssets = countRows(con, "SELECT COUNT(*) FROM assets");

        missingTokenCount = countRows(con,
                "SELECT COUNT(*) FROM assets "
                + "WHERE qr_public_token IS NULL OR TRIM(qr_public_token) = ''");

        urlMismatchCount = countPrepared(con,
                "SELECT COUNT(*) FROM assets "
                + "WHERE qr_public_token IS NOT NULL AND TRIM(qr_public_token) <> '' "
                + "AND (qr_code IS NULL OR TRIM(qr_code) = '' "
                + "OR qr_code <> CONCAT(?, '/public_asset_view.jsp?token=', qr_public_token))",
                baseUrl);

        scanTableExists = tableExists(con, "asset_qr_scan_logs");

        if (scanTableExists) {
            invalidTokenCount = countRows(con,
                    "SELECT COUNT(*) FROM asset_qr_scan_logs WHERE scan_status = 'INVALID_TOKEN'");
        }

        if ("ALL".equals(issueFilter) || "MISSING_TOKEN".equals(issueFilter)) {
            StringBuilder sql = new StringBuilder();

            sql.append("SELECT ")
                    .append("a.asset_id, a.asset_code, a.asset_name, a.asset_status, ")
                    .append("COALESCE(d.department_name, 'Unassigned') AS department_name, ")
                    .append("COALESCE(a.qr_public_token, '') AS token_value, ")
                    .append("COALESCE(a.qr_code, '') AS stored_url, ")
                    .append("DATE_FORMAT(a.updated_at, '%d %b %Y, %h:%i %p') AS ref_time ")
                    .append("FROM assets a ")
                    .append("LEFT JOIN departments d ON a.department_id = d.department_id ")
                    .append("WHERE a.qr_public_token IS NULL OR TRIM(a.qr_public_token) = '' ");

            List<String> params = new ArrayList<String>();

            if (!q.isEmpty()) {
                sql.append("AND (a.asset_code LIKE ? OR a.asset_name LIKE ? OR d.department_name LIKE ?) ");

                String searchValue = "%" + q + "%";
                params.add(searchValue);
                params.add(searchValue);
                params.add(searchValue);
            }

            sql.append("ORDER BY a.asset_id DESC LIMIT 150");

            try (PreparedStatement ps = con.prepareStatement(sql.toString())) {
                for (int i = 0; i < params.size(); i++) {
                    ps.setString(i + 1, params.get(i));
                }

                try (ResultSet rs = ps.executeQuery()) {
                    while (rs.next()) {
                        ExceptionRow row = new ExceptionRow();

                        row.issueType = "MISSING_TOKEN";
                        row.severity = "HIGH";
                        row.assetId = rs.getString("asset_id");
                        row.assetCode = rs.getString("asset_code");
                        row.assetName = rs.getString("asset_name");
                        row.departmentName = rs.getString("department_name");
                        row.assetStatus = rs.getString("asset_status");
                        row.token = rs.getString("token_value");
                        row.storedUrl = rs.getString("stored_url");
                        row.expectedUrl = "Generate QR token first";
                        row.refTime = rs.getString("ref_time");
                        row.details = "Asset does not have QR public token. Generate QR before printing label.";

                        rows.add(row);
                    }
                }
            }
        }

        if ("ALL".equals(issueFilter) || "URL_MISMATCH".equals(issueFilter)) {
            StringBuilder sql = new StringBuilder();

            sql.append("SELECT ")
                    .append("a.asset_id, a.asset_code, a.asset_name, a.asset_status, ")
                    .append("COALESCE(d.department_name, 'Unassigned') AS department_name, ")
                    .append("a.qr_public_token AS token_value, ")
                    .append("COALESCE(a.qr_code, '') AS stored_url, ")
                    .append("DATE_FORMAT(a.updated_at, '%d %b %Y, %h:%i %p') AS ref_time ")
                    .append("FROM assets a ")
                    .append("LEFT JOIN departments d ON a.department_id = d.department_id ")
                    .append("WHERE a.qr_public_token IS NOT NULL AND TRIM(a.qr_public_token) <> '' ")
                    .append("AND (a.qr_code IS NULL OR TRIM(a.qr_code) = '' ")
                    .append("OR a.qr_code <> CONCAT(?, '/public_asset_view.jsp?token=', a.qr_public_token)) ");

            List<String> params = new ArrayList<String>();
            params.add(baseUrl);

            if (!q.isEmpty()) {
                sql.append("AND (a.asset_code LIKE ? OR a.asset_name LIKE ? OR d.department_name LIKE ? OR a.qr_public_token LIKE ? OR a.qr_code LIKE ?) ");

                String searchValue = "%" + q + "%";

                for (int i = 0; i < 5; i++) {
                    params.add(searchValue);
                }
            }

            sql.append("ORDER BY a.asset_id DESC LIMIT 150");

            try (PreparedStatement ps = con.prepareStatement(sql.toString())) {
                for (int i = 0; i < params.size(); i++) {
                    ps.setString(i + 1, params.get(i));
                }

                try (ResultSet rs = ps.executeQuery()) {
                    while (rs.next()) {
                        ExceptionRow row = new ExceptionRow();

                        row.issueType = "URL_MISMATCH";
                        row.severity = "MEDIUM";
                        row.assetId = rs.getString("asset_id");
                        row.assetCode = rs.getString("asset_code");
                        row.assetName = rs.getString("asset_name");
                        row.departmentName = rs.getString("department_name");
                        row.assetStatus = rs.getString("asset_status");
                        row.token = rs.getString("token_value");
                        row.storedUrl = rs.getString("stored_url");
                        row.expectedUrl = baseUrl + "/public_asset_view.jsp?token=" + row.token;
                        row.refTime = rs.getString("ref_time");
                        row.details = "Stored QR URL does not match current application base URL. Use QR URL Refresh.";

                        rows.add(row);
                    }
                }
            }
        }

        if (scanTableExists && ("ALL".equals(issueFilter) || "INVALID_TOKEN".equals(issueFilter))) {
            StringBuilder sql = new StringBuilder();

            sql.append("SELECT ")
                    .append("q.asset_id, COALESCE(a.asset_code, 'No Linked Asset') AS asset_code, ")
                    .append("COALESCE(a.asset_name, 'Invalid token was not linked with any asset') AS asset_name, ")
                    .append("COALESCE(a.asset_status, '') AS asset_status, ")
                    .append("COALESCE(d.department_name, 'Not Available') AS department_name, ")
                    .append("COALESCE(q.qr_public_token, '') AS token_value, ")
                    .append("COALESCE(q.remarks, '') AS details, ")
                    .append("DATE_FORMAT(q.scanned_at, '%d %b %Y, %h:%i %p') AS ref_time ")
                    .append("FROM asset_qr_scan_logs q ")
                    .append("LEFT JOIN assets a ON q.asset_id = a.asset_id ")
                    .append("LEFT JOIN departments d ON a.department_id = d.department_id ")
                    .append("WHERE q.scan_status = 'INVALID_TOKEN' ");

            List<String> params = new ArrayList<String>();

            if (!q.isEmpty()) {
                sql.append("AND (a.asset_code LIKE ? OR a.asset_name LIKE ? OR d.department_name LIKE ? OR q.qr_public_token LIKE ? OR q.remarks LIKE ?) ");

                String searchValue = "%" + q + "%";

                for (int i = 0; i < 5; i++) {
                    params.add(searchValue);
                }
            }

            sql.append("ORDER BY q.scan_id DESC LIMIT 150");

            try (PreparedStatement ps = con.prepareStatement(sql.toString())) {
                for (int i = 0; i < params.size(); i++) {
                    ps.setString(i + 1, params.get(i));
                }

                try (ResultSet rs = ps.executeQuery()) {
                    while (rs.next()) {
                        ExceptionRow row = new ExceptionRow();

                        row.issueType = "INVALID_TOKEN";
                        row.severity = "LOW";
                        row.assetId = rs.getString("asset_id");
                        row.assetCode = rs.getString("asset_code");
                        row.assetName = rs.getString("asset_name");
                        row.departmentName = rs.getString("department_name");
                        row.assetStatus = rs.getString("asset_status");
                        row.token = rs.getString("token_value");
                        row.storedUrl = "N/A";
                        row.expectedUrl = "No matching asset found";
                        row.refTime = rs.getString("ref_time");
                        row.details = rs.getString("details");

                        rows.add(row);
                    }
                }
            }
        }

        filteredCount = rows.size();

    } catch (Exception e) {
        System.err.println("QR Module DB Error: " + e.getMessage());
    }
%>

<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>QR Exception Report - IR-AMS</title>

    <link rel="stylesheet"
          href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.0/css/all.min.css">

    <link rel="stylesheet" href="css/ir-glass.css?v=28000">
    <link rel="stylesheet" href="css/ams-pro.css?v=28000">
    <link rel="stylesheet" href="css/ir-ams-railway-ui.css?v=28000">
<link rel="stylesheet" href="css/qr_exception_report.css?v=topbarfix1">
</head>

<body class="railway-ui">
<div class="app ams-shell">

        <jsp:include page="sidebar.jsp" />

    <main class="main railway-main">
                <jsp:include page="topbar.jsp" />

        <div class="main-scroll-content exception-board">

            <section class="exception-hero">
                <div>
                    <h1>QR Exception Report</h1>
                    <p>
                        Official exception register for missing QR tokens, QR URL mismatches,
                        and invalid public QR scan attempts.
                    </p>
                </div>

                <div class="hero-actions">
                    <a href="<%= safeText(exportUrl) %>" class="action-btn green">
                        <i class="fa-solid fa-file-excel"></i>
                        Export Excel
                    </a>

                    <a href="qr_url_refresh.jsp" class="action-btn primary">
                        <i class="fa-solid fa-link"></i>
                        Fix URL Mismatch
                    </a>

                    <a href="qr_bulk_generate.jsp" class="action-btn">
                        <i class="fa-solid fa-wand-magic-sparkles"></i>
                        Generate Missing QR
                    </a>

                    <a href="qr_control_center.jsp" class="action-btn">
                        <i class="fa-solid fa-arrow-left"></i>
                        Control Center
                    </a>
                </div>
            </section>

            <section class="kpi-grid">
                <div class="kpi-card">
                    <div class="kpi-icon"><i class="fa-solid fa-cubes"></i></div>
                    <h3>Total Assets</h3>
                    <p><%= totalAssets %></p>
                </div>

                <div class="kpi-card">
                    <div class="kpi-icon"><i class="fa-solid fa-key"></i></div>
                    <h3>Missing Token</h3>
                    <p><%= missingTokenCount %></p>
                </div>

                <div class="kpi-card">
                    <div class="kpi-icon"><i class="fa-solid fa-link-slash"></i></div>
                    <h3>URL Mismatch</h3>
                    <p><%= urlMismatchCount %></p>
                </div>

                <div class="kpi-card">
                    <div class="kpi-icon"><i class="fa-solid fa-ban"></i></div>
                    <h3>Invalid Scans</h3>
                    <p><%= invalidTokenCount %></p>
                </div>

                <div class="kpi-card">
                    <div class="kpi-icon"><i class="fa-solid fa-filter"></i></div>
                    <h3>Filtered</h3>
                    <p><%= filteredCount %></p>
                </div>
            </section>

            <section class="panel">
                <div class="toolbar">
                    <div>
                        <h2>QR Exception Register</h2>
                        <p class="table-subtext">Showing <%= filteredCount %> matching exception records.</p>
                    </div>

                    <form class="filter-form" method="get" action="qr_exception_report.jsp">
                        <input class="filter-input"
                               type="text"
                               name="q"
                               value="<%= q.isEmpty() ? "" : safeText(q) %>"
                               placeholder="Search asset, department, token, URL...">

                        <select class="filter-select" name="issue">
                            <option value="ALL" <%= "ALL".equals(issueFilter) ? "selected" : "" %>>All Issues</option>
                            <option value="MISSING_TOKEN" <%= "MISSING_TOKEN".equals(issueFilter) ? "selected" : "" %>>Missing Token</option>
                            <option value="URL_MISMATCH" <%= "URL_MISMATCH".equals(issueFilter) ? "selected" : "" %>>URL Mismatch</option>
                            <option value="INVALID_TOKEN" <%= "INVALID_TOKEN".equals(issueFilter) ? "selected" : "" %>>Invalid Token Scan</option>
                        </select>

                        <button class="action-btn primary" type="submit">
                            <i class="fa-solid fa-filter"></i>
                            Filter
                        </button>

                        <a class="action-btn green" href="<%= safeText(exportUrl) %>">
                            <i class="fa-solid fa-file-excel"></i>
                            Export
                        </a>

                        <a class="action-btn" href="qr_exception_report.jsp">
                            <i class="fa-solid fa-rotate-right"></i>
                            Reset
                        </a>
                    </form>
                </div>

                <% if (rows.isEmpty()) { %>
                    <div class="empty-box">
                        <i class="fa-solid fa-circle-check"></i>
                        <strong>No QR exception found</strong>
                        <span>QR token, URL and invalid scan checks are clean for the selected filter.</span>
                    </div>
                <% } else { %>
                    <div class="table-wrap">
                        <table class="exception-table">
                            <thead>
                                <tr>
                                    <th>Issue</th>
                                    <th>Severity</th>
                                    <th>Asset</th>
                                    <th>Department</th>
                                    <th>Asset Status</th>
                                    <th>Token</th>
                                    <th>Stored URL</th>
                                    <th>Expected / Action</th>
                                    <th>Details</th>
                                    <th>Time</th>
                                    <th>Open</th>
                                </tr>
                            </thead>

                            <tbody>
                                <% for (ExceptionRow row : rows) { %>
                                    <tr>
                                        <td>
                                            <span class="pill issue-<%= safeText(statusClass(row.issueType)) %>">
                                                <%= safeText(cleanLabel(row.issueType)) %>
                                            </span>
                                        </td>

                                        <td>
                                            <span class="pill severity-<%= safeText(statusClass(row.severity)) %>">
                                                <%= safeText(row.severity) %>
                                            </span>
                                        </td>

                                        <td>
                                            <div class="asset-title">
                                                <strong><%= safeText(row.assetCode) %></strong>
                                                <span><%= safeText(row.assetName) %></span>
                                            </div>
                                        </td>

                                        <td><%= safeText(row.departmentName) %></td>

                                        <td>
                                            <span class="pill">
                                                <%= safeText(cleanLabel(row.assetStatus)) %>
                                            </span>
                                        </td>

                                        <td>
                                            <span class="pill" title="<%= safeText(row.token) %>">
                                                <%= safeText(limitText(row.token, 36)) %>
                                            </span>
                                        </td>

                                        <td>
                                            <span class="pill" title="<%= safeText(row.storedUrl) %>">
                                                <%= safeText(limitText(row.storedUrl, 42)) %>
                                            </span>
                                        </td>

                                        <td>
                                            <span class="pill" title="<%= safeText(row.expectedUrl) %>">
                                                <%= safeText(limitText(row.expectedUrl, 42)) %>
                                            </span>
                                        </td>

                                        <td>
                                            <div class="asset-title">
                                                <span><%= safeText(limitText(row.details, 120)) %></span>
                                            </div>
                                        </td>

                                        <td><%= safeText(row.refTime) %></td>

                                        <td>
                                            <% if (row.assetId != null && !row.assetId.trim().isEmpty()) { %>
                                                <a class="action-btn" href="view_asset.jsp?id=<%= safeText(row.assetId) %>">
                                                    Asset
                                                </a>
                                            <% } else { %>
                                                <span class="pill">No Link</span>
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

</body>
</html>