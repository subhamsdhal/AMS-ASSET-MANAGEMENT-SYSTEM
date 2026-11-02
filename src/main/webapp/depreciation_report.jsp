<%@page contentType="text/html" pageEncoding="UTF-8"%>
<%@page import="com.mycompany.asset_management_system_ams.AssetDAO"%>
<%@page import="com.mycompany.asset_management_system_ams.HtmlEscapeUtil"%>
<%@page import="java.util.List"%>
<%@page import="java.util.Map"%>
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

    // Same viewer set as reports.jsp itself (reportsPageOps), so a role that
    // can open the Reports hub never hits a 403 on one of its own report
    // cards - the same broken-link shape fixed earlier this session for
    // asset_disposals.jsp/asset_transfers.jsp.
    boolean canView = "SUPER_ADMIN".equals(role) || "ADMIN".equals(role) || "ASSET_MANAGER".equals(role)
            || "AUDITOR".equals(role) || "DEPARTMENT_HEAD".equals(role);
    if (!canView) {
        response.sendRedirect("dashboard.jsp?access=denied");
        return;
    }

    AssetDAO dao = new AssetDAO();
    List<Map<String, String>> rows = dao.getDepreciationReport();

    DecimalFormat money = new DecimalFormat("#,##0.00");

    double totalCost = 0, totalDepreciation = 0, totalBookValue = 0;
    for (Map<String, String> r : rows) {
        totalCost += Double.parseDouble(r.get("purchase_cost"));
        totalDepreciation += Double.parseDouble(r.get("accumulated_depreciation"));
        totalBookValue += Double.parseDouble(r.get("book_value"));
    }
%>

<!DOCTYPE html>
<html>
<head>
    <title>IR-AMS Depreciation Report</title>

    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.0/css/all.min.css">

    <link rel="stylesheet" href="css/ir-glass.css?v=28000">
    <link rel="stylesheet" href="css/ams-pro.css?v=28000">
    <link rel="stylesheet" href="css/ir-ams-railway-ui.css?v=28000">
    <link rel="stylesheet" href="css/asset_requests.css?v=topbarfix1">
    <link rel="stylesheet" href="css/depreciation_report.css?v=1">
</head>

<body class="railway-ui">

<div class="app ams-shell">

    <jsp:include page="sidebar.jsp" />

    <main class="main railway-main">
        <jsp:include page="topbar.jsp" />

        <div class="main-scroll-content">

            <section class="request-hero">
                <div class="request-hero-copy">
                    <h1>Depreciation Report</h1>

                    <p>
                        Straight-line depreciation, computed live from each asset's purchase cost, annual
                        depreciation rate, and age - the same calculation used on the asset detail page and
                        recorded as the write-off figure when a disposal is approved. Disposed assets keep
                        their final value on the disposal record and are not shown here.
                    </p>

                    <div class="hero-pills">
                        <div class="hero-pill"><i class="fa-solid fa-chart-line"></i> Straight-Line Method</div>
                        <div class="hero-pill"><i class="fa-solid fa-calculator"></i> Live Calculation</div>
                        <div class="hero-pill"><i class="fa-solid fa-file-lines"></i> Report Ready</div>
                    </div>
                </div>
            </section>

            <section class="kpi-grid">
                <div class="kpi-card">
                    <div class="kpi-icon purple"><i class="fa-solid fa-boxes-stacked"></i></div>
                    <h3 class="kpi-title">Assets in Service</h3>
                    <div class="kpi-value"><%= rows.size() %></div>
                </div>
                <div class="kpi-card">
                    <div class="kpi-icon blue"><i class="fa-solid fa-sack-dollar"></i></div>
                    <h3 class="kpi-title">Total Purchase Cost</h3>
                    <div class="kpi-value">&#8377; <%= money.format(totalCost) %></div>
                </div>
                <div class="kpi-card">
                    <div class="kpi-icon orange"><i class="fa-solid fa-arrow-trend-down"></i></div>
                    <h3 class="kpi-title">Accumulated Depreciation</h3>
                    <div class="kpi-value">&#8377; <%= money.format(totalDepreciation) %></div>
                </div>
                <div class="kpi-card">
                    <div class="kpi-icon green"><i class="fa-solid fa-scale-balanced"></i></div>
                    <h3 class="kpi-title">Current Book Value</h3>
                    <div class="kpi-value">&#8377; <%= money.format(totalBookValue) %></div>
                </div>
            </section>

            <section class="glass-panel">

                <div class="registry-toolbar">
                    <div>
                        <h2>Asset Valuation Table</h2>
                        <p class="table-subtext">Showing <%= rows.size() %> in-service asset(s).</p>
                    </div>
                    <div class="registry-actions">
                        <a href="reports.jsp" class="btn request-export-btn request-header-export-btn">
                            <i class="fa-solid fa-arrow-left"></i> Back to Reports
                        </a>
                    </div>
                </div>

                <div class="registry-filter-grid">
                    <div class="registry-search">
                        <i class="fa-solid fa-magnifying-glass"></i>
                        <input type="text" id="depSearch" placeholder="Search asset code, name, category...">
                    </div>
                    <button type="button" class="btn" onclick="resetDepFilters()">
                        <i class="fa-solid fa-filter-circle-xmark"></i> Reset Filters
                    </button>
                </div>

                <div class="registry-table-wrap">
                    <table class="asset-table" id="depTable">
                        <thead>
                            <tr>
                                <th>Asset</th>
                                <th>Category</th>
                                <th>Purchase Date</th>
                                <th>Purchase Cost</th>
                                <th>Annual Rate</th>
                                <th>Accumulated Depreciation</th>
                                <th>Current Book Value</th>
                                <th>Status</th>
                            </tr>
                        </thead>
                        <tbody>
                            <% if (rows.isEmpty()) { %>
                                <tr><td colspan="8" style="text-align:center; padding:24px;">
                                    <i class="fa-solid fa-circle-info"></i> No in-service assets found.
                                </td></tr>
                            <% } %>

                            <% for (Map<String, String> r : rows) { %>
                            <tr>
                                <td>
                                    <a href="view_asset.jsp?id=<%= HtmlEscapeUtil.escape(r.get("asset_id")) %>">
                                        <strong><%= HtmlEscapeUtil.escape(r.get("asset_code")) %></strong>
                                    </a>
                                    <br><span class="table-subtext"><%= HtmlEscapeUtil.escape(r.get("asset_name")) %></span>
                                </td>
                                <td><%= HtmlEscapeUtil.escape(r.get("category_name")) %></td>
                                <td><%= HtmlEscapeUtil.escape(r.get("purchase_date")) %></td>
                                <td>&#8377; <%= money.format(Double.parseDouble(r.get("purchase_cost"))) %></td>
                                <td><%= HtmlEscapeUtil.escape(r.get("depreciation_rate")) %>%</td>
                                <td>&#8377; <%= money.format(Double.parseDouble(r.get("accumulated_depreciation"))) %></td>
                                <td><strong>&#8377; <%= money.format(Double.parseDouble(r.get("book_value"))) %></strong></td>
                                <td><span class="status-badge status-<%= HtmlEscapeUtil.escape(r.get("asset_status")) %>"><%= HtmlEscapeUtil.escape(r.get("asset_status")) %></span></td>
                            </tr>
                            <% } %>
                        </tbody>
                    </table>

                    <div id="depNoRecords" class="no-records-message" style="display:none;">
                        <i class="fa-solid fa-circle-info"></i>
                        <strong>No matching assets found.</strong>
                    </div>
                </div>

            </section>

        </div>
    </main>

</div>

<script>
    const depSearch = document.getElementById("depSearch");
    const depRows = document.querySelectorAll("#depTable tbody tr");
    const depNoRecords = document.getElementById("depNoRecords");

    function normalizeText(text) { return text.toLowerCase().replace(/\s+/g, " ").trim(); }

    function applyDepFilters() {
        const keyword = normalizeText(depSearch.value);
        let visibleCount = 0;

        depRows.forEach(row => {
            const matches = keyword === "" || normalizeText(row.textContent).indexOf(keyword) !== -1;
            row.style.display = matches ? "" : "none";
            if (matches) visibleCount++;
        });

        if (depNoRecords) depNoRecords.style.display = visibleCount === 0 ? "block" : "none";
    }

    function resetDepFilters() {
        depSearch.value = "";
        applyDepFilters();
    }

    depSearch.addEventListener("input", applyDepFilters);
    applyDepFilters();
</script>

<script src="js/topbar-search.js?v=28000"></script>
<script src="js/user-dropdown.js?v=28000"></script>
<script src="js/sidebar-role.js?v=28000"></script>
<script src="js/ir-body-watermark.js?v=28000"></script>
<script src="js/dashboard-actions.js?v=28000"></script>

</body>
</html>
