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

    public static class MissingQrRow {
        String assetId = "";
        String assetCode = "";
        String assetName = "";
        String categoryName = "";
        String departmentName = "";
        String vendorName = "";
        String locationName = "";
        String assetStatus = "";
        String conditionStatus = "";
        String createdAt = "";
        String updatedAt = "";
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

    String exportUrl = "export_qr_missing_qr_excel.jsp?status=" + URLEncoder.encode(statusFilter, "UTF-8");

    if (!q.isEmpty()) {
        exportUrl += "&q=" + URLEncoder.encode(q, "UTF-8");
    }

    String userInitial = username.substring(0, Math.min(2, username.length())).toUpperCase(Locale.ENGLISH);

    int totalAssets = 0;
    int missingQr = 0;
    int filteredCount = 0;

    List<MissingQrRow> rows = new ArrayList<MissingQrRow>();

    try (Connection con = DBConnection.getConnection()) {
        totalAssets = countRows(con, "SELECT COUNT(*) FROM assets");

        missingQr = countRows(con,
                "SELECT COUNT(*) FROM assets "
                + "WHERE qr_public_token IS NULL OR TRIM(qr_public_token) = ''");

        StringBuilder sql = new StringBuilder();

        sql.append("SELECT ")
                .append("a.asset_id, a.asset_code, a.asset_name, a.asset_status, a.condition_status, ")
                .append("DATE_FORMAT(a.created_at, '%d %b %Y, %h:%i %p') AS created_at, ")
                .append("DATE_FORMAT(a.updated_at, '%d %b %Y, %h:%i %p') AS updated_at, ")
                .append("COALESCE(ac.category_name, 'Uncategorized') AS category_name, ")
                .append("COALESCE(d.department_name, 'Unassigned') AS department_name, ")
                .append("COALESCE(v.vendor_name, 'No Vendor') AS vendor_name, ")
                .append("COALESCE(rl.location_name, a.location, 'Not Mentioned') AS location_name ")
                .append("FROM assets a ")
                .append("LEFT JOIN asset_categories ac ON a.category_id = ac.category_id ")
                .append("LEFT JOIN departments d ON a.department_id = d.department_id ")
                .append("LEFT JOIN vendors v ON a.vendor_id = v.vendor_id ")
                .append("LEFT JOIN railway_locations rl ON a.location_id = rl.location_id ")
                .append("WHERE a.qr_public_token IS NULL OR TRIM(a.qr_public_token) = '' ");

        List<String> params = new ArrayList<String>();

        if (!"ALL".equals(statusFilter)) {
            sql.append("AND a.asset_status = ? ");
            params.add(statusFilter);
        }

        if (!q.isEmpty()) {
            sql.append("AND (")
                    .append("a.asset_code LIKE ? ")
                    .append("OR a.asset_name LIKE ? ")
                    .append("OR ac.category_name LIKE ? ")
                    .append("OR d.department_name LIKE ? ")
                    .append("OR v.vendor_name LIKE ? ")
                    .append("OR rl.location_name LIKE ? ")
                    .append(") ");

            String searchValue = "%" + q + "%";

            for (int i = 0; i < 6; i++) {
                params.add(searchValue);
            }
        }

        sql.append("ORDER BY a.asset_id DESC LIMIT 500");

        try (PreparedStatement ps = con.prepareStatement(sql.toString())) {
            for (int i = 0; i < params.size(); i++) {
                ps.setString(i + 1, params.get(i));
            }

            try (ResultSet rs = ps.executeQuery()) {
                while (rs.next()) {
                    MissingQrRow row = new MissingQrRow();

                    row.assetId = rs.getString("asset_id");
                    row.assetCode = rs.getString("asset_code");
                    row.assetName = rs.getString("asset_name");
                    row.categoryName = rs.getString("category_name");
                    row.departmentName = rs.getString("department_name");
                    row.vendorName = rs.getString("vendor_name");
                    row.locationName = rs.getString("location_name");
                    row.assetStatus = rs.getString("asset_status");
                    row.conditionStatus = rs.getString("condition_status");
                    row.createdAt = rs.getString("created_at");
                    row.updatedAt = rs.getString("updated_at");

                    rows.add(row);
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
    <title>Missing QR Report - IR-AMS</title>

    <link rel="stylesheet"
          href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.0/css/all.min.css">

    <link rel="stylesheet" href="css/ir-glass.css?v=28000">
    <link rel="stylesheet" href="css/ams-pro.css?v=28000">
    <link rel="stylesheet" href="css/ir-ams-railway-ui.css?v=28000">
<link rel="stylesheet" href="css/qr_missing_qr_report.css?v=topbarfix1">
</head>

<body class="railway-ui">
<div class="app ams-shell">

        <jsp:include page="sidebar.jsp" />

    <main class="main railway-main">
                <jsp:include page="topbar.jsp" />

        <div class="main-scroll-content missing-board">

            <section class="missing-hero">
                <div>
                    <h1>Missing QR Report</h1>
                    <p>
                        List of assets where dynamic QR token is still missing. Use this page before QR label printing
                        and physical tagging work.
                    </p>
                </div>

                <div class="hero-actions">
                    <a href="<%= safeText(exportUrl) %>" class="action-btn green">
                        <i class="fa-solid fa-file-excel"></i>
                        Export Excel
                    </a>

                    <a href="qr_bulk_generate.jsp" class="action-btn primary">
                        <i class="fa-solid fa-wand-magic-sparkles"></i>
                        Generate QR
                    </a>

                    <a href="qr_coverage_report.jsp" class="action-btn">
                        <i class="fa-solid fa-chart-pie"></i>
                        Coverage
                    </a>

                    <a href="qr_control_center.jsp" class="action-btn">
                        <i class="fa-solid fa-arrow-left"></i>
                        Control Center
                    </a>
                </div>
            </section>

            <section class="kpi-grid">
                <div class="kpi-card">
                    <h3>Total Assets</h3>
                    <p title="<%= totalAssets %>"><%= formatNumber(totalAssets) %></p>
                    <span>Complete asset register</span>
                </div>

                <div class="kpi-card">
                    <h3>Missing QR</h3>
                    <p title="<%= missingQr %>"><%= formatNumber(missingQr) %></p>
                    <span>Assets requiring QR generation</span>
                </div>

                <div class="kpi-card">
                    <h3>Filtered</h3>
                    <p title="<%= filteredCount %>"><%= formatNumber(filteredCount) %></p>
                    <span>Current report rows</span>
                </div>
            </section>

            <section class="panel">
                <div class="toolbar">
                    <div>
                        <h2>Assets Without QR Token</h2>
                        <p class="table-subtext">Showing <%= filteredCount %> matching assets. Maximum 500 records shown.</p>
                    </div>

                    <form class="filter-form" method="get" action="qr_missing_qr_report.jsp">
                        <input class="filter-input"
                               type="text"
                               name="q"
                               value="<%= q.isEmpty() ? "" : safeText(q) %>"
                               placeholder="Search asset, category, department, vendor, location...">

                        <select class="filter-select" name="status">
                            <option value="ALL" <%= "ALL".equals(statusFilter) ? "selected" : "" %>>All Status</option>
                            <option value="AVAILABLE" <%= "AVAILABLE".equals(statusFilter) ? "selected" : "" %>>Available</option>
                            <option value="ALLOCATED" <%= "ALLOCATED".equals(statusFilter) ? "selected" : "" %>>Allocated</option>
                            <option value="UNDER_MAINTENANCE" <%= "UNDER_MAINTENANCE".equals(statusFilter) ? "selected" : "" %>>Under Maintenance</option>
                            <option value="DISPOSED" <%= "DISPOSED".equals(statusFilter) ? "selected" : "" %>>Disposed</option>
                        </select>

                        <button class="action-btn primary" type="submit">
                            <i class="fa-solid fa-filter"></i>
                            Filter
                        </button>

                        <a class="action-btn green" href="<%= safeText(exportUrl) %>">
                            <i class="fa-solid fa-file-excel"></i>
                            Export
                        </a>

                        <a class="action-btn" href="qr_missing_qr_report.jsp">
                            <i class="fa-solid fa-rotate-right"></i>
                            Reset
                        </a>
                    </form>
                </div>

                <div class="table-wrap">
                    <table class="missing-table">
                        <thead>
                            <tr>
                                <th>Asset</th>
                                <th>Category</th>
                                <th>Department</th>
                                <th>Vendor</th>
                                <th>Location</th>
                                <th>Status</th>
                                <th>Condition</th>
                                <th>Created</th>
                                <th>Updated</th>
                                <th>Action</th>
                            </tr>
                        </thead>

                        <tbody>
                            <% for (MissingQrRow row : rows) { %>
                                <tr>
                                    <td>
                                        <div class="asset-title">
                                            <strong><%= safeText(row.assetCode) %></strong>
                                            <span><%= safeText(row.assetName) %></span>
                                        </div>
                                    </td>

                                    <td><%= safeText(row.categoryName) %></td>
                                    <td><%= safeText(row.departmentName) %></td>
                                    <td><%= safeText(row.vendorName) %></td>
                                    <td><%= safeText(row.locationName) %></td>

                                    <td>
                                        <span class="pill status-<%= safeText(statusClass(row.assetStatus)) %>">
                                            <%= safeText(cleanLabel(row.assetStatus)) %>
                                        </span>
                                    </td>

                                    <td>
                                        <span class="pill">
                                            <%= safeText(cleanLabel(row.conditionStatus)) %>
                                        </span>
                                    </td>

                                    <td><%= safeText(row.createdAt) %></td>
                                    <td><%= safeText(row.updatedAt) %></td>

                                    <td>
                                        <div class="hero-actions" style="justify-content:flex-start;">
                                            <a class="action-btn" href="view_asset.jsp?id=<%= safeText(row.assetId) %>">
                                                Asset
                                            </a>

                                            <a class="action-btn primary" href="qr_bulk_generate.jsp?q=<%= safeText(row.assetCode) %>">
                                                Generate
                                            </a>
                                        </div>
                                    </td>
                                </tr>
                            <% } %>

                            <% if (rows.isEmpty()) { %>
                                <tr>
                                    <td colspan="10">
                                        <span class="pill">No missing QR asset found for selected filter.</span>
                                    </td>
                                </tr>
                            <% } %>
                        </tbody>
                    </table>
                </div>
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