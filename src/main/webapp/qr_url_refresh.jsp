<%@page contentType="text/html" pageEncoding="UTF-8"%>
<%@page import="com.mycompany.asset_management_system_ams.DBConnection"%>
<%@page import="com.mycompany.asset_management_system_ams.QrUrlUtil"%>
<%@page import="java.sql.*"%>
<%@page import="java.util.*"%>
<%@page import="jakarta.servlet.http.HttpServletRequest"%>

<%!
    public String formatNumber(int number) {
        if (number >= 100000) {
            return String.format("%.1fL", number / 100000.0);
        } else if (number >= 1000) {
            return String.format("%.1fK", number / 1000.0);
        }
        return String.valueOf(number);
    }

    public static class QrUrlRow {
        String assetId = "";
        String assetCode = "";
        String assetName = "";
        String departmentName = "";
        String assetStatus = "";
        String qrPublicToken = "";
        String currentQrCode = "";
        String expectedQrCode = "";
        String updatedAt = "";
        boolean correctUrl = false;
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

    private String expectedUrl(String baseUrl, String token) {
        if (token == null || token.trim().isEmpty()) {
            return "";
        }

        return baseUrl + "/public_asset_view.jsp?token=" + token.trim();
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

    private int countPrepared(Connection con, String sql, String value) {
        try (PreparedStatement ps = con.prepareStatement(sql)) {
            ps.setString(1, value);

            try (ResultSet rs = ps.executeQuery()) {
                if (rs.next()) {
                    return rs.getInt(1);
                }
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
    String urlFilter = request.getParameter("url");
    String msg = request.getParameter("msg");
    String error = request.getParameter("error");
    String count = request.getParameter("count");

    if (q == null) {
        q = "";
    }

    if (urlFilter == null || urlFilter.trim().isEmpty()) {
        urlFilter = "MISMATCH";
    }

    q = q.trim();
    urlFilter = urlFilter.trim().toUpperCase(Locale.ENGLISH);

    String baseUrl = QrUrlUtil.getConfiguredPublicBaseUrl();
    String userInitial = username.substring(0, Math.min(2, username.length())).toUpperCase(Locale.ENGLISH);

    int totalAssets = 0;
    int tokenGenerated = 0;
    int tokenMissing = 0;
    int urlCorrect = 0;
    int urlMismatch = 0;
    int filteredCount = 0;

    List<QrUrlRow> rows = new ArrayList<QrUrlRow>();

    try (Connection con = DBConnection.getConnection()) {
        totalAssets = countRows(con, "SELECT COUNT(*) FROM assets");

        tokenGenerated = countRows(con,
                "SELECT COUNT(*) FROM assets "
                + "WHERE qr_public_token IS NOT NULL AND TRIM(qr_public_token) <> ''");

        tokenMissing = totalAssets - tokenGenerated;

        urlCorrect = countPrepared(con,
                "SELECT COUNT(*) FROM assets "
                + "WHERE qr_public_token IS NOT NULL AND TRIM(qr_public_token) <> '' "
                + "AND qr_code = CONCAT(?, '/public_asset_view.jsp?token=', qr_public_token)",
                baseUrl);

        urlMismatch = countPrepared(con,
                "SELECT COUNT(*) FROM assets "
                + "WHERE qr_public_token IS NOT NULL AND TRIM(qr_public_token) <> '' "
                + "AND (qr_code IS NULL OR TRIM(qr_code) = '' "
                + "OR qr_code <> CONCAT(?, '/public_asset_view.jsp?token=', qr_public_token))",
                baseUrl);

        StringBuilder sql = new StringBuilder();

        sql.append("SELECT ")
                .append("a.asset_id, a.asset_code, a.asset_name, a.asset_status, ")
                .append("a.qr_public_token, a.qr_code, ")
                .append("DATE_FORMAT(a.updated_at, '%d %b %Y, %h:%i %p') AS updated_at, ")
                .append("COALESCE(d.department_name, 'Unassigned') AS department_name ")
                .append("FROM assets a ")
                .append("LEFT JOIN departments d ON a.department_id = d.department_id ")
                .append("WHERE a.qr_public_token IS NOT NULL AND TRIM(a.qr_public_token) <> '' ");

        List<String> params = new ArrayList<String>();

        if ("MISMATCH".equals(urlFilter)) {
            sql.append("AND (a.qr_code IS NULL OR TRIM(a.qr_code) = '' ")
                    .append("OR a.qr_code <> CONCAT(?, '/public_asset_view.jsp?token=', a.qr_public_token)) ");
            params.add(baseUrl);
        } else if ("CORRECT".equals(urlFilter)) {
            sql.append("AND a.qr_code = CONCAT(?, '/public_asset_view.jsp?token=', a.qr_public_token) ");
            params.add(baseUrl);
        }

        if (!q.isEmpty()) {
            sql.append("AND (a.asset_code LIKE ? OR a.asset_name LIKE ? OR d.department_name LIKE ? ")
                    .append("OR a.qr_public_token LIKE ? OR a.qr_code LIKE ?) ");

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
                    QrUrlRow row = new QrUrlRow();

                    row.assetId = rs.getString("asset_id");
                    row.assetCode = rs.getString("asset_code");
                    row.assetName = rs.getString("asset_name");
                    row.departmentName = rs.getString("department_name");
                    row.assetStatus = rs.getString("asset_status");
                    row.qrPublicToken = rs.getString("qr_public_token");
                    row.currentQrCode = rs.getString("qr_code");
                    row.updatedAt = rs.getString("updated_at");
                    row.expectedQrCode = expectedUrl(baseUrl, row.qrPublicToken);
                    row.correctUrl = row.expectedQrCode.equals(row.currentQrCode == null ? "" : row.currentQrCode.trim());

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
    <title>QR URL Refresh - IR-AMS</title>

    <link rel="stylesheet"
          href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.0/css/all.min.css">

    <link rel="stylesheet" href="css/ir-glass.css?v=28000">
    <link rel="stylesheet" href="css/ams-pro.css?v=28000">
    <link rel="stylesheet" href="css/ir-ams-railway-ui.css?v=28000">
<link rel="stylesheet" href="css/qr_url_refresh.css?v=topbarfix1">
</head>

<body class="railway-ui">
<div class="app ams-shell">

        <jsp:include page="sidebar.jsp" />

    <main class="main railway-main">
                <jsp:include page="topbar.jsp" />

        <div class="main-scroll-content refresh-board">

            <section class="refresh-hero">
                <div>
                    <h1>QR URL Refresh</h1>
                    <p>
                        Refresh stored QR URL field for localhost, Cloudflare tunnel, Render deployment,
                        or changed public domain. Token remains same; only the stored public URL is corrected.
                    </p>
                </div>

                <div class="hero-actions">
                    <form method="post" action="RefreshAssetQrUrlsServlet" style="margin:0;"
                          onsubmit="return confirm('Refresh stored QR URLs for all mismatched assets using current base URL?');">
                        <input type="hidden" name="mode" value="mismatch">
                        <button class="action-btn primary" type="submit">
                            <i class="fa-solid fa-arrows-rotate"></i>
                            Refresh All Mismatched
                        </button>
                    </form>

                    <a href="qr_system_health.jsp" class="action-btn">
                        <i class="fa-solid fa-heart-pulse"></i>
                        System Health
                    </a>

                    <a href="qr_control_center.jsp" class="action-btn">
                        <i class="fa-solid fa-arrow-left"></i>
                        Control Center
                    </a>
                </div>
            </section>

            <% if ("refreshed".equals(msg)) { %>
                <div class="message-success">
                    <i class="fa-solid fa-circle-check"></i>
                    QR URL refreshed successfully for <%= safeText(count) %> asset(s).
                </div>
            <% } %>

            <% if ("none_selected".equals(error)) { %>
                <div class="message-error">
                    <i class="fa-solid fa-triangle-exclamation"></i>
                    No asset selected. Please select at least one asset.
                </div>
            <% } %>

            <% if ("failed".equals(error)) { %>
                <div class="message-error">
                    <i class="fa-solid fa-triangle-exclamation"></i>
                    QR URL refresh failed. Please check server console.
                </div>
            <% } %>

            <% if ("public_base_url".equals(error)) { %>
                <div class="message-error">
                    <i class="fa-solid fa-triangle-exclamation"></i>
                    Set a non-localhost public QR base URL in Settings or QR Control Center before refreshing QR URLs.
                </div>
            <% } %>

            <section class="panel">
                <h2 style="margin:0 0 12px 0;color:#08348f;font-size:17px;font-weight:950;text-transform:uppercase;">
                    Configured Public QR Base URL
                </h2>

                <div class="current-base-box">
                    <strong>Public Base:</strong><br>
                    <%= safeText(baseUrl) %>
                    <br><br>
                    All QR URL fields should follow:
                    <br>
                    <%= safeText(baseUrl) %>/public_asset_view.jsp?token=ASSET_TOKEN
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
                    <h3>Token Generated</h3>
                    <p><%= tokenGenerated %></p>
                </div>

                <div class="kpi-card">
                    <div class="kpi-icon"><i class="fa-solid fa-hourglass-half"></i></div>
                    <h3>Token Missing</h3>
                    <p><%= tokenMissing %></p>
                </div>

                <div class="kpi-card">
                    <div class="kpi-icon"><i class="fa-solid fa-circle-check"></i></div>
                    <h3>URL Correct</h3>
                    <p><%= urlCorrect %></p>
                </div>

                <div class="kpi-card">
                    <div class="kpi-icon"><i class="fa-solid fa-link-slash"></i></div>
                    <h3>URL Mismatch</h3>
                    <p><%= urlMismatch %></p>
                </div>
            </section>

            <section class="panel">
                <div class="toolbar">
                    <div>
                        <h2>QR URL Register</h2>
                        <p class="table-subtext">Showing <%= filteredCount %> matching assets. Maximum 300 records shown.</p>
                    </div>

                    <form class="filter-form" method="get" action="qr_url_refresh.jsp">
                        <input class="filter-input"
                               type="text"
                               name="q"
                               value="<%= q.isEmpty() ? "" : safeText(q) %>"
                               placeholder="Search asset, department, token, URL...">

                        <select class="filter-select" name="url">
                            <option value="MISMATCH" <%= "MISMATCH".equals(urlFilter) ? "selected" : "" %>>URL Mismatch</option>
                            <option value="CORRECT" <%= "CORRECT".equals(urlFilter) ? "selected" : "" %>>URL Correct</option>
                            <option value="ALL" <%= "ALL".equals(urlFilter) ? "selected" : "" %>>All Token Assets</option>
                        </select>

                        <button class="action-btn primary" type="submit">
                            <i class="fa-solid fa-filter"></i>
                            Filter
                        </button>

                        <a class="action-btn" href="qr_url_refresh.jsp">
                            <i class="fa-solid fa-rotate-right"></i>
                            Reset
                        </a>
                    </form>
                </div>

                <form method="post" action="RefreshAssetQrUrlsServlet"
                      onsubmit="return confirm('Refresh stored QR URL for selected assets?');">

                    <input type="hidden" name="mode" value="selected">

                    <div class="toolbar">
                        <div class="table-subtext">
                            Select assets below, then click Refresh Selected.
                        </div>

                        <button class="action-btn primary" type="submit">
                            <i class="fa-solid fa-link"></i>
                            Refresh Selected
                        </button>
                    </div>

                    <div class="table-wrap">
                        <table class="asset-table">
                            <thead>
                                <tr>
                                    <th>Select</th>
                                    <th>Asset</th>
                                    <th>Department</th>
                                    <th>Status</th>
                                    <th>QR Token</th>
                                    <th>Stored QR URL</th>
                                    <th>Expected QR URL</th>
                                    <th>URL Status</th>
                                    <th>Open</th>
                                </tr>
                            </thead>

                            <tbody>
                                <% for (QrUrlRow row : rows) { %>
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

                                        <td><%= safeText(row.departmentName) %></td>

                                        <td>
                                            <span class="pill status-<%= safeText(statusClass(row.assetStatus)) %>">
                                                <%= safeText(cleanLabel(row.assetStatus)) %>
                                            </span>
                                        </td>

                                        <td>
                                            <span class="pill" title="<%= safeText(row.qrPublicToken) %>">
                                                <%= safeText(row.qrPublicToken) %>
                                            </span>
                                        </td>

                                        <td>
                                            <span class="pill" title="<%= safeText(row.currentQrCode) %>">
                                                <%= safeText(row.currentQrCode) %>
                                            </span>
                                        </td>

                                        <td>
                                            <span class="pill" title="<%= safeText(row.expectedQrCode) %>">
                                                <%= safeText(row.expectedQrCode) %>
                                            </span>
                                        </td>

                                        <td>
                                            <% if (row.correctUrl) { %>
                                                <span class="pill good">
                                                    <i class="fa-solid fa-circle-check"></i>
                                                    &nbsp;Correct
                                                </span>
                                            <% } else { %>
                                                <span class="pill warn">
                                                    <i class="fa-solid fa-triangle-exclamation"></i>
                                                    &nbsp;Mismatch
                                                </span>
                                            <% } %>
                                        </td>

                                        <td>
                                            <div class="hero-actions" style="justify-content:flex-start;">
                                                <a class="action-btn" href="view_asset.jsp?id=<%= safeText(row.assetId) %>">Asset</a>
                                                <a class="action-btn primary" target="_blank" href="<%= safeText(row.expectedQrCode) %>">Public</a>
                                            </div>
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
