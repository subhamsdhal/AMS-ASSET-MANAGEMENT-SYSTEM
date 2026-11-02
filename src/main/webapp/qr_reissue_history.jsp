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
        String historyId = "";
        String assetId = "";
        String assetCode = "";
        String assetName = "";
        String oldToken = "";
        String newToken = "";
        String oldUrl = "";
        String newUrl = "";
        String reason = "";
        String reissuedBy = "";
        String role = "";
        String createdAt = "";
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
    String userRole = (String) session.getAttribute("role");

    response.setHeader("Cache-Control", "no-cache, no-store, must-revalidate");
    response.setHeader("Pragma", "no-cache");
    response.setDateHeader("Expires", 0);

    if (username == null || userRole == null) {
        response.sendRedirect("login.jsp");
        return;
    }

    boolean canView = ("SUPER_ADMIN".equals(userRole) || "ADMIN".equals(userRole))
            || "ASSET_MANAGER".equals(userRole)
            || "AUDITOR".equals(userRole);

    if (!canView) {
        response.sendRedirect("dashboard.jsp?access=denied");
        return;
    }

    String q = request.getParameter("q");

    if (q == null) {
        q = "";
    }

    q = q.trim();

    String exportUrl = "export_qr_reissue_history_excel.jsp";

    if (!q.isEmpty()) {
        exportUrl += "?q=" + URLEncoder.encode(q, "UTF-8");
    }

    String userInitial = username.substring(0, Math.min(2, username.length())).toUpperCase(Locale.ENGLISH);

    boolean historyTableExists = false;
    int totalHistory = 0;
    int filteredCount = 0;

    List<HistoryRow> rows = new ArrayList<HistoryRow>();

    try (Connection con = DBConnection.getConnection()) {
        historyTableExists = tableExists(con, "asset_qr_token_history");

        if (historyTableExists) {
            StringBuilder where = new StringBuilder(" WHERE 1 = 1 ");
            List<String> params = new ArrayList<String>();

            if (!q.isEmpty()) {
                where.append("AND (")
                        .append("asset_code LIKE ? ")
                        .append("OR asset_name LIKE ? ")
                        .append("OR old_qr_public_token LIKE ? ")
                        .append("OR new_qr_public_token LIKE ? ")
                        .append("OR reissue_reason LIKE ? ")
                        .append("OR reissued_by_username LIKE ? ")
                        .append(") ");

                String searchValue = "%" + q + "%";

                for (int i = 0; i < 6; i++) {
                    params.add(searchValue);
                }
            }

            totalHistory = countRows(con,
                    "SELECT COUNT(*) FROM asset_qr_token_history",
                    new ArrayList<String>());

            filteredCount = countRows(con,
                    "SELECT COUNT(*) FROM asset_qr_token_history " + where.toString(),
                    params);

            String sql =
                    "SELECT "
                    + "history_id, asset_id, asset_code, asset_name, "
                    + "old_qr_public_token, new_qr_public_token, old_qr_code, new_qr_code, "
                    + "reissue_reason, reissued_by_username, reissued_by_role, "
                    + "DATE_FORMAT(created_at, '%d %b %Y, %h:%i %p') AS created_at "
                    + "FROM asset_qr_token_history "
                    + where.toString()
                    + "ORDER BY history_id DESC LIMIT 400";

            try (PreparedStatement ps = con.prepareStatement(sql)) {
                for (int i = 0; i < params.size(); i++) {
                    ps.setString(i + 1, params.get(i));
                }

                try (ResultSet rs = ps.executeQuery()) {
                    while (rs.next()) {
                        HistoryRow row = new HistoryRow();

                        row.historyId = rs.getString("history_id");
                        row.assetId = rs.getString("asset_id");
                        row.assetCode = rs.getString("asset_code");
                        row.assetName = rs.getString("asset_name");
                        row.oldToken = rs.getString("old_qr_public_token");
                        row.newToken = rs.getString("new_qr_public_token");
                        row.oldUrl = rs.getString("old_qr_code");
                        row.newUrl = rs.getString("new_qr_code");
                        row.reason = rs.getString("reissue_reason");
                        row.reissuedBy = rs.getString("reissued_by_username");
                        row.role = rs.getString("reissued_by_role");
                        row.createdAt = rs.getString("created_at");

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
    <title>QR Reissue History - IR-AMS</title>

    <link rel="stylesheet"
          href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.0/css/all.min.css">

    <link rel="stylesheet" href="css/ir-glass.css?v=28000">
    <link rel="stylesheet" href="css/ams-pro.css?v=28000">
    <link rel="stylesheet" href="css/ir-ams-railway-ui.css?v=28000">
<link rel="stylesheet" href="css/qr_reissue_history.css?v=topbarfix1">
</head>

<body class="railway-ui">
<div class="app ams-shell">

        <jsp:include page="sidebar.jsp" />

    <main class="main railway-main">
                <jsp:include page="topbar.jsp" />

        <div class="main-scroll-content history-board">

            <section class="history-hero">
                <div>
                    <h1>QR Reissue History</h1>
                    <p>
                        Official audit trail of old token, new token, reissue reason, user and time.
                        Use this for accountability when QR labels are replaced.
                    </p>
                </div>

                <div class="hero-actions">
                    <a href="<%= safeText(exportUrl) %>" class="action-btn green">
                        <i class="fa-solid fa-file-excel"></i>
                        Export Excel
                    </a>

                    <a href="qr_token_reissue.jsp" class="action-btn primary">
                        <i class="fa-solid fa-rotate"></i>
                        Reissue Token
                    </a>

                    <a href="qr_control_center.jsp" class="action-btn">
                        <i class="fa-solid fa-arrow-left"></i>
                        Control Center
                    </a>
                </div>
            </section>

            <section class="kpi-grid">
                <div class="kpi-card">
                    <h3>Total Reissue Records</h3>
                    <p title="<%= totalHistory %>"><%= formatNumber(totalHistory) %></p>
                    <span>Complete QR replacement trail</span>
                </div>

                <div class="kpi-card">
                    <h3>Filtered Records</h3>
                    <p title="<%= filteredCount %>"><%= formatNumber(filteredCount) %></p>
                    <span>Visible result count</span>
                </div>

                <div class="kpi-card">
                    <h3>History Table</h3>
                    <p><%= historyTableExists ? "OK" : "N/A" %></p>
                    <span>Created automatically after first reissue</span>
                </div>
            </section>

            <section class="panel">
                <div class="toolbar">
                    <div>
                        <h2>QR Token Replacement Register</h2>
                        <p class="table-subtext">Showing <%= rows.size() %> latest matching records. Maximum 400 records shown.</p>
                    </div>

                    <form class="filter-form" method="get" action="qr_reissue_history.jsp">
                        <input class="filter-input"
                               type="text"
                               name="q"
                               value="<%= q.isEmpty() ? "" : safeText(q) %>"
                               placeholder="Search asset, old token, new token, reason, user...">

                        <button class="action-btn primary" type="submit">
                            <i class="fa-solid fa-filter"></i>
                            Search
                        </button>

                        <a class="action-btn green" href="<%= safeText(exportUrl) %>">
                            <i class="fa-solid fa-file-excel"></i>
                            Export
                        </a>

                        <a class="action-btn" href="qr_reissue_history.jsp">
                            <i class="fa-solid fa-rotate-right"></i>
                            Reset
                        </a>
                    </form>
                </div>

                <% if (!historyTableExists) { %>
                    <span class="pill old">
                        No reissue history table yet. It will be created automatically after first QR token reissue.
                    </span>
                <% } else { %>
                    <div class="table-wrap">
                        <table class="history-table">
                            <thead>
                                <tr>
                                    <th>History ID</th>
                                    <th>Asset</th>
                                    <th>Old Token</th>
                                    <th>New Token</th>
                                    <th>Old URL</th>
                                    <th>New URL</th>
                                    <th>Reason</th>
                                    <th>Reissued By</th>
                                    <th>Time</th>
                                    <th>Open</th>
                                </tr>
                            </thead>

                            <tbody>
                                <% for (HistoryRow row : rows) { %>
                                    <tr>
                                        <td><strong>#<%= safeText(row.historyId) %></strong></td>

                                        <td>
                                            <div class="asset-title">
                                                <strong><%= safeText(row.assetCode) %></strong>
                                                <span><%= safeText(row.assetName) %></span>
                                            </div>
                                        </td>

                                        <td>
                                            <span class="pill old" title="<%= safeText(row.oldToken) %>">
                                                <%= safeText(limitText(row.oldToken, 36)) %>
                                            </span>
                                        </td>

                                        <td>
                                            <span class="pill new" title="<%= safeText(row.newToken) %>">
                                                <%= safeText(limitText(row.newToken, 36)) %>
                                            </span>
                                        </td>

                                        <td>
                                            <span class="pill old" title="<%= safeText(row.oldUrl) %>">
                                                <%= safeText(limitText(row.oldUrl, 42)) %>
                                            </span>
                                        </td>

                                        <td>
                                            <span class="pill new" title="<%= safeText(row.newUrl) %>">
                                                <%= safeText(limitText(row.newUrl, 42)) %>
                                            </span>
                                        </td>

                                        <td>
                                            <span class="pill" title="<%= safeText(row.reason) %>">
                                                <%= safeText(limitText(row.reason, 44)) %>
                                            </span>
                                        </td>

                                        <td>
                                            <div class="asset-title">
                                                <strong><%= safeText(row.reissuedBy) %></strong>
                                                <span><%= safeText(cleanLabel(row.role)) %></span>
                                            </div>
                                        </td>

                                        <td><%= safeText(row.createdAt) %></td>

                                        <td>
                                            <% if (row.assetId != null && !row.assetId.trim().isEmpty()) { %>
                                                <a class="action-btn primary" href="view_asset.jsp?id=<%= safeText(row.assetId) %>">
                                                    Asset
                                                </a>
                                            <% } else { %>
                                                <span class="pill">No Link</span>
                                            <% } %>
                                        </td>
                                    </tr>
                                <% } %>

                                <% if (rows.isEmpty()) { %>
                                    <tr>
                                        <td colspan="10">
                                            <span class="pill">No QR token reissue record found.</span>
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