﻿<%@page contentType="text/html" pageEncoding="UTF-8"%>
<%@page import="com.mycompany.asset_management_system_ams.DBConnection"%>
<%@page import="java.sql.*"%>
<%@page import="java.util.*"%>

<%!
    private String safeText(String value) {
        if (value == null || value.trim().isEmpty()) return "N/A";
        return value.trim()
                .replace("&", "&amp;")
                .replace("<", "&lt;")
                .replace(">", "&gt;")
                .replace("\"", "&quot;")
                .replace("'", "&#39;");
    }

    private String cleanLabel(String value) {
        if (value == null || value.trim().isEmpty()) return "N/A";
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

    private String shortText(String value, int max) {
        if (value == null || value.trim().isEmpty()) return "N/A";
        String text = value.trim();
        return text.length() <= max ? text : text.substring(0, max) + "...";
    }

    private Map<String, String> singleRow(String sql, String id) {
        Map<String, String> row = new HashMap<>();

        try (Connection con = DBConnection.getConnection();
             PreparedStatement ps = con.prepareStatement(sql)) {

            ps.setString(1, id);

            try (ResultSet rs = ps.executeQuery()) {
                ResultSetMetaData meta = rs.getMetaData();
                int columnCount = meta.getColumnCount();

                if (rs.next()) {
                    for (int i = 1; i <= columnCount; i++) {
                        row.put(meta.getColumnLabel(i), rs.getString(i));
                    }
                }
            }

        } catch (Exception e) {
            e.printStackTrace();
        }

        return row;
    }

    private List<Map<String, String>> listRows(String sql, String id) {
        List<Map<String, String>> rows = new ArrayList<>();

        try (Connection con = DBConnection.getConnection();
             PreparedStatement ps = con.prepareStatement(sql)) {

            ps.setString(1, id);

            try (ResultSet rs = ps.executeQuery()) {
                ResultSetMetaData meta = rs.getMetaData();
                int columnCount = meta.getColumnCount();

                while (rs.next()) {
                    Map<String, String> row = new HashMap<>();

                    for (int i = 1; i <= columnCount; i++) {
                        row.put(meta.getColumnLabel(i), rs.getString(i));
                    }

                    rows.add(row);
                }
            }

        } catch (Exception e) {
            e.printStackTrace();
        }

        return rows;
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

    String allocationId = request.getParameter("id");
    if (allocationId == null || allocationId.trim().isEmpty()) {
        allocationId = request.getParameter("allocation_id");
    }

    if (allocationId == null || allocationId.trim().isEmpty()) {
        response.sendRedirect("allocation.jsp?error=invalid");
        return;
    }

    allocationId = allocationId.trim();

    String userInitial = username.substring(0, Math.min(2, username.length())).toUpperCase(Locale.ENGLISH);

    Map<String, String> allocation = singleRow(
            "SELECT "
            + "aa.allocation_id, aa.asset_id, aa.employee_id, aa.allocation_status, aa.issue_condition, "
            + "DATE_FORMAT(aa.allocation_date, '%d %b %Y') AS allocation_date, "
            + "DATE_FORMAT(aa.expected_return_date, '%d %b %Y') AS expected_return_date, "
            + "DATE_FORMAT(aa.return_date, '%d %b %Y') AS return_date, "
            + "aa.remarks, "
            + "DATE_FORMAT(aa.created_at, '%d %b %Y, %h:%i %p') AS created_at, "
            + "DATE_FORMAT(aa.updated_at, '%d %b %Y, %h:%i %p') AS updated_at, "
            + "a.asset_code, a.asset_name, a.serial_number, a.model_number, a.asset_status, a.service_status, "
            + "COALESCE(ac.category_name, 'Uncategorized') AS category_name, "
            + "COALESCE(e.employee_name, 'Employee') AS employee_name, "
            + "COALESCE(e.employee_code, '') AS employee_code, "
            + "COALESCE(e.designation, '') AS designation, "
            + "COALESCE(e.email, '') AS employee_email, "
            + "COALESCE(e.phone, '') AS employee_phone, "
            + "COALESCE(d.department_name, 'No Department') AS department_name, "
            + "COALESCE(rd.division_name, '') AS division_name, "
            + "COALESCE(rl.location_name, '') AS issue_location, "
            + "COALESCE(rl.location_code, '') AS issue_location_code, "
            + "COALESCE(iu.username, 'System') AS issued_by_name, "
            + "COALESCE(ru.username, '') AS received_by_name "
            + "FROM asset_allocation aa "
            + "LEFT JOIN assets a ON aa.asset_id = a.asset_id "
            + "LEFT JOIN asset_categories ac ON a.category_id = ac.category_id "
            + "LEFT JOIN employees e ON aa.employee_id = e.employee_id "
            + "LEFT JOIN departments d ON e.department_id = d.department_id "
            + "LEFT JOIN railway_divisions rd ON e.division_id = rd.division_id "
            + "LEFT JOIN railway_locations rl ON aa.issue_location_id = rl.location_id "
            + "LEFT JOIN users iu ON aa.issued_by = iu.user_id "
            + "LEFT JOIN users ru ON aa.received_by = ru.user_id "
            + "WHERE aa.allocation_id = ? "
            + "LIMIT 1",
            allocationId
    );

    if (allocation.isEmpty()) {
        response.sendRedirect("allocation.jsp?error=notfound");
        return;
    }

    Map<String, String> returnInfo = singleRow(
            "SELECT "
            + "ar.return_id, ar.return_condition, ar.action_after_return, ar.remarks, "
            + "DATE_FORMAT(ar.return_date, '%d %b %Y') AS return_date, "
            + "DATE_FORMAT(ar.created_at, '%d %b %Y, %h:%i %p') AS created_at, "
            + "COALESCE(u.username, 'System') AS received_by_name, "
            + "COALESCE(rl.location_name, '') AS return_location, "
            + "COALESCE(rl.location_code, '') AS return_location_code "
            + "FROM asset_returns ar "
            + "LEFT JOIN users u ON ar.received_by = u.user_id "
            + "LEFT JOIN railway_locations rl ON ar.return_location_id = rl.location_id "
            + "WHERE ar.allocation_id = ? "
            + "LIMIT 1",
            allocationId
    );

    List<Map<String, String>> assetAllocationHistory = listRows(
            "SELECT "
            + "allocation_id, allocation_status, issue_condition, "
            + "DATE_FORMAT(allocation_date, '%d %b %Y') AS allocation_date, "
            + "DATE_FORMAT(return_date, '%d %b %Y') AS return_date, "
            + "COALESCE(remarks, '') AS remarks "
            + "FROM asset_allocation "
            + "WHERE asset_id = (SELECT asset_id FROM asset_allocation WHERE allocation_id = ?) "
            + "ORDER BY allocation_id DESC LIMIT 8",
            allocationId
    );

    String allocationStatus = rowValue(allocation, "allocation_status");
    String statusClass = "";

    if ("RETURNED".equalsIgnoreCase(allocationStatus)) {
        statusClass = "danger";
    }
%>

<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>Allocation Details - IR-AMS</title>

    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.0/css/all.min.css">

    <link rel="stylesheet" href="css/ir-glass.css?v=28000">
    <link rel="stylesheet" href="css/ams-pro.css?v=28000">
    <link rel="stylesheet" href="css/ir-ams-railway-ui.css?v=28000">
<link rel="stylesheet" href="css/view_allocation.css?v=topbarfix1">
</head>

<body class="railway-ui">
<div class="app ams-shell">

    <jsp:include page="sidebar.jsp" />

    <main class="main railway-main">
        <jsp:include page="topbar.jsp" />

        <div class="main-scroll-content detail-board">

            <section class="detail-hero">
                <div>
                    <h1>Allocation #<%= safeText(rowValue(allocation, "allocation_id")) %></h1>
                    <p>
                        <strong><%= safeText(rowValue(allocation, "asset_code")) %></strong>
                        · <%= safeText(rowValue(allocation, "asset_name")) %>
                        · Holder: <%= safeText(rowValue(allocation, "employee_name")) %>
                    </p>
                </div>

                <div class="hero-actions">
                    <span class="status-pill <%= statusClass %>">
                        <i class="fa-solid fa-circle-check"></i>
                        <%= safeText(cleanLabel(allocationStatus)) %>
                    </span>

                    <a href="allocation.jsp" class="btn btn-secondary">
                        <i class="fa-solid fa-arrow-left"></i>
                        Back
                    </a>
                </div>
            </section>

            <section class="summary-grid">
                <div class="summary-card"><span>Asset</span><strong><%= safeText(rowValue(allocation, "asset_code")) %></strong></div>
                <div class="summary-card"><span>Holder</span><strong><%= safeText(rowValue(allocation, "employee_name")) %></strong></div>
                <div class="summary-card"><span>Issue Date</span><strong><%= safeText(rowValue(allocation, "allocation_date")) %></strong></div>
                <div class="summary-card"><span>Expected Return</span><strong><%= safeText(rowValue(allocation, "expected_return_date")) %></strong></div>
            </section>

            <section class="detail-grid">
                <div class="detail-panel">
                    <div class="panel-title-row">
                        <h2 class="panel-title">Allocation Details</h2>
                    </div>

                    <table class="detail-table">
                        <tr><th>Allocation ID</th><td><%= safeText(rowValue(allocation, "allocation_id")) %></td></tr>
                        <tr><th>Allocation Status</th><td><%= safeText(cleanLabel(allocationStatus)) %></td></tr>
                        <tr><th>Issue Condition</th><td><%= safeText(cleanLabel(rowValue(allocation, "issue_condition"))) %></td></tr>
                        <tr><th>Allocation Date</th><td><%= safeText(rowValue(allocation, "allocation_date")) %></td></tr>
                        <tr><th>Expected Return</th><td><%= safeText(rowValue(allocation, "expected_return_date")) %></td></tr>
                        <tr><th>Actual Return</th><td><%= safeText(rowValue(allocation, "return_date")) %></td></tr>
                        <tr><th>Issue Location</th><td><%= safeText(rowValue(allocation, "issue_location")) %> · <%= safeText(rowValue(allocation, "issue_location_code")) %></td></tr>
                        <tr><th>Issued By</th><td><%= safeText(rowValue(allocation, "issued_by_name")) %></td></tr>
                        <tr><th>Received By</th><td><%= safeText(rowValue(allocation, "received_by_name")) %></td></tr>
                        <tr><th>Remarks</th><td><%= safeText(rowValue(allocation, "remarks")) %></td></tr>
                        <tr><th>Created On</th><td><%= safeText(rowValue(allocation, "created_at")) %></td></tr>
                        <tr><th>Updated On</th><td><%= safeText(rowValue(allocation, "updated_at")) %></td></tr>
                    </table>
                </div>

                <div class="detail-panel">
                    <div class="panel-title-row">
                        <h2 class="panel-title">Asset and Holder</h2>
                    </div>

                    <table class="detail-table">
                        <tr><th>Asset Code</th><td><a href="view_asset.jsp?id=<%= safeText(rowValue(allocation, "asset_id")) %>"><%= safeText(rowValue(allocation, "asset_code")) %></a></td></tr>
                        <tr><th>Asset Name</th><td><%= safeText(rowValue(allocation, "asset_name")) %></td></tr>
                        <tr><th>Category</th><td><%= safeText(rowValue(allocation, "category_name")) %></td></tr>
                        <tr><th>Serial Number</th><td><%= safeText(rowValue(allocation, "serial_number")) %></td></tr>
                        <tr><th>Model Number</th><td><%= safeText(rowValue(allocation, "model_number")) %></td></tr>
                        <tr><th>Asset Status</th><td><%= safeText(cleanLabel(rowValue(allocation, "asset_status"))) %></td></tr>
                        <tr><th>Service Status</th><td><%= safeText(cleanLabel(rowValue(allocation, "service_status"))) %></td></tr>
                        <tr><th>Holder</th><td><a href="view_employee.jsp?id=<%= safeText(rowValue(allocation, "employee_id")) %>"><%= safeText(rowValue(allocation, "employee_name")) %></a></td></tr>
                        <tr><th>Employee Code</th><td><%= safeText(rowValue(allocation, "employee_code")) %></td></tr>
                        <tr><th>Designation</th><td><%= safeText(rowValue(allocation, "designation")) %></td></tr>
                        <tr><th>Department</th><td><%= safeText(rowValue(allocation, "department_name")) %></td></tr>
                        <tr><th>Division</th><td><%= safeText(rowValue(allocation, "division_name")) %></td></tr>
                    </table>
                </div>
            </section>

            <section class="detail-grid">
                <div class="detail-panel">
                    <div class="panel-title-row">
                        <h2 class="panel-title">Return Details</h2>
                    </div>

                    <% if (returnInfo.isEmpty()) { %>
                        <div class="empty-box">
                            <i class="fa-solid fa-rotate-left"></i>
                            <strong>Not returned yet</strong>
                            <span>Return details will appear here after the asset is returned.</span>
                        </div>
                    <% } else { %>
                        <table class="detail-table">
                            <tr><th>Return ID</th><td><a href="view_return.jsp?id=<%= safeText(rowValue(returnInfo, "return_id")) %>"><%= safeText(rowValue(returnInfo, "return_id")) %></a></td></tr>
                            <tr><th>Return Date</th><td><%= safeText(rowValue(returnInfo, "return_date")) %></td></tr>
                            <tr><th>Return Condition</th><td><%= safeText(cleanLabel(rowValue(returnInfo, "return_condition"))) %></td></tr>
                            <tr><th>Action After Return</th><td><%= safeText(cleanLabel(rowValue(returnInfo, "action_after_return"))) %></td></tr>
                            <tr><th>Return Location</th><td><%= safeText(rowValue(returnInfo, "return_location")) %> · <%= safeText(rowValue(returnInfo, "return_location_code")) %></td></tr>
                            <tr><th>Received By</th><td><%= safeText(rowValue(returnInfo, "received_by_name")) %></td></tr>
                            <tr><th>Remarks</th><td><%= safeText(rowValue(returnInfo, "remarks")) %></td></tr>
                            <tr><th>Created On</th><td><%= safeText(rowValue(returnInfo, "created_at")) %></td></tr>
                        </table>
                    <% } %>
                </div>

                <div class="detail-panel">
                    <div class="panel-title-row">
                        <h2 class="panel-title">Asset Allocation History</h2>
                    </div>

                    <div class="timeline-list">
                        <% if (assetAllocationHistory.isEmpty()) { %>
                            <div class="empty-box">
                                <i class="fa-solid fa-clock-rotate-left"></i>
                                <strong>No allocation history</strong>
                                <span>Asset issue history will appear here.</span>
                            </div>
                        <% } else {
                            for (Map<String, String> row : assetAllocationHistory) {
                        %>
                            <a class="timeline-row" href="view_allocation.jsp?id=<%= safeText(rowValue(row, "allocation_id")) %>">
                                <div class="timeline-icon"><i class="fa-solid fa-arrow-right-arrow-left"></i></div>
                                <div class="timeline-text">
                                    <strong>Allocation #<%= safeText(rowValue(row, "allocation_id")) %> · <%= safeText(cleanLabel(rowValue(row, "allocation_status"))) %></strong>
                                    <span><%= safeText(cleanLabel(rowValue(row, "issue_condition"))) %> · Return: <%= safeText(rowValue(row, "return_date")) %> · <%= safeText(shortText(rowValue(row, "remarks"), 70)) %></span>
                                </div>
                                <div class="timeline-date"><%= safeText(rowValue(row, "allocation_date")) %></div>
                            </a>
                        <%  }
                        } %>
                    </div>
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
