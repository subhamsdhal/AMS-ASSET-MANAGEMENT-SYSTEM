﻿<%@page contentType="text/html" pageEncoding="UTF-8"%>
<%@page import="com.mycompany.asset_management_system_ams.DBConnection"%>
<%@page import="com.mycompany.asset_management_system_ams.HtmlEscapeUtil"%>
<%@page import="java.sql.Connection"%>
<%@page import="java.sql.PreparedStatement"%>
<%@page import="java.sql.ResultSet"%>
<%@page import="java.math.BigDecimal"%>
<%@page import="java.text.DecimalFormat"%>

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

    boolean canRenewWarranty = "SUPER_ADMIN".equals(role) || "ADMIN".equals(role) || "ASSET_MANAGER".equals(role);

    DecimalFormat moneyFormat = new DecimalFormat("#,##0.00");

    int totalAssets = 0;
    int activeWarranty = 0;
    int expiringSoon = 0;
    int expiredWarranty = 0;
    int noWarranty = 0;

    try {
        Connection con = DBConnection.getConnection();

        PreparedStatement kpiPs = con.prepareStatement(
                "SELECT "
                + "COUNT(*) AS total_assets, "
                + "SUM(CASE WHEN warranty_expiry IS NOT NULL AND warranty_expiry > DATE_ADD(CURDATE(), INTERVAL 30 DAY) THEN 1 ELSE 0 END) AS active_warranty, "
                + "SUM(CASE WHEN warranty_expiry IS NOT NULL AND warranty_expiry BETWEEN CURDATE() AND DATE_ADD(CURDATE(), INTERVAL 30 DAY) THEN 1 ELSE 0 END) AS expiring_soon, "
                + "SUM(CASE WHEN warranty_expiry IS NOT NULL AND warranty_expiry < CURDATE() THEN 1 ELSE 0 END) AS expired_warranty, "
                + "SUM(CASE WHEN warranty_expiry IS NULL THEN 1 ELSE 0 END) AS no_warranty "
                + "FROM assets"
        );

        ResultSet kpiRs = kpiPs.executeQuery();

        if (kpiRs.next()) {
            totalAssets = kpiRs.getInt("total_assets");
            activeWarranty = kpiRs.getInt("active_warranty");
            expiringSoon = kpiRs.getInt("expiring_soon");
            expiredWarranty = kpiRs.getInt("expired_warranty");
            noWarranty = kpiRs.getInt("no_warranty");
        }

    } catch (Exception e) {
        e.printStackTrace();
    }

    String reportMsg = request.getParameter("msg");
%>

<!DOCTYPE html>
<html>
<head>
    <title>IR-AMS Warranty Report</title>

    <link rel="stylesheet"
          href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.0/css/all.min.css">

    <link rel="stylesheet" href="css/ir-glass.css?v=28000">
    <link rel="stylesheet" href="css/ams-pro.css?v=28000">
    <link rel="stylesheet" href="css/ir-ams-railway-ui.css?v=28000">
<link rel="stylesheet" href="css/warranty_report.css?v=topbarfix1">
</head>

<body class="railway-ui">

<div class="app">

    <jsp:include page="sidebar.jsp" />

    <main class="main railway-main">
        <jsp:include page="topbar.jsp" />

        <div class="main-scroll-content">

            <section class="asset-hero">
                <h1>Warranty Tracking Report</h1>

                <p>
                    Monitor railway asset warranty validity, expired assets, assets expiring soon,
                    vendor responsibility and lifecycle support readiness.
                </p>

                <br>

                <div class="hero-pills">
                    <div class="hero-pill">
                        <i class="fa-solid fa-shield-halved"></i> Warranty Control
                    </div>

                    <div class="hero-pill">
                        <i class="fa-solid fa-clock"></i> Expiry Tracking
                    </div>

                    <div class="hero-pill">
                        <i class="fa-solid fa-truck-field"></i> Vendor Visibility
                    </div>

                    <div class="hero-pill">
                        <i class="fa-solid fa-file-lines"></i> Report Ready
                    </div>
                </div>
            </section>

            <% if ("renewed".equals(reportMsg)) { %>
                <div class="page-success">
                    <i class="fa-solid fa-circle-check"></i>
                    Warranty renewal recorded and asset expiry updated.
                </div>
            <% } %>

            <section class="kpi-grid warranty-kpi-grid">

                <div class="kpi-card">
                    <div class="kpi-icon purple">
                        <i class="fa-solid fa-boxes-stacked"></i>
                    </div>
                    <h3>Total Assets</h3>
                    <p><%= totalAssets %></p>
                </div>

                <div class="kpi-card">
                    <div class="kpi-icon green">
                        <i class="fa-solid fa-circle-check"></i>
                    </div>
                    <h3>Active Warranty</h3>
                    <p><%= activeWarranty %></p>
                </div>

                <div class="kpi-card">
                    <div class="kpi-icon orange">
                        <i class="fa-solid fa-clock"></i>
                    </div>
                    <h3>Expiring Soon</h3>
                    <p><%= expiringSoon %></p>
                </div>

                <div class="kpi-card">
                    <div class="kpi-icon red">
                        <i class="fa-solid fa-triangle-exclamation"></i>
                    </div>
                    <h3>Expired</h3>
                    <p><%= expiredWarranty %></p>
                </div>

                <div class="kpi-card">
                    <div class="kpi-icon blue">
                        <i class="fa-solid fa-circle-info"></i>
                    </div>
                    <h3>No Warranty</h3>
                    <p><%= noWarranty %></p>
                </div>

                <div class="kpi-card">
                    <div class="kpi-icon pink">
                        <i class="fa-solid fa-database"></i>
                    </div>
                    <h3>Live Status</h3>
                    <p>ON</p>
                </div>

            </section>

            <section class="glass-panel">

                <div class="registry-toolbar">

                    <div>
                        <h2>Warranty Control Table</h2>
                        <p class="table-subtext">
                            Live warranty report generated from asset inventory database.
                        </p>
                    </div>

                    <div class="registry-actions">

                        <a href="export_warranty_report.jsp" class="btn">
                            <i class="fa-solid fa-file-excel"></i>
                            Export Excel
                        </a>

                        <a href="reports.jsp" class="btn secondary-btn">
                            <i class="fa-solid fa-arrow-left"></i>
                            Back to Reports
                        </a>

                    </div>

                </div>

                <div class="registry-filter-grid">

                    <div class="registry-search">
                        <i class="fa-solid fa-magnifying-glass"></i>
                        <input type="text"
                               id="warrantySearch"
                               placeholder="Search asset code, asset name, category, vendor, status, location...">
                    </div>

                    <select id="warrantyStatusFilter" class="status-filter-select">
                        <option value="ALL">All Warranty Status</option>
                        <option value="ACTIVE">Active</option>
                        <option value="EXPIRING_SOON">Expiring Soon</option>
                        <option value="EXPIRED">Expired</option>
                        <option value="NO_WARRANTY">No Warranty</option>
                    </select>

                    <button type="button" class="btn" onclick="resetWarrantyFilters()">
                        <i class="fa-solid fa-filter-circle-xmark"></i>
                        Reset Filters
                    </button>

                </div>

                <div class="registry-table-wrap">

                    <table class="asset-table" id="warrantyTable">
                        <thead>
                            <tr>
                                <th>Asset ID</th>
                                <th>Asset Details</th>
                                <th>Category</th>
                                <th>Vendor</th>
                                <th>Purchase Date</th>
                                <th>Warranty Expiry</th>
                                <th>Days Left</th>
                                <th>Purchase Cost</th>
                                <th>Location</th>
                                <th>Warranty Status</th>
                                <th>Action</th>
                            </tr>
                        </thead>

                        <tbody>

                            <%
                                boolean hasRows = false;

                                try {
                                    Connection con = DBConnection.getConnection();

                                    String sql = "SELECT a.asset_id, a.asset_code, a.asset_name, "
                                            + "c.category_name, v.vendor_name, a.purchase_date, "
                                            + "a.warranty_expiry, DATEDIFF(a.warranty_expiry, CURDATE()) AS days_left, "
                                            + "a.purchase_cost, a.location, a.asset_status "
                                            + "FROM assets a "
                                            + "LEFT JOIN asset_categories c ON a.category_id = c.category_id "
                                            + "LEFT JOIN vendors v ON a.vendor_id = v.vendor_id "
                                            + "ORDER BY "
                                            + "CASE "
                                            + "WHEN a.warranty_expiry IS NULL THEN 4 "
                                            + "WHEN a.warranty_expiry < CURDATE() THEN 1 "
                                            + "WHEN a.warranty_expiry BETWEEN CURDATE() AND DATE_ADD(CURDATE(), INTERVAL 30 DAY) THEN 2 "
                                            + "ELSE 3 END, "
                                            + "a.warranty_expiry ASC, a.asset_id ASC";

                                    PreparedStatement ps = con.prepareStatement(sql);
                                    ResultSet rs = ps.executeQuery();

                                    while (rs.next()) {
                                        hasRows = true;

                                        String warrantyExpiry = rs.getString("warranty_expiry");
                                        Object daysObj = rs.getObject("days_left");
                                        int daysLeft = daysObj == null ? 0 : rs.getInt("days_left");

                                        String warrantyStatus;
                                        String warrantyLabel;
                                        String warrantyClass;
                                        String warrantyIcon;

                                        if (warrantyExpiry == null || warrantyExpiry.trim().isEmpty()) {
                                            warrantyStatus = "NO_WARRANTY";
                                            warrantyLabel = "No Warranty";
                                            warrantyClass = "warranty-none";
                                            warrantyIcon = "fa-circle-info";
                                        } else if (daysLeft < 0) {
                                            warrantyStatus = "EXPIRED";
                                            warrantyLabel = "Expired";
                                            warrantyClass = "warranty-expired";
                                            warrantyIcon = "fa-triangle-exclamation";
                                        } else if (daysLeft <= 30) {
                                            warrantyStatus = "EXPIRING_SOON";
                                            warrantyLabel = "Expiring Soon";
                                            warrantyClass = "warranty-expiring";
                                            warrantyIcon = "fa-clock";
                                        } else {
                                            warrantyStatus = "ACTIVE";
                                            warrantyLabel = "Active";
                                            warrantyClass = "warranty-active";
                                            warrantyIcon = "fa-circle-check";
                                        }

                                        BigDecimal purchaseCost = rs.getBigDecimal("purchase_cost");

                                        if (purchaseCost == null) {
                                            purchaseCost = BigDecimal.ZERO;
                                        }
                            %>

                            <tr data-warranty-status="<%= warrantyStatus %>">
                                <td>
                                    <span class="warranty-id-pill">
                                        <%= HtmlEscapeUtil.escape(rs.getString("asset_code")) %>
                                    </span>
                                </td>

                                <td>
                                    <strong><%= HtmlEscapeUtil.escape(rs.getString("asset_name")) %></strong>
                                    <br>
                                    <span class="table-subtext">
                                        Asset status: <%= HtmlEscapeUtil.escape(rs.getString("asset_status"), "-") %>
                                    </span>
                                </td>

                                <td>
                                    <%= HtmlEscapeUtil.escape(rs.getString("category_name"), "-") %>
                                </td>

                                <td>
                                    <%= HtmlEscapeUtil.escape(rs.getString("vendor_name"), "-") %>
                                </td>

                                <td>
                                    <%= rs.getString("purchase_date") == null ? "-" : rs.getString("purchase_date") %>
                                </td>

                                <td>
                                    <%= warrantyExpiry == null ? "-" : warrantyExpiry %>
                                </td>

                                <td>
                                    <% if ("NO_WARRANTY".equals(warrantyStatus)) { %>
                                        <span class="warranty-days-pill">
                                            <i class="fa-solid fa-minus"></i>
                                            N/A
                                        </span>
                                    <% } else if (daysLeft < 0) { %>
                                        <span class="warranty-days-pill">
                                            <i class="fa-solid fa-clock-rotate-left"></i>
                                            <%= Math.abs(daysLeft) %> days overdue
                                        </span>
                                    <% } else { %>
                                        <span class="warranty-days-pill">
                                            <i class="fa-solid fa-calendar-days"></i>
                                            <%= daysLeft %> days
                                        </span>
                                    <% } %>
                                </td>

                                <td>
                                    <span class="warranty-money-pill">
                                        ₹<%= moneyFormat.format(purchaseCost) %>
                                    </span>
                                </td>

                                <td>
                                    <%= HtmlEscapeUtil.escape(rs.getString("location"), "-") %>
                                </td>

                                <td>
                                    <span class="warranty-status-pill <%= warrantyClass %>">
                                        <i class="fa-solid <%= warrantyIcon %>"></i>
                                        <%= warrantyLabel %>
                                    </span>
                                </td>

                                <td>
                                    <a href="view_asset.jsp?id=<%= rs.getInt("asset_id") %>"
                                       class="asset-action-btn inspect-btn">
                                        <i class="fa-solid fa-eye"></i>
                                        View Asset
                                    </a>
                                    <a href="view_warranty_history.jsp?id=<%= rs.getInt("asset_id") %>"
                                       class="asset-action-btn inspect-btn">
                                        <i class="fa-solid fa-clock-rotate-left"></i>
                                        History
                                    </a>
                                    <% if (canRenewWarranty) { %>
                                    <a href="renew_warranty.jsp?id=<%= rs.getInt("asset_id") %>"
                                       class="asset-action-btn inspect-btn">
                                        <i class="fa-solid fa-rotate"></i>
                                        Renew
                                    </a>
                                    <% } %>
                                </td>
                            </tr>

                            <%
                                    }

                                } catch (Exception e) {
                                    e.printStackTrace();
                                }

                                if (!hasRows) {
                            %>

                            <tr>
                                <td colspan="11">
                                    <div class="no-records-message">
                                        <i class="fa-solid fa-circle-info"></i>
                                        <strong>No asset warranty records found.</strong>
                                    </div>
                                </td>
                            </tr>

                            <%
                                }
                            %>

                        </tbody>
                    </table>

                    <div id="warrantyNoRecords" class="no-records-message" style="display:none;">
                        <i class="fa-solid fa-circle-info"></i>
                        <strong>No matching warranty records found.</strong>
                        Try changing search keyword or warranty status filter.
                    </div>

                </div>

            </section>

        </div>

    </main>

</div>
<script>
    const warrantySearch = document.getElementById("warrantySearch");
    const warrantyStatusFilter = document.getElementById("warrantyStatusFilter");
    const tableRows = document.querySelectorAll("#warrantyTable tbody tr[data-warranty-status]");
    const warrantyNoRecords = document.getElementById("warrantyNoRecords");

    function normalizeText(text) {
        return text
                .toLowerCase()
                .replace(/\s+/g, " ")
                .trim();
    }

    function applyWarrantyFilters() {
        const keyword = normalizeText(warrantySearch.value);
        const selectedStatus = warrantyStatusFilter.value;

        let visibleCount = 0;

        tableRows.forEach(row => {
            const rowText = normalizeText(row.textContent);
            const rowStatus = row.dataset.warrantyStatus || "NO_WARRANTY";

            const matchesSearch =
                    keyword === "" || rowText.indexOf(keyword) !== -1;

            const matchesStatus =
                    selectedStatus === "ALL" || rowStatus === selectedStatus;

            if (matchesSearch && matchesStatus) {
                row.style.display = "";
                visibleCount++;
            } else {
                row.style.display = "none";
            }
        });

        if (warrantyNoRecords) {
            warrantyNoRecords.style.display = visibleCount === 0 ? "block" : "none";
        }
    }

    function resetWarrantyFilters() {
        warrantyStatusFilter.value = "ALL";
        warrantySearch.value = "";
        applyWarrantyFilters();
    }

    warrantySearch.addEventListener("input", applyWarrantyFilters);
    warrantyStatusFilter.addEventListener("change", applyWarrantyFilters);

    applyWarrantyFilters();

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

<script src="js/topbar-search.js?v=28000"></script>
<script src="js/user-dropdown.js?v=28000"></script>
<script src="js/sidebar-role.js?v=28000"></script>
<script src="js/ir-body-watermark.js?v=28000"></script>
<script src="js/dashboard-actions.js?v=28000"></script>

</body>
</html>