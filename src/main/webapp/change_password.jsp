<%@page contentType="text/html" pageEncoding="UTF-8"%>
<%@page import="java.sql.*"%>
<%@page import="com.mycompany.asset_management_system_ams.DBConnection"%>
<%@page import="com.mycompany.asset_management_system_ams.PasswordUtil"%>
<%@page import="com.mycompany.asset_management_system_ams.HtmlEscapeUtil"%>

<%
    String username = (String) session.getAttribute("username");
    String role = (String) session.getAttribute("role");

    Object userIdObj = session.getAttribute("user_id");
    int userId = 0;

    if (userIdObj != null) {
        userId = Integer.parseInt(userIdObj.toString());
    }

    response.setHeader("Cache-Control", "no-cache, no-store, must-revalidate");
    response.setHeader("Pragma", "no-cache");
    response.setDateHeader("Expires", 0);

    if (username == null || role == null || userId == 0) {
        response.sendRedirect("login.jsp");
        return;
    }

    String success = request.getParameter("msg") != null ? request.getParameter("msg") : "";
    String error = request.getParameter("error") != null ? request.getParameter("error") : "";
%>

<!DOCTYPE html>
<html>
<head>
    <title>Change Password | IR-AMS</title>

    <link rel="stylesheet"
          href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.0/css/all.min.css">

    <link rel="stylesheet" href="css/ir-glass.css?v=5000">

    <link rel="stylesheet" href="css/ams-pro.css?v=28001">
    <link rel="stylesheet" href="css/ir-ams-railway-ui.css?v=28001">
    <link rel="stylesheet" href="css/change_password.css?v=28001">
    <style>
        h1, h2, h3, h4, h5, h6, .hero-banner h1, .panel-header h2, .section-title, .module-title, .card-title {
            color: #0f172a !important;
        }
    </style>
</head>

<body class="railway-ui">

<div class="app ams-shell">

    <jsp:include page="sidebar.jsp" />

    <main class="main railway-main">

        <jsp:include page="topbar.jsp" />

        <div class="main-scroll-content">

            <section class="settings-hero">
                <h1>Change Password</h1>
                <p>
                    Update your account password securely. This action will be recorded
                    in audit logs for administrative security tracking.
                </p>

                <br>

                <div class="hero-pills">
                    <div class="hero-pill"><i class="fa-solid fa-lock"></i> Account Security</div>
                    <div class="hero-pill"><i class="fa-solid fa-user-shield"></i> User Access</div>
                    <div class="hero-pill"><i class="fa-solid fa-shield-halved"></i> Audit Tracked</div>
                </div>
            </section>

            <%-- Fault: msg/error are printed directly from the request's own query
                 string with no escaping. The servlet only ever redirects here with
                 its own fixed, safe strings - but the page itself has no way to
                 tell that request apart from someone crafting
                 change_password.jsp?error=<script>...</script> directly and
                 getting a logged-in user to click it (reflected XSS, running in
                 the AMS session's own origin). Escaped like every other
                 request-controlled value displayed elsewhere in this app. --%>
            <% if (!success.isEmpty()) { %>
                <div class="page-success">
                    <i class="fa-solid fa-circle-check"></i>
                    <%= HtmlEscapeUtil.escape(success) %>
                </div>
            <% } %>

            <% if (!error.isEmpty()) { %>
                <div class="page-error">
                    <i class="fa-solid fa-triangle-exclamation"></i>
                    <%= HtmlEscapeUtil.escape(error) %>
                </div>
            <% } %>

            <section class="glass-panel password-card">

                <h2><i class="fa-solid fa-key"></i> Update Password</h2>

                <form method="post" action="${pageContext.request.contextPath}/ChangePasswordServlet">

                    <div class="form-grid">

                        <div class="form-group">
                            <label>Current Password</label>

                            <div class="password-input-wrap">
                                <input type="password"
                                       id="currentPassword"
                                       name="currentPassword"
                                       placeholder="Enter current password"
                                       required>

                                <button type="button"
                                        class="password-toggle"
                                        onclick="togglePasswordField('currentPassword', this)">
                                    <i class="fa-regular fa-eye"></i>
                                </button>
                            </div>
                        </div>

                        <div class="form-group">
                            <label>New Password</label>

                            <div class="password-input-wrap">
                                <input type="password"
                                       id="newPassword"
                                       name="newPassword"
                                       placeholder="Enter new password"
                                       required>

                                <button type="button"
                                        class="password-toggle"
                                        onclick="togglePasswordField('newPassword', this)">
                                    <i class="fa-regular fa-eye"></i>
                                </button>
                            </div>
                        </div>

                        <div class="form-group">
                            <label>Confirm New Password</label>

                            <div class="password-input-wrap">
                                <input type="password"
                                       id="confirmPassword"
                                       name="confirmPassword"
                                       placeholder="Confirm new password"
                                       required>

                                <button type="button"
                                        class="password-toggle"
                                        onclick="togglePasswordField('confirmPassword', this)">
                                    <i class="fa-regular fa-eye"></i>
                                </button>
                            </div>
                        </div>

                    </div>

                    <div class="form-actions">
                        <button type="submit" class="btn">
                            <i class="fa-solid fa-floppy-disk"></i>
                            Change Password
                        </button>

                        <% if (!"EMPLOYEE".equalsIgnoreCase(role)) { %>
                        <a href="ams_copilot.jsp"><i class="fa-solid fa-robot"></i> AI Copilot</a>
                        <a href="settings.jsp" class="btn">
                            <i class="fa-solid fa-arrow-left"></i>
                            Back to Settings
                        </a>
                        <% } %>
                    </div>

                </form>

                <div class="password-note">
                    <strong>Password Rules:</strong>
                    <br>
                    New password must be at least 6 characters long.
                    It cannot be same as your current password.
                    Password change activity will be stored in audit logs.
                </div>

            </section>

        </div>

    </main>

</div>

<script>
    function togglePasswordField(inputId, button) {
        const input = document.getElementById(inputId);
        const icon = button.querySelector("i");

        if (input.type === "password") {
            input.type = "text";
            icon.classList.remove("fa-eye");
            icon.classList.add("fa-eye-slash");
        } else {
            input.type = "password";
            icon.classList.remove("fa-eye-slash");
            icon.classList.add("fa-eye");
        }
    }
</script>

<script src="js/topbar-search.js?v=6000000"></script>

</body>
</html>