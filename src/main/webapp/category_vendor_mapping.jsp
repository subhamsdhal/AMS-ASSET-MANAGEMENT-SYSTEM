<%@page contentType="text/html" pageEncoding="UTF-8"%>
<%@page import="com.mycompany.asset_management_system_ams.Category"%>
<%@page import="com.mycompany.asset_management_system_ams.CategoryDAO"%>
<%@page import="com.mycompany.asset_management_system_ams.Vendor"%>
<%@page import="com.mycompany.asset_management_system_ams.VendorDAO"%>
<%@page import="com.mycompany.asset_management_system_ams.CategoryVendorMapping"%>
<%@page import="com.mycompany.asset_management_system_ams.CategoryVendorMappingDAO"%>
<%@page import="java.util.List"%>
<%@page import="java.util.Locale"%>

<%!
    private String safe(Object value) {
        if (value == null) {
            return "";
        }

        return value.toString()
                .replace("&", "&amp;")
                .replace("<", "&lt;")
                .replace(">", "&gt;")
                .replace("\"", "&quot;")
                .replace("'", "&#39;");
    }

    private String cleanLabel(String value) {
        if (value == null || value.trim().isEmpty()) {
            return "N/A";
        }

        String text = value.trim().replace("_", " ").toLowerCase(Locale.ENGLISH);
        String[] parts = text.split("\\s+");
        StringBuilder out = new StringBuilder();

        for (String part : parts) {
            if (part.length() > 0) {
                out.append(Character.toUpperCase(part.charAt(0))).append(part.substring(1)).append(" ");
            }
        }

        return out.toString().trim();
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

    boolean canManageMapping = ("SUPER_ADMIN".equals(role) || "ADMIN".equals(role))
            || "ASSET_MANAGER".equalsIgnoreCase(role);

    boolean canExportMappingReport = ("SUPER_ADMIN".equals(role) || "ADMIN".equals(role))
            || "ASSET_MANAGER".equalsIgnoreCase(role)
            || "AUDITOR".equalsIgnoreCase(role);

    CategoryDAO categoryDAO = new CategoryDAO();
    VendorDAO vendorDAO = new VendorDAO();
    CategoryVendorMappingDAO mappingDAO = new CategoryVendorMappingDAO();

    List<Category> categoryList = categoryDAO.getActiveCategories();
    List<Vendor> vendorList = vendorDAO.getActiveVendors();
    List<CategoryVendorMapping> mappingList = mappingDAO.getAllMappings();

    String msg = request.getParameter("msg");
    String error = request.getParameter("error");
    String access = request.getParameter("access");

    int activeMappings = 0;
    int inactiveMappings = 0;
    int mappingsWithAssets = 0;

    for (CategoryVendorMapping mapping : mappingList) {
        if ("ACTIVE".equals(mapping.getStatus())) {
            activeMappings++;
        } else {
            inactiveMappings++;
        }

        if (mapping.getLinkedAssetCount() > 0) {
            mappingsWithAssets++;
        }
    }

    String userInitial = username.substring(0, Math.min(2, username.length())).toUpperCase(Locale.ENGLISH);
%>

<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>Category Supplier Mapping - IR-AMS</title>

    <link rel="stylesheet"
          href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.0/css/all.min.css">

    <link rel="stylesheet" href="css/ir-glass.css?v=28000">
    <link rel="stylesheet" href="css/ams-pro.css?v=28000">
    <link rel="stylesheet" href="css/ir-ams-railway-ui.css?v=28000">
<link rel="stylesheet" href="css/category_vendor_mapping.css?v=pagerow3">
</head>

<body class="railway-ui">
<div class="app ams-shell">

    
    <jsp:include page="sidebar.jsp" />

    <main class="main railway-main">
        
        <jsp:include page="topbar.jsp" />

        <div class="main-scroll-content mapping-board">

            <section class="mapping-hero">
                <h1>Category Supplier Mapping Console</h1>

                <p>
                    Control which suppliers are approved for each asset category. This mapping powers
                    the Add Asset and Edit Asset supplier dropdowns.
                </p>

                <div class="hero-pills">
                    <div class="hero-pill"><i class="fa-solid fa-layer-group"></i> Category Control</div>
                    <div class="hero-pill"><i class="fa-solid fa-truck-field"></i> Supplier Control</div>
                    <div class="hero-pill"><i class="fa-solid fa-diagram-project"></i> Dropdown Mapping</div>
                    <div class="hero-pill"><i class="fa-solid fa-shield-halved"></i> Admin Controlled</div>
                </div>
            </section>

            <% if ("denied".equals(access)) { %>
                <div class="page-error">
                    <i class="fa-solid fa-triangle-exclamation"></i>
                    Access denied. You do not have permission to manage category-supplier mapping.
                </div>
            <% } %>

            <section class="kpi-grid">

                <div class="kpi-card">
                    <div class="kpi-icon">
                        <i class="fa-solid fa-diagram-project"></i>
                    </div>
                    <h3>Total Mappings</h3>
                    <p><%= mappingList.size() %></p>
                </div>

                <div class="kpi-card">
                    <div class="kpi-icon">
                        <i class="fa-solid fa-circle-check"></i>
                    </div>
                    <h3>Active</h3>
                    <p><%= activeMappings %></p>
                </div>

                <div class="kpi-card">
                    <div class="kpi-icon">
                        <i class="fa-solid fa-ban"></i>
                    </div>
                    <h3>Inactive</h3>
                    <p><%= inactiveMappings %></p>
                </div>

                <div class="kpi-card">
                    <div class="kpi-icon">
                        <i class="fa-solid fa-boxes-stacked"></i>
                    </div>
                    <h3>Used Mappings</h3>
                    <p><%= mappingsWithAssets %></p>
                </div>

                <div class="kpi-card">
                    <div class="kpi-icon">
                        <i class="fa-solid fa-layer-group"></i>
                    </div>
                    <h3>Active Categories</h3>
                    <p><%= categoryList.size() %></p>
                </div>

                <div class="kpi-card">
                    <div class="kpi-icon">
                        <i class="fa-solid fa-truck"></i>
                    </div>
                    <h3>Total Suppliers</h3>
                    <p><%= vendorList.size() %></p>
                </div>

            </section>

            <%
                if ("mapped".equals(msg)) {
            %>
                <div class="page-success">
                    <i class="fa-solid fa-circle-check"></i>
                    Supplier mapped with category successfully.
                </div>
            <%
                } else if ("reactivated".equals(msg)) {
            %>
                <div class="page-success">
                    <i class="fa-solid fa-circle-check"></i>
                    Mapping reactivated successfully.
                </div>
            <%
                } else if ("duplicate".equals(msg)) {
            %>
                <div class="page-error" style="background-color: #fff3cd; color: #856404; border-left-color: #ffeeba;">
                    <i class="fa-solid fa-circle-info"></i>
                    This category and supplier are already mapped.
                </div>
            <%
                } else if ("enabled".equals(msg)) {
            %>
                <div class="page-success">
                    <i class="fa-solid fa-circle-check"></i>
                    Mapping activated successfully.
                </div>
            <%
                } else if ("disabled".equals(msg)) {
            %>
                <div class="page-success">
                    <i class="fa-solid fa-circle-check"></i>
                    Mapping deactivated successfully.
                </div>
            <%
                }
            %>

            <%
                if ("invalid".equals(error)) {
            %>
                <div class="page-error">
                    <i class="fa-solid fa-triangle-exclamation"></i>
                    Invalid mapping request. Please select both category and supplier.
                </div>
            <%
                } else if ("failed".equals(error)) {
            %>
                <div class="page-error">
                    <i class="fa-solid fa-triangle-exclamation"></i>
                    Mapping action failed. Please try again.
                </div>
            <%
                } else if ("server".equals(error)) {
            %>
                <div class="page-error">
                    <i class="fa-solid fa-triangle-exclamation"></i>
                    Server error occurred while processing mapping request.
                </div>
            <%
                }
            %>

            <% if (canManageMapping) { %>
                <section class="glass-panel">
                    <div class="registry-toolbar">
                        <div>
                            <h2>Create / Reactivate Mapping</h2>
                            <p class="table-subtext">
                                Select one asset category and one supplier to approve that supplier for future asset entry.
                            </p>
                        </div>
                    </div>

                    <form action="AddCategoryVendorMappingServlet" method="post">
                        <div class="mapping-form-grid">

                            <div class="form-group">
                                <label>Category</label>

                                <select name="categoryId" required>
                                    <option value="" disabled selected hidden>Select Category</option>

                                    <%
                                        for (Category category : categoryList) {
                                    %>
                                        <option value="<%= category.getCategoryId() %>">
                                            <%= safe(category.getCategoryName()) %>
                                        </option>
                                    <%
                                        }
                                    %>
                                </select>
                            </div>

                            <div class="form-group">
                                <label>Supplier</label>

                                <select name="vendorId" required>
                                    <option value="" disabled selected hidden>Select Supplier</option>

                                    <%
                                        for (Vendor vendor : vendorList) {
                                    %>
                                        <option value="<%= vendor.getVendorId() %>">
                                            <%= safe(vendor.getVendorName()) %>
                                        </option>
                                    <%
                                        }
                                    %>
                                </select>
                            </div>

                            <div class="form-group">
                                <button type="submit" class="btn primary" id="mapSubmitBtn">
                                    <i class="fa-solid fa-link"></i>
                                    Map Supplier
                                </button>
                            </div>

                        </div>
                    </form>
                </section>
                <script>
                    document.querySelector('form[action="AddCategoryVendorMappingServlet"]').addEventListener('submit', function(e) {
                        const btn = document.getElementById('mapSubmitBtn');
                        if (btn.disabled) {
                            e.preventDefault();
                            return;
                        }
                        btn.disabled = true;
                        btn.innerHTML = '<i class="fa-solid fa-spinner fa-spin"></i> Processing...';
                        setTimeout(() => { btn.disabled = false; btn.innerHTML = '<i class="fa-solid fa-link"></i> Map Supplier'; }, 3000);
                    });
                </script>
            <% } %>

            <section class="glass-panel">

                <div class="registry-toolbar">

                    <div>
                        <h2>Mapping Control Table</h2>
                        <p class="table-subtext">
                            Showing <%= mappingList.size() %> category-supplier mapping records.
                        </p>
                    </div>

                    <div class="registry-actions">
                    </div>

                </div>

                <div class="registry-filter-grid mapping-filter-grid <%= canExportMappingReport ? "has-export" : "no-export" %>">

                    <div class="registry-search">
                        <i class="fa-solid fa-magnifying-glass"></i>
                        <input type="text"
                               id="mappingSearch"
                               placeholder="Search category, supplier, mapping status...">
                    </div>

                    <select id="mappingStatusFilter" class="status-filter-select">
                        <option value="ALL">All Mappings</option>
                        <option value="ACTIVE">Active</option>
                        <option value="INACTIVE">Inactive</option>
                    </select>

                    <div class="page-size-selector">
                        <label for="pageSizeSelect">Show
                            <select id="pageSizeSelect" onchange="changePageSize()">
                                <option value="10">10</option>
                                <option value="25" selected>25</option>
                                <option value="50">50</option>
                                <option value="100">100</option>
                                <option value="ALL">All</option>
                            </select>
                            entries
                        </label>
                    </div>

                    <% if (canExportMappingReport) { %>
                        <a href="export_category_vendor_mapping_report.jsp" class="btn mapping-export-btn">
                            <i class="fa-solid fa-file-excel"></i>
                            Export Excel
                        </a>
                    <% } %>

                    <button type="button" class="btn" onclick="resetMappingFilters()">
                        <i class="fa-solid fa-filter-circle-xmark"></i>
                        Reset Filters
                    </button>

                </div>

                <div class="pagination-controls" id="paginationControls">
                    <!-- controls rendered via JS -->
                </div>

                <div class="registry-table-wrap">

                    <table class="mapping-table" id="mappingTable">
                        <thead>
                            <tr>
                                <th onclick="sortTable(0)" style="cursor: pointer;" title="Click to sort">Mapping ID <i class="fa-solid fa-sort" style="color: #cbd5e1; margin-left: 4px;"></i></th>
                                <th onclick="sortTable(1)" style="cursor: pointer;" title="Click to sort">Category <i class="fa-solid fa-sort" style="color: #cbd5e1; margin-left: 4px;"></i></th>
                                <th onclick="sortTable(2)" style="cursor: pointer;" title="Click to sort">Supplier <i class="fa-solid fa-sort" style="color: #cbd5e1; margin-left: 4px;"></i></th>
                                <th onclick="sortTable(3)" style="cursor: pointer;" title="Click to sort">Status <i class="fa-solid fa-sort" style="color: #cbd5e1; margin-left: 4px;"></i></th>
                                <th onclick="sortTable(4)" style="cursor: pointer;" title="Click to sort">Linked Assets <i class="fa-solid fa-sort" style="color: #cbd5e1; margin-left: 4px;"></i></th>
                                <th onclick="sortTable(5)" style="cursor: pointer;" title="Click to sort">Created At <i class="fa-solid fa-sort" style="color: #cbd5e1; margin-left: 4px;"></i></th>
                                <th>Control Actions</th>
                            </tr>
                        </thead>

                        <tbody>
                            <%
                                for (CategoryVendorMapping mapping : mappingList) {
                                    String mappingStatus = mapping.getStatus() == null
                                            ? "INACTIVE"
                                            : mapping.getStatus();
                            %>
                                <tr>
                                    <td>
                                        <span class="mapping-id-pill">
                                            MAP-<%= mapping.getMappingId() %>
                                        </span>
                                    </td>

                                    <td>
                                        <strong><%= safe(mapping.getCategoryName()) %></strong>
                                        <br>
                                        <span class="table-subtext">Asset category</span>
                                    </td>

                                    <td>
                                        <strong><%= safe(mapping.getVendorName()) %></strong>
                                        <br>
                                        <span class="table-subtext">Approved supplier</span>
                                    </td>

                                    <td>
                                        <% if ("ACTIVE".equals(mappingStatus)) { %>
                                            <span class="mapping-status-active" data-status="ACTIVE">
                                                <i class="fa-solid fa-circle-check"></i>
                                                Active
                                            </span>
                                        <% } else { %>
                                            <span class="mapping-status-inactive" data-status="INACTIVE">
                                                <i class="fa-solid fa-ban"></i>
                                                Inactive
                                            </span>
                                        <% } %>
                                    </td>

                                    <td>
                                        <span class="mapping-count-pill">
                                            <i class="fa-solid fa-boxes-stacked"></i>
                                            <%= mapping.getLinkedAssetCount() %> Assets
                                        </span>
                                    </td>

                                    <td>
                                        <%= mapping.getCreatedAt() == null ? "-" : safe(mapping.getCreatedAt()) %>
                                    </td>

                                    <td class="action-cell">
                                        <% if (canManageMapping) { %>
                                            <button type="button" 
                                                    class="mapping-action-btn <%= "ACTIVE".equals(mappingStatus) ? "deactivate" : "activate" %>"
                                                    onclick="toggleMappingStatus(this, <%= mapping.getMappingId() %>, '<%= "ACTIVE".equals(mappingStatus) ? "disable" : "enable" %>')"
                                                    title="<%= "ACTIVE".equals(mappingStatus) ? "Deactivate this mapping" : "Activate this mapping" %>">
                                                <i class="fa-solid <%= "ACTIVE".equals(mappingStatus) ? "fa-ban" : "fa-circle-check" %>"></i> 
                                                <span><%= "ACTIVE".equals(mappingStatus) ? "Deactivate" : "Activate" %></span>
                                            </button>
                                        <% } else { %>
                                            <span class="mapping-action-btn">
                                                <i class="fa-solid fa-lock"></i>
                                                View Only
                                            </span>
                                        <% } %>
                                    </td>
                                </tr>
                            <%
                                }
                            %>
                        </tbody>
                    </table>

                    <div id="mappingNoRecords" class="no-records-message" style="display:none;">
                        <i class="fa-solid fa-circle-info"></i>
                        <strong>No matching mapping records found.</strong>
                        Try changing search keyword or status filter.
                    </div>

                </div>

            </section>

        </div>
    </main>

</div>

<script>
    const mappingSearch = document.getElementById("mappingSearch");
    const mappingStatusFilter = document.getElementById("mappingStatusFilter");
    const tableRows = Array.from(document.querySelectorAll("#mappingTable tbody tr"));
    const mappingNoRecords = document.getElementById("mappingNoRecords");
    
    let currentPage = 1;
    let itemsPerPage = 25;
    let filteredRows = [];

    function normalizeText(text) {
        return text.toLowerCase().replace(/\s+/g, " ").trim();
    }

    function applyMappingFilters() {
        if (!mappingSearch || !mappingStatusFilter) return;
        
        const keyword = normalizeText(mappingSearch.value);
        const selectedStatus = mappingStatusFilter.value;

        filteredRows = [];

        tableRows.forEach(row => {
            if (row.querySelector(".no-records-message")) return;

            const rowText = normalizeText(row.textContent);
            
            const activeStatus = row.querySelector(".mapping-status-active");
            const inactiveStatus = row.querySelector(".mapping-status-inactive");
            let rowStatus = "";
            if (activeStatus) rowStatus = activeStatus.getAttribute("data-status");
            else if (inactiveStatus) rowStatus = inactiveStatus.getAttribute("data-status");

            const matchesSearch = keyword === "" || rowText.indexOf(keyword) !== -1;
            const matchesStatus = selectedStatus === "ALL" || rowStatus === selectedStatus;

            if (matchesSearch && matchesStatus) {
                filteredRows.push(row);
            } else {
                row.style.display = "none";
            }
        });

        currentPage = 1;
        renderPagination();
    }

    function renderPagination() {
        const totalItems = filteredRows.length;
        const totalPages = itemsPerPage === "ALL" ? 1 : Math.ceil(totalItems / itemsPerPage);
        
        tableRows.forEach(r => r.style.display = "none");
        
        if (totalItems === 0) {
            if (mappingNoRecords) mappingNoRecords.style.display = "block";
            document.getElementById("paginationControls").innerHTML = "";
            return;
        } else {
            if (mappingNoRecords) mappingNoRecords.style.display = "none";
        }
        
        const startIdx = itemsPerPage === "ALL" ? 0 : (currentPage - 1) * itemsPerPage;
        const endIdx = itemsPerPage === "ALL" ? totalItems : Math.min(startIdx + itemsPerPage, totalItems);
        
        for (let i = startIdx; i < endIdx; i++) {
            filteredRows[i].style.display = "";
        }
        
        renderPaginationButtons(totalPages);
    }
    
    function renderPaginationButtons(totalPages) {
        const controls = document.getElementById("paginationControls");
        if (!controls) return;
        
        if (totalPages <= 1) {
            controls.innerHTML = "";
            return;
        }
        
        // Fault: this whole page 500'd on every load. Jasper's JSP compiler scans
        // template text (including inside script blocks) for dollar-brace sequences
        // and tries to parse them as JSP EL - it doesn't know these are JavaScript
        // template-literal interpolations, not EL expressions. A triple-equals
        // comparison plus a ternary isn't valid EL grammar, so the JSP failed to even
        // COMPILE (a JasperException, not a runtime error) - every visit to this page
        // failed before this fix, regardless of data or role. Fixed by escaping the
        // dollar sign so Jasper treats these as literal template text; the browser's
        // real JS engine still sees the interpolation syntax it expects (the escape
        // backslash is stripped by Jasper before the response is ever sent, so it
        // never reaches the client).
        let html = `<button class="btn" onclick="goToPage(1)" \${currentPage === 1 ? 'disabled' : ''}>&laquo;</button>`;
        html += `<button class="btn" onclick="goToPage(\${currentPage - 1})" \${currentPage === 1 ? 'disabled' : ''}>&lsaquo;</button>`;

        html += `<span style="padding: 5px 10px;">Page \${currentPage} of \${totalPages}</span>`;

        html += `<button class="btn" onclick="goToPage(\${currentPage + 1})" \${currentPage === totalPages ? 'disabled' : ''}>&rsaquo;</button>`;
        html += `<button class="btn" onclick="goToPage(\${totalPages})" \${currentPage === totalPages ? 'disabled' : ''}>&raquo;</button>`;
        
        controls.innerHTML = html;
    }
    
    function goToPage(page) {
        currentPage = page;
        renderPagination();
    }
    
    function changePageSize() {
        const select = document.getElementById("pageSizeSelect");
        if (select.value === "ALL") {
            itemsPerPage = "ALL";
        } else {
            itemsPerPage = parseInt(select.value);
        }
        currentPage = 1;
        renderPagination();
    }

    function resetMappingFilters() {
        if (mappingStatusFilter) mappingStatusFilter.value = "ALL";
        if (mappingSearch) mappingSearch.value = "";
        applyMappingFilters();
    }

    if (mappingSearch) mappingSearch.addEventListener("input", applyMappingFilters);
    if (mappingStatusFilter) mappingStatusFilter.addEventListener("change", applyMappingFilters);

    applyMappingFilters();

    var sortDirections = [true, true, true, true, true, true, true];
    function sortTable(columnIndex) {
        var table = document.getElementById("mappingTable");
        if (!table) return;
        
        var tbody = table.querySelector("tbody");
        if (!tbody) return;

        if (filteredRows.length <= 1) return;

        var asc = sortDirections[columnIndex];
        sortDirections[columnIndex] = !asc;

        filteredRows.sort(function(a, b) {
            var cellA = a.querySelectorAll("td")[columnIndex];
            var cellB = b.querySelectorAll("td")[columnIndex];

            if (!cellA || !cellB) return 0;
            
            var valA = cellA.innerText || cellA.textContent;
            var valB = cellB.innerText || cellB.textContent;
            
            valA = valA.trim().toLowerCase();
            valB = valB.trim().toLowerCase();
            
            // Check for numeric columns (Mapping ID, Linked Assets)
            const numA = parseFloat(valA.replace(/[^0-9.-]+/g,""));
            const numB = parseFloat(valB.replace(/[^0-9.-]+/g,""));
            
            if (!isNaN(numA) && !isNaN(numB) && (columnIndex === 0 || columnIndex === 4)) {
                if (numA < numB) return asc ? -1 : 1;
                if (numA > numB) return asc ? 1 : -1;
                return 0;
            }
            
            if (valA < valB) return asc ? -1 : 1;
            if (valA > valB) return asc ? 1 : -1;
            return 0;
        });
        
        // Re-append sorted elements to DOM
        filteredRows.forEach(function(row) {
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
        
        renderPagination();
    }

    function toggleMappingStatus(btn, mappingId, action) {
        const msg = action === 'disable' 
            ? 'Deactivate this mapping? Existing assets will remain linked, but this supplier will stop showing for new assets in this category.' 
            : 'Activate this mapping again?';
            
        if (!confirm(msg)) return;
        
        const originalHtml = btn.innerHTML;
        btn.innerHTML = '<i class="fa-solid fa-spinner fa-spin"></i> Processing...';
        btn.disabled = true;
        
        fetch('CategoryVendorMappingAjaxServlet', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/x-www-form-urlencoded',
            },
            body: 'mappingId=' + encodeURIComponent(mappingId) + '&action=' + encodeURIComponent(action)
        })
        .then(response => response.json())
        .then(data => {
            if (data.success) {
                const tr = btn.closest('tr');
                const statusCell = tr.querySelectorAll('td')[3];
                
                if (action === 'disable') {
                    statusCell.innerHTML = '<span class="mapping-status-inactive" data-status="INACTIVE"><i class="fa-solid fa-ban"></i> Inactive</span>';
                    btn.className = 'mapping-action-btn activate';
                    btn.onclick = function() { toggleMappingStatus(btn, mappingId, 'enable'); };
                    btn.title = 'Activate this mapping';
                    btn.innerHTML = '<i class="fa-solid fa-circle-check"></i> <span>Activate</span>';
                } else {
                    statusCell.innerHTML = '<span class="mapping-status-active" data-status="ACTIVE"><i class="fa-solid fa-circle-check"></i> Active</span>';
                    btn.className = 'mapping-action-btn deactivate';
                    btn.onclick = function() { toggleMappingStatus(btn, mappingId, 'disable'); };
                    btn.title = 'Deactivate this mapping';
                    btn.innerHTML = '<i class="fa-solid fa-ban"></i> <span>Deactivate</span>';
                }
                
                // Re-apply filters in case they are hiding inactive entries
                applyMappingFilters();
            } else {
                alert('Error: ' + (data.error || 'Failed to update status.'));
                btn.innerHTML = originalHtml;
            }
        })
        .catch(error => {
            console.error('Error:', error);
            alert('A network error occurred. Please try again.');
            btn.innerHTML = originalHtml;
        })
        .finally(() => {
            btn.disabled = false;
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