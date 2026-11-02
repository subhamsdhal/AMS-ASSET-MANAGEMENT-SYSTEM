<%@page contentType="text/html" pageEncoding="UTF-8"%>
<%@page import="com.mycompany.asset_management_system_ams.DBConnection"%>
<%@page import="java.sql.*"%>
<%@page import="java.util.*"%>

<%!
    public static class AlertGroup {
        String title = "";
        String icon = "";
        String url = "";
        int count = 0;
        String note = "";
        String severity = "";
    }

    private String safeText(String value) {
        if (value == null || value.trim().isEmpty()) return "N/A";
        return value.trim().replace("&","&amp;").replace("<","&lt;").replace(">","&gt;").replace("\"","&quot;").replace("'","&#39;");
    }

    private String cleanLabel(String value) {
        if (value == null || value.trim().isEmpty()) return "N/A";
        String text = value.trim().replace("_", " ").toLowerCase(Locale.ENGLISH);
        String[] parts = text.split("\\s+");
        StringBuilder out = new StringBuilder();
        for (String part : parts) {
            if (part.length() > 0) out.append(Character.toUpperCase(part.charAt(0))).append(part.substring(1)).append(" ");
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

    private AlertGroup group(String title, String icon, String url, int count, String note, String severity) {
        AlertGroup g = new AlertGroup();
        g.title = title;
        g.icon = icon;
        g.url = url;
        g.count = count;
        g.note = note;
        g.severity = severity;
        return g;
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

    ArrayList<AlertGroup> groups = new ArrayList<AlertGroup>();

    int criticalCount = 0;
    int warningCount = 0;
    int infoCount = 0;

    try (Connection con = DBConnection.getConnection()) {

        if (tableExists(con, "asset_allocation")) {
            int c = countRows(con, "SELECT COUNT(*) FROM asset_allocation WHERE expected_return_date IS NOT NULL AND expected_return_date < CURDATE() AND allocation_status='ALLOCATED'");
            groups.add(group("Return Overdue", "fa-rotate-left", "overdue_actions.jsp", c, "Assets not returned by expected date", "danger"));
            criticalCount += c;
        }

        if (tableExists(con, "physical_verification")) {
            int c = countRows(con, "SELECT COUNT(*) FROM physical_verification WHERE asset_found='NO' OR verification_status IN ('LOCATION_MISMATCH','HOLDER_MISMATCH','REPAIR_FLAGGED','NOT_FOUND')");
            groups.add(group("Physical Verification Issues", "fa-shield-halved", "physical_verification.jsp", c, "Mismatch, repair flagged or asset not found", "danger"));
            criticalCount += c;
        }

        if (tableExists(con, "assets")) {
            int c1 = countRows(con, "SELECT COUNT(*) FROM assets WHERE asset_status='UNDER_MAINTENANCE' OR service_status IN ('UNDER_REPAIR','UNSERVICEABLE')");
            groups.add(group("Assets Under Maintenance", "fa-screwdriver-wrench", "assets.jsp", c1, "Assets currently unavailable for normal use", "danger"));
            criticalCount += c1;

            int c2 = countRows(con, "SELECT COUNT(*) FROM assets WHERE warranty_expiry IS NOT NULL AND warranty_expiry BETWEEN CURDATE() AND DATE_ADD(CURDATE(), INTERVAL 30 DAY) AND asset_status <> 'DISPOSED'");
            groups.add(group("Warranty Expiring Soon", "fa-calendar-days", "warranty_report.jsp", c2, "Warranty ending within next 30 days", "warning"));
            warningCount += c2;

            int c3 = countRows(con, "SELECT COUNT(*) FROM assets WHERE asset_status='DAMAGED' OR condition_status IN ('DAMAGED','NEEDS_REPAIR')");
            groups.add(group("Damaged / Needs Repair", "fa-triangle-exclamation", "assets.jsp", c3, "Damaged or repair required assets", "warning"));
            warningCount += c3;
        }

        if (tableExists(con, "maintenance_logs")) {
            int c = countRows(con, "SELECT COUNT(*) FROM maintenance_logs WHERE next_due_date IS NOT NULL AND next_due_date <= DATE_ADD(CURDATE(), INTERVAL 7 DAY) AND maintenance_status NOT IN ('COMPLETED','CANCELLED')");
            groups.add(group("Maintenance Due", "fa-wrench", "overdue_actions.jsp", c, "Preventive/corrective maintenance due soon", "warning"));
            warningCount += c;
        }

        if (tableExists(con, "asset_requests")) {
            int c = countRows(con, "SELECT COUNT(*) FROM asset_requests WHERE request_status='PENDING'");
            groups.add(group("Pending Asset Requests", "fa-square-plus", "asset_requests.jsp", c, "Requests waiting for approval/review", "warning"));
            warningCount += c;
        }

        if (canViewAdminData && tableExists(con, "asset_disposal")) {
            int c = countRows(con, "SELECT COUNT(*) FROM asset_disposal WHERE disposal_status='PENDING'");
            groups.add(group("Pending Disposal Approval", "fa-recycle", "assets.jsp", c, "Disposal proposals waiting for approval", "warning"));
            warningCount += c;
        }

        if ((isSuperAdmin || isAuditor) && tableExists(con, "audit_logs")) {
            int c = countRows(con, "SELECT COUNT(*) FROM audit_logs WHERE created_at >= DATE_SUB(NOW(), INTERVAL 24 HOUR)");
            groups.add(group("Recent Audit Activity", "fa-clipboard-check", "audit_logs.jsp", c, "System activity in last 24 hours", "info"));
            infoCount += c;
        }

    } catch (Exception e) {
        e.printStackTrace();
    }

    int totalCount = criticalCount + warningCount + infoCount;
%>

<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>Alert Center - IR-AMS</title>

    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.0/css/all.min.css">

    <link rel="stylesheet" href="css/ir-glass.css?v=28000">
    <link rel="stylesheet" href="css/ams-pro.css?v=28000">
    <link rel="stylesheet" href="css/ir-ams-railway-ui.css?v=alert-center-final-1">

    <link rel="stylesheet" href="css/alert_center.css?v=28001">
</head>

<body class="railway-ui">
<div class="app ams-shell">

    <jsp:include page="sidebar.jsp" />

    <main class="main railway-main">
        <jsp:include page="topbar.jsp" />

        <div class="main-scroll-content alert-board">

            <section class="alert-hero">
                <div>
                    <h1>Alert Center</h1>
                    <p>Consolidated real-time risk and action overview for railway asset control.</p>
                </div>

                <div class="alert-total">
                    <strong><%= totalCount %></strong>
                    <span>Total Signals</span>
                </div>
            </section>

            <section class="alert-summary">
                <div class="summary-box danger"><span>Critical</span><strong><%= criticalCount %></strong></div>
                <div class="summary-box warning"><span>Warning</span><strong><%= warningCount %></strong></div>
                <div class="summary-box"><span>Information</span><strong><%= infoCount %></strong></div>
            </section>

            <section class="alert-grid">
                <% for (AlertGroup g : groups) { %>
                    <a class="alert-card <%= safeText(g.severity) %>" href="<%= safeText(g.url) %>">
                        <div>
                            <div class="alert-icon"><i class="fa-solid <%= safeText(g.icon) %>"></i></div>
                            <strong><%= safeText(g.title) %></strong>
                            <span><%= safeText(g.note) %></span>
                        </div>
                        <div class="alert-number"><%= g.count %></div>
                    </a>
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