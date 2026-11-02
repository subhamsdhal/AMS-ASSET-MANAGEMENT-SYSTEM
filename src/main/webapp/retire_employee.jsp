<%@page contentType="text/html" pageEncoding="UTF-8"%>
<%@ page import="java.util.List" %>
<%@ page import="com.mycompany.asset_management_system_ams.Employee" %>
<%@ page import="com.mycompany.asset_management_system_ams.EmployeeDAO" %>
<%@ page import="com.mycompany.asset_management_system_ams.AssetAllocation" %>
<%@ page import="com.mycompany.asset_management_system_ams.AssetAllocationDAO" %>
<%@ page import="com.mycompany.asset_management_system_ams.HtmlEscapeUtil" %>

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

    boolean canManageEmployees = ("SUPER_ADMIN".equals(role) || "ADMIN".equals(role))
            || "DEPARTMENT_HEAD".equalsIgnoreCase(role);

    if (!canManageEmployees) {
        response.sendRedirect("employees.jsp?access=denied");
        return;
    }

    int employeeId = 0;
    try {
        employeeId = Integer.parseInt(request.getParameter("id"));
    } catch (Exception e) {
        response.sendRedirect("employees.jsp?error=invalid");
        return;
    }

    EmployeeDAO employeeDAO = new EmployeeDAO();

    if ("DEPARTMENT_HEAD".equalsIgnoreCase(role)) {
        int userIdForScope = 0;
        try {
            Object uid = session.getAttribute("user_id");
            userIdForScope = uid == null ? 0 : Integer.parseInt(String.valueOf(uid));
        } catch (Exception e) {
            userIdForScope = 0;
        }

        if (!employeeDAO.isEmployeeUnderDepartmentHead(employeeId, userIdForScope)) {
            response.sendRedirect("employees.jsp?access=denied");
            return;
        }
    }

    Employee employee = employeeDAO.getEmployeeById(employeeId);

    if (employee == null) {
        response.sendRedirect("employees.jsp?error=invalid");
        return;
    }

    if (!"ACTIVE".equalsIgnoreCase(employee.getStatus())) {
        response.sendRedirect("view_employee.jsp?id=" + employeeId + "&error=notretirable");
        return;
    }

    String error = request.getParameter("error");

    AssetAllocationDAO allocationDAO = new AssetAllocationDAO();
    List<AssetAllocation> allocations = allocationDAO.getAllocationsByEmployeeId(employeeId);
%>

<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>IR-AMS Retire Employee</title>

    <link rel="stylesheet"
          href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.0/css/all.min.css">

    <link rel="stylesheet" href="css/ir-glass.css?v=28000">
    <link rel="stylesheet" href="css/ams-pro.css?v=28000">
    <link rel="stylesheet" href="css/ir-ams-railway-ui.css?v=28000">
</head>

<body class="railway-ui">

<div class="app ams-shell">

    <jsp:include page="sidebar.jsp" />

    <main class="main railway-main">
        <jsp:include page="topbar.jsp" />

        <div class="main-scroll-content">

            <section class="add-employee-hero">
                <h1>Retire Employee</h1>

                <p>
                    Mark <strong><%= HtmlEscapeUtil.escape(employee.getEmployeeName()) %></strong>
                    (<%= HtmlEscapeUtil.escape(employee.getEmployeeCode()) %>) as retired.
                    Every asset currently allocated to this employee must be returned as part of this action -
                    a retired employee cannot keep custody of railway property.
                </p>
            </section>

            <section class="glass-panel">

                <h2>Retirement Details</h2>
                <br>

                <% if ("receivedbyrequired".equals(error)) { %>
                    <div class="alert-error">Please enter who is receiving the returned asset(s).</div>
                <% } else if ("allassetsrequired".equals(error)) { %>
                    <div class="alert-error">Every allocated asset below must have a return condition selected before retirement can be completed.</div>
                <% } else if ("returnfailed".equals(error)) { %>
                    <div class="alert-error">One of the assets could not be returned (it may already be returned elsewhere). Please review and try again.</div>
                <% } else if ("failed".equals(error)) { %>
                    <div class="alert-error">Retirement could not be completed. Please try again.</div>
                <% } else if ("server".equals(error)) { %>
                    <div class="alert-error">Server error occurred while processing the retirement.</div>
                <% } %>

                <form action="RetireEmployeeServlet" method="post">
                    <input type="hidden" name="employeeId" value="<%= employee.getEmployeeId() %>">

                    <div class="form-grid">
                        <div class="form-group form-group-full">
                            <label>Retirement Remarks</label>
                            <input type="text" name="remarks"
                                   placeholder="Example: Superannuation as per service record"
                                   maxlength="255">
                        </div>
                    </div>

                    <br>

                    <h2>Assets to be Returned</h2>

                    <%
                        boolean hasActiveAllocation = false;
                        for (AssetAllocation allocation : allocations) {
                            if (!"ALLOCATED".equalsIgnoreCase(allocation.getAllocationStatus())) {
                                continue;
                            }
                            hasActiveAllocation = true;
                    %>
                        <div class="form-group form-group-full" style="border:1px solid #e2e8f0; border-radius:10px; padding:14px; margin-bottom:12px;">
                            <strong><%= HtmlEscapeUtil.escape(allocation.getAssetCode()) %></strong>
                            &middot; <%= HtmlEscapeUtil.escape(allocation.getAssetName()) %>
                            <span class="table-subtext">(ALLOC-<%= allocation.getAllocationId() %>, allocated <%= HtmlEscapeUtil.escape(allocation.getAllocationDate(), "N/A") %>)</span>

                            <div style="margin-top:8px;">
                                Return Condition:
                                <select name="condition_<%= allocation.getAllocationId() %>" required>
                                    <option value="">Select Condition</option>
                                    <option value="GOOD">GOOD</option>
                                    <option value="DAMAGED">DAMAGED</option>
                                    <option value="NEEDS_REPAIR">NEEDS_REPAIR</option>
                                </select>
                            </div>
                        </div>
                    <%
                        }

                        if (!hasActiveAllocation) {
                    %>
                        <p class="table-subtext">This employee has no currently active (ALLOCATED) assets - retirement will not process any returns.</p>
                    <%
                        } else {
                    %>
                        <div class="form-group form-group-full">
                            <label>Received By</label>
                            <input type="text" name="receivedBy" required placeholder="Example: Store Officer">
                        </div>
                    <%
                        }
                    %>

                    <div class="form-actions">
                        <button type="submit" class="btn" onclick="return confirm('Retire this employee? This cannot be undone from this screen.');">
                            <i class="fa-solid fa-user-clock"></i> Confirm Retirement
                        </button>

                        <a href="view_employee.jsp?id=<%= employee.getEmployeeId() %>" class="btn secondary-btn">
                            <i class="fa-solid fa-arrow-left"></i> Cancel
                        </a>
                    </div>

                </form>

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
