<%@page contentType="text/html" pageEncoding="UTF-8"%>
<%@page import="java.sql.*"%>
<%@page import="java.util.*"%>
<%@page import="com.mycompany.asset_management_system_ams.DBConnection"%>
<%@page import="com.mycompany.asset_management_system_ams.MaintenanceRequestDAO"%>
<%@page import="com.mycompany.asset_management_system_ams.HtmlEscapeUtil"%>

<%
    String username = (String) session.getAttribute("username");
    String role = (String) session.getAttribute("role");
    Object userIdObj = session.getAttribute("user_id");
    Object employeeIdObj = session.getAttribute("employee_id");

    response.setHeader("Cache-Control", "no-cache, no-store, must-revalidate");
    response.setHeader("Pragma", "no-cache");
    response.setDateHeader("Expires", 0);

    if (username == null || role == null || userIdObj == null || employeeIdObj == null || !"EMPLOYEE".equals(role)) {
        response.sendRedirect("login.jsp");
        return;
    }

    int employeeId = Integer.parseInt(employeeIdObj.toString());

    MaintenanceRequestDAO dao = new MaintenanceRequestDAO();
    List<Map<String, String>> allottedAssets = dao.getAllottedAssetsByEmployeeId(employeeId);
    List<Map<String, String>> requests = dao.getMaintenanceRequestsByEmployeeId(employeeId);
    
    String error = request.getParameter("error");
    String msg = request.getParameter("msg");
%>

<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>My Maintenance Requests - IR-AMS</title>
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
            margin-bottom: 24px;
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
        .badge-pending { background: #fef9c3; color: #854d0e; }
        .badge-approved { background: #dcfce7; color: #15803d; }
        .badge-in_progress { background: #dbeafe; color: #1d4ed8; }
        .badge-completed { background: #dcfce7; color: #15803d; }
        .badge-rejected { background: #fee2e2; color: #b91c1c; }
        .empty-state { text-align: center; padding: 40px 20px; color: #64748b; font-weight: 500; }
        .empty-state i { font-size: 32px; color: #94a3b8; margin-bottom: 12px; display: block; }
        
        .form-group { margin-bottom: 16px; }
        .form-group label { display: block; color: #475569; font-weight: 600; margin-bottom: 6px; font-size: 14px; }
        .form-group select, .form-group input, .form-group textarea {
            width: 100%;
            padding: 10px 14px;
            border: 1px solid #cbd5e1;
            border-radius: 8px;
            background: #f8fafc;
            color: #0f172a;
            font-size: 14px;
            transition: 0.2s ease;
            box-sizing: border-box;
        }
        .form-group select:focus, .form-group input:focus, .form-group textarea:focus {
            border-color: #0284c7;
            background: #ffffff;
            outline: none;
            box-shadow: 0 0 0 3px rgba(2, 132, 199, 0.1);
        }
        .btn-submit {
            background: #0284c7;
            color: #fff;
            padding: 10px 20px;
            border: none;
            border-radius: 8px;
            cursor: pointer;
            font-weight: 600;
            display: inline-flex;
            align-items: center;
            gap: 8px;
            box-shadow: 0 4px 6px rgba(2, 132, 199, 0.2);
            transition: 0.2s ease;
        }
        .btn-submit:hover {
            background: #0369a1;
            transform: translateY(-2px);
        }
        .alert-error { background: #fef2f2; color: #b91c1c; padding: 12px 16px; border: 1px solid #fecaca; border-radius: 8px; margin-bottom: 20px; font-size: 14px; font-weight: 600; }
        .alert-success { background: #f0fdf4; color: #15803d; padding: 12px 16px; border: 1px solid #bbf7d0; border-radius: 8px; margin-bottom: 20px; font-size: 14px; font-weight: 600; }
    </style>
</head>
<body class="railway-ui">
<div class="app ams-shell">
    <jsp:include page="sidebar.jsp" />
    <main class="main railway-main">
        <jsp:include page="topbar.jsp" />
        <div class="main-scroll-content">
            
            <% if ("invalid_employee".equals(error)) { %> <div class="alert-error">Authentication error. Employee record not found.</div> <% } %>
            <% if ("invalid_asset".equals(error)) { %> <div class="alert-error">Invalid asset selected.</div> <% } %>
            <% if ("empty_desc".equals(error)) { %> <div class="alert-error">Issue description cannot be empty.</div> <% } %>
            <% if ("not_allotted".equals(error)) { %> <div class="alert-error">You can raise maintenance request only for assets currently allotted to you.</div> <% } %>
            <% if ("submission_failed".equals(error)) { %> <div class="alert-error">Failed to submit maintenance request. Please try again.</div> <% } %>
            <% if ("request_submitted".equals(msg)) { %> <div class="alert-success">Maintenance request submitted successfully!</div> <% } %>

            <div class="hero-banner">
                <div>
                    <h1>My Maintenance Requests</h1>
                    <p>Request maintenance for assets currently allotted to you and track their status.</p>
                </div>
            </div>
            
            <div class="panel">
                <div class="panel-header">
                    <h2><i class="fa-solid fa-wrench"></i> Raise New Maintenance Request</h2>
                </div>
                <% if (allottedAssets.isEmpty()) { %>
                    <div class="empty-state">
                        <i class="fa-solid fa-box-open"></i>
                        <p>You have no active asset allocations. Maintenance can only be requested for allotted assets.</p>
                    </div>
                <% } else { %>
                    <form action="EmployeeMaintenanceRequestServlet" method="POST">
                        <div class="form-group">
                            <label>Select Allotted Asset *</label>
                            <select name="assetId" required>
                                <option value="">-- Select Asset --</option>
                                <% for (Map<String, String> asset : allottedAssets) { %>
                                    <option value="<%= HtmlEscapeUtil.escape(asset.get("asset_id")) %>"><%= HtmlEscapeUtil.escape(asset.get("asset_code")) %> - <%= HtmlEscapeUtil.escape(asset.get("asset_name")) %></option>
                                <% } %>
                            </select>
                        </div>
                        <div class="form-group">
                            <label>Priority</label>
                            <select name="priority">
                                <option value="LOW">Low</option>
                                <option value="MEDIUM" selected>Medium</option>
                                <option value="HIGH">High</option>
                                <option value="CRITICAL">Critical</option>
                            </select>
                        </div>
                        <div class="form-group">
                            <label>Issue Description *</label>
                            <textarea name="issueDescription" rows="4" required placeholder="Describe the issue with the asset in detail..."></textarea>
                        </div>
                        <button type="submit" class="btn-submit"><i class="fa-solid fa-paper-plane"></i> Submit Request</button>
                    </form>
                <% } %>
            </div>

            <div class="panel">
                <div class="panel-header">
                    <h2><i class="fa-solid fa-clock-rotate-left"></i> Maintenance Request History</h2>
                </div>
                
                <% if (requests.isEmpty()) { %>
                    <div class="empty-state">
                        <i class="fa-solid fa-folder-open"></i>
                        <p>No past maintenance requests found.</p>
                    </div>
                <% } else { %>
                    <div class="list-group">
                        <% for (Map<String, String> req : requests) { 
                            String status = req.get("request_status");
                            String badgeClass = "badge-" + (status != null ? status.toLowerCase() : "pending");
                        %>
                        <div class="list-item">
                            <div class="item-icon"><i class="fa-solid fa-screwdriver-wrench"></i></div>
                            <div class="item-content">
                                <strong><%= HtmlEscapeUtil.escape(req.get("asset_code")) %> - <%= HtmlEscapeUtil.escape(req.get("asset_name")) %></strong>
                                <span>Requested on <%= HtmlEscapeUtil.escape(req.get("request_date")) %> | Priority: <%= HtmlEscapeUtil.escape(req.get("priority")) %></span>
                                <% if (req.get("remarks") != null && !req.get("remarks").isEmpty()) { %>
                                    <span style="margin-top:4px; color:#475569; font-style:italic;"><i class="fa-solid fa-comment-dots"></i> <%= HtmlEscapeUtil.escape(req.get("remarks")) %></span>
                                <% } %>
                            </div>
                            <div class="item-badge <%= badgeClass %>"><%= HtmlEscapeUtil.escape(status) %></div>
                        </div>
                        <% } %>
                    </div>
                <% } %>
            </div>

        </div>
    </main>
</div>
</body>
</html>
