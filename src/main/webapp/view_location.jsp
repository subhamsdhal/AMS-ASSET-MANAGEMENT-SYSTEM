<%@page contentType="text/html" pageEncoding="UTF-8"%>
<%@page import="com.mycompany.asset_management_system_ams.DBConnection"%>
<%@page import="java.sql.*"%>
<%@page import="java.util.*"%>
<%@page import="java.text.NumberFormat"%>

<%!
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

    private String indianNumber(long value) {
        try {
            NumberFormat nf = NumberFormat.getNumberInstance(new Locale("en", "IN"));
            nf.setMaximumFractionDigits(0);
            return nf.format(value);
        } catch (Exception e) {
            return String.valueOf(value);
        }
    }

    private Map<String, String> singleRow(String sql, String id) {
        Map<String, String> row = new HashMap<>();

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

    private List<Map<String, String>> listRows(String sql, String id) {
        List<Map<String, String>> rows = new ArrayList<>();

        try (Connection con = DBConnection.getConnection();
             PreparedStatement ps = con.prepareStatement(sql)) {

            ps.setString(1, id);

            try (ResultSet rs = ps.executeQuery()) {
                ResultSetMetaData meta = rs.getMetaData();
                int count = meta.getColumnCount();

                while (rs.next()) {
                    Map<String, String> row = new HashMap<>();

                    for (int i = 1; i <= count; i++) {
                        row.put(meta.getColumnLabel(i), rs.getString(i));
                    }

                    rows.add(row);
                }
            }

        } catch (Exception e) {
            e.printStackTrace();
        }

        return rows;
    }

    private int singleInt(String sql, String id) {
        int value = 0;

        try (Connection con = DBConnection.getConnection();
             PreparedStatement ps = con.prepareStatement(sql)) {

            ps.setString(1, id);

            try (ResultSet rs = ps.executeQuery()) {
                if (rs.next()) value = rs.getInt(1);
            }

        } catch (Exception e) {
            e.printStackTrace();
        }

        return value;
    }

    private String rowValue(Map<String, String> row, String key) {
        if (row == null) return "";
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

    String locationId = request.getParameter("id");

    if (locationId == null || locationId.trim().isEmpty()) {
        locationId = request.getParameter("location_id");
    }

    if (locationId == null || locationId.trim().isEmpty()) {
        response.sendRedirect("category_vendor_mapping.jsp?error=invalid_location");
        return;
    }

    locationId = locationId.trim();

    String userInitial = username.substring(0, Math.min(2, username.length())).toUpperCase(Locale.ENGLISH);

    Map<String, String> location = singleRow(
            "SELECT "
            + "rl.location_id, "
            + "rl.location_code, "
            + "rl.location_name, "
            + "rl.location_type, "
            + "rl.building_block, "
            + "rl.floor_level, "
            + "rl.room_no, "
            + "rl.status, "
            + "DATE_FORMAT(rl.created_at, '%d %b %Y, %h:%i %p') AS created_at, "
            + "DATE_FORMAT(rl.updated_at, '%d %b %Y, %h:%i %p') AS updated_at, "
            + "COALESCE(d.department_name, 'No Department') AS department_name, "
            + "COALESCE(rd.division_name, '') AS division_name, "
            + "COALESCE(rz.zone_name, 'East Coast Railway') AS zone_name, "
            + "COALESCE(rz.zone_code, 'ECoR') AS zone_code "
            + "FROM railway_locations rl "
            + "LEFT JOIN departments d ON rl.department_id = d.department_id "
            + "LEFT JOIN railway_divisions rd ON rl.division_id = rd.division_id "
            + "LEFT JOIN railway_zones rz ON rd.zone_id = rz.zone_id "
            + "WHERE rl.location_id = ? "
            + "LIMIT 1",
            locationId
    );

    if (location.isEmpty()) {
        response.sendRedirect("category_vendor_mapping.jsp?error=location_notfound");
        return;
    }

    int totalAssets = singleInt("SELECT COUNT(*) FROM assets WHERE location_id = ?", locationId);
    int totalEmployees = singleInt("SELECT COUNT(*) FROM employees WHERE location_id = ?", locationId);
    int totalAllocations = singleInt("SELECT COUNT(*) FROM asset_allocation WHERE issue_location_id = ?", locationId);
    int totalRequests = singleInt("SELECT COUNT(*) FROM asset_requests WHERE location_id = ?", locationId);
    int totalVerifications = singleInt("SELECT COUNT(*) FROM physical_verification WHERE ? IN (expected_location_id, actual_location_id)", locationId);

    List<Map<String, String>> assetRows = listRows(
            "SELECT "
            + "a.asset_id, "
            + "a.asset_code, "
            + "a.asset_name, "
            + "a.asset_status, "
            + "a.service_status, "
            + "COALESCE(ac.category_name, 'Uncategorized') AS category_name "
            + "FROM assets a "
            + "LEFT JOIN asset_categories ac ON a.category_id = ac.category_id "
            + "WHERE a.location_id = ? "
            + "ORDER BY a.asset_id DESC "
            + "LIMIT 10",
            locationId
    );

    List<Map<String, String>> employeeRows = listRows(
            "SELECT "
            + "employee_id, "
            + "employee_code, "
            + "employee_name AS full_name, "
            + "designation, "
            + "employee_status "
            + "FROM employees "
            + "WHERE location_id = ? "
            + "ORDER BY employee_name ASC "
            + "LIMIT 10",
            locationId
    );

    List<Map<String, String>> verificationRows = listRows(
            "SELECT "
            + "pv.verification_id, "
            + "pv.asset_id, "
            + "a.asset_code, "
            + "a.asset_name, "
            + "DATE_FORMAT(pv.verification_date, '%d %b %Y') AS verification_date, "
            + "pv.verification_status, "
            + "pv.asset_found, "
            + "pv.physical_condition "
            + "FROM physical_verification pv "
            + "LEFT JOIN assets a ON pv.asset_id = a.asset_id "
            + "WHERE ? IN (pv.expected_location_id, pv.actual_location_id) "
            + "ORDER BY pv.verification_id DESC "
            + "LIMIT 10",
            locationId
    );

    String locationStatus = rowValue(location, "status");
    String statusClass = "";

    if ("INACTIVE".equalsIgnoreCase(locationStatus)) {
        statusClass = "danger";
    }
%>

<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>Location Details - IR-AMS</title>

    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.0/css/all.min.css">

    <link rel="stylesheet" href="css/ir-glass.css?v=28000">
    <link rel="stylesheet" href="css/ams-pro.css?v=28000">
    <link rel="stylesheet" href="css/ir-ams-railway-ui.css?v=view-location-real-1">

    <link rel="stylesheet" href="css/view_location.css?v=28001">
</head>

<body class="railway-ui">
<div class="app ams-shell">

    <jsp:include page="sidebar.jsp" />

    <main class="main railway-main">
        <jsp:include page="topbar.jsp" />

        <div class="main-scroll-content detail-board">

            <section class="detail-hero">
                <div>
                    <h1><%= safeText(rowValue(location, "location_name")) %></h1>
                    <p>
                        <strong><%= safeText(rowValue(location, "location_code")) %></strong>
                        · <%= safeText(rowValue(location, "location_type")) %>
                        · <%= safeText(rowValue(location, "division_name")) %>
                    </p>
                </div>

                <div class="hero-actions">
                    <span class="status-pill <%= statusClass %>">
                        <i class="fa-solid fa-location-dot"></i>
                        <%= safeText(cleanLabel(locationStatus)) %>
                    </span>

                    <a href="category_vendor_mapping.jsp" class="btn btn-secondary">
                        <i class="fa-solid fa-arrow-left"></i>
                        Back
                    </a>
                </div>
            </section>

            <section class="summary-grid">
                <div class="summary-card"><span>Assets</span><strong><%= indianNumber(totalAssets) %></strong></div>
                <div class="summary-card"><span>Employees</span><strong><%= indianNumber(totalEmployees) %></strong></div>
                <div class="summary-card"><span>Allocations</span><strong><%= indianNumber(totalAllocations) %></strong></div>
                <div class="summary-card"><span>Requests</span><strong><%= indianNumber(totalRequests) %></strong></div>
                <div class="summary-card"><span>Verifications</span><strong><%= indianNumber(totalVerifications) %></strong></div>
            </section>

            <section class="detail-grid">
                <div class="detail-panel">
                    <div class="panel-title-row"><h2 class="panel-title">Location Profile</h2></div>

                    <table class="detail-table">
                        <tr><th>Location Code</th><td><%= safeText(rowValue(location, "location_code")) %></td></tr>
                        <tr><th>Location Name</th><td><%= safeText(rowValue(location, "location_name")) %></td></tr>
                        <tr><th>Location Type</th><td><%= safeText(rowValue(location, "location_type")) %></td></tr>
                        <tr><th>Building / Block</th><td><%= safeText(rowValue(location, "building_block")) %></td></tr>
                        <tr><th>Floor Level</th><td><%= safeText(rowValue(location, "floor_level")) %></td></tr>
                        <tr><th>Room No</th><td><%= safeText(rowValue(location, "room_no")) %></td></tr>
                        <tr><th>Department</th><td><%= safeText(rowValue(location, "department_name")) %></td></tr>
                        <tr><th>Division</th><td><%= safeText(rowValue(location, "division_name")) %></td></tr>
                        <tr><th>Zone</th><td><%= safeText(rowValue(location, "zone_name")) %> · <%= safeText(rowValue(location, "zone_code")) %></td></tr>
                        <tr><th>Status</th><td><%= safeText(cleanLabel(locationStatus)) %></td></tr>
                        <tr><th>Created On</th><td><%= safeText(rowValue(location, "created_at")) %></td></tr>
                        <tr><th>Updated On</th><td><%= safeText(rowValue(location, "updated_at")) %></td></tr>
                    </table>
                </div>

                <div class="detail-panel">
                    <div class="panel-title-row"><h2 class="panel-title">Assets at this Location</h2></div>

                    <div class="timeline-list">
                        <% if (assetRows.isEmpty()) { %>
                            <div class="empty-box">
                                <i class="fa-solid fa-cubes"></i>
                                <strong>No asset found</strong>
                                <span>Assets linked to this location will appear here.</span>
                            </div>
                        <% } else {
                            for (Map<String, String> row : assetRows) {
                        %>
                            <a class="timeline-row" href="view_asset.jsp?id=<%= safeText(rowValue(row, "asset_id")) %>">
                                <div class="timeline-icon"><i class="fa-solid fa-cube"></i></div>
                                <div class="timeline-text">
                                    <strong><%= safeText(rowValue(row, "asset_code")) %> · <%= safeText(rowValue(row, "asset_name")) %></strong>
                                    <span><%= safeText(rowValue(row, "category_name")) %> · <%= safeText(cleanLabel(rowValue(row, "asset_status"))) %> · <%= safeText(cleanLabel(rowValue(row, "service_status"))) %></span>
                                </div>
                                <div class="timeline-date">Asset</div>
                            </a>
                        <%  }
                        } %>
                    </div>
                </div>
            </section>

            <section class="detail-grid">
                <div class="detail-panel">
                    <div class="panel-title-row"><h2 class="panel-title">Employees at this Location</h2></div>

                    <div class="timeline-list">
                        <% if (employeeRows.isEmpty()) { %>
                            <div class="empty-box">
                                <i class="fa-regular fa-id-card"></i>
                                <strong>No holder found</strong>
                                <span>Employees linked to this location will appear here.</span>
                            </div>
                        <% } else {
                            for (Map<String, String> row : employeeRows) {
                        %>
                            <a class="timeline-row" href="view_employee.jsp?id=<%= safeText(rowValue(row, "employee_id")) %>">
                                <div class="timeline-icon"><i class="fa-regular fa-id-card"></i></div>
                                <div class="timeline-text">
                                    <strong><%= safeText(rowValue(row, "full_name")) %> · <%= safeText(rowValue(row, "employee_code")) %></strong>
                                    <span><%= safeText(rowValue(row, "designation")) %> · <%= safeText(cleanLabel(rowValue(row, "employee_status"))) %></span>
                                </div>
                                <div class="timeline-date">Holder</div>
                            </a>
                        <%  }
                        } %>
                    </div>
                </div>

                <div class="detail-panel">
                    <div class="panel-title-row"><h2 class="panel-title">Verification Activity</h2></div>

                    <div class="timeline-list">
                        <% if (verificationRows.isEmpty()) { %>
                            <div class="empty-box">
                                <i class="fa-solid fa-shield-halved"></i>
                                <strong>No verification found</strong>
                                <span>Physical verification records linked to this location will appear here.</span>
                            </div>
                        <% } else {
                            for (Map<String, String> row : verificationRows) {
                        %>
                            <a class="timeline-row" href="view_verification.jsp?id=<%= safeText(rowValue(row, "verification_id")) %>">
                                <div class="timeline-icon"><i class="fa-solid fa-shield-halved"></i></div>
                                <div class="timeline-text">
                                    <strong><%= safeText(rowValue(row, "asset_code")) %> · <%= safeText(rowValue(row, "asset_name")) %></strong>
                                    <span><%= safeText(cleanLabel(rowValue(row, "verification_status"))) %> · Found: <%= safeText(cleanLabel(rowValue(row, "asset_found"))) %> · <%= safeText(cleanLabel(rowValue(row, "physical_condition"))) %></span>
                                </div>
                                <div class="timeline-date"><%= safeText(rowValue(row, "verification_date")) %></div>
                            </a>
                        <%  }
                        } %>
                    </div>
                </div>
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
