<%@page contentType="text/html" pageEncoding="UTF-8"%>
<%@page import="java.sql.*"%>
<%@page import="java.util.*"%>
<%@page import="com.mycompany.asset_management_system_ams.DBConnection"%>
<%@page import="com.mycompany.asset_management_system_ams.EmployeeDashboardDAO"%>
<%@page import="com.mycompany.asset_management_system_ams.HtmlEscapeUtil"%>

<%
    String username = (String) session.getAttribute("username");
    String role = (String) session.getAttribute("role");
    Object userIdObj = session.getAttribute("user_id");
    Object employeeIdObj = session.getAttribute("employee_id");

    response.setHeader("Cache-Control", "no-cache, no-store, must-revalidate");
    response.setHeader("Pragma", "no-cache");
    response.setDateHeader("Expires", 0);

    if (username == null || role == null || userIdObj == null || employeeIdObj == null) {
        response.sendRedirect("login.jsp");
        return;
    }

    int employeeId = Integer.parseInt(employeeIdObj.toString());

    EmployeeDashboardDAO dao = new EmployeeDashboardDAO();
    List<Map<String, String>> returns = dao.getRecentReturns(employeeId, 1000);
%>

<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>My Returns - IR-AMS</title>
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
        .hero-banner h1 { margin: 0; color: #0f172a; font-size: 24px; font-weight: 700; }
        .hero-banner p { margin: 8px 0 0 0; color: #475569; font-size: 15px; }
        
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
        .badge-returned { background: #f1f5f9; color: #475569; }
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
            <div class="hero-banner">
                <div>
                    <h1>My Returns</h1>
                    <p>Assets you have returned.</p>
                </div>
            </div>

            <div class="panel">
                <div class="panel-header">
                    <h2>Asset Returns</h2>
                </div>
                <div class="list-group">
                    <% if (returns.isEmpty()) { %>
                        <div class="empty-state">
                            <i class="fa-solid fa-rotate-left"></i>
                            You have no returned assets.
                        </div>
                    <% } else {
                        for (Map<String, String> row : returns) { 
                    %>
                        <div class="list-item">
                            <div class="item-icon"><i class="fa-solid fa-rotate-left"></i></div>
                            <div class="item-content">
                                <strong><%= HtmlEscapeUtil.escape(row.get("asset_name")) %> (<%= HtmlEscapeUtil.escape(row.get("asset_code")) %>)</strong>
                                <span>
                                    <%= HtmlEscapeUtil.escape(row.get("category_name")) %> &middot;
                                    Allocated: <%= HtmlEscapeUtil.escape(row.get("allocation_date"), "N/A") %> &middot;
                                    Returned on: <%= HtmlEscapeUtil.escape(row.get("return_date"), "N/A") %> &middot;
                                    Condition: <%= HtmlEscapeUtil.escape(row.get("return_condition"), "N/A") %>
                                </span>
                                <span style="display: block; margin-top: 4px; color: #475569; font-size: 12px;">
                                    Received By: <%= HtmlEscapeUtil.escape(row.get("received_by"), "N/A") %>
                                    <% if(row.get("remarks") != null && !row.get("remarks").trim().isEmpty()) { %>
                                        &middot; Remarks: <%= HtmlEscapeUtil.escape(row.get("remarks")) %>
                                    <% } %>
                                </span>
                            </div>
                            <span class="item-badge badge-returned">RETURNED</span>
                        </div>
                    <%  }
                    } %>
                </div>
            </div>
        </div>
    </main>
</div>
<script src="js/topbar-search.js?v=1"></script>
<script src="js/user-dropdown.js?v=1"></script>
<script src="js/sidebar-role.js?v=1"></script>
<script src="js/ir-body-watermark.js?v=1"></script>
<script src="js/dashboard-actions.js?v=1"></script>
</body>
</html>
