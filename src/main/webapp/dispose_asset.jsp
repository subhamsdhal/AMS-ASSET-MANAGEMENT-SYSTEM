<%@page contentType="text/html" pageEncoding="UTF-8"%>
<%@page import="com.mycompany.asset_management_system_ams.Asset"%>
<%@page import="com.mycompany.asset_management_system_ams.AssetDAO"%>
<%@page import="com.mycompany.asset_management_system_ams.HtmlEscapeUtil"%>
<%@page import="java.time.LocalDate"%>
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

    boolean canDisposeAsset = ("SUPER_ADMIN".equals(role) || "ADMIN".equals(role))
            || "ASSET_MANAGER".equals(role);

    if (!canDisposeAsset) {
        response.sendRedirect("assets.jsp?access=denied");
        return;
    }

    int assetId = 0;

    try {
        assetId = Integer.parseInt(request.getParameter("id"));
    } catch (Exception e) {
        response.sendRedirect("assets.jsp?error=failed");
        return;
    }

    AssetDAO dao = new AssetDAO();
    Asset asset = dao.getAssetById(assetId);

    if (asset == null) {
        response.sendRedirect("assets.jsp?error=failed");
        return;
    }

    String error = request.getParameter("error");

    DecimalFormat moneyFormat = new DecimalFormat("#,##0.00");

    // Escaped at extraction, not at each print site - dispose_asset.jsp had no
    // escaping helper at all (unlike essentially every other JSP in this app),
    // so asset_name/category_name/vendor_name/location (all admin-entered
    // fields) were being rendered raw. Same stored-XSS bug class fixed
    // repeatedly elsewhere in this audit.
    String assetStatus = HtmlEscapeUtil.escape(asset.getAssetStatus(), "UNKNOWN");
    String assetCode = HtmlEscapeUtil.escape(asset.getAssetCode(), "-");
    String assetName = HtmlEscapeUtil.escape(asset.getAssetName(), "-");
    String categoryName = HtmlEscapeUtil.escape(asset.getCategoryName(), "-");
    String vendorName = HtmlEscapeUtil.escape(asset.getVendorName(), "-");
    String serialNumber = HtmlEscapeUtil.escape(asset.getSerialNumber(), "-");
    String location = HtmlEscapeUtil.escape(asset.getLocation(), "-");
    String today = LocalDate.now().toString();
%>

<!DOCTYPE html>
<html>
<head>
    <title>IR-AMS Dispose Asset</title>

    <link rel="stylesheet"
          href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.0/css/all.min.css">

    <link rel="stylesheet" href="css/ir-glass.css?v=asset-allocation-inner-1">
    <link rel="stylesheet" href="css/ams-pro.css?v=asset-allocation-inner-1">
    <link rel="stylesheet" href="css/ir-ams-railway-ui.css?v=asset-allocation-inner-1">
<link rel="stylesheet" href="css/dispose_asset.css?v=topbarfix1">
</head>

<body class="railway-ui">

<div class="app">

        <jsp:include page="sidebar.jsp" />

    <main class="main railway-main">

                <jsp:include page="topbar.jsp" />

        <div class="main-scroll-content">

            <section class="asset-hero">
                <h1>Asset Disposal Approval</h1>

                <p>
                    Record disposal reason, approval details, disposal value and final lifecycle closure
                    for railway asset inventory control.
                </p>

                <br>

                <div class="hero-pills">
                    <div class="hero-pill">
                        <i class="fa-solid fa-trash"></i> Disposal Workflow
                    </div>

                    <div class="hero-pill">
                        <i class="fa-solid fa-shield-halved"></i> Login Approval Locked
                    </div>

                    <div class="hero-pill">
                        <i class="fa-solid fa-database"></i> Disposal History
                    </div>

                    <div class="hero-pill">
                        <i class="fa-solid fa-clock-rotate-left"></i> Audit Logged
                    </div>
                </div>
            </section>

            <% if ("allocated".equals(error)) { %>
                <div class="page-error">
                    <i class="fa-solid fa-triangle-exclamation"></i>
                    This asset is currently allocated. Return the asset first before disposal.
                </div>
            <% } else if ("alreadydisposed".equals(error)) { %>
                <div class="page-error">
                    <i class="fa-solid fa-circle-info"></i>
                    This asset is already disposed.
                </div>
            <% } else if ("failed".equals(error)) { %>
                <div class="page-error">
                    <i class="fa-solid fa-triangle-exclamation"></i>
                    Disposal could not be completed. Please check all required fields.
                </div>
            <% } else if ("invaliddate".equals(error)) { %>
                <div class="page-error">
                    <i class="fa-solid fa-triangle-exclamation"></i>
                    Disposal date must be today or an earlier valid date.
                </div>
            <% } else if ("server".equals(error)) { %>
                <div class="page-error">
                    <i class="fa-solid fa-triangle-exclamation"></i>
                    Server error occurred while disposing this asset.
                </div>
            <% } %>

            <div class="dispose-warning-panel">
                <h3>
                    <i class="fa-solid fa-triangle-exclamation"></i>
                    Important Disposal Warning
                </h3>
                <p>
                    Disposal will permanently mark this asset as <strong>DISPOSED</strong> in the asset lifecycle.
                    It will remain in records for audit and reporting, but should not be allocated again.
                </p>
            </div>

            <section class="dispose-grid">

                <div class="dispose-card glass-panel">

                    <div class="dispose-big-icon">
                        <i class="fa-solid fa-laptop-code"></i>
                    </div>

                    <h2><%= assetName %></h2>

                    <p class="table-subtext">
                        Asset selected for disposal approval and lifecycle closure.
                    </p>

                    <br>

                    <div class="dispose-detail-row">
                        <span>Asset Code</span>
                        <strong>
                            <span class="dispose-id-pill">
                                <i class="fa-solid fa-id-badge"></i>
                                <%= assetCode %>
                            </span>
                        </strong>
                    </div>

                    <div class="dispose-detail-row">
                        <span>Category</span>
                        <strong><%= categoryName %></strong>
                    </div>

                    <div class="dispose-detail-row">
                        <span>Vendor</span>
                        <strong><%= vendorName %></strong>
                    </div>

                    <div class="dispose-detail-row">
                        <span>Serial Number</span>
                        <strong><%= serialNumber %></strong>
                    </div>

                    <div class="dispose-detail-row">
                        <span>Location</span>
                        <strong><%= location %></strong>
                    </div>

                    <div class="dispose-detail-row">
                        <span>Purchase Cost</span>
                        <strong>₹<%= moneyFormat.format(asset.getPurchaseCost()) %></strong>
                    </div>

                    <div class="dispose-detail-row">
                        <span>Current Status</span>
                        <strong>
                            <span class="dispose-status-pill">
                                <i class="fa-solid fa-circle-info"></i>
                                <%= assetStatus %>
                            </span>
                        </strong>
                    </div>

                </div>

                <div class="dispose-card glass-panel">

                    <h2>Disposal Entry Form</h2>
                    <br>

                    <% if ("DISPOSED".equalsIgnoreCase(assetStatus)) { %>

                        <div class="page-error">
                            <i class="fa-solid fa-circle-info"></i>
                            This asset is already disposed. New disposal entry is not allowed.
                        </div>

                        <div class="form-actions">
                            <a href="view_asset.jsp?id=<%= asset.getAssetId() %>" class="btn">
                                <i class="fa-solid fa-eye"></i>
                                Back to Asset
                            </a>

                            <a href="assets.jsp" class="btn secondary-btn">
                                <i class="fa-solid fa-arrow-left"></i>
                                Back to Assets
                            </a>
                        </div>

                    <% } else { %>

                        <form action="<%= request.getContextPath() %>/DisposeAssetServlet"
                              method="post"
                              onsubmit="return confirmDisposalSubmit();">

                            <input type="hidden" name="assetId" value="<%= asset.getAssetId() %>">

                            <div class="form-grid">

                                <div class="form-group">
                                    <label>Disposal Date</label>
                                    <input type="date"
                                           name="disposalDate"
                                           value="<%= today %>"
                                           required>
                                </div>

                                <div class="form-group">
                                    <label>Disposal Value</label>
                                    <input type="number"
                                           step="0.01"
                                           min="0"
                                           name="disposalValue"
                                           placeholder="Example: 2500.00"
                                           required>
                                </div>

                                <div class="form-group full-width">
                                    <label>Approved By</label>

                                    <input type="hidden"
                                           name="approvedBy"
                                           value="<%= username %>">

                                    <input type="text"
                                           value="<%= username %>"
                                           readonly
                                           class="readonly-login-field"
                                           title="Approved By is locked to the logged-in user ID">
                                </div>

                                <div class="form-group full-width">
                                    <label>Disposal Reason</label>
                                    <textarea name="disposalReason"
                                              rows="5"
                                              placeholder="Example: Asset damaged beyond repair / obsolete / replaced with upgraded model"
                                              required></textarea>
                                </div>

                            </div>

                            <br>

                            <div class="form-actions">
                                <button type="submit" class="btn" id="disposeSubmitBtn">
                                    <i class="fa-solid fa-trash"></i>
                                    Confirm Disposal
                                </button>

                                <a href="view_asset.jsp?id=<%= asset.getAssetId() %>" class="btn secondary-btn">
                                    <i class="fa-solid fa-eye"></i>
                                    Back to Asset
                                </a>

                                <a href="assets.jsp" class="btn secondary-btn">
                                    <i class="fa-solid fa-arrow-left"></i>
                                    Back to Assets
                                </a>
                            </div>

                        </form>

                    <% } %>

                </div>

            </section>

        </div>

    </main>

</div>
<script>
    function confirmDisposalSubmit() {
        const confirmed = confirm("Confirm disposal of this asset? This will mark the asset as DISPOSED.");

        if (!confirmed) {
            return false;
        }

        const btn = document.getElementById("disposeSubmitBtn");

        if (btn) {
            btn.disabled = true;
            btn.innerHTML = '<i class="fa-solid fa-spinner fa-spin"></i> Processing Disposal...';
        }

        return true;
    }

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

<script src="js/topbar-search.js?v=asset-allocation-inner-1"></script>
<script src="js/user-dropdown.js?v=asset-allocation-inner-1"></script>
<script src="js/sidebar-role.js?v=asset-allocation-inner-1"></script>
<script src="js/ir-body-watermark.js?v=asset-allocation-inner-1"></script>
<script src="js/dashboard-actions.js?v=asset-allocation-inner-1"></script>

</body>
</html>
