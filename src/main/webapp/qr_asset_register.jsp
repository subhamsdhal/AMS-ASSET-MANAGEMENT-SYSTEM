<%@page contentType="text/html" pageEncoding="UTF-8"%>
<%@page import="com.mycompany.asset_management_system_ams.DBConnection"%>
<%@page import="com.mycompany.asset_management_system_ams.QrUrlUtil"%>
<%@page import="java.sql.*"%>
<%@page import="java.util.*"%>
<%@page import="java.net.URLEncoder"%>
<%@page import="jakarta.servlet.http.HttpServletRequest"%>

<%!
    public static class QrAssetRow {
        String assetId = "";
        String assetCode = "";
        String assetName = "";
        String categoryName = "";
        String departmentName = "";
        String vendorName = "";
        String assetStatus = "";
        String conditionStatus = "";
        String serviceStatus = "";
        String locationName = "";
        String qrPublicToken = "";
        String qrCode = "";
        String updatedAt = "";
    }

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

    private int countRows(Connection con, String sql) {
        try (Statement st = con.createStatement();
             ResultSet rs = st.executeQuery(sql)) {

            if (rs.next()) {
                return rs.getInt(1);
            }

        } catch (Exception e) {
            System.err.println("QR Module DB Error: " + e.getMessage());
        }

        return 0;
    }

    private String appBaseUrl(HttpServletRequest request) {
        String scheme = request.getHeader("X-Forwarded-Proto");

        if (scheme == null || scheme.trim().isEmpty()) {
            scheme = request.getScheme();
        }

        String host = request.getHeader("X-Forwarded-Host");

        if (host == null || host.trim().isEmpty()) {
            host = request.getServerName();

            int port = request.getServerPort();

            if (!("http".equalsIgnoreCase(scheme) && port == 80)
                    && !("https".equalsIgnoreCase(scheme) && port == 443)) {
                host = host + ":" + port;
            }
        }

        return scheme + "://" + host + request.getContextPath();
    }

    private String liveUrl(String publicBaseUrl, String token, String qrCode) {
        String finalToken = "";

        if (token != null && !token.trim().isEmpty()) {
            finalToken = token.trim();
        } else if (qrCode != null && !qrCode.trim().isEmpty()) {
            finalToken = qrCode.trim();
        }

        if (finalToken.isEmpty()) {
            return "";
        }

        if (publicBaseUrl == null || publicBaseUrl.trim().isEmpty()) {
            return "";
        }

        return publicBaseUrl.trim() + "/public_asset_view.jsp?token=" + finalToken;
    }

    private String statusClass(String status) {
        if (status == null || status.trim().isEmpty()) {
            return "UNKNOWN";
        }

        return status.trim().toUpperCase(Locale.ENGLISH).replace(" ", "_");
    }

    // Fault: this "Public Live URL" column showed the full URL - scheme,
    // domain, AND the long random token querystring - as plain (non-clickable)
    // pill text on every single row, which gets very cluttered/odd-looking
    // across a register listing many assets, and the pill wasn't even a real
    // link (there's a separate "Public" action button per row that already
    // opens it). Shows just the scheme+host here instead (e.g.
    // "https://your-tunnel.example.com") - enough for an admin to confirm at a
    // glance which domain/provider is currently configured (e.g. spot a stale
    // localhost or an old tunnel domain) without the token noise - full URL
    // stays in the title= tooltip, and the pill is now itself a real link to
    // that exact URL. Deliberately provider-agnostic (plain java.net.URI
    // parsing, not pattern-matched against ngrok/cloudflare specifically) so
    // this keeps working unchanged no matter what tunnel provider or custom
    // domain ends up configured in Settings.
    private String urlHost(String url) {
        if (url == null || url.trim().isEmpty()) {
            return "";
        }
        try {
            java.net.URI uri = new java.net.URI(url.trim());
            String scheme = uri.getScheme();
            String host = uri.getHost();
            if (host == null) {
                return url.trim();
            }
            return (scheme != null ? scheme + "://" : "") + host;
        } catch (Exception e) {
            return url.trim();
        }
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

    boolean canViewQrRegister = ("SUPER_ADMIN".equals(role) || "ADMIN".equals(role))
            || "ASSET_MANAGER".equals(role)
            || "AUDITOR".equals(role);

    if (!canViewQrRegister) {
        response.sendRedirect("dashboard.jsp?access=denied");
        return;
    }

    String q = request.getParameter("q");
    String qrFilter = request.getParameter("qr");
    String statusFilter = request.getParameter("status");

    if (q == null) {
        q = "";
    }

    if (qrFilter == null || qrFilter.trim().isEmpty()) {
        qrFilter = "ALL";
    }

    if (statusFilter == null || statusFilter.trim().isEmpty()) {
        statusFilter = "ALL";
    }

    q = q.trim();
    qrFilter = qrFilter.trim().toUpperCase(Locale.ENGLISH);
    statusFilter = statusFilter.trim().toUpperCase(Locale.ENGLISH);

    String exportUrl = "export_qr_asset_register.jsp?qr="
            + URLEncoder.encode(qrFilter, "UTF-8")
            + "&status=" + URLEncoder.encode(statusFilter, "UTF-8");

    String printUrl = "qr_print_labels.jsp?qr="
            + URLEncoder.encode(qrFilter, "UTF-8")
            + "&status=" + URLEncoder.encode(statusFilter, "UTF-8");

    if (!q.isEmpty()) {
        exportUrl += "&q=" + URLEncoder.encode(q, "UTF-8");
        printUrl += "&q=" + URLEncoder.encode(q, "UTF-8");
    }

    String publicBaseUrl = QrUrlUtil.getConfiguredPublicBaseUrl();
    String userInitial = username.substring(0, Math.min(2, username.length())).toUpperCase(Locale.ENGLISH);

    int totalAssets = 0;
    int generatedQr = 0;
    int missingQr = 0;
    int filteredCount = 0;

    List<QrAssetRow> rows = new ArrayList<QrAssetRow>();

    try (Connection con = DBConnection.getConnection()) {
        totalAssets = countRows(con, "SELECT COUNT(*) FROM assets");

        generatedQr = countRows(con,
                "SELECT COUNT(*) FROM assets "
                + "WHERE qr_public_token IS NOT NULL AND TRIM(qr_public_token) <> ''");

        missingQr = totalAssets - generatedQr;

        StringBuilder sql = new StringBuilder();

        sql.append("SELECT ")
                .append("a.asset_id, a.asset_code, a.asset_name, a.asset_status, ")
                .append("a.condition_status, a.service_status, a.qr_public_token, a.qr_code, ")
                .append("DATE_FORMAT(a.updated_at, '%d %b %Y, %h:%i %p') AS updated_at, ")
                .append("COALESCE(ac.category_name, 'Uncategorized') AS category_name, ")
                .append("COALESCE(d.department_name, 'Unassigned') AS department_name, ")
                .append("COALESCE(v.vendor_name, 'No Vendor') AS vendor_name, ")
                .append("COALESCE(rl.location_name, a.location, 'Not Mentioned') AS location_name ")
                .append("FROM assets a ")
                .append("LEFT JOIN asset_categories ac ON a.category_id = ac.category_id ")
                .append("LEFT JOIN departments d ON a.department_id = d.department_id ")
                .append("LEFT JOIN vendors v ON a.vendor_id = v.vendor_id ")
                .append("LEFT JOIN railway_locations rl ON a.location_id = rl.location_id ")
                .append("WHERE 1 = 1 ");

        List<String> params = new ArrayList<String>();

        if ("GENERATED".equals(qrFilter)) {
            sql.append("AND a.qr_public_token IS NOT NULL AND TRIM(a.qr_public_token) <> '' ");
        } else if ("MISSING".equals(qrFilter)) {
            sql.append("AND (a.qr_public_token IS NULL OR TRIM(a.qr_public_token) = '') ");
        }

        if (!"ALL".equals(statusFilter)) {
            sql.append("AND a.asset_status = ? ");
            params.add(statusFilter);
        }

        if (!q.isEmpty()) {
            sql.append("AND (")
                    .append("a.asset_code LIKE ? ")
                    .append("OR a.asset_name LIKE ? ")
                    .append("OR ac.category_name LIKE ? ")
                    .append("OR d.department_name LIKE ? ")
                    .append("OR v.vendor_name LIKE ? ")
                    .append("OR rl.location_name LIKE ? ")
                    .append("OR a.qr_public_token LIKE ? ")
                    .append("OR a.qr_code LIKE ? ")
                    .append(") ");

            String searchValue = "%" + q + "%";

            for (int i = 0; i < 8; i++) {
                params.add(searchValue);
            }
        }

        sql.append("ORDER BY a.asset_id DESC LIMIT 300");

        try (PreparedStatement ps = con.prepareStatement(sql.toString())) {
            for (int i = 0; i < params.size(); i++) {
                ps.setString(i + 1, params.get(i));
            }

            try (ResultSet rs = ps.executeQuery()) {
                while (rs.next()) {
                    QrAssetRow row = new QrAssetRow();

                    row.assetId = rs.getString("asset_id");
                    row.assetCode = rs.getString("asset_code");
                    row.assetName = rs.getString("asset_name");
                    row.categoryName = rs.getString("category_name");
                    row.departmentName = rs.getString("department_name");
                    row.vendorName = rs.getString("vendor_name");
                    row.assetStatus = rs.getString("asset_status");
                    row.conditionStatus = rs.getString("condition_status");
                    row.serviceStatus = rs.getString("service_status");
                    row.locationName = rs.getString("location_name");
                    row.qrPublicToken = rs.getString("qr_public_token");
                    row.qrCode = rs.getString("qr_code");
                    row.updatedAt = rs.getString("updated_at");

                    rows.add(row);
                }
            }
        }

        filteredCount = rows.size();

    } catch (Exception e) {
        System.err.println("QR Module DB Error: " + e.getMessage());
    }
%>

<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>QR Asset Register - IR-AMS</title>

    <link rel="stylesheet"
          href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.0/css/all.min.css">

    <link rel="stylesheet" href="css/ir-glass.css?v=28000">
    <link rel="stylesheet" href="css/ams-pro.css?v=28000">
    <link rel="stylesheet" href="css/ir-ams-railway-ui.css?v=28000">
<link rel="stylesheet" href="css/qr_asset_register.css?v=topbarfix1">
        </head>

<body class="railway-ui">
<div class="app ams-shell">
    <jsp:include page="sidebar.jsp" />
<main class="main railway-main">
        
        <header class="topbar railway-topbar">
            <button class="nav-toggle" type="button" aria-label="Toggle sidebar">
                <i class="fa-solid fa-bars"></i>
            </button>

            <a href="dashboard.jsp" class="topbar-title topbar-home-link" title="Open Dashboard">
                <h1>IR-AMS</h1>
                <span>QR Asset Register</span>
            </a>

            <button class="hq-selector" type="button" data-dashboard-menu="hq" aria-label="Railway unit">
                <i class="fa-solid fa-location-dot"></i>
                <div>
                    <strong>East Coast Railway</strong>
                    <span>Headquarters / Rail Sadan, Bhubaneswar</span>
                </div>
                <i class="fa-solid fa-angle-down"></i>
            </button>

            <div class="search-box">
                <i class="fa-solid fa-magnifying-glass"></i>
                <input type="text"
                       id="globalSearch"
                       placeholder="Search QR assets, tokens, public links, status...">
            </div>

            <div class="topbar-actions top-right">
                <button type="button" class="control-active" data-dashboard-menu="alerts">
                    <i class="fa-solid fa-shield-halved"></i>
                    Control Active
                    <i class="fa-solid fa-angle-down"></i>
                </button>

                <button type="button" class="top-icon-btn" title="Notifications">
                    <i class="fa-regular fa-bell"></i>
                </button>

                <button type="button" class="top-icon-btn" title="Messages">
                    <i class="fa-regular fa-envelope"></i>
                </button>

                <button type="button" class="top-icon-btn" title="Help">
                    <i class="fa-regular fa-circle-question"></i>
                </button>

                <div class="user-card" title="User menu">
                    <div class="avatar">IR</div>
                    <div>
                        <strong><%= username %></strong>
                        <span><%= role == null ? "" : role.replace("_", " ") %></span>
                    </div>
                </div>
            </div>
        </header>

        <div class="main-scroll-content qr-register-board">

            <section class="register-hero">
                <div>
                    <h1>QR Asset Register</h1>
                    <p>
                        Official QR register showing asset-wise live QR token, public QR URL,
                        print label status, asset status and railway department/location details.
                    </p>
                </div>

                <div class="hero-actions">
                    <a href="<%= safeText(printUrl) %>" class="action-btn primary">
                        <i class="fa-solid fa-print"></i>
                        Print Labels
                    </a>

                    <a href="<%= safeText(exportUrl) %>" class="action-btn green">
                        <i class="fa-solid fa-file-excel"></i>
                        Export Excel
                    </a>

                    <a href="qr_bulk_generate.jsp" class="action-btn">
                        <i class="fa-solid fa-wand-magic-sparkles"></i>
                        Bulk Generate
                    </a>

                    <a href="qr_control_center.jsp" class="action-btn">
                        <i class="fa-solid fa-arrow-left"></i>
                        Control Center
                    </a>
                </div>
            </section>

            <section class="kpi-grid">
                <div class="kpi-card">
                    <div class="kpi-icon"><i class="fa-solid fa-cubes"></i></div>
                    <h3>Total Assets</h3>
                    <p><%= totalAssets %></p>
                </div>

                <div class="kpi-card">
                    <div class="kpi-icon"><i class="fa-solid fa-qrcode"></i></div>
                    <h3>QR Generated</h3>
                    <p><%= generatedQr %></p>
                </div>

                <div class="kpi-card">
                    <div class="kpi-icon"><i class="fa-solid fa-hourglass-half"></i></div>
                    <h3>QR Missing</h3>
                    <p><%= missingQr %></p>
                </div>

                <div class="kpi-card">
                    <div class="kpi-icon"><i class="fa-solid fa-filter"></i></div>
                    <h3>Filtered</h3>
                    <p><%= filteredCount %></p>
                </div>
            </section>

            <section class="panel">
                <div class="toolbar">
                    <div>
                        <h2>Asset QR Register</h2>
                        <p class="table-subtext">Showing <%= filteredCount %> matching assets. Maximum 300 records shown.</p>
                    </div>

                    <form class="filter-form" method="get" action="qr_asset_register.jsp">
                        <input class="filter-input"
                               type="text"
                               name="q"
                               value="<%= q.isEmpty() ? "" : safeText(q) %>"
                               placeholder="Search asset, category, department, vendor, token...">

                        <select class="filter-select" name="qr">
                            <option value="ALL" <%= "ALL".equals(qrFilter) ? "selected" : "" %>>All QR</option>
                            <option value="GENERATED" <%= "GENERATED".equals(qrFilter) ? "selected" : "" %>>QR Generated</option>
                            <option value="MISSING" <%= "MISSING".equals(qrFilter) ? "selected" : "" %>>QR Missing</option>
                        </select>

                        <select class="filter-select" name="status">
                            <option value="ALL" <%= "ALL".equals(statusFilter) ? "selected" : "" %>>All Status</option>
                            <option value="AVAILABLE" <%= "AVAILABLE".equals(statusFilter) ? "selected" : "" %>>Available</option>
                            <option value="ALLOCATED" <%= "ALLOCATED".equals(statusFilter) ? "selected" : "" %>>Allocated</option>
                            <option value="UNDER_MAINTENANCE" <%= "UNDER_MAINTENANCE".equals(statusFilter) ? "selected" : "" %>>Under Maintenance</option>
                            <option value="DISPOSED" <%= "DISPOSED".equals(statusFilter) ? "selected" : "" %>>Disposed</option>
                        </select>

                        <button class="action-btn primary" type="submit">
                            <i class="fa-solid fa-filter"></i>
                            Filter
                        </button>

                        <a class="action-btn green" href="<%= safeText(exportUrl) %>">
                            <i class="fa-solid fa-file-excel"></i>
                            Export
                        </a>

                        <a class="action-btn" href="qr_asset_register.jsp">
                            <i class="fa-solid fa-rotate-right"></i>
                            Reset
                        </a>
                    </form>
                </div>

                <div class="table-wrap">
                    <table class="asset-table" id="assetTable">
                        <thead>
                            <tr>
                                <th onclick="sortTable(0)" style="cursor: pointer;" title="Click to sort">Asset <i class="fa-solid fa-sort" style="color: #cbd5e1; margin-left: 4px;"></i></th>
                                <th onclick="sortTable(1)" style="cursor: pointer;" title="Click to sort">Department / Category <i class="fa-solid fa-sort" style="color: #cbd5e1; margin-left: 4px;"></i></th>
                                <th onclick="sortTable(2)" style="cursor: pointer;" title="Click to sort">Vendor / Location <i class="fa-solid fa-sort" style="color: #cbd5e1; margin-left: 4px;"></i></th>
                                <th onclick="sortTable(3)" style="cursor: pointer;" title="Click to sort">Status <i class="fa-solid fa-sort" style="color: #cbd5e1; margin-left: 4px;"></i></th>
                                <th onclick="sortTable(4)" style="cursor: pointer;" title="Click to sort">QR Token <i class="fa-solid fa-sort" style="color: #cbd5e1; margin-left: 4px;"></i></th>
                                <th onclick="sortTable(5)" style="cursor: pointer;" title="Click to sort">Public Live URL <i class="fa-solid fa-sort" style="color: #cbd5e1; margin-left: 4px;"></i></th>
                                <th onclick="sortTable(6)" style="cursor: pointer;" title="Click to sort">Updated <i class="fa-solid fa-sort" style="color: #cbd5e1; margin-left: 4px;"></i></th>
                                <th>Actions</th>
                            </tr>
                        </thead>

                        <tbody>
                            <% for (QrAssetRow row : rows) {
                                boolean hasQr = row.qrPublicToken != null && !row.qrPublicToken.trim().isEmpty();
                                String currentLiveUrl = liveUrl(publicBaseUrl, row.qrPublicToken, row.qrCode);
                            %>
                                <tr>
                                    <td>
                                        <div class="asset-title">
                                            <strong><%= safeText(row.assetCode) %></strong>
                                            <span><%= safeText(row.assetName) %></span>
                                        </div>
                                    </td>

                                    <td>
                                        <div class="asset-title">
                                            <strong><%= safeText(row.departmentName) %></strong>
                                            <span><%= safeText(row.categoryName) %></span>
                                        </div>
                                    </td>

                                    <td>
                                        <div class="asset-title">
                                            <strong><%= safeText(row.vendorName) %></strong>
                                            <span><%= safeText(row.locationName) %></span>
                                        </div>
                                    </td>

                                    <td>
                                        <span class="pill status-<%= safeText(statusClass(row.assetStatus)) %>">
                                            <%= safeText(cleanLabel(row.assetStatus)) %>
                                        </span>
                                    </td>

                                    <td>
                                        <% if (hasQr) { %>
                                            <span class="pill generated" title="<%= safeText(row.qrPublicToken) %>">
                                                <i class="fa-solid fa-circle-check"></i>
                                                &nbsp;<%= safeText(row.qrPublicToken) %>
                                            </span>
                                        <% } else { %>
                                            <span class="pill missing">
                                                <i class="fa-solid fa-clock"></i>
                                                &nbsp;Missing
                                            </span>
                                        <% } %>
                                    </td>

                                    <td>
                                        <% if (!currentLiveUrl.trim().isEmpty()) { %>
                                            <a class="pill" href="<%= safeText(currentLiveUrl) %>" target="_blank" title="<%= safeText(currentLiveUrl) %>" style="text-decoration:none;">
                                                <%= safeText(urlHost(currentLiveUrl)) %>
                                                <i class="fa-solid fa-up-right-from-square" style="font-size:9px;margin-left:4px;"></i>
                                            </a>
                                        <% } else { %>
                                            <span class="pill missing">Not Generated</span>
                                        <% } %>
                                    </td>

                                    <td><%= safeText(row.updatedAt) %></td>

                                    <td>
                                        <div class="hero-actions" style="justify-content:flex-start;">
                                            <a class="action-btn" href="view_asset.jsp?id=<%= safeText(row.assetId) %>">Asset</a>

                                            <% if (hasQr) { %>
                                                <a class="action-btn" href="asset_qr_card.jsp?id=<%= safeText(row.assetId) %>">QR</a>
                                                <a class="action-btn green" href="qr_print.jsp?id=<%= safeText(row.assetId) %>">Print</a>
                                                <% if (!currentLiveUrl.trim().isEmpty()) { %>
                                                    <a class="action-btn primary" target="_blank" href="<%= safeText(currentLiveUrl) %>">Public</a>
                                                <% } %>
                                            <% } %>
                                        </div>
                                    </td>
                                </tr>
                            <% } %>
                        </tbody>
                    </table>
                </div>
            </section>

        </div>
    </main>
</div>

<script src="js/topbar-search.js?v=28000"></script>
<script src="js/user-dropdown.js?v=28000"></script>
<script src="js/sidebar-role.js?v=28000"></script>
<script src="js/ir-body-watermark.js?v=28000"></script>
<script src="js/dashboard-actions.js?v=28000"></script>
<script>
    var sortDirections = [true, true, true, true, true, true, true, true];
    
    function sortTable(columnIndex) {
        var table = document.getElementById("assetTable");
        var tbody = table.querySelector("tbody");
        var rows = Array.from(tbody.querySelectorAll("tr"));
        
        if (rows.length === 0) return;
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

</body>
</html>
