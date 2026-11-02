<%@page contentType="text/html" pageEncoding="UTF-8"%>
<%@page import="com.mycompany.asset_management_system_ams.DBConnection"%>
<%@page import="java.sql.*"%>
<%@page import="java.util.*"%>
<%@page import="java.net.URLEncoder"%>

<%!
    public String formatNumber(int number) {
        if (number >= 100000) {
            return String.format("%.1fL", number / 100000.0);
        } else if (number >= 1000) {
            return String.format("%.1fK", number / 1000.0);
        }
        return String.valueOf(number);
    }

    public static class TagRow {
        String assetId = "";
        String assetCode = "";
        String assetName = "";
        String categoryName = "";
        String departmentName = "";
        String locationName = "";
        String assetStatus = "";
        String token = "";
        String qrUrl = "";
        String printStatus = "";
        String tagStatus = "";
        String printedAt = "";
        String taggedAt = "";
        String printedBy = "";
        String taggedBy = "";
        String remarks = "";
        String updatedAt = "";
    }

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

    private void ensureTaggingTable(Connection con) {
        String sql =
                "CREATE TABLE IF NOT EXISTS asset_qr_tagging_status ("
                + "tagging_id INT AUTO_INCREMENT PRIMARY KEY, "
                + "asset_id INT NOT NULL UNIQUE, "
                + "qr_public_token VARCHAR(120), "
                + "print_status VARCHAR(40) DEFAULT 'PENDING', "
                + "tag_status VARCHAR(40) DEFAULT 'PENDING', "
                + "printed_by_user_id INT, "
                + "tagged_by_user_id INT, "
                + "printed_at TIMESTAMP NULL, "
                + "tagged_at TIMESTAMP NULL, "
                + "remarks VARCHAR(500), "
                + "created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP, "
                + "updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP, "
                + "INDEX idx_qr_tagging_asset (asset_id), "
                + "INDEX idx_qr_tagging_print_status (print_status), "
                + "INDEX idx_qr_tagging_tag_status (tag_status)"
                + ") ENGINE=InnoDB DEFAULT CHARSET=utf8mb4";

        try (PreparedStatement ps = con.prepareStatement(sql)) {
            ps.executeUpdate();
        } catch (Exception e) {
            System.err.println("QR Module DB Error: " + e.getMessage());
        }
    }

    private int countRows(Connection con, String sql) {
        try (Statement st = con.createStatement();
             ResultSet rs = st.executeQuery(sql)) {

            if (rs.next()) {
                return rs.getInt(1);
            }

        } catch (Exception e) {
            System.err.println("QR Module DB Error: " + e.getMessage());
        }

        return 0;
    }

    private String statusClass(String value) {
        if (value == null || value.trim().isEmpty()) {
            return "PENDING";
        }

        return value.trim().toUpperCase(Locale.ENGLISH).replace(" ", "_");
    }

    private String selected(String actual, String expected) {
        if (actual == null) {
            actual = "";
        }

        return actual.equalsIgnoreCase(expected) ? "selected" : "";
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

    boolean canView = ("SUPER_ADMIN".equals(role) || "ADMIN".equals(role))
            || "ASSET_MANAGER".equals(role)
            || "AUDITOR".equals(role);

    boolean canUpdate = ("SUPER_ADMIN".equals(role) || "ADMIN".equals(role))
            || "ASSET_MANAGER".equals(role);

    if (!canView) {
        response.sendRedirect("dashboard.jsp?access=denied");
        return;
    }

    String q = request.getParameter("q");
    String printFilter = request.getParameter("print");
    String tagFilter = request.getParameter("tag");
    String msg = request.getParameter("msg");
    String error = request.getParameter("error");

    if (q == null) {
        q = "";
    }

    if (printFilter == null || printFilter.trim().isEmpty()) {
        printFilter = "ALL";
    }

    if (tagFilter == null || tagFilter.trim().isEmpty()) {
        tagFilter = "ALL";
    }

    q = q.trim();
    printFilter = printFilter.trim().toUpperCase(Locale.ENGLISH);
    tagFilter = tagFilter.trim().toUpperCase(Locale.ENGLISH);

    String exportUrl = "export_qr_tagging_status.jsp?print="
            + URLEncoder.encode(printFilter, "UTF-8")
            + "&tag=" + URLEncoder.encode(tagFilter, "UTF-8");

    String workOrderUrl = "qr_tagging_work_order.jsp?print="
            + URLEncoder.encode(printFilter, "UTF-8")
            + "&tag=" + URLEncoder.encode(tagFilter, "UTF-8");

    if (!q.isEmpty()) {
        exportUrl += "&q=" + URLEncoder.encode(q, "UTF-8");
        workOrderUrl += "&q=" + URLEncoder.encode(q, "UTF-8");
    }

    String userInitial = username.substring(0, Math.min(2, username.length())).toUpperCase(Locale.ENGLISH);

    int qrAssets = 0;
    int printedCount = 0;
    int taggedCount = 0;
    int pendingTagCount = 0;
    int filteredCount = 0;

    List<TagRow> rows = new ArrayList<TagRow>();

    try (Connection con = DBConnection.getConnection()) {
        ensureTaggingTable(con);

        qrAssets = countRows(con,
                "SELECT COUNT(*) FROM assets "
                + "WHERE qr_public_token IS NOT NULL AND TRIM(qr_public_token) <> ''");

        printedCount = countRows(con,
                "SELECT COUNT(*) FROM asset_qr_tagging_status WHERE print_status = 'PRINTED'");

        taggedCount = countRows(con,
                "SELECT COUNT(*) FROM asset_qr_tagging_status WHERE tag_status = 'TAGGED'");

        pendingTagCount = qrAssets - taggedCount;

        StringBuilder sql = new StringBuilder();

        sql.append("SELECT ")
                .append("a.asset_id, a.asset_code, a.asset_name, a.asset_status, ")
                .append("a.qr_public_token, a.qr_code, ")
                .append("COALESCE(ac.category_name, 'Uncategorized') AS category_name, ")
                .append("COALESCE(d.department_name, 'Unassigned') AS department_name, ")
                .append("COALESCE(rl.location_name, a.location, 'Not Mentioned') AS location_name, ")
                .append("COALESCE(t.print_status, 'PENDING') AS print_status, ")
                .append("COALESCE(t.tag_status, 'PENDING') AS tag_status, ")
                .append("DATE_FORMAT(t.printed_at, '%d %b %Y, %h:%i %p') AS printed_at, ")
                .append("DATE_FORMAT(t.tagged_at, '%d %b %Y, %h:%i %p') AS tagged_at, ")
                .append("COALESCE(pu.username, 'N/A') AS printed_by, ")
                .append("COALESCE(tu.username, 'N/A') AS tagged_by, ")
                .append("COALESCE(t.remarks, '') AS remarks, ")
                .append("DATE_FORMAT(COALESCE(t.updated_at, a.updated_at), '%d %b %Y, %h:%i %p') AS updated_at ")
                .append("FROM assets a ")
                .append("LEFT JOIN asset_categories ac ON a.category_id = ac.category_id ")
                .append("LEFT JOIN departments d ON a.department_id = d.department_id ")
                .append("LEFT JOIN railway_locations rl ON a.location_id = rl.location_id ")
                .append("LEFT JOIN asset_qr_tagging_status t ON a.asset_id = t.asset_id ")
                .append("LEFT JOIN users pu ON t.printed_by_user_id = pu.user_id ")
                .append("LEFT JOIN users tu ON t.tagged_by_user_id = tu.user_id ")
                .append("WHERE a.qr_public_token IS NOT NULL AND TRIM(a.qr_public_token) <> '' ");

        List<String> params = new ArrayList<String>();

        if (!"ALL".equals(printFilter)) {
            sql.append("AND COALESCE(t.print_status, 'PENDING') = ? ");
            params.add(printFilter);
        }

        if (!"ALL".equals(tagFilter)) {
            sql.append("AND COALESCE(t.tag_status, 'PENDING') = ? ");
            params.add(tagFilter);
        }

        if (!q.isEmpty()) {
            sql.append("AND (")
                    .append("a.asset_code LIKE ? ")
                    .append("OR a.asset_name LIKE ? ")
                    .append("OR a.qr_public_token LIKE ? ")
                    .append("OR d.department_name LIKE ? ")
                    .append("OR ac.category_name LIKE ? ")
                    .append("OR rl.location_name LIKE ? ")
                    .append(") ");

            String searchValue = "%" + q + "%";

            for (int i = 0; i < 6; i++) {
                params.add(searchValue);
            }
        }

        sql.append("ORDER BY a.asset_id DESC LIMIT 400");

        try (PreparedStatement ps = con.prepareStatement(sql.toString())) {
            for (int i = 0; i < params.size(); i++) {
                ps.setString(i + 1, params.get(i));
            }

            try (ResultSet rs = ps.executeQuery()) {
                while (rs.next()) {
                    TagRow row = new TagRow();

                    row.assetId = rs.getString("asset_id");
                    row.assetCode = rs.getString("asset_code");
                    row.assetName = rs.getString("asset_name");
                    row.categoryName = rs.getString("category_name");
                    row.departmentName = rs.getString("department_name");
                    row.locationName = rs.getString("location_name");
                    row.assetStatus = rs.getString("asset_status");
                    row.token = rs.getString("qr_public_token");
                    row.qrUrl = rs.getString("qr_code");
                    row.printStatus = rs.getString("print_status");
                    row.tagStatus = rs.getString("tag_status");
                    row.printedAt = rs.getString("printed_at");
                    row.taggedAt = rs.getString("tagged_at");
                    row.printedBy = rs.getString("printed_by");
                    row.taggedBy = rs.getString("tagged_by");
                    row.remarks = rs.getString("remarks");
                    row.updatedAt = rs.getString("updated_at");

                    rows.add(row);
                }
            }
        }

        filteredCount = rows.size();

    } catch (Exception e) {
        System.err.println("QR Module DB Error: " + e.getMessage());
    }
%>

<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>QR Tagging Status - IR-AMS</title>

    <link rel="stylesheet"
          href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.0/css/all.min.css">

    <link rel="stylesheet" href="css/ir-glass.css?v=28000">
    <link rel="stylesheet" href="css/ams-pro.css?v=28000">
    <link rel="stylesheet" href="css/ir-ams-railway-ui.css?v=28000">
<link rel="stylesheet" href="css/qr_tagging_status.css?v=topbarfix1">
        </head>

<body class="railway-ui">
<div class="app ams-shell">

    
    <jsp:include page="sidebar.jsp" />

    <main class="main railway-main">
        
        <jsp:include page="topbar.jsp" />

        <div class="main-scroll-content tag-board">

            <section class="tag-hero">
                <div>
                    <h1>QR Physical Tagging Status</h1>
                    <p>
                        Track QR label printing and physical tagging on assets. This gives official proof of QR tagging work,
                        pending work, damaged labels and reprint requirements.
                    </p>
                </div>

                <div class="hero-actions">
                    <a href="<%= safeText(workOrderUrl) %>" class="action-btn primary">
                        <i class="fa-solid fa-clipboard-list"></i>
                        Print Work Order
                    </a>

                    <a href="<%= safeText(exportUrl) %>" class="action-btn green">
                        <i class="fa-solid fa-file-excel"></i>
                        Export Excel
                    </a>

                    <a href="qr_control_center.jsp" class="action-btn">
                        <i class="fa-solid fa-arrow-left"></i>
                        Control Center
                    </a>
                </div>
            </section>

            <% if ("updated".equals(msg)) { %>
                <div class="message-success">
                    <i class="fa-solid fa-circle-check"></i>
                    QR tagging status updated successfully.
                </div>
            <% } %>

            <% if ("failed".equals(error)) { %>
                <div class="message-error">
                    <i class="fa-solid fa-triangle-exclamation"></i>
                    Status update failed. Please check server console.
                </div>
            <% } %>

            <section class="kpi-grid">
                <div class="kpi-card">
                    <h3>QR Assets</h3>
                    <p title="<%= qrAssets %>"><%= formatNumber(qrAssets) %></p>
                    <span>Assets having QR token</span>
                </div>

                <div class="kpi-card">
                    <h3>Printed</h3>
                    <p title="<%= printedCount %>"><%= formatNumber(printedCount) %></p>
                    <span>QR label printed</span>
                </div>

                <div class="kpi-card">
                    <h3>Tagged</h3>
                    <p title="<%= taggedCount %>"><%= formatNumber(taggedCount) %></p>
                    <span>Physically tagged assets</span>
                </div>

                <div class="kpi-card">
                    <h3>Pending Tagging</h3>
                    <p title="<%= pendingTagCount %>"><%= formatNumber(pendingTagCount) %></p>
                    <span>Still to be tagged</span>
                </div>

                <div class="kpi-card">
                    <h3>Filtered</h3>
                    <p title="<%= filteredCount %>"><%= formatNumber(filteredCount) %></p>
                    <span>Current visible rows</span>
                </div>
            </section>

            <section class="panel">
                <div class="toolbar">
                    <div>
                        <h2>QR Tagging Register</h2>
                        <p class="table-subtext">Showing <%= rows.size() %> QR-enabled assets. Maximum 400 records shown.</p>
                    </div>

                    <form class="filter-form" method="get" action="qr_tagging_status.jsp">
                        <input class="filter-input"
                               type="text"
                               name="q"
                               value="<%= q.isEmpty() ? "" : safeText(q) %>"
                               placeholder="Search asset, department, location, token...">

                        <select class="filter-select" name="print">
                            <option value="ALL" <%= selected(printFilter, "ALL") %>>All Print</option>
                            <option value="PENDING" <%= selected(printFilter, "PENDING") %>>Print Pending</option>
                            <option value="PRINTED" <%= selected(printFilter, "PRINTED") %>>Printed</option>
                            <option value="REPRINT_REQUIRED" <%= selected(printFilter, "REPRINT_REQUIRED") %>>Reprint Required</option>
                        </select>

                        <select class="filter-select" name="tag">
                            <option value="ALL" <%= selected(tagFilter, "ALL") %>>All Tagging</option>
                            <option value="PENDING" <%= selected(tagFilter, "PENDING") %>>Tag Pending</option>
                            <option value="TAGGED" <%= selected(tagFilter, "TAGGED") %>>Tagged</option>
                            <option value="DAMAGED" <%= selected(tagFilter, "DAMAGED") %>>Damaged</option>
                            <option value="REMOVED" <%= selected(tagFilter, "REMOVED") %>>Removed</option>
                        </select>

                        <button class="action-btn primary" type="submit">
                            <i class="fa-solid fa-filter"></i>
                            Filter
                        </button>

                        <a class="action-btn" href="qr_tagging_status.jsp">
                            <i class="fa-solid fa-rotate-right"></i>
                            Reset
                        </a>
                    </form>
                </div>

                <div class="table-wrap">
                    <table class="tag-table" id="taggingTable">
                        <thead>
                            <tr>
                                <th onclick="sortTable(0)" style="cursor: pointer;" title="Click to sort">Asset <i class="fa-solid fa-sort" style="color: #cbd5e1; margin-left: 4px;"></i></th>
                                <th onclick="sortTable(1)" style="cursor: pointer;" title="Click to sort">Department / Category <i class="fa-solid fa-sort" style="color: #cbd5e1; margin-left: 4px;"></i></th>
                                <th onclick="sortTable(2)" style="cursor: pointer;" title="Click to sort">Location <i class="fa-solid fa-sort" style="color: #cbd5e1; margin-left: 4px;"></i></th>
                                <th onclick="sortTable(3)" style="cursor: pointer;" title="Click to sort">Asset Status <i class="fa-solid fa-sort" style="color: #cbd5e1; margin-left: 4px;"></i></th>
                                <th onclick="sortTable(4)" style="cursor: pointer;" title="Click to sort">QR Token <i class="fa-solid fa-sort" style="color: #cbd5e1; margin-left: 4px;"></i></th>
                                <th onclick="sortTable(5)" style="cursor: pointer;" title="Click to sort">Print Status <i class="fa-solid fa-sort" style="color: #cbd5e1; margin-left: 4px;"></i></th>
                                <th onclick="sortTable(6)" style="cursor: pointer;" title="Click to sort">Tag Status <i class="fa-solid fa-sort" style="color: #cbd5e1; margin-left: 4px;"></i></th>
                                <th onclick="sortTable(7)" style="cursor: pointer;" title="Click to sort">Printed <i class="fa-solid fa-sort" style="color: #cbd5e1; margin-left: 4px;"></i></th>
                                <th onclick="sortTable(8)" style="cursor: pointer;" title="Click to sort">Tagged <i class="fa-solid fa-sort" style="color: #cbd5e1; margin-left: 4px;"></i></th>
                                <th onclick="sortTable(9)" style="cursor: pointer;" title="Click to sort">Remarks <i class="fa-solid fa-sort" style="color: #cbd5e1; margin-left: 4px;"></i></th>
                                <th>Update</th>
                                <th>Open</th>
                            </tr>
                        </thead>

                        <tbody>
                            <% for (TagRow row : rows) { %>
                                <tr>
                                    <td>
                                        <div class="asset-title">
                                            <strong><%= safeText(row.assetCode) %></strong>
                                            <span><%= safeText(row.assetName) %></span>
                                        </div>
                                    </td>

                                    <td>
                                        <div class="asset-title">
                                            <strong><%= safeText(row.departmentName) %></strong>
                                            <span><%= safeText(row.categoryName) %></span>
                                        </div>
                                    </td>

                                    <td><%= safeText(row.locationName) %></td>

                                    <td>
                                        <span class="pill">
                                            <%= safeText(cleanLabel(row.assetStatus)) %>
                                        </span>
                                    </td>

                                    <td>
                                        <span class="pill" title="<%= safeText(row.token) %>">
                                            <%= safeText(row.token) %>
                                        </span>
                                    </td>

                                    <td>
                                        <span class="pill status-<%= safeText(statusClass(row.printStatus)) %>">
                                            <%= safeText(cleanLabel(row.printStatus)) %>
                                        </span>
                                    </td>

                                    <td>
                                        <span class="pill status-<%= safeText(statusClass(row.tagStatus)) %>">
                                            <%= safeText(cleanLabel(row.tagStatus)) %>
                                        </span>
                                    </td>

                                    <td>
                                        <div class="asset-title">
                                            <strong><%= safeText(row.printedAt) %></strong>
                                            <span><%= safeText(row.printedBy) %></span>
                                        </div>
                                    </td>

                                    <td>
                                        <div class="asset-title">
                                            <strong><%= safeText(row.taggedAt) %></strong>
                                            <span><%= safeText(row.taggedBy) %></span>
                                        </div>
                                    </td>

                                    <td>
                                        <span class="pill" title="<%= safeText(row.remarks) %>">
                                            <%= safeText(row.remarks) %>
                                        </span>
                                    </td>

                                    <td>
                                        <% if (canUpdate) { %>
                                            <form class="row-form" method="post" action="UpdateQrTaggingStatusServlet">
                                                <input type="hidden" name="asset_id" value="<%= safeText(row.assetId) %>">

                                                <select name="print_status">
                                                    <option value="PENDING" <%= selected(row.printStatus, "PENDING") %>>Print Pending</option>
                                                    <option value="PRINTED" <%= selected(row.printStatus, "PRINTED") %>>Printed</option>
                                                    <option value="REPRINT_REQUIRED" <%= selected(row.printStatus, "REPRINT_REQUIRED") %>>Reprint Required</option>
                                                </select>

                                                <select name="tag_status">
                                                    <option value="PENDING" <%= selected(row.tagStatus, "PENDING") %>>Tag Pending</option>
                                                    <option value="TAGGED" <%= selected(row.tagStatus, "TAGGED") %>>Tagged</option>
                                                    <option value="DAMAGED" <%= selected(row.tagStatus, "DAMAGED") %>>Damaged</option>
                                                    <option value="REMOVED" <%= selected(row.tagStatus, "REMOVED") %>>Removed</option>
                                                </select>

                                                <input type="text" name="remarks" value="<%= row.remarks == null ? "" : safeText(row.remarks) %>" placeholder="Remarks">

                                                <button class="action-btn primary" type="submit">
                                                    Save
                                                </button>
                                            </form>
                                        <% } else { %>
                                            <span class="pill">View Only</span>
                                        <% } %>
                                    </td>

                                    <td>
                                        <div class="hero-actions" style="justify-content:flex-start;">
                                            <a class="action-btn" href="view_asset.jsp?id=<%= safeText(row.assetId) %>">Asset</a>
                                            <a class="action-btn green" href="qr_print.jsp?id=<%= safeText(row.assetId) %>">Print</a>
                                        </div>
                                    </td>
                                </tr>
                            <% } %>

                            <% if (rows.isEmpty()) { %>
                                <tr>
                                    <td colspan="12">
                                        <span class="pill">No QR tagging record found for selected filter.</span>
                                    </td>
                                </tr>
                            <% } %>
                        </tbody>
                    </table>
                </div>
            </section>

        </div>
    </main>
</div>

<script src="js/topbar-search.js?v=28000"></script>
<script src="js/user-dropdown.js?v=28000"></script>
<script src="js/sidebar-role.js?v=28000"></script>
<script src="js/ir-body-watermark.js?v=28000"></script>
<script src="js/dashboard-actions.js?v=28000"></script>
<script>
    var sortDirections = [true, true, true, true, true, true, true, true, true, true];
    
    function sortTable(columnIndex) {
        var table = document.getElementById("taggingTable");
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