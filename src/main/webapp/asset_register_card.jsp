<%@page contentType="text/html" pageEncoding="UTF-8"%>
<%@page import="com.mycompany.asset_management_system_ams.DBConnection"%>
<%@page import="java.sql.*"%>
<%@page import="java.util.*"%>
<%@page import="java.text.DecimalFormat"%>
<%@page import="java.net.URLEncoder"%>

<%!
    private String safe(Object value) {
        if (value == null) {
            return "-";
        }

        String text = value.toString().trim();

        if (text.isEmpty()) {
            return "-";
        }

        return text
                .replace("&", "&amp;")
                .replace("<", "&lt;")
                .replace(">", "&gt;")
                .replace("\"", "&quot;")
                .replace("'", "&#39;");
    }

    private String get(Map<String, String> data, String key) {
        if (data == null || !data.containsKey(key)) {
            return "-";
        }

        String value = data.get(key);

        if (value == null || value.trim().isEmpty()) {
            return "-";
        }

        return value.trim();
    }

    private String moneyText(Object value) {
        try {
            if (value == null) {
                return "-";
            }

            String text = value.toString().trim();

            if (text.equals("-") || text.isEmpty()) {
                return "-";
            }

            double amount = Double.parseDouble(text);
            DecimalFormat df = new DecimalFormat("#,##0.00");
            return "₹" + df.format(amount);

        } catch (Exception e) {
            return "-";
        }
    }

    private String statusText(String value) {
        if (value == null || value.trim().isEmpty() || value.trim().equals("-")) {
            return "UNKNOWN";
        }

        return value.trim().replace("_", " ");
    }

    private String statusClass(String value) {
        if (value == null || value.trim().isEmpty() || value.trim().equals("-")) {
            return "UNKNOWN";
        }

        return value.trim().toUpperCase().replace(" ", "_");
    }

    private String shortText(String value, int max) {
        if (value == null) {
            return "-";
        }

        String text = value.trim();

        if (text.isEmpty()) {
            return "-";
        }

        if (text.length() <= max) {
            return text;
        }

        return text.substring(0, max) + "...";
    }

    private String officeTypeText(String value) {
        if (value == null || value.trim().isEmpty() || value.trim().equals("-")) {
            return "Headquarters";
        }

        String text = value.trim();

        if ("HQ_OFFICE".equals(text)) {
            return "Headquarters";
        }

        if ("STORE".equals(text)) {
            return "Store";
        }

        if ("CONFERENCE_ROOM".equals(text)) {
            return "Conference Room";
        }

        if ("TRAINING_CENTRE".equals(text)) {
            return "Training Centre";
        }

        if ("WORKSHOP".equals(text)) {
            return "Workshop";
        }

        if ("DEPOT".equals(text)) {
            return "Depot";
        }

        return text.replace("_", " ");
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

    boolean canManageAssets = ("SUPER_ADMIN".equals(role) || "ADMIN".equals(role)) || "ASSET_MANAGER".equals(role);

    String idParam = request.getParameter("id");
    String codeParam = request.getParameter("code");
    String qrParam = request.getParameter("qr");

    int assetIdParam = 0;

    try {
        assetIdParam = Integer.parseInt(idParam);
    } catch (Exception e) {
        assetIdParam = 0;
    }

    Map<String, String> asset = new HashMap<>();

    StringBuilder allocationRows = new StringBuilder();
    StringBuilder maintenanceRows = new StringBuilder();
    StringBuilder returnRows = new StringBuilder();
    StringBuilder scanRows = new StringBuilder();
    StringBuilder verificationRows = new StringBuilder();
    StringBuilder disposalRows = new StringBuilder();

    int assetId = 0;
    boolean found = false;

    try (Connection con = DBConnection.getConnection()) {

        String assetSql = "SELECT * FROM vw_railway_asset_register_card "
                + "WHERE asset_id = ? "
                + "OR asset_code = ? "
                + "OR railway_asset_no = ? "
                + "OR qr_public_token = ? "
                + "LIMIT 1";

        try (PreparedStatement ps = con.prepareStatement(assetSql)) {
            ps.setInt(1, assetIdParam);
            ps.setString(2, codeParam == null ? "" : codeParam.trim());
            ps.setString(3, codeParam == null ? "" : codeParam.trim());
            ps.setString(4, qrParam == null ? "" : qrParam.trim());

            try (ResultSet rs = ps.executeQuery()) {
                if (rs.next()) {
                    found = true;
                    assetId = rs.getInt("asset_id");

                    ResultSetMetaData meta = rs.getMetaData();
                    int columnCount = meta.getColumnCount();

                    for (int i = 1; i <= columnCount; i++) {
                        asset.put(meta.getColumnLabel(i), rs.getString(i));
                    }
                }
            }
        }

        if (found) {

            String allocationSql = "SELECT aa.allocation_id, aa.allocation_date, aa.return_date, "
                    + "aa.allocation_status, aa.remarks, "
                    + "e.employee_code, "
                    + "e.employee_name AS employee_name, "
                    + "e.designation, d.department_name "
                    + "FROM asset_allocation aa "
                    + "LEFT JOIN employees e ON aa.employee_id = e.employee_id "
                    + "LEFT JOIN departments d ON e.department_id = d.department_id "
                    + "WHERE aa.asset_id = ? "
                    + "ORDER BY aa.allocation_id DESC";

            try (PreparedStatement ps = con.prepareStatement(allocationSql)) {
                ps.setInt(1, assetId);

                try (ResultSet rs = ps.executeQuery()) {
                    while (rs.next()) {
                        String returnDate = rs.getString("return_date");

                        allocationRows.append("<tr>")
                                .append("<td>").append(safe(rs.getString("allocation_id"))).append("</td>")
                                .append("<td>").append(safe(rs.getString("employee_code"))).append("</td>")
                                .append("<td>").append(safe(rs.getString("employee_name"))).append("</td>")
                                .append("<td>").append(safe(rs.getString("designation"))).append("</td>")
                                .append("<td>").append(safe(rs.getString("department_name"))).append("</td>")
                                .append("<td>").append(safe(rs.getString("allocation_date"))).append("</td>")
                                .append("<td>").append(safe(returnDate == null ? "Currently Allocated" : returnDate)).append("</td>")
                                .append("<td><span class='mini-badge status-").append(statusClass(rs.getString("allocation_status"))).append("'>")
                                .append(safe(statusText(rs.getString("allocation_status")))).append("</span></td>")
                                .append("</tr>");
                    }
                }
            }

            String maintenanceSql = "SELECT maintenance_id, maintenance_date, maintenance_type, "
                    + "performed_by, cost, description "
                    + "FROM maintenance_logs "
                    + "WHERE asset_id = ? "
                    + "ORDER BY maintenance_date DESC, maintenance_id DESC";

            try (PreparedStatement ps = con.prepareStatement(maintenanceSql)) {
                ps.setInt(1, assetId);

                try (ResultSet rs = ps.executeQuery()) {
                    while (rs.next()) {
                        maintenanceRows.append("<tr>")
                                .append("<td>").append(safe(rs.getString("maintenance_id"))).append("</td>")
                                .append("<td>").append(safe(rs.getString("maintenance_date"))).append("</td>")
                                .append("<td>").append(safe(statusText(rs.getString("maintenance_type")))).append("</td>")
                                .append("<td>").append(safe(rs.getString("performed_by"))).append("</td>")
                                .append("<td>").append(safe(moneyText(rs.getString("cost")))).append("</td>")
                                .append("<td>").append(safe(shortText(rs.getString("description"), 90))).append("</td>")
                                .append("</tr>");
                    }
                }
            }

            String returnSql = "SELECT r.return_id, r.return_date, r.return_condition, "
                    + "r.received_by, r.remarks, aa.allocation_id "
                    + "FROM asset_returns r "
                    + "JOIN asset_allocation aa ON r.allocation_id = aa.allocation_id "
                    + "WHERE aa.asset_id = ? "
                    + "ORDER BY r.return_date DESC, r.return_id DESC";

            try (PreparedStatement ps = con.prepareStatement(returnSql)) {
                ps.setInt(1, assetId);

                try (ResultSet rs = ps.executeQuery()) {
                    while (rs.next()) {
                        returnRows.append("<tr>")
                                .append("<td>").append(safe(rs.getString("return_id"))).append("</td>")
                                .append("<td>").append(safe(rs.getString("allocation_id"))).append("</td>")
                                .append("<td>").append(safe(rs.getString("return_date"))).append("</td>")
                                .append("<td><span class='mini-badge status-").append(statusClass(rs.getString("return_condition"))).append("'>")
                                .append(safe(statusText(rs.getString("return_condition")))).append("</span></td>")
                                .append("<td>").append(safe(rs.getString("received_by"))).append("</td>")
                                .append("<td>").append(safe(shortText(rs.getString("remarks"), 90))).append("</td>")
                                .append("</tr>");
                    }
                }
            }

            String scanSql = "SELECT scan_source, scan_result, scanner_ip, scanned_at "
                    + "FROM asset_qr_scan_logs "
                    + "WHERE asset_id = ? "
                    + "ORDER BY scanned_at DESC "
                    + "LIMIT 10";

            try (PreparedStatement ps = con.prepareStatement(scanSql)) {
                ps.setInt(1, assetId);

                try (ResultSet rs = ps.executeQuery()) {
                    while (rs.next()) {
                        scanRows.append("<tr>")
                                .append("<td>").append(safe(statusText(rs.getString("scan_source")))).append("</td>")
                                .append("<td><span class='mini-badge status-").append(statusClass(rs.getString("scan_result"))).append("'>")
                                .append(safe(statusText(rs.getString("scan_result")))).append("</span></td>")
                                .append("<td>").append(safe(rs.getString("scanner_ip"))).append("</td>")
                                .append("<td>").append(safe(rs.getString("scanned_at"))).append("</td>")
                                .append("</tr>");
                    }
                }
            }

            String verificationSql = "SELECT pv.verified_status, pv.verified_on, pv.remarks, "
                    + "rl.location_name, "
                    + "e.employee_name AS actual_employee_name, "
                    + "u.username AS verified_by "
                    + "FROM asset_physical_verification pv "
                    + "LEFT JOIN railway_locations rl ON pv.actual_location_id = rl.location_id "
                    + "LEFT JOIN employees e ON pv.actual_employee_id = e.employee_id "
                    + "LEFT JOIN users u ON pv.verified_by_user_id = u.user_id "
                    + "WHERE pv.asset_id = ? "
                    + "ORDER BY pv.verified_on DESC "
                    + "LIMIT 10";

            try (PreparedStatement ps = con.prepareStatement(verificationSql)) {
                ps.setInt(1, assetId);

                try (ResultSet rs = ps.executeQuery()) {
                    while (rs.next()) {
                        verificationRows.append("<tr>")
                                .append("<td><span class='mini-badge status-").append(statusClass(rs.getString("verified_status"))).append("'>")
                                .append(safe(statusText(rs.getString("verified_status")))).append("</span></td>")
                                .append("<td>").append(safe(rs.getString("location_name"))).append("</td>")
                                .append("<td>").append(safe(rs.getString("actual_employee_name"))).append("</td>")
                                .append("<td>").append(safe(rs.getString("verified_by"))).append("</td>")
                                .append("<td>").append(safe(rs.getString("verified_on"))).append("</td>")
                                .append("<td>").append(safe(shortText(rs.getString("remarks"), 90))).append("</td>")
                                .append("</tr>");
                    }
                }
            }

            String disposalSql = "SELECT disposal_date, disposal_reason, disposal_value, approved_by, created_at "
                    + "FROM asset_disposal "
                    + "WHERE asset_id = ? "
                    + "ORDER BY disposal_id DESC";

            try (PreparedStatement ps = con.prepareStatement(disposalSql)) {
                ps.setInt(1, assetId);

                try (ResultSet rs = ps.executeQuery()) {
                    while (rs.next()) {
                        disposalRows.append("<tr>")
                                .append("<td>").append(safe(rs.getString("disposal_date"))).append("</td>")
                                .append("<td>").append(safe(shortText(rs.getString("disposal_reason"), 90))).append("</td>")
                                .append("<td>").append(safe(moneyText(rs.getString("disposal_value")))).append("</td>")
                                .append("<td>").append(safe(rs.getString("approved_by"))).append("</td>")
                                .append("<td>").append(safe(rs.getString("created_at"))).append("</td>")
                                .append("</tr>");
                    }
                }
            }
        }

    } catch (Exception e) {
        e.printStackTrace();
    }

    if (!found) {
%>

<!DOCTYPE html>
<html>
<head>
    <title>IR-AMS Railway Asset Register Card</title>
    <link rel="stylesheet" href="css/ir-glass.css?v=5000">
    <link rel="stylesheet"
          href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.0/css/all.min.css">
</head>
<body>
    <div style="padding:40px;">
        <div class="page-error">
            <i class="fa-solid fa-triangle-exclamation"></i>
            Asset record not found.
            <br><br>
            <a href="assets.jsp" class="btn">Back to Assets</a>
        </div>
    </div>
</body>
</html>

<%
        return;
    }

    String assetCode = get(asset, "asset_code");
    String railwayAssetNo = get(asset, "railway_asset_no");
    String assetName = get(asset, "asset_name");
    String qrPublicToken = get(asset, "qr_public_token");

    if ("-".equals(qrPublicToken)) {
        qrPublicToken = "IRAMS-" + assetCode;
    }

    String portText = "";
    int port = request.getServerPort();

    if (port != 80 && port != 443) {
        portText = ":" + port;
    }

    String appBaseUrl = request.getScheme() + "://" + request.getServerName() + portText + request.getContextPath();
    String publicScanUrl = appBaseUrl + "/public_scan_result.jsp?qr=" + URLEncoder.encode(qrPublicToken, "UTF-8");
    String encodedQrUrl = URLEncoder.encode(publicScanUrl, "UTF-8");

    String assetStatus = get(asset, "asset_status");
    String serviceStatus = get(asset, "service_status");
    String criticality = get(asset, "asset_criticality");

    String assignedEmployee = get(asset, "assigned_employee_name");
    String assignedEmployeeCode = get(asset, "assigned_employee_code");
    String assignedDepartment = get(asset, "assigned_department_name");

    if ("-".equals(assignedEmployee.trim())) {
        assignedEmployee = "Not Allocated";
        assignedEmployeeCode = "-";
        assignedDepartment = "-";
    }
%>

<!DOCTYPE html>
<html>
<head>
    <title>IR-AMS Railway Asset Register Card</title>

    <link rel="stylesheet"
          href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.0/css/all.min.css">

    <link rel="stylesheet" href="css/ir-glass.css?v=5000">

    <link rel="stylesheet" href="css/asset_register_card.css?v=28001">
</head>

<body>

<div class="app">

    <jsp:include page="sidebar.jsp" />

    <main class="main">

        <jsp:include page="topbar.jsp" />

        <div class="main-scroll-content register-card-page">

            <div class="register-top">

                <section class="register-title-card">
                    <h1>Railway Asset Register Card</h1>

                    <p>
                        Official railway asset record showing asset identity, section mapping,
                        current allocation, service condition, warranty, QR verification,
                        maintenance, return and physical verification history.
                    </p>

                    <div class="register-id-strip">
                        <span class="register-pill">
                            <i class="fa-solid fa-hashtag"></i>
                            Asset Code: <%= safe(assetCode) %>
                        </span>

                        <span class="register-pill">
                            <i class="fa-solid fa-train"></i>
                            Railway Asset No: <%= safe(railwayAssetNo) %>
                        </span>

                        <span class="register-pill">
                            <i class="fa-solid fa-qrcode"></i>
                            QR Token: <%= safe(qrPublicToken) %>
                        </span>
                    </div>

                    <div class="action-bar">
                        <a href="assets.jsp" class="pro-btn">
                            <i class="fa-solid fa-arrow-left"></i> Back to Assets
                        </a>

                        <a href="view_asset.jsp?id=<%= assetId %>" class="pro-btn green">
                            <i class="fa-solid fa-circle-info"></i> Inspect
                        </a>

                        <a href="<%= publicScanUrl %>" target="_blank" class="pro-btn orange">
                            <i class="fa-solid fa-up-right-from-square"></i> Open QR Verification
                        </a>

                        <% if (canManageAssets) { %>
                            <a href="edit_asset.jsp?id=<%= assetId %>" class="pro-btn">
                                <i class="fa-solid fa-pen-to-square"></i> Edit Asset
                            </a>
                        <% } %>

                        <a href="#" onclick="window.print(); return false;" class="pro-btn red">
                            <i class="fa-solid fa-print"></i> Print Register Card
                        </a>
                    </div>
                </section>

                <section class="qr-card">
                    <img src="https://api.qrserver.com/v1/create-qr-code/?size=220x220&data=<%= encodedQrUrl %>"
                         alt="Asset QR Code">

                    <h3>Dynamic QR Verification</h3>
                    <p>
                        Printed QR opens live database details. Updating asset data automatically
                        updates the scanned result.
                    </p>
                </section>

            </div>

            <div class="register-grid">

                <div>

                    <section class="register-panel">
                        <h2><i class="fa-solid fa-id-card-clip"></i> Asset Identity</h2>

                        <div class="info-grid">
                            <div class="info-item">
                                <span>Asset Name</span>
                                <strong><%= safe(assetName) %></strong>
                            </div>

                            <div class="info-item">
                                <span>Category</span>
                                <strong><%= safe(get(asset, "category_name")) %></strong>
                            </div>

                            <div class="info-item">
                                <span>Make / Brand</span>
                                <strong><%= safe(get(asset, "make_brand")) %></strong>
                            </div>

                            <div class="info-item">
                                <span>Model Number</span>
                                <strong><%= safe(get(asset, "model_number")) %></strong>
                            </div>

                            <div class="info-item">
                                <span>Serial Number</span>
                                <strong><%= safe(get(asset, "serial_number")) %></strong>
                            </div>

                            <div class="info-item">
                                <span>Supplier / Vendor</span>
                                <strong><%= safe(get(asset, "vendor_name")) %></strong>
                            </div>
                        </div>
                    </section>

                    <section class="register-panel">
                        <h2><i class="fa-solid fa-location-dot"></i> Railway Office Mapping</h2>

                        <div class="info-grid">
                            <div class="info-item">
                                <span>Railway Zone</span>
                                <strong><%= safe(get(asset, "zone_name")) %></strong>
                            </div>

                            <div class="info-item">
                                <span>Office Type</span>
                                <strong><%= safe(officeTypeText(get(asset, "office_type_code"))) %></strong>
                            </div>

                            <div class="info-item">
                                <span>Division / Office Level</span>
                                <strong><%= safe(get(asset, "division_name")) %></strong>
                            </div>

                            <div class="info-item">
                                <span>Section</span>
                                <strong><%= safe(get(asset, "section_name")) %></strong>
                            </div>

                            <div class="info-item">
                                <span>Office</span>
                                <strong><%= safe(get(asset, "office_name")) %></strong>
                            </div>

                            <div class="info-item">
                                <span>Building / Room</span>
                                <strong>
                                    <%= safe(get(asset, "building_name")) %>
                                    <br>
                                    <%= safe(get(asset, "floor_no")) %>
                                    /
                                    <%= safe(get(asset, "room_no")) %>
                                </strong>
                            </div>

                            <div class="info-item">
                                <span>Location</span>
                                <strong><%= safe(get(asset, "location_name")) %></strong>
                            </div>

                            <div class="info-item">
                                <span>Location Code</span>
                                <strong><%= safe(get(asset, "location_code")) %></strong>
                            </div>
                        </div>
                    </section>

                    <section class="register-panel">
                        <h2><i class="fa-solid fa-user-check"></i> Current Allocation Details</h2>

                        <div class="info-grid">
                            <div class="info-item">
                                <span>Assigned Employee</span>
                                <strong><%= safe(assignedEmployee) %></strong>
                            </div>

                            <div class="info-item">
                                <span>Employee Code</span>
                                <strong><%= safe(assignedEmployeeCode) %></strong>
                            </div>

                            <div class="info-item">
                                <span>Designation</span>
                                <strong><%= safe(get(asset, "assigned_employee_designation")) %></strong>
                            </div>

                            <div class="info-item">
                                <span>Assigned Department</span>
                                <strong><%= safe(assignedDepartment) %></strong>
                            </div>

                            <div class="info-item">
                                <span>Allocation Date</span>
                                <strong><%= safe(get(asset, "allocation_date")) %></strong>
                            </div>

                            <div class="info-item">
                                <span>Allocation Status</span>
                                <strong><%= safe(statusText(get(asset, "allocation_status"))) %></strong>
                            </div>
                        </div>
                    </section>

                </div>

                <div>

                    <section class="register-panel">
                        <h2><i class="fa-solid fa-signal"></i> Operational Status</h2>

                        <div class="info-grid">
                            <div class="info-item">
                                <span>Asset Status</span>
                                <strong>
                                    <span class="status-badge-main status-<%= statusClass(assetStatus) %>">
                                        <%= safe(statusText(assetStatus)) %>
                                    </span>
                                </strong>
                            </div>

                            <div class="info-item">
                                <span>Service Status</span>
                                <strong>
                                    <span class="status-badge-main status-<%= statusClass(serviceStatus) %>">
                                        <%= safe(statusText(serviceStatus)) %>
                                    </span>
                                </strong>
                            </div>

                            <div class="info-item">
                                <span>Criticality</span>
                                <strong>
                                    <span class="status-badge-main status-<%= statusClass(criticality) %>">
                                        <%= safe(statusText(criticality)) %>
                                    </span>
                                </strong>
                            </div>

                            <div class="info-item">
                                <span>Last QR Scan</span>
                                <strong><%= safe(get(asset, "last_qr_scan_at")) %></strong>
                            </div>
                        </div>
                    </section>

                    <section class="register-panel">
                        <h2><i class="fa-solid fa-indian-rupee-sign"></i> Purchase & Warranty</h2>

                        <div class="info-grid">
                            <div class="info-item">
                                <span>Purchase Date</span>
                                <strong><%= safe(get(asset, "purchase_date")) %></strong>
                            </div>

                            <div class="info-item">
                                <span>Purchase Cost</span>
                                <strong><%= safe(moneyText(get(asset, "purchase_cost"))) %></strong>
                            </div>

                            <div class="info-item">
                                <span>Warranty Expiry</span>
                                <strong><%= safe(get(asset, "warranty_expiry")) %></strong>
                            </div>

                            <div class="info-item">
                                <span>Depreciation Rate</span>
                                <strong><%= safe(get(asset, "depreciation_rate")) %>%</strong>
                            </div>
                        </div>
                    </section>

                    <section class="register-panel">
                        <h2><i class="fa-solid fa-clipboard-check"></i> Verification Summary</h2>

                        <div class="info-grid">
                            <div class="info-item">
                                <span>Last Physical Verification</span>
                                <strong><%= safe(get(asset, "last_physical_verification_date")) %></strong>
                            </div>

                            <div class="info-item">
                                <span>QR Public Token</span>
                                <strong><%= safe(qrPublicToken) %></strong>
                            </div>
                        </div>

                        <p class="print-note">
                            This card is generated from live IR-AMS database records and can be used for
                            internal review, asset inspection, QR verification and physical verification.
                        </p>
                    </section>

                </div>

            </div>

            <section class="register-panel">
                <h2><i class="fa-solid fa-clock-rotate-left"></i> Allocation History</h2>

                <% if (allocationRows.length() == 0) { %>
                    <div class="empty-row">No allocation history found for this asset.</div>
                <% } else { %>
                    <table class="timeline-table">
                        <thead>
                            <tr>
                                <th>Allocation ID</th>
                                <th>Employee Code</th>
                                <th>Employee Name</th>
                                <th>Designation</th>
                                <th>Department</th>
                                <th>Issue Date</th>
                                <th>Return Date</th>
                                <th>Status</th>
                            </tr>
                        </thead>
                        <tbody>
                            <%= allocationRows.toString() %>
                        </tbody>
                    </table>
                <% } %>
            </section>

            <section class="register-panel">
                <h2><i class="fa-solid fa-screwdriver-wrench"></i> Maintenance & Repair History</h2>

                <% if (maintenanceRows.length() == 0) { %>
                    <div class="empty-row">No maintenance or repair record found for this asset.</div>
                <% } else { %>
                    <table class="timeline-table">
                        <thead>
                            <tr>
                                <th>ID</th>
                                <th>Date</th>
                                <th>Type</th>
                                <th>Performed By</th>
                                <th>Cost</th>
                                <th>Remarks</th>
                            </tr>
                        </thead>
                        <tbody>
                            <%= maintenanceRows.toString() %>
                        </tbody>
                    </table>
                <% } %>
            </section>

            <section class="register-panel">
                <h2><i class="fa-solid fa-rotate-left"></i> Return & Condition History</h2>

                <% if (returnRows.length() == 0) { %>
                    <div class="empty-row">No return record found for this asset.</div>
                <% } else { %>
                    <table class="timeline-table">
                        <thead>
                            <tr>
                                <th>Return ID</th>
                                <th>Allocation ID</th>
                                <th>Return Date</th>
                                <th>Condition</th>
                                <th>Received By</th>
                                <th>Remarks</th>
                            </tr>
                        </thead>
                        <tbody>
                            <%= returnRows.toString() %>
                        </tbody>
                    </table>
                <% } %>
            </section>

            <section class="register-panel">
                <h2><i class="fa-solid fa-qrcode"></i> QR Verification Activity</h2>

                <% if (scanRows.length() == 0) { %>
                    <div class="empty-row">No QR verification activity recorded yet.</div>
                <% } else { %>
                    <table class="timeline-table">
                        <thead>
                            <tr>
                                <th>Source</th>
                                <th>Result</th>
                                <th>IP Address</th>
                                <th>Scanned At</th>
                            </tr>
                        </thead>
                        <tbody>
                            <%= scanRows.toString() %>
                        </tbody>
                    </table>
                <% } %>
            </section>

            <section class="register-panel">
                <h2><i class="fa-solid fa-list-check"></i> Physical Verification Register</h2>

                <% if (verificationRows.length() == 0) { %>
                    <div class="empty-row">No physical verification record found yet.</div>
                <% } else { %>
                    <table class="timeline-table">
                        <thead>
                            <tr>
                                <th>Status</th>
                                <th>Actual Location</th>
                                <th>Actual Employee</th>
                                <th>Verified By</th>
                                <th>Verified On</th>
                                <th>Remarks</th>
                            </tr>
                        </thead>
                        <tbody>
                            <%= verificationRows.toString() %>
                        </tbody>
                    </table>
                <% } %>
            </section>

            <section class="register-panel">
                <h2><i class="fa-solid fa-recycle"></i> Condemnation / Disposal Register</h2>

                <% if (disposalRows.length() == 0) { %>
                    <div class="empty-row">No condemnation or disposal record found for this asset.</div>
                <% } else { %>
                    <table class="timeline-table">
                        <thead>
                            <tr>
                                <th>Disposal Date</th>
                                <th>Reason</th>
                                <th>Disposal Value</th>
                                <th>Approved By</th>
                                <th>Recorded At</th>
                            </tr>
                        </thead>
                        <tbody>
                            <%= disposalRows.toString() %>
                        </tbody>
                    </table>
                <% } %>
            </section>

        </div>

    </main>

</div>
<script src="js/user-dropdown.js"></script>
<script src="js/topbar-search.js"></script>
<script src="js/global-live-search.js"></script>

<script>
    function changeRailBackground() {
        const total = 7;
        const next = Math.floor(Math.random() * total) + 1;

        document.body.style.backgroundImage =
                "linear-gradient(rgba(0,0,0,0.35), rgba(0,0,0,0.35)), url('<%= request.getContextPath() %>/images/rail-bg-" + next + ".jpg')";
    }
</script>

</body>
</html>