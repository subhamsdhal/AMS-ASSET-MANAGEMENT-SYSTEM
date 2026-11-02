<%@page contentType="text/html" pageEncoding="UTF-8"%>
<%@page import="java.sql.*"%>
<%@page import="java.util.*"%>
<%@page import="com.mycompany.asset_management_system_ams.DBConnection"%>
<%@page import="com.mycompany.asset_management_system_ams.HtmlEscapeUtil"%>

<%!
    // Was a no-op (returned the raw value unescaped, just with a "-" fallback) -
    // named the same as every other file's real escaping helper, which made it
    // easy to assume this page was already covered like the rest of the app.
    // roleName currently only ever comes from the seeded `roles` table (no
    // reachable UI in this app lets any role create/rename a row there), so this
    // wasn't a live injection path today - fixed anyway for defense in depth and
    // to stop the misleading name from hiding a real gap if a role-management
    // feature is ever added.
    private String safeText(String value) {
        return value == null || value.trim().isEmpty() ? "-" : HtmlEscapeUtil.escape(value);
    }

    private String normalizeRole(String roleName) {
        if (roleName == null) {
            return "";
        }

        return roleName.trim().toUpperCase().replace(" ", "_");
    }

    private boolean isAllowed(String roleName, String moduleKey) {
        String role = normalizeRole(roleName);

        if ("SUPER_ADMIN".equals(role) || "ADMIN".equals(role)) {
            return true;
        }

        if ("ASSET_MANAGER".equals(role)) {
            return moduleKey.equals("DASHBOARD")
                    || moduleKey.equals("ASSETS")
                    || moduleKey.equals("CATEGORIES")
                    || moduleKey.equals("VENDORS")
                    || moduleKey.equals("EMPLOYEES")
                    || moduleKey.equals("REQUESTS")
                    || moduleKey.equals("ALLOCATION")
                    || moduleKey.equals("RETURNS")
                    || moduleKey.equals("MAINTENANCE")
                    || moduleKey.equals("REPORTS")
                    || moduleKey.equals("WARRANTY")
                    || moduleKey.equals("QR_SCANNER");
        }

        if ("DEPARTMENT_HEAD".equals(role)) {
            return moduleKey.equals("DASHBOARD")
                    || moduleKey.equals("ASSETS")
                    || moduleKey.equals("EMPLOYEES")
                    || moduleKey.equals("REQUESTS")
                    || moduleKey.equals("ALLOCATION")
                    || moduleKey.equals("RETURNS")
                    || moduleKey.equals("MAINTENANCE")
                    || moduleKey.equals("REPORTS")
                    || moduleKey.equals("WARRANTY")
                    || moduleKey.equals("QR_SCANNER");
        }

        if ("AUDITOR".equals(role)) {
            return moduleKey.equals("DASHBOARD")
                    || moduleKey.equals("ASSETS")
                    || moduleKey.equals("EMPLOYEES")
                    || moduleKey.equals("REPORTS")
                    || moduleKey.equals("WARRANTY")
                    || moduleKey.equals("AUDIT_LOGS")
                    || moduleKey.equals("ACCESS_MATRIX")
                    || moduleKey.equals("QR_SCANNER")
                    || moduleKey.equals("SETTINGS");
        }

        if ("EMPLOYEE".equals(role)) {
            return moduleKey.equals("DASHBOARD")
                    || moduleKey.equals("ASSETS")
                    || moduleKey.equals("REQUESTS")
                    || moduleKey.equals("RETURNS")
                    || moduleKey.equals("QR_SCANNER");
        }

        return moduleKey.equals("DASHBOARD");
    }

    private String accessBadge(boolean allowed) {
        if (allowed) {
            return "<span class='matrix-badge allowed'><i class='fa-solid fa-check'></i> Allowed</span>";
        }

        return "<span class='matrix-badge restricted'><i class='fa-solid fa-lock'></i> Restricted</span>";
    }

    private String roleIcon(String roleName) {
        String role = normalizeRole(roleName);

        if ("SUPER_ADMIN".equals(role) || "ADMIN".equals(role)) {
            return "fa-user-tie";
        }

        if ("ASSET_MANAGER".equals(role)) {
            return "fa-boxes-stacked";
        }

        if ("DEPARTMENT_HEAD".equals(role)) {
            return "fa-user-shield";
        }

        if ("AUDITOR".equals(role)) {
            return "fa-clipboard-check";
        }

        if ("EMPLOYEE".equals(role)) {
            return "fa-user";
        }

        return "fa-circle-user";
    }

    private String roleDescription(String roleName) {
        String role = normalizeRole(roleName);

        if ("SUPER_ADMIN".equals(role) || "ADMIN".equals(role)) {
            return "Complete administrative control including users, settings, backup, restore and audit supervision.";
        }

        if ("ASSET_MANAGER".equals(role)) {
            return "Operational control over assets, vendors, categories, allocations, returns, maintenance and reports.";
        }

        if ("DEPARTMENT_HEAD".equals(role)) {
            return "Department-level visibility for assets, employees, requests, allocation, maintenance and reports.";
        }

        if ("AUDITOR".equals(role)) {
            return "Read-focused compliance access for reports, audit logs, warranty tracking and access matrix review.";
        }

        if ("EMPLOYEE".equals(role)) {
            return "Limited self-service access for dashboard, asset view, requests, returns and QR scanner.";
        }

        return "Basic system access configured with limited module visibility.";
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

    if (!("SUPER_ADMIN".equals(role) || "ADMIN".equals(role)) && !"AUDITOR".equals(role)) {
        response.sendRedirect("settings.jsp?access=denied");
        return;
    }

    List<Map<String, String>> roleList = new ArrayList<>();

    Connection con = null;
    PreparedStatement ps = null;
    ResultSet rs = null;

    try {
        con = DBConnection.getConnection();

        ps = con.prepareStatement(
                "SELECT r.role_name, COUNT(u.user_id) AS user_count "
                + "FROM roles r "
                + "LEFT JOIN users u ON r.role_id = u.role_id "
                + "GROUP BY r.role_id, r.role_name "
                + "ORDER BY r.role_id ASC"
        );

        rs = ps.executeQuery();

        while (rs.next()) {
            Map<String, String> roleMap = new LinkedHashMap<>();
            roleMap.put("roleName", rs.getString("role_name"));
            roleMap.put("userCount", String.valueOf(rs.getInt("user_count")));

            roleList.add(roleMap);
        }

    } catch (Exception e) {
        e.printStackTrace();
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
            ex.printStackTrace();
        }
    }

    if (roleList.isEmpty()) {
        String[] fallbackRoles = {
            "SUPER_ADMIN",
            "ADMIN",
            "ASSET_MANAGER",
            "DEPARTMENT_HEAD",
            "AUDITOR",
            "EMPLOYEE"
        };

        for (String fallbackRole : fallbackRoles) {
            Map<String, String> roleMap = new LinkedHashMap<>();
            roleMap.put("roleName", fallbackRole);
            roleMap.put("userCount", "0");

            roleList.add(roleMap);
        }
    }

    String[][] modules = {
        {"DASHBOARD", "Dashboard", "fa-house"},
        {"ASSETS", "Assets", "fa-laptop"},
        {"CATEGORIES", "Categories", "fa-layer-group"},
        {"VENDORS", "Vendors", "fa-truck-field"},
        {"EMPLOYEES", "Employees", "fa-users"},
        {"REQUESTS", "Requests", "fa-file-circle-plus"},
        {"ALLOCATION", "Allocation", "fa-arrows-rotate"},
        {"RETURNS", "Returns", "fa-rotate-left"},
        {"MAINTENANCE", "Maintenance", "fa-screwdriver-wrench"},
        {"REPORTS", "Reports", "fa-chart-pie"},
        {"WARRANTY", "Warranty", "fa-shield-halved"},
        {"QR_SCANNER", "QR Scanner", "fa-qrcode"},
        {"AUDIT_LOGS", "Audit Logs", "fa-clipboard-list"},
        {"ACCESS_MATRIX", "Access Matrix", "fa-user-shield"},
        {"BACKUP_RESTORE", "Backup Restore", "fa-database"},
        {"DB_STATUS", "DB Status", "fa-server"},
        {"SETTINGS", "Settings", "fa-gear"}
    };

    int totalRoles = roleList.size();
    int totalModules = modules.length;
    int totalRules = totalRoles * totalModules;
    int allowedRules = 0;

    for (Map<String, String> roleMap : roleList) {
        String matrixRoleName = roleMap.get("roleName");

        for (String[] module : modules) {
            if (isAllowed(matrixRoleName, module[0])) {
                allowedRules++;
            }
        }
    }

    int restrictedRules = totalRules - allowedRules;
%>

<!DOCTYPE html>
<html>
<head>
    <title>IR-AMS Access Matrix</title>

    <link rel="stylesheet"
          href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.0/css/all.min.css">

    <link rel="stylesheet" href="css/ir-glass.css?v=5000">

    <link rel="stylesheet" href="css/access_matrix.css?v=28001">
</head>

<body>

<div class="app">

    <jsp:include page="sidebar.jsp" />

    <main class="main">

        <jsp:include page="topbar.jsp" />

        <div class="main-scroll-content">

            <section class="asset-hero">
                <h1>Role Access Matrix</h1>

                <p>
                    Review role-wise authorization for all IR-AMS modules including asset operations,
                    reports, warranty tracking, audit logs, system settings, database status and backup/restore.
                </p>

                <br>

                <div class="hero-pills">
                    <div class="hero-pill">
                        <i class="fa-solid fa-user-shield"></i> RBAC Control
                    </div>

                    <div class="hero-pill">
                        <i class="fa-solid fa-lock"></i> Permission Audit
                    </div>

                    <div class="hero-pill">
                        <i class="fa-solid fa-eye"></i> Readable Matrix
                    </div>

                    <div class="hero-pill">
                        <i class="fa-solid fa-shield-halved"></i> Compliance Ready
                    </div>
                </div>
            </section>

            <section class="matrix-kpi-grid">

                <div class="matrix-kpi-card">
                    <i class="fa-solid fa-users-gear"></i>
                    <span>Total Roles</span>
                    <strong><%= totalRoles %></strong>
                </div>

                <div class="matrix-kpi-card">
                    <i class="fa-solid fa-table-cells-large"></i>
                    <span>Total Modules</span>
                    <strong><%= totalModules %></strong>
                </div>

                <div class="matrix-kpi-card">
                    <i class="fa-solid fa-circle-check"></i>
                    <span>Allowed Rules</span>
                    <strong><%= allowedRules %></strong>
                </div>

                <div class="matrix-kpi-card">
                    <i class="fa-solid fa-lock"></i>
                    <span>Restricted Rules</span>
                    <strong><%= restrictedRules %></strong>
                </div>

            </section>

            <section class="glass-panel">

                <div class="registry-toolbar">
                    <div>
                        <h2>Role Summary</h2>
                        <p class="table-subtext">
                            Current system roles with assigned user count and access responsibility.
                        </p>
                    </div>

                    <div class="registry-actions">
                        <a href="ams_copilot.jsp"><i class="fa-solid fa-robot"></i> AI Copilot</a>
              <a href="settings.jsp" class="btn secondary-btn">
                            <i class="fa-solid fa-arrow-left"></i>
                            Back to Settings
                        </a>
                    </div>
                </div>

                <div class="role-card-grid">

                    <%
                        for (Map<String, String> roleMap : roleList) {
                            String matrixRoleName = safeText(roleMap.get("roleName"));
                            String userCount = safeText(roleMap.get("userCount"));
                    %>

                    <div class="role-card">
                        <div class="role-card-head">
                            <div class="role-card-icon">
                                <i class="fa-solid <%= roleIcon(matrixRoleName) %>"></i>
                            </div>

                            <div>
                                <h3><%= matrixRoleName.replace("_", " ") %></h3>
                                <small><%= userCount %> user(s)</small>
                            </div>
                        </div>

                        <p><%= roleDescription(matrixRoleName) %></p>
                    </div>

                    <%
                        }
                    %>

                </div>

            </section>

            <br>

            <section class="glass-panel">

                <div class="registry-toolbar">
                    <div>
                        <h2>Permission Matrix</h2>
                        <p class="table-subtext">
                            Allowed and restricted module access by user role.
                        </p>
                    </div>

                    <div class="registry-actions">
                        <span class="matrix-badge allowed">
                            <i class="fa-solid fa-check"></i>
                            Allowed
                        </span>

                        <span class="matrix-badge restricted">
                            <i class="fa-solid fa-lock"></i>
                            Restricted
                        </span>
                    </div>
                </div>

                <div class="matrix-scroll">
                    <table class="matrix-table">
                        <thead>
                            <tr>
                                <th class="matrix-role-cell">Role</th>

                                <%
                                    for (String[] module : modules) {
                                %>
                                    <th>
                                        <i class="fa-solid <%= module[2] %>"></i>
                                        <br>
                                        <%= module[1] %>
                                    </th>
                                <%
                                    }
                                %>
                            </tr>
                        </thead>

                        <tbody>
                            <%
                                for (Map<String, String> roleMap : roleList) {
                                    String matrixRoleName = safeText(roleMap.get("roleName"));
                                    String userCount = safeText(roleMap.get("userCount"));
                            %>

                            <tr>
                                <td class="matrix-role-cell">
                                    <div class="matrix-role-main">
                                        <i class="fa-solid <%= roleIcon(matrixRoleName) %>"></i>

                                        <div>
                                            <strong><%= matrixRoleName.replace("_", " ") %></strong>
                                            <span><%= userCount %> user(s)</span>
                                        </div>
                                    </div>
                                </td>

                                <%
                                    for (String[] module : modules) {
                                        boolean allowed = isAllowed(matrixRoleName, module[0]);
                                %>
                                    <td>
                                        <%= accessBadge(allowed) %>
                                    </td>
                                <%
                                    }
                                %>
                            </tr>

                            <%
                                }
                            %>
                        </tbody>
                    </table>
                </div>

            </section>

            <br>

            <section class="glass-panel">

                <div class="registry-toolbar">
                    <div>
                        <h2>Access Policy Notes</h2>
                        <p class="table-subtext">
                            Security interpretation used by the IR-AMS role-based access model.
                        </p>
                    </div>
                </div>

                <div class="policy-note-grid">

                    <div class="policy-note">
                        <h3>
                            <i class="fa-solid fa-user-tie"></i>
                            Super Admin Control
                        </h3>

                        <p>
                            Super Admin has complete system control including role management,
                            audit logs, backup/restore, database health and all operational modules.
                        </p>
                    </div>

                    <div class="policy-note">
                        <h3>
                            <i class="fa-solid fa-boxes-stacked"></i>
                            Asset Operations
                        </h3>

                        <p>
                            Asset Manager controls asset lifecycle operations such as registration,
                            categorization, vendor mapping, allocation, return, maintenance and reports.
                        </p>
                    </div>

                    <div class="policy-note">
                        <h3>
                            <i class="fa-solid fa-clipboard-check"></i>
                            Audit Compliance
                        </h3>

                        <p>
                            Auditor receives controlled read/compliance access to reports, warranty tracking,
                            audit logs and access matrix without backup/restore privilege.
                        </p>
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
<script src="js/sidebar-role.js?v=10000"></script>

</body>
</html>