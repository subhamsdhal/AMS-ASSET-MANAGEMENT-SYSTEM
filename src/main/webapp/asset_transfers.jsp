<%@page contentType="text/html" pageEncoding="UTF-8"%>
<%@page import="com.mycompany.asset_management_system_ams.AssetTransferDAO"%>
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
    // ROLE_MAP already gates this path (assetOps) at the filter level; this is
    // the per-page re-check.
    boolean canReview = "SUPER_ADMIN".equals(role) || "ADMIN".equals(role) || "ASSET_MANAGER".equals(role);
    if (!canReview) {
        response.sendRedirect("dashboard.jsp?access=denied");
        return;
    }

    AssetTransferDAO dao = new AssetTransferDAO();
    List<Map<String, String>> transferList = dao.getAllTransferRequests();

    int pending = 0, completed = 0, rejected = 0;
    for (Map<String, String> t : transferList) {
        String st = t.get("request_status");
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
    <title>Asset Transfers - IR-AMS</title>

    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.0/css/all.min.css">

    <link rel="stylesheet" href="css/ir-glass.css?v=28000">
    <link rel="stylesheet" href="css/ams-pro.css?v=28000">
    <link rel="stylesheet" href="css/ir-ams-railway-ui.css?v=28000">
    <link rel="stylesheet" href="css/asset_requests.css?v=topbarfix1">
    <link rel="stylesheet" href="css/asset_transfers.css?v=1">
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
                        <i class="fa-solid fa-right-left"></i>
                        Asset Transfers · East Coast Railway
                    </span>

                    <h1>Employee-to-Employee Asset Transfers</h1>

                    <p>
                        Maker-checker workflow: an employee (or an Asset Manager/Admin/Super Admin on their behalf)
                        proposes handing an allocated asset to a named colleague, and a Super Admin, Admin, or
                        Asset Manager separately reviews it. Approval closes the sender's allocation and opens a
                        new one for the receiver in a single step - the asset is never left unassigned in between.
                    </p>

                    <div class="hero-pills">
                        <div class="hero-pill"><i class="fa-solid fa-right-left"></i> Direct Handoff</div>
                        <div class="hero-pill"><i class="fa-solid fa-user-check"></i> Second-Party Review</div>
                        <div class="hero-pill"><i class="fa-solid fa-shield-halved"></i> Admin Controlled</div>
                    </div>
                </div>
            </section>

            <% if ("completed".equals(success)) { %>
                <div class="page-success"><i class="fa-solid fa-circle-check"></i> Transfer approved and completed. The asset now belongs to the receiving employee.</div>
            <% } else if ("rejected".equals(success)) { %>
                <div class="page-success"><i class="fa-solid fa-circle-check"></i> Transfer request rejected. The asset remains with its current holder.</div>
            <% } else if ("accessDenied".equals(error)) { %>
                <div class="page-error"><i class="fa-solid fa-triangle-exclamation"></i> Access denied. You do not have permission to review transfers.</div>
            <% } else if ("invalidRequest".equals(error)) { %>
                <div class="page-error"><i class="fa-solid fa-triangle-exclamation"></i> Invalid transfer request selected.</div>
            <% } else if ("reviewFailed".equals(error)) { %>
                <div class="page-error"><i class="fa-solid fa-triangle-exclamation"></i> This request could not be reviewed. It may already have been processed, or the source allocation is no longer active.</div>
            <% } %>

            <section class="kpi-grid">
                <div class="kpi-card">
                    <div class="kpi-icon purple"><i class="fa-solid fa-right-left"></i></div>
                    <h3 class="kpi-title">Total Requests</h3>
                    <div class="kpi-value"><%= transferList.size() %></div>
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
                        <h2>Transfer Requests</h2>
                        <p class="table-subtext">Showing <%= transferList.size() %> transfer request(s).</p>
                    </div>
                </div>

                <div class="registry-filter-grid">
                    <div class="registry-search">
                        <i class="fa-solid fa-magnifying-glass"></i>
                        <input type="text" id="transferSearch" placeholder="Search request id, asset, employee, status...">
                    </div>
                    <select id="transferStatusFilter" class="status-filter-select">
                        <option value="ALL">All Status</option>
                        <option value="PENDING">PENDING</option>
                        <option value="COMPLETED">COMPLETED</option>
                        <option value="REJECTED">REJECTED</option>
                    </select>
                    <button type="button" class="btn" onclick="resetTransferFilters()">
                        <i class="fa-solid fa-filter-circle-xmark"></i> Reset Filters
                    </button>
                </div>

                <div class="registry-table-wrap">
                    <table class="asset-table" id="transferTable">
                        <thead>
                            <tr>
                                <th>Request ID</th>
                                <th>Asset</th>
                                <th>From</th>
                                <th>To</th>
                                <th>Reason</th>
                                <th>Status</th>
                                <th>Reviewed By</th>
                                <th>Control Actions</th>
                            </tr>
                        </thead>
                        <tbody>
                            <% if (transferList.isEmpty()) { %>
                                <tr><td colspan="8" style="text-align:center; padding:24px;">
                                    <i class="fa-solid fa-circle-info"></i> No transfer requests found.
                                </td></tr>
                            <% } %>

                            <% for (Map<String, String> t : transferList) {
                                String st = t.get("request_status");
                            %>
                            <tr>
                                <td><span class="request-id-pill">XFER-<%= HtmlEscapeUtil.escape(t.get("request_id")) %></span></td>
                                <td>
                                    <strong><%= HtmlEscapeUtil.escape(t.get("asset_code")) %></strong>
                                    <br><span class="table-subtext"><%= HtmlEscapeUtil.escape(t.get("asset_name")) %></span>
                                </td>
                                <td><%= HtmlEscapeUtil.escape(t.get("from_name")) %> (<%= HtmlEscapeUtil.escape(t.get("from_code")) %>)</td>
                                <td><%= HtmlEscapeUtil.escape(t.get("to_name")) %> (<%= HtmlEscapeUtil.escape(t.get("to_code")) %>)</td>
                                <td><%= t.get("transfer_reason") == null || t.get("transfer_reason").isEmpty() ? "-" : HtmlEscapeUtil.escape(t.get("transfer_reason")) %></td>
                                <td><span class="status-badge status-<%= HtmlEscapeUtil.escape(st) %>"><%= HtmlEscapeUtil.escape(st) %></span></td>
                                <td><%= t.get("reviewed_by_name") == null || t.get("reviewed_by_name").isEmpty() ? "-" : HtmlEscapeUtil.escape(t.get("reviewed_by_name")) %></td>
                                <td>
                                    <div class="request-actions">
                                        <% if ("PENDING".equals(st)) { %>
                                            <form method="post" action="ReviewAssetTransferServlet" style="display:inline;"
                                                  onsubmit="return confirm('Approve this transfer? It will move immediately from the current holder to the receiving employee.');">
                                                <input type="hidden" name="requestId" value="<%= t.get("request_id") %>">
                                                <input type="hidden" name="action" value="approve">
                                                <button type="submit" class="asset-action-btn custody-btn" style="border:none; cursor:pointer;" title="Approve"><i class="fa-solid fa-check"></i> Approve</button>
                                            </form>
                                            <form method="post" action="ReviewAssetTransferServlet" style="display:inline;"
                                                  onsubmit="return confirm('Reject this transfer request?');">
                                                <input type="hidden" name="requestId" value="<%= t.get("request_id") %>">
                                                <input type="hidden" name="action" value="reject">
                                                <button type="submit" class="asset-action-btn qr-btn" style="border:none; cursor:pointer;" title="Reject"><i class="fa-solid fa-ban"></i> Reject</button>
                                            </form>
                                        <% } else { %>
                                            <span class="asset-action-btn custody-btn request-disabled-action" title="Already reviewed">
                                                <i class="fa-solid fa-check-double"></i> Reviewed
                                            </span>
                                        <% } %>
                                    </div>
                                </td>
                            </tr>
                            <% } %>
                        </tbody>
                    </table>

                    <div id="transferNoRecords" class="no-records-message" style="display:none;">
                        <i class="fa-solid fa-circle-info"></i>
                        <strong>No matching transfer records found.</strong>
                    </div>
                </div>

            </section>

        </div>
    </main>

</div>

<script>
    const transferSearch = document.getElementById("transferSearch");
    const transferStatusFilter = document.getElementById("transferStatusFilter");
    const transferRows = document.querySelectorAll("#transferTable tbody tr");
    const transferNoRecords = document.getElementById("transferNoRecords");

    function normalizeText(text) { return text.toLowerCase().replace(/\s+/g, " ").trim(); }

    function applyTransferFilters() {
        const keyword = normalizeText(transferSearch.value);
        const selectedStatus = transferStatusFilter.value;
        let visibleCount = 0;

        transferRows.forEach(row => {
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

        if (transferNoRecords) transferNoRecords.style.display = visibleCount === 0 ? "block" : "none";
    }

    function resetTransferFilters() {
        transferStatusFilter.value = "ALL";
        transferSearch.value = "";
        applyTransferFilters();
    }

    transferSearch.addEventListener("input", applyTransferFilters);
    transferStatusFilter.addEventListener("change", applyTransferFilters);
    applyTransferFilters();
</script>

<script src="js/topbar-search.js?v=28000"></script>
<script src="js/user-dropdown.js?v=28000"></script>
<script src="js/sidebar-role.js?v=28000"></script>
<script src="js/ir-body-watermark.js?v=28000"></script>
<script src="js/dashboard-actions.js?v=28000"></script>

</body>
</html>
