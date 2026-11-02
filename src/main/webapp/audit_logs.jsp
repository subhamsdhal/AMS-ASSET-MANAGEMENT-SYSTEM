<%@page contentType="text/html" pageEncoding="UTF-8"%>
<%@page import="com.mycompany.asset_management_system_ams.DBConnection"%>
<%@page import="java.sql.*"%>
<%@page import="java.util.*"%>

<%!
    private String safe(Object value) {
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

    private String raw(Object value) {
        if (value == null) {
            return "";
        }

        return String.valueOf(value).trim();
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

    private String shortText(String value, int max) {
        if (value == null || value.trim().isEmpty()) {
            return "N/A";
        }

        String text = value.trim();

        if (text.length() <= max) {
            return text;
        }

        return text.substring(0, max) + "...";
    }

    private String badgeClass(String action) {
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

        if (a.contains("LOGIN")
                || a.contains("LOGOUT")
                || a.contains("VIEW")) {
            return "neutral";
        }

        return "neutral";
    }

    private String iconClass(String action) {
        if (action == null) {
            return "fa-regular fa-circle-dot";
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

    private String rowValue(Map<String, String> row, String key) {
        if (row == null) {
            return "";
        }

        String value = row.get(key);
        return value == null ? "" : value;
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

    boolean canViewAudit = ("SUPER_ADMIN".equals(role) || "ADMIN".equals(role))
            || "AUDITOR".equalsIgnoreCase(role);

    if (!canViewAudit) {
        response.sendRedirect("dashboard.jsp?access=denied");
        return;
    }

    String userInitial = username.substring(0, Math.min(2, username.length())).toUpperCase(Locale.ENGLISH);
    String error = request.getParameter("error");

    int totalLogs = 0;
    int todayLogs = 0;
    int exportLogs = 0;
    int blockedLogs = 0;

    List<Map<String, String>> auditList = new ArrayList<Map<String, String>>();
    Set<String> moduleSet = new TreeSet<String>();
    Set<String> actionSet = new TreeSet<String>();

    try (Connection con = DBConnection.getConnection()) {

        String countSql = "SELECT "
                + "COUNT(*) AS total_logs, "
                + "SUM(CASE WHEN DATE(created_at) = CURDATE() THEN 1 ELSE 0 END) AS today_logs, "
                + "SUM(CASE WHEN UPPER(action_type) LIKE '%EXPORT%' THEN 1 ELSE 0 END) AS export_logs, "
                + "SUM(CASE WHEN UPPER(action_type) LIKE '%BLOCKED%' OR UPPER(action_type) LIKE '%DENIED%' THEN 1 ELSE 0 END) AS blocked_logs "
                + "FROM audit_logs";

        try (PreparedStatement ps = con.prepareStatement(countSql);
             ResultSet rs = ps.executeQuery()) {

            if (rs.next()) {
                totalLogs = rs.getInt("total_logs");
                todayLogs = rs.getInt("today_logs");
                exportLogs = rs.getInt("export_logs");
                blockedLogs = rs.getInt("blocked_logs");
            }
        }

        String sql = "SELECT "
                + "audit_id, "
                + "COALESCE(user_id, '') AS user_id, "
                + "COALESCE(username, 'System') AS username, "
                + "COALESCE(user_role, 'SYSTEM') AS user_role, "
                + "COALESCE(module_name, 'SYSTEM') AS module_name, "
                + "COALESCE(action_type, 'GENERAL_ACTION') AS action_type, "
                + "COALESCE(record_id, '') AS record_id, "
                + "COALESCE(action_details, '') AS action_details, "
                + "COALESCE(ip_address, '') AS ip_address, "
                + "COALESCE(user_agent, '') AS user_agent, "
                + "DATE_FORMAT(created_at, '%d %b %Y, %h:%i %p') AS created_at_display "
                + "FROM audit_logs "
                + "ORDER BY created_at DESC, audit_id DESC "
                + "LIMIT 500";

        try (PreparedStatement ps = con.prepareStatement(sql);
             ResultSet rs = ps.executeQuery()) {

            while (rs.next()) {
                Map<String, String> row = new HashMap<String, String>();

                row.put("audit_id", raw(rs.getObject("audit_id")));
                row.put("user_id", raw(rs.getObject("user_id")));
                row.put("username", raw(rs.getObject("username")));
                row.put("user_role", raw(rs.getObject("user_role")));
                row.put("module_name", raw(rs.getObject("module_name")));
                row.put("action_type", raw(rs.getObject("action_type")));
                row.put("record_id", raw(rs.getObject("record_id")));
                row.put("action_details", raw(rs.getObject("action_details")));
                row.put("ip_address", raw(rs.getObject("ip_address")));
                row.put("user_agent", raw(rs.getObject("user_agent")));
                row.put("created_at_display", raw(rs.getObject("created_at_display")));

                auditList.add(row);

                if (!rowValue(row, "module_name").isEmpty()) {
                    moduleSet.add(rowValue(row, "module_name"));
                }

                if (!rowValue(row, "action_type").isEmpty()) {
                    actionSet.add(rowValue(row, "action_type"));
                }
            }
        }

    } catch (Exception e) {
        e.printStackTrace();
        error = "pageLoadFailed";
    }
%>

<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>Audit - IR-AMS</title>

    <link rel="stylesheet"
          href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.0/css/all.min.css">

    <link rel="stylesheet" href="css/ir-glass.css?v=28000">
    <link rel="stylesheet" href="css/ams-pro.css?v=28000">
    <link rel="stylesheet" href="css/ir-ams-railway-ui.css?v=28000">

<link rel="stylesheet" href="css/audit_logs.css?v=topbarfix1">

        </head>

<body class="railway-ui">
<div class="app ams-shell">

    <jsp:include page="sidebar.jsp" />

    <main class="main railway-main">

        <jsp:include page="topbar.jsp" />

        <div class="main-scroll-content audit-board">

            <% if (error != null && !error.trim().isEmpty()) { %>
                <div class="audit-alert">
                    <i class="fa-solid fa-triangle-exclamation"></i>
                    Unable to load audit page: <%= safe(cleanLabel(error)) %>
                </div>
            <% } %>

            <section class="audit-hero">
                <div>
                    <h1>Audit Trail</h1>

                    <p>
                        Review administrative actions, export history, record changes, blocked attempts,
                        verification actions and system-level activity history.
                    </p>

                    <div class="hero-actions">
                        <span class="audit-pill">
                            <i class="fa-solid fa-circle-check"></i>
                            Audit Logging Active
                        </span>

                        <a href="ams_copilot.jsp" class="audit-btn secondary">
                            <i class="fa-solid fa-robot"></i>
                            AI Copilot
                        </a>

                        <a href="settings.jsp" class="audit-btn secondary">
                            <i class="fa-solid fa-arrow-left"></i>
                            Settings
                        </a>
                    </div>
                </div>
            </section>

            <section class="kpi-grid">
                <div class="kpi-card">
                    <div class="kpi-icon"><i class="fa-solid fa-database"></i></div>
                    <div>
                        <h3>Total Logs</h3>
                        <p><%= totalLogs %></p>
                    </div>
                </div>

                <div class="kpi-card">
                    <div class="kpi-icon"><i class="fa-solid fa-calendar-day"></i></div>
                    <div>
                        <h3>Today</h3>
                        <p><%= todayLogs %></p>
                    </div>
                </div>

                <div class="kpi-card">
                    <div class="kpi-icon"><i class="fa-solid fa-file-export"></i></div>
                    <div>
                        <h3>Exports</h3>
                        <p><%= exportLogs %></p>
                    </div>
                </div>

                <div class="kpi-card">
                    <div class="kpi-icon"><i class="fa-solid fa-ban"></i></div>
                    <div>
                        <h3>Blocked / Denied</h3>
                        <p><%= blockedLogs %></p>
                    </div>
                </div>
            </section>

            <section class="audit-panel">
                <div class="audit-panel-head">
                    <div>
                        <h2>Audit Log Register</h2>
                        <p>Latest 500 audit events from the real audit_logs table.</p>
                    </div>

                    <a href="export_audit_logs.jsp" class="audit-btn secondary">
                        <i class="fa-solid fa-file-excel"></i>
                        Export Audit Logs
                    </a>
                </div>

                <div class="audit-filter-grid">
                    <div class="audit-search-wrap">
                        <i class="fa-solid fa-magnifying-glass"></i>
                        <input type="text"
                               id="auditSearch"
                               class="audit-search"
                               placeholder="Search audit logs...">
                    </div>

                    <select id="auditActionFilter" class="audit-select">
                        <option value="ALL">All Actions</option>
                        <%
                            for (String action : actionSet) {
                        %>
                            <option value="<%= safe(action) %>"><%= safe(cleanLabel(action)) %></option>
                        <%
                            }
                        %>
                    </select>

                    <select id="auditModuleFilter" class="audit-select">
                        <option value="ALL">All Modules</option>
                        <%
                            for (String module : moduleSet) {
                        %>
                            <option value="<%= safe(module) %>"><%= safe(cleanLabel(module)) %></option>
                        <%
                            }
                        %>
                    </select>

                    <button type="button" id="clearAuditFilters" class="audit-btn secondary">
                        <i class="fa-solid fa-filter-circle-xmark"></i>
                        Clear
                    </button>
                </div>

                <div class="audit-table-wrap">
                    <table class="audit-table" id="auditTable">
                        <thead>
                            <tr>
                                <th onclick="sortTable(0)" style="cursor: pointer;" title="Click to sort">Audit ID <i class="fa-solid fa-sort" style="color: #cbd5e1; margin-left: 4px;"></i></th>
                                <th onclick="sortTable(1)" style="cursor: pointer;" title="Click to sort">Action <i class="fa-solid fa-sort" style="color: #cbd5e1; margin-left: 4px;"></i></th>
                                <th onclick="sortTable(2)" style="cursor: pointer;" title="Click to sort">Module <i class="fa-solid fa-sort" style="color: #cbd5e1; margin-left: 4px;"></i></th>
                                <th onclick="sortTable(3)" style="cursor: pointer;" title="Click to sort">Record <i class="fa-solid fa-sort" style="color: #cbd5e1; margin-left: 4px;"></i></th>
                                <th onclick="sortTable(4)" style="cursor: pointer;" title="Click to sort">User <i class="fa-solid fa-sort" style="color: #cbd5e1; margin-left: 4px;"></i></th>
                                <th onclick="sortTable(5)" style="cursor: pointer;" title="Click to sort">Role <i class="fa-solid fa-sort" style="color: #cbd5e1; margin-left: 4px;"></i></th>
                                <th onclick="sortTable(6)" style="cursor: pointer;" title="Click to sort">Details <i class="fa-solid fa-sort" style="color: #cbd5e1; margin-left: 4px;"></i></th>
                                <th onclick="sortTable(7)" style="cursor: pointer;" title="Click to sort">IP <i class="fa-solid fa-sort" style="color: #cbd5e1; margin-left: 4px;"></i></th>
                                <th onclick="sortTable(8)" style="cursor: pointer;" title="Click to sort">Date &amp; Time <i class="fa-solid fa-sort" style="color: #cbd5e1; margin-left: 4px;"></i></th>
                                <th>Action</th>
                            </tr>
                        </thead>

                        <tbody>
                            <% if (auditList.isEmpty()) { %>
                                <tr>
                                    <td colspan="10" class="no-records">
                                        <i class="fa-solid fa-circle-info" style="font-size:30px;"></i>
                                        <br><br>
                                        No audit logs found. System actions will appear here after audit entries are recorded.
                                    </td>
                                </tr>
                            <% } else {
                                for (Map<String, String> row : auditList) {
                                    String actionType = rowValue(row, "action_type");
                                    String moduleName = rowValue(row, "module_name");
                            %>
                                <tr data-action="<%= safe(actionType) %>"
                                    data-module="<%= safe(moduleName) %>">

                                    <td>
                                        <strong>#<%= safe(rowValue(row, "audit_id")) %></strong>
                                    </td>

                                    <td>
                                        <span class="action-badge <%= badgeClass(actionType) %>">
                                            <i class="<%= iconClass(actionType) %>"></i>
                                            <%= safe(cleanLabel(actionType)) %>
                                        </span>
                                    </td>

                                    <td>
                                        <span class="module-pill">
                                            <%= safe(cleanLabel(moduleName)) %>
                                        </span>
                                    </td>

                                    <td>
                                        <%= safe(rowValue(row, "record_id")) %>
                                    </td>

                                    <td>
                                        <strong><%= safe(rowValue(row, "username")) %></strong>
                                        <span class="subtext">User ID: <%= safe(rowValue(row, "user_id")) %></span>
                                    </td>

                                    <td>
                                        <%= safe(cleanLabel(rowValue(row, "user_role"))) %>
                                    </td>

                                    <td class="details-cell">
                                        <%= safe(shortText(rowValue(row, "action_details"), 120)) %>
                                    </td>

                                    <td>
                                        <%= safe(rowValue(row, "ip_address")) %>
                                    </td>

                                    <td>
                                        <%= safe(rowValue(row, "created_at_display")) %>
                                    </td>

                                    <td>
                                        <a href="view_audit_log.jsp?id=<%= safe(rowValue(row, "audit_id")) %>"
                                           class="mini-link">
                                            <i class="fa-solid fa-eye"></i>
                                            View
                                        </a>
                                    </td>
                                </tr>
                            <%
                                }
                            }
                            %>
                        </tbody>
                    </table>

                    <div id="auditNoRecords"
                         class="no-records"
                         style="display:none;">
                        <i class="fa-solid fa-circle-info" style="font-size:30px;"></i>
                        <br><br>
                        No matching audit logs found.
                    </div>
                </div>
            </section>

        </div>
    </main>
</div>

<script>
    const auditSearch = document.getElementById("auditSearch");
    const auditActionFilter = document.getElementById("auditActionFilter");
    const auditModuleFilter = document.getElementById("auditModuleFilter");
    const clearAuditFilters = document.getElementById("clearAuditFilters");
    const auditRows = document.querySelectorAll("#auditTable tbody tr[data-action]");
    const auditNoRecords = document.getElementById("auditNoRecords");

    function normalizeText(text) {
        return String(text || "").toLowerCase().replace(/\s+/g, " ").trim();
    }

    function applyAuditFilters() {
        const keyword = normalizeText(auditSearch ? auditSearch.value : "");
        const selectedAction = auditActionFilter ? auditActionFilter.value : "ALL";
        const selectedModule = auditModuleFilter ? auditModuleFilter.value : "ALL";

        let visibleCount = 0;

        auditRows.forEach(function (row) {
            const rowText = normalizeText(row.textContent);
            const rowAction = String(row.dataset.action || "");
            const rowModule = String(row.dataset.module || "");

            const matchesKeyword = keyword === "" || rowText.indexOf(keyword) !== -1;
            const matchesAction = selectedAction === "ALL" || rowAction === selectedAction;
            const matchesModule = selectedModule === "ALL" || rowModule === selectedModule;

            if (matchesKeyword && matchesAction && matchesModule) {
                row.style.display = "";
                visibleCount++;
            } else {
                row.style.display = "none";
            }
        });

        if (auditNoRecords) {
            auditNoRecords.style.display = visibleCount === 0 && auditRows.length > 0 ? "block" : "none";
        }
    }

    if (auditSearch) {
        auditSearch.addEventListener("input", applyAuditFilters);
    }

    if (auditActionFilter) {
        auditActionFilter.addEventListener("change", applyAuditFilters);
    }

    if (auditModuleFilter) {
        auditModuleFilter.addEventListener("change", applyAuditFilters);
    }

    if (clearAuditFilters) {
        clearAuditFilters.addEventListener("click", function () {
            if (auditSearch) {
                auditSearch.value = "";
            }

            if (auditActionFilter) {
                auditActionFilter.value = "ALL";
            }

            if (auditModuleFilter) {
                auditModuleFilter.value = "ALL";
            }

            applyAuditFilters();
        });
    }
</script>

<script src="js/topbar-search.js?v=28000"></script>
<script src="js/user-dropdown.js?v=28000"></script>
<script src="js/sidebar-role.js?v=28000"></script>
<script src="js/ir-body-watermark.js?v=28000"></script>
<script src="js/dashboard-actions.js?v=28000"></script>

<script>
    var sortDirections = [true, true, true, true, true, true, true, true, true];

    function sortTable(columnIndex) {
        var table = document.getElementById("auditTable");
        var tbody = table.querySelector("tbody");
        var rows = Array.from(tbody.querySelectorAll("tr"));

        if (rows.length === 0) return;
        if (rows.length === 1 && rows[0].querySelector("td[colspan]")) return;

        var asc = sortDirections[columnIndex];
        sortDirections[columnIndex] = !asc;

        rows.sort(function(a, b) {
            var cellA = a.querySelectorAll("td")[columnIndex];
            var cellB = b.querySelectorAll("td")[columnIndex];

            if (!cellA || !cellB) return 0;

            var valA = cellA.innerText || cellA.textContent;
            var valB = cellB.innerText || cellB.textContent;

            valA = valA.trim().toLowerCase();
            valB = valB.trim().toLowerCase();

            if (valA < valB) return asc ? -1 : 1;
            if (valA > valB) return asc ? 1 : -1;
            return 0;
        });

        rows.forEach(function(row) {
            tbody.appendChild(row);
        });

        var headers = table.querySelectorAll("thead th");
        headers.forEach(function(th, idx) {
            var icon = th.querySelector("i.fa-sort, i.fa-sort-up, i.fa-sort-down");
            if (icon) {
                icon.className = "fa-solid fa-sort";
                if (idx === columnIndex) {
                    icon.className = asc ? "fa-solid fa-sort-up" : "fa-solid fa-sort-down";
                }
            }
        });
    }
</script>

</body>
</html>