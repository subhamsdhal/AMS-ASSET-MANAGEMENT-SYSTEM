<%@page contentType="text/html" pageEncoding="UTF-8"%>
<%@page import="com.mycompany.asset_management_system_ams.AssetDAO"%>
<%@page import="com.mycompany.asset_management_system_ams.HtmlEscapeUtil"%>
<%@page import="java.util.List"%>
<%@page import="java.util.Map"%>

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

    // Same double-layered RBAC pattern used throughout this app: RoleAccessUtil's
    // ROLE_MAP already gates this path (reportExportOps) at the filter level;
    // this is the per-page re-check.
    boolean canView = "SUPER_ADMIN".equals(role) || "ADMIN".equals(role)
            || "ASSET_MANAGER".equals(role) || "AUDITOR".equals(role);
    if (!canView) {
        response.sendRedirect("dashboard.jsp?access=denied");
        return;
    }

    // Checker stage - open to SUPER_ADMIN/ADMIN/ASSET_MANAGER, matching
    // ReviewAssetDisposalServlet's own RBAC re-check. Note ASSET_MANAGER is
    // also the role that submits proposals from dispose_asset.jsp.
    boolean canReview = "SUPER_ADMIN".equals(role) || "ADMIN".equals(role) || "ASSET_MANAGER".equals(role);

    AssetDAO dao = new AssetDAO();
    List<Map<String, String>> disposalList = dao.getAllDisposals();

    int pending = 0, completed = 0, rejected = 0;
    for (Map<String, String> d : disposalList) {
        String st = d.get("disposal_status");
        if ("PENDING".equals(st)) pending++;
        else if ("COMPLETED".equals(st)) completed++;
        else if ("REJECTED".equals(st)) rejected++;
    }

    String success = request.getParameter("success");
    String error = request.getParameter("error");
%>

<!DOCTYPE html>
<html>
<head>
    <title>Asset Disposals - IR-AMS</title>

    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.0/css/all.min.css">

    <link rel="stylesheet" href="css/ir-glass.css?v=28000">
    <link rel="stylesheet" href="css/ams-pro.css?v=28000">
    <link rel="stylesheet" href="css/ir-ams-railway-ui.css?v=28000">
    <link rel="stylesheet" href="css/asset_requests.css?v=topbarfix1">
    <link rel="stylesheet" href="css/asset_disposals.css?v=1">
</head>

<body class="railway-ui">

<div class="app ams-shell">

    <jsp:include page="sidebar.jsp" />

    <main class="main railway-main">
        <jsp:include page="topbar.jsp" />

        <div class="main-scroll-content">

            <section class="asset-hero">
                <div class="asset-hero-bg"></div>
                <div class="asset-hero-soft-fade"></div>

                <div class="asset-hero-copy">
                    <span class="eyebrow">
                        <i class="fa-solid fa-recycle"></i>
                        Asset Disposals · East Coast Railway
                    </span>

                    <h1>Asset Disposal Approvals</h1>

                    <p>
                        Maker-checker workflow for permanent asset disposal: an Asset Manager, Admin, or Super Admin
                        proposes a disposal, and a Super Admin, Admin, or Asset Manager separately reviews it before
                        the asset is actually marked disposed.
                    </p>

                    <div class="hero-pills">
                        <div class="hero-pill"><i class="fa-solid fa-user-clock"></i> Second-Party Review</div>
                        <div class="hero-pill"><i class="fa-solid fa-recycle"></i> Disposal Lifecycle</div>
                        <div class="hero-pill"><i class="fa-solid fa-shield-halved"></i> Admin Controlled</div>
                    </div>
                </div>
            </section>

            <% if ("approved".equals(success)) { %>
                <div class="page-success"><i class="fa-solid fa-circle-check"></i> Disposal approved. The asset is now marked disposed.</div>
            <% } else if ("rejected".equals(success)) { %>
                <div class="page-success"><i class="fa-solid fa-circle-check"></i> Disposal rejected. The asset's status is unchanged.</div>
            <% } else if ("accessDenied".equals(error)) { %>
                <div class="page-error"><i class="fa-solid fa-triangle-exclamation"></i> Access denied. You do not have permission to review disposals.</div>
            <% } else if ("invalidRequest".equals(error)) { %>
                <div class="page-error"><i class="fa-solid fa-triangle-exclamation"></i> Invalid disposal selected.</div>
            <% } else if ("reviewFailed".equals(error)) { %>
                <div class="page-error"><i class="fa-solid fa-triangle-exclamation"></i> This disposal could not be reviewed. It may already have been processed.</div>
            <% } %>

            <section class="kpi-grid">
                <div class="kpi-card">
                    <div class="kpi-icon purple"><i class="fa-solid fa-recycle"></i></div>
                    <h3 class="kpi-title">Total Disposals</h3>
                    <div class="kpi-value"><%= disposalList.size() %></div>
                </div>
                <div class="kpi-card">
                    <div class="kpi-icon orange"><i class="fa-solid fa-hourglass-half"></i></div>
                    <h3 class="kpi-title">Pending Review</h3>
                    <div class="kpi-value"><%= pending %></div>
                </div>
                <div class="kpi-card">
                    <div class="kpi-icon green"><i class="fa-solid fa-circle-check"></i></div>
                    <h3 class="kpi-title">Completed</h3>
                    <div class="kpi-value"><%= completed %></div>
                </div>
                <div class="kpi-card">
                    <div class="kpi-icon red"><i class="fa-solid fa-ban"></i></div>
                    <h3 class="kpi-title">Rejected</h3>
                    <div class="kpi-value"><%= rejected %></div>
                </div>
            </section>

            <section class="glass-panel">

                <div class="registry-toolbar">
                    <div>
                        <h2>Disposal Records</h2>
                        <p class="table-subtext">Showing <%= disposalList.size() %> disposal record(s).</p>
                    </div>
                </div>

                <div class="registry-filter-grid">
                    <div class="registry-search">
                        <i class="fa-solid fa-magnifying-glass"></i>
                        <input type="text" id="disposalSearch" placeholder="Search disposal id, asset, reason, status...">
                    </div>
                    <select id="disposalStatusFilter" class="status-filter-select">
                        <option value="ALL">All Status</option>
                        <option value="PENDING">PENDING</option>
                        <option value="COMPLETED">COMPLETED</option>
                        <option value="REJECTED">REJECTED</option>
                    </select>
                    <button type="button" class="btn" onclick="resetDisposalFilters()">
                        <i class="fa-solid fa-filter-circle-xmark"></i> Reset Filters
                    </button>
                </div>

                <div class="registry-table-wrap">
                    <table class="asset-table" id="disposalTable">
                        <thead>
                            <tr>
                                <th>Disposal ID</th>
                                <th>Asset</th>
                                <th>Reason</th>
                                <th>Value</th>
                                <th>Requested By</th>
                                <th>Status</th>
                                <th>Reviewed By</th>
                                <th>Control Actions</th>
                            </tr>
                        </thead>
                        <tbody>
                            <% if (disposalList.isEmpty()) { %>
                                <tr><td colspan="8" style="text-align:center; padding:24px;">
                                    <i class="fa-solid fa-circle-info"></i> No disposal records found.
                                </td></tr>
                            <% } %>

                            <% for (Map<String, String> d : disposalList) {
                                String st = d.get("disposal_status");
                            %>
                            <tr>
                                <td><span class="request-id-pill">DISP-<%= HtmlEscapeUtil.escape(d.get("disposal_id")) %></span></td>
                                <td>
                                    <a href="view_disposal.jsp?id=<%= HtmlEscapeUtil.escape(d.get("disposal_id")) %>">
                                        <strong><%= HtmlEscapeUtil.escape(d.get("asset_code")) %></strong>
                                    </a>
                                    <br><span class="table-subtext"><%= HtmlEscapeUtil.escape(d.get("asset_name")) %></span>
                                </td>
                                <td><%= HtmlEscapeUtil.escape(d.get("disposal_reason")) %></td>
                                <td>&#8377; <%= HtmlEscapeUtil.escape(d.get("disposal_value")) %></td>
                                <td><%= d.get("requested_by_name") == null || d.get("requested_by_name").isEmpty() ? "-" : HtmlEscapeUtil.escape(d.get("requested_by_name")) %></td>
                                <td><span class="status-badge status-<%= HtmlEscapeUtil.escape(st) %>"><%= HtmlEscapeUtil.escape(st) %></span></td>
                                <td><%= d.get("approved_by_name") == null || d.get("approved_by_name").isEmpty() ? "-" : HtmlEscapeUtil.escape(d.get("approved_by_name")) %></td>
                                <td>
                                    <div class="request-actions">
                                        <a href="view_disposal.jsp?id=<%= HtmlEscapeUtil.escape(d.get("disposal_id")) %>"
                                           class="asset-action-btn inspect-btn" title="View details"><i class="fa-solid fa-eye"></i> View</a>

                                        <% if ("PENDING".equals(st) && canReview) { %>
                                            <form method="post" action="ReviewAssetDisposalServlet" style="display:inline;"
                                                  onsubmit="return confirm('Approve this disposal? The asset will be permanently marked as disposed.');">
                                                <input type="hidden" name="disposalId" value="<%= d.get("disposal_id") %>">
                                                <input type="hidden" name="action" value="approve">
                                                <button type="submit" class="asset-action-btn custody-btn" style="border:none; cursor:pointer;" title="Approve"><i class="fa-solid fa-check"></i> Approve</button>
                                            </form>
                                            <form method="post" action="ReviewAssetDisposalServlet" style="display:inline;"
                                                  onsubmit="return confirm('Reject this disposal proposal?');">
                                                <input type="hidden" name="disposalId" value="<%= d.get("disposal_id") %>">
                                                <input type="hidden" name="action" value="reject">
                                                <button type="submit" class="asset-action-btn qr-btn" style="border:none; cursor:pointer;" title="Reject"><i class="fa-solid fa-ban"></i> Reject</button>
                                            </form>
                                        <% } else if ("PENDING".equals(st)) { %>
                                            <span class="asset-action-btn qr-btn request-disabled-action request-pending-action" title="Awaiting Super Admin/Admin review">
                                                <i class="fa-solid fa-hourglass-half"></i> Awaiting Review
                                            </span>
                                        <% } %>
                                    </div>
                                </td>
                            </tr>
                            <% } %>
                        </tbody>
                    </table>

                    <div id="disposalNoRecords" class="no-records-message" style="display:none;">
                        <i class="fa-solid fa-circle-info"></i>
                        <strong>No matching disposal records found.</strong>
                    </div>
                </div>

            </section>

        </div>
    </main>

</div>

<script>
    const disposalSearch = document.getElementById("disposalSearch");
    const disposalStatusFilter = document.getElementById("disposalStatusFilter");
    const disposalRows = document.querySelectorAll("#disposalTable tbody tr");
    const disposalNoRecords = document.getElementById("disposalNoRecords");

    function normalizeText(text) { return text.toLowerCase().replace(/\s+/g, " ").trim(); }

    function applyDisposalFilters() {
        const keyword = normalizeText(disposalSearch.value);
        const selectedStatus = disposalStatusFilter.value;
        let visibleCount = 0;

        disposalRows.forEach(row => {
            const rowText = normalizeText(row.textContent);
            const statusBadge = row.querySelector(".status-badge");
            const rowStatus = statusBadge ? statusBadge.textContent.trim() : "";
            const matchesSearch = keyword === "" || rowText.indexOf(keyword) !== -1;
            const matchesStatus = selectedStatus === "ALL" || rowStatus === selectedStatus;

            if (matchesSearch && matchesStatus) {
                row.style.display = "";
                visibleCount++;
            } else {
                row.style.display = "none";
            }
        });

        if (disposalNoRecords) disposalNoRecords.style.display = visibleCount === 0 ? "block" : "none";
    }

    function resetDisposalFilters() {
        disposalStatusFilter.value = "ALL";
        disposalSearch.value = "";
        applyDisposalFilters();
    }

    disposalSearch.addEventListener("input", applyDisposalFilters);
    disposalStatusFilter.addEventListener("change", applyDisposalFilters);
    applyDisposalFilters();
</script>

<script src="js/topbar-search.js?v=28000"></script>
<script src="js/user-dropdown.js?v=28000"></script>
<script src="js/sidebar-role.js?v=28000"></script>
<script src="js/ir-body-watermark.js?v=28000"></script>
<script src="js/dashboard-actions.js?v=28000"></script>

</body>
</html>
