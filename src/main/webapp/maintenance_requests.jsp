<%@page contentType="text/html" pageEncoding="UTF-8"%>
<%
    // This page is a pure redirect shim - still linked from dashboard.jsp,
    // employee_dashboard.jsp and sidebar.jsp as a "Maintenance Requests" nav
    // entry, but there is no request-list view of its own. Everyone lands on
    // the actual maintenance-requests table via maintenance.jsp (admin/asset
    // manager side) or employee_maintenance_request.jsp (employee self-service
    // side). Previously this file had a full DAO query + table render below
    // an unconditional redirect - unreachable code (confirmed via the
    // RoleAccessUtil sweep earlier in this audit) that also had an unescaped
    // stored-XSS output pattern; both are removed here since neither could
    // ever actually run.
    String username = (String) session.getAttribute("username");
    String role = (String) session.getAttribute("role");

    response.setHeader("Cache-Control", "no-cache, no-store, must-revalidate");
    response.setHeader("Pragma", "no-cache");
    response.setDateHeader("Expires", 0);

    if (username == null || role == null) {
        response.sendRedirect("login.jsp");
        return;
    }

    if ("EMPLOYEE".equals(role)) {
        response.sendRedirect("employee_maintenance_request.jsp");
    } else {
        response.sendRedirect("maintenance.jsp");
    }
%>
