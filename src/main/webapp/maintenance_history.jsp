<%@page contentType="text/html" pageEncoding="UTF-8"%>
<%@page import="com.mycompany.asset_management_system_ams.DBConnection"%>
<%@page import="java.sql.*"%>
<%@page import="java.util.*"%>

<%!
    private String safe(Object value) {
        if (value == null) {
            return "";
        }

        return value.toString()
                .replace("&", "&amp;")
                .replace("<", "&lt;")
                .replace(">", "&gt;")
                .replace("\"", "&quot;")
                .replace("'", "&#39;");
    }

    private String display(Object value) {
        if (value == null || value.toString().trim().isEmpty()) {
            return "N/A";
        }

        return safe(value);
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

    private boolean columnExists(Connection con, String tableName, String columnName) {
        String sql = "SELECT COUNT(*) FROM information_schema.columns "
                + "WHERE table_schema = DATABASE() AND table_name = ? AND column_name = ?";

        try (PreparedStatement ps = con.prepareStatement(sql)) {
            ps.setString(1, tableName);
            ps.setString(2, columnName);

            try (ResultSet rs = ps.executeQuery()) {
                return rs.next() && rs.getInt(1) > 0;
            }

        } catch (Exception e) {
            e.printStackTrace();
        }

        return false;
    }

    private String rowValue(Map<String, String> row, String key) {
        if (row == null) {
            return "";
        }

        String value = row.get(key);
        return value == null ? "" : value;
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

    String maintenanceId = request.getParameter("id");

    if (maintenanceId == null || maintenanceId.trim().isEmpty()) {
        response.sendRedirect("maintenance.jsp?error=invalid");
        return;
    }

    maintenanceId = maintenanceId.trim();

    String userInitial = username.substring(0, Math.min(2, username.length())).toUpperCase(Locale.ENGLISH);

    Map<String, String> selectedMaintenance = new HashMap<String, String>();
    List<Map<String, String>> historyList = new ArrayList<Map<String, String>>();

    try (Connection con = DBConnection.getConnection()) {

        boolean hasDescription = columnExists(con, "maintenance_logs", "description");
        boolean hasPerformedBy = columnExists(con, "maintenance_logs", "performed_by");
        boolean hasStatus = columnExists(con, "maintenance_logs", "maintenance_status");

        String selectedSql = "SELECT ml.maintenance_id, ml.asset_id, "
                + "a.asset_code, a.asset_name, a.asset_status, "
                + "COALESCE(c.category_name, 'Uncategorized') AS category_name "
                + "FROM maintenance_logs ml "
                + "LEFT JOIN assets a ON ml.asset_id = a.asset_id "
                + "LEFT JOIN asset_categories c ON a.category_id = c.category_id "
                + "WHERE ml.maintenance_id = ? "
                + "LIMIT 1";

        try (PreparedStatement ps = con.prepareStatement(selectedSql)) {
            ps.setString(1, maintenanceId);

            try (ResultSet rs = ps.executeQuery()) {
                ResultSetMetaData meta = rs.getMetaData();
                int count = meta.getColumnCount();

                if (rs.next()) {
                    for (int i = 1; i <= count; i++) {
                        selectedMaintenance.put(meta.getColumnLabel(i), rs.getString(i));
                    }
                }
            }
        }

        if (selectedMaintenance.isEmpty()) {
            response.sendRedirect("maintenance.jsp?error=notfound");
            return;
        }

        String historySql = "SELECT ml.maintenance_id, "
                + "DATE_FORMAT(ml.maintenance_date, '%d %b %Y') AS maintenance_date, "
                + "ml.maintenance_type, "
                + (hasStatus ? "COALESCE(ml.maintenance_status, '')" : "''") + " AS maintenance_status, "
                + (hasDescription ? "COALESCE(ml.description, '')" : "''") + " AS description, "
                + "COALESCE(ml.cost, 0) AS cost, "
                + (hasPerformedBy ? "COALESCE(ml.performed_by, '')" : "''") + " AS performed_by "
                + "FROM maintenance_logs ml "
                + "WHERE ml.asset_id = ? "
                + "ORDER BY ml.maintenance_date DESC, ml.maintenance_id DESC";

        try (PreparedStatement ps = con.prepareStatement(historySql)) {
            ps.setString(1, rowValue(selectedMaintenance, "asset_id"));

            try (ResultSet rs = ps.executeQuery()) {
                ResultSetMetaData meta = rs.getMetaData();
                int count = meta.getColumnCount();

                while (rs.next()) {
                    Map<String, String> row = new HashMap<String, String>();

                    for (int i = 1; i <= count; i++) {
                        row.put(meta.getColumnLabel(i), rs.getString(i));
                    }

                    historyList.add(row);
                }
            }
        }

    } catch (Exception e) {
        e.printStackTrace();
        response.sendRedirect("maintenance.jsp?error=server");
        return;
    }
%>

<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>Maintenance History - IR-AMS</title>

    <link rel="stylesheet"
          href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.0/css/all.min.css">

    <link rel="stylesheet" href="css/ir-glass.css?v=28000">
    <link rel="stylesheet" href="css/ams-pro.css?v=28000">
    <link rel="stylesheet" href="css/ir-ams-railway-ui.css?v=28000">

    <link rel="stylesheet" href="css/maintenance_history.css?v=28000">
</head>

<body class="railway-ui">
<div class="app ams-shell">

    <jsp:include page="sidebar.jsp" />

    <main class="main railway-main">
        <jsp:include page="topbar.jsp" />

        <div class="main-scroll-content history-board">

            <section class="history-hero">
                <div>
                    <h1>Maintenance History</h1>
                    <p>
                        <strong><%= display(rowValue(selectedMaintenance, "asset_code")) %></strong>
                        · <%= display(rowValue(selectedMaintenance, "asset_name")) %>
                        · <%= display(rowValue(selectedMaintenance, "category_name")) %>
                    </p>
                </div>

                <div>
                    <a href="view_maintenance.jsp?id=<%= safe(maintenanceId) %>" class="action-btn primary">
                        <i class="fa-solid fa-eye"></i>
                        View Selected
                    </a>

                    <a href="maintenance.jsp" class="action-btn">
                        <i class="fa-solid fa-arrow-left"></i>
                        Back
                    </a>
                </div>
            </section>

            <section class="timeline-panel">
                <h2>Asset Maintenance Timeline</h2>

                <div class="timeline-list">
                    <%
                        for (Map<String, String> row : historyList) {
                    %>
                        <a class="timeline-row" href="view_maintenance.jsp?id=<%= safe(rowValue(row, "maintenance_id")) %>">
                            <div class="timeline-icon">
                                <i class="fa-solid fa-screwdriver-wrench"></i>
                            </div>

                            <div class="timeline-text">
                                <strong>
                                    MNT-<%= display(rowValue(row, "maintenance_id")) %>
                                    · <%= display(cleanLabel(rowValue(row, "maintenance_type"))) %>
                                    · <%= display(cleanLabel(rowValue(row, "maintenance_status"))) %>
                                </strong>

                                <span>
                                    <%= display(rowValue(row, "description")) %>
                                    <br>
                                    Cost: ₹<%= display(rowValue(row, "cost")) %>
                                    · Performed By: <%= display(rowValue(row, "performed_by")) %>
                                </span>
                            </div>

                            <div class="timeline-date">
                                <%= display(rowValue(row, "maintenance_date")) %>
                            </div>
                        </a>
                    <%
                        }
                    %>
                </div>
            </section>

        </div>
    </main>
</div>

<script src="js/user-dropdown.js?v=28000"></script>
<script src="js/sidebar-role.js?v=28000"></script>
<script src="js/topbar-search.js?v=28000"></script>
<script src="js/dashboard-actions.js?v=28000"></script>
</body>
</html>