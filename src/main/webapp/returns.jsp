<%@page contentType="text/html" pageEncoding="UTF-8"%>
<%@page import="com.mycompany.asset_management_system_ams.AssetReturn"%>
<%@page import="com.mycompany.asset_management_system_ams.AssetReturnDAO"%>
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

    boolean canCreateReturn = ("SUPER_ADMIN".equals(role) || "ADMIN".equals(role))
            || "ASSET_MANAGER".equalsIgnoreCase(role)
            || "EMPLOYEE".equalsIgnoreCase(role);

    boolean canExportReturnReport = ("SUPER_ADMIN".equals(role) || "ADMIN".equals(role))
            || "ASSET_MANAGER".equalsIgnoreCase(role)
            || "AUDITOR".equalsIgnoreCase(role);

    AssetReturnDAO dao = new AssetReturnDAO();
    List<AssetReturn> returnList = dao.getAllReturns();

    String msg = request.getParameter("msg");

    int good = 0;
    int damaged = 0;
    int needsRepair = 0;

    for (AssetReturn r : returnList) {
        if ("GOOD".equalsIgnoreCase(r.getReturnCondition())) {
            good++;
        }

        if ("DAMAGED".equalsIgnoreCase(r.getReturnCondition())) {
            damaged++;
        }

        if ("NEEDS_REPAIR".equalsIgnoreCase(r.getReturnCondition())) {
            needsRepair++;
        }
    }
%>

<!DOCTYPE html>
<html>
<head>
    <title>IR-AMS Asset Returns</title>

    <link rel="stylesheet"
          href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.0/css/all.min.css">

    <link rel="stylesheet" href="css/ir-glass.css?v=28000">
    <link rel="stylesheet" href="css/ams-pro.css?v=28000">
    <link rel="stylesheet" href="css/ir-ams-railway-ui.css?v=28000">
<link rel="stylesheet" href="css/returns.css?v=topbarfix1">
        </head>

<body class="railway-ui">

<div class="app ams-shell">

    
    <jsp:include page="sidebar.jsp" />

    <main class="main railway-main">
        <jsp:include page="topbar.jsp" />

        <div class="main-scroll-content">

            <section class="return-hero">
                <h1>Asset Return Control</h1>

                <p>
                    Monitor returned assets, return condition, receiving authority, allocation closure
                    and repair requirement status for railway operational inventory.
                </p>


                <div class="hero-pills">
                    <div class="hero-pill"><i class="fa-solid fa-rotate-left"></i> Return Tracking</div>
                    <div class="hero-pill"><i class="fa-solid fa-clipboard-check"></i> Condition Verification</div>
                    <div class="hero-pill"><i class="fa-solid fa-user-shield"></i> Received By Record</div>
                    <div class="hero-pill"><i class="fa-solid fa-wrench"></i> Repair Flagging</div>
                </div>
            </section>

            <% if ("denied".equals(request.getParameter("access"))) { %>
                <div class="page-error">
                    <i class="fa-solid fa-triangle-exclamation"></i>
                    Access denied. You do not have permission to create asset return.
                </div>
            <% } %>

            <section class="kpi-grid">

                <div class="kpi-card">
                    <div class="kpi-icon purple"><i class="fa-solid fa-rotate-left"></i></div>
                    <h3 class="kpi-title">Total Returns</h3>
                    <div class="kpi-value"><%= formatNumber(returnList.size()) %></div>
                </div>

                <div class="kpi-card">
                    <div class="kpi-icon green"><i class="fa-solid fa-circle-check"></i></div>
                    <h3 class="kpi-title">Good Condition</h3>
                    <div class="kpi-value"><%= formatNumber(good) %></div>
                </div>

                <div class="kpi-card">
                    <div class="kpi-icon red"><i class="fa-solid fa-triangle-exclamation"></i></div>
                    <h3 class="kpi-title">Damaged</h3>
                    <div class="kpi-value"><%= formatNumber(damaged) %></div>
                </div>

                <div class="kpi-card">
                    <div class="kpi-icon orange"><i class="fa-solid fa-wrench"></i></div>
                    <h3 class="kpi-title">Needs Repair</h3>
                    <div class="kpi-value"><%= formatNumber(needsRepair) %></div>
                </div>

                <div class="kpi-card">
                    <div class="kpi-icon blue"><i class="fa-solid fa-user-shield"></i></div>
                    <h3 class="kpi-title">Verified Returns</h3>
                    <div class="kpi-value"><%= formatNumber(returnList.size()) %></div>
                </div>

                <div class="kpi-card">
                    <div class="kpi-icon pink"><i class="fa-solid fa-database"></i></div>
                    <h3 class="kpi-title">Live Status</h3>
                    <p>ON</p>
                </div>

            </section>

            <%
                if ("added".equals(msg)) {
            %>
                <div class="page-success">
                    <i class="fa-solid fa-circle-check"></i>
                    Asset return registered successfully and asset status updated.
                </div>
            <%
                }
            %>

            <section class="glass-panel">

                <div class="registry-toolbar">

                    <div>
                        <h2>Return Verification Table</h2>
                        <p class="table-subtext">
                            Showing <%= returnList.size() %> live asset return records from railway database.
                        </p>
                    </div>

                    <div class="registry-actions">

                        <% if (canExportReturnReport) { %>
                            <a href="export_returns_report.jsp" class="btn return-export-btn">
                                <i class="fa-solid fa-file-excel"></i> Export Excel
                            </a>
                        <% } %>

                    </div>

                </div>

                <div class="registry-filter-grid return-filter-grid <%= canCreateReturn ? "has-primary" : "no-primary" %>">

                    <div class="registry-search">
                        <i class="fa-solid fa-magnifying-glass"></i>
                        <input type="text"
                               id="returnSearch"
                               placeholder="Search return id, asset, employee, department, condition...">
                    </div>

                    <select id="returnConditionFilter" class="status-filter-select">
                        <option value="ALL">All Condition</option>
                        <option value="GOOD">GOOD</option>
                        <option value="DAMAGED">DAMAGED</option>
                        <option value="NEEDS_REPAIR">NEEDS_REPAIR</option>
                        <option value="REPAIR_REQUIRED">REPAIR REQUIRED</option>
                    </select>

                    <% if (canCreateReturn) { %>
                        <a href="add_return.jsp" class="btn btn-primary return-primary-action-btn">
                            <i class="fa-solid fa-plus"></i> New Return
                        </a>
                    <% } %>

                    <button type="button" class="btn" onclick="resetReturnFilters()">
                        <i class="fa-solid fa-filter-circle-xmark"></i> Reset Filters
                    </button>

                </div>

                <div class="registry-table-wrap">

                    <table class="asset-table" id="returnTable">
                        <colgroup>
                            <col style="width: 7%;">
                            <col style="width: 8%;">
                            <col style="width: 12%;">
                            <col style="width: 12%;">
                            <col style="width: 9%;">
                            <col style="width: 9%;">
                            <col style="width: 9%;">
                            <col style="width: 8%;">
                            <col style="width: 15%;">
                            <col style="width: 11%;">
                        </colgroup>
                        <thead>
                            <tr>
                                <th onclick="sortTable(0)" style="cursor: pointer;" title="Click to sort">Return ID <i class="fa-solid fa-sort" style="color: #cbd5e1; margin-left: 4px;"></i></th>
                                <th onclick="sortTable(1)" style="cursor: pointer;" title="Click to sort">Allocation ID <i class="fa-solid fa-sort" style="color: #cbd5e1; margin-left: 4px;"></i></th>
                                <th onclick="sortTable(2)" style="cursor: pointer;" title="Click to sort">Asset <i class="fa-solid fa-sort" style="color: #cbd5e1; margin-left: 4px;"></i></th>
                                <th onclick="sortTable(3)" style="cursor: pointer;" title="Click to sort">Employee <i class="fa-solid fa-sort" style="color: #cbd5e1; margin-left: 4px;"></i></th>
                                <th onclick="sortTable(4)" style="cursor: pointer;" title="Click to sort">Department <i class="fa-solid fa-sort" style="color: #cbd5e1; margin-left: 4px;"></i></th>
                                <th onclick="sortTable(5)" style="cursor: pointer;" title="Click to sort">Return Date <i class="fa-solid fa-sort" style="color: #cbd5e1; margin-left: 4px;"></i></th>
                                <th onclick="sortTable(6)" style="cursor: pointer;" title="Click to sort">Condition <i class="fa-solid fa-sort" style="color: #cbd5e1; margin-left: 4px;"></i></th>
                                <th onclick="sortTable(7)" style="cursor: pointer;" title="Click to sort">Received By <i class="fa-solid fa-sort" style="color: #cbd5e1; margin-left: 4px;"></i></th>
                                <th>Remarks</th>
                                <th>Control Actions</th>
                            </tr>
                        </thead>

                        <tbody>

                            <%
                                for (AssetReturn r : returnList) {
                            %>

                            <tr>
                                <td>
                                    <span class="return-id-pill">
                                        RET-<%= r.getReturnId() %>
                                    </span>
                                </td>

                                <td>
                                    <span class="return-allocation-pill">
                                        ALLOC-<%= r.getAllocationId() %>
                                    </span>
                                </td>

                                <td>
                                    <span class="asset-mini-pill">
                                        <%= r.getAssetCode() %>
                                    </span>
                                    <br>
                                    <span class="table-subtext">
                                        <%= r.getAssetName() %>
                                    </span>
                                </td>

                                <td>
                                    <span class="employee-mini-pill">
                                        <%= r.getEmployeeCode() %>
                                    </span>
                                    <br>
                                    <strong><%= r.getEmployeeName() %></strong>
                                </td>

                                <td><%= r.getDepartmentName() %></td>

                                <td><%= r.getReturnDate() %></td>

                                <td>
                                    <span class="status-badge condition-<%= r.getReturnCondition() %>">
                                        <%= r.getReturnCondition() %>
                                    </span>
                                </td>

                                <td><%= r.getReceivedBy() %></td>

                                <td><%= r.getRemarks() %></td>

                                <td>
                                    <div class="asset-actions">

                                        <a href="view_return.jsp?id=<%= r.getReturnId() %>"
                                           class="asset-action-btn inspect-btn" title="View details of this return record">
                                            <i class="fa-solid fa-eye"></i> View
                                        </a>

                                        <%
                                            if ("GOOD".equalsIgnoreCase(r.getReturnCondition())) {
                                        %>
                                            <span class="condition-action-badge condition-good-action" title="Condition verified">
                                                <i class="fa-solid fa-circle-check"></i> Verified
                                            </span>
                                        <%
                                            } else {
                                        %>
                                            <span class="condition-action-badge condition-repair-action" title="Asset requires repair">
                                                <i class="fa-solid fa-wrench"></i> Repair Flagged
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

                    <div id="returnNoRecords" class="no-records-message" style="display:none;">
                        <i class="fa-solid fa-circle-info"></i>
                        <strong>No matching return records found.</strong>
                        Try changing search keyword or condition filter.
                    </div>

                </div>

            </section>

        </div>
    </main>

</div>
<script>
    const returnSearch = document.getElementById("returnSearch");
    const returnConditionFilter = document.getElementById("returnConditionFilter");
    const tableRows = document.querySelectorAll("#returnTable tbody tr");
    const returnNoRecords = document.getElementById("returnNoRecords");

    function normalizeText(text) {
        return text
                .toLowerCase()
                .replace(/\s+/g, " ")
                .trim();
    }

    function applyReturnFilters() {
        const keyword = normalizeText(returnSearch.value);
        const selectedCondition = returnConditionFilter.value;

        let visibleCount = 0;

        tableRows.forEach(row => {
            const rowText = normalizeText(row.textContent);

            const conditionBadge = row.querySelector(".status-badge");
            const rowCondition = conditionBadge ? conditionBadge.textContent.trim() : "";

            const matchesSearch =
                    keyword === "" || rowText.indexOf(keyword) !== -1;

            let matchesCondition = false;

            if (selectedCondition === "ALL") {
                matchesCondition = true;
            } else if (selectedCondition === "REPAIR_REQUIRED") {
                matchesCondition = rowCondition === "DAMAGED" || rowCondition === "NEEDS_REPAIR";
            } else {
                matchesCondition = rowCondition === selectedCondition;
            }

            if (matchesSearch && matchesCondition) {
                row.style.display = "";
                visibleCount++;
            } else {
                row.style.display = "none";
            }
        });

        if (returnNoRecords) {
            returnNoRecords.style.display = visibleCount === 0 ? "block" : "none";
        }
    }

    function resetReturnFilters() {
        returnConditionFilter.value = "ALL";
        returnSearch.value = "";
        applyReturnFilters();
    }

    returnSearch.addEventListener("input", applyReturnFilters);
    returnConditionFilter.addEventListener("change", applyReturnFilters);

    applyReturnFilters();

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
    
    var sortDirections = [true, true, true, true, true, true, true, true];
    function sortTable(columnIndex) {
        var table = document.getElementById("returnTable");
        if (!table) return;
        
        var tbody = table.querySelector("tbody");
        if (!tbody) return;
        
        var rows = Array.from(tbody.querySelectorAll("tr"));
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

<script src="js/topbar-search.js?v=28000"></script>
<script src="js/user-dropdown.js?v=28000"></script>
<script src="js/sidebar-role.js?v=28000"></script>
<script src="js/ir-body-watermark.js?v=28000"></script>
<script src="js/dashboard-actions.js?v=28000"></script>

</body>
</html>