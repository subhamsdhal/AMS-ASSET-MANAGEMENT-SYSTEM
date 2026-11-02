﻿<%@page contentType="text/html" pageEncoding="UTF-8"%>
<%@page import="com.mycompany.asset_management_system_ams.DBConnection"%>
<%@page import="java.sql.*"%>
<%@page import="java.util.*"%>
<%@page import="java.text.NumberFormat"%>

<%!
    private String safeText(Object value) {
        if (value == null || value.toString().trim().isEmpty()) {
            return "N/A";
        }

        return value.toString().trim()
                .replace("&", "&amp;")
                .replace("<", "&lt;")
                .replace(">", "&gt;")
                .replace("\"", "&quot;")
                .replace("'", "&#39;");
    }

    private String safeValue(Object value) {
        if (value == null) {
            return "";
        }

        return value.toString().trim()
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

    private String moneyText(String value) {
        try {
            double amount = Double.parseDouble(value == null ? "0" : value);
            NumberFormat nf = NumberFormat.getNumberInstance(new Locale("en", "IN"));
            nf.setMinimumFractionDigits(2);
            nf.setMaximumFractionDigits(2);
            return nf.format(amount);
        } catch (Exception e) {
            return "0.00";
        }
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

    boolean canManageMaintenance = ("SUPER_ADMIN".equals(role) || "ADMIN".equals(role))
            || "ASSET_MANAGER".equalsIgnoreCase(role);

    String maintenanceId = request.getParameter("id");

    if (maintenanceId == null || maintenanceId.trim().isEmpty()) {
        response.sendRedirect("maintenance.jsp?error=invalid");
        return;
    }

    maintenanceId = maintenanceId.trim();

    String msg = request.getParameter("msg");
    String userInitial = username.substring(0, Math.min(2, username.length())).toUpperCase(Locale.ENGLISH);

    Map<String, String> maintenance = new HashMap<String, String>();

    try (Connection con = DBConnection.getConnection()) {

        boolean hasStatus = columnExists(con, "maintenance_logs", "maintenance_status");
        boolean hasNextDue = columnExists(con, "maintenance_logs", "next_due_date");
        boolean hasIssue = columnExists(con, "maintenance_logs", "issue_reported");
        boolean hasWork = columnExists(con, "maintenance_logs", "work_done");
        boolean hasDescription = columnExists(con, "maintenance_logs", "description");
        boolean hasPerformedBy = columnExists(con, "maintenance_logs", "performed_by");
        boolean hasVendor = columnExists(con, "maintenance_logs", "vendor_id");
        boolean hasRemarks = columnExists(con, "maintenance_logs", "remarks");

        String sql = "SELECT "
                + "ml.maintenance_id, ml.asset_id, "
                + "DATE_FORMAT(ml.maintenance_date, '%d %b %Y') AS maintenance_date_display, "
                + "DATE_FORMAT(ml.maintenance_date, '%Y-%m-%d') AS maintenance_date_raw, "
                + "ml.maintenance_type, "
                + (hasStatus ? "COALESCE(ml.maintenance_status, '')" : "''") + " AS maintenance_status, "
                + (hasNextDue ? "DATE_FORMAT(ml.next_due_date, '%d %b %Y')" : "''") + " AS next_due_date, "
                + (hasIssue ? "COALESCE(ml.issue_reported, '')" : (hasDescription ? "COALESCE(ml.description, '')" : "''")) + " AS issue_reported, "
                + (hasWork ? "COALESCE(ml.work_done, '')" : "''") + " AS work_done, "
                + (hasDescription ? "COALESCE(ml.description, '')" : "''") + " AS description, "
                + "COALESCE(ml.cost, 0) AS cost, "
                + (hasPerformedBy ? "COALESCE(ml.performed_by, '')" : "''") + " AS performed_by, "
                + (hasRemarks ? "COALESCE(ml.remarks, '')" : "''") + " AS remarks, "
                + "a.asset_code, a.asset_name, a.asset_status, a.serial_number, a.location, "
                + "COALESCE(c.category_name, 'Uncategorized') AS category_name, "
                + (hasVendor ? "COALESCE(v.vendor_name, 'Internal Maintenance')" : "'Internal Maintenance'") + " AS supplier_name "
                + "FROM maintenance_logs ml "
                + "LEFT JOIN assets a ON ml.asset_id = a.asset_id "
                + "LEFT JOIN asset_categories c ON a.category_id = c.category_id "
                + (hasVendor ? "LEFT JOIN vendors v ON ml.vendor_id = v.vendor_id " : "")
                + "WHERE ml.maintenance_id = ? "
                + "LIMIT 1";

        try (PreparedStatement ps = con.prepareStatement(sql)) {
            ps.setString(1, maintenanceId);

            try (ResultSet rs = ps.executeQuery()) {
                ResultSetMetaData meta = rs.getMetaData();
                int count = meta.getColumnCount();

                if (rs.next()) {
                    for (int i = 1; i <= count; i++) {
                        maintenance.put(meta.getColumnLabel(i), rs.getString(i));
                    }
                }
            }
        }

    } catch (Exception e) {
        e.printStackTrace();
        response.sendRedirect("maintenance.jsp?error=server");
        return;
    }

    if (maintenance.isEmpty()) {
        response.sendRedirect("maintenance.jsp?error=notfound");
        return;
    }
%>

<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>View Maintenance - IR-AMS</title>

    <link rel="stylesheet"
          href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.0/css/all.min.css">

    <link rel="stylesheet" href="css/ir-glass.css?v=28000">
    <link rel="stylesheet" href="css/ams-pro.css?v=28000">
    <link rel="stylesheet" href="css/ir-ams-railway-ui.css?v=28000">
<link rel="stylesheet" href="css/view_maintenance.css?v=topbarfix1">
</head>

<body class="railway-ui">
<div class="app ams-shell">

    <jsp:include page="sidebar.jsp" />

    <main class="main railway-main">
        <jsp:include page="topbar.jsp" />

        <div class="main-scroll-content view-board">

            <% if ("updated".equals(msg)) { %>
                <div class="page-success">
                    <i class="fa-solid fa-circle-check"></i>
                    Maintenance record updated successfully.
                </div>
            <% } %>

            <section class="view-hero">
                <div>
                    <h1>Maintenance MNT-<%= safeText(maintenanceId) %></h1>
                    <p>
                        <strong><%= safeText(rowValue(maintenance, "asset_code")) %></strong>
                        · <%= safeText(rowValue(maintenance, "asset_name")) %>
                        · <%= safeText(cleanLabel(rowValue(maintenance, "maintenance_type"))) %>
                    </p>
                </div>

                <div class="hero-actions">
                    <a href="maintenance.jsp" class="action-btn">
                        <i class="fa-solid fa-arrow-left"></i>
                        Back
                    </a>

                    <% if (canManageMaintenance) { %>
                        <a href="edit_maintenance.jsp?id=<%= safeValue(maintenanceId) %>" class="action-btn gold">
                            <i class="fa-solid fa-pen-to-square"></i>
                            Edit
                        </a>
                    <% } %>

                    <a href="maintenance_history.jsp?id=<%= safeValue(maintenanceId) %>" class="action-btn primary">
                        <i class="fa-solid fa-clock-rotate-left"></i>
                        History
                    </a>

                    <% if (canManageMaintenance && "UNDER_MAINTENANCE".equalsIgnoreCase(rowValue(maintenance, "asset_status"))) { %>
                        <form action="resolve_maintenance.jsp" method="post" style="display:inline;" onsubmit="return confirm('Resolve this maintenance and mark asset as AVAILABLE?');">
                            <input type="hidden" name="id" value="<%= safeValue(maintenanceId) %>">
                            <button type="submit" class="action-btn green" style="border:none; cursor:pointer;">
                                <i class="fa-solid fa-circle-check"></i>
                                Resolve
                            </button>
                        </form>
                    <% } %>
                </div>
            </section>

            <section class="status-card-row">
                <div class="status-card">
                    <span>Maintenance Type</span>
                    <strong><%= safeText(cleanLabel(rowValue(maintenance, "maintenance_type"))) %></strong>
                </div>

                <div class="status-card">
                    <span>Maintenance Status</span>
                    <strong><%= safeText(cleanLabel(rowValue(maintenance, "maintenance_status"))) %></strong>
                </div>

                <div class="status-card">
                    <span>Asset Status</span>
                    <strong><%= safeText(cleanLabel(rowValue(maintenance, "asset_status"))) %></strong>
                </div>
            </section>

            <section class="detail-grid">

                <div class="detail-panel">
                    <h2>Maintenance Details</h2>

                    <table class="detail-table">
                        <tr><th>Maintenance ID</th><td>MNT-<%= safeText(maintenanceId) %></td></tr>
                        <tr><th>Date</th><td><%= safeText(rowValue(maintenance, "maintenance_date_display")) %></td></tr>
                        <tr><th>Next Due</th><td><%= safeText(rowValue(maintenance, "next_due_date")) %></td></tr>
                        <tr><th>Type</th><td><%= safeText(cleanLabel(rowValue(maintenance, "maintenance_type"))) %></td></tr>
                        <tr><th>Status</th><td><%= safeText(cleanLabel(rowValue(maintenance, "maintenance_status"))) %></td></tr>
                        <tr><th>Cost</th><td>₹ <%= moneyText(rowValue(maintenance, "cost")) %></td></tr>
                        <tr><th>Performed By</th><td><%= safeText(rowValue(maintenance, "performed_by")) %></td></tr>
                        <tr><th>Supplier</th><td><%= safeText(rowValue(maintenance, "supplier_name")) %></td></tr>
                    </table>
                </div>

                <div class="detail-panel">
                    <h2>Asset Details</h2>

                    <table class="detail-table">
                        <tr><th>Asset Code</th><td><%= safeText(rowValue(maintenance, "asset_code")) %></td></tr>
                        <tr><th>Asset Name</th><td><%= safeText(rowValue(maintenance, "asset_name")) %></td></tr>
                        <tr><th>Category</th><td><%= safeText(rowValue(maintenance, "category_name")) %></td></tr>
                        <tr><th>Serial Number</th><td><%= safeText(rowValue(maintenance, "serial_number")) %></td></tr>
                        <tr><th>Location</th><td><%= safeText(rowValue(maintenance, "location")) %></td></tr>
                        <tr><th>Asset Status</th><td><%= safeText(cleanLabel(rowValue(maintenance, "asset_status"))) %></td></tr>
                        <tr>
                            <th>Asset Link</th>
                            <td>
                                <a class="action-btn primary" href="view_asset.jsp?id=<%= safeValue(rowValue(maintenance, "asset_id")) %>">
                                    <i class="fa-solid fa-up-right-from-square"></i>
                                    Open Asset
                                </a>
                            </td>
                        </tr>
                    </table>
                </div>

            </section>

            
            <section class="detail-panel">
                <h2>Work Notes</h2>

                <table class="detail-table">
                    <tr><th>Issue Reported</th><td><%= safeText(rowValue(maintenance, "issue_reported")) %></td></tr>
                    <tr><th>Work Done</th><td><%= safeText(rowValue(maintenance, "work_done")) %></td></tr>
                    <tr><th>Description</th><td><%= safeText(rowValue(maintenance, "description")) %></td></tr>
                    <tr><th>Remarks</th><td><%= safeText(rowValue(maintenance, "remarks")) %></td></tr>
                </table>
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