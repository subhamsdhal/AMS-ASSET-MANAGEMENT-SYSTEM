﻿<%@page contentType="text/html" pageEncoding="UTF-8"%>
<%@page import="com.mycompany.asset_management_system_ams.DBConnection"%>
<%@page import="java.sql.*"%>
<%@page import="java.util.*"%>

<%!
    private String safeText(String value) {
        if (value == null || value.trim().isEmpty()) return "N/A";
        return value.trim().replace("&","&amp;").replace("<","&lt;").replace(">","&gt;").replace("\"","&quot;").replace("'","&#39;");
    }

    private String cleanLabel(String value) {
        if (value == null || value.trim().isEmpty()) return "N/A";
        String text = value.trim().replace("_", " ").toLowerCase(Locale.ENGLISH);
        String[] parts = text.split("\\s+");
        StringBuilder out = new StringBuilder();
        for (String part : parts) {
            if (part.length() > 0) out.append(Character.toUpperCase(part.charAt(0))).append(part.substring(1)).append(" ");
        }
        return out.toString().trim();
    }

    private Map<String, String> singleRow(String sql, String id) {
        Map<String, String> row = new HashMap<>();
        try (Connection con = DBConnection.getConnection();
             PreparedStatement ps = con.prepareStatement(sql)) {
            ps.setString(1, id);
            try (ResultSet rs = ps.executeQuery()) {
                ResultSetMetaData meta = rs.getMetaData();
                int count = meta.getColumnCount();
                if (rs.next()) {
                    for (int i = 1; i <= count; i++) row.put(meta.getColumnLabel(i), rs.getString(i));
                }
            }
        } catch (Exception e) {
            e.printStackTrace();
        }
        return row;
    }

    private String rowValue(Map<String, String> row, String key) {
        if (row == null) return "";
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

    String returnId = request.getParameter("id");
    if (returnId == null || returnId.trim().isEmpty()) returnId = request.getParameter("return_id");

    if (returnId == null || returnId.trim().isEmpty()) {
        response.sendRedirect("allocation.jsp?error=invalid_return");
        return;
    }

    returnId = returnId.trim();

    String userInitial = username.substring(0, Math.min(2, username.length())).toUpperCase(Locale.ENGLISH);

    Map<String, String> ret = singleRow(
            "SELECT "
            + "ar.return_id, ar.allocation_id, ar.asset_id, ar.employee_id, ar.return_condition, ar.action_after_return, ar.remarks, "
            + "DATE_FORMAT(ar.return_date, '%d %b %Y') AS return_date, "
            + "DATE_FORMAT(ar.created_at, '%d %b %Y, %h:%i %p') AS created_at, "
            + "DATE_FORMAT(ar.updated_at, '%d %b %Y, %h:%i %p') AS updated_at, "
            + "a.asset_code, a.asset_name, a.serial_number, a.model_number, a.asset_status, a.service_status, "
            + "COALESCE(ac.category_name, 'Uncategorized') AS category_name, "
            + "COALESCE(e.employee_name, 'Employee') AS employee_name, "
            + "COALESCE(e.employee_code, '') AS employee_code, "
            + "COALESCE(e.designation, '') AS designation, "
            + "COALESCE(d.department_name, 'No Department') AS department_name, "
            + "COALESCE(u.username, 'System') AS received_by_name, "
            + "COALESCE(rl.location_name, '') AS return_location, "
            + "COALESCE(rl.location_code, '') AS return_location_code, "
            + "DATE_FORMAT(aa.allocation_date, '%d %b %Y') AS allocation_date, "
            + "DATE_FORMAT(aa.expected_return_date, '%d %b %Y') AS expected_return_date "
            + "FROM asset_returns ar "
            + "LEFT JOIN asset_allocation aa ON ar.allocation_id = aa.allocation_id "
            + "LEFT JOIN assets a ON ar.asset_id = a.asset_id "
            + "LEFT JOIN asset_categories ac ON a.category_id = ac.category_id "
            + "LEFT JOIN employees e ON ar.employee_id = e.employee_id "
            + "LEFT JOIN departments d ON e.department_id = d.department_id "
            + "LEFT JOIN users u ON ar.received_by = u.user_id "
            + "LEFT JOIN railway_locations rl ON ar.return_location_id = rl.location_id "
            + "WHERE ar.return_id = ? LIMIT 1",
            returnId
    );

    if (ret.isEmpty()) {
        response.sendRedirect("allocation.jsp?error=return_notfound");
        return;
    }

    String returnCondition = rowValue(ret, "return_condition");
    String statusClass = "";
    if ("DAMAGED".equalsIgnoreCase(returnCondition) || "NEEDS_REPAIR".equalsIgnoreCase(returnCondition)) statusClass = "warning";
%>

<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>Return Details - IR-AMS</title>

    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.0/css/all.min.css">

    <link rel="stylesheet" href="css/ir-glass.css?v=28000">
    <link rel="stylesheet" href="css/ams-pro.css?v=28000">
    <link rel="stylesheet" href="css/ir-ams-railway-ui.css?v=28000">
<link rel="stylesheet" href="css/view_return.css?v=topbarfix1">
</head>

<body class="railway-ui">
<div class="app ams-shell">

    <jsp:include page="sidebar.jsp" />

    <main class="main railway-main">
        <jsp:include page="topbar.jsp" />

        <div class="main-scroll-content detail-board">

            <section class="detail-hero">
                <div>
                    <h1>Return #<%= safeText(rowValue(ret, "return_id")) %></h1>
                    <p>
                        <strong><%= safeText(rowValue(ret, "asset_code")) %></strong>
                        · <%= safeText(rowValue(ret, "asset_name")) %>
                        · Holder: <%= safeText(rowValue(ret, "employee_name")) %>
                    </p>
                </div>

                <div class="hero-actions">
                    <span class="status-pill <%= statusClass %>">
                        <i class="fa-solid fa-rotate-left"></i>
                        <%= safeText(cleanLabel(returnCondition)) %>
                    </span>

                    <a href="allocation.jsp" class="btn btn-secondary">
                        <i class="fa-solid fa-arrow-left"></i>
                        Back
                    </a>
                </div>
            </section>

            <section class="summary-grid">
                <div class="summary-card"><span>Asset</span><strong><%= safeText(rowValue(ret, "asset_code")) %></strong></div>
                <div class="summary-card"><span>Holder</span><strong><%= safeText(rowValue(ret, "employee_name")) %></strong></div>
                <div class="summary-card"><span>Return Date</span><strong><%= safeText(rowValue(ret, "return_date")) %></strong></div>
                <div class="summary-card"><span>Action After Return</span><strong><%= safeText(cleanLabel(rowValue(ret, "action_after_return"))) %></strong></div>
            </section>

            <section class="detail-grid">
                <div class="detail-panel">
                    <div class="panel-title-row"><h2 class="panel-title">Return Details</h2></div>

                    <table class="detail-table">
                        <tr><th>Return ID</th><td><%= safeText(rowValue(ret, "return_id")) %></td></tr>
                        <tr><th>Allocation ID</th><td><a href="view_allocation.jsp?id=<%= safeText(rowValue(ret, "allocation_id")) %>"><%= safeText(rowValue(ret, "allocation_id")) %></a></td></tr>
                        <tr><th>Return Date</th><td><%= safeText(rowValue(ret, "return_date")) %></td></tr>
                        <tr><th>Return Condition</th><td><%= safeText(cleanLabel(returnCondition)) %></td></tr>
                        <tr><th>Action After Return</th><td><%= safeText(cleanLabel(rowValue(ret, "action_after_return"))) %></td></tr>
                        <tr><th>Return Location</th><td><%= safeText(rowValue(ret, "return_location")) %> · <%= safeText(rowValue(ret, "return_location_code")) %></td></tr>
                        <tr><th>Received By</th><td><%= safeText(rowValue(ret, "received_by_name")) %></td></tr>
                        <tr><th>Remarks</th><td><%= safeText(rowValue(ret, "remarks")) %></td></tr>
                        <tr><th>Created On</th><td><%= safeText(rowValue(ret, "created_at")) %></td></tr>
                        <tr><th>Updated On</th><td><%= safeText(rowValue(ret, "updated_at")) %></td></tr>
                    </table>
                </div>

                <div class="detail-panel">
                    <div class="panel-title-row"><h2 class="panel-title">Asset and Holder</h2></div>

                    <table class="detail-table">
                        <tr><th>Asset Code</th><td><a href="view_asset.jsp?id=<%= safeText(rowValue(ret, "asset_id")) %>"><%= safeText(rowValue(ret, "asset_code")) %></a></td></tr>
                        <tr><th>Asset Name</th><td><%= safeText(rowValue(ret, "asset_name")) %></td></tr>
                        <tr><th>Category</th><td><%= safeText(rowValue(ret, "category_name")) %></td></tr>
                        <tr><th>Serial Number</th><td><%= safeText(rowValue(ret, "serial_number")) %></td></tr>
                        <tr><th>Model Number</th><td><%= safeText(rowValue(ret, "model_number")) %></td></tr>
                        <tr><th>Asset Status</th><td><%= safeText(cleanLabel(rowValue(ret, "asset_status"))) %></td></tr>
                        <tr><th>Service Status</th><td><%= safeText(cleanLabel(rowValue(ret, "service_status"))) %></td></tr>
                        <tr><th>Holder</th><td><a href="view_employee.jsp?id=<%= safeText(rowValue(ret, "employee_id")) %>"><%= safeText(rowValue(ret, "employee_name")) %></a></td></tr>
                        <tr><th>Employee Code</th><td><%= safeText(rowValue(ret, "employee_code")) %></td></tr>
                        <tr><th>Designation</th><td><%= safeText(rowValue(ret, "designation")) %></td></tr>
                        <tr><th>Department</th><td><%= safeText(rowValue(ret, "department_name")) %></td></tr>
                        <tr><th>Allocation Date</th><td><%= safeText(rowValue(ret, "allocation_date")) %></td></tr>
                        <tr><th>Expected Return</th><td><%= safeText(rowValue(ret, "expected_return_date")) %></td></tr>
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
