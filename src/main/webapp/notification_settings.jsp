<%@page contentType="text/html" pageEncoding="UTF-8"%>
<%@page import="java.sql.*"%>
<%@page import="com.mycompany.asset_management_system_ams.DBConnection"%>

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

    int maintenanceAlerts = 1;
    int requestAlerts = 1;
    int returnAlerts = 1;
    int auditAlerts = 1;
    int emailAlerts = 0;
    int dashboardAlerts = 1;
    int warrantyAlerts = 1;
    int copilotDigestAlerts = 1;

    Connection con = null;
    PreparedStatement ps = null;
    ResultSet rs = null;

    try {
        con = DBConnection.getConnection();

        ps = con.prepareStatement("SELECT * FROM notification_settings WHERE setting_id = 1");
        rs = ps.executeQuery();

        if (rs.next()) {
            maintenanceAlerts = rs.getInt("maintenance_alerts");
            requestAlerts = rs.getInt("request_alerts");
            returnAlerts = rs.getInt("return_alerts");
            auditAlerts = rs.getInt("audit_alerts");
            emailAlerts = rs.getInt("email_alerts");
            dashboardAlerts = rs.getInt("dashboard_alerts");
            // warranty_alerts already existed in schema.sql but was never read here -
            // it now actually gates WarrantyAlertScheduler's daily warranty-expiry check.
            warrantyAlerts = rs.getInt("warranty_alerts");
            copilotDigestAlerts = rs.getInt("copilot_digest_alerts");
        }

    } catch (Exception e) {
        System.err.println("Notification settings fetch error: " + e.getMessage());
    } finally {
        try {
            if (rs != null) {
                rs.close();
            }

            if (ps != null) {
                ps.close();
            }

            if (con != null) {
                con.close();
            }
        } catch (Exception ex) {
            System.err.println("Resource close error: " + ex.getMessage());
        }
    }

    String msg = request.getParameter("msg");
    String error = request.getParameter("error");
%>

<!DOCTYPE html>
<html>
<head>
    <title>IR-AMS Notification Settings</title>

    <link rel="stylesheet"
          href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.0/css/all.min.css">

    <link rel="stylesheet" href="css/ir-glass.css?v=system-audit-scanner-1">
    <link rel="stylesheet" href="css/ams-pro.css?v=system-audit-scanner-1">
    <link rel="stylesheet" href="css/ir-ams-railway-ui.css?v=system-audit-scanner-1">
<link rel="stylesheet" href="css/notification_settings.css?v=topbarfix1">
</head>

<body class="railway-ui">

<div class="app">

        <jsp:include page="sidebar.jsp" />

    <main class="main railway-main">

                <jsp:include page="topbar.jsp" />

        <div class="main-scroll-content">

            <section class="asset-hero">
                <h1>Notification Settings</h1>

                <p>
                    Configure system alert preferences for maintenance reminders, asset requests,
                    return workflow, audit activities, Gmail email notification and dashboard alerts.
                </p>

                <br>

                <div class="hero-pills">
                    <div class="hero-pill">
                        <i class="fa-solid fa-bell"></i> Alert Control
                    </div>

                    <div class="hero-pill">
                        <i class="fa-solid fa-screwdriver-wrench"></i> Maintenance Alerts
                    </div>

                    <div class="hero-pill">
                        <i class="fa-brands fa-google"></i> Gmail Email
                    </div>

                    <div class="hero-pill">
                        <i class="fa-solid fa-lock"></i> Super Admin Only
                    </div>
                </div>
            </section>

            <% if ("updated".equals(msg)) { %>
                <div class="page-success">
                    <i class="fa-solid fa-circle-check"></i>
                    Notification settings updated successfully.
                </div>
            <% } else if ("server".equals(error)) { %>
                <div class="page-error">
                    <i class="fa-solid fa-triangle-exclamation"></i>
                    Server error occurred while updating notification settings.
                </div>
            <% } %>

            <section class="glass-panel">

                <div class="registry-toolbar">
                    <div>
                        <h2>Alert Preferences</h2>
                        <p class="table-subtext">
                            Turn system notifications on or off as per administrative requirement.
                        </p>
                    </div>

                    <div class="registry-actions">
                        <a href="test_email.jsp" class="btn">
                            <i class="fa-brands fa-google"></i>
                            Test Gmail Email
                        </a>

                        <a href="ams_copilot.jsp"><i class="fa-solid fa-robot"></i> AI Copilot</a>
              <a href="settings.jsp" class="btn secondary-btn">
                            <i class="fa-solid fa-arrow-left"></i>
                            Back to Settings
                        </a>
                    </div>
                </div>

                <form action="UpdateNotificationSettingsServlet" method="post">

                    <div class="notification-grid">

                        <div class="notification-card">
                            <div class="notification-info">
                                <div class="notification-icon">
                                    <i class="fa-solid fa-screwdriver-wrench"></i>
                                </div>

                                <div>
                                    <h3>Maintenance Alerts</h3>
                                    <p>Notify when assets require service, repair or preventive maintenance action.</p>
                                </div>
                            </div>

                            <label class="switch">
                                <input type="checkbox" name="maintenanceAlerts" value="1" <%= maintenanceAlerts == 1 ? "checked" : "" %>>
                                <span class="slider"></span>
                            </label>
                        </div>

                        <div class="notification-card">
                            <div class="notification-info">
                                <div class="notification-icon">
                                    <i class="fa-solid fa-file-circle-plus"></i>
                                </div>

                                <div>
                                    <h3>Request Alerts</h3>
                                    <p>Notify administrators when asset requests are created or awaiting action.</p>
                                </div>
                            </div>

                            <label class="switch">
                                <input type="checkbox" name="requestAlerts" value="1" <%= requestAlerts == 1 ? "checked" : "" %>>
                                <span class="slider"></span>
                            </label>
                        </div>

                        <div class="notification-card">
                            <div class="notification-info">
                                <div class="notification-icon">
                                    <i class="fa-solid fa-rotate-left"></i>
                                </div>

                                <div>
                                    <h3>Return Alerts</h3>
                                    <p>Notify when assets are returned, damaged, verified or marked for repair.</p>
                                </div>
                            </div>

                            <label class="switch">
                                <input type="checkbox" name="returnAlerts" value="1" <%= returnAlerts == 1 ? "checked" : "" %>>
                                <span class="slider"></span>
                            </label>
                        </div>

                        <div class="notification-card">
                            <div class="notification-info">
                                <div class="notification-icon">
                                    <i class="fa-solid fa-shield-halved"></i>
                                </div>

                                <div>
                                    <h3>Audit Alerts</h3>
                                    <p>Track important administrative actions such as update, export, backup and restore.</p>
                                </div>
                            </div>

                            <label class="switch">
                                <input type="checkbox" name="auditAlerts" value="1" <%= auditAlerts == 1 ? "checked" : "" %>>
                                <span class="slider"></span>
                            </label>
                        </div>

                        <div class="notification-card">
                            <div class="notification-info">
                                <div class="notification-icon">
                                    <i class="fa-brands fa-google"></i>
                                </div>

                                <div>
                                    <h3>Gmail Email Alerts</h3>
                                    <p>Enable Gmail SMTP email alerts for system notifications and administrative updates.</p>
                                </div>
                            </div>

                            <label class="switch">
                                <input type="checkbox" name="emailAlerts" value="1" <%= emailAlerts == 1 ? "checked" : "" %>>
                                <span class="slider"></span>
                            </label>
                        </div>

                        <div class="notification-card">
                            <div class="notification-info">
                                <div class="notification-icon">
                                    <i class="fa-solid fa-display"></i>
                                </div>

                                <div>
                                    <h3>Dashboard Alerts</h3>
                                    <p>Show important operational alerts directly on admin and manager dashboards.</p>
                                </div>
                            </div>

                            <label class="switch">
                                <input type="checkbox" name="dashboardAlerts" value="1" <%= dashboardAlerts == 1 ? "checked" : "" %>>
                                <span class="slider"></span>
                            </label>
                        </div>

                        <div class="notification-card">
                            <div class="notification-info">
                                <div class="notification-icon">
                                    <i class="fa-solid fa-file-shield"></i>
                                </div>

                                <div>
                                    <h3>Warranty Alerts</h3>
                                    <p>Email the asset manager when an asset's warranty is about to expire. Threshold is set on Settings &gt; Notifications ("Warranty Expiry Alert - Days Before").</p>
                                </div>
                            </div>

                            <label class="switch">
                                <input type="checkbox" name="warrantyAlerts" value="1" <%= warrantyAlerts == 1 ? "checked" : "" %>>
                                <span class="slider"></span>
                            </label>
                        </div>

                        <div class="notification-card">
                            <div class="notification-info">
                                <div class="notification-icon">
                                    <i class="fa-solid fa-robot"></i>
                                </div>

                                <div>
                                    <h3>Copilot Daily Digest</h3>
                                    <p>Email the asset manager a daily summary of pending asset requests and pending maintenance requests that have been waiting too long. Threshold is set on Settings &gt; Notifications ("Copilot Digest - Aging Threshold").</p>
                                </div>
                            </div>

                            <label class="switch">
                                <input type="checkbox" name="copilotDigestAlerts" value="1" <%= copilotDigestAlerts == 1 ? "checked" : "" %>>
                                <span class="slider"></span>
                            </label>
                        </div>

                    </div>

                    <div class="form-actions">
                        <button type="submit" class="btn submit-btn">
                            <i class="fa-solid fa-floppy-disk"></i>
                            Save Notification Settings
                        </button>

                        <a href="test_email.jsp" class="btn">
                            <i class="fa-brands fa-google"></i>
                            Test Gmail Email
                        </a>

                        <a href="ams_copilot.jsp"><i class="fa-solid fa-robot"></i> AI Copilot</a>
              <a href="settings.jsp" class="btn secondary-btn">
                            <i class="fa-solid fa-arrow-left"></i>
                            Back to Settings
                        </a>
                    </div>

                </form>

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

<script src="js/topbar-search.js?v=system-audit-scanner-1"></script>
<script src="js/user-dropdown.js?v=system-audit-scanner-1"></script>
<script src="js/sidebar-role.js?v=system-audit-scanner-1"></script>
<script src="js/ir-body-watermark.js?v=system-audit-scanner-1"></script>
<script src="js/dashboard-actions.js?v=system-audit-scanner-1"></script>

</body>
</html>
