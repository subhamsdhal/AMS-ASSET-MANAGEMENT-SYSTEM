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
    List<Map<String, String>> requests = dao.getRecentRequests(employeeId, 1000);
    
    String msg = request.getParameter("success");
%>

<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>My Asset Requests - IR-AMS</title>
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
        .badge-pending { background: #fef9c3; color: #854d0e; }
        .badge-approved { background: #dcfce7; color: #15803d; }
        .badge-rejected { background: #fee2e2; color: #b91c1c; }
        .empty-state { text-align: center; padding: 40px 20px; color: #64748b; font-weight: 500; }
        .empty-state i { font-size: 32px; color: #94a3b8; margin-bottom: 12px; display: block; }
        .form-group { margin-bottom: 16px; }
        .form-group label { display: block; color: #475569; font-weight: 600; margin-bottom: 6px; font-size: 14px; }
        .form-group select, .form-group input {
            width: 100%;
            padding: 10px 14px;
            border: 1px solid #cbd5e1;
            border-radius: 8px;
            background: #f8fafc;
            color: #0f172a;
            font-size: 14px;
            transition: 0.2s ease;
        }
        .form-group select:focus, .form-group input:focus {
            border-color: #0284c7;
            background: #ffffff;
            outline: none;
            box-shadow: 0 0 0 3px rgba(2, 132, 199, 0.1);
        }
        .alert-error {
            background: #fef2f2;
            color: #b91c1c;
            padding: 12px 16px;
            border: 1px solid #fecaca;
            border-radius: 8px;
            margin-bottom: 20px;
            font-size: 14px;
            font-weight: 600;
        }
    </style>
</head>
<body class="railway-ui">
<div class="app ams-shell">
    <jsp:include page="sidebar.jsp" />
    <main class="main railway-main">
        <jsp:include page="topbar.jsp" />
        <div class="main-scroll-content">
        
            <% if ("1".equals(msg)) { %>
                <div class="page-success" style="margin-bottom: 20px; padding: 15px; background: #dcfce7; color: #166534; border-radius: 8px; font-weight: 500;">
                    <i class="fa-solid fa-circle-check"></i> Asset request submitted successfully!
                </div>
            <% } %>

            <div class="hero-banner">
                <div>
                    <h1>My Asset Requests</h1>
                    <p>Track the status of your requested assets.</p>
                </div>
                <a href="employee_requests.jsp?new=1" class="btn-new-req">
                    <i class="fa-solid fa-plus"></i> Request New Asset
                </a>
            </div>

            <% if ("1".equals(request.getParameter("new"))) { %>
                <div class="panel" style="margin-bottom: 24px;">
                    <div class="panel-header">
                        <h2>Request Form</h2>
                    </div>

                    <% String error = request.getParameter("error"); %>
                    <% if ("failed".equals(error)) { %>
                        <div class="alert-error">Request could not be added. Please check the details.</div>
                    <% } else if ("server".equals(error)) { %>
                        <div class="alert-error">Server error occurred. Please try again.</div>
                    <% } else if ("invaliddate".equals(error)) { %>
                        <div class="alert-error">Request date must be today or a previous date.</div>
                    <% } else if ("invalidselection".equals(error)) { %>
                        <div class="alert-error">Please select a valid category.</div>
                    <% } else if ("access".equals(error)) { %>
                        <div class="alert-error">Your login is not linked to an active employee record.</div>
                    <% } %>

                    <form action="AddAssetRequestServlet" method="post">
                        
                        <div class="form-group">
                            <label>Asset Category</label>
                            <select name="categoryId" required>
                                <option value="">Select Category</option>
                                <%
                                    try (Connection con = DBConnection.getConnection();
                                         PreparedStatement ps = con.prepareStatement(
                                             "SELECT category_id, category_name FROM asset_categories WHERE is_active = 'YES' ORDER BY category_name");
                                         ResultSet rs = ps.executeQuery()) {
                                         
                                         while (rs.next()) {
                                %>
                                            <option value="<%= rs.getInt("category_id") %>">
                                                <%= HtmlEscapeUtil.escape(rs.getString("category_name")) %>
                                            </option>
                                <%       }
                                    } catch (Exception e) {
                                        e.printStackTrace();
                                    }
                                %>
                            </select>
                        </div>

                        <div class="form-group">
                            <label>Request Date</label>
                            <input type="date" name="requestDate" id="requestDate" value="<%= new java.sql.Date(System.currentTimeMillis()) %>" required>
                        </div>

                        <div class="form-group">
                            <label>Reason / Remarks</label>
                            <input type="text" name="remarks" placeholder="Example: Laptop required for field inspection" required>
                        </div>

                        <div style="display: flex; gap: 10px; margin-top: 20px;">
                            <button type="submit" class="btn-new-req" style="border: none; cursor: pointer; padding: 12px 24px; font-size: 15px;">
                                <i class="fa-solid fa-paper-plane"></i> Submit Request
                            </button>
                            <a href="employee_requests.jsp" style="display: inline-flex; align-items: center; justify-content: center; padding: 12px 24px; border-radius: 8px; text-decoration: none; font-weight: 600; background: #f1f5f9; color: #475569; border: 1px solid #cbd5e1; font-size: 15px; transition: 0.2s ease;">Cancel</a>
                        </div>
                    </form>
                </div>
            <% } %>

            <div class="panel">
                <div class="panel-header">
                    <h2>Asset Requests</h2>
                </div>
                <div class="list-group">
                    <% if (requests.isEmpty()) { %>
                        <div class="empty-state">
                            <i class="fa-regular fa-folder-open"></i>
                            You have no requests.
                        </div>
                    <% } else {
                        for (Map<String, String> row : requests) { 
                            String status = row.get("request_status");
                            String badgeClass = ("PENDING".equalsIgnoreCase(status) || "PENDING_DEPT_HEAD".equalsIgnoreCase(status)) ? "badge-pending"
                                                : "APPROVED".equalsIgnoreCase(status) ? "badge-approved"
                                                : "badge-rejected";
                            String statusLabel = "PENDING_DEPT_HEAD".equalsIgnoreCase(status)
                                                ? "Awaiting Department Head Review"
                                                : status;
                    %>
                        <a href="view_request.jsp?id=<%= HtmlEscapeUtil.escape(row.get("request_id")) %>" class="list-item">
                            <div class="item-icon" style="background: #fffbeb; color: #b45309;"><i class="fa-solid fa-file-contract"></i></div>
                            <div class="item-content">
                                <strong><%= HtmlEscapeUtil.escape(row.get("request_type")) %> - <%= HtmlEscapeUtil.escape(row.get("category_name")) %></strong>
                                <span>Requested on: <%= HtmlEscapeUtil.escape(row.get("request_date")) %></span>
                            </div>
                            <span class="item-badge <%= badgeClass %>"><%= HtmlEscapeUtil.escape(statusLabel) %></span>
                        </a>
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
