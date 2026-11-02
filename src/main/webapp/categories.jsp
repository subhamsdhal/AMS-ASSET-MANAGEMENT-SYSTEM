<%@page contentType="text/html" pageEncoding="UTF-8"%>
<%@page import="com.mycompany.asset_management_system_ams.Category"%>
<%@page import="com.mycompany.asset_management_system_ams.CategoryDAO"%>
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
    
    private String safeText(String value) {
        if (value == null || value.trim().isEmpty()) {
            return "-";
        }
        return value.trim()
                .replace("&", "&amp;")
                .replace("<", "&lt;")
                .replace(">", "&gt;")
                .replace("\"", "&quot;")
                .replace("'", "&#39;");
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

    boolean canManageCategories = ("SUPER_ADMIN".equals(role) || "ADMIN".equals(role))
            || "ASSET_MANAGER".equals(role);

    boolean canExportCategories = canManageCategories
            || "AUDITOR".equals(role);

    CategoryDAO dao = new CategoryDAO();
    List<Category> categoryList = dao.getAllCategories();

    String msg = request.getParameter("msg");
    String error = request.getParameter("error");

    int activeCategories = 0;
    int inactiveCategories = 0;
    int totalMappedAssets = 0;
    int totalCategoryRequests = 0;

    for (Category category : categoryList) {
        if ("YES".equals(category.getIsActive())) {
            activeCategories++;
        } else {
            inactiveCategories++;
        }

        totalMappedAssets += category.getAssetCount();
        totalCategoryRequests += category.getRequestCount();
    }
%>

<!DOCTYPE html>
<html>
<head>
    <title>IR-AMS Categories</title>

    <link rel="stylesheet"
          href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.0/css/all.min.css">

    <link rel="stylesheet" href="css/ir-glass.css?v=final-reference-1">
    <link rel="stylesheet" href="css/ams-pro.css?v=final-reference-1">
    <link rel="stylesheet" href="css/ir-ams-railway-ui.css?v=final-reference-1">
<link rel="stylesheet" href="css/categories.css?v=topbarfix1">
        </head>

<body class="railway-ui">

<div class="app ams-shell">

    
    <jsp:include page="sidebar.jsp" />

    <main class="main railway-main">
        <jsp:include page="topbar.jsp" />

        <div class="main-scroll-content">

            <section class="asset-hero">
                <h1>Category Management Console</h1>

                <p>
                    Manage railway asset categories such as laptops, printers, networking devices,
                    furniture and operational equipment with mapped asset and request visibility.
                </p>

                <br>

                <div class="hero-pills">
                    <div class="hero-pill">
                        <i class="fa-solid fa-layer-group"></i> Category Registry
                    </div>

                    <div class="hero-pill">
                        <i class="fa-solid fa-boxes-stacked"></i> Asset Mapping
                    </div>

                    <div class="hero-pill">
                        <i class="fa-solid fa-file-circle-plus"></i> Request Demand
                    </div>

                    <div class="hero-pill">
                        <i class="fa-solid fa-shield-halved"></i> Admin Controlled
                    </div>
                </div>
            </section>

            <% if ("denied".equals(request.getParameter("access"))) { %>
                <div class="page-error">
                    <i class="fa-solid fa-triangle-exclamation"></i>
                    Access denied. You do not have permission to manage categories.
                </div>
            <% } %>

            <section class="kpi-grid">

                <div class="kpi-card">
                    <div class="kpi-icon purple">
                        <i class="fa-solid fa-layer-group"></i>
                    </div>
                    <h3 class="kpi-title">Total Categories</h3>
                    <div class="kpi-value"><%= formatNumber(categoryList.size()) %></div>
                </div>

                <div class="kpi-card">
                    <div class="kpi-icon green">
                        <i class="fa-solid fa-circle-check"></i>
                    </div>
                    <h3 class="kpi-title">Active</h3>
                    <div class="kpi-value"><%= formatNumber(activeCategories) %></div>
                </div>

                <div class="kpi-card">
                    <div class="kpi-icon red">
                        <i class="fa-solid fa-ban"></i>
                    </div>
                    <h3 class="kpi-title">Inactive</h3>
                    <div class="kpi-value"><%= formatNumber(inactiveCategories) %></div>
                </div>

                <div class="kpi-card">
                    <div class="kpi-icon orange">
                        <i class="fa-solid fa-boxes-stacked"></i>
                    </div>
                    <h3 class="kpi-title">Mapped Assets</h3>
                    <div class="kpi-value"><%= formatNumber(totalMappedAssets) %></div>
                </div>

                <div class="kpi-card">
                    <div class="kpi-icon blue">
                        <i class="fa-solid fa-file-circle-plus"></i>
                    </div>
                    <h3 class="kpi-title">Pending Requests</h3>
                    <div class="kpi-value"><%= formatNumber(totalCategoryRequests) %></div>
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
                    Category added successfully.
                </div>
            <%
                } else if ("updated".equals(msg)) {
            %>
                <div class="page-success">
                    <i class="fa-solid fa-circle-check"></i>
                    Category updated successfully.
                </div>
            <%
                } else if ("enabled".equals(msg)) {
            %>
                <div class="page-success">
                    <i class="fa-solid fa-circle-check"></i>
                    Category enabled successfully.
                </div>
            <%
                } else if ("disabled".equals(msg)) {
            %>
                <div class="page-success">
                    <i class="fa-solid fa-circle-check"></i>
                    Category disabled successfully.
                </div>
            <%
                }
            %>

            <%
                if ("failed".equals(error)) {
            %>
                <div class="page-error">
                    <i class="fa-solid fa-triangle-exclamation"></i>
                    Category action failed. Please try again.
                </div>
            <%
                } else if ("server".equals(error)) {
            %>
                <div class="page-error">
                    <i class="fa-solid fa-triangle-exclamation"></i>
                    Server error occurred while processing category request.
                </div>
            <%
                }
            %>

            <section class="glass-panel">

                <div class="registry-toolbar">

                    <div>
                        <h2>Category Control Table</h2>
                        <p class="table-subtext">
                            Showing <%= categoryList.size() %> live category records with asset and request counts.
                        </p>
                    </div>

                    <div class="registry-actions">

                        <% if (canManageCategories) { %>
                            <a href="add_category.jsp" class="btn primary">
                                <i class="fa-solid fa-plus"></i>
                                Add Category
                            </a>
                        <% } %>

                        <% if (canExportCategories) { %>
                            <a href="export_categories_report.jsp" class="btn green category-export-btn">
                                <i class="fa-solid fa-file-excel"></i>
                                Export Excel
                            </a>
                        <% } %>

                    </div>

                </div>

                <div class="registry-filter-grid">

                    <div class="registry-search">
                        <i class="fa-solid fa-magnifying-glass"></i>
                        <input type="text"
                               id="categorySearch"
                               placeholder="Search category id, name, description, status...">
                    </div>

                    <select id="categoryStatusFilter" class="status-filter-select">
                        <option value="ALL">All Categories</option>
                        <option value="YES">Active</option>
                        <option value="NO">Inactive</option>
                    </select>

                    <button type="button" class="btn" onclick="resetCategoryFilters()">
                        <i class="fa-solid fa-filter-circle-xmark"></i> Reset Filters
                    </button>

                </div>

                <div class="registry-table-wrap">

                    <table class="asset-table" id="categoryTable">
                        <colgroup>
                            <col style="width: 8%;">
                            <col style="width: 15%;">
                            <col style="width: 22%;">
                            <col style="width: 9%;">
                            <col style="width: 11%;">
                            <col style="width: 10%;">
                            <col style="width: 11%;">
                            <col style="width: 14%;">
                        </colgroup>
                        <thead>
                            <tr>
                                <th onclick="sortTable(0)" style="cursor: pointer;" title="Click to sort">Category ID <i class="fa-solid fa-sort" style="color: #cbd5e1; margin-left: 4px;"></i></th>
                                <th onclick="sortTable(1)" style="cursor: pointer;" title="Click to sort">Category Details <i class="fa-solid fa-sort" style="color: #cbd5e1; margin-left: 4px;"></i></th>
                                <th onclick="sortTable(2)" style="cursor: pointer;" title="Click to sort">Description <i class="fa-solid fa-sort" style="color: #cbd5e1; margin-left: 4px;"></i></th>
                                <th onclick="sortTable(3)" style="cursor: pointer;" title="Click to sort">Status <i class="fa-solid fa-sort" style="color: #cbd5e1; margin-left: 4px;"></i></th>
                                <th onclick="sortTable(4)" style="cursor: pointer;" title="Click to sort">Mapped Assets <i class="fa-solid fa-sort" style="color: #cbd5e1; margin-left: 4px;"></i></th>
                                <th onclick="sortTable(5)" style="cursor: pointer;" title="Click to sort">Requests <i class="fa-solid fa-sort" style="color: #cbd5e1; margin-left: 4px;"></i></th>
                                <th onclick="sortTable(6)" style="cursor: pointer;" title="Click to sort">Created At <i class="fa-solid fa-sort" style="color: #cbd5e1; margin-left: 4px;"></i></th>
                                <th>Control Actions</th>
                            </tr>
                        </thead>

                        <tbody>

                            <%
                                for (Category category : categoryList) {
                                    String activeStatus = category.getIsActive() == null ? "NO" : category.getIsActive();
                            %>

                            <tr>
                                <td>
                                    <span class="category-id-pill">
                                        CAT-<%= category.getCategoryId() %>
                                    </span>
                                </td>

                                <td>
                                    <strong><%= safeText(category.getCategoryName()) %></strong>
                                    <br>
                                    <span class="table-subtext">
                                        Railway asset classification
                                    </span>
                                </td>

                                <td>
                                    <%= safeText(category.getDescription()) %>
                                </td>

                                <td>
                                    <% if ("YES".equals(activeStatus)) { %>
                                        <span class="category-active-pill" data-status="YES">
                                            <i class="fa-solid fa-circle-check"></i>
                                            Active
                                        </span>
                                    <% } else { %>
                                        <span class="category-inactive-pill" data-status="NO">
                                            <i class="fa-solid fa-ban"></i>
                                            Inactive
                                        </span>
                                    <% } %>
                                </td>

                                <td>
                                    <span class="category-count-pill">
                                        <i class="fa-solid fa-boxes-stacked"></i>
                                        <%= category.getAssetCount() %> Assets
                                    </span>
                                </td>

                                <td>
                                    <span class="category-request-pill">
                                        <i class="fa-solid fa-file-circle-plus"></i>
                                        <%= category.getRequestCount() %> <%= category.getRequestCount() == 1 ? "Request" : "Requests" %>
                                    </span>
                                </td>

                                <td>
                                    <%= category.getCreatedAt() == null ? "-" : category.getCreatedAt() %>
                                </td>

                                <td>
                                    <div class="asset-actions">

                                        <a href="view_category.jsp?id=<%= category.getCategoryId() %>"
                                           class="asset-action-btn inspect-btn" title="View category details">
                                            <i class="fa-solid fa-eye"></i> View
                                        </a>

                                        <% if (canManageCategories) { %>

                                            <a href="edit_category.jsp?id=<%= category.getCategoryId() %>"
                                               class="asset-action-btn custody-btn" title="Edit this category">
                                                <i class="fa-solid fa-pen-to-square"></i> Edit
                                            </a>

                                            <% if ("YES".equals(activeStatus)) { %>
                                                <form method="post" action="UpdateCategoryStatusServlet" style="display:inline;" onsubmit="return confirm('Disable this category? Existing assets will remain linked.');">
                                                    <input type="hidden" name="id" value="<%= category.getCategoryId() %>">
                                                    <input type="hidden" name="action" value="disable">
                                                    <button type="submit" class="asset-action-btn qr-btn" style="border:none; cursor:pointer;" title="Disable this category">
                                                        <i class="fa-solid fa-ban"></i> Disable
                                                    </button>
                                                </form>
                                            <% } else { %>
                                                <form method="post" action="UpdateCategoryStatusServlet" style="display:inline;" onsubmit="return confirm('Enable this category again?');">
                                                    <input type="hidden" name="id" value="<%= category.getCategoryId() %>">
                                                    <input type="hidden" name="action" value="enable">
                                                    <button type="submit" class="asset-action-btn custody-btn" style="border:none; cursor:pointer;" title="Enable this category">
                                                        <i class="fa-solid fa-circle-check"></i> Enable
                                                    </button>
                                                </form>
                                            <% } %>

                                        <% } %>

                                    </div>
                                </td>
                            </tr>

                            <%
                                }
                            %>

                        </tbody>
                    </table>

                    <div id="categoryNoRecords" class="no-records-message" style="display:none;">
                        <i class="fa-solid fa-circle-info"></i>
                        <strong>No matching category records found.</strong>
                        Try changing search keyword or status filter.
                    </div>

                </div>

            </section>

        </div>
    </main>

</div>
<script>
    const categorySearch = document.getElementById("categorySearch");
    const categoryStatusFilter = document.getElementById("categoryStatusFilter");
    const tableRows = document.querySelectorAll("#categoryTable tbody tr");
    const categoryNoRecords = document.getElementById("categoryNoRecords");

    function normalizeText(text) {
        return text.toLowerCase().replace(/\s+/g, " ").trim();
    }

    function applyCategoryFilters() {
        if (!categorySearch || !categoryStatusFilter) return;
        
        const keyword = normalizeText(categorySearch.value);
        const selectedStatus = categoryStatusFilter.value;

        let visibleCount = 0;

        tableRows.forEach(row => {
            const rowText = normalizeText(row.textContent);
            
            const activePill = row.querySelector(".category-active-pill");
            const inactivePill = row.querySelector(".category-inactive-pill");
            let rowStatus = "";
            if (activePill) rowStatus = activePill.getAttribute("data-status");
            else if (inactivePill) rowStatus = inactivePill.getAttribute("data-status");

            const matchesSearch = keyword === "" || rowText.indexOf(keyword) !== -1;
            const matchesStatus = selectedStatus === "ALL" || rowStatus === selectedStatus;

            if (matchesSearch && matchesStatus) {
                row.style.display = "";
                visibleCount++;
            } else {
                row.style.display = "none";
            }
        });

        if (categoryNoRecords) {
            categoryNoRecords.style.display = visibleCount === 0 ? "block" : "none";
        }
    }

    function resetCategoryFilters() {
        if (categoryStatusFilter) categoryStatusFilter.value = "ALL";
        if (categorySearch) categorySearch.value = "";
        applyCategoryFilters();
    }

    if (categorySearch) categorySearch.addEventListener("input", applyCategoryFilters);
    if (categoryStatusFilter) categoryStatusFilter.addEventListener("change", applyCategoryFilters);

    applyCategoryFilters();

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
        var table = document.getElementById("categoryTable");
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


<script src="js/topbar-search.js?v=final-reference-1"></script>
<script src="js/user-dropdown.js?v=final-reference-1"></script>
<script src="js/sidebar-role.js?v=final-reference-1"></script>
<script src="js/ir-body-watermark.js?v=final-reference-1"></script>
<script src="js/dashboard-actions.js?v=final-reference-1"></script>

</body>
</html>