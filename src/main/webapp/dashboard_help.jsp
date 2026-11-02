<%@page contentType="text/html" pageEncoding="UTF-8"%>

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

    boolean isSuperAdmin = ("SUPER_ADMIN".equals(role) || "ADMIN".equals(role));
    boolean isAssetManager = "ASSET_MANAGER".equals(role);
    boolean isDepartmentHead = "DEPARTMENT_HEAD".equals(role);
    boolean isAuditor = "AUDITOR".equals(role);
    boolean isEmployee = "EMPLOYEE".equals(role);

    boolean canManageAssets = isSuperAdmin || isAssetManager;
    boolean canVerify = isSuperAdmin || isAssetManager || isAuditor;
    boolean canRequest = isSuperAdmin || isDepartmentHead || isEmployee;
    boolean canReport = isSuperAdmin || isAssetManager || isDepartmentHead || isAuditor;
%>

<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>Help & Support - IR-AMS</title>

    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.0/css/all.min.css">

    <link rel="stylesheet" href="css/ir-glass.css?v=28000">
    <link rel="stylesheet" href="css/ams-pro.css?v=28000">
    <link rel="stylesheet" href="css/ir-ams-railway-ui.css?v=dashboard-help-final-1">

    <link rel="stylesheet" href="css/dashboard_help.css?v=28001">
</head>

<body class="railway-ui">
<div class="app ams-shell">

    <jsp:include page="sidebar.jsp" />

    <main class="main railway-main">
        <jsp:include page="topbar.jsp" />

        <div class="main-scroll-content help-board">

            <section class="help-hero">
                <div>
                    <h1>IR-AMS Help & Support</h1>
                    <p>
                        Official help centre for railway asset registration, issue/allocation, return,
                        maintenance, warranty, physical verification, reports, audit trail and system control.
                    </p>
                </div>

                <div class="help-status">
                    <strong>LIVE</strong>
                    <span>Support Ready</span>
                </div>
            </section>

            <section class="help-grid">
                <a class="help-card" href="global_search.jsp">
                    <div>
                        <i class="fa-solid fa-magnifying-glass"></i>
                        <strong>Global Search</strong>
                        <span>Search assets, holders, vendors, categories, locations, maintenance, requests and verification records.</span>
                    </div>
                </a>

                <a class="help-card" href="<%= canManageAssets ? "add_asset.jsp" : "assets.jsp" %>">
                    <div>
                        <i class="fa-solid fa-cube"></i>
                        <strong>Asset Registration</strong>
                        <span>Register, view and manage official railway assets with category, vendor, location and QR details.</span>
                    </div>
                </a>

                <a class="help-card" href="allocation.jsp">
                    <div>
                        <i class="fa-solid fa-arrow-right-arrow-left"></i>
                        <strong>Allocation & Return</strong>
                        <span>Issue assets to holders, track active assignment, return condition and complete movement history.</span>
                    </div>
                </a>

                <a class="help-card" href="maintenance.jsp">
                    <div>
                        <i class="fa-solid fa-screwdriver-wrench"></i>
                        <strong>Maintenance & Warranty</strong>
                        <span>Record repair, preventive maintenance, warranty status, next due date and vendor service details.</span>
                    </div>
                </a>

                <a class="help-card" href="<%= canVerify ? "physical_verification.jsp" : "dashboard.jsp" %>">
                    <div>
                        <i class="fa-solid fa-shield-halved"></i>
                        <strong>Physical Verification</strong>
                        <span>Verify asset availability, actual holder, actual location, condition mismatch and inspection remarks.</span>
                    </div>
                </a>

                <a class="help-card" href="<%= canReport ? "reports.jsp" : "dashboard.jsp" %>">
                    <div>
                        <i class="fa-regular fa-clipboard"></i>
                        <strong>Reports & Audit</strong>
                        <span>Open MIS reports, Excel exports, asset register, allocation register and audit trail review.</span>
                    </div>
                </a>

                <a class="help-card" href="<%= canRequest ? "asset_requests.jsp" : "dashboard.jsp" %>">
                    <div>
                        <i class="fa-regular fa-square-plus"></i>
                        <strong>Planning & Requests</strong>
                        <span>Create and track asset requests, demand planning, approval status and fulfilment details.</span>
                    </div>
                </a>

                <a class="help-card" href="qr_scanner.jsp">
                    <div>
                        <i class="fa-solid fa-qrcode"></i>
                        <strong>QR Scan Support</strong>
                        <span>Scan asset QR codes and verify real-time asset details through the system database.</span>
                    </div>
                </a>

                <a class="help-card" href="<%= isSuperAdmin || isAssetManager || isAuditor ? "db_status.jsp" : "dashboard.jsp" %>">
                    <div>
                        <i class="fa-solid fa-database"></i>
                        <strong>System Status</strong>
                        <span>Check database connection, table counts and live module readiness for administration use.</span>
                    </div>
                </a>
            </section>

            <section class="help-panel">
                <h2>Daily Railway AMS Workflow</h2>

                <div class="workflow-grid">
                    <div class="workflow-step">
                        <b>1</b>
                        <strong>Register Asset</strong>
                        <span>Add asset code, name, category, vendor, section/location, cost and warranty.</span>
                    </div>

                    <div class="workflow-step">
                        <b>2</b>
                        <strong>Issue / Allocate</strong>
                        <span>Assign asset to employee or section with issue date and issue condition.</span>
                    </div>

                    <div class="workflow-step">
                        <b>3</b>
                        <strong>Maintain</strong>
                        <span>Record repair, preventive service, cost, vendor and next maintenance due date.</span>
                    </div>

                    <div class="workflow-step">
                        <b>4</b>
                        <strong>Verify Physically</strong>
                        <span>Check asset found status, actual holder, actual location and physical condition.</span>
                    </div>

                    <div class="workflow-step">
                        <b>5</b>
                        <strong>Report & Audit</strong>
                        <span>Generate registers, audit logs, warranty reports and official MIS exports.</span>
                    </div>
                </div>
            </section>

            <section class="help-note">
                <strong>Important:</strong>
                Use railway-friendly workflow terms such as allocation, issue, return, holder, section,
                location, physical verification, asset register and reports. For mobile QR testing from
                another device, localhost will not work directly; use Cloudflare Tunnel or a deployed server URL.
            </section>

        </div>
    </main>
</div>

<script src="js/user-dropdown.js?v=5"></script>
<script src="js/sidebar-role.js?v=7000"></script>
<script src="js/topbar-search.js?v=global-search-ready-1"></script>
<script src="js/dashboard-actions.js?v=1"></script>
</body>
</html>