<%@page contentType="text/html" pageEncoding="UTF-8"%>
<%@page import="com.mycompany.asset_management_system_ams.Department"%>
<%@page import="com.mycompany.asset_management_system_ams.DepartmentDAO"%>
<%@page import="java.util.List"%>
<%!
    private String safe(Object value) {
        if (value == null || String.valueOf(value).trim().isEmpty()) {
            return "";
        }

        return String.valueOf(value).trim()
                .replace("&", "&amp;")
                .replace("<", "&lt;")
                .replace(">", "&gt;")
                .replace("\"", "&quot;")
                .replace("'", "&#39;");
    }
%>
<%@page import="com.mycompany.asset_management_system_ams.RoleAccessUtil"%>
<%
    String username = (String) session.getAttribute("username");
    String role = (String) session.getAttribute("role");

    if (username == null || role == null) {
        response.sendRedirect("login.jsp");
        return;
    }

    boolean canViewDepartments = RoleAccessUtil.hasAccess(role, "DEPARTMENT_MANAGEMENT", "VIEW");
    boolean canManageDepartments = RoleAccessUtil.hasAccess(role, "DEPARTMENT_MANAGEMENT", "CREATE");
    boolean canExportDepartments = RoleAccessUtil.hasAccess(role, "DEPARTMENT_MANAGEMENT", "EXPORT");

    if (!canViewDepartments) {
        response.sendRedirect("dashboard.jsp?access=denied");
        return;
    }

    List<Department> departmentsList = DepartmentDAO.getAllDepartments();

    String msg = request.getParameter("msg");
    String error = request.getParameter("error");
    String access = request.getParameter("access");
    String blockReason = request.getParameter("reason");

    String contextPath = request.getContextPath();

    int totalDepartments = departmentsList != null ? departmentsList.size() : 0;
    int activeDepartments = 0;
    int inactiveDepartments = 0;
    int totalEmployees = 0;
    int totalAssets = 0;
    java.util.Set<String> headSet = new java.util.HashSet<String>();

    if (departmentsList != null) {
        for (Department dept : departmentsList) {
            if ("ACTIVE".equalsIgnoreCase(dept.getStatus())) {
                activeDepartments++;
            } else {
                inactiveDepartments++;
            }
            totalEmployees += dept.getEmployeeCount();
            totalAssets += dept.getAssetCount();
            
            if (dept.getDepartmentHeadName() != null && !dept.getDepartmentHeadName().trim().isEmpty()) {
                headSet.add(dept.getDepartmentHeadName().trim());
            }
        }
    }
    int uniqueHeads = headSet.size();

%>
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <title>Departments - Railway AMS</title>
    <meta name="viewport" content="width=device-width, initial-scale=1.0">

    <!-- Railway AMS global styles -->
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.0/css/all.min.css">
    <link rel="stylesheet" href="<%= contextPath %>/css/ir-glass.css?v=28000">
    <link rel="stylesheet" href="<%= contextPath %>/css/ams-pro.css?v=28000">
    <link rel="stylesheet" href="<%= contextPath %>/css/ir-ams-railway-ui.css?v=28000">
    
    <link rel="stylesheet" href="<%= contextPath %>/css/departments.css?v=28002">
</head>

<body class="railway-ui">
<div class="app ams-shell">

    <jsp:include page="sidebar.jsp" />

    <main class="main railway-main">
        <jsp:include page="topbar.jsp" />

        <div class="main-scroll-content">
            <div class="department-board">

                <section class="department-hero">
                    <div class="department-hero-copy">
                        <span class="department-eyebrow">
                            <i class="fa-solid fa-building-columns"></i>
                            Departments Module · East Coast Railway
                        </span>

                        <h1>Department Management</h1>

                        <p>
                            Manage official railway departments, department heads, activity status,
                            employee strength and asset linkage from one clean administrative register.
                        </p>

                        <div class="department-hero-pills">
                            <div class="department-hero-pill"><i class="fa-solid fa-building"></i> Department Register</div>
                            <div class="department-hero-pill"><i class="fa-solid fa-users"></i> Employee Linking</div>
                            <div class="department-hero-pill"><i class="fa-solid fa-laptop-file"></i> Asset Mapping</div>
                        </div>
                    </div>
                </section>

                <% if ("added".equals(msg)) { %>
                    <div class="department-message success">
                        <i class="fa-solid fa-circle-check"></i>
                        Department added successfully.
                    </div>
                <% } else if ("updated".equals(msg)) { %>
                    <div class="department-message success">
                        <i class="fa-solid fa-circle-check"></i>
                        Department updated successfully.
                    </div>
                <% } else if ("deleted".equals(msg)) { %>
                    <div class="department-message success">
                        <i class="fa-solid fa-circle-check"></i>
                        Department deleted successfully.
                    </div>
                <% } else if ("invalid".equals(error)) { %>
                    <div class="department-message error">
                        <i class="fa-solid fa-circle-exclamation"></i>
                        Invalid request.
                    </div>
                <% } else if ("server".equals(error)) { %>
                    <div class="department-message error">
                        <i class="fa-solid fa-triangle-exclamation"></i>
                        Server error. Please try again.
                    </div>
                <% } else if ("denied".equals(access)) { %>
                    <div class="department-message error">
                        <i class="fa-solid fa-shield-halved"></i>
                        Access denied.
                    </div>
                <% } else if ("deleteblocked".equals(error)) { %>
                    <%-- Fault: this always showed the same fixed "assets or
                         employees" text regardless of the real reason - now
                         DeleteDepartmentServlet checks (and reports) the
                         specific blocking reason, matching the pattern already
                         used on employees.jsp. Falls back to the old generic
                         text only if the server ever sends this code without
                         a reason. --%>
                    <div class="department-message error">
                        <i class="fa-solid fa-triangle-exclamation"></i>
                        Cannot delete this department. <%= !safe(blockReason).isEmpty() ? safe(blockReason) : "It has linked assets or employees. Disable it instead." %>
                    </div>
                <% } %>

                <section class="department-kpi-grid">
                    <a href="departments.jsp" class="department-kpi-card">
                        <div class="department-kpi-icon">
                            <i class="fa-solid fa-building"></i>
                        </div>
                        <h3>Total Departments</h3>
                        <p><%= totalDepartments %></p>
                        <span><i class="fa-solid fa-arrow-up"></i> Registered units</span>
                    </a>

                    <a href="#" class="department-kpi-card" onclick="document.getElementById('departmentStatusFilter').value='ACTIVE'; applyDepartmentFilters(); return false;">
                        <div class="department-kpi-icon green">
                            <i class="fa-solid fa-circle-check"></i>
                        </div>
                        <h3>Active</h3>
                        <p><%= activeDepartments %></p>
                        <span><i class="fa-solid fa-arrow-up"></i> Live operations</span>
                    </a>

                    <a href="#" class="department-kpi-card" onclick="document.getElementById('departmentStatusFilter').value='INACTIVE'; applyDepartmentFilters(); return false;">
                        <div class="department-kpi-icon red">
                            <i class="fa-solid fa-xmark"></i>
                        </div>
                        <h3>Inactive</h3>
                        <p><%= inactiveDepartments %></p>
                        <span><i class="fa-solid fa-arrow-up"></i> Disabled units</span>
                    </a>

                    <a href="employees.jsp" class="department-kpi-card">
                        <div class="department-kpi-icon purple">
                            <i class="fa-solid fa-users"></i>
                        </div>
                        <h3>Employees Linked</h3>
                        <p><%= totalEmployees %></p>
                        <span><i class="fa-solid fa-arrow-up"></i> Assigned staff</span>
                    </a>

                    <a href="assets.jsp" class="department-kpi-card">
                        <div class="department-kpi-icon orange">
                            <i class="fa-solid fa-laptop-file"></i>
                        </div>
                        <h3>Assets Linked</h3>
                        <p><%= totalAssets %></p>
                        <span><i class="fa-solid fa-arrow-up"></i> Managed items</span>
                    </a>
                    
                    <a href="#" class="department-kpi-card">
                        <div class="department-kpi-icon" style="background: #eef2ff; color: #4f46e5; border-color: #c7d2fe;">
                            <i class="fa-solid fa-user-tie"></i>
                        </div>
                        <h3>Mapped Heads</h3>
                        <p><%= uniqueHeads %></p>
                        <span><i class="fa-solid fa-arrow-up"></i> Dept leadership</span>
                    </a>
                </section>

                <section class="department-control-panel">
                    <div class="department-panel-head">
                        <div>
                            <h2>Department Register</h2>
                            <p>
                                Showing <strong id="visibleDepartmentCount"><%= totalDepartments %></strong>
                                official departments from railway database.
                            </p>
                        </div>

                        <div class="department-toolbar">
                            <% if (canManageDepartments) { %>
                                <a href="add_department.jsp" class="department-btn primary">
                                    <i class="fa-solid fa-plus"></i>
                                    Add Department
                                </a>
                            <% } %>

                            <% if (canExportDepartments) { %>
                                <a href="export_departments_excel.jsp" class="department-btn green">
                                    <i class="fa-solid fa-file-excel"></i>
                                    Export Excel
                                </a>
                            <% } %>

                            <button type="button" class="department-btn" onclick="window.print();">
                                <i class="fa-solid fa-print"></i>
                                Print
                            </button>

                            <button type="button" class="department-btn" id="resetDepartmentFilters">
                                <i class="fa-solid fa-rotate-right"></i>
                                Reset
                            </button>
                        </div>
                    </div>

                    <div class="department-filter-grid">
                        <div class="department-search-wrap">
                            <i class="fa-solid fa-magnifying-glass"></i>
                            <input type="text"
                                   id="departmentSearch"
                                   class="department-search-control"
                                   placeholder="Search by code, name, head, status...">
                        </div>

                        <select id="departmentStatusFilter" class="department-select-control">
                            <option value="ALL">All Status</option>
                            <option value="ACTIVE">Active Only</option>
                            <option value="INACTIVE">Inactive Only</option>
                        </select>
                    </div>

                    <div class="department-no-records" id="departmentNoRecords">
                        <i class="fa-solid fa-magnifying-glass"></i>
                        No matching department records found.
                    </div>

                    <div class="department-table-wrap">
                        <table class="department-table" id="departmentTable">
                            <colgroup>
                                <col style="width: 12%;">
                                <col style="width: 24%;">
                                <col style="width: 17%;">
                                <col style="width: 9%;">
                                <col style="width: 8%;">
                                <col style="width: 9%;">
                                <col style="width: 21%;">
                            </colgroup>
                            <thead>
                                <tr>
                                    <th onclick="sortTable(0)" style="cursor: pointer;" title="Click to sort">Dept Code <i class="fa-solid fa-sort" style="color: #cbd5e1; margin-left: 4px;"></i></th>
                                    <th onclick="sortTable(1)" style="cursor: pointer;" title="Click to sort">Department <i class="fa-solid fa-sort" style="color: #cbd5e1; margin-left: 4px;"></i></th>
                                    <th onclick="sortTable(2)" style="cursor: pointer;" title="Click to sort">Department Head <i class="fa-solid fa-sort" style="color: #cbd5e1; margin-left: 4px;"></i></th>
                                    <th onclick="sortTable(3)" style="cursor: pointer;" title="Click to sort">Status <i class="fa-solid fa-sort" style="color: #cbd5e1; margin-left: 4px;"></i></th>
                                    <th onclick="sortTable(4)" style="cursor: pointer;" title="Click to sort">Assets <i class="fa-solid fa-sort" style="color: #cbd5e1; margin-left: 4px;"></i></th>
                                    <th onclick="sortTable(5)" style="cursor: pointer;" title="Click to sort">Employees <i class="fa-solid fa-sort" style="color: #cbd5e1; margin-left: 4px;"></i></th>
                                    <th>Control Actions</th>
                                </tr>
                            </thead>
                            <tbody>
                                <%
                                    if (departmentsList != null) {
                                        for (Department dept : departmentsList) {
                                            String activeStatus = dept.getStatus() == null ? "INACTIVE" : dept.getStatus().toUpperCase(java.util.Locale.ENGLISH);
                                            String deptDescription = safe(dept.getDescription());
                                            if (deptDescription.isEmpty()) {
                                                deptDescription = "No description available";
                                            }
                                            
                                            String rowSearchText = (
                                                dept.getDepartmentCode() + " "
                                                + dept.getDepartmentName() + " "
                                                + dept.getDepartmentHeadName() + " "
                                                + activeStatus
                                            ).toLowerCase(java.util.Locale.ENGLISH);
                                            
                                            String statusClassValue = "neutral";
                                            String displayStatus = activeStatus;
                                            if ("ACTIVE".equals(activeStatus)) {
                                                statusClassValue = "success";
                                                displayStatus = "Active";
                                            } else if ("INACTIVE".equals(activeStatus)) {
                                                statusClassValue = "danger";
                                                displayStatus = "Inactive";
                                            }
                                %>
                                    <tr class="department-row"
                                        data-search="<%= safe(rowSearchText) %>"
                                        data-status="<%= activeStatus %>">

                                        <td>
                                            <div class="department-identity">
                                                <div class="department-avatar">IR</div>
                                                <div>
                                                    <strong><%= safe(dept.getDepartmentCode()) %></strong>
                                                    <span>Code</span>
                                                </div>
                                            </div>
                                        </td>

                                        <td>
                                            <span class="department-main-text"><%= safe(dept.getDepartmentName()) %></span>
                                            <span class="department-sub-text"><%= deptDescription %></span>
                                        </td>

                                        <td>
                                            <% if (dept.getDepartmentHeadName() != null && !dept.getDepartmentHeadName().trim().isEmpty()) { %>
                                                <span class="department-main-text"><%= safe(dept.getDepartmentHeadName()) %></span>
                                                <span class="department-sub-text">Head of Dept</span>
                                            <% } else { %>
                                                <span class="department-main-text" style="color: #94a3b8;">Not Assigned</span>
                                            <% } %>
                                        </td>

                                        <td>
                                            <span class="department-status <%= statusClassValue %>">
                                                <%= displayStatus %>
                                            </span>
                                        </td>

                                        <td>
                                            <span class="assigned-pill <%= dept.getAssetCount() > 0 ? "green" : "" %>">
                                                <i class="fa-solid fa-laptop"></i>
                                                <span><%= dept.getAssetCount() %></span>
                                            </span>
                                        </td>

                                        <td>
                                            <span class="assigned-pill <%= dept.getEmployeeCount() > 0 ? "green" : "" %>">
                                                <i class="fa-solid fa-users"></i>
                                                <span><%= dept.getEmployeeCount() %></span>
                                            </span>
                                        </td>

                                        <td>
                                            <div class="department-action-grid">
                                                <a href="view_department.jsp?id=<%= dept.getDepartmentId() %>"
                                                   class="department-action-btn" title="View department details">
                                                    <i class="fa-solid fa-eye"></i> View
                                                </a>

                                                <% if (canManageDepartments) { %>
                                                    <a href="edit_department.jsp?id=<%= dept.getDepartmentId() %>"
                                                       class="department-action-btn orange" title="Edit department record">
                                                        <i class="fa-solid fa-pen-to-square"></i> Edit
                                                    </a>
                                                    <form action="DeleteDepartmentServlet" method="post" style="display:inline;" onsubmit="return confirm('Delete this department? This cannot be undone.');">
                                                        <input type="hidden" name="id" value="<%= dept.getDepartmentId() %>">
                                                        <button type="submit" class="department-action-btn red" style="border:none; cursor:pointer;" title="Delete department">
                                                            <i class="fa-solid fa-trash"></i> Delete
                                                        </button>
                                                    </form>
                                                <% } else { %>
                                                    <span class="department-action-btn" title="You do not have permission to modify">
                                                        <i class="fa-solid fa-lock"></i> Locked
                                                    </span>
                                                <% } %>
                                            </div>
                                        </td>
                                    </tr>
                                <%
                                        }
                                    }
                                %>
                            </tbody>
                        </table>
                    </div>
                </section>
            </div>
        </div>
    </main>
</div>

<script>
    (function () {
        "use strict";

        const departmentSearch = document.getElementById("departmentSearch");
        const departmentStatusFilter = document.getElementById("departmentStatusFilter");
        const departmentNoRecords = document.getElementById("departmentNoRecords");
        const visibleDepartmentCount = document.getElementById("visibleDepartmentCount");
        const rows = Array.prototype.slice.call(document.querySelectorAll(".department-row"));

        function normalizeText(value) {
            if (!value) return "";
            return value.toString().replace(/\s+/g, " ").trim().toLowerCase();
        }

        function applyDepartmentFilters() {
            const searchValue = normalizeText(departmentSearch ? departmentSearch.value : "");
            const selectedStatus = departmentStatusFilter ? departmentStatusFilter.value : "ALL";

            let visibleCount = 0;

            rows.forEach(function (row) {
                const rowSearch = normalizeText(row.getAttribute("data-search"));
                const rowStatus = row.getAttribute("data-status") || "";

                const matchesSearch = searchValue === "" || rowSearch.indexOf(searchValue) !== -1;
                const matchesStatus = selectedStatus === "ALL" || rowStatus === selectedStatus;

                if (matchesSearch && matchesStatus) {
                    row.style.display = "";
                    visibleCount++;
                } else {
                    row.style.display = "none";
                }
            });

            if (departmentNoRecords) {
                departmentNoRecords.style.display = visibleCount === 0 && rows.length > 0 ? "block" : "none";
            }

            if (visibleDepartmentCount) {
                visibleDepartmentCount.textContent = visibleCount;
            }
        }

        if (departmentSearch) {
            departmentSearch.addEventListener("input", applyDepartmentFilters);
        }

        if (departmentStatusFilter) {
            departmentStatusFilter.addEventListener("change", applyDepartmentFilters);
        }

        const resetButton = document.getElementById("resetDepartmentFilters");
        if (resetButton) {
            resetButton.addEventListener("click", function () {
                if (departmentSearch) departmentSearch.value = "";
                if (departmentStatusFilter) departmentStatusFilter.value = "ALL";
                applyDepartmentFilters();
            });
        }

        // Expose to window for inline onclick handler from KPI cards
        window.applyDepartmentFilters = applyDepartmentFilters;

        applyDepartmentFilters();
    })();

    var sortDirections = [true, true, true, true, true, true, true];
    function sortTable(columnIndex) {
        var table = document.getElementById("departmentTable");
        if (!table) return;
        
        var tbody = table.querySelector("tbody");
        if (!tbody) return;
        
        var rows = Array.from(tbody.querySelectorAll("tr.department-row"));
        if (rows.length === 0) return;

        var asc = sortDirections[columnIndex];
        sortDirections[columnIndex] = !asc;

        rows.sort(function(a, b) {
            var cellA = a.querySelectorAll("td")[columnIndex];
            var cellB = b.querySelectorAll("td")[columnIndex];

            if (!cellA || !cellB) return 0;
            
            var valA = (cellA.innerText || cellA.textContent || "").trim().toLowerCase();
            var valB = (cellB.innerText || cellB.textContent || "").trim().toLowerCase();
            
            // Numeric sorting for assets & employees
            if (columnIndex === 4 || columnIndex === 5) {
                var numA = parseInt(valA.replace(/[^0-9]/g, "")) || 0;
                var numB = parseInt(valB.replace(/[^0-9]/g, "")) || 0;
                return asc ? (numA - numB) : (numB - numA);
            }

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
                icon.style.color = "#cbd5e1";
                if (idx === columnIndex) {
                    icon.className = asc ? "fa-solid fa-sort-up" : "fa-solid fa-sort-down";
                    icon.style.color = "#082f73";
                }
            }
        });
    }
</script>

<script src="<%= contextPath %>/js/topbar-search.js?v=28000"></script>
<script src="<%= contextPath %>/js/user-dropdown.js?v=28000"></script>
<script src="<%= contextPath %>/js/sidebar-role.js?v=28000"></script>
<script src="<%= contextPath %>/js/ir-body-watermark.js?v=28000"></script>
<script src="<%= contextPath %>/js/dashboard-actions.js?v=28000"></script>

</body>
</html>
