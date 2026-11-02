<%@page contentType="text/html" pageEncoding="UTF-8"%>
<%@ page import="java.sql.*" %>
<%@ page import="com.mycompany.asset_management_system_ams.DBConnection" %>
<%
    String role = (String) session.getAttribute("role");
    if (role == null || !"SUPER_ADMIN".equals(role)) {
        response.sendRedirect("login.jsp");
        return;
    }
%>
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>Emergency Recovery | IR-AMS</title>
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.0/css/all.min.css">
    <link rel="stylesheet" href="css/ams-pro.css">
    <link rel="stylesheet" href="css/ir-ams-railway-ui.css">
</head>
<body class="railway-ui">
<div class="app">
    <jsp:include page="sidebar.jsp" />
    <main class="main railway-main">
        <jsp:include page="topbar.jsp" />
        <div class="main-scroll-content">
            <section class="add-employee-hero" style="margin-bottom: 20px; padding: 20px; background: white; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.05);">
                <h1 style="color:red;"><i class="fa-solid fa-triangle-exclamation"></i> Emergency Admin Recovery</h1>
                <p>Use this form to reset a user to Admin in case of lockout. This action requires your Super Admin password.</p>
            </section>
            
            <div style="background: white; padding: 20px; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.05);">
                <form action="emergency-admin-reset" method="POST">
                    <div style="margin-bottom: 15px;">
                        <label style="display: block; margin-bottom: 5px; font-weight: bold;">Target User ID</label>
                        <input type="number" name="targetUserId" required style="width:100%; padding: 8px; border: 1px solid #ccc; border-radius: 4px;">
                    </div>
                    
                    <div style="margin-bottom: 15px;">
                        <label style="display: block; margin-bottom: 5px; font-weight: bold;">Fallback Role for Outgoing Admin(s)</label>
                        <select name="outgoingAdminRole" required style="width:100%; padding: 8px; border: 1px solid #ccc; border-radius: 4px;">
                            <option value="employee">Employee</option>
                            <option value="asset_manager">Asset Manager</option>
                            <option value="dept_head">Department Head</option>
                            <option value="auditor">Auditor</option>
                        </select>
                    </div>
                    
                    <div style="margin-bottom: 15px;">
                        <label style="display: block; margin-bottom: 5px; font-weight: bold;">Super Admin Password</label>
                        <input type="password" name="password" required style="width:100%; padding: 8px; border: 1px solid #ccc; border-radius: 4px;">
                    </div>
                    
                    <button type="submit" style="background: #dc3545; color: white; padding: 10px 15px; border: none; border-radius: 4px; cursor: pointer;"><i class="fa-solid fa-bolt"></i> Execute Recovery</button>
                </form>
            </div>
        </div>
    </main>
</div>
</body>
</html>
