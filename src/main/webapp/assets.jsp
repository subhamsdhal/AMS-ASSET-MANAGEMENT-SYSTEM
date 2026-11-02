<%@page contentType="text/html" pageEncoding="UTF-8"%>
<%@page import="com.mycompany.asset_management_system_ams.Asset"%>
<%@page import="com.mycompany.asset_management_system_ams.AssetDAO"%>
<%@page import="java.util.List"%>
<%@page import="java.util.Locale"%>
<%@page import="java.text.DecimalFormat"%>

<%!
    private String safeText(String value) {
        if (value == null || value.trim().isEmpty()) {
            return "N/A";
        }

        return value.trim()
                .replace("&", "&amp;")
                .replace("<", "&lt;")
                .replace(">", "&gt;")
                .replace("\"", "&quot;")
                .replace("'", "&#39;");
    }

    private String assetImageSrc(String value) {
        if (value == null || value.trim().isEmpty()) {
            return "images/indian-railway-logo.png";
        }

        return value.trim()
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
                out.append(Character.toUpperCase(part.charAt(0)))
                        .append(part.substring(1))
                        .append(" ");
            }
        }

        return out.toString().trim();
    }

    private String statusClass(String status) {
        if (status == null || status.trim().isEmpty()) {
            return "UNKNOWN";
        }

        return status.trim().toUpperCase(Locale.ENGLISH).replace(" ", "_");
    }

    private String moneyNoDecimal(double value) {
        return String.format("%,.0f", value);
    }

    private String compactNumber(int value) {
        DecimalFormat df = new DecimalFormat("0.#");

        if (value >= 10000000) {
            return df.format(value / 10000000.0) + "Cr";
        }

        if (value >= 100000) {
            return df.format(value / 100000.0) + "L";
        }

        if (value >= 1000) {
            return df.format(value / 1000.0) + "K";
        }

        return String.valueOf(value);
    }

    private String compactCurrency(double value) {
        DecimalFormat df = new DecimalFormat("0.#");

        if (value >= 10000000) {
            return "₹" + df.format(value / 10000000.0) + "Cr";
        }

        if (value >= 100000) {
            return "₹" + df.format(value / 100000.0) + "L";
        }

        if (value >= 1000) {
            return "₹" + df.format(value / 1000.0) + "K";
        }

        return "₹" + moneyNoDecimal(value);
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

    boolean canManageAssets = ("SUPER_ADMIN".equals(role) || "ADMIN".equals(role)) || "ASSET_MANAGER".equalsIgnoreCase(role);

    AssetDAO dao = new AssetDAO();
    List<Asset> assetList = null;
    
    if ("DEPARTMENT_HEAD".equalsIgnoreCase(role)) {
        java.util.List<Integer> departmentIds = (java.util.List<Integer>) session.getAttribute("departmentIds");
        assetList = dao.getAllAssets(departmentIds);
    } else {
        assetList = dao.getAllAssets();
    }

    String msg = request.getParameter("msg");
    String access = request.getParameter("access");
    String error = request.getParameter("error");

    int available = 0;
    int allocated = 0;
    int maintenance = 0;
    int disposed = 0;
    int damaged = 0;
    double totalAssetValue = 0.0;

    for (Asset a : assetList) {
        String st = a.getAssetStatus();

        totalAssetValue += a.getPurchaseCost();

        if ("AVAILABLE".equalsIgnoreCase(st)) {
            available++;
        } else if ("ALLOCATED".equalsIgnoreCase(st)) {
            allocated++;
        } else if ("UNDER_MAINTENANCE".equalsIgnoreCase(st)) {
            maintenance++;
        } else if ("DISPOSED".equalsIgnoreCase(st)) {
            disposed++;
        } else if ("DAMAGED".equalsIgnoreCase(st)) {
            damaged++;
        }
    }

    String userInitial = username.substring(0, Math.min(2, username.length())).toUpperCase(Locale.ENGLISH);
%>

<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>Assets - IR-AMS</title>

    <link rel="stylesheet"
          href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.0/css/all.min.css">

    <link rel="stylesheet" href="css/ir-glass.css?v=28000">
    <link rel="stylesheet" href="css/ams-pro.css?v=28000">
    <link rel="stylesheet" href="css/ir-ams-railway-ui.css?v=assets-module-auto-center-emblem-1">

    <link rel="stylesheet" href="css/assets.css?v=28001">
</head>

<body class="railway-ui">
<div class="app ams-shell">

    <div class="page-fixed-emblem-watermark" aria-hidden="true">
        <img src="images/Emblem_of_India.png" alt="">
    </div>
    <jsp:include page="sidebar.jsp" />

    <main class="main railway-main">
        <jsp:include page="topbar.jsp" />

        <div class="main-scroll-content assets-board">

            <section class="asset-hero">
                <div class="asset-hero-bg"></div>
                <div class="asset-hero-soft-fade"></div>

                <div class="asset-hero-copy">
                    <span class="eyebrow">
                        <i class="fa-solid fa-cubes"></i>
                        Assets Module · East Coast Railway
                    </span>

                    <h1>Railway Asset Registry</h1>

                    <p>
                        Monitor, track and control railway assets using serial numbers, dynamic QR identity,
                        location mapping, warranty records and live operational status for official asset lifecycle management.
                    </p>

                    <div class="hero-pills">
                        <div class="hero-pill"><i class="fa-solid fa-database"></i> Live MySQL Connected</div>
                        <div class="hero-pill"><i class="fa-solid fa-qrcode"></i> Dynamic QR Enabled</div>
                        <div class="hero-pill"><i class="fa-solid fa-location-dot"></i> Location Tracking</div>
                        <div class="hero-pill"><i class="fa-solid fa-shield-halved"></i> Secure Registry</div>
                    </div>
                </div>
            </section>

            <% if ("denied".equals(access)) { %>
                <div class="page-error">
                    <i class="fa-solid fa-triangle-exclamation"></i>
                    Access denied. You do not have permission to manage assets.
                </div>
            <% } %>

            <% if ("invalid_qr_asset".equals(error)) { %>
                <div class="page-error">
                    <i class="fa-solid fa-triangle-exclamation"></i>
                    Invalid asset selected for QR action.
                </div>
            <% } %>

            <% if ("asset_notfound".equals(error)) { %>
                <div class="page-error">
                    <i class="fa-solid fa-triangle-exclamation"></i>
                    Selected asset was not found.
                </div>
            <% } %>

            <% if ("server".equals(error)) { %>
                <div class="page-error">
                    <i class="fa-solid fa-triangle-exclamation"></i>
                    Server error occurred while processing the asset request.
                </div>
            <% } %>

            <% if ("added".equals(msg)) { %>
                <div class="page-success">
                    <i class="fa-solid fa-circle-check"></i>
                    Asset added successfully.
                </div>
            <% } else if ("added_doc_failed".equals(msg)) { %>
                <div class="page-error" style="background: #fff3cd; color: #856404; border-color: #ffeeba;">
                    <i class="fa-solid fa-triangle-exclamation"></i>
                    Asset added successfully, but the attached document failed to upload. You can attach it again from the asset's page.
                </div>
            <% } %>

            <% if ("updated".equals(msg)) { %>
                <div class="page-success">
                    <i class="fa-solid fa-circle-check"></i>
                    Asset updated successfully.
                </div>
            <% } %>

            <% if ("disposed".equals(msg)) { %>
                <div class="page-success">
                    <i class="fa-solid fa-circle-check"></i>
                    Asset disposed successfully.
                </div>
            <% } else if ("disposalsubmitted".equals(msg)) { %>
                <div class="page-success">
                    <i class="fa-solid fa-circle-check"></i>
                    Disposal proposal submitted. It is now awaiting review by a Super Admin or Admin -
                    <a href="asset_disposals.jsp">view pending disposals</a>.
                </div>
            <% } %>

            <section class="kpi-grid">
                <div class="kpi-card">
                    <div class="kpi-icon"><i class="fa-solid fa-boxes-stacked"></i></div>
                    <h3>Total Assets</h3>
                    <p title="<%= assetList.size() %>"><%= compactNumber(assetList.size()) %></p>
                </div>

                <div class="kpi-card">
                    <div class="kpi-icon"><i class="fa-solid fa-circle-check"></i></div>
                    <h3>Available</h3>
                    <p title="<%= available %>"><%= compactNumber(available) %></p>
                </div>

                <div class="kpi-card">
                    <div class="kpi-icon"><i class="fa-solid fa-user-check"></i></div>
                    <h3>Allocated</h3>
                    <p title="<%= allocated %>"><%= compactNumber(allocated) %></p>
                </div>

                <div class="kpi-card">
                    <div class="kpi-icon"><i class="fa-solid fa-screwdriver-wrench"></i></div>
                    <h3>Maintenance</h3>
                    <p title="<%= maintenance %>"><%= compactNumber(maintenance) %></p>
                </div>

                <div class="kpi-card">
                    <div class="kpi-icon"><i class="fa-solid fa-recycle"></i></div>
                    <h3>Disposed</h3>
                    <p title="<%= disposed %>"><%= compactNumber(disposed) %></p>
                </div>

                <div class="kpi-card">
                    <div class="kpi-icon"><i class="fa-solid fa-indian-rupee-sign"></i></div>
                    <h3>Asset Value</h3>
                    <p title="₹<%= moneyNoDecimal(totalAssetValue) %>"><%= compactCurrency(totalAssetValue) %></p>
                </div>
            </section>

            <section class="glass-panel">
                <div class="registry-toolbar">
                    <div>
                        <h2>Asset Control Table</h2>
                        <p class="table-subtext">
                            Showing <%= assetList.size() %> live asset records from railway database.
                        </p>
                    </div>

                    <div class="registry-actions">
                        <% if (canManageAssets) { %>
                            <a href="add_asset.jsp" class="btn primary">
                                <i class="fa-solid fa-plus"></i>
                                Add Asset
                            </a>
                        <% } %>

                        <a href="export_asset_report.jsp" class="btn green">
                            <i class="fa-solid fa-file-excel"></i>
                            Export Excel
                        </a>

                        <a href="qr_print.jsp" class="btn">
                            <i class="fa-solid fa-print"></i>
                            Print QR Labels
                        </a>

                        <a href="qr_scanner.jsp" class="btn">
                            <i class="fa-solid fa-qrcode"></i>
                            QR Scanner
                        </a>
                    </div>
                </div>

                <div class="registry-filter-grid">
                    <div class="registry-search">
                        <i class="fa-solid fa-magnifying-glass"></i>
                        <input type="text"
                               id="assetSearch"
                               placeholder="Search asset code, name, category, serial, location, supplier, QR...">
                    </div>

                    <select id="assetStatusFilter" class="status-filter-select">
                        <option value="ALL">All Status</option>
                        <option value="AVAILABLE">AVAILABLE</option>
                        <option value="ALLOCATED">ALLOCATED</option>
                        <option value="UNDER_MAINTENANCE">UNDER_MAINTENANCE</option>
                        <option value="DAMAGED">DAMAGED</option>
                        <option value="DISPOSED">DISPOSED</option>
                    </select>
                </div>

                <div class="registry-table-wrap">
                    <table class="asset-table" id="assetTable">
                        <colgroup>
                            <col class="asset-col-main">
                            <col class="asset-col-meta">
                            <col class="asset-col-qr">
                            <col class="asset-col-location">
                            <col class="asset-col-supplier">
                            <col class="asset-col-status">
                            <col class="asset-col-actions">
                        </colgroup>

                        <thead>
                            <tr>
                                <th onclick="sortTable(0)" style="cursor: pointer;" title="Click to sort">Asset <i class="fa-solid fa-sort" style="color: #cbd5e1; margin-left: 4px;"></i></th>
                                <th onclick="sortTable(1)" style="cursor: pointer;" title="Click to sort">Category / Serial <i class="fa-solid fa-sort" style="color: #cbd5e1; margin-left: 4px;"></i></th>
                                <th onclick="sortTable(2)" style="cursor: pointer;" title="Click to sort">QR Identity <i class="fa-solid fa-sort" style="color: #cbd5e1; margin-left: 4px;"></i></th>
                                <th onclick="sortTable(3)" style="cursor: pointer;" title="Click to sort">Location <i class="fa-solid fa-sort" style="color: #cbd5e1; margin-left: 4px;"></i></th>
                                <th onclick="sortTable(4)" style="cursor: pointer;" title="Click to sort">Supplier / Warranty <i class="fa-solid fa-sort" style="color: #cbd5e1; margin-left: 4px;"></i></th>
                                <th onclick="sortTable(5)" style="cursor: pointer;" title="Click to sort">Status <i class="fa-solid fa-sort" style="color: #cbd5e1; margin-left: 4px;"></i></th>
                                <th>Control Actions</th>
                            </tr>
                        </thead>

                        <tbody>
                            <% if (assetList == null || assetList.isEmpty()) { %>
                                <tr>
                                    <td colspan="7" class="empty-row">
                                        <i class="fa-solid fa-box-open"></i>
                                        No asset records found.
                                    </td>
                                </tr>
                            <% } else { %>
                                <% for (Asset asset : assetList) {
                                    String currentStatus = asset.getAssetStatus() == null ? "UNKNOWN" : asset.getAssetStatus();
                                %>
                                    <tr data-status="<%= safeText(statusClass(currentStatus)) %>">
                                        <td>
                                            <div class="asset-main-cell">
                                                <img class="asset-thumb"
                                                     src="<%= assetImageSrc(asset.getAssetImagePath()) %>"
                                                     alt="Asset Photo">

                                                <div class="asset-main-copy">
                                            <span class="asset-code-pill">
                                                <i class="fa-solid fa-cube"></i>
                                                <%= safeText(asset.getAssetCode()) %>
                                            </span>

                                            <strong class="asset-primary-title">
                                                <%= safeText(asset.getAssetName()) %>
                                            </strong>

                                            <span class="table-subtext">
                                                ID: <%= asset.getAssetId() %> · Cost: ₹<%= moneyNoDecimal(asset.getPurchaseCost()) %> · Dep: <%= asset.getDepreciationRate() %>%
                                            </span>
                                                </div>
                                            </div>
                                        </td>

                                        <td>
                                            <div class="cell-stack">
                                                <strong><%= safeText(asset.getCategoryName()) %></strong>
                                                <span><%= safeText(asset.getSerialNumber()) %></span>
                                            </div>
                                        </td>

                                        <td>
                                            <%-- Fault: printed the raw qr_code column value directly. Same
                                                 "raw QR value looks odd" issue already fixed on view_asset.jsp/
                                                 asset_qr_card.jsp/etc. - just missed on this list page. Made
                                                 worse here by real data (AST002) where qr_code itself holds a
                                                 full URL, not a short code - a data-entry slip from directly
                                                 editing that column rather than going through QR generation,
                                                 which normally writes a clean "IRAMS-<code>" value here. Fixed
                                                 the display defensively: always show the asset's own code
                                                 (always short, always clean, needs no extra DB column) instead
                                                 of trusting whatever qr_code currently holds - the full/raw
                                                 value is still available on hover via title. --%>
                                            <span class="qr-pill" title="<%= safeText(asset.getQrCode()) %>">
                                                <i class="fa-solid fa-qrcode"></i>
                                                <%= safeText(asset.getAssetCode()) %>
                                            </span>
                                        </td>

                                        <td>
                                            <div class="cell-stack">
                                                <strong><%= safeText(asset.getLocation()) %></strong>
                                                <span>Mapped location / section</span>
                                            </div>
                                        </td>

                                        <td>
                                            <div class="cell-stack">
                                                <strong><%= safeText(asset.getVendorName()) %></strong>
                                                <span>Warranty: <%= safeText(asset.getWarrantyExpiry()) %></span>
                                            </div>
                                        </td>

                                        <td>
                                            <span class="status-badge status-<%= safeText(statusClass(currentStatus)) %>">
                                                <%= safeText(cleanLabel(currentStatus)) %>
                                            </span>
                                        </td>

                                        <td>
                                            <div class="asset-actions">
                                                <a href="view_asset.jsp?id=<%= asset.getAssetId() %>"
                                                   class="asset-action-btn inspect-btn" title="Inspect details of this asset">
                                                    <i class="fa-solid fa-magnifying-glass-chart"></i>
                                                    Inspect
                                                </a>

                                                <a href="asset_qr_card.jsp?id=<%= asset.getAssetId() %>"
                                                   class="asset-action-btn qr-btn" title="View QR digital twin">
                                                    <i class="fa-solid fa-qrcode"></i>
                                                    View QR
                                                </a>

                                                <a href="qr_print.jsp?id=<%= asset.getAssetId() %>"
                                                   class="asset-action-btn print-btn" title="Print physical QR sticker">
                                                    <i class="fa-solid fa-print"></i>
                                                    Print QR
                                                </a>

                                                <% if (canManageAssets) { %>
                                                    <% if (!"DISPOSED".equalsIgnoreCase(currentStatus)) { %>
                                                        <a href="edit_asset.jsp?id=<%= asset.getAssetId() %>"
                                                           class="asset-action-btn edit-btn" title="Edit asset properties">
                                                            <i class="fa-solid fa-pen-to-square"></i>
                                                            Edit
                                                        </a>
                                                    <% } %>

                                                    <% if ("AVAILABLE".equalsIgnoreCase(currentStatus)
                                                            || "UNDER_MAINTENANCE".equalsIgnoreCase(currentStatus)) { %>
                                                        <a href="dispose_asset.jsp?id=<%= asset.getAssetId() %>"
                                                           class="asset-action-btn dispose-btn" title="Dispose or retire asset">
                                                            <i class="fa-solid fa-recycle"></i>
                                                            Dispose
                                                        </a>
                                                    <% } %>
                                                <% } %>
                                            </div>
                                        </td>
                                    </tr>
                                <% } %>
                            <% } %>
                        </tbody>
                    </table>
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
            setTimeout(updateBodyEmblemCenter, 80);
            setTimeout(updateBodyEmblemCenter, 220);
            setTimeout(updateBodyEmblemCenter, 520);
            setTimeout(updateBodyEmblemCenter, 900);
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

        var observeTargets = [
            document.body,
            document.querySelector(".app"),
            document.querySelector(".ams-shell"),
            document.querySelector(".sidebar"),
            document.querySelector(".railway-sidebar"),
            document.querySelector(".main"),
            document.querySelector(".railway-main")
        ].filter(Boolean);

        observeTargets.forEach(function (target) {
            var observer = new MutationObserver(scheduleBodyEmblemCenter);
            observer.observe(target, {
                attributes: true,
                attributeFilter: ["class", "style"]
            });
        });

        scheduleBodyEmblemCenter();
    })();

    (function () {
        var searchInput = document.getElementById("assetSearch");
        var statusFilter = document.getElementById("assetStatusFilter");
        var table = document.getElementById("assetTable");

        function filterTable() {
            if (!table) {
                return;
            }

            var searchText = searchInput ? searchInput.value.toLowerCase().trim() : "";
            var statusValue = statusFilter ? statusFilter.value : "ALL";
            var rows = table.querySelectorAll("tbody tr");

            rows.forEach(function (row) {
                if (!row.getAttribute("data-status")) {
                    return;
                }

                var rowText = row.innerText.toLowerCase();
                var rowStatus = row.getAttribute("data-status") || "";
                var searchMatch = searchText.length === 0 || rowText.indexOf(searchText) >= 0;
                var statusMatch = statusValue === "ALL" || rowStatus === statusValue;

                row.style.display = searchMatch && statusMatch ? "" : "none";
            });
        }

        if (searchInput) {
            searchInput.addEventListener("keyup", filterTable);
        }

        if (statusFilter) {
            statusFilter.addEventListener("change", filterTable);
        }
    })();

    var sortDirections = [true, true, true, true, true, true]; // true = ASC, false = DESC
    function sortTable(columnIndex) {
        var table = document.getElementById("assetTable");
        if (!table) return;
        
        var tbody = table.querySelector("tbody");
        if (!tbody) return;
        
        var rows = Array.from(tbody.querySelectorAll("tr"));
        // Skip sort if it's the "empty-row" message
        if (rows.length === 1 && rows[0].querySelector(".empty-row")) return;

        var asc = sortDirections[columnIndex];
        sortDirections[columnIndex] = !asc; // Toggle for next click

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

        // Re-attach sorted rows
        rows.forEach(function(row) {
            tbody.appendChild(row);
        });
        
        // Update header icons (optional UI polish)
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

<script src="js/user-dropdown.js?v=5"></script>
<script src="js/sidebar-role.js?v=assets-module-auto-center-emblem-1"></script>
<script src="js/topbar-search.js?v=global-search-ready-1"></script>
<script src="js/dashboard-actions.js?v=2"></script>

</body>
</html>
