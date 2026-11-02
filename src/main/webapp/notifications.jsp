<%@page contentType="text/html" pageEncoding="UTF-8"%>
<%@page import="com.mycompany.asset_management_system_ams.DBConnection"%>
<%@page import="java.sql.*"%>
<%@page import="java.util.*"%>

<%!
    public static class AlertItem {
        String alertType = "";
        String icon = "";
        String titleText = "";
        String detailText = "";
        String targetUrl = "";
        String dateText = "";
        String severity = "";
    }

    private String safeText(String value) {
        if (value == null || value.trim().isEmpty()) return "N/A";
        return value.trim()
                .replace("&", "&amp;")
                .replace("<", "&lt;")
                .replace(">", "&gt;")
                .replace("\"", "&quot;")
                .replace("'", "&#39;");
    }

    private String cleanLabel(String value) {
        if (value == null || value.trim().isEmpty()) return "N/A";
        String text = value.trim().replace("_", " ").toLowerCase(Locale.ENGLISH);
        String[] parts = text.split("\\s+");
        StringBuilder out = new StringBuilder();

        for (String part : parts) {
            if (part.length() > 0) {
                out.append(Character.toUpperCase(part.charAt(0))).append(part.substring(1)).append(" ");
            }
        }
        return out.toString().trim();
    }

    private boolean tableExists(Connection con, String tableName) {
        String sql = "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = DATABASE() AND table_name = ?";

        try (PreparedStatement ps = con.prepareStatement(sql)) {
            ps.setString(1, tableName);

            try (ResultSet rs = ps.executeQuery()) {
                return rs.next() && rs.getInt(1) > 0;
            }

        } catch (Exception e) {
            e.printStackTrace();
        }

        return false;
    }

    private int countRows(Connection con, String sql) {
        try (Statement st = con.createStatement();
             ResultSet rs = st.executeQuery(sql)) {

            if (rs.next()) return rs.getInt(1);

        } catch (Exception e) {
            e.printStackTrace();
        }

        return 0;
    }

    private List<AlertItem> runAlertQuery(Connection con, String sql) {
        List<AlertItem> list = new ArrayList<AlertItem>();

        try (Statement st = con.createStatement();
             ResultSet rs = st.executeQuery(sql)) {

            while (rs.next()) {
                AlertItem item = new AlertItem();

                item.alertType = rs.getString("alert_type");
                item.icon = rs.getString("icon");
                item.titleText = rs.getString("title_text");
                item.detailText = rs.getString("detail_text");
                item.targetUrl = rs.getString("target_url");
                item.dateText = rs.getString("date_text");
                item.severity = rs.getString("severity");

                list.add(item);
            }

        } catch (Exception e) {
            e.printStackTrace();
        }

        return list;
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

    String userInitial = username.substring(0, Math.min(2, username.length())).toUpperCase(Locale.ENGLISH);

    boolean isSuperAdmin = ("SUPER_ADMIN".equals(role) || "ADMIN".equals(role));
    boolean isAssetManager = "ASSET_MANAGER".equals(role);
    boolean isAuditor = "AUDITOR".equals(role);

    boolean canViewAdminData = isSuperAdmin || isAssetManager || isAuditor;

    int pendingRequests = 0;
    int warrantyExpiring = 0;
    int maintenanceDue = 0;
    int overdueReturns = 0;
    int verificationIssues = 0;
    int assetsUnderMaintenance = 0;
    int pendingDisposal = 0;
    int recentAudit = 0;

    List<AlertItem> alerts = new ArrayList<AlertItem>();

    try (Connection con = DBConnection.getConnection()) {

        if (tableExists(con, "asset_requests")) {
            pendingRequests = countRows(con, "SELECT COUNT(*) FROM asset_requests WHERE request_status = 'PENDING'");

            alerts.addAll(runAlertQuery(con,
                    "SELECT "
                    + "'Pending Request' AS alert_type, "
                    + "'fa-square-plus' AS icon, "
                    + "CONCAT('Request #', ar.request_id, ' · ', COALESCE(e.full_name, 'Employee')) AS title_text, "
                    + "CONCAT_WS(' · ', COALESCE(ac.category_name, 'Category'), COALESCE(ar.priority, 'NORMAL'), COALESCE(ar.request_reason, 'Asset request pending for review')) AS detail_text, "
                    + "CONCAT('view_request.jsp?id=', ar.request_id) AS target_url, "
                    + "DATE_FORMAT(ar.created_at, '%d %b %Y, %h:%i %p') AS date_text, "
                    + "'warning' AS severity "
                    + "FROM asset_requests ar "
                    + "LEFT JOIN employees e ON ar.employee_id = e.employee_id "
                    + "LEFT JOIN asset_categories ac ON ar.category_id = ac.category_id "
                    + "WHERE ar.request_status = 'PENDING' "
                    + "ORDER BY ar.request_id DESC LIMIT 8"
            ));
        }

        if (tableExists(con, "assets")) {
            warrantyExpiring = countRows(con,
                    "SELECT COUNT(*) FROM assets "
                    + "WHERE warranty_expiry IS NOT NULL "
                    + "AND warranty_expiry BETWEEN CURDATE() AND DATE_ADD(CURDATE(), INTERVAL 30 DAY) "
                    + "AND asset_status <> 'DISPOSED'");

            assetsUnderMaintenance = countRows(con,
                    "SELECT COUNT(*) FROM assets "
                    + "WHERE asset_status = 'UNDER_MAINTENANCE' "
                    + "OR service_status IN ('UNDER_REPAIR','NEEDS_ATTENTION','UNSERVICEABLE')");

            alerts.addAll(runAlertQuery(con,
                    "SELECT "
                    + "'Warranty Expiring' AS alert_type, "
                    + "'fa-calendar-days' AS icon, "
                    + "CONCAT(a.asset_code, ' · ', a.asset_name) AS title_text, "
                    + "CONCAT('Warranty expires on ', DATE_FORMAT(a.warranty_expiry, '%d %b %Y'), ' · ', COALESCE(v.vendor_name, 'No Vendor')) AS detail_text, "
                    + "CONCAT('view_asset.jsp?id=', a.asset_id) AS target_url, "
                    + "DATE_FORMAT(a.warranty_expiry, '%d %b %Y') AS date_text, "
                    + "'warning' AS severity "
                    + "FROM assets a "
                    + "LEFT JOIN vendors v ON a.vendor_id = v.vendor_id "
                    + "WHERE a.warranty_expiry IS NOT NULL "
                    + "AND a.warranty_expiry BETWEEN CURDATE() AND DATE_ADD(CURDATE(), INTERVAL 30 DAY) "
                    + "AND a.asset_status <> 'DISPOSED' "
                    + "ORDER BY a.warranty_expiry ASC LIMIT 8"
            ));

            alerts.addAll(runAlertQuery(con,
                    "SELECT "
                    + "'Under Maintenance' AS alert_type, "
                    + "'fa-screwdriver-wrench' AS icon, "
                    + "CONCAT(asset_code, ' · ', asset_name) AS title_text, "
                    + "CONCAT_WS(' · ', asset_status, service_status, COALESCE(location, 'Location not updated')) AS detail_text, "
                    + "CONCAT('view_asset.jsp?id=', asset_id) AS target_url, "
                    + "DATE_FORMAT(updated_at, '%d %b %Y, %h:%i %p') AS date_text, "
                    + "'danger' AS severity "
                    + "FROM assets "
                    + "WHERE asset_status = 'UNDER_MAINTENANCE' "
                    + "OR service_status IN ('UNDER_REPAIR','NEEDS_ATTENTION','UNSERVICEABLE') "
                    + "ORDER BY updated_at DESC LIMIT 8"
            ));
        }

        if (tableExists(con, "maintenance_logs")) {
            maintenanceDue = countRows(con,
                    "SELECT COUNT(*) FROM maintenance_logs "
                    + "WHERE next_due_date IS NOT NULL "
                    + "AND next_due_date <= DATE_ADD(CURDATE(), INTERVAL 7 DAY) "
                    + "AND maintenance_status NOT IN ('COMPLETED','CANCELLED')");

            alerts.addAll(runAlertQuery(con,
                    "SELECT "
                    + "'Maintenance Due' AS alert_type, "
                    + "'fa-screwdriver-wrench' AS icon, "
                    + "CONCAT(a.asset_code, ' · ', a.asset_name) AS title_text, "
                    + "CONCAT('Next due: ', DATE_FORMAT(ml.next_due_date, '%d %b %Y'), ' · ', COALESCE(ml.maintenance_status, 'OPEN'), ' · ', COALESCE(ml.issue_reported, 'Maintenance follow-up required')) AS detail_text, "
                    + "CONCAT('view_maintenance.jsp?id=', ml.maintenance_id) AS target_url, "
                    + "DATE_FORMAT(ml.next_due_date, '%d %b %Y') AS date_text, "
                    + "'warning' AS severity "
                    + "FROM maintenance_logs ml "
                    + "LEFT JOIN assets a ON ml.asset_id = a.asset_id "
                    + "WHERE ml.next_due_date IS NOT NULL "
                    + "AND ml.next_due_date <= DATE_ADD(CURDATE(), INTERVAL 7 DAY) "
                    + "AND ml.maintenance_status NOT IN ('COMPLETED','CANCELLED') "
                    + "ORDER BY ml.next_due_date ASC LIMIT 8"
            ));
        }

        if (tableExists(con, "asset_allocation")) {
            overdueReturns = countRows(con,
                    "SELECT COUNT(*) FROM asset_allocation "
                    + "WHERE expected_return_date IS NOT NULL "
                    + "AND expected_return_date < CURDATE() "
                    + "AND allocation_status = 'ALLOCATED'");

            alerts.addAll(runAlertQuery(con,
                    "SELECT "
                    + "'Return Overdue' AS alert_type, "
                    + "'fa-rotate-left' AS icon, "
                    + "CONCAT(a.asset_code, ' · ', a.asset_name) AS title_text, "
                    + "CONCAT('Holder: ', COALESCE(e.full_name, 'Employee'), ' · Expected return: ', DATE_FORMAT(aa.expected_return_date, '%d %b %Y')) AS detail_text, "
                    + "CONCAT('view_allocation.jsp?id=', aa.allocation_id) AS target_url, "
                    + "DATE_FORMAT(aa.expected_return_date, '%d %b %Y') AS date_text, "
                    + "'danger' AS severity "
                    + "FROM asset_allocation aa "
                    + "LEFT JOIN assets a ON aa.asset_id = a.asset_id "
                    + "LEFT JOIN employees e ON aa.employee_id = e.employee_id "
                    + "WHERE aa.expected_return_date IS NOT NULL "
                    + "AND aa.expected_return_date < CURDATE() "
                    + "AND aa.allocation_status = 'ALLOCATED' "
                    + "ORDER BY aa.expected_return_date ASC LIMIT 8"
            ));
        }

        if (tableExists(con, "physical_verification")) {
            verificationIssues = countRows(con,
                    "SELECT COUNT(*) FROM physical_verification "
                    + "WHERE asset_found = 'NO' "
                    + "OR verification_status IN ('LOCATION_MISMATCH','HOLDER_MISMATCH','REPAIR_FLAGGED','NOT_FOUND')");

            alerts.addAll(runAlertQuery(con,
                    "SELECT "
                    + "'Verification Issue' AS alert_type, "
                    + "'fa-shield-halved' AS icon, "
                    + "CONCAT(a.asset_code, ' · ', a.asset_name) AS title_text, "
                    + "CONCAT_WS(' · ', pv.verification_status, CONCAT('Found: ', pv.asset_found), pv.physical_condition, COALESCE(pv.remarks, 'Verification issue requires attention')) AS detail_text, "
                    + "CONCAT('view_verification.jsp?id=', pv.verification_id) AS target_url, "
                    + "DATE_FORMAT(pv.verification_date, '%d %b %Y') AS date_text, "
                    + "'danger' AS severity "
                    + "FROM physical_verification pv "
                    + "LEFT JOIN assets a ON pv.asset_id = a.asset_id "
                    + "WHERE pv.asset_found = 'NO' "
                    + "OR pv.verification_status IN ('LOCATION_MISMATCH','HOLDER_MISMATCH','REPAIR_FLAGGED','NOT_FOUND') "
                    + "ORDER BY pv.verification_id DESC LIMIT 8"
            ));
        }

        if (canViewAdminData && tableExists(con, "asset_disposal")) {
            pendingDisposal = countRows(con, "SELECT COUNT(*) FROM asset_disposal WHERE disposal_status = 'PENDING'");

            alerts.addAll(runAlertQuery(con,
                    "SELECT "
                    + "'Disposal Pending' AS alert_type, "
                    + "'fa-recycle' AS icon, "
                    + "CONCAT(a.asset_code, ' · ', a.asset_name) AS title_text, "
                    + "CONCAT_WS(' · ', ad.disposal_reason, CONCAT('Value ₹', COALESCE(ad.disposal_value, 0)), COALESCE(ad.remarks, 'Disposal approval pending')) AS detail_text, "
                    + "CONCAT('view_disposal.jsp?id=', ad.disposal_id) AS target_url, "
                    + "DATE_FORMAT(ad.created_at, '%d %b %Y, %h:%i %p') AS date_text, "
                    + "'warning' AS severity "
                    + "FROM asset_disposal ad "
                    + "LEFT JOIN assets a ON ad.asset_id = a.asset_id "
                    + "WHERE ad.disposal_status = 'PENDING' "
                    + "ORDER BY ad.disposal_id DESC LIMIT 8"
            ));
        }

        if ((isSuperAdmin || isAuditor) && tableExists(con, "audit_logs")) {
            recentAudit = countRows(con,
                    "SELECT COUNT(*) FROM audit_logs WHERE created_at >= DATE_SUB(NOW(), INTERVAL 24 HOUR)");

            alerts.addAll(runAlertQuery(con,
                    "SELECT "
                    + "'Audit Activity' AS alert_type, "
                    + "'fa-clipboard-check' AS icon, "
                    + "CONCAT(COALESCE(module_name, 'Module'), ' · ', COALESCE(action_type, 'Action')) AS title_text, "
                    + "CONCAT_WS(' · ', COALESCE(username, 'System'), COALESCE(user_role, ''), COALESCE(action_details, 'Recent system activity')) AS detail_text, "
                    + "CONCAT('view_audit_log.jsp?id=', audit_id) AS target_url, "
                    + "DATE_FORMAT(created_at, '%d %b %Y, %h:%i %p') AS date_text, "
                    + "'info' AS severity "
                    + "FROM audit_logs "
                    + "ORDER BY audit_id DESC LIMIT 8"
            ));
        }

    } catch (Exception e) {
        e.printStackTrace();
    }

    int totalAlerts = pendingRequests + warrantyExpiring + maintenanceDue + overdueReturns + verificationIssues + assetsUnderMaintenance + pendingDisposal;
%>

<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>Notifications - IR-AMS</title>

    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.0/css/all.min.css">

    <link rel="stylesheet" href="css/ir-glass.css?v=28000">
    <link rel="stylesheet" href="css/ams-pro.css?v=28000">
    <link rel="stylesheet" href="css/ir-ams-railway-ui.css?v=notifications-final-1">

    <link rel="stylesheet" href="css/notifications.css?v=28001">
</head>

<body class="railway-ui">
<div class="app ams-shell">

    <jsp:include page="sidebar.jsp" />

    <main class="main railway-main">
        <jsp:include page="topbar.jsp" />

        <div class="main-scroll-content notify-board">

            <section class="notify-hero">
                <div>
                    <h1>Notifications</h1>
                    <p>Live railway asset alerts from requests, warranty, maintenance, returns, verification, disposal and audit activity.</p>
                </div>

                <div class="notify-count">
                    <strong><%= totalAlerts %></strong>
                    <span>Active Alerts</span>
                </div>
            </section>

            <section class="notify-grid">
                <a class="notify-card" href="asset_requests.jsp"><span>Pending Requests</span><strong><%= pendingRequests %></strong><small>Needs review</small></a>
                <a class="notify-card" href="warranty_report.jsp"><span>Warranty Expiring</span><strong><%= warrantyExpiring %></strong><small>Within 30 days</small></a>
                <a class="notify-card" href="maintenance.jsp"><span>Maintenance Due</span><strong><%= maintenanceDue %></strong><small>Due / upcoming</small></a>
                <a class="notify-card" href="overdue_actions.jsp"><span>Return Overdue</span><strong><%= overdueReturns %></strong><small>Action required</small></a>
                <a class="notify-card" href="physical_verification.jsp"><span>Verification Issues</span><strong><%= verificationIssues %></strong><small>Mismatch / not found</small></a>
                <a class="notify-card" href="assets.jsp"><span>Under Maintenance</span><strong><%= assetsUnderMaintenance %></strong><small>Not serviceable</small></a>
                <a class="notify-card" href="assets.jsp"><span>Disposal Pending</span><strong><%= pendingDisposal %></strong><small>Approval waiting</small></a>
                <a class="notify-card" href="audit_logs.jsp"><span>Recent Audit</span><strong><%= recentAudit %></strong><small>Last 24 hours</small></a>
            </section>

            <section class="notify-panel">
                <h2>Latest Alerts</h2>

                <% if (alerts.isEmpty()) { %>
                    <div class="empty-box">
                        <i class="fa-solid fa-circle-check"></i>
                        <strong>No active notification found</strong>
                        <span>Current asset records do not need immediate attention.</span>
                    </div>
                <% } else { %>
                    <div class="notify-list">
                        <% for (AlertItem item : alerts) { %>
                            <a class="notify-row <%= safeText(item.severity) %>" href="<%= safeText(item.targetUrl) %>">
                                <div class="notify-icon"><i class="fa-solid <%= safeText(item.icon) %>"></i></div>
                                <div class="notify-main">
                                    <strong><%= safeText(item.alertType) %> · <%= safeText(item.titleText) %></strong>
                                    <span><%= safeText(item.detailText) %></span>
                                </div>
                                <div class="notify-date"><%= safeText(item.dateText) %></div>
                            </a>
                        <% } %>
                    </div>
                <% } %>
            </section>

        </div>
    </main>
</div>

<script src="js/user-dropdown.js?v=5"></script>
<script src="js/sidebar-role.js?v=7000"></script>
<script src="js/topbar-search.js?v=global-search-ready-1"></script>
<script src="js/dashboard-actions.js?v=2"></script>
</body>
</html>