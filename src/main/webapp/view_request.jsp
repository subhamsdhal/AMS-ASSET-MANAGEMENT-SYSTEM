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

    private List<Map<String, String>> listRows(String sql, String id) {
        List<Map<String, String>> rows = new ArrayList<>();
        try (Connection con = DBConnection.getConnection();
             PreparedStatement ps = con.prepareStatement(sql)) {
            ps.setString(1, id);
            try (ResultSet rs = ps.executeQuery()) {
                ResultSetMetaData meta = rs.getMetaData();
                int count = meta.getColumnCount();
                while (rs.next()) {
                    Map<String, String> row = new HashMap<>();
                    for (int i = 1; i <= count; i++) row.put(meta.getColumnLabel(i), rs.getString(i));
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

    private int linkedEmployeeId(int userId) {
        if (userId <= 0) {
            return 0;
        }

        try (Connection con = DBConnection.getConnection();
             PreparedStatement ps = con.prepareStatement("SELECT employee_id FROM users WHERE user_id = ? AND employee_id IS NOT NULL")) {
            ps.setInt(1, userId);

            try (ResultSet rs = ps.executeQuery()) {
                if (rs.next()) {
                    return rs.getInt("employee_id");
                }
            }
        } catch (Exception e) {
            e.printStackTrace();
        }

        return 0;
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

    String requestId = request.getParameter("id");
    if (requestId == null || requestId.trim().isEmpty()) requestId = request.getParameter("request_id");

    if (requestId == null || requestId.trim().isEmpty()) {
        response.sendRedirect("asset_requests.jsp?error=invalid");
        return;
    }

    requestId = requestId.trim();

    String userInitial = username.substring(0, Math.min(2, username.length())).toUpperCase(Locale.ENGLISH);
    int currentUserId = 0;

    try {
        Object userIdObj = session.getAttribute("user_id");
        if (userIdObj == null) {
            userIdObj = session.getAttribute("userId");
        }
        if (userIdObj != null) {
            currentUserId = Integer.parseInt(String.valueOf(userIdObj));
        }
    } catch (Exception e) {
        currentUserId = 0;
    }

    Map<String, String> req = singleRow(
            "SELECT "
            + "ar.request_id, ar.employee_id, ar.category_id, ar.fulfilled_asset_id, ar.fulfilled_allocation_id, "
            + "ar.request_type, ar.request_status, ar.priority, "
            + "DATE_FORMAT(ar.request_date, '%d %b %Y') AS request_date, "
            + "DATE_FORMAT(ar.required_by_date, '%d %b %Y') AS required_by_date, "
            + "DATE_FORMAT(ar.approved_date, '%d %b %Y') AS approved_date, "
            + "ar.request_reason, ar.remarks, "
            + "DATE_FORMAT(ar.created_at, '%d %b %Y, %h:%i %p') AS created_at, "
            + "DATE_FORMAT(ar.updated_at, '%d %b %Y, %h:%i %p') AS updated_at, "
            + "COALESCE(e.employee_name, 'Employee') AS employee_name, "
            + "COALESCE(e.employee_code, '') AS employee_code, "
            + "COALESCE(e.designation, '') AS designation, "
            + "COALESCE(e.email, '') AS employee_email, "
            + "COALESCE(e.phone, '') AS employee_phone, "
            + "COALESCE(ac.category_name, 'No Category') AS category_name, "
            + "COALESCE(d.department_name, 'No Department') AS department_name, "
            + "COALESCE(rd.division_name, '') AS division_name, "
            + "COALESCE(rl.location_name, '') AS location_name, "
            + "COALESCE(rl.location_code, '') AS location_code, "
            + "COALESCE(u.username, '') AS approved_by_name, "
            + "COALESCE(fa.asset_code, '') AS fulfilled_asset_code, "
            + "COALESCE(fa.asset_name, '') AS fulfilled_asset_name, "
            + "ar.dept_head_action, COALESCE(dh.username, '') AS dept_head_by_name, "
            + "DATE_FORMAT(ar.dept_head_date, '%d %b %Y') AS dept_head_date, "
            + "ar.dept_head_remarks "
            + "FROM asset_requests ar "
            + "LEFT JOIN employees e ON ar.employee_id = e.employee_id "
            + "LEFT JOIN asset_categories ac ON ar.category_id = ac.category_id "
            + "LEFT JOIN departments d ON ar.department_id = d.department_id "
            + "LEFT JOIN railway_divisions rd ON ar.division_id = rd.division_id "
            + "LEFT JOIN railway_locations rl ON ar.location_id = rl.location_id "
            + "LEFT JOIN users u ON ar.approved_by = u.user_id "
            + "LEFT JOIN users dh ON ar.dept_head_by = dh.user_id "
            + "LEFT JOIN assets fa ON ar.fulfilled_asset_id = fa.asset_id "
            + "WHERE ar.request_id = ? LIMIT 1",
            requestId
    );

    if (req.isEmpty()) {
        response.sendRedirect("asset_requests.jsp?error=notfound");
        return;
    }

    String employeeId = rowValue(req, "employee_id");

    if ("EMPLOYEE".equals(role)) {
        int linkedEmpId = linkedEmployeeId(currentUserId);

        if (linkedEmpId <= 0 || !String.valueOf(linkedEmpId).equals(employeeId)) {
            response.sendRedirect("dashboard.jsp?access=denied");
            return;
        }
    }

    String categoryId = rowValue(req, "category_id");

    List<Map<String, String>> employeeRequestRows = listRows(
            "SELECT request_id, request_type, request_status, priority, "
            + "DATE_FORMAT(request_date, '%d %b %Y') AS request_date, "
            + "request_reason "
            + "FROM asset_requests "
            + "WHERE employee_id = ? "
            + "ORDER BY request_id DESC LIMIT 8",
            employeeId
    );

    List<Map<String, String>> categoryAssetRows = listRows(
            "SELECT asset_id, asset_code, asset_name, asset_status, service_status "
            + "FROM assets "
            + "WHERE category_id = ? "
            + "ORDER BY asset_id DESC LIMIT 8",
            categoryId
    );

    String requestStatus = rowValue(req, "request_status");
    String statusClass = "";
    if ("PENDING".equalsIgnoreCase(requestStatus) || "PENDING_DEPT_HEAD".equalsIgnoreCase(requestStatus)) statusClass = "warning";
    if ("REJECTED".equalsIgnoreCase(requestStatus) || "CANCELLED".equalsIgnoreCase(requestStatus)) statusClass = "danger";
%>

<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>Request Details - IR-AMS</title>

    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.0/css/all.min.css">

    <link rel="stylesheet" href="css/ir-glass.css?v=28000">
    <link rel="stylesheet" href="css/ams-pro.css?v=28000">
    <link rel="stylesheet" href="css/ir-ams-railway-ui.css?v=28000">
<link rel="stylesheet" href="css/view_request.css?v=topbarfix1">
</head>

<body class="railway-ui">
<div class="app ams-shell">

    <jsp:include page="sidebar.jsp" />

    <main class="main railway-main">
        <jsp:include page="topbar.jsp" />

        <div class="main-scroll-content detail-board">

            <section class="detail-hero">
                <div>
                    <h1>Request #<%= safeText(rowValue(req, "request_id")) %></h1>
                    <p>
                        <strong><%= safeText(rowValue(req, "employee_name")) %></strong>
                        · <%= safeText(rowValue(req, "category_name")) %>
                        · <%= safeText(cleanLabel(rowValue(req, "priority"))) %>
                    </p>
                </div>

                <div class="hero-actions">
                    <span class="status-pill <%= statusClass %>">
                        <i class="fa-regular fa-square-plus"></i>
                        <%= safeText(cleanLabel(requestStatus)) %>
                    </span>

                    <%-- No "Edit" action here: there has never been an edit_request.jsp
                         or a backend update-fields endpoint for asset requests (only
                         UpdateRequestStatusServlet, which changes status/remarks, not
                         the request itself). The button that used to link to
                         edit_request.jsp always 404'd - removed rather than building a
                         new edit workflow that wasn't part of this audit's scope. --%>

                    <a href="asset_requests.jsp" class="btn btn-secondary">
                        <i class="fa-solid fa-arrow-left"></i>
                        Back
                    </a>
                </div>
            </section>

            <section class="summary-grid">
                <div class="summary-card"><span>Request Type</span><strong><%= safeText(cleanLabel(rowValue(req, "request_type"))) %></strong></div>
                <div class="summary-card"><span>Priority</span><strong><%= safeText(cleanLabel(rowValue(req, "priority"))) %></strong></div>
                <div class="summary-card"><span>Request Date</span><strong><%= safeText(rowValue(req, "request_date")) %></strong></div>
                <div class="summary-card"><span>Required By</span><strong><%= safeText(rowValue(req, "required_by_date")) %></strong></div>
            </section>

            <section class="detail-grid">
                <div class="detail-panel">
                    <div class="panel-title-row"><h2 class="panel-title">Request Details</h2></div>

                    <table class="detail-table">
                        <tr><th>Request ID</th><td><%= safeText(rowValue(req, "request_id")) %></td></tr>
                        <tr><th>Request Type</th><td><%= safeText(cleanLabel(rowValue(req, "request_type"))) %></td></tr>
                        <tr><th>Status</th><td><%= safeText(cleanLabel(requestStatus)) %></td></tr>
                        <tr><th>Priority</th><td><%= safeText(cleanLabel(rowValue(req, "priority"))) %></td></tr>
                        <tr><th>Request Date</th><td><%= safeText(rowValue(req, "request_date")) %></td></tr>
                        <tr><th>Required By</th><td><%= safeText(rowValue(req, "required_by_date")) %></td></tr>
                        <tr><th>Category</th><td><a href="view_category.jsp?id=<%= safeText(rowValue(req, "category_id")) %>"><%= safeText(rowValue(req, "category_name")) %></a></td></tr>
                        <tr><th>Department</th><td><%= safeText(rowValue(req, "department_name")) %></td></tr>
                        <tr><th>Division</th><td><%= safeText(rowValue(req, "division_name")) %></td></tr>
                        <tr><th>Location</th><td><%= safeText(rowValue(req, "location_name")) %> · <%= safeText(rowValue(req, "location_code")) %></td></tr>
                        <% if (!rowValue(req, "dept_head_action").trim().isEmpty()) { %>
                        <tr><th>Department Head Action</th><td><%= safeText(cleanLabel(rowValue(req, "dept_head_action"))) %> by <%= safeText(rowValue(req, "dept_head_by_name")) %> on <%= safeText(rowValue(req, "dept_head_date")) %></td></tr>
                        <% if (!rowValue(req, "dept_head_remarks").trim().isEmpty()) { %>
                        <tr><th>Department Head Remarks</th><td><%= safeText(rowValue(req, "dept_head_remarks")) %></td></tr>
                        <% } %>
                        <% } %>
                        <tr><th>Approved By</th><td><%= safeText(rowValue(req, "approved_by_name")) %></td></tr>
                        <tr><th>Approved Date</th><td><%= safeText(rowValue(req, "approved_date")) %></td></tr>
                        <tr><th>Fulfilled Asset</th><td>
                            <% if (rowValue(req, "fulfilled_asset_id").trim().isEmpty()) { %>
                                N/A
                            <% } else { %>
                                <a href="view_asset.jsp?id=<%= safeText(rowValue(req, "fulfilled_asset_id")) %>">
                                    <%= safeText(rowValue(req, "fulfilled_asset_code")) %> · <%= safeText(rowValue(req, "fulfilled_asset_name")) %>
                                </a>
                            <% } %>
                        </td></tr>
                        <tr><th>Fulfilling Allocation</th><td>
                            <% if (rowValue(req, "fulfilled_allocation_id").trim().isEmpty()) { %>
                                N/A
                            <% } else { %>
                                <a href="view_allocation.jsp?id=<%= safeText(rowValue(req, "fulfilled_allocation_id")) %>">
                                    Allocation #<%= safeText(rowValue(req, "fulfilled_allocation_id")) %>
                                </a>
                            <% } %>
                        </td></tr>
                        <tr><th>Reason</th><td><%= safeText(rowValue(req, "request_reason")) %></td></tr>
                        <tr><th>Remarks</th><td><%= safeText(rowValue(req, "remarks")) %></td></tr>
                        <tr><th>Created On</th><td><%= safeText(rowValue(req, "created_at")) %></td></tr>
                        <tr><th>Updated On</th><td><%= safeText(rowValue(req, "updated_at")) %></td></tr>
                    </table>
                </div>

                <div class="detail-panel">
                    <div class="panel-title-row"><h2 class="panel-title">Requester Details</h2></div>

                    <table class="detail-table">
                        <tr><th>Employee</th><td><a href="view_employee.jsp?id=<%= safeText(employeeId) %>"><%= safeText(rowValue(req, "employee_name")) %></a></td></tr>
                        <tr><th>Employee Code</th><td><%= safeText(rowValue(req, "employee_code")) %></td></tr>
                        <tr><th>Designation</th><td><%= safeText(rowValue(req, "designation")) %></td></tr>
                        <tr><th>Email</th><td><%= safeText(rowValue(req, "employee_email")) %></td></tr>
                        <tr><th>Phone</th><td><%= safeText(rowValue(req, "employee_phone")) %></td></tr>
                        <tr><th>Department</th><td><%= safeText(rowValue(req, "department_name")) %></td></tr>
                        <tr><th>Location</th><td><%= safeText(rowValue(req, "location_name")) %></td></tr>
                    </table>
                </div>
            </section>

            <section class="detail-grid">
                <div class="detail-panel">
                    <div class="panel-title-row"><h2 class="panel-title">Other Requests by Same Holder</h2></div>
                    <div class="timeline-list">
                        <% for (Map<String, String> row : employeeRequestRows) { %>
                            <a class="timeline-row" href="view_request.jsp?id=<%= safeText(rowValue(row, "request_id")) %>">
                                <div class="timeline-icon"><i class="fa-regular fa-square-plus"></i></div>
                                <div class="timeline-text">
                                    <strong>Request #<%= safeText(rowValue(row, "request_id")) %> · <%= safeText(cleanLabel(rowValue(row, "request_status"))) %></strong>
                                    <span><%= safeText(cleanLabel(rowValue(row, "request_type"))) %> · <%= safeText(cleanLabel(rowValue(row, "priority"))) %> · <%= safeText(shortText(rowValue(row, "request_reason"), 70)) %></span>
                                </div>
                                <div class="timeline-date"><%= safeText(rowValue(row, "request_date")) %></div>
                            </a>
                        <% } %>
                    </div>
                </div>

                <div class="detail-panel">
                    <div class="panel-title-row"><h2 class="panel-title">Available Assets in Requested Category</h2></div>
                    <div class="timeline-list">
                        <% for (Map<String, String> row : categoryAssetRows) { %>
                            <a class="timeline-row" href="view_asset.jsp?id=<%= safeText(rowValue(row, "asset_id")) %>">
                                <div class="timeline-icon"><i class="fa-solid fa-cube"></i></div>
                                <div class="timeline-text">
                                    <strong><%= safeText(rowValue(row, "asset_code")) %> · <%= safeText(rowValue(row, "asset_name")) %></strong>
                                    <span><%= safeText(cleanLabel(rowValue(row, "asset_status"))) %> · <%= safeText(cleanLabel(rowValue(row, "service_status"))) %></span>
                                </div>
                                <div class="timeline-date">Asset</div>
                            </a>
                        <% } %>
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
