<%@page contentType="text/html" pageEncoding="UTF-8"%>
<%@page import="java.util.Locale"%>

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

    boolean isSuperAdmin = ("SUPER_ADMIN".equals(role) || "ADMIN".equals(role));

    if (!isSuperAdmin) {
        response.sendRedirect("dashboard.jsp?access=denied");
        return;
    }

    String userInitial = username.substring(0, Math.min(2, username.length())).toUpperCase(Locale.ENGLISH);
    String error = request.getParameter("error");
    String message = request.getParameter("msg");
    String restoredCount = request.getParameter("count");
    String alertType = "";
    String alertMessage = "";

    if ("restored".equalsIgnoreCase(message)) {
        alertType = "success";
        alertMessage = "Database restore completed successfully. Executed statements: " + safeText(restoredCount);
    } else if ("confirm".equalsIgnoreCase(error)) {
        alertType = "error";
        alertMessage = "Restore was blocked because the confirmation phrase did not match.";
    } else if ("nofile".equalsIgnoreCase(error)) {
        alertType = "error";
        alertMessage = "Please select a SQL backup file before restoring.";
    } else if ("invalid".equalsIgnoreCase(error)) {
        alertType = "error";
        alertMessage = "Only trusted .sql backup files can be restored.";
    } else if ("db".equalsIgnoreCase(error)) {
        alertType = "error";
        alertMessage = "Database connection is not available. Check db.properties or AMS_DB_* environment variables.";
    } else if ("server".equalsIgnoreCase(error)) {
        alertType = "error";
        alertMessage = "Restore failed. Check the server log, then verify database status before retrying.";
    }
%>

<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>Backup & Restore - IR-AMS</title>

    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.0/css/all.min.css">

    <link rel="stylesheet" href="css/ir-glass.css?v=28000">
    <link rel="stylesheet" href="css/ams-pro.css?v=28000">
    <link rel="stylesheet" href="css/ir-ams-railway-ui.css?v=backup-restore-final-1">

    <link rel="stylesheet" href="css/backup_restore.css?v=28001">
</head>

<body class="railway-ui">
<div class="app ams-shell">

    <jsp:include page="sidebar.jsp" />

    <main class="main railway-main">
        <jsp:include page="topbar.jsp" />

        <div class="main-scroll-content backup-board">

            <% if (!alertMessage.isEmpty()) { %>
                <section class="backup-alert <%= safeText(alertType) %>">
                    <%= alertMessage %>
                </section>
            <% } %>

            <section class="backup-hero">
                <div>
                    <h1>Backup & Restore Console</h1>
                    <p>
                        Super Admin controlled database backup panel for Railway Asset Management System.
                        Backup is available directly as SQL export. Restore is intentionally restricted for safety.
                    </p>
                </div>

                <div class="secure-pill">
                    <i class="fa-solid fa-lock"></i>
                    Secure Area
                </div>
            </section>

            <section class="backup-grid">
                <a class="backup-card" href="BackupDatabaseServlet">
                    <div>
                        <i class="fa-solid fa-database"></i>
                        <strong>Download Full SQL Backup</strong>
                        <span>Exports all available database tables with CREATE TABLE and INSERT statements.</span>
                    </div>
                    <span>Click to download .sql</span>
                </a>

                <a class="backup-card" href="reports.jsp">
                    <div>
                        <i class="fa-solid fa-file-excel"></i>
                        <strong>Operational Reports Backup</strong>
                        <span>Open report module and export official asset, allocation, maintenance and verification registers.</span>
                    </div>
                    <span>Open reports</span>
                </a>

                <a class="backup-card" href="db_status.jsp">
                    <div>
                        <i class="fa-solid fa-heart-pulse"></i>
                        <strong>Check Database Health</strong>
                        <span>Verify connection, table availability, row counts and recent audit activity before backup.</span>
                    </div>
                    <span>Open status</span>
                </a>
            </section>

            <section class="warning-box">
                <strong>Restore Safety Rule:</strong>
                Restore can overwrite live railway records. Download a fresh backup first, restore only a trusted SQL file,
                and type the exact confirmation phrase before submitting.
            </section>

            <section class="backup-panel">
                <h2>Restore Trusted SQL Backup</h2>

                <form class="restore-form"
                      method="post"
                      action="RestoreDatabaseServlet"
                      enctype="multipart/form-data"
                      onsubmit="return confirm('Restore this SQL backup now? Existing Railway AMS data may be overwritten.');">
                    <div>
                        <label for="backupFile">SQL Backup File</label>
                        <input type="file" id="backupFile" name="backupFile" accept=".sql" required>
                    </div>

                    <div>
                        <label for="restoreConfirmation">Type RESTORE RAILWAY AMS</label>
                        <input type="text"
                               id="restoreConfirmation"
                               name="restoreConfirmation"
                               autocomplete="off"
                               placeholder="RESTORE RAILWAY AMS"
                               required>
                    </div>

                    <button class="restore-submit" type="submit">
                        <i class="fa-solid fa-triangle-exclamation"></i>
                        Restore SQL
                    </button>
                </form>
            </section>

            <section class="backup-panel">
                <h2>Recommended Restore Procedure</h2>

                <ol class="backup-list">
                    <li>Download fresh SQL backup from this page.</li>
                    <li>Verify the backup file name, date and database name.</li>
                    <li>Stop user operations temporarily during restore.</li>
                    <li>Restore using MySQL Workbench or approved server command.</li>
                    <li>Run database status check from <strong>db_status.jsp</strong>.</li>
                    <li>Login and verify dashboard, assets, allocation, maintenance and reports.</li>
                </ol>
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
