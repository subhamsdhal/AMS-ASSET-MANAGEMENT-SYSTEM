<%@page contentType="text/html" pageEncoding="UTF-8"%>
<%@page import="com.mycompany.asset_management_system_ams.Department"%>
<%@page import="com.mycompany.asset_management_system_ams.DepartmentDAO"%>
<%@page import="java.sql.*"%>
<%@page import="java.util.*"%>
<%@page import="com.mycompany.asset_management_system_ams.DBConnection"%>
<%@page import="com.mycompany.asset_management_system_ams.RoleAssignmentDAO"%>
<%! 
    private String escapeHtml(String input) {
        if (input == null) return "";
        return input.replace("&", "&amp;")
                    .replace("<", "&lt;")
                    .replace(">", "&gt;")
                    .replace("\"", "&quot;")
                    .replace("'", "&#x27;");
    }
%>
<%@page import="com.mycompany.asset_management_system_ams.RoleAccessUtil"%>
<%
    String username = (String) session.getAttribute("username");
    String role = (String) session.getAttribute("role");

    if (username == null || role == null) {
        response.sendRedirect("login.jsp");
        return;
    }

    boolean canViewDepartments = RoleAccessUtil.hasAccess(role, "DEPARTMENT_MANAGEMENT", "VIEW");
    boolean canManageDepartments = RoleAccessUtil.hasAccess(role, "DEPARTMENT_MANAGEMENT", "EDIT");

    if (!canViewDepartments) {
        response.sendRedirect("dashboard.jsp?access=denied");
        return;
    }

    String idStr = request.getParameter("id");
    if (idStr == null || idStr.trim().isEmpty()) {
        response.sendRedirect("departments.jsp?error=invalid");
        return;
    }

    int deptId = 0;
    try {
        deptId = Integer.parseInt(idStr);
    } catch (NumberFormatException e) {
        response.sendRedirect("departments.jsp?error=invalid");
        return;
    }

    Department d = DepartmentDAO.getDepartmentById(deptId);
    if (d == null) {
        response.sendRedirect("departments.jsp?error=invalid");
        return;
    }

    int dynamicTotalEmployees = 0;
    List<Map<String, String>> empList = new ArrayList<>();
    
    com.mycompany.asset_management_system_ams.EmployeeDAO employeeDAO = new com.mycompany.asset_management_system_ams.EmployeeDAO();
    empList = employeeDAO.getEmployeesByDepartmentId(deptId);
    dynamicTotalEmployees = empList.size();
%>
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <title>View Department - Railway AMS</title>
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.2/css/all.min.css">
    <link rel="stylesheet" href="css/ir-glass.css?v=28000">
    <link rel="stylesheet" href="css/ams-pro.css?v=28000">
    <link rel="stylesheet" href="css/ir-ams-railway-ui.css?v=28000">
    <link rel="stylesheet" href="css/departments.css?v=28001">
</head>
<body class="railway-ui">
<div class="app ams-shell">

    <jsp:include page="sidebar.jsp" />

    <main class="main railway-main">
        <jsp:include page="topbar.jsp" />

        <div class="main-scroll-content">
            <div class="department-board">

            <div class="ams-breadcrumb">
                <a href="dashboard.jsp"><i class="fa-solid fa-house"></i> Home</a> 
                <span>/</span> 
                <a href="departments.jsp">Departments</a> 
                <span>/</span> 
                <strong>View Department</strong>
            </div>

            <section class="department-hero" style="min-height: 200px; height: 200px;">
                <div class="department-hero-copy">
                    <span class="department-eyebrow">
                        <i class="fa-solid fa-building"></i>
                        Departments Module
                    </span>
                    <h1>Department Details</h1>
                    <p>Information for <%= escapeHtml(d.getDepartmentName()) %></p>
                    <div class="department-hero-pills" style="margin-top: 20px;">
                        <a href="departments.jsp" class="department-hero-pill" style="text-decoration: none; cursor: pointer;">
                            <i class="fa-solid fa-arrow-left"></i> Back to List
                        </a>
                        <% if (canManageDepartments) { %>
                            <a href="edit_department.jsp?id=<%= d.getDepartmentId() %>" class="department-hero-pill" style="text-decoration: none; cursor: pointer; color: #9a5a00; border-color: #ffe0a8;">
                                <i class="fa-solid fa-pen-to-square"></i> Edit
                            </a>
                        <% } %>
                    </div>
                </div>
            </section>

            <section class="asset-card fade-in delay-1">
                <div class="asset-card-header">
                    <h2><i class="fa-solid fa-info-circle"></i> General Information</h2>
                </div>
                
                <div class="asset-card-body">
                    <div class="details-grid">
                        <div class="detail-item">
                            <span class="detail-label">Department Code</span>
                            <span class="detail-value"><strong><%= d.getDepartmentCode() != null ? escapeHtml(d.getDepartmentCode()) : "N/A" %></strong></span>
                        </div>
                        <div class="detail-item">
                            <span class="detail-label">Department Name</span>
                            <span class="detail-value"><%= escapeHtml(d.getDepartmentName()) %></span>
                        </div>
                        <div class="detail-item">
                            <span class="detail-label">Department Head</span>
                            <span class="detail-value">
                                <%
                                    List<String> dynHeads = RoleAssignmentDAO.getDepartmentHeadsByDepartmentId(d.getDepartmentId());
                                    if (!dynHeads.isEmpty()) {
                                        out.print(escapeHtml(String.join(", ", dynHeads)));
                                    } else if (d.getDepartmentHeadName() != null && !d.getDepartmentHeadName().trim().isEmpty()) {
                                        out.print(escapeHtml(d.getDepartmentHeadName()) + " (Static)");
                                    } else {
                                        out.print("<span class='text-muted'>Not Assigned</span>");
                                    }
                                %>
                            </span>
                        </div>
                        <div class="detail-item">
                            <span class="detail-label">Status</span>
                            <span class="detail-value">
                                <% if ("ACTIVE".equals(d.getStatus())) { %>
                                    <span class="status-pill status-active"><i class="fa-solid fa-check"></i> Active</span>
                                <% } else { %>
                                    <span class="status-pill status-disposed"><i class="fa-solid fa-xmark"></i> Inactive</span>
                                <% } %>
                            </span>
                        </div>
                        <div class="detail-item full-width">
                            <span class="detail-label">Description</span>
                            <span class="detail-value"><%= d.getDescription() != null && !d.getDescription().trim().isEmpty() ? escapeHtml(d.getDescription()) : "No description available." %></span>
                        </div>
                        <div class="detail-item">
                            <span class="detail-label">Total Assets</span>
                            <span class="detail-value count-badge"><i class="fa-solid fa-laptop"></i> <%= d.getAssetCount() %></span>
                        </div>
                        <div class="detail-item">
                            <span class="detail-label">Total Employees</span>
                            <span class="detail-value count-badge"><i class="fa-solid fa-users"></i> <%= dynamicTotalEmployees %></span>
                        </div>
                        <div class="detail-item">
                            <span class="detail-label">Created At</span>
                            <span class="detail-value"><%= d.getCreatedAt() != null ? d.getCreatedAt().toString() : "N/A" %></span>
                        </div>
                        <div class="detail-item">
                            <span class="detail-label">Last Updated</span>
                            <span class="detail-value"><%= d.getUpdatedAt() != null ? d.getUpdatedAt().toString() : "N/A" %></span>
                        </div>
                    </div>
                </div>
            </section>
            
            <section class="asset-card fade-in delay-2" style="margin-top: 20px;">
                <div class="asset-card-header">
                    <h2><i class="fa-solid fa-users"></i> Employees in this Department (<%= dynamicTotalEmployees %>)</h2>
                </div>
                
                <div class="asset-card-body">
                    <% if (empList.isEmpty()) { %>
                        <div class="empty-state" style="padding: 40px; text-align: center; color: #6c757d;">
                            <i class="fa-solid fa-users-slash" style="font-size: 48px; margin-bottom: 15px; color: #cbd5e1;"></i>
                            <p style="font-size: 16px; margin: 0;">No employees are currently assigned to this department.</p>
                        </div>
                    <% } else { %>
                        <div class="department-table-wrap" style="margin-top: 0; box-shadow: none; border: 1px solid #e2e8f0; border-radius: 8px;">
                            <table class="department-table">
                                <thead>
                                    <tr>
                                        <th style="padding-left: 15px;">EMP Code</th>
                                        <th>Name</th>
                                        <th>Designation</th>
                                        <th>Email</th>
                                        <th>Phone</th>
                                        <th style="text-align: center;">Status</th>
                                        <th style="text-align: center;">Action</th>
                                    </tr>
                                </thead>
                                <tbody>
                                    <% for (Map<String, String> emp : empList) { %>
                                    <tr>
                                        <td style="padding-left: 15px;"><strong><%= escapeHtml(emp.get("employee_code")) %></strong></td>
                                        <td><%= escapeHtml(emp.get("employee_name")) %></td>
                                        <td><%= escapeHtml(emp.get("designation")) %></td>
                                        <td><%= escapeHtml(emp.get("email")) %></td>
                                        <td><%= escapeHtml(emp.get("phone")) %></td>
                                        <td style="text-align: center;">
                                            <% if ("ACTIVE".equalsIgnoreCase(emp.get("status"))) { %>
                                                <span class="status-pill status-active"><i class="fa-solid fa-check"></i> Active</span>
                                            <% } else { %>
                                                <span class="status-pill status-disposed"><i class="fa-solid fa-xmark"></i> Inactive</span>
                                            <% } %>
                                        </td>
                                        <td style="text-align: center;">
                                            <a href="view_employee.jsp?id=<%= escapeHtml(emp.get("employee_id")) %>" class="department-action-btn" title="View"><i class="fa-solid fa-eye"></i> View</a>
                                        </td>
                                    </tr>
                                    <% } %>
                                </tbody>
                            </table>
                        </div>
                    <% } %>
                </div>
            </section>
            
            </div>
        </div>
    </main>
</div>

<script src="js/topbar-search.js?v=28000"></script>
<script src="js/user-dropdown.js?v=28000"></script>
<script src="js/sidebar-role.js?v=28000"></script>
<script src="js/ir-body-watermark.js?v=28000"></script>

</body>
</html>
