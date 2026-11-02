<%@page contentType="text/html" pageEncoding="UTF-8"%>
<%@page import="com.mycompany.asset_management_system_ams.DBConnection"%>
<%@page import="java.sql.*"%>
<%@page import="java.util.*"%>

<%!
    public String formatNumber(int number) {
        if (number >= 100000) {
            return String.format("%.1fL", number / 100000.0);
        } else if (number >= 1000) {
            return String.format("%.1fK", number / 1000.0);
        }
        return String.valueOf(number);
    }

    public static class AssetTokenRow {
        String assetId = "";
        String assetCode = "";
        String assetName = "";
        String categoryName = "";
        String departmentName = "";
        String locationName = "";
        String assetStatus = "";
        String currentToken = "";
        String currentUrl = "";
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

    boolean canReissue = ("SUPER_ADMIN".equals(role) || "ADMIN".equals(role))
            || "ASSET_MANAGER".equals(role);

    if (!canReissue) {
        response.sendRedirect("dashboard.jsp?access=denied");
        return;
    }

    String q = request.getParameter("q");
    String msg = request.getParameter("msg");
    String error = request.getParameter("error");

    if (q == null) {
        q = "";
    }

    q = q.trim();

    String userInitial = username.substring(0, Math.min(2, username.length())).toUpperCase(Locale.ENGLISH);

    int totalAssets = 0;
    int qrGenerated = 0;
    int qrMissing = 0;
    int filteredCount = 0;

    List<AssetTokenRow> rows = new ArrayList<AssetTokenRow>();

    try (Connection con = DBConnection.getConnection()) {
        totalAssets = countRows(con, "SELECT COUNT(*) FROM assets");

        qrGenerated = countRows(con,
                "SELECT COUNT(*) FROM assets "
                + "WHERE qr_public_token IS NOT NULL AND TRIM(qr_public_token) <> ''");

        qrMissing = totalAssets - qrGenerated;

        StringBuilder sql = new StringBuilder();

        sql.append("SELECT ")
                .append("a.asset_id, a.asset_code, a.asset_name, a.asset_status, ")
                .append("a.qr_public_token, a.qr_code, ")
                .append("DATE_FORMAT(a.updated_at, '%d %b %Y, %h:%i %p') AS updated_at, ")
                .append("COALESCE(ac.category_name, 'Uncategorized') AS category_name, ")
                .append("COALESCE(d.department_name, 'Unassigned') AS department_name, ")
                .append("COALESCE(rl.location_name, a.location, 'Not Mentioned') AS location_name ")
                .append("FROM assets a ")
                .append("LEFT JOIN asset_categories ac ON a.category_id = ac.category_id ")
                .append("LEFT JOIN departments d ON a.department_id = d.department_id ")
                .append("LEFT JOIN railway_locations rl ON a.location_id = rl.location_id ")
                .append("WHERE a.qr_public_token IS NOT NULL AND TRIM(a.qr_public_token) <> '' ");

        List<String> params = new ArrayList<String>();

        if (!q.isEmpty()) {
            sql.append("AND (")
                    .append("a.asset_code LIKE ? ")
                    .append("OR a.asset_name LIKE ? ")
                    .append("OR a.qr_public_token LIKE ? ")
                    .append("OR a.qr_code LIKE ? ")
                    .append("OR ac.category_name LIKE ? ")
                    .append("OR d.department_name LIKE ? ")
                    .append("OR rl.location_name LIKE ? ")
                    .append(") ");

            String searchValue = "%" + q + "%";

            for (int i = 0; i < 7; i++) {
                params.add(searchValue);
            }
        }

        sql.append("ORDER BY a.asset_id DESC LIMIT 300");

        try (PreparedStatement ps = con.prepareStatement(sql.toString())) {
            for (int i = 0; i < params.size(); i++) {
                ps.setString(i + 1, params.get(i));
            }

            try (ResultSet rs = ps.executeQuery()) {
                while (rs.next()) {
                    AssetTokenRow row = new AssetTokenRow();

                    row.assetId = rs.getString("asset_id");
                    row.assetCode = rs.getString("asset_code");
                    row.assetName = rs.getString("asset_name");
                    row.categoryName = rs.getString("category_name");
                    row.departmentName = rs.getString("department_name");
                    row.locationName = rs.getString("location_name");
                    row.assetStatus = rs.getString("asset_status");
                    row.currentToken = rs.getString("qr_public_token");
                    row.currentUrl = rs.getString("qr_code");
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
    <title>QR Token Reissue - IR-AMS</title>

    <link rel="stylesheet"
          href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.0/css/all.min.css">

    <link rel="stylesheet" href="css/ir-glass.css?v=28000">
    <link rel="stylesheet" href="css/ams-pro.css?v=28000">
    <link rel="stylesheet" href="css/ir-ams-railway-ui.css?v=28000">
<link rel="stylesheet" href="css/qr_token_reissue.css?v=topbarfix1">
</head>

<body class="railway-ui">
<div class="app ams-shell">

        <jsp:include page="sidebar.jsp" />

    <main class="main railway-main">
                <jsp:include page="topbar.jsp" />

        <div class="main-scroll-content reissue-board">

            <section class="reissue-hero">
                <div>
                    <h1>QR Token Reissue</h1>
                    <p>
                        Reissue a fresh QR token for an asset when the printed QR is damaged, leaked, wrongly printed,
                        or officially replaced. Old token will be saved in reissue history.
                    </p>
                </div>

                <div class="hero-actions">
                    <a href="qr_reissue_history.jsp" class="action-btn green">
                        <i class="fa-solid fa-clock-rotate-left"></i>
                        Reissue History
                    </a>

                    <a href="qr_token_lookup.jsp" class="action-btn">
                        <i class="fa-solid fa-magnifying-glass"></i>
                        Token Lookup
                    </a>

                    <a href="qr_control_center.jsp" class="action-btn primary">
                        <i class="fa-solid fa-arrow-left"></i>
                        Control Center
                    </a>
                </div>
            </section>

            <% if ("reissued".equals(msg)) { %>
                <div class="message-success">
                    <i class="fa-solid fa-circle-check"></i>
                    QR token reissued successfully. Print the new QR label again.
                </div>
            <% } %>

            <% if ("missing_reason".equals(error)) { %>
                <div class="message-error">
                    <i class="fa-solid fa-triangle-exclamation"></i>
                    Reissue reason is required for official audit trail.
                </div>
            <% } %>

            <% if ("failed".equals(error)) { %>
                <div class="message-error">
                    <i class="fa-solid fa-triangle-exclamation"></i>
                    QR token reissue failed. Please check server console.
                </div>
            <% } %>

            <% if ("public_base_url".equals(error)) { %>
                <div class="message-error">
                    <i class="fa-solid fa-triangle-exclamation"></i>
                    Set a non-localhost public QR base URL in Settings or QR Control Center before reissuing QR tokens.
                </div>
            <% } %>

            <section class="kpi-grid">
                <div class="kpi-card">
                    <h3>Total Assets</h3>
                    <p title="<%= totalAssets %>"><%= formatNumber(totalAssets) %></p>
                    <span>Complete asset register</span>
                </div>

                <div class="kpi-card">
                    <h3>QR Generated</h3>
                    <p title="<%= qrGenerated %>"><%= formatNumber(qrGenerated) %></p>
                    <span>Assets eligible for reissue</span>
                </div>

                <div class="kpi-card">
                    <h3>QR Missing</h3>
                    <p title="<%= qrMissing %>"><%= formatNumber(qrMissing) %></p>
                    <span>Generate QR first</span>
                </div>

                <div class="kpi-card">
                    <h3>Filtered</h3>
                    <p title="<%= filteredCount %>"><%= formatNumber(filteredCount) %></p>
                    <span>Current visible rows</span>
                </div>
            </section>

            <section class="panel">
                <div class="toolbar">
                    <div>
                        <h2>Assets With Active QR Token</h2>
                        <p class="table-subtext">
                            Search asset and reissue token only when replacement is officially required.
                        </p>
                    </div>

                    <form class="filter-form" method="get" action="qr_token_reissue.jsp">
                        <input class="filter-input"
                               type="text"
                               name="q"
                               value="<%= q.isEmpty() ? "" : safeText(q) %>"
                               placeholder="Search asset, token, department, location...">

                        <button class="action-btn primary" type="submit">
                            <i class="fa-solid fa-filter"></i>
                            Search
                        </button>

                        <a class="action-btn" href="qr_token_reissue.jsp">
                            <i class="fa-solid fa-rotate-right"></i>
                            Reset
                        </a>
                    </form>
                </div>

                <div class="table-wrap">
                    <table class="reissue-table">
                        <thead>
                            <tr>
                                <th>Asset</th>
                                <th>Department / Category</th>
                                <th>Location</th>
                                <th>Status</th>
                                <th>Current Token</th>
                                <th>Current Public URL</th>
                                <th>Updated</th>
                                <th>Reissue Reason</th>
                                <th>Action</th>
                            </tr>
                        </thead>

                        <tbody>
                            <% for (AssetTokenRow row : rows) { %>
                                <tr>
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

                                    <td><%= safeText(row.locationName) %></td>

                                    <td>
                                        <span class="pill status-<%= safeText(statusClass(row.assetStatus)) %>">
                                            <%= safeText(cleanLabel(row.assetStatus)) %>
                                        </span>
                                    </td>

                                    <td>
                                        <span class="pill" title="<%= safeText(row.currentToken) %>">
                                            <%= safeText(row.currentToken) %>
                                        </span>
                                    </td>

                                    <td>
                                        <span class="pill" title="<%= safeText(row.currentUrl) %>">
                                            <%= safeText(row.currentUrl) %>
                                        </span>
                                    </td>

                                    <td><%= safeText(row.updatedAt) %></td>

                                    <td>
                                        <form method="post"
                                              action="ReissueAssetQrTokenServlet"
                                              id="reissueForm<%= safeText(row.assetId) %>"
                                              style="margin:0;">
                                            <input type="hidden" name="asset_id" value="<%= safeText(row.assetId) %>">

                                            <input class="filter-input"
                                                   style="width:260px !important;"
                                                   type="text"
                                                   name="reason"
                                                   placeholder="Reason: damaged / leaked / reprint..."
                                                   required>
                                        </form>
                                    </td>

                                    <td>
                                        <div class="hero-actions" style="justify-content:flex-start;">
                                            <a class="action-btn" href="view_asset.jsp?id=<%= safeText(row.assetId) %>">
                                                Asset
                                            </a>

                                            <button class="action-btn danger"
                                                    type="submit"
                                                    form="reissueForm<%= safeText(row.assetId) %>"
                                                    onclick="return confirm('Reissue QR token for <%= safeText(row.assetCode) %>? Old printed QR may stop matching the new token.');">
                                                <i class="fa-solid fa-rotate"></i>
                                                Reissue
                                            </button>
                                        </div>
                                    </td>
                                </tr>
                            <% } %>

                            <% if (rows.isEmpty()) { %>
                                <tr>
                                    <td colspan="9">
                                        <span class="pill">No QR-enabled asset found for selected search.</span>
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
