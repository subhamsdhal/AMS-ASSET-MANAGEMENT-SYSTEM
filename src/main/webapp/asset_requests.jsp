<%@page contentType="text/html" pageEncoding="UTF-8"%>
<%@page import="com.mycompany.asset_management_system_ams.AssetRequest"%>
<%@page import="com.mycompany.asset_management_system_ams.AssetRequestDAO"%>
<%@page import="com.mycompany.asset_management_system_ams.HtmlEscapeUtil"%>
<%@page import="java.util.List"%>

<%!
    public String formatNumber(int number) {
        if (number >= 100000) {
            return String.format("%.1fL", number / 100000.0).replace(".0", "");
        } else if (number >= 1000) {
            return String.format("%.1fK", number / 1000.0).replace(".0", "");
        }
        return String.valueOf(number);
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

    boolean canCreateRequest = ("SUPER_ADMIN".equals(role) || "ADMIN".equals(role))
            || "ASSET_MANAGER".equals(role)
            || "DEPARTMENT_HEAD".equals(role)
            || "EMPLOYEE".equals(role);

    boolean canApproveRejectRequest = ("SUPER_ADMIN".equals(role) || "ADMIN".equals(role))
            || "ASSET_MANAGER".equals(role);

    boolean canFulfillRequest = ("SUPER_ADMIN".equals(role) || "ADMIN".equals(role))
            || "ASSET_MANAGER".equals(role);

    boolean canExportRequestReport = ("SUPER_ADMIN".equals(role) || "ADMIN".equals(role))
            || "ASSET_MANAGER".equals(role)
            || "AUDITOR".equals(role);

    AssetRequestDAO dao = new AssetRequestDAO();
    List<AssetRequest> requestList = dao.getAllRequests();

    String msg = request.getParameter("msg");
    String error = request.getParameter("error");

    int pending = 0;
    int approved = 0;
    int rejected = 0;
    int fulfilled = 0;

    for (AssetRequest req : requestList) {
        if ("PENDING".equals(req.getRequestStatus())) {
            pending++;
        }

        if ("APPROVED".equals(req.getRequestStatus())) {
            approved++;
        }

        if ("REJECTED".equals(req.getRequestStatus())) {
            rejected++;
        }

        if ("FULFILLED".equals(req.getRequestStatus())) {
            fulfilled++;
        }
    }
%>

<!DOCTYPE html>
<html>
<head>
    <title>IR-AMS Asset Requests</title>

    <link rel="stylesheet"
          href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.0/css/all.min.css">

    <link rel="stylesheet" href="css/ir-glass.css?v=28000">
    <link rel="stylesheet" href="css/ams-pro.css?v=28000">
    <link rel="stylesheet" href="css/ir-ams-railway-ui.css?v=28000">
<link rel="stylesheet" href="css/asset_requests.css?v=topbarfix1">
        </head>

<body class="railway-ui">

<div class="app ams-shell">

    <jsp:include page="sidebar.jsp" />

    <main class="main railway-main">
        <jsp:include page="topbar.jsp" />

        <div class="main-scroll-content">

            <section class="request-hero">
                                <div class="request-hero-copy">
                    <h1>Asset Request Control Desk</h1>

                    <p>
                    Review, approve, reject and track employee asset requests for railway departments
                    with category-wise demand visibility and real-time approval status.
                </p>

                    <div class="hero-pills">
                    <div class="hero-pill">
                        <i class="fa-solid fa-file-circle-plus"></i> Request Workflow
                    </div>

                    <div class="hero-pill">
                        <i class="fa-solid fa-user-check"></i> Approval Tracking
                    </div>

                    <div class="hero-pill">
                        <i class="fa-solid fa-layer-group"></i> Category Demand
                    </div>

                    <div class="hero-pill">
                        <i class="fa-solid fa-shield-halved"></i> Admin Controlled
                    </div>
                </div>
                </div>
            </section>

            <% if ("denied".equals(request.getParameter("access"))) { %>
                <div class="page-error">
                    <i class="fa-solid fa-triangle-exclamation"></i>
                    Access denied. You do not have permission to perform this request action.
                </div>
            <% } %>

            <section class="kpi-grid">

                <div class="kpi-card">
                    <div class="kpi-icon purple">
                        <i class="fa-solid fa-file-lines"></i>
                    </div>
                    <h3 class="kpi-title">Total Requests</h3>
                    <div class="kpi-value"><%= formatNumber(requestList.size()) %></div>
                </div>

                <div class="kpi-card">
                    <div class="kpi-icon orange">
                        <i class="fa-solid fa-hourglass-half"></i>
                    </div>
                    <h3 class="kpi-title">Pending</h3>
                    <div class="kpi-value"><%= formatNumber(pending) %></div>
                </div>

                <div class="kpi-card">
                    <div class="kpi-icon blue">
                        <i class="fa-solid fa-thumbs-up"></i>
                    </div>
                    <h3 class="kpi-title">Approved</h3>
                    <div class="kpi-value"><%= formatNumber(approved) %></div>
                </div>

                <div class="kpi-card">
                    <div class="kpi-icon red">
                        <i class="fa-solid fa-ban"></i>
                    </div>
                    <h3 class="kpi-title">Rejected</h3>
                    <div class="kpi-value"><%= formatNumber(rejected) %></div>
                </div>

                <div class="kpi-card">
                    <div class="kpi-icon green">
                        <i class="fa-solid fa-circle-check"></i>
                    </div>
                    <h3 class="kpi-title">Fulfilled</h3>
                    <div class="kpi-value"><%= formatNumber(fulfilled) %></div>
                </div>

                <div class="kpi-card">
                    <div class="kpi-icon pink">
                        <i class="fa-solid fa-database"></i>
                    </div>
                    <h3 class="kpi-title">Live Status</h3>
                    <p>ON</p>
                </div>

            </section>

            <%
                if ("added".equals(msg)) {
            %>
                <div class="page-success">
                    <i class="fa-solid fa-circle-check"></i>
                    Asset request added successfully.
                </div>
            <%
                } else if ("approved".equals(msg)) {
            %>
                <div class="page-success">
                    <i class="fa-solid fa-circle-check"></i>
                    Asset request approved successfully.
                </div>
            <%
                } else if ("rejected".equals(msg)) {
            %>
                <div class="page-success">
                    <i class="fa-solid fa-circle-check"></i>
                    Asset request rejected successfully.
                </div>
            <%
                } else if ("fulfilled".equals(msg)) {
            %>
                <div class="page-success">
                    <i class="fa-solid fa-circle-check"></i>
                    Asset request fulfilled successfully.
                </div>
            <%
                } else if ("invalidrequest".equals(error)) {
            %>
                <div class="page-error">
                    <i class="fa-solid fa-triangle-exclamation"></i>
                    Invalid request selected.
                </div>
            <%
                } else if ("invalidaction".equals(error)) {
            %>
                <div class="page-error">
                    <i class="fa-solid fa-triangle-exclamation"></i>
                    Invalid request action selected.
                </div>
            <%
                } else if ("updatefailed".equals(error)) {
            %>
                <div class="page-error">
                    <i class="fa-solid fa-triangle-exclamation"></i>
                    Request status could not be updated. Please refresh and try again.
                </div>
            <%
                } else if ("server".equals(error)) {
            %>
                <div class="page-error">
                    <i class="fa-solid fa-triangle-exclamation"></i>
                    Server error occurred while processing the request action.
                </div>
            <%
                }
            %>

            <section class="glass-panel">

                <div class="registry-toolbar">

                    <div>
                        <h2>Request Approval Table</h2>
                        <p class="table-subtext">
                            Showing <%= requestList.size() %> live asset request records from railway database.
                        </p>
                    </div>

                    <div class="registry-actions">

                        <% if (canExportRequestReport) { %>
                            <a href="export_requests_report.jsp" class="btn request-export-btn request-header-export-btn">
                                <i class="fa-solid fa-file-excel"></i> Export Excel
                            </a>
                        <% } %>

                    </div>

                </div>

                <div class="registry-filter-grid request-filter-grid <%= canCreateRequest ? "has-new-request" : "no-new-request" %>">

                    <div class="registry-search">
                        <i class="fa-solid fa-magnifying-glass"></i>
                        <input type="text"
                               id="requestSearch"
                               placeholder="Search request id, employee, category, status, remarks...">
                    </div>

                    <select id="requestStatusFilter" class="status-filter-select">
                        <option value="ALL">All Status</option>
                        <option value="PENDING_DEPT_HEAD">PENDING_DEPT_HEAD</option>
                        <option value="PENDING">PENDING</option>
                        <option value="APPROVED">APPROVED</option>
                        <option value="REJECTED">REJECTED</option>
                        <option value="FULFILLED">FULFILLED</option>
                    </select>

                    <% if (canCreateRequest) { %>
                        <a href="add_request.jsp" class="btn request-new-primary-btn">
                            <i class="fa-solid fa-plus"></i> New Request
                        </a>
                    <% } %>

                    <button type="button" class="btn" onclick="resetRequestFilters()">
                        <i class="fa-solid fa-filter-circle-xmark"></i> Reset Filters
                    </button>

                </div>

                <div class="registry-table-wrap">

                    <table class="asset-table" id="requestTable">
                        <colgroup>
                            <col style="width: 7%;">
                            <col style="width: 12%;">
                            <col style="width: 9%;">
                            <col style="width: 13%;">
                            <col style="width: 8%;">
                            <col style="width: 11%;">
                            <col style="width: 9%;">
                            <col style="width: 14%;">
                            <col style="width: 17%;">
                        </colgroup>
                        <thead>
                            <tr>
                                <th onclick="sortTable(0)" style="cursor: pointer;" title="Click to sort">Request ID <i class="fa-solid fa-sort" style="color: #cbd5e1; margin-left: 4px;"></i></th>
                                <th onclick="sortTable(1)" style="cursor: pointer;" title="Click to sort">Employee <i class="fa-solid fa-sort" style="color: #cbd5e1; margin-left: 4px;"></i></th>
                                <th onclick="sortTable(2)" style="cursor: pointer;" title="Click to sort">Employee Code <i class="fa-solid fa-sort" style="color: #cbd5e1; margin-left: 4px;"></i></th>
                                <th onclick="sortTable(3)" style="cursor: pointer;" title="Click to sort">Requested Category <i class="fa-solid fa-sort" style="color: #cbd5e1; margin-left: 4px;"></i></th>
                                <th onclick="sortTable(4)" style="cursor: pointer;" title="Click to sort">Request Date <i class="fa-solid fa-sort" style="color: #cbd5e1; margin-left: 4px;"></i></th>
                                <th onclick="sortTable(5)" style="cursor: pointer;" title="Click to sort">Status <i class="fa-solid fa-sort" style="color: #cbd5e1; margin-left: 4px;"></i></th>
                                <th onclick="sortTable(6)" style="cursor: pointer;" title="Click to sort">Approved By <i class="fa-solid fa-sort" style="color: #cbd5e1; margin-left: 4px;"></i></th>
                                <th>Remarks</th>
                                <th>Control Actions</th>
                            </tr>
                        </thead>

                        <tbody>

                            <%
                                for (AssetRequest req : requestList) {
                            %>

                            <tr>
                                <td>
                                    <span class="request-id-pill">
                                        REQ-<%= req.getRequestId() %>
                                    </span>
                                </td>

                                <td>
                                    <strong><%= HtmlEscapeUtil.escape(req.getEmployeeName()) %></strong>
                                    <br>
                                    <span class="table-subtext">
                                        Railway staff request
                                    </span>
                                </td>

                                <td><%= HtmlEscapeUtil.escape(req.getEmployeeCode()) %></td>

                                <td>
                                    <span class="category-pill">
                                        <%= HtmlEscapeUtil.escape(req.getCategoryName()) %>
                                    </span>
                                </td>

                                <td><%= HtmlEscapeUtil.escape(req.getRequestDate()) %></td>

                                <td>
                                    <span class="status-badge status-<%= HtmlEscapeUtil.escape(req.getRequestStatus()) %>">
                                        <%= HtmlEscapeUtil.escape(req.getRequestStatus()) %>
                                    </span>
                                    <% if ("FORWARDED".equals(req.getDeptHeadAction())) { %>
                                        <br><span class="table-subtext">Forwarded by <%= HtmlEscapeUtil.escape(req.getDeptHeadByName()) %></span>
                                    <% } %>
                                </td>

                                <td>
                                    <%= req.getApprovedBy() == null ? "Pending" : HtmlEscapeUtil.escape(req.getApprovedBy()) %>
                                </td>

                                <td>
                                    <%= req.getRemarks() == null ? "-" : HtmlEscapeUtil.escape(req.getRemarks()) %>
                                </td>

                                <td>
                                    <div class="request-actions">

                                        <a href="view_request.jsp?id=<%= req.getRequestId() %>"
                                           class="asset-action-btn inspect-btn" title="Review request details">
                                            <i class="fa-solid fa-eye"></i> Review
                                        </a>

                                        <%
                                            if ("PENDING_DEPT_HEAD".equals(req.getRequestStatus())) {
                                        %>

                                            <span class="asset-action-btn qr-btn request-disabled-action request-pending-action" title="Awaiting Department Head review before it reaches this queue">
                                                <i class="fa-solid fa-user-clock"></i> Awaiting Dept Head
                                            </span>

                                        <%
                                            } else if ("PENDING".equals(req.getRequestStatus()) && canApproveRejectRequest) {
                                        %>

                                            <form method="post" action="UpdateRequestStatusServlet" style="display:inline;" onsubmit="return confirm('Approve this asset request?');">
                                                <input type="hidden" name="requestId" value="<%= req.getRequestId() %>">
                                                <input type="hidden" name="requestStatus" value="APPROVED">
                                                <button type="submit" class="asset-action-btn custody-btn" style="border:none; cursor:pointer;" title="Approve request">
                                                    <i class="fa-solid fa-check"></i> Approve
                                                </button>
                                            </form>

                                            <form method="post" action="UpdateRequestStatusServlet" style="display:inline;" onsubmit="return confirm('Reject this asset request?');">
                                                <input type="hidden" name="requestId" value="<%= req.getRequestId() %>">
                                                <input type="hidden" name="requestStatus" value="REJECTED">
                                                <button type="submit" class="asset-action-btn qr-btn" style="border:none; cursor:pointer;" title="Reject request">
                                                    <i class="fa-solid fa-ban"></i> Reject
                                                </button>
                                            </form>

                                        <%
                                            } else if ("APPROVED".equals(req.getRequestStatus()) && canFulfillRequest) {
                                                // Allocation picker: lets the actor link this request to the specific
                                                // asset_allocation record that fulfils it (Future Scope traceability
                                                // fix - fulfilled_asset_id existed but was never populated before).
                                                // Queried inline per row, only for rows that can actually reach
                                                // Fulfill, matching this JSP's existing per-row style.
                                                int fulfillEmployeeId = dao.getEmployeeIdByRequestId(req.getRequestId());
                                                List<java.util.Map<String, String>> activeAllocations =
                                                        dao.getActiveAllocationsForEmployee(fulfillEmployeeId);
                                        %>

                                            <form method="post" action="UpdateRequestStatusServlet" style="display:inline; display:flex; gap:4px; align-items:center;" onsubmit="return confirm('Mark this request as fulfilled?');">
                                                <input type="hidden" name="requestId" value="<%= req.getRequestId() %>">
                                                <input type="hidden" name="requestStatus" value="FULFILLED">
                                                <% if (!activeAllocations.isEmpty()) { %>
                                                    <select name="fulfilledAllocationId" style="font-size:11px; padding:2px; max-width:150px;" title="Which allocation fulfils this request?">
                                                        <option value="0">-- No allocation link --</option>
                                                        <% for (java.util.Map<String, String> allocRow : activeAllocations) { %>
                                                            <option value="<%= allocRow.get("allocation_id") %>">
                                                                <%= HtmlEscapeUtil.escape(allocRow.get("asset_code")) %> (<%= HtmlEscapeUtil.escape(allocRow.get("allocation_date")) %>)
                                                            </option>
                                                        <% } %>
                                                    </select>
                                                <% } %>
                                                <button type="submit" class="asset-action-btn custody-btn" style="border:none; cursor:pointer;" title="Mark as fulfilled">
                                                    <i class="fa-solid fa-circle-check"></i> Fulfill
                                                </button>
                                            </form>

                                        <%
                                            } else if ("FULFILLED".equals(req.getRequestStatus())) {
                                        %>

                                            <span class="asset-action-btn custody-btn request-disabled-action request-completed-action" title="Request has been fulfilled">
                                                <i class="fa-solid fa-circle-check"></i> Completed
                                            </span>

                                        <%
                                            } else if ("REJECTED".equals(req.getRequestStatus())) {
                                        %>

                                            <span class="asset-action-btn qr-btn request-disabled-action request-rejected-action" title="Request has been rejected">
                                                <i class="fa-solid fa-ban"></i> Rejected
                                            </span>

                                        <%
                                            } else if ("PENDING".equals(req.getRequestStatus()) && !canApproveRejectRequest) {
                                        %>

                                            <span class="asset-action-btn qr-btn request-disabled-action request-pending-action" title="Pending approval">
                                                <i class="fa-solid fa-hourglass-half"></i> Pending
                                            </span>

                                        <%
                                            } else if ("APPROVED".equals(req.getRequestStatus()) && !canFulfillRequest) {
                                        %>

                                            <span class="asset-action-btn custody-btn request-disabled-action request-pending-action" title="Approved and pending fulfillment">
                                                <i class="fa-solid fa-thumbs-up"></i> Approved
                                            </span>

                                        <%
                                            }
                                        %>

                                    </div>
                                </td>
                            </tr>

                            <%
                                }
                            %>

                        </tbody>
                    </table>

                    <div id="requestNoRecords" class="no-records-message" style="display:none;">
                        <i class="fa-solid fa-circle-info"></i>
                        <strong>No matching request records found.</strong>
                        Try changing search keyword or status filter.
                    </div>

                </div>

            </section>

        </div>
    </main>

</div>
<script>
    const requestSearch = document.getElementById("requestSearch");
    const requestStatusFilter = document.getElementById("requestStatusFilter");
    const tableRows = document.querySelectorAll("#requestTable tbody tr");
    const requestNoRecords = document.getElementById("requestNoRecords");

    function normalizeText(text) {
        return text
                .toLowerCase()
                .replace(/\s+/g, " ")
                .trim();
    }

    function applyRequestFilters() {
        const keyword = normalizeText(requestSearch.value);
        const selectedStatus = requestStatusFilter.value;

        let visibleCount = 0;

        tableRows.forEach(row => {
            const rowText = normalizeText(row.textContent);

            const statusBadge = row.querySelector(".status-badge");
            const rowStatus = statusBadge ? statusBadge.textContent.trim() : "";

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

        if (requestNoRecords) {
            requestNoRecords.style.display = visibleCount === 0 ? "block" : "none";
        }
    }

    function resetRequestFilters() {
        requestStatusFilter.value = "ALL";
        requestSearch.value = "";
        applyRequestFilters();
    }

    requestSearch.addEventListener("input", applyRequestFilters);
    requestStatusFilter.addEventListener("change", applyRequestFilters);

    applyRequestFilters();

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
    
    var sortDirections = [true, true, true, true, true, true, true];
    function sortTable(columnIndex) {
        var table = document.getElementById("requestTable");
        if (!table) return;
        
        var tbody = table.querySelector("tbody");
        if (!tbody) return;
        
        var rows = Array.from(tbody.querySelectorAll("tr"));
        if (rows.length === 1 && rows[0].querySelector(".no-records-message")) return;

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

<script src="js/topbar-search.js?v=28000"></script>
<script src="js/user-dropdown.js?v=28000"></script>
<script src="js/sidebar-role.js?v=28000"></script>
<script src="js/ir-body-watermark.js?v=28000"></script>
<script src="js/dashboard-actions.js?v=28000"></script>

</body>
</html>
