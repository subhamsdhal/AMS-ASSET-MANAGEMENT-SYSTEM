<%@page contentType="text/html" pageEncoding="UTF-8"%>
<%@page import="com.mycompany.asset_management_system_ams.DBConnection"%>
<%@page import="java.sql.*"%>
<%@page import="java.util.*"%>

<%!
    private String safeText(Object value) {
        if (value == null || String.valueOf(value).trim().isEmpty()) {
            return "N/A";
        }

        return String.valueOf(value).trim()
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
                out.append(Character.toUpperCase(part.charAt(0)))
                        .append(part.substring(1))
                        .append(" ");
            }
        }

        return out.toString().trim();
    }

    private String rowValue(Map<String, String> row, String key) {
        if (row == null) {
            return "";
        }

        String value = row.get(key);
        return value == null ? "" : value;
    }

    private Map<String, String> singleRow(String sql, String id) {
        Map<String, String> row = new HashMap<String, String>();

        try (Connection con = DBConnection.getConnection();
             PreparedStatement ps = con.prepareStatement(sql)) {

            ps.setString(1, id);

            try (ResultSet rs = ps.executeQuery()) {
                ResultSetMetaData meta = rs.getMetaData();
                int count = meta.getColumnCount();

                if (rs.next()) {
                    for (int i = 1; i <= count; i++) {
                        row.put(meta.getColumnLabel(i), rs.getString(i));
                    }
                }
            }

        } catch (Exception e) {
            e.printStackTrace();
        }

        return row;
    }

    private String actionBadgeClass(String action) {
        if (action == null) {
            return "neutral";
        }

        String a = action.trim().toUpperCase(Locale.ENGLISH);

        if (a.contains("DELETE_BLOCKED")
                || a.contains("BLOCKED")
                || a.contains("DENIED")) {
            return "blocked";
        }

        if (a.contains("DELETE")
                || a.contains("REMOVE")
                || a.contains("DISPOSE")
                || a.contains("REJECT")) {
            return "danger";
        }

        if (a.contains("UPDATE")
                || a.contains("EDIT")
                || a.contains("CHANGE")
                || a.contains("MODIFY")
                || a.contains("SCHEDULE")) {
            return "warning";
        }

        if (a.contains("ADD")
                || a.contains("CREATE")
                || a.contains("INSERT")
                || a.contains("SAVE")
                || a.contains("SUBMIT")) {
            return "success";
        }

        if (a.contains("EXPORT")
                || a.contains("REPORT")
                || a.contains("DOWNLOAD")) {
            return "info";
        }

        return "neutral";
    }

    private String actionIcon(String action) {
        if (action == null) {
            return "fa-solid fa-clipboard-check";
        }

        String a = action.trim().toUpperCase(Locale.ENGLISH);

        if (a.contains("EXPORT") || a.contains("REPORT")) {
            return "fa-solid fa-file-export";
        }

        if (a.contains("DELETE") || a.contains("DISPOSE")) {
            return "fa-solid fa-trash";
        }

        if (a.contains("UPDATE") || a.contains("EDIT") || a.contains("CHANGE")) {
            return "fa-solid fa-pen-to-square";
        }

        if (a.contains("ADD") || a.contains("CREATE") || a.contains("SAVE") || a.contains("SUBMIT")) {
            return "fa-solid fa-circle-plus";
        }

        if (a.contains("LOGIN")) {
            return "fa-solid fa-right-to-bracket";
        }

        if (a.contains("LOGOUT")) {
            return "fa-solid fa-right-from-bracket";
        }

        if (a.contains("BLOCKED") || a.contains("DENIED")) {
            return "fa-solid fa-ban";
        }

        if (a.contains("SCHEDULE")) {
            return "fa-regular fa-calendar-check";
        }

        return "fa-solid fa-clipboard-check";
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

    boolean allowed = ("SUPER_ADMIN".equals(role) || "ADMIN".equals(role))
            || "AUDITOR".equalsIgnoreCase(role);

    if (!allowed) {
        response.sendRedirect("dashboard.jsp?access=denied");
        return;
    }

    String auditId = request.getParameter("id");

    if (auditId == null || auditId.trim().isEmpty()) {
        auditId = request.getParameter("audit_id");
    }

    if (auditId == null || auditId.trim().isEmpty()) {
        response.sendRedirect("audit_logs.jsp?error=invalid");
        return;
    }

    auditId = auditId.trim();

    String userInitial = username.substring(0, Math.min(2, username.length())).toUpperCase(Locale.ENGLISH);

    Map<String, String> audit = singleRow(
            "SELECT "
            + "audit_id, "
            + "user_id, "
            + "COALESCE(username, 'System') AS username, "
            + "COALESCE(user_role, 'SYSTEM') AS user_role, "
            + "COALESCE(module_name, 'SYSTEM') AS module_name, "
            + "COALESCE(action_type, 'GENERAL_ACTION') AS action_type, "
            + "COALESCE(record_id, '') AS record_id, "
            + "COALESCE(action_details, '') AS action_details, "
            + "COALESCE(ip_address, '') AS ip_address, "
            + "COALESCE(user_agent, '') AS user_agent, "
            + "DATE_FORMAT(created_at, '%d %b %Y, %h:%i %p') AS created_at "
            + "FROM audit_logs "
            + "WHERE audit_id = ? "
            + "LIMIT 1",
            auditId
    );

    if (audit.isEmpty()) {
        response.sendRedirect("audit_logs.jsp?error=notfound");
        return;
    }

    String actionType = rowValue(audit, "action_type");
    String badgeClass = actionBadgeClass(actionType);
%>

<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>Audit Log Details - IR-AMS</title>

    <link rel="stylesheet"
          href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.0/css/all.min.css">

    <link rel="stylesheet" href="css/ir-glass.css?v=28000">
    <link rel="stylesheet" href="css/ams-pro.css?v=28000">
    <link rel="stylesheet" href="css/ir-ams-railway-ui.css?v=28000">

    <link rel="stylesheet" href="css/view_audit_log.css?v=28000">
</head>

<body class="railway-ui">
<div class="app ams-shell">

    <jsp:include page="sidebar.jsp" />

    <main class="main railway-main">

        <jsp:include page="topbar.jsp" />

        <div class="main-scroll-content detail-board">

            <section class="detail-hero">
                <div>
                    <h1>Audit Log #<%= safeText(rowValue(audit, "audit_id")) %></h1>

                    <p>
                        <strong><%= safeText(cleanLabel(rowValue(audit, "module_name"))) %></strong>
                        · <%= safeText(cleanLabel(rowValue(audit, "action_type"))) %>
                        · <%= safeText(rowValue(audit, "created_at")) %>
                    </p>
                </div>

                <div class="hero-actions">
                    <span class="status-pill <%= badgeClass %>">
                        <i class="<%= actionIcon(actionType) %>"></i>
                        <%= safeText(cleanLabel(actionType)) %>
                    </span>

                    <a href="audit_logs.jsp" class="audit-btn secondary">
                        <i class="fa-solid fa-arrow-left"></i>
                        Back
                    </a>

                    <a href="export_audit_logs.jsp" class="audit-btn">
                        <i class="fa-solid fa-file-excel"></i>
                        Export
                    </a>
                </div>
            </section>

            <section class="summary-grid">
                <div class="summary-card">
                    <span>User</span>
                    <strong><%= safeText(rowValue(audit, "username")) %></strong>
                </div>

                <div class="summary-card">
                    <span>Role</span>
                    <strong><%= safeText(cleanLabel(rowValue(audit, "user_role"))) %></strong>
                </div>

                <div class="summary-card">
                    <span>Module</span>
                    <strong><%= safeText(cleanLabel(rowValue(audit, "module_name"))) %></strong>
                </div>

                <div class="summary-card">
                    <span>Action</span>
                    <strong><%= safeText(cleanLabel(actionType)) %></strong>
                </div>
            </section>


            <section class="detail-panel">
                <div class="panel-title-row">
                    <h2 class="panel-title">Complete Audit Details</h2>
                </div>

                <table class="detail-table">
                    <tr>
                        <th>Audit ID</th>
                        <td><%= safeText(rowValue(audit, "audit_id")) %></td>
                    </tr>

                    <tr>
                        <th>User ID</th>
                        <td><%= safeText(rowValue(audit, "user_id")) %></td>
                    </tr>

                    <tr>
                        <th>Username</th>
                        <td><%= safeText(rowValue(audit, "username")) %></td>
                    </tr>

                    <tr>
                        <th>User Role</th>
                        <td><%= safeText(cleanLabel(rowValue(audit, "user_role"))) %></td>
                    </tr>

                    <tr>
                        <th>Module</th>
                        <td><%= safeText(cleanLabel(rowValue(audit, "module_name"))) %></td>
                    </tr>

                    <tr>
                        <th>Action Type</th>
                        <td><%= safeText(cleanLabel(actionType)) %></td>
                    </tr>

                    <tr>
                        <th>Record ID</th>
                        <td><%= safeText(rowValue(audit, "record_id")) %></td>
                    </tr>

                    <tr>
                        <th>IP Address</th>
                        <td><%= safeText(rowValue(audit, "ip_address")) %></td>
                    </tr>

                    <tr>
                        <th>User Agent</th>
                        <td><%= safeText(rowValue(audit, "user_agent")) %></td>
                    </tr>

                    <tr>
                        <th>Created On</th>
                        <td><%= safeText(rowValue(audit, "created_at")) %></td>
                    </tr>

                    <tr>
                        <th>Action Details</th>
                        <td><%= safeText(rowValue(audit, "action_details")) %></td>
                    </tr>
                </table>
            </section>

        </div>
    </main>
</div>

<script src="js/topbar-search.js?v=28000"></script>
<script src="js/user-dropdown.js?v=28000"></script>
<script src="js/sidebar-role.js?v=28000"></script>
<script src="js/ir-body-watermark.js?v=28000"></script>
<script src="js/dashboard-actions.js?v=28000"></script>

</body>
</html>