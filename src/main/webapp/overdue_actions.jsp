<%@page contentType="text/html" pageEncoding="UTF-8"%>
<%@page import="com.mycompany.asset_management_system_ams.DBConnection"%>
<%@page import="java.sql.*"%>
<%@page import="java.util.*"%>

<%!
    public static class ActionRow {
        String type = "";
        String title = "";
        String detail = "";
        String dueDate = "";
        String url = "";
        String icon = "";
        String severity = "";
    }

    private String safeText(String value) {
        if (value == null || value.trim().isEmpty()) return "N/A";
        return value.trim().replace("&","&amp;").replace("<","&lt;").replace(">","&gt;").replace("\"","&quot;").replace("'","&#39;");
    }

    private String cleanLabel(String value) {
        if (value == null || value.trim().isEmpty()) return "N/A";
        String text = value.trim().replace("_"," ").toLowerCase(Locale.ENGLISH);
        String[] parts = text.split("\\s+");
        StringBuilder out = new StringBuilder();
        for (String part : parts) {
            if (part.length() > 0) out.append(Character.toUpperCase(part.charAt(0))).append(part.substring(1)).append(" ");
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
            e.printStackTrace();
        }
        return false;
    }

    private List<ActionRow> runRows(Connection con, String sql) {
        List<ActionRow> rows = new ArrayList<ActionRow>();

        try (Statement st = con.createStatement();
             ResultSet rs = st.executeQuery(sql)) {

            while (rs.next()) {
                ActionRow row = new ActionRow();
                row.type = rs.getString("type_text");
                row.title = rs.getString("title_text");
                row.detail = rs.getString("detail_text");
                row.dueDate = rs.getString("due_date");
                row.url = rs.getString("target_url");
                row.icon = rs.getString("icon");
                row.severity = rs.getString("severity");
                rows.add(row);
            }

        } catch (Exception e) {
            e.printStackTrace();
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

    String userInitial = username.substring(0, Math.min(2, username.length())).toUpperCase(Locale.ENGLISH);

    ArrayList<ActionRow> rows = new ArrayList<ActionRow>();

    try (Connection con = DBConnection.getConnection()) {

        if (tableExists(con, "asset_allocation")) {
            rows.addAll(runRows(con,
                    "SELECT "
                    + "'Return Overdue' AS type_text, "
                    + "CONCAT(a.asset_code, ' · ', a.asset_name) AS title_text, "
                    + "CONCAT('Holder: ', COALESCE(e.full_name, 'Employee'), ' · Expected return date crossed') AS detail_text, "
                    + "DATE_FORMAT(aa.expected_return_date, '%d %b %Y') AS due_date, "
                    + "CONCAT('view_allocation.jsp?id=', aa.allocation_id) AS target_url, "
                    + "'fa-rotate-left' AS icon, "
                    + "'danger' AS severity "
                    + "FROM asset_allocation aa "
                    + "LEFT JOIN assets a ON aa.asset_id = a.asset_id "
                    + "LEFT JOIN employees e ON aa.employee_id = e.employee_id "
                    + "WHERE aa.expected_return_date IS NOT NULL "
                    + "AND aa.expected_return_date < CURDATE() "
                    + "AND aa.allocation_status = 'ALLOCATED' "
                    + "ORDER BY aa.expected_return_date ASC LIMIT 30"
            ));
        }

        if (tableExists(con, "maintenance_logs")) {
            rows.addAll(runRows(con,
                    "SELECT "
                    + "'Maintenance Due' AS type_text, "
                    + "CONCAT(a.asset_code, ' · ', a.asset_name) AS title_text, "
                    + "CONCAT_WS(' · ', COALESCE(ml.maintenance_status, 'OPEN'), COALESCE(ml.issue_reported, 'Maintenance required')) AS detail_text, "
                    + "DATE_FORMAT(ml.next_due_date, '%d %b %Y') AS due_date, "
                    + "CONCAT('view_maintenance.jsp?id=', ml.maintenance_id) AS target_url, "
                    + "'fa-screwdriver-wrench' AS icon, "
                    + "IF(ml.next_due_date < CURDATE(), 'danger', 'warning') AS severity "
                    + "FROM maintenance_logs ml "
                    + "LEFT JOIN assets a ON ml.asset_id = a.asset_id "
                    + "WHERE ml.next_due_date IS NOT NULL "
                    + "AND ml.next_due_date <= DATE_ADD(CURDATE(), INTERVAL 7 DAY) "
                    + "AND ml.maintenance_status NOT IN ('COMPLETED','CANCELLED') "
                    + "ORDER BY ml.next_due_date ASC LIMIT 30"
            ));
        }

        if (tableExists(con, "assets")) {
            rows.addAll(runRows(con,
                    "SELECT "
                    + "'Warranty Expiring' AS type_text, "
                    + "CONCAT(a.asset_code, ' · ', a.asset_name) AS title_text, "
                    + "CONCAT('Vendor: ', COALESCE(v.vendor_name, 'No Vendor'), ' · Warranty renewal/check required') AS detail_text, "
                    + "DATE_FORMAT(a.warranty_expiry, '%d %b %Y') AS due_date, "
                    + "CONCAT('view_asset.jsp?id=', a.asset_id) AS target_url, "
                    + "'fa-calendar-days' AS icon, "
                    + "'warning' AS severity "
                    + "FROM assets a "
                    + "LEFT JOIN vendors v ON a.vendor_id = v.vendor_id "
                    + "WHERE a.warranty_expiry IS NOT NULL "
                    + "AND a.warranty_expiry BETWEEN CURDATE() AND DATE_ADD(CURDATE(), INTERVAL 30 DAY) "
                    + "AND a.asset_status <> 'DISPOSED' "
                    + "ORDER BY a.warranty_expiry ASC LIMIT 30"
            ));
        }

    } catch (Exception e) {
        e.printStackTrace();
    }
%>

<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>Overdue Actions - IR-AMS</title>

    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.0/css/all.min.css">

    <link rel="stylesheet" href="css/ir-glass.css?v=28000">
    <link rel="stylesheet" href="css/ams-pro.css?v=28000">
    <link rel="stylesheet" href="css/ir-ams-railway-ui.css?v=overdue-actions-final-1">

    <link rel="stylesheet" href="css/overdue_actions.css?v=28001">
</head>

<body class="railway-ui">
<div class="app ams-shell">

    <jsp:include page="sidebar.jsp" />

    <main class="main railway-main">
        <jsp:include page="topbar.jsp" />

        <div class="main-scroll-content action-board">

            <section class="action-hero">
                <div>
                    <h1>Overdue Actions</h1>
                    <p>Operational action list for overdue returns, due maintenance and warranty follow-up.</p>
                </div>

                <div class="action-count">
                    <strong><%= rows.size() %></strong>
                    <span>Action Items</span>
                </div>
            </section>

            <section class="action-panel">
                <h2>Pending Action Register</h2>

                <% if (rows.isEmpty()) { %>
                    <div class="empty-box">
                        <i class="fa-solid fa-circle-check"></i>
                        <strong>No overdue action found</strong>
                        <span>Return, maintenance and warranty action list is clear.</span>
                    </div>
                <% } else { %>
                    <div class="action-list">
                        <% for (ActionRow row : rows) { %>
                            <a class="action-row <%= safeText(row.severity) %>" href="<%= safeText(row.url) %>">
                                <div class="action-icon"><i class="fa-solid <%= safeText(row.icon) %>"></i></div>
                                <div class="action-main">
                                    <strong><%= safeText(row.type) %> · <%= safeText(row.title) %></strong>
                                    <span><%= safeText(row.detail) %></span>
                                </div>
                                <div class="action-date"><%= safeText(row.dueDate) %></div>
                            </a>
                        <% } %>
                    </div>
                <% } %>
            </section>

        </div>
    </main>
</div>

<script src="js/user-dropdown.js?v=5"></script>
<script src="js/sidebar-role.js?v=7000"></script>
<script src="js/topbar-search.js?v=global-search-ready-1"></script>
<script src="js/dashboard-actions.js?v=2"></script>
</body>
</html>