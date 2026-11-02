<%@page contentType="text/html" pageEncoding="UTF-8"%>
<%@page import="com.mycompany.asset_management_system_ams.DBConnection"%>
<%@page import="java.sql.*"%>
<%@page import="java.util.*"%>

<%!
    private String safeText(String value) {
        if (value == null || value.trim().isEmpty()) {
            return "N/A";
        }

        return value.trim()
                .replace("&", "&amp;")
                .replace("<", "&lt;")
                .replace(">", "&gt;")
                .replace("\"", "&quot;")
                .replace("'", "&#39;");
    }

    private String cleanLabel(String value) {
        if (value == null || value.trim().isEmpty()) {
            return "N/A";
        }

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
                if (rs.next()) {
                    return rs.getInt(1) > 0;
                }
            }

        } catch (Exception e) {
            e.printStackTrace();
        }

        return false;
    }

    private boolean columnExists(Connection con, String tableName, String columnName) {
        String sql = "SELECT COUNT(*) FROM information_schema.columns WHERE table_schema = DATABASE() AND table_name = ? AND column_name = ?";

        try (PreparedStatement ps = con.prepareStatement(sql)) {
            ps.setString(1, tableName);
            ps.setString(2, columnName);

            try (ResultSet rs = ps.executeQuery()) {
                if (rs.next()) {
                    return rs.getInt(1) > 0;
                }
            }

        } catch (Exception e) {
            e.printStackTrace();
        }

        return false;
    }

    private int rowCount(Connection con, String tableName) {
        if (!tableExists(con, tableName)) {
            return -1;
        }

        String sql = "SELECT COUNT(*) FROM `" + tableName.replace("`", "``") + "`";

        try (Statement st = con.createStatement();
             ResultSet rs = st.executeQuery(sql)) {

            if (rs.next()) {
                return rs.getInt(1);
            }

        } catch (Exception e) {
            e.printStackTrace();
        }

        return -1;
    }

    private String singleValue(Connection con, String sql) {
        try (Statement st = con.createStatement();
             ResultSet rs = st.executeQuery(sql)) {

            if (rs.next()) {
                String value = rs.getString(1);
                return value == null ? "" : value;
            }

        } catch (Exception e) {
            e.printStackTrace();
        }

        return "";
    }

    private int sqlInt(Connection con, String sql) {
        try (PreparedStatement ps = con.prepareStatement(sql);
             ResultSet rs = ps.executeQuery()) {

            if (rs.next()) {
                return rs.getInt(1);
            }

        } catch (Exception e) {
            e.printStackTrace();
        }

        return 0;
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

    boolean allowed = ("SUPER_ADMIN".equals(role) || "ADMIN".equals(role)) || "ASSET_MANAGER".equals(role) || "AUDITOR".equals(role);

    if (!allowed) {
        response.sendRedirect("dashboard.jsp?access=denied");
        return;
    }

    String userInitial = username.substring(0, Math.min(2, username.length())).toUpperCase(Locale.ENGLISH);

    boolean connectionOk = false;
    String dbName = "N/A";
    String dbVersion = "N/A";
    String dbUser = "N/A";
    String driverName = "N/A";
    String driverVersion = "N/A";
    String dbUrl = "N/A";
    String dbMode = DBConnection.isLocalDatabase() ? "LOCAL MySQL" : "CLOUD / REMOTE DB";
    String errorMessage = "";
    int publicSnapshotRows = 0;
    int pendingQrSyncRows = 0;
    int failedQrSyncRows = 0;

    LinkedHashMap<String, Integer> tableCounts = new LinkedHashMap<String, Integer>();
    ArrayList<String[]> recentAuditRows = new ArrayList<String[]>();

    String[] coreTables = {
        "users",
        "roles",
        "departments",
        "employees",
        "asset_categories",
        "vendors",
        "assets",
        "asset_allocation",
        "asset_returns",
        "maintenance_logs",
        "asset_requests",
        "physical_verification",
        "asset_physical_verification",
        "asset_disposal",
        "asset_documents",
        "asset_qr_scan_logs",
        "asset_qr_tagging_status",
        "asset_qr_token_history",
        "public_asset_snapshot",
        "qr_sync_queue",
        "railway_zones",
        "railway_divisions",
        "railway_locations",
        "audit_logs"
    };

    try (Connection con = DBConnection.getConnection()) {
        connectionOk = con != null && !con.isClosed();

        if (connectionOk) {
            DatabaseMetaData meta = con.getMetaData();

            dbName = singleValue(con, "SELECT DATABASE()");
            dbVersion = singleValue(con, "SELECT VERSION()");
            dbUser = singleValue(con, "SELECT USER()");

            driverName = meta.getDriverName();
            driverVersion = meta.getDriverVersion();
            dbUrl = DBConnection.getMaskedDbUrl();

            for (String tableName : coreTables) {
                tableCounts.put(tableName, rowCount(con, tableName));
            }

            if (tableExists(con, "public_asset_snapshot")) {
                publicSnapshotRows = rowCount(con, "public_asset_snapshot");
            }

            if (tableExists(con, "qr_sync_queue")) {
                pendingQrSyncRows = sqlInt(con, "SELECT COUNT(*) FROM qr_sync_queue WHERE sync_status IN ('PENDING','PROCESSING')");
                failedQrSyncRows = sqlInt(con, "SELECT COUNT(*) FROM qr_sync_queue WHERE sync_status = 'FAILED'");
            }

            if (tableExists(con, "audit_logs")) {
                boolean newAudit = columnExists(con, "audit_logs", "module_name");
                boolean oldAudit = columnExists(con, "audit_logs", "table_name");

                if (newAudit) {
                    String sql = "SELECT username, module_name, action_type, DATE_FORMAT(created_at, '%d %b %Y, %h:%i %p') AS created_at "
                            + "FROM audit_logs ORDER BY audit_id DESC LIMIT 8";

                    try (Statement st = con.createStatement();
                         ResultSet rs = st.executeQuery(sql)) {

                        while (rs.next()) {
                            recentAuditRows.add(new String[]{
                                rs.getString("username"),
                                rs.getString("module_name"),
                                rs.getString("action_type"),
                                rs.getString("created_at")
                            });
                        }
                    }

                } else if (oldAudit) {
                    String sql = "SELECT 'System' AS username, table_name, action, DATE_FORMAT(action_time, '%d %b %Y, %h:%i %p') AS action_time "
                            + "FROM audit_logs ORDER BY audit_id DESC LIMIT 8";

                    try (Statement st = con.createStatement();
                         ResultSet rs = st.executeQuery(sql)) {

                        while (rs.next()) {
                            recentAuditRows.add(new String[]{
                                rs.getString("username"),
                                rs.getString("table_name"),
                                rs.getString("action"),
                                rs.getString("action_time")
                            });
                        }
                    }
                }
            }
        }

    } catch (Exception e) {
        connectionOk = false;
        errorMessage = "A database connection error occurred.";
        e.printStackTrace();
    }

    int activeTables = 0;
    int missingTables = 0;
    int totalRows = 0;

    for (Map.Entry<String, Integer> entry : tableCounts.entrySet()) {
        if (entry.getValue() >= 0) {
            activeTables++;
            totalRows += entry.getValue();
        } else {
            missingTables++;
        }
    }
%>

<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>Database Status - IR-AMS</title>

    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.0/css/all.min.css">

    <link rel="stylesheet" href="css/ir-glass.css?v=28000">
    <link rel="stylesheet" href="css/ams-pro.css?v=28000">
    <link rel="stylesheet" href="css/ir-ams-railway-ui.css?v=db-status-final-1">

    <link rel="stylesheet" href="css/db_status.css?v=28001">
</head>

<body class="railway-ui">
<div class="app ams-shell">

    <jsp:include page="sidebar.jsp" />

    <main class="main railway-main">
        <jsp:include page="topbar.jsp" />

        <div class="main-scroll-content status-board">

            <section class="status-hero">
                <div>
                    <h1>Database Status</h1>
                    <p>Live database health, module table availability, row counts, driver details and recent audit activity.</p>
                </div>

                <div class="live-pill <%= connectionOk ? "pill-ok" : "pill-error" %>">
                    <i class="fa-solid <%= connectionOk ? "fa-circle-check" : "fa-circle-xmark" %>"></i>
                    <%= connectionOk ? "Connected" : "Offline" %>
                </div>
            </section>

            <% if (!connectionOk) { %>
                <div class="error-box">
                    <strong>Connection Error:</strong>
                    <%= safeText(errorMessage) %>
                </div>
            <% } %>

            <section class="status-grid">
                <div class="status-card">
                    <span>Database</span>
                    <strong><%= safeText(dbName) %></strong>
                </div>

                <div class="status-card">
                    <span>Connection Type</span>
                    <strong><%= safeText(dbMode) %></strong>
                </div>

                <div class="status-card">
                    <span>Active Tables</span>
                    <strong><%= activeTables %></strong>
                </div>

                <div class="status-card">
                    <span>Total Rows</span>
                    <strong><%= totalRows %></strong>
                </div>

                <div class="status-card">
                    <span>Missing Tables</span>
                    <strong><%= missingTables %></strong>
                </div>

                <div class="status-card">
                    <span>MySQL Version</span>
                    <strong><%= safeText(dbVersion) %></strong>
                </div>

                <div class="status-card">
                    <span>Database User</span>
                    <strong><%= safeText(dbUser) %></strong>
                </div>

                <div class="status-card">
                    <span>JDBC Driver</span>
                    <strong><%= safeText(driverName) %></strong>
                </div>

                <div class="status-card">
                    <span>Driver Version</span>
                    <strong><%= safeText(driverVersion) %></strong>
                </div>

                <div class="status-card">
                    <span>Public QR Snapshots</span>
                    <strong><%= publicSnapshotRows %></strong>
                </div>

                <div class="status-card">
                    <span>QR Sync Pending</span>
                    <strong><%= pendingQrSyncRows %></strong>
                </div>

                <div class="status-card">
                    <span>QR Sync Failed</span>
                    <strong><%= failedQrSyncRows %></strong>
                </div>
            </section>

            <section class="status-panel">
                <h2>Core Module Table Status</h2>

                <table class="status-table">
                    <thead>
                        <tr>
                            <th>Table</th>
                            <th>Status</th>
                            <th>Rows</th>
                        </tr>
                    </thead>

                    <tbody>
                        <% for (Map.Entry<String, Integer> entry : tableCounts.entrySet()) { %>
                            <tr>
                                <td><%= safeText(entry.getKey()) %></td>
                                <td>
                                    <% if (entry.getValue() >= 0) { %>
                                        <span class="table-ok">Available</span>
                                    <% } else { %>
                                        <span class="table-missing">Missing</span>
                                    <% } %>
                                </td>
                                <td><%= entry.getValue() >= 0 ? entry.getValue() : 0 %></td>
                            </tr>
                        <% } %>
                    </tbody>
                </table>
            </section>

            <section class="status-panel">
                <h2>Recent Audit Activity</h2>

                <table class="status-table">
                    <thead>
                        <tr>
                            <th>User</th>
                            <th>Module</th>
                            <th>Action</th>
                            <th>Time</th>
                        </tr>
                    </thead>

                    <tbody>
                        <% if (recentAuditRows.isEmpty()) { %>
                            <tr>
                                <td colspan="4">No recent audit activity found.</td>
                            </tr>
                        <% } else {
                            for (String[] row : recentAuditRows) {
                        %>
                            <tr>
                                <td><%= safeText(row[0]) %></td>
                                <td><%= safeText(row[1]) %></td>
                                <td><%= safeText(cleanLabel(row[2])) %></td>
                                <td><%= safeText(row[3]) %></td>
                            </tr>
                        <%  }
                        } %>
                    </tbody>
                </table>
            </section>

            <section class="status-panel">
                <h2>Connection URL</h2>
                <table class="status-table">
                    <tr>
                        <th>JDBC URL</th>
                        <td><%= safeText(dbUrl) %></td>
                    </tr>
                </table>
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
