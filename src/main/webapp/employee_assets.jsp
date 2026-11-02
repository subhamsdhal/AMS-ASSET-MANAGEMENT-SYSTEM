<%@page contentType="text/html" pageEncoding="UTF-8"%>
<%@page import="java.sql.*"%>
<%@page import="java.util.*"%>
<%@page import="com.mycompany.asset_management_system_ams.DBConnection"%>
<%@page import="com.mycompany.asset_management_system_ams.EmployeeDashboardDAO"%>
<%@page import="com.mycompany.asset_management_system_ams.AssetTransferDAO"%>
<%@page import="com.mycompany.asset_management_system_ams.EmployeeDAO"%>
<%@page import="com.mycompany.asset_management_system_ams.Employee"%>
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
    List<Map<String, String>> allocations = dao.getRecentAllocations(employeeId, 1000);

    AssetTransferDAO transferDao = new AssetTransferDAO();
    List<Map<String, String>> myTransfers = transferDao.getTransferRequestsForEmployee(employeeId);

    // Target-employee picker for "Request Transfer" - every other active
    // employee. Filtered client-side is not an option here (the list would
    // leak inactive/other-department employees to view-source); filtered
    // server-side instead.
    List<Employee> transferTargets = new ArrayList<>();
    for (Employee e : new EmployeeDAO().getAllEmployees()) {
        if (e.getEmployeeId() != employeeId && "ACTIVE".equalsIgnoreCase(e.getStatus())) {
            transferTargets.add(e);
        }
    }

    String success = request.getParameter("success");
    String error = request.getParameter("error");
%>

<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>My Assets - IR-AMS</title>
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
        .badge-allocated { background: #dcfce7; color: #15803d; }
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
                    <h1>My Assets</h1>
                    <p>All assets currently or previously allocated to you.</p>
                </div>
                <a href="employee_transfer_preference.jsp" class="btn btn-primary">
                    <i class="fa-solid fa-right-left"></i> Transfer Asset Preference
                </a>
            </div>

            <% if ("transferSubmitted".equals(success)) { %>
                <div class="page-success" style="margin-bottom:16px;">
                    <i class="fa-solid fa-circle-check"></i>
                    Transfer request submitted. It is now awaiting review by an Asset Manager, Admin, or Super Admin.
                </div>
            <% } else if ("accessDenied".equals(error)) { %>
                <div class="page-error" style="margin-bottom:16px;">
                    <i class="fa-solid fa-triangle-exclamation"></i> That allocation does not belong to you.
                </div>
            <% } else if ("invalidRequest".equals(error)) { %>
                <div class="page-error" style="margin-bottom:16px;">
                    <i class="fa-solid fa-triangle-exclamation"></i> Please select an asset and a colleague to transfer to.
                </div>
            <% } else if ("transferFailed".equals(error)) { %>
                <div class="page-error" style="margin-bottom:16px;">
                    <i class="fa-solid fa-triangle-exclamation"></i> Could not submit the transfer request - the asset may no longer be allocated to you, or a transfer for it is already pending.
                </div>
            <% } %>

            <div class="panel">
                <div class="panel-header">
                    <h2>Asset Allocations</h2>
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
                        <div class="list-item" style="text-decoration:none;">
                            <div class="item-icon"><i class="fa-solid fa-laptop"></i></div>
                            <div class="item-content">
                                <strong><%= HtmlEscapeUtil.escape(row.get("asset_name")) %> (<%= HtmlEscapeUtil.escape(row.get("asset_code")) %>)</strong>
                                <span><%= HtmlEscapeUtil.escape(row.get("category_name")) %> &middot; Allocated on: <%= HtmlEscapeUtil.escape(row.get("allocation_date")) %></span>
                            </div>
                            <span class="item-badge <%= badgeClass %>"><%= HtmlEscapeUtil.escape(status) %></span>
                            <% if ("ALLOCATED".equalsIgnoreCase(status) && !transferTargets.isEmpty()) { %>
                                <button type="button" class="btn btn-secondary" style="margin-left:10px; white-space:nowrap;"
                                        onclick="document.getElementById('transferForm-<%= row.get("allocation_id") %>').style.display='flex';">
                                    <i class="fa-solid fa-right-left"></i> Request Transfer
                                </button>
                            <% } %>
                        </div>
                        <% if ("ALLOCATED".equalsIgnoreCase(status) && !transferTargets.isEmpty()) { %>
                            <form id="transferForm-<%= row.get("allocation_id") %>" method="post" action="SubmitAssetTransferServlet"
                                  style="display:none; gap:8px; align-items:center; padding:10px 16px; background:#f8fafc; border:1px solid #e2e8f0; border-top:none; border-radius:0 0 8px 8px; margin-top:-12px; margin-bottom:12px;"
                                  onsubmit="return confirm('Submit a transfer request for this asset?');">
                                <input type="hidden" name="allocationId" value="<%= row.get("allocation_id") %>">
                                <span style="font-size:13px; color:#475569;">Transfer to:</span>
                                <select name="toEmployeeId" required style="font-size:13px; padding:4px;">
                                    <% for (Employee target : transferTargets) { %>
                                        <option value="<%= target.getEmployeeId() %>">
                                            <%= HtmlEscapeUtil.escape(target.getEmployeeName()) %> (<%= HtmlEscapeUtil.escape(target.getEmployeeCode()) %>)
                                        </option>
                                    <% } %>
                                </select>
                                <input type="text" name="transferReason" placeholder="Reason" required style="font-size:13px; padding:4px; flex:1; min-width:120px;">
                                <button type="submit" class="btn btn-primary" style="font-size:13px; padding:4px 12px;">Submit</button>
                            </form>
                        <% }
                    }
                    } %>
                </div>
            </div>

            <div class="panel" style="margin-top:24px;">
                <div class="panel-header">
                    <h2>My Transfer Requests</h2>
                </div>
                <div class="list-group">
                    <% if (myTransfers.isEmpty()) { %>
                        <div class="empty-state">
                            <i class="fa-solid fa-right-left"></i>
                            You have no transfer requests.
                        </div>
                    <% } else {
                        for (Map<String, String> t : myTransfers) {
                            String st = t.get("request_status");
                            String badgeClass = "PENDING".equals(st) ? "badge-allocated"
                                    : "COMPLETED".equals(st) ? "badge-allocated" : "badge-returned";
                            boolean outgoing = "OUTGOING".equals(t.get("direction"));
                    %>
                        <div class="list-item">
                            <div class="item-icon"><i class="fa-solid <%= outgoing ? "fa-arrow-up" : "fa-arrow-down" %>"></i></div>
                            <div class="item-content">
                                <strong><%= HtmlEscapeUtil.escape(t.get("asset_code")) %> - <%= HtmlEscapeUtil.escape(t.get("asset_name")) %></strong>
                                <span>
                                    <%= outgoing ? "To " + HtmlEscapeUtil.escape(t.get("to_name")) : "From " + HtmlEscapeUtil.escape(t.get("from_name")) %>
                                    &middot; Requested on: <%= HtmlEscapeUtil.escape(t.get("requested_date")) %>
                                </span>
                            </div>
                            <span class="item-badge <%= badgeClass %>"><%= HtmlEscapeUtil.escape(st) %></span>
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
