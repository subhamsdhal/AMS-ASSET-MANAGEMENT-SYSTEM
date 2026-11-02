<%@page contentType="text/html" pageEncoding="UTF-8"%>
<%@page import="com.mycompany.asset_management_system_ams.Department"%>
<%@page import="com.mycompany.asset_management_system_ams.DepartmentDAO"%>
<%@page import="java.util.List"%>
<%@page import="com.mycompany.asset_management_system_ams.RoleAccessUtil"%>
<%@page import="com.mycompany.asset_management_system_ams.HtmlEscapeUtil"%>
<%
    String username = (String) session.getAttribute("username");
    String role = (String) session.getAttribute("role");

    if (username == null || role == null) {
        response.sendRedirect("login.jsp");
        return;
    }

    boolean canManageDepartments = RoleAccessUtil.hasAccess(role, "DEPARTMENT_MANAGEMENT", "EDIT");

    if (!canManageDepartments) {
        response.sendRedirect("departments.jsp?access=denied");
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

    List<DepartmentDAO.UserSnippet> users = DepartmentDAO.getPotentialHeadUsers();

    String error = request.getParameter("error");
%>
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <title>Edit Department - Railway AMS</title>
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
                <strong>Edit Department</strong>
            </div>

            <% if ("duplicatecode".equals(error)) { %>
                <div class="alert alert-danger"><i class="fa-solid fa-circle-exclamation"></i> Department code already exists.</div>
            <% } else if ("duplicatename".equals(error)) { %>
                <div class="alert alert-danger"><i class="fa-solid fa-circle-exclamation"></i> Department name already exists.</div>
            <% } else if ("invalid".equals(error)) { %>
                <div class="alert alert-danger"><i class="fa-solid fa-circle-exclamation"></i> Please fill all required fields correctly.</div>
            <% } else if ("server".equals(error)) { %>
                <div class="alert alert-danger"><i class="fa-solid fa-triangle-exclamation"></i> Database error occurred.</div>
            <% } %>

            <section class="department-hero" style="min-height: 200px; height: 200px;">
                <div class="department-hero-copy">
                    <span class="department-eyebrow">
                        <i class="fa-solid fa-pen-to-square"></i>
                        Departments Module
                    </span>
                    <h1>Edit Department</h1>
                    <p>Update department details for <%= HtmlEscapeUtil.escape(d.getDepartmentCode() != null ? d.getDepartmentCode() : d.getDepartmentName()) %>.</p>
                </div>
            </section>

            <section class="asset-card form-card fade-in delay-1">
                <div class="asset-card-header">
                    <h2><i class="fa-solid fa-building"></i> Department Details</h2>
                </div>
                
                <div class="asset-card-body">
                    <form action="UpdateDepartmentServlet" method="POST" class="ams-form">
                        <input type="hidden" name="department_id" value="<%= d.getDepartmentId() %>">
                        
                        <div class="form-group">
                            <label for="department_code">Department Code <span class="required">*</span></label>
                            <div class="input-icon">
                                <i class="fa-solid fa-hashtag"></i>
                                <input type="text" id="department_code" name="department_code" required value="<%= HtmlEscapeUtil.escape(d.getDepartmentCode()) %>" maxlength="30">
                            </div>
                        </div>

                        <div class="form-group">
                            <label for="department_name">Department Name <span class="required">*</span></label>
                            <div class="input-icon">
                                <i class="fa-solid fa-font"></i>
                                <input type="text" id="department_name" name="department_name" required value="<%= HtmlEscapeUtil.escape(d.getDepartmentName()) %>" maxlength="100">
                            </div>
                        </div>
                        
                        <div class="form-group">
                            <label for="department_head_user_id">Department Head</label>
                            <div class="input-icon">
                                <i class="fa-solid fa-user-tie"></i>
                                <select id="department_head_user_id" name="department_head_user_id">
                                    <option value="">-- No Department Head --</option>
                                    <% for (DepartmentDAO.UserSnippet u : users) { %>
                                        <option value="<%= u.userId %>" <%= (d.getDepartmentHeadUserId() == u.userId) ? "selected" : "" %>><%= HtmlEscapeUtil.escape(u.username) %> (<%= HtmlEscapeUtil.escape(u.roleName) %>)</option>
                                    <% } %>
                                </select>
                            </div>
                        </div>

                        <div class="form-group">
                            <label for="status">Status <span class="required">*</span></label>
                            <div class="input-icon">
                                <i class="fa-solid fa-toggle-on"></i>
                                <select id="status" name="status" required>
                                    <option value="ACTIVE" <%= "ACTIVE".equals(d.getStatus()) ? "selected" : "" %>>ACTIVE</option>
                                    <option value="INACTIVE" <%= "INACTIVE".equals(d.getStatus()) ? "selected" : "" %>>INACTIVE</option>
                                </select>
                            </div>
                        </div>

                        <div class="form-group full-width">
                            <label for="description">Description</label>
                            <div class="input-icon textarea-icon">
                                <i class="fa-solid fa-align-left"></i>
                                <textarea id="description" name="description" rows="3" maxlength="255"><%= HtmlEscapeUtil.escape(d.getDescription()) %></textarea>
                            </div>
                        </div>

                        <div class="form-actions">
                            <button type="submit" class="btn btn-primary"><i class="fa-solid fa-check"></i> Update Department</button>
                            <a href="departments.jsp" class="btn btn-secondary"><i class="fa-solid fa-xmark"></i> Cancel</a>
                        </div>
                    </form>
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
