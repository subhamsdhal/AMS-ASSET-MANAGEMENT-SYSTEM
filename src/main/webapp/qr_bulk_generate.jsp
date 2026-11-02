<%@page contentType="text/html" pageEncoding="UTF-8"%>
<%@page import="com.mycompany.asset_management_system_ams.DBConnection"%>
<%@page import="java.sql.*"%>
<%@page import="java.util.*"%>

<%!
    public String formatNumber(int number) {
        if (number >= 100000) {
            return String.format("%.1fL", number / 100000.0);
        } else if (number >= 1000) {
            return String.format("%.1fK", number / 1000.0);
        }
        return String.valueOf(number);
    }

    public static class AssetQrRow {
        String assetId = "";
        String assetCode = "";
        String assetName = "";
        String categoryName = "";
        String departmentName = "";
        String assetStatus = "";
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

    private String statusClass(String status) {
        if (status == null || status.trim().isEmpty()) {
            return "UNKNOWN";
        }

        return status.trim().toUpperCase(Locale.ENGLISH).replace(" ", "_");
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

    boolean canManageQr = ("SUPER_ADMIN".equals(role) || "ADMIN".equals(role))
            || "ASSET_MANAGER".equals(role);

    if (!canManageQr) {
        response.sendRedirect("dashboard.jsp?access=denied");
        return;
    }

    String q = request.getParameter("q");
    String qrFilter = request.getParameter("qr");
    String msg = request.getParameter("msg");
    String error = request.getParameter("error");
    String count = request.getParameter("count");

    if (q == null) {
        q = "";
    }

    if (qrFilter == null || qrFilter.trim().isEmpty()) {
        qrFilter = "MISSING";
    }

    q = q.trim();
    qrFilter = qrFilter.trim().toUpperCase(Locale.ENGLISH);

    String userInitial = username.substring(0, Math.min(2, username.length())).toUpperCase(Locale.ENGLISH);

    int totalAssets = 0;
    int generatedAssets = 0;
    int missingAssets = 0;
    int filteredCount = 0;

    List<AssetQrRow> rows = new ArrayList<AssetQrRow>();

    try (Connection con = DBConnection.getConnection()) {
        totalAssets = countRows(con, "SELECT COUNT(*) FROM assets");

        generatedAssets = countRows(con,
                "SELECT COUNT(*) FROM assets "
                + "WHERE qr_public_token IS NOT NULL AND TRIM(qr_public_token) <> ''");

        missingAssets = totalAssets - generatedAssets;

        StringBuilder sql = new StringBuilder();

        sql.append("SELECT ")
                .append("a.asset_id, a.asset_code, a.asset_name, a.asset_status, ")
                .append("a.qr_public_token, a.qr_code, ")
                .append("DATE_FORMAT(a.updated_at, '%d %b %Y, %h:%i %p') AS updated_at, ")
                .append("COALESCE(ac.category_name, 'Uncategorized') AS category_name, ")
                .append("COALESCE(d.department_name, 'Unassigned') AS department_name ")
                .append("FROM assets a ")
                .append("LEFT JOIN asset_categories ac ON a.category_id = ac.category_id ")
                .append("LEFT JOIN departments d ON a.department_id = d.department_id ")
                .append("WHERE 1 = 1 ");

        List<String> params = new ArrayList<String>();

        if ("MISSING".equals(qrFilter)) {
            sql.append("AND (a.qr_public_token IS NULL OR TRIM(a.qr_public_token) = '') ");
        } else if ("GENERATED".equals(qrFilter)) {
            sql.append("AND (a.qr_public_token IS NOT NULL AND TRIM(a.qr_public_token) <> '') ");
        }

        if (!q.isEmpty()) {
            sql.append("AND (a.asset_code LIKE ? OR a.asset_name LIKE ? OR ac.category_name LIKE ? OR d.department_name LIKE ? OR a.qr_public_token LIKE ?) ");

            String searchValue = "%" + q + "%";

            for (int i = 0; i < 5; i++) {
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
                    AssetQrRow row = new AssetQrRow();

                    row.assetId = rs.getString("asset_id");
                    row.assetCode = rs.getString("asset_code");
                    row.assetName = rs.getString("asset_name");
                    row.categoryName = rs.getString("category_name");
                    row.departmentName = rs.getString("department_name");
                    row.assetStatus = rs.getString("asset_status");
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
    <title>Bulk QR Generation - IR-AMS</title>

    <link rel="stylesheet"
          href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.0/css/all.min.css">

    <link rel="stylesheet" href="css/ir-glass.css?v=28000">
    <link rel="stylesheet" href="css/ams-pro.css?v=28000">
    <link rel="stylesheet" href="css/ir-ams-railway-ui.css?v=28000">
<link rel="stylesheet" href="css/qr_bulk_generate.css?v=topbarfix1">
</head>

<body class="railway-ui">
<div class="app ams-shell">

        <jsp:include page="sidebar.jsp" />

    <main class="main railway-main">
                <jsp:include page="topbar.jsp" />

        <div class="main-scroll-content bulk-board">

            <section class="bulk-hero">
                <div>
                    <h1>Bulk QR Generation</h1>
                    <p>
                        Generate missing dynamic QR tokens for multiple railway assets.
                        QR stores only the live public URL, so printed labels stay updated from database.
                    </p>
                </div>

                <div class="hero-actions">
                    <form method="post" action="BulkGenerateAssetQrServlet" style="margin:0;"
                          onsubmit="return confirm('Generate QR for all missing assets?');">
                        <input type="hidden" name="mode" value="missing">
                        <button class="action-btn primary" type="submit">
                            <i class="fa-solid fa-wand-magic-sparkles"></i>
                            Generate All Missing
                        </button>
                    </form>

                    <a href="qr_control_center.jsp" class="action-btn">
                        <i class="fa-solid fa-arrow-left"></i>
                        QR Control Center
                    </a>

                    <a href="qr_print.jsp" class="action-btn green">
                        <i class="fa-solid fa-print"></i>
                        Print Labels
                    </a>
                </div>
            </section>

            <% if ("bulk_generated".equals(msg)) { %>
                <div class="message-success">
                    <i class="fa-solid fa-circle-check"></i>
                    QR generated successfully for <%= safeText(count) %> asset(s).
                </div>
            <% } %>

            <% if ("none_selected".equals(error)) { %>
                <div class="message-error">
                    <i class="fa-solid fa-triangle-exclamation"></i>
                    No asset selected. Please select at least one asset.
                </div>
            <% } %>

            <% if ("public_base_url".equals(error)) { %>
                <div class="message-error">
                    <i class="fa-solid fa-triangle-exclamation"></i>
                    Set a non-localhost public QR base URL in Settings or QR Control Center before generating QR codes.
                </div>
            <% } %>

            <section class="kpi-grid">
                <div class="kpi-card">
                    <div class="kpi-icon"><i class="fa-solid fa-cubes"></i></div>
                    <h3>Total Assets</h3>
                    <p><%= totalAssets %></p>
                </div>

                <div class="kpi-card">
                    <div class="kpi-icon"><i class="fa-solid fa-qrcode"></i></div>
                    <h3>QR Generated</h3>
                    <p><%= generatedAssets %></p>
                </div>

                <div class="kpi-card">
                    <div class="kpi-icon"><i class="fa-solid fa-hourglass-half"></i></div>
                    <h3>QR Missing</h3>
                    <p><%= missingAssets %></p>
                </div>
            </section>

            <section class="panel">
                <div class="toolbar">
                    <div>
                        <h2>Asset QR Token Register</h2>
                        <p class="table-subtext">
                            Showing <%= filteredCount %> matching assets. Maximum 300 records shown.
                        </p>
                    </div>

                    <form class="filter-form" method="get" action="qr_bulk_generate.jsp">
                        <input class="filter-input"
                               type="text"
                               name="q"
                               value="<%= q.isEmpty() ? "" : safeText(q) %>"
                               placeholder="Search asset, category, department, token...">

                        <select class="filter-select" name="qr">
                            <option value="MISSING" <%= "MISSING".equals(qrFilter) ? "selected" : "" %>>QR Missing</option>
                            <option value="GENERATED" <%= "GENERATED".equals(qrFilter) ? "selected" : "" %>>QR Generated</option>
                            <option value="ALL" <%= "ALL".equals(qrFilter) ? "selected" : "" %>>All Assets</option>
                        </select>

                        <button class="action-btn primary" type="submit">
                            <i class="fa-solid fa-filter"></i>
                            Filter
                        </button>

                        <a class="action-btn" href="qr_bulk_generate.jsp">
                            <i class="fa-solid fa-rotate-right"></i>
                            Reset
                        </a>
                    </form>
                </div>

                <form method="post" action="BulkGenerateAssetQrServlet"
                      onsubmit="return confirm('Generate or refresh QR for selected assets?');">

                    <input type="hidden" name="mode" value="selected">

                    <div class="toolbar">
                        <div class="table-subtext">
                            Select assets below, then click Generate Selected.
                        </div>

                        <button class="action-btn primary" type="submit">
                            <i class="fa-solid fa-qrcode"></i>
                            Generate Selected
                        </button>
                    </div>

                    <div class="table-wrap">
                        <table class="asset-table">
                            <thead>
                                <tr>
                                    <th>Select</th>
                                    <th>Asset</th>
                                    <th>Category</th>
                                    <th>Department</th>
                                    <th>Status</th>
                                    <th>QR Token</th>
                                    <th>QR URL Field</th>
                                    <th>Updated</th>
                                    <th>Open</th>
                                </tr>
                            </thead>

                            <tbody>
                                <% for (AssetQrRow row : rows) {
                                    boolean hasQr = row.qrPublicToken != null && !row.qrPublicToken.trim().isEmpty();
                                %>
                                    <tr>
                                        <td class="checkbox-cell">
                                            <input type="checkbox" name="asset_ids" value="<%= safeText(row.assetId) %>">
                                        </td>

                                        <td>
                                            <div class="asset-title">
                                                <strong><%= safeText(row.assetCode) %></strong>
                                                <span><%= safeText(row.assetName) %></span>
                                            </div>
                                        </td>

                                        <td><%= safeText(row.categoryName) %></td>

                                        <td><%= safeText(row.departmentName) %></td>

                                        <td>
                                            <span class="pill">
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
                                            <span class="pill" title="<%= safeText(row.qrCode) %>">
                                                <%= safeText(row.qrCode) %>
                                            </span>
                                        </td>

                                        <td><%= safeText(row.updatedAt) %></td>

                                        <td>
                                            <a class="action-btn" href="view_asset.jsp?id=<%= safeText(row.assetId) %>">
                                                Asset
                                            </a>
                                        </td>
                                    </tr>
                                <% } %>
                            </tbody>
                        </table>
                    </div>
                </form>
            </section>

        </div>
    </main>
</div>

<script>
    (function () {
        var firstCheckbox = document.querySelector('input[name="asset_ids"]');

        if (firstCheckbox) {
            firstCheckbox.addEventListener("dblclick", function () {
                var boxes = document.querySelectorAll('input[name="asset_ids"]');
                boxes.forEach(function (box) {
                    box.checked = true;
                });
            });
        }
    })();
</script>

<script src="js/topbar-search.js?v=28000"></script>
<script src="js/user-dropdown.js?v=28000"></script>
<script src="js/sidebar-role.js?v=28000"></script>
<script src="js/ir-body-watermark.js?v=28000"></script>
<script src="js/dashboard-actions.js?v=28000"></script>

</body>
</html>
