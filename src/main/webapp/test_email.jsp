<%@page contentType="text/html" pageEncoding="UTF-8"%>

<%!
    private String safeValue(String value) {
        if (value == null) {
            return "";
        }

        return value
                .replace("&", "&amp;")
                .replace("<", "&lt;")
                .replace(">", "&gt;")
                .replace("\"", "&quot;")
                .replace("'", "&#39;");
    }
%>

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

    if (!("SUPER_ADMIN".equals(role) || "ADMIN".equals(role))) {
        response.sendRedirect("settings.jsp?access=denied");
        return;
    }

    String msg = request.getParameter("msg");
    String error = request.getParameter("error");

    String email = request.getParameter("email");

    if (email == null || email.trim().isEmpty()) {
        email = request.getParameter("toEmail");
    }

    if (email == null) {
        email = "";
    }
%>

<!DOCTYPE html>
<html>
<head>
    <title>IR-AMS Gmail Notification Test</title>

    <link rel="stylesheet"
          href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.0/css/all.min.css">

    <link rel="stylesheet" href="css/ir-glass.css?v=5000">

    <link rel="stylesheet" href="css/test_email.css?v=28001">
</head>

<body>

<div class="app">

    <jsp:include page="sidebar.jsp" />

    <main class="main">

        <jsp:include page="topbar.jsp" />

        <div class="main-scroll-content">

            <section class="asset-hero">
                <h1>
                    <i class="fa-brands fa-google gmail-icon"></i>
                    Test Gmail Notification
                </h1>

                <p>
                    Send a real email alert from IR-AMS using Gmail SMTP and your configured Gmail App Password.
                </p>

                <br>

                <div class="hero-pills">
                    <div class="hero-pill">
                        <i class="fa-brands fa-google"></i> Gmail SMTP
                    </div>

                    <div class="hero-pill">
                        <i class="fa-solid fa-envelope-circle-check"></i> Real Email Alert
                    </div>

                    <div class="hero-pill">
                        <i class="fa-solid fa-shield-halved"></i> Audit Logged
                    </div>

                    <div class="hero-pill">
                        <i class="fa-solid fa-lock"></i> Super Admin Only
                    </div>
                </div>
            </section>

            <% if ("sent".equals(msg)) { %>
                <div class="page-success">
                    <i class="fa-solid fa-circle-check"></i>

                    <% if (!email.trim().isEmpty()) { %>
                        Test email sent successfully to <strong><%= safeValue(email) %></strong>.
                    <% } else { %>
                        Test email sent successfully.
                    <% } %>
                </div>
            <% } else if ("invalid".equals(error)) { %>
                <div class="page-error">
                    <i class="fa-solid fa-triangle-exclamation"></i>
                    Please enter valid email, subject and message.
                </div>
            <% } else if ("server".equals(error)) { %>
                <div class="page-error">
                    <i class="fa-solid fa-triangle-exclamation"></i>
                    Email sending failed. Check Gmail address, app password, internet connection and Tomcat console.
                </div>
            <% } %>

            <section class="email-layout">

                <div class="email-card">

                    <h2>
                        <i class="fa-brands fa-google gmail-icon"></i>
                        Send Gmail Test Email
                    </h2>

                    <p>
                        Use this page to verify that IR-AMS Gmail email notifications are connected successfully.
                    </p>

                    <form action="SendTestEmailServlet" method="post">

                        <div class="form-group">
                            <label>
                                <i class="fa-solid fa-at"></i>
                                Receiver Email
                            </label>

                            <input type="email"
                                   name="toEmail"
                                   placeholder="Enter receiver email address"
                                   maxlength="120"
                                   required>
                        </div>

                        <div class="form-group">
                            <label>
                                <i class="fa-solid fa-heading"></i>
                                Subject
                            </label>

                            <input type="text"
                                   name="subject"
                                   value="IR-AMS Gmail Test Email Notification"
                                   maxlength="150"
                                   required>
                        </div>

                        <div class="form-group">
                            <label>
                                <i class="fa-solid fa-align-left"></i>
                                Message
                            </label>

                            <textarea name="messageBody"
                                      maxlength="1200"
                                      required>Dear User,

This is a test email notification from IR-AMS.

Your Gmail SMTP notification service is connected successfully.

Regards,
IR-AMS Notification System</textarea>
                        </div>

                        <div class="form-actions">
                            <button type="submit" class="btn submit-btn">
                                <i class="fa-brands fa-google"></i>
                                Send Gmail Test Email
                            </button>

                            <a href="notification_settings.jsp" class="btn secondary-btn">
                                <i class="fa-solid fa-bell"></i>
                                Notification Settings
                            </a>

                            <a href="ams_copilot.jsp"><i class="fa-solid fa-robot"></i> AI Copilot</a>
              <a href="settings.jsp" class="btn secondary-btn">
                                <i class="fa-solid fa-arrow-left"></i>
                                Back to Settings
                            </a>
                        </div>

                    </form>

                </div>

                <div class="email-card">

                    <h2>
                        <i class="fa-solid fa-circle-info"></i>
                        Setup Status
                    </h2>

                    <p>
                        This page uses the Gmail SMTP details stored inside WEB-INF/notification.properties.
                    </p>

                    <div class="info-row">
                        <span>SMTP Provider</span>
                        <strong>Gmail SMTP</strong>
                    </div>

                    <div class="info-row">
                        <span>Security</span>
                        <strong>Gmail App Password + TLS</strong>
                    </div>

                    <div class="info-row">
                        <span>Audit Table</span>
                        <strong>audit_logs</strong>
                    </div>

                    <div class="info-row">
                        <span>Trigger Type</span>
                        <strong>Manual Gmail Test Notification</strong>
                    </div>

                    <div class="info-row">
                        <span>SMTP Fallback</span>
                        <strong>Primary 587 STARTTLS, Fallback 465 SSL</strong>
                    </div>

                    <div class="info-row">
                        <span>Next Phase</span>
                        <strong>Auto email on request, return, repair and maintenance</strong>
                    </div>

                </div>

            </section>

        </div>

    </main>

</div>
<script>
    const contextPath = "<%= request.getContextPath() %>";

    const railBackgrounds = [
        contextPath + "/images/rail-bg-1.jpg",
        contextPath + "/images/rail-bg-2.jpg",
        contextPath + "/images/rail-bg-3.jpg",
        contextPath + "/images/rail-bg-4.jpg",
        contextPath + "/images/rail-bg-5.jpg",
        contextPath + "/images/rail-bg-6.jpg",
        contextPath + "/images/rail-bg-7.jpg"
    ];

    let currentBgIndex = 0;

    function changeRailBackground() {
        currentBgIndex++;

        if (currentBgIndex >= railBackgrounds.length) {
            currentBgIndex = 0;
        }

        document.body.style.setProperty(
                "--rail-bg",
                "url('" + railBackgrounds[currentBgIndex] + "')"
        );
    }

    setInterval(changeRailBackground, 90000);
</script>

<script src="js/topbar-search.js?v=6000000"></script>
<script src="js/user-dropdown.js?v=4"></script>
<script src="js/sidebar-role.js?v=11000"></script>

</body>
</html>