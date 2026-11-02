<%@page contentType="text/html" pageEncoding="UTF-8"%>
<%@page import="java.util.*"%>
<%@page import="com.mycompany.asset_management_system_ams.EmployeeDashboardDAO"%>
<%@page import="com.mycompany.asset_management_system_ams.MaintenanceRequestDAO"%>
<%@page import="com.mycompany.asset_management_system_ams.HtmlEscapeUtil"%>

<%
    String username = (String) session.getAttribute("username");
    String role = (String) session.getAttribute("role");
    Object userIdObj = session.getAttribute("user_id");

    response.setHeader("Cache-Control", "no-cache, no-store, must-revalidate");
    response.setHeader("Pragma", "no-cache");
    response.setDateHeader("Expires", 0);

    if (username == null || role == null || userIdObj == null) {
        response.sendRedirect("login.jsp");
        return;
    }

    int userId = Integer.parseInt(userIdObj.toString());
    
    Object employeeIdObj = session.getAttribute("employee_id");
    int employeeId = employeeIdObj != null ? Integer.parseInt(employeeIdObj.toString()) : 0;
    String employeeName = username;

    if (employeeId == 0) {
        response.sendRedirect("login.jsp?error=employee_not_found");
        return;
    }

    EmployeeDashboardDAO dao = new EmployeeDashboardDAO();
    Map<String, Integer> stats = dao.getDashboardStats(employeeId);
    List<Map<String, String>> allocations = dao.getRecentAllocations(employeeId, 10);
    List<Map<String, String>> requests = dao.getRecentRequests(employeeId, 10);
    
    MaintenanceRequestDAO maintDao = new MaintenanceRequestDAO();
    List<Map<String, String>> maintRequests = maintDao.getMaintenanceRequestsByEmployeeId(employeeId);
    if (maintRequests.size() > 5) {
        maintRequests = maintRequests.subList(0, 5);
    }

    String msg = request.getParameter("msg");
%>

<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>Employee Dashboard - IR-AMS</title>
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.0/css/all.min.css">
    <link rel="stylesheet" href="css/ir-glass.css?v=28000">
    <link rel="stylesheet" href="css/ams-pro.css?v=28000">
    <link rel="stylesheet" href="css/ir-ams-railway-ui.css?v=28000">
    <style>
        h1, h2, h3, h4, h5, h6, .hero-banner h1, .panel-header h2, .section-title, .module-title, .card-title {
            color: #0f172a !important;
        }
        .hero-banner {
            background: linear-gradient(135deg, #f0f7ff, #e0f2fe);
            padding: 24px 30px;
            border-radius: 12px;
            margin-bottom: 24px;
            border: 1px solid #bae6fd;
            display: flex;
            align-items: center;
            justify-content: space-between;
            box-shadow: 0 2px 4px rgba(0,0,0,0.02);
        }
        .hero-banner h1 {
            margin: 0;
            color: #0f172a;
            font-size: 24px;
            font-weight: 700;
        }
        .hero-banner p {
            margin: 8px 0 0 0;
            color: #475569;
            font-size: 15px;
        }
        .btn-new-req {
            background: #0284c7;
            color: #fff;
            padding: 10px 20px;
            border-radius: 8px;
            text-decoration: none;
            font-weight: 600;
            display: inline-flex;
            align-items: center;
            gap: 8px;
            box-shadow: 0 4px 6px rgba(2, 132, 199, 0.2);
            transition: 0.2s ease;
        }
        .btn-new-req:hover {
            background: #0369a1;
            transform: translateY(-2px);
            color: #fff;
        }
        .stats-grid {
            display: grid;
            grid-template-columns: repeat(4, 1fr);
            gap: 20px;
            margin-bottom: 30px;
        }
        .stat-card {
            background: #ffffff;
            border: 1px solid #e2e8f0;
            border-radius: 12px;
            padding: 24px;
            box-shadow: 0 4px 6px -1px rgba(0, 0, 0, 0.05);
            display: flex;
            align-items: center;
            gap: 16px;
        }
        .stat-card .icon {
            width: 50px;
            height: 50px;
            border-radius: 12px;
            display: flex;
            align-items: center;
            justify-content: center;
            font-size: 22px;
        }
        .stat-card.blue .icon { background: #e0f2fe; color: #0284c7; }
        .stat-card.green .icon { background: #dcfce7; color: #16a34a; }
        .stat-card.orange .icon { background: #ffedd5; color: #ea580c; }
        .stat-card.purple .icon { background: #f3e8ff; color: #9333ea; }

        .stat-details span { display: block; color: #64748b; font-size: 13px; font-weight: 600; text-transform: uppercase; letter-spacing: 0.5px; margin-bottom: 4px; }
        .stat-details strong { display: block; color: #0f172a; font-size: 26px; font-weight: 700; line-height: 1; }

        .content-grid {
            display: grid;
            grid-template-columns: 1fr 1fr;
            gap: 24px;
        }
        .panel {
            background: #ffffff;
            border: 1px solid #e2e8f0;
            border-radius: 12px;
            padding: 24px;
            box-shadow: 0 4px 6px -1px rgba(0, 0, 0, 0.05);
        }
        .panel-header {
            display: flex;
            justify-content: space-between;
            align-items: center;
            margin-bottom: 20px;
        }
        .panel-header h2 { margin: 0; font-size: 18px; color: #0f172a; font-weight: 700; }
        .panel-header a { font-size: 14px; color: #0284c7; text-decoration: none; font-weight: 600; }
        .panel-header a:hover { text-decoration: underline; color: #0369a1; }

        .list-group { display: flex; flex-direction: column; gap: 12px; }
        .list-item {
            display: flex;
            align-items: center;
            gap: 16px;
            padding: 16px;
            background: #f8fafc;
            border-radius: 8px;
            border: 1px solid #e2e8f0;
            text-decoration: none;
            color: inherit;
            transition: all 0.2s;
        }
        .list-item:hover {
            background: #ffffff;
            transform: translateY(-2px);
            box-shadow: 0 4px 12px rgba(0,0,0,0.05);
            border-color: #cbd5e1;
        }
        .item-icon { width: 40px; height: 40px; border-radius: 50%; background: #e0e7ff; color: #4338ca; display: flex; align-items: center; justify-content: center; font-size: 16px; flex-shrink: 0; }
        .item-content { flex: 1; }
        .item-content strong { display: block; color: #0f172a; font-size: 15px; font-weight: 600; margin-bottom: 2px; }
        .item-content span { display: block; color: #475569; font-size: 13px; }
        .item-badge { padding: 4px 10px; border-radius: 20px; font-size: 12px; font-weight: 600; }
        .badge-allocated { background: #dcfce7; color: #15803d; }
        .badge-returned { background: #f1f5f9; color: #475569; }
        .badge-pending { background: #fef9c3; color: #854d0e; }
        .badge-approved { background: #dcfce7; color: #15803d; }
        .badge-rejected { background: #fee2e2; color: #b91c1c; }
        .badge-fulfilled { background: #dcfce7; color: #15803d; }
        .badge-cancelled { background: #f1f5f9; color: #475569; }
        <%-- maintenance_requests.request_status badge classes are built dynamically
             ("badge-" + status.toLowerCase()) from MaintenanceRequestDAO's live values
             (PENDING, APPROVED, IN_PROGRESS, REJECTED, COMPLETED - confirmed against
             maintenance_requests.jsp's status-transition buttons, since this table
             isn't in the schema.sql dump). in_progress/completed had no matching class
             at all, so those two statuses rendered as plain unstyled badges. --%>
        .badge-in_progress { background: #dbeafe; color: #1d4ed8; }
        .badge-completed { background: #dcfce7; color: #15803d; }
        .empty-state { text-align: center; padding: 40px 20px; color: #64748b; font-weight: 500; }
        .empty-state i { font-size: 32px; color: #94a3b8; margin-bottom: 12px; display: block; }
    </style>
</head>
<body class="railway-ui">
<div class="app ams-shell">

    <jsp:include page="sidebar.jsp" />

    <main class="main railway-main">
        <jsp:include page="topbar.jsp" />

        <div class="main-scroll-content">
            
            <% if ("password_changed".equals(msg)) { %>
                <div class="page-success" style="margin-bottom: 20px; padding: 15px; background: #dcfce7; color: #166534; border-radius: 8px; font-weight: 500;">
                    <i class="fa-solid fa-circle-check"></i> Password changed successfully!
                </div>
            <% } %>

            <div class="hero-banner">
                <div>
                    <h1>Welcome back, <%= HtmlEscapeUtil.escape(employeeName) %>!</h1>
                    <p>Here's an overview of your allocated assets and active requests.</p>
                </div>
                <a href="new_employee_asset_request.jsp" class="btn-new-req">
                    <i class="fa-solid fa-plus"></i> Request New Asset
                </a>
            </div>

            <div class="stats-grid">
                <div class="stat-card blue">
                    <div class="icon"><i class="fa-solid fa-boxes-stacked"></i></div>
                    <div class="stat-details">
                        <span>Total Allocations</span>
                        <strong><%= stats.get("total_allocations") %></strong>
                    </div>
                </div>
                <div class="stat-card green">
                    <div class="icon"><i class="fa-solid fa-box-open"></i></div>
                    <div class="stat-details">
                        <span>Active Assets</span>
                        <strong><%= stats.get("active_allocations") %></strong>
                    </div>
                </div>
                <div class="stat-card purple">
                    <div class="icon"><i class="fa-solid fa-file-invoice"></i></div>
                    <div class="stat-details">
                        <span>Total Requests</span>
                        <strong><%= stats.get("total_requests") %></strong>
                    </div>
                </div>
                <div class="stat-card orange">
                    <div class="icon"><i class="fa-regular fa-hourglass-half"></i></div>
                    <div class="stat-details">
                        <span>Pending Requests</span>
                        <strong><%= stats.get("pending_requests") %></strong>
                    </div>
                </div>
            </div>

            <div class="content-grid">
                <div class="panel">
                    <div class="panel-header">
                        <h2>My Assets</h2>
                    </div>
                    <div class="list-group">
                        <% if (allocations.isEmpty()) { %>
                            <div class="empty-state">
                                <i class="fa-solid fa-box-archive"></i>
                                You have no allocated assets.
                            </div>
                        <% } else {
                            for (Map<String, String> row : allocations) { 
                                String status = row.get("allocation_status");
                                String badgeClass = "RETURNED".equalsIgnoreCase(status) ? "badge-returned" : "badge-allocated";
                        %>
                            <div class="list-item">
                                <div class="item-icon"><i class="fa-solid fa-laptop"></i></div>
                                <div class="item-content">
                                    <strong><%= HtmlEscapeUtil.escape(row.get("asset_name")) %> (<%= HtmlEscapeUtil.escape(row.get("asset_code")) %>)</strong>
                                    <span><%= HtmlEscapeUtil.escape(row.get("category_name")) %> &middot; <%= HtmlEscapeUtil.escape(row.get("allocation_date")) %></span>
                                </div>
                                <span class="item-badge <%= badgeClass %>"><%= HtmlEscapeUtil.escape(status) %></span>
                            </div>
                        <%  }
                        } %>
                    </div>
                </div>

                <div class="panel">
                    <div class="panel-header">
                        <h2>Recent Requests</h2>
                        <a href="view_request.jsp">View All</a>
                    </div>
                    <div class="list-group">
                        <% if (requests.isEmpty()) { %>
                            <div class="empty-state">
                                <i class="fa-regular fa-folder-open"></i>
                                You have no recent requests.
                            </div>
                        <% } else {
                            for (Map<String, String> row : requests) {
                                String status = row.get("request_status");
                                // asset_requests.request_status is an enum of 6 values (schema.sql):
                                // PENDING_DEPT_HEAD, PENDING, APPROVED, REJECTED, FULFILLED, CANCELLED.
                                // This used to only branch on PENDING/APPROVED and fall everything
                                // else - including FULFILLED, a successful outcome - into
                                // "badge-rejected" (red), showing the text "FULFILLED" styled as if
                                // it had been rejected. PENDING_DEPT_HEAD (added with the Department
                                // Head review stage) has the same fault if left unhandled.
                                String badgeClass = ("PENDING".equalsIgnoreCase(status) || "PENDING_DEPT_HEAD".equalsIgnoreCase(status)) ? "badge-pending"
                                                    : "APPROVED".equalsIgnoreCase(status) ? "badge-approved"
                                                    : "FULFILLED".equalsIgnoreCase(status) ? "badge-fulfilled"
                                                    : "CANCELLED".equalsIgnoreCase(status) ? "badge-cancelled"
                                                    : "badge-rejected";
                                String statusLabel = "PENDING_DEPT_HEAD".equalsIgnoreCase(status)
                                                    ? "Awaiting Dept Head"
                                                    : status;
                        %>
                            <a href="view_request.jsp?id=<%= HtmlEscapeUtil.escape(row.get("request_id")) %>" class="list-item">
                                <div class="item-icon" style="background: #fffbeb; color: #b45309;"><i class="fa-solid fa-file-contract"></i></div>
                                <div class="item-content">
                                    <strong><%= HtmlEscapeUtil.escape(row.get("request_type")) %> - <%= HtmlEscapeUtil.escape(row.get("category_name")) %></strong>
                                    <span><%= HtmlEscapeUtil.escape(row.get("request_date")) %></span>
                                </div>
                                <span class="item-badge <%= badgeClass %>"><%= HtmlEscapeUtil.escape(statusLabel) %></span>
                            </a>
                        <%  }
                        } %>
                    </div>
                </div>
            </div>

            <div class="panel" style="margin-top: 24px;">
                <div class="panel-header">
                    <h2>Recent Maintenance Requests</h2>
                    <a href="employee_maintenance_request.jsp">View All</a>
                </div>
                <div class="list-group">
                    <% if (maintRequests.isEmpty()) { %>
                        <div class="empty-state">
                            <i class="fa-solid fa-screwdriver-wrench"></i>
                            You have no recent maintenance requests.
                        </div>
                    <% } else {
                        for (Map<String, String> row : maintRequests) {
                            String status = row.get("request_status");
                            String badgeClass = "badge-" + HtmlEscapeUtil.escape(status != null ? status.toLowerCase() : "pending");
                    %>
                        <a href="employee_maintenance_request.jsp" class="list-item">
                            <div class="item-icon" style="background: #f1f5f9; color: #475569;"><i class="fa-solid fa-wrench"></i></div>
                            <div class="item-content">
                                <strong><%= HtmlEscapeUtil.escape(row.get("asset_name")) %> (<%= HtmlEscapeUtil.escape(row.get("asset_code")) %>)</strong>
                                <span><%= HtmlEscapeUtil.escape(row.get("request_date")) %> &middot; Priority: <%= HtmlEscapeUtil.escape(row.get("priority")) %></span>
                            </div>
                            <span class="item-badge <%= badgeClass %>"><%= HtmlEscapeUtil.escape(status) %></span>
                        </a>
                    <%  }
                    } %>
                </div>
            </div>

        </div>
    </main>
</div>

<script src="js/topbar-search.js?v=employee-maintenance-inner-1"></script>
<script src="js/user-dropdown.js?v=employee-maintenance-inner-1"></script>
<script src="js/sidebar-role.js?v=employee-maintenance-inner-1"></script>
<script src="js/ir-body-watermark.js?v=employee-maintenance-inner-1"></script>
<script src="js/dashboard-actions.js?v=employee-maintenance-inner-1"></script>
</body>
</html>
