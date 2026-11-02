<%@page contentType="text/html" pageEncoding="UTF-8"%>
<%@page import="com.mycompany.asset_management_system_ams.Vendor"%>
<%@page import="com.mycompany.asset_management_system_ams.VendorDAO"%>
<%@page import="java.util.List"%>
<%@page import="java.util.Locale"%>
<%@page import="java.math.BigDecimal"%>
<%@page import="java.text.DecimalFormat"%>

<%!
    private String safeText(Object value) {
        if (value == null || value.toString().trim().isEmpty()) {
            return "N/A";
        }

        return value.toString().trim()
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

    private String compactMoney(BigDecimal value) {
        if (value == null) {
            return "0";
        }

        double amount = value.doubleValue();
        DecimalFormat df = new DecimalFormat("0.#");

        if (amount >= 10000000) {
            return df.format(amount / 10000000.0) + "Cr";
        }

        if (amount >= 100000) {
            return df.format(amount / 100000.0) + "L";
        }

        if (amount >= 1000) {
            return df.format(amount / 1000.0) + "K";
        }

        return new DecimalFormat("#,##0").format(amount);
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

    boolean canManageSuppliers = ("SUPER_ADMIN".equals(role) || "ADMIN".equals(role))
            || "ASSET_MANAGER".equals(role);

    VendorDAO dao = new VendorDAO();
    List<Vendor> vendorList = dao.getAllVendors();

    String msg = request.getParameter("msg");
    String error = request.getParameter("error");
    String access = request.getParameter("access");

    int suppliersWithAssets = 0;
    int suppliersWithoutAssets = 0;
    int totalLinkedAssets = 0;
    BigDecimal totalProcurementValue = BigDecimal.ZERO;

    for (Vendor vendor : vendorList) {
        totalLinkedAssets += vendor.getAssetCount();

        if (vendor.getAssetCount() > 0) {
            suppliersWithAssets++;
        } else {
            suppliersWithoutAssets++;
        }

        if (vendor.getTotalPurchaseValue() != null) {
            totalProcurementValue = totalProcurementValue.add(vendor.getTotalPurchaseValue());
        }
    }

    DecimalFormat moneyFormat = new DecimalFormat("#,##0.00");
    String userInitial = username.substring(0, Math.min(2, username.length())).toUpperCase(Locale.ENGLISH);
%>

<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>Suppliers - IR-AMS</title>

    <link rel="stylesheet"
          href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.0/css/all.min.css">

    <link rel="stylesheet" href="css/ir-glass.css?v=final-reference-1">
    <link rel="stylesheet" href="css/ams-pro.css?v=final-reference-1">
    <link rel="stylesheet" href="css/ir-ams-railway-ui.css?v=final-reference-1">
<link rel="stylesheet" href="css/vendors.css?v=topbarfix1">
</head>

<body class="railway-ui">
<div class="app ams-shell">

    <jsp:include page="sidebar.jsp" />

    <main class="main railway-main">
        <jsp:include page="topbar.jsp" />
        <div class="main-scroll-content suppliers-board">

            <section class="supplier-hero">
                <h1>Supplier Management Console</h1>

                <p>
                    Maintain supplier records, contact details, category mapping, procurement value and
                    linked asset visibility for railway inventory and lifecycle control.
                </p>

                <div class="hero-pills">
                    <div class="hero-pill">
                        <i class="fa-solid fa-truck-field"></i> Supplier Registry
                    </div>

                    <div class="hero-pill">
                        <i class="fa-solid fa-boxes-stacked"></i> Asset Supply Mapping
                    </div>

                    <div class="hero-pill">
                        <i class="fa-solid fa-indian-rupee-sign"></i> Procurement Value
                    </div>

                    <div class="hero-pill">
                        <i class="fa-solid fa-shield-halved"></i> Admin Controlled
                    </div>
                </div>
            </section>

            <% if ("denied".equals(access)) { %>
                <div class="page-error">
                    <i class="fa-solid fa-triangle-exclamation"></i>
                    Access denied. You do not have permission to manage suppliers.
                </div>
            <% } %>

            <section class="kpi-grid">

                <div class="kpi-card">
                    <div class="kpi-icon">
                        <i class="fa-solid fa-truck-field"></i>
                    </div>
                    <h3>Total Suppliers</h3>
                    <p title="<%= vendorList.size() %>"><%= vendorList.size() %></p>
                </div>

                <div class="kpi-card">
                    <div class="kpi-icon">
                        <i class="fa-solid fa-link"></i>
                    </div>
                    <h3>Linked Suppliers</h3>
                    <p title="<%= suppliersWithAssets %>"><%= suppliersWithAssets %></p>
                </div>

                <div class="kpi-card">
                    <div class="kpi-icon">
                        <i class="fa-solid fa-boxes-stacked"></i>
                    </div>
                    <h3>Supplied Assets</h3>
                    <p title="<%= totalLinkedAssets %>"><%= totalLinkedAssets %></p>
                </div>

                <div class="kpi-card">
                    <div class="kpi-icon">
                        <i class="fa-solid fa-indian-rupee-sign"></i>
                    </div>
                    <h3>Procurement Value</h3>
                    <p title="&#8377;<%= moneyFormat.format(totalProcurementValue) %>">&#8377;<%= compactMoney(totalProcurementValue) %></p>
                </div>

                <div class="kpi-card">
                    <div class="kpi-icon">
                        <i class="fa-solid fa-unlink"></i>
                    </div>
                    <h3>Unlinked Suppliers</h3>
                    <p title="<%= suppliersWithoutAssets %>"><%= suppliersWithoutAssets %></p>
                </div>

                <div class="kpi-card">
                    <div class="kpi-icon">
                        <i class="fa-solid fa-database"></i>
                    </div>
                    <h3>Live Status</h3>
                    <p>ON</p>
                </div>

            </section>

            <%
                if ("added".equals(msg)) {
            %>
                <div class="page-success">
                    <i class="fa-solid fa-circle-check"></i>
                    Supplier added successfully.
                </div>
            <%
                } else if ("updated".equals(msg)) {
            %>
                <div class="page-success">
                    <i class="fa-solid fa-circle-check"></i>
                    Supplier updated successfully.
                </div>
            <%
                } else if ("deleted".equals(msg)) {
            %>
                <div class="page-success">
                    <i class="fa-solid fa-circle-check"></i>
                    Supplier deleted successfully.
                </div>
            <%
                } else if ("reactivated".equals(msg)) {
            %>
                <div class="page-success">
                    <i class="fa-solid fa-circle-check"></i>
                    Supplier reactivated successfully.
                </div>
            <%
                }
            %>

            <%
                if ("inuse".equals(error)) {
            %>
                <div class="page-error">
                    <i class="fa-solid fa-triangle-exclamation"></i>
                    Supplier cannot be deleted because assets are linked with this supplier.
                </div>
            <%
                } else if ("reactivatefailed".equals(error)) {
            %>
                <div class="page-error">
                    <i class="fa-solid fa-triangle-exclamation"></i>
                    Could not reactivate this supplier. Please try again.
                </div>
            <%
                } else if ("failed".equals(error)) {
            %>
                <div class="page-error">
                    <i class="fa-solid fa-triangle-exclamation"></i>
                    Supplier action failed. Please try again.
                </div>
            <%
                } else if ("server".equals(error)) {
            %>
                <div class="page-error">
                    <i class="fa-solid fa-triangle-exclamation"></i>
                    Server error occurred while processing supplier request.
                </div>
            <%
                }
            %>

            <section class="glass-panel">

                <div class="registry-toolbar">

                    <div>
                        <h2>Supplier Control Table</h2>
                        <p class="table-subtext">
                            Showing <%= vendorList.size() %> live supplier records with linked asset count.
                        </p>
                    </div>

                    <div class="registry-actions">

                        <% if (canManageSuppliers) { %>
                            <a href="add_vendor.jsp" class="btn primary">
                                <i class="fa-solid fa-plus"></i>
                                Add Supplier
                            </a>
                        <% } %>

                    </div>

                </div>

                <div class="registry-filter-grid supplier-filter-grid">

                    <div class="registry-search">
                        <i class="fa-solid fa-magnifying-glass"></i>
                        <input type="text"
                               id="supplierSearch"
                               placeholder="Search supplier name, contact person, email, phone, address...">
                    </div>

                    <select id="supplierLinkedFilter" class="status-filter-select">
                        <option value="ALL">All Suppliers</option>
                        <option value="LINKED">With Assets</option>
                        <option value="UNLINKED">Without Assets</option>
                    </select>

                    <select id="supplierStatusFilter" class="status-filter-select">
                        <option value="ALL">All Statuses</option>
                        <option value="ACTIVE">Active</option>
                        <option value="INACTIVE">Inactive (Deleted)</option>
                    </select>

                    <button type="button" class="btn" onclick="resetSupplierFilters()">
                        <i class="fa-solid fa-filter-circle-xmark"></i>
                        Reset Filters
                    </button>

                </div>

                <div class="registry-table-wrap">

                    <table class="supplier-table" id="supplierTable">
                        <colgroup>
                            <col class="supplier-col-id">
                            <col class="supplier-col-main">
                            <col class="supplier-col-contact">
                            <col class="supplier-col-email">
                            <col class="supplier-col-phone">
                            <col class="supplier-col-address">
                            <col class="supplier-col-linked">
                            <col class="supplier-col-value">
                            <col style="width: 9%;">
                            <col class="supplier-col-actions">
                        </colgroup>

                        <thead>
                            <tr>
                                <th onclick="sortTable(0)" style="cursor: pointer;" title="Click to sort">Supplier ID <i class="fa-solid fa-sort" style="color: #cbd5e1; margin-left: 4px;"></i></th>
                                <th onclick="sortTable(1)" style="cursor: pointer;" title="Click to sort">Supplier Details <i class="fa-solid fa-sort" style="color: #cbd5e1; margin-left: 4px;"></i></th>
                                <th onclick="sortTable(2)" style="cursor: pointer;" title="Click to sort">Contact Person <i class="fa-solid fa-sort" style="color: #cbd5e1; margin-left: 4px;"></i></th>
                                <th onclick="sortTable(3)" style="cursor: pointer;" title="Click to sort">Email <i class="fa-solid fa-sort" style="color: #cbd5e1; margin-left: 4px;"></i></th>
                                <th onclick="sortTable(4)" style="cursor: pointer;" title="Click to sort">Phone <i class="fa-solid fa-sort" style="color: #cbd5e1; margin-left: 4px;"></i></th>
                                <th onclick="sortTable(5)" style="cursor: pointer;" title="Click to sort">Address <i class="fa-solid fa-sort" style="color: #cbd5e1; margin-left: 4px;"></i></th>
                                <th onclick="sortTable(6)" style="cursor: pointer;" title="Click to sort">Linked Assets <i class="fa-solid fa-sort" style="color: #cbd5e1; margin-left: 4px;"></i></th>
                                <th onclick="sortTable(7)" style="cursor: pointer;" title="Click to sort">Purchase Value <i class="fa-solid fa-sort" style="color: #cbd5e1; margin-left: 4px;"></i></th>
                                <th onclick="sortTable(8)" style="cursor: pointer;" title="Click to sort">Status <i class="fa-solid fa-sort" style="color: #cbd5e1; margin-left: 4px;"></i></th>
                                <th>Control Actions</th>
                            </tr>
                        </thead>

                        <tbody>

                            <%
                                for (Vendor vendor : vendorList) {
                                    BigDecimal vendorValue = vendor.getTotalPurchaseValue() == null
                                            ? BigDecimal.ZERO
                                            : vendor.getTotalPurchaseValue();
                                    boolean vendorActive = !"INACTIVE".equalsIgnoreCase(vendor.getStatus());
                            %>

                            <tr>
                                <td>
                                    <span class="supplier-id-pill">
                                        SUP-<%= vendor.getVendorId() %>
                                    </span>
                                </td>

                                <td>
                                    <div class="supplier-main">
                                        <strong><%= safeText(vendor.getVendorName()) %></strong>
                                        <span class="table-subtext">
                                            Railway procurement supplier
                                        </span>
                                    </div>
                                </td>

                                <td>
                                    <%= safeText(vendor.getContactPerson()) %>
                                </td>

                                <td>
                                    <i class="fa-solid fa-envelope"></i>
                                    <%= safeText(vendor.getEmail()) %>
                                </td>

                                <td>
                                    <i class="fa-solid fa-phone"></i>
                                    <%= safeText(vendor.getPhone()) %>
                                </td>

                                <td>
                                    <%= safeText(vendor.getAddress()) %>
                                </td>

                                <td>
                                    <% if (vendor.getAssetCount() > 0) { %>
                                        <span class="supplier-linked-pill" data-assets="<%= vendor.getAssetCount() %>">
                                            <i class="fa-solid fa-link"></i>
                                            <%= vendor.getAssetCount() %> Assets
                                        </span>
                                    <% } else { %>
                                        <span class="supplier-free-pill" data-assets="0">
                                            <i class="fa-solid fa-unlink"></i>
                                            No Assets
                                        </span>
                                    <% } %>
                                </td>

                                <td>
                                    <span class="supplier-value-pill">
                                        &#8377;<%= moneyFormat.format(vendorValue) %>
                                    </span>
                                </td>

                                <td>
                                    <% if (vendorActive) { %>
                                        <span class="supplier-status-active" data-status="ACTIVE">
                                            <i class="fa-solid fa-circle-check"></i>
                                            Active
                                        </span>
                                    <% } else { %>
                                        <span class="supplier-status-inactive" data-status="INACTIVE">
                                            <i class="fa-solid fa-ban"></i>
                                            Inactive
                                        </span>
                                    <% } %>
                                </td>

                                <td>
                                    <div class="supplier-actions">

                                        <a href="view_vendor.jsp?id=<%= vendor.getVendorId() %>"
                                           class="supplier-action-btn inspect-btn" title="View supplier details">
                                            <i class="fa-solid fa-eye"></i> View
                                        </a>

                                        <% if (canManageSuppliers) { %>

                                            <a href="edit_vendor.jsp?id=<%= vendor.getVendorId() %>"
                                               class="supplier-action-btn edit-btn" title="Edit supplier record">
                                                <i class="fa-solid fa-pen-to-square"></i> Edit
                                            </a>

                                            <% if (!vendorActive) { %>
                                                <form action="DeleteVendorServlet" method="post" style="display:inline;" onsubmit="return confirm('Reactivate this supplier? It will become selectable again for new category mappings.');">
                                                    <input type="hidden" name="id" value="<%= vendor.getVendorId() %>">
                                                    <input type="hidden" name="action" value="enable">
                                                    <button type="submit" class="supplier-action-btn edit-btn" style="border:none; cursor:pointer;" title="Reactivate this supplier">
                                                        <i class="fa-solid fa-circle-check"></i> Reactivate
                                                    </button>
                                                </form>
                                            <% } else if (vendor.getAssetCount() == 0) { %>
                                                <form action="DeleteVendorServlet" method="post" style="display:inline;" onsubmit="return confirm('Are you sure you want to delete this supplier?');">
                                                    <input type="hidden" name="id" value="<%= vendor.getVendorId() %>">
                                                    <button type="submit" class="supplier-action-btn delete-btn" style="border:none; cursor:pointer;" title="Delete this supplier">
                                                        <i class="fa-solid fa-trash"></i> Delete
                                                    </button>
                                                </form>
                                            <% } else { %>
                                                <span class="supplier-action-btn supplier-disabled-action" title="Cannot delete: supplier is linked to assets">
                                                    <i class="fa-solid fa-lock"></i> In Use
                                                </span>
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

                    <div id="supplierNoRecords" class="no-records-message" style="display:none;">
                        <i class="fa-solid fa-circle-info"></i>
                        <strong>No matching supplier records found.</strong>
                        Try changing search keyword or linked asset filter.
                    </div>

                </div>

            </section>

        </div>
    </main>

</div>

<script>
    const supplierSearch = document.getElementById("supplierSearch");
    const supplierLinkedFilter = document.getElementById("supplierLinkedFilter");
    const supplierStatusFilter = document.getElementById("supplierStatusFilter");
    const tableRows = document.querySelectorAll("#supplierTable tbody tr");
    const supplierNoRecords = document.getElementById("supplierNoRecords");

    function normalizeText(text) {
        return text.toLowerCase().replace(/\s+/g, " ").trim();
    }

    function applySupplierFilters() {
        if (!supplierSearch || !supplierLinkedFilter) return;

        const keyword = normalizeText(supplierSearch.value);
        const selectedLinked = supplierLinkedFilter.value;
        const selectedStatus = supplierStatusFilter ? supplierStatusFilter.value : "ALL";

        let visibleCount = 0;

        tableRows.forEach(row => {
            const rowText = normalizeText(row.textContent);

            const linkedPill = row.querySelector(".supplier-linked-pill");
            const freePill = row.querySelector(".supplier-free-pill");
            let rowLinked = "";
            if (linkedPill) rowLinked = "LINKED";
            else if (freePill) rowLinked = "UNLINKED";

            const activePill = row.querySelector(".supplier-status-active");
            const inactivePill = row.querySelector(".supplier-status-inactive");
            let rowStatus = "";
            if (activePill) rowStatus = "ACTIVE";
            else if (inactivePill) rowStatus = "INACTIVE";

            const matchesSearch = keyword === "" || rowText.indexOf(keyword) !== -1;
            const matchesLinked = selectedLinked === "ALL" || rowLinked === selectedLinked;
            const matchesStatus = selectedStatus === "ALL" || rowStatus === selectedStatus;

            if (matchesSearch && matchesLinked && matchesStatus) {
                row.style.display = "";
                visibleCount++;
            } else {
                row.style.display = "none";
            }
        });

        if (supplierNoRecords) {
            supplierNoRecords.style.display = visibleCount === 0 ? "block" : "none";
        }
    }

    function resetSupplierFilters() {
        if (supplierLinkedFilter) supplierLinkedFilter.value = "ALL";
        if (supplierStatusFilter) supplierStatusFilter.value = "ALL";
        if (supplierSearch) supplierSearch.value = "";
        applySupplierFilters();
    }

    if (supplierSearch) supplierSearch.addEventListener("input", applySupplierFilters);
    if (supplierLinkedFilter) supplierLinkedFilter.addEventListener("change", applySupplierFilters);
    if (supplierStatusFilter) supplierStatusFilter.addEventListener("change", applySupplierFilters);

    applySupplierFilters();

    var sortDirections = [true, true, true, true, true, true, true, true, true];
    function sortTable(columnIndex) {
        var table = document.getElementById("supplierTable");
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
            
            // Special handling for value sorting
            if (columnIndex === 7) {
                valA = parseFloat(valA.replace(/[^0-9.-]+/g,"")) || 0;
                valB = parseFloat(valB.replace(/[^0-9.-]+/g,"")) || 0;
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