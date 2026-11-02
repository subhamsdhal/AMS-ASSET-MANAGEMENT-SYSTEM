<%@page contentType="text/html" pageEncoding="UTF-8"%>
<%@page import="com.mycompany.asset_management_system_ams.AssetAllocation"%>
<%@page import="com.mycompany.asset_management_system_ams.AssetAllocationDAO"%>
<%@page import="java.util.List"%>

<%!
    private String safeText(String value) {
        if (value == null) {
            return "";
        }

        return value
                .replace("&", "&amp;")
                .replace("<", "&lt;")
                .replace(">", "&gt;")
                .replace("\"", "&quot;")
                .replace("'", "&#39;");
    }

    private String cleanRole(String role) {
        if (role == null || role.trim().equals("")) {
            return "User";
        }

        String cleaned = role.replace("_", " ").toLowerCase();
        String[] parts = cleaned.split(" ");
        StringBuilder result = new StringBuilder();

        for (String part : parts) {
            if (part.length() > 0) {
                result.append(part.substring(0, 1).toUpperCase())
                      .append(part.substring(1))
                      .append(" ");
            }
        }

        return result.toString().trim();
    }

    private String userInitial(String username) {
        if (username == null || username.trim().equals("")) {
            return "IR";
        }

        String cleaned = username.trim();
        if (cleaned.length() == 1) {
            return cleaned.toUpperCase();
        }

        return cleaned.substring(0, 2).toUpperCase();
    }

    private String safeStatusClass(String status) {
        if (status == null) {
            return "";
        }

        return status.toLowerCase().replace("_", "-").replace(" ", "-");
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

    boolean canManageAllocation = ("SUPER_ADMIN".equals(role) || "ADMIN".equals(role)) || "ASSET_MANAGER".equals(role);
    boolean canExportAllocationReport = ("SUPER_ADMIN".equals(role) || "ADMIN".equals(role))
            || "ASSET_MANAGER".equals(role)
            || "AUDITOR".equals(role);

    AssetAllocationDAO dao = new AssetAllocationDAO();

    String employeeIdParam = request.getParameter("employeeId");
    boolean employeeFiltered = false;
    int selectedEmployeeId = 0;

    try {
        if (employeeIdParam != null && !employeeIdParam.trim().equals("")) {
            selectedEmployeeId = Integer.parseInt(employeeIdParam);
            employeeFiltered = selectedEmployeeId > 0;
        }
    } catch (Exception e) {
        employeeFiltered = false;
        selectedEmployeeId = 0;
    }

    List<AssetAllocation> allocationList;

    if (employeeFiltered) {
        allocationList = dao.getAllocationsByEmployeeId(selectedEmployeeId);
    } else {
        allocationList = dao.getAllAllocations();
    }

    String msg = request.getParameter("msg");

    int allocated = 0;
    int returned = 0;

    for (AssetAllocation allocation : allocationList) {
        if ("ALLOCATED".equals(allocation.getAllocationStatus())) {
            allocated++;
        }

        if ("RETURNED".equals(allocation.getAllocationStatus())) {
            returned++;
        }
    }
%>

<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>IR-AMS | Allocation</title>

    <link rel="stylesheet"
          href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.0/css/all.min.css">

    <link rel="stylesheet" href="css/ir-glass.css?v=28000">
    <link rel="stylesheet" href="css/ams-pro.css?v=28000">
    <link rel="stylesheet" href="css/ir-ams-railway-ui.css?v=28000">
<link rel="stylesheet" href="css/allocation.css?v=topbarfix1">
</head>

<body class="railway-ui">
<div class="app ams-shell">

    <jsp:include page="sidebar.jsp" />

    <main class="main railway-main">
        <jsp:include page="topbar.jsp" />

        <div class="main-scroll-content allocation-board">

            <section class="allocation-hero-official">
                <div class="allocation-hero-copy">
                    <h1>Asset Allocation Control</h1>

                    <p>
                        Track official asset issue, assigned employee, department mapping,
                        return status, custody records, and live allocation movement across
                        railway offices and sections.
                    </p>

                    <div class="allocation-hero-actions">
                        <a href="add_allocation.jsp" class="allocation-hero-tab">
                            <i class="fa-solid fa-plus"></i>
                            Allocate Asset
                        </a>

                        <a href="returns.jsp" class="allocation-hero-tab">
                            <i class="fa-solid fa-rotate-left"></i>
                            Return Records
                        </a>

                        <a href="reports.jsp" class="allocation-hero-tab">
                            <i class="fa-solid fa-chart-simple"></i>
                            Allocation Reports
                        </a>
                    </div>
                </div>
            </section>

            <% if ("denied".equals(request.getParameter("access"))) { %>
                <div class="page-error">
                    <i class="fa-solid fa-triangle-exclamation"></i>
                    Access denied. You do not have permission to create asset allocation.
                </div>
            <% } %>

            <section class="allocation-kpi-grid">
                <div class="allocation-kpi-card">
                    <div class="kpi-icon purple"><i class="fa-solid fa-right-left"></i></div>
                    <div>
                        <h3>Total Allocations</h3>
                        <p><%= allocationList.size() %></p>
                    </div>
                </div>

                <div class="allocation-kpi-card">
                    <div class="kpi-icon"><i class="fa-solid fa-user-check"></i></div>
                    <div>
                        <h3>Currently Allocated</h3>
                        <p><%= allocated %></p>
                    </div>
                </div>

                <div class="allocation-kpi-card">
                    <div class="kpi-icon green"><i class="fa-solid fa-rotate-left"></i></div>
                    <div>
                        <h3>Returned</h3>
                        <p><%= returned %></p>
                    </div>
                </div>

                <div class="allocation-kpi-card">
                    <div class="kpi-icon orange"><i class="fa-solid fa-laptop"></i></div>
                    <div>
                        <h3>Custody Records</h3>
                        <p><%= allocationList.size() %></p>
                    </div>
                </div>

                <div class="allocation-kpi-card">
                    <div class="kpi-icon"><i class="fa-solid fa-shield-halved"></i></div>
                    <div>
                        <h3>Audit Ready</h3>
                        <p>YES</p>
                    </div>
                </div>

                <div class="allocation-kpi-card">
                    <div class="kpi-icon red"><i class="fa-solid fa-database"></i></div>
                    <div>
                        <h3>Live Status</h3>
                        <p>ON</p>
                    </div>
                </div>
            </section>

            <%
                if ("added".equals(msg)) {
            %>
                <div class="page-success">
                    <i class="fa-solid fa-circle-check"></i>
                    Asset allocation added successfully and asset status updated.
                </div>
            <%
                } else if ("returned".equals(msg)) {
            %>
                <div class="page-success">
                    <i class="fa-solid fa-circle-check"></i>
                    Asset returned successfully. Allocation status updated and asset is now AVAILABLE.
                </div>
            <%
                } else if ("returnfailed".equals(msg)) {
            %>
                <div class="page-error">
                    <i class="fa-solid fa-triangle-exclamation"></i>
                    Asset return failed. This allocation may already be returned.
                </div>
            <%
                }
            %>

            <section class="allocation-panel">
                <div class="allocation-toolbar">
                    <div>
                        <h2>Allocation Control Table</h2>
                        <p class="table-subtext">
                            <% if (employeeFiltered) { %>
                                Showing <%= allocationList.size() %> allocation records for selected employee.
                            <% } else { %>
                                Showing <%= allocationList.size() %> live allocation records from railway database.
                            <% } %>
                        </p>
                    </div>

                    <div class="allocation-actions">
                        <% if (employeeFiltered) { %>
                            <a href="allocation.jsp" class="btn">
                                <i class="fa-solid fa-list"></i> All Allocations
                            </a>
                        <% } %>

                        <% if (canExportAllocationReport) { %>
                            <a href="export_allocation_report.jsp" class="btn allocation-export-btn">
                                <i class="fa-solid fa-file-excel"></i> Export Excel
                            </a>
                        <% } %>
                    </div>
                </div>

                <div class="allocation-filter-grid allocation-report-filter-grid <%= canManageAllocation ? "has-primary" : "no-primary" %>">
                    <div class="allocation-search">
                        <i class="fa-solid fa-magnifying-glass"></i>
                        <input type="text"
                               id="allocationSearch"
                               placeholder="Search asset code, employee, department, status...">
                    </div>

                    <select id="allocationStatusFilter" class="status-filter-select">
                        <option value="ALL">All Status</option>
                        <option value="ALLOCATED">ALLOCATED</option>
                        <option value="RETURNED">RETURNED</option>
                    </select>

                    <% if (canManageAllocation) { %>
                        <a href="add_allocation.jsp" class="btn btn-primary allocation-primary-action-btn">
                            <i class="fa-solid fa-plus"></i> Allocate Asset
                        </a>
                    <% } %>

                    <button type="button" class="btn" onclick="resetAllocationFilters()">
                        <i class="fa-solid fa-filter-circle-xmark"></i> Reset Filters
                    </button>
                </div>

                <div class="allocation-table-wrap">
                    <table class="allocation-table" id="allocationTable">
                        <thead>
                            <tr>
                                <th onclick="sortTable(0)" style="cursor: pointer;" title="Click to sort">Allocation ID <i class="fa-solid fa-sort" style="color: #cbd5e1; margin-left: 4px;"></i></th>
                                <th onclick="sortTable(1)" style="cursor: pointer;" title="Click to sort">Asset <i class="fa-solid fa-sort" style="color: #cbd5e1; margin-left: 4px;"></i></th>
                                <th onclick="sortTable(2)" style="cursor: pointer;" title="Click to sort">Employee <i class="fa-solid fa-sort" style="color: #cbd5e1; margin-left: 4px;"></i></th>
                                <th onclick="sortTable(3)" style="cursor: pointer;" title="Click to sort">Department <i class="fa-solid fa-sort" style="color: #cbd5e1; margin-left: 4px;"></i></th>
                                <th onclick="sortTable(4)" style="cursor: pointer;" title="Click to sort">Allocation Date <i class="fa-solid fa-sort" style="color: #cbd5e1; margin-left: 4px;"></i></th>
                                <th onclick="sortTable(5)" style="cursor: pointer;" title="Click to sort">Return Date <i class="fa-solid fa-sort" style="color: #cbd5e1; margin-left: 4px;"></i></th>
                                <th onclick="sortTable(6)" style="cursor: pointer;" title="Click to sort">Status <i class="fa-solid fa-sort" style="color: #cbd5e1; margin-left: 4px;"></i></th>
                                <th>Remarks</th>
                                <th>Control Actions</th>
                            </tr>
                        </thead>

                        <tbody>
                            <%
                                for (AssetAllocation allocation : allocationList) {
                            %>
                            <tr>
                                <td>
                                    <span class="allocation-id-pill">
                                        ALLOC-<%= allocation.getAllocationId() %>
                                    </span>
                                </td>

                                <td>
                                    <span class="asset-mini-pill">
                                        <%= safeText(allocation.getAssetCode()) %>
                                    </span>
                                    <br>
                                    <span class="table-subtext">
                                        <%= safeText(allocation.getAssetName()) %>
                                    </span>
                                </td>

                                <td>
                                    <span class="employee-mini-pill">
                                        <%= safeText(allocation.getEmployeeCode()) %>
                                    </span>
                                    <br>
                                    <strong><%= safeText(allocation.getEmployeeName()) %></strong>
                                </td>

                                <td><%= safeText(allocation.getDepartmentName()) %></td>

                                <td><%= allocation.getAllocationDate() %></td>

                                <td>
                                    <%
                                        if (allocation.getReturnDate() == null) {
                                    %>
                                        <span class="return-pending">Not Returned</span>
                                    <%
                                        } else {
                                    %>
                                        <%= allocation.getReturnDate() %>
                                    <%
                                        }
                                    %>
                                </td>

                                <td>
                                    <span class="status-badge status-<%= safeStatusClass(allocation.getAllocationStatus()) %>">
                                        <%= safeText(allocation.getAllocationStatus()) %>
                                    </span>
                                </td>

                                <td><%= safeText(allocation.getRemarks()) %></td>

                                <td>
                                    <div class="asset-actions">
                                        <a href="view_allocation.jsp?id=<%= allocation.getAllocationId() %>"
                                           class="asset-action-btn inspect-btn" title="View details of this allocation">
                                            <i class="fa-solid fa-eye"></i> Details
                                        </a>

                                        <% if ("ALLOCATED".equals(allocation.getAllocationStatus()) && canManageAllocation) { %>
                                            <a href="add_return.jsp?allocationId=<%= allocation.getAllocationId() %>"
                                               class="asset-action-btn custody-btn" title="Process asset return">
                                                <i class="fa-solid fa-rotate-left"></i> Return
                                            </a>
                                        <% } else { %>
                                            <span class="asset-action-btn returned-disabled" title="Asset already returned">
                                                <i class="fa-solid fa-rotate-left"></i> Returned
                                            </span>
                                        <% } %>
                                    </div>
                                </td>
                            </tr>
                            <%
                                }
                            %>
                        </tbody>
                    </table>
                </div>

                <div id="allocationNoRecords" class="no-records-message" style="display:none;">
                    <i class="fa-solid fa-circle-info"></i>
                    <strong>No matching allocation records found.</strong>
                    Try changing search keyword or status filter.
                </div>
            </section>

        </div>
    </main>

</div>

<script>
    (function () {
        function updateBodyEmblemCenter() {
            var main = document.querySelector(".railway-main") || document.querySelector(".main");
            var topbar = document.querySelector(".railway-topbar") || document.querySelector(".topbar");

            if (!main) {
                document.documentElement.style.setProperty("--ir-body-emblem-left", "50vw");
                document.documentElement.style.setProperty("--ir-body-emblem-top", "54vh");
                return;
            }

            var mainRect = main.getBoundingClientRect();
            var topbarRect = topbar ? topbar.getBoundingClientRect() : null;

            var visibleLeft = Math.max(mainRect.left, 0);
            var visibleRight = Math.min(mainRect.right, window.innerWidth);

            if (visibleRight <= visibleLeft) {
                visibleLeft = 0;
                visibleRight = window.innerWidth;
            }

            var topLimit = topbarRect ? Math.max(topbarRect.bottom, mainRect.top, 0) : Math.max(mainRect.top, 0);
            var bottomLimit = Math.min(window.innerHeight, mainRect.bottom);

            if (bottomLimit <= topLimit) {
                topLimit = 0;
                bottomLimit = window.innerHeight;
            }

            var centerX = visibleLeft + ((visibleRight - visibleLeft) / 2);
            var centerY = topLimit + ((bottomLimit - topLimit) / 2);

            document.documentElement.style.setProperty("--ir-body-emblem-left", centerX + "px");
            document.documentElement.style.setProperty("--ir-body-emblem-top", centerY + "px");
        }

        function scheduleBodyEmblemCenter() {
            requestAnimationFrame(updateBodyEmblemCenter);
            window.setTimeout(updateBodyEmblemCenter, 80);
            window.setTimeout(updateBodyEmblemCenter, 250);
        }

        window.addEventListener("load", scheduleBodyEmblemCenter);
        window.addEventListener("resize", scheduleBodyEmblemCenter);
        window.addEventListener("orientationchange", scheduleBodyEmblemCenter);

        document.addEventListener("click", function (event) {
            if (event.target.closest(".nav-toggle")
                    || event.target.closest("[data-sidebar-toggle]")
                    || event.target.closest(".sidebar-toggle")
                    || event.target.closest(".menu-toggle")) {
                scheduleBodyEmblemCenter();
            }
        });

        scheduleBodyEmblemCenter();
    })();

    (function () {
        var allocationSearch = document.getElementById("allocationSearch");
        var allocationStatusFilter = document.getElementById("allocationStatusFilter");
        var tableRows = document.querySelectorAll("#allocationTable tbody tr");
        var allocationNoRecords = document.getElementById("allocationNoRecords");

        function normalizeText(text) {
            if (!text) {
                return "";
            }

            return text
                    .toString()
                    .toLowerCase()
                    .replace(/\s+/g, " ")
                    .trim();
        }

        function applyAllocationFilters() {
            var keyword = normalizeText(allocationSearch ? allocationSearch.value : "");
            var selectedStatus = allocationStatusFilter ? allocationStatusFilter.value : "ALL";
            var visibleCount = 0;

            tableRows.forEach(function (row) {
                var rowText = normalizeText(row.textContent);
                var statusBadge = row.querySelector(".status-badge");
                var rowStatus = statusBadge ? statusBadge.textContent.trim() : "";

                var matchesSearch = keyword === "" || rowText.indexOf(keyword) !== -1;
                var matchesStatus = selectedStatus === "ALL" || rowStatus === selectedStatus;

                if (matchesSearch && matchesStatus) {
                    row.style.display = "";
                    visibleCount++;
                } else {
                    row.style.display = "none";
                }
            });

            if (allocationNoRecords) {
                allocationNoRecords.style.display = visibleCount === 0 ? "block" : "none";
            }
        }

        window.resetAllocationFilters = function () {
            if (allocationStatusFilter) {
                allocationStatusFilter.value = "ALL";
            }

            if (allocationSearch) {
                allocationSearch.value = "";
            }

            applyAllocationFilters();
        };

        if (allocationSearch) {
            allocationSearch.addEventListener("input", applyAllocationFilters);
        }

        if (allocationStatusFilter) {
            allocationStatusFilter.addEventListener("change", applyAllocationFilters);
        }

        applyAllocationFilters();
    })();

    var sortDirections = [true, true, true, true, true, true, true]; // true = ASC, false = DESC
    function sortTable(columnIndex) {
        var table = document.getElementById("allocationTable");
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
