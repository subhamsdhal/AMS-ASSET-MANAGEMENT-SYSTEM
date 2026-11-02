﻿<%@page contentType="text/html" pageEncoding="UTF-8"%>
<%@page import="com.mycompany.asset_management_system_ams.Asset"%>
<%@page import="com.mycompany.asset_management_system_ams.AssetDAO"%>
<%@page import="com.mycompany.asset_management_system_ams.DBConnection"%>
<%@page import="java.sql.*"%>
<%@page import="java.text.DecimalFormat"%>
<%@page import="java.net.URLDecoder"%>

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

    private String money(double value) {
        DecimalFormat df = new DecimalFormat("#,##0.00");
        return "₹" + df.format(value);
    }

    private String moneyText(Object value) {
        try {
            if (value == null) {
                return "-";
            }

            double amount = Double.parseDouble(value.toString());
            DecimalFormat df = new DecimalFormat("#,##0.00");
            return "₹" + df.format(amount);

        } catch (Exception e) {
            return "-";
        }
    }

    private String statusClass(String status) {
        if (status == null) {
            return "UNKNOWN";
        }

        return status.trim().toUpperCase().replace(" ", "_");
    }

    private Asset findAssetFlexibly(String scannedValue) {

        if (scannedValue == null || scannedValue.trim().isEmpty()) {
            return null;
        }

        String value = scannedValue.trim();

        try {
            if (value.contains("qr=")) {
                String qrPart = value.substring(value.indexOf("qr=") + 3);

                if (qrPart.contains("&")) {
                    qrPart = qrPart.substring(0, qrPart.indexOf("&"));
                }

                value = URLDecoder.decode(qrPart, "UTF-8").trim();
            }
        } catch (Exception e) {
            // Continue with original value
        }

        AssetDAO dao = new AssetDAO();

        Asset asset = dao.getAssetByQrCode(value);

        if (asset != null) {
            return asset;
        }

        String possibleAssetCode = value;

        if (possibleAssetCode.toUpperCase().startsWith("IRAMS-")) {
            possibleAssetCode = possibleAssetCode.substring(6);
        }

        if (possibleAssetCode.toUpperCase().startsWith("QR-")) {
            possibleAssetCode = possibleAssetCode.substring(3);
        }

        String noSpaceAssetCode = possibleAssetCode.replace(" ", "");
        String noSpaceValue = value.replace(" ", "");

        String sql = "SELECT asset_id FROM assets "
                + "WHERE asset_code = ? "
                + "OR asset_code = ? "
                + "OR qr_code = ? "
                + "OR qr_code = ? "
                + "OR qr_code = ? "
                + "OR qr_code = ? "
                + "LIMIT 1";

        try (
                Connection con = DBConnection.getConnection();
                PreparedStatement ps = con.prepareStatement(sql)
        ) {
            ps.setString(1, possibleAssetCode);
            ps.setString(2, noSpaceAssetCode);
            ps.setString(3, value);
            ps.setString(4, noSpaceValue);
            ps.setString(5, "IRAMS-" + noSpaceAssetCode);
            ps.setString(6, "QR-" + noSpaceAssetCode);

            try (ResultSet rs = ps.executeQuery()) {
                if (rs.next()) {
                    return dao.getAssetById(rs.getInt("asset_id"));
                }
            }

        } catch (Exception e) {
            e.printStackTrace();
        }

        return null;
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

    String qrCode = request.getParameter("qr");

    Asset asset = null;

    if (qrCode != null && !qrCode.trim().isEmpty()) {
        asset = findAssetFlexibly(qrCode.trim());
    }

    boolean hasAllocation = false;
    String allocationEmployeeCode = "-";
    String allocationEmployeeName = "-";
    String allocationDepartment = "-";
    String allocationDesignation = "-";
    String allocationDate = "-";
    String allocationStatus = "No Active Allocation";

    boolean hasMaintenance = false;
    String maintenanceDate = "-";
    String maintenanceType = "-";
    String maintenancePerformedBy = "-";
    String maintenanceCost = "-";
    String maintenanceRemarks = "-";

    boolean hasDisposal = false;
    String disposalDate = "-";
    String disposalReason = "-";
    String disposalValue = "-";
    String disposalApprovedBy = "-";

    StringBuilder returnRows = new StringBuilder();
    int returnCount = 0;

    if (asset != null) {

        int assetId = asset.getAssetId();

        try (Connection con = DBConnection.getConnection()) {

            String allocationSql = "SELECT aa.allocation_date, aa.allocation_status, "
                    + "e.employee_code, "
                    + "e.employee_name AS employee_name, "
                    + "e.designation, d.department_name "
                    + "FROM asset_allocation aa "
                    + "JOIN employees e ON aa.employee_id = e.employee_id "
                    + "LEFT JOIN departments d ON e.department_id = d.department_id "
                    + "WHERE aa.asset_id = ? "
                    + "AND aa.allocation_status = 'ALLOCATED' "
                    + "ORDER BY aa.allocation_id DESC "
                    + "LIMIT 1";

            try (PreparedStatement ps = con.prepareStatement(allocationSql)) {
                ps.setInt(1, assetId);

                try (ResultSet rs = ps.executeQuery()) {
                    if (rs.next()) {
                        hasAllocation = true;
                        allocationEmployeeCode = rs.getString("employee_code");
                        allocationEmployeeName = rs.getString("employee_name");
                        allocationDepartment = rs.getString("department_name");
                        allocationDesignation = rs.getString("designation");
                        allocationDate = rs.getString("allocation_date");
                        allocationStatus = rs.getString("allocation_status");
                    }
                }
            }

            String maintenanceSql = "SELECT maintenance_date, maintenance_type, "
                    + "performed_by, cost, description "
                    + "FROM maintenance_logs "
                    + "WHERE asset_id = ? "
                    + "ORDER BY maintenance_date DESC, maintenance_id DESC "
                    + "LIMIT 1";

            try (PreparedStatement ps = con.prepareStatement(maintenanceSql)) {
                ps.setInt(1, assetId);

                try (ResultSet rs = ps.executeQuery()) {
                    if (rs.next()) {
                        hasMaintenance = true;
                        maintenanceDate = rs.getString("maintenance_date");
                        maintenanceType = rs.getString("maintenance_type");
                        maintenancePerformedBy = rs.getString("performed_by");
                        maintenanceCost = moneyText(rs.getString("cost"));
                        maintenanceRemarks = rs.getString("description");
                    }
                }
            }

            String returnSql = "SELECT r.return_date, r.return_condition, "
                    + "r.received_by, r.remarks "
                    + "FROM asset_returns r "
                    + "JOIN asset_allocation aa ON r.allocation_id = aa.allocation_id "
                    + "WHERE aa.asset_id = ? "
                    + "ORDER BY r.return_date DESC, r.return_id DESC "
                    + "LIMIT 5";

            try (PreparedStatement ps = con.prepareStatement(returnSql)) {
                ps.setInt(1, assetId);

                try (ResultSet rs = ps.executeQuery()) {
                    while (rs.next()) {
                        returnCount++;

                        returnRows.append("<tr>")
                                .append("<td>").append(safe(rs.getString("return_date"))).append("</td>")
                                .append("<td>").append(safe(rs.getString("return_condition"))).append("</td>")
                                .append("<td>").append(safe(rs.getString("received_by"))).append("</td>")
                                .append("<td>").append(safe(rs.getString("remarks"))).append("</td>")
                                .append("</tr>");
                    }
                }
            }

            String disposalSql = "SELECT disposal_date, disposal_reason, "
                    + "disposal_value, approved_by "
                    + "FROM asset_disposal "
                    + "WHERE asset_id = ? "
                    + "ORDER BY disposal_id DESC "
                    + "LIMIT 1";

            try (PreparedStatement ps = con.prepareStatement(disposalSql)) {
                ps.setInt(1, assetId);

                try (ResultSet rs = ps.executeQuery()) {
                    if (rs.next()) {
                        hasDisposal = true;
                        disposalDate = rs.getString("disposal_date");
                        disposalReason = rs.getString("disposal_reason");
                        disposalValue = moneyText(rs.getString("disposal_value"));
                        disposalApprovedBy = rs.getString("approved_by");
                    }
                }
            }

        } catch (Exception e) {
            e.printStackTrace();
        }
    }
%>

<!DOCTYPE html>
<html>
<head>
    <title>IR-AMS Advanced QR Scan Result</title>

    <link rel="stylesheet"
          href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.0/css/all.min.css">

    <link rel="stylesheet" href="css/ir-glass.css?v=system-audit-scanner-1">
    <link rel="stylesheet" href="css/ams-pro.css?v=system-audit-scanner-1">
    <link rel="stylesheet" href="css/ir-ams-railway-ui.css?v=system-audit-scanner-1">
<link rel="stylesheet" href="css/scan_result.css?v=topbarfix1">
</head>

<body class="railway-ui">

<div class="app">

        <jsp:include page="sidebar.jsp" />

    <main class="main railway-main">

                <jsp:include page="topbar.jsp" />

        <div class="main-scroll-content">

            <section class="scan-advanced-hero">
                <h1>Advanced QR Asset Verification</h1>

                <p>
                    Live asset lifecycle lookup from IR-AMS database using QR identity:
                    <strong><%= safe(qrCode == null ? "No QR Provided" : qrCode) %></strong>.
                    QR contains only asset identity; all details below are fetched live from database.
                </p>

                <br>

                <div class="hero-pills">
                    <div class="hero-pill"><i class="fa-solid fa-qrcode"></i> QR Lookup</div>
                    <div class="hero-pill"><i class="fa-solid fa-database"></i> Live Database</div>
                    <div class="hero-pill"><i class="fa-solid fa-user-check"></i> Custody Tracking</div>
                    <div class="hero-pill"><i class="fa-solid fa-screwdriver-wrench"></i> Lifecycle View</div>
                </div>
            </section>

            <section class="glass-panel">

                <%
                    if (asset == null) {
                %>

                    <div class="scan-error-box">
                        <i class="fa-solid fa-triangle-exclamation"></i>
                        No asset found for QR code:
                        <%= safe(qrCode == null ? "Not Provided" : qrCode) %>
                    </div>

                    <div class="scan-action-row">
                        <a href="qr_scanner.jsp" class="btn">
                            <i class="fa-solid fa-qrcode"></i> Scan Again
                        </a>

                        <a href="assets.jsp" class="btn">
                            <i class="fa-solid fa-list"></i> Asset Registry
                        </a>
                    </div>

                <%
                    } else {
                %>

                    <div class="scan-success-box">
                        <i class="fa-solid fa-circle-check"></i>
                        Asset found successfully. Showing complete live lifecycle details.
                    </div>

                    <h2 class="scan-section-title">
                        <i class="fa-solid fa-id-card"></i>
                        Asset Identity
                    </h2>

                    <div class="scan-card-grid">
                        <div class="scan-info-card">
                            <h3>Asset Code</h3>
                            <p><%= safe(asset.getAssetCode()) %></p>
                        </div>

                        <div class="scan-info-card">
                            <h3>Asset Name</h3>
                            <p><%= safe(asset.getAssetName()) %></p>
                        </div>

                        <div class="scan-info-card">
                            <h3>QR Code</h3>
                            <p><%= safe(asset.getQrCode()) %></p>
                        </div>

                        <div class="scan-info-card">
                            <h3>Serial Number</h3>
                            <p><%= safe(asset.getSerialNumber()) %></p>
                        </div>
                    </div>

                    <h2 class="scan-section-title">
                        <i class="fa-solid fa-layer-group"></i>
                        Classification
                    </h2>

                    <div class="scan-card-grid">
                        <div class="scan-info-card">
                            <h3>Category</h3>
                            <p><%= safe(asset.getCategoryName()) %></p>
                        </div>

                        <div class="scan-info-card">
                            <h3>Vendor</h3>
                            <p><%= safe(asset.getVendorName()) %></p>
                        </div>
                    </div>

                    <h2 class="scan-section-title">
                        <i class="fa-solid fa-location-dot"></i>
                        Location & Status
                    </h2>

                    <div class="scan-card-grid">
                        <div class="scan-info-card">
                            <h3>Current Location</h3>
                            <p><%= safe(asset.getLocation()) %></p>
                        </div>

                        <div class="scan-info-card">
                            <h3>Current Status</h3>
                            <p>
                                <span class="status-badge-qr status-<%= statusClass(asset.getAssetStatus()) %>">
                                    <i class="fa-solid fa-circle"></i>
                                    <%= safe(asset.getAssetStatus()) %>
                                </span>
                            </p>
                        </div>
                    </div>

                    <h2 class="scan-section-title">
                        <i class="fa-solid fa-file-invoice"></i>
                        Purchase & Warranty
                    </h2>

                    <div class="scan-card-grid">
                        <div class="scan-info-card">
                            <h3>Purchase Date</h3>
                            <p><%= safe(asset.getPurchaseDate()) %></p>
                        </div>

                        <div class="scan-info-card">
                            <h3>Purchase Cost</h3>
                            <p><%= money(asset.getPurchaseCost()) %></p>
                        </div>

                        <div class="scan-info-card">
                            <h3>Warranty Expiry</h3>
                            <p><%= safe(asset.getWarrantyExpiry()) %></p>
                        </div>

                        <div class="scan-info-card">
                            <h3>Depreciation Rate</h3>
                            <p><%= asset.getDepreciationRate() %>%</p>
                        </div>
                    </div>

                    <h2 class="scan-section-title">
                        <i class="fa-solid fa-user-check"></i>
                        Current Employee Allocation
                    </h2>

                    <div class="scan-card-grid">
                        <div class="scan-info-card">
                            <h3>Allocation Status</h3>
                            <p><%= safe(allocationStatus) %></p>
                        </div>

                        <div class="scan-info-card">
                            <h3>Employee Code</h3>
                            <p><%= hasAllocation ? safe(allocationEmployeeCode) : "Not Allocated" %></p>
                        </div>

                        <div class="scan-info-card">
                            <h3>Employee Name</h3>
                            <p><%= hasAllocation ? safe(allocationEmployeeName) : "Not Allocated" %></p>
                        </div>

                        <div class="scan-info-card">
                            <h3>Department</h3>
                            <p><%= hasAllocation ? safe(allocationDepartment) : "Not Allocated" %></p>
                        </div>

                        <div class="scan-info-card">
                            <h3>Designation</h3>
                            <p><%= hasAllocation ? safe(allocationDesignation) : "Not Allocated" %></p>
                        </div>

                        <div class="scan-info-card">
                            <h3>Allocation Date</h3>
                            <p><%= hasAllocation ? safe(allocationDate) : "Not Allocated" %></p>
                        </div>
                    </div>

                    <h2 class="scan-section-title">
                        <i class="fa-solid fa-screwdriver-wrench"></i>
                        Maintenance Status
                    </h2>

                    <div class="scan-card-grid">
                        <div class="scan-info-card">
                            <h3>Latest Maintenance Date</h3>
                            <p><%= hasMaintenance ? safe(maintenanceDate) : "No Maintenance Record" %></p>
                        </div>

                        <div class="scan-info-card">
                            <h3>Maintenance Type</h3>
                            <p><%= hasMaintenance ? safe(maintenanceType) : "No Maintenance Record" %></p>
                        </div>

                        <div class="scan-info-card">
                            <h3>Performed By</h3>
                            <p><%= hasMaintenance ? safe(maintenancePerformedBy) : "No Maintenance Record" %></p>
                        </div>

                        <div class="scan-info-card">
                            <h3>Cost</h3>
                            <p><%= hasMaintenance ? safe(maintenanceCost) : "No Maintenance Record" %></p>
                        </div>

                        <div class="scan-info-card">
                            <h3>Latest Remarks</h3>
                            <p><%= hasMaintenance ? safe(maintenanceRemarks) : "No Maintenance Record" %></p>
                        </div>
                    </div>

                    <h2 class="scan-section-title">
                        <i class="fa-solid fa-rotate-left"></i>
                        Return History
                    </h2>

                    <%
                        if (returnCount == 0) {
                    %>
                        <div class="scan-empty-box">
                            <i class="fa-solid fa-circle-info"></i>
                            No return history found for this asset.
                        </div>
                    <%
                        } else {
                    %>
                        <div class="scan-table-wrap">
                            <table class="scan-life-table">
                                <thead>
                                    <tr>
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
                        </div>
                    <%
                        }
                    %>

                    <h2 class="scan-section-title">
                        <i class="fa-solid fa-trash-can"></i>
                        Disposal Status
                    </h2>

                    <div class="scan-card-grid">
                        <div class="scan-info-card">
                            <h3>Disposed / Not Disposed</h3>
                            <p><%= hasDisposal ? "Disposed" : "Not Disposed" %></p>
                        </div>

                        <div class="scan-info-card">
                            <h3>Disposal Date</h3>
                            <p><%= hasDisposal ? safe(disposalDate) : "Not Disposed" %></p>
                        </div>

                        <div class="scan-info-card">
                            <h3>Disposal Reason</h3>
                            <p><%= hasDisposal ? safe(disposalReason) : "Not Disposed" %></p>
                        </div>

                        <div class="scan-info-card">
                            <h3>Disposal Value</h3>
                            <p><%= hasDisposal ? safe(disposalValue) : "Not Disposed" %></p>
                        </div>

                        <div class="scan-info-card">
                            <h3>Approved By</h3>
                            <p><%= hasDisposal ? safe(disposalApprovedBy) : "Not Disposed" %></p>
                        </div>
                    </div>

                    <div class="scan-action-row">
                        <a href="view_asset.jsp?id=<%= asset.getAssetId() %>" class="btn">
                            <i class="fa-solid fa-eye"></i> Full Asset View
                        </a>

                        <a href="assets.jsp" class="btn">
                            <i class="fa-solid fa-list"></i> Asset Registry
                        </a>

                        <a href="qr_scanner.jsp" class="btn">
                            <i class="fa-solid fa-qrcode"></i> Scan Another
                        </a>

                        <a href="qr_tags.jsp?assetId=<%= asset.getAssetId() %>" class="btn">
                            <i class="fa-solid fa-print"></i> Print QR Tag
                        </a>

                        <a href="maintenance_history.jsp?assetId=<%= asset.getAssetId() %>" class="btn">
                            <i class="fa-solid fa-clock-rotate-left"></i> Maintenance History
                        </a>
                    </div>

                <%
                    }
                %>

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

<script src="js/topbar-search.js?v=system-audit-scanner-1"></script>
<script src="js/user-dropdown.js?v=system-audit-scanner-1"></script>
<script src="js/sidebar-role.js?v=system-audit-scanner-1"></script>
<script src="js/ir-body-watermark.js?v=system-audit-scanner-1"></script>
<script src="js/dashboard-actions.js?v=system-audit-scanner-1"></script>

</body>
</html>