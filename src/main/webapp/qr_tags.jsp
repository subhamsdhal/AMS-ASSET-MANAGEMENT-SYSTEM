<%@page contentType="text/html" pageEncoding="UTF-8"%>
<%@page import="com.mycompany.asset_management_system_ams.DBConnection"%>
<%@page import="java.sql.*"%>
<%@page import="java.util.*"%>
<%@page import="java.net.URLEncoder"%>
<%@page import="jakarta.servlet.http.HttpServletRequest"%>

<%!
    private String safe(Object value) {
        if (value == null) {
            return "-";
        }

        String text = value.toString().trim();

        if (text.isEmpty()) {
            return "-";
        }

        return text
                .replace("&", "&amp;")
                .replace("<", "&lt;")
                .replace(">", "&gt;")
                .replace("\"", "&quot;")
                .replace("'", "&#39;");
    }

    private String get(Map<String, String> data, String key) {
        if (data == null || !data.containsKey(key)) {
            return "-";
        }

        String value = data.get(key);

        if (value == null || value.trim().isEmpty()) {
            return "-";
        }

        return value.trim();
    }

    private String encodeText(String text) {
        try {
            if (text == null) {
                return "";
            }

            return URLEncoder.encode(text, "UTF-8");

        } catch (Exception e) {
            return "";
        }
    }

    private String buildAppBaseUrl(HttpServletRequest request) {
        String scheme = request.getHeader("X-Forwarded-Proto");

        if (scheme == null || scheme.trim().isEmpty()) {
            scheme = request.getScheme();
        }

        String host = request.getHeader("X-Forwarded-Host");

        if (host == null || host.trim().isEmpty()) {
            host = request.getHeader("Host");
        }

        if (host == null || host.trim().isEmpty()) {
            host = request.getServerName();

            int port = request.getServerPort();

            boolean normalHttp = "http".equalsIgnoreCase(scheme) && port == 80;
            boolean normalHttps = "https".equalsIgnoreCase(scheme) && port == 443;

            if (!normalHttp && !normalHttps) {
                host = host + ":" + port;
            }
        }

        return scheme + "://" + host + request.getContextPath();
    }

    private String buildQrIdentity(Map<String, String> asset) {
        String qrToken = get(asset, "qr_public_token");

        if (!"-".equals(qrToken)) {
            return qrToken;
        }

        return "IRAMS-" + get(asset, "asset_code");
    }

    private String officeTypeText(String value) {
        if (value == null || value.trim().isEmpty() || value.trim().equals("-")) {
            return "Headquarters";
        }

        String text = value.trim();

        if ("HQ_OFFICE".equals(text)) {
            return "Headquarters";
        }

        if ("STORE".equals(text)) {
            return "Store";
        }

        if ("CONFERENCE_ROOM".equals(text)) {
            return "Conference Room";
        }

        if ("TRAINING_CENTRE".equals(text)) {
            return "Training Centre";
        }

        if ("WORKSHOP".equals(text)) {
            return "Workshop";
        }

        if ("DEPOT".equals(text)) {
            return "Depot";
        }

        return text.replace("_", " ");
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

    if (!("SUPER_ADMIN".equals(role) || "ADMIN".equals(role))
            && !"ASSET_MANAGER".equalsIgnoreCase(role)) {
        response.sendRedirect("assets.jsp?access=denied");
        return;
    }

    String assetIdParam = request.getParameter("assetId");

    if (assetIdParam == null || assetIdParam.trim().isEmpty()) {
        assetIdParam = request.getParameter("id");
    }

    String codeParam = request.getParameter("code");

    boolean singleAssetMode = false;
    int assetId = 0;

    try {
        if (assetIdParam != null && !assetIdParam.trim().isEmpty()) {
            assetId = Integer.parseInt(assetIdParam.trim());
            singleAssetMode = true;
        }
    } catch (Exception e) {
        assetId = 0;
        singleAssetMode = false;
    }

    if (codeParam != null && !codeParam.trim().isEmpty()) {
        singleAssetMode = true;
    }

    List<Map<String, String>> assetList = new ArrayList<>();

    try (Connection con = DBConnection.getConnection()) {

        String sql;

        if (singleAssetMode) {
            sql = "SELECT * FROM vw_railway_asset_register_card "
                    + "WHERE asset_id = ? "
                    + "OR asset_code = ? "
                    + "OR railway_asset_no = ? "
                    + "OR qr_public_token = ? "
                    + "ORDER BY asset_code";
        } else {
            sql = "SELECT * FROM vw_railway_asset_register_card "
                    + "ORDER BY asset_code";
        }

        try (PreparedStatement ps = con.prepareStatement(sql)) {

            if (singleAssetMode) {
                String cleanCode = codeParam == null ? "" : codeParam.trim();

                ps.setInt(1, assetId);
                ps.setString(2, cleanCode);
                ps.setString(3, cleanCode);
                ps.setString(4, cleanCode);
            }

            try (ResultSet rs = ps.executeQuery()) {
                ResultSetMetaData meta = rs.getMetaData();
                int columnCount = meta.getColumnCount();

                while (rs.next()) {
                    Map<String, String> row = new HashMap<>();

                    for (int i = 1; i <= columnCount; i++) {
                        row.put(meta.getColumnLabel(i), rs.getString(i));
                    }

                    assetList.add(row);
                }
            }
        }

    } catch (Exception e) {
        System.err.println("QR Module DB Error: " + e.getMessage());
    }

    String appBaseUrl = buildAppBaseUrl(request);
%>

<!DOCTYPE html>
<html>
<head>
    <title>IR-AMS QR Tags</title>

    <link rel="stylesheet"
          href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.0/css/all.min.css">

    <link rel="stylesheet" href="css/ir-glass.css?v=28000">
    <link rel="stylesheet" href="css/ams-pro.css?v=28000">
    <link rel="stylesheet" href="css/ir-ams-railway-ui.css?v=28000">
<link rel="stylesheet" href="css/qr_tags.css?v=topbarfix1">
</head>

<body class="railway-ui">

<div class="app">

        <jsp:include page="sidebar.jsp" />

    <main class="main railway-main">

                <jsp:include page="topbar.jsp" />

        <div class="main-scroll-content">

            <section class="qr-tags-hero">
                <h1><%= singleAssetMode ? "Selected Asset QR Tag" : "Railway Asset QR Tags" %></h1>

                <p>
                    <% if (singleAssetMode) { %>
                        Generate and print a professional QR tag for the selected railway asset.
                        The QR opens live public verification details from the IR-AMS database.
                    <% } else { %>
                        Generate printable QR tags for railway assets. Each tag displays official
                        asset identity, section, location and a dynamic QR verification link.
                    <% } %>
                </p>

                <br>

                <div class="hero-pills">
                    <div class="hero-pill">
                        <i class="fa-solid fa-qrcode"></i>
                        <%= singleAssetMode ? "Single QR Tag" : "Bulk QR Tags" %>
                    </div>

                    <div class="hero-pill">
                        <i class="fa-solid fa-mobile-screen-button"></i> Mobile Camera Ready
                    </div>

                    <div class="hero-pill">
                        <i class="fa-solid fa-database"></i> Live Database Verification
                    </div>

                    <div class="hero-pill">
                        <i class="fa-solid fa-building-columns"></i> Rail Sadan HQ Mapping
                    </div>
                </div>
            </section>

            <section class="glass-panel">

                <div class="print-toolbar">
                    <div>
                        <h2>
                            <%= singleAssetMode && !assetList.isEmpty()
                                    ? "Printable QR Tag for " + safe(get(assetList.get(0), "asset_code"))
                                    : "Printable Railway Asset QR Tags" %>
                        </h2>

                        <p class="table-subtext">
                            <% if (singleAssetMode) { %>
                                Showing QR tag for selected asset from live database.
                            <% } else { %>
                                Showing <%= assetList.size() %> QR tags from live asset database.
                            <% } %>
                        </p>
                    </div>

                    <div class="registry-actions">
                        <button class="btn" onclick="window.print()">
                            <i class="fa-solid fa-print"></i> Print QR Tags
                        </button>

                        <% if (singleAssetMode && !assetList.isEmpty()) { %>
                            <a href="asset_register_card.jsp?id=<%= safe(get(assetList.get(0), "asset_id")) %>" class="btn secondary-btn">
                                <i class="fa-solid fa-id-card-clip"></i> Register Card
                            </a>

                            <a href="qr_tags.jsp" class="btn secondary-btn">
                                <i class="fa-solid fa-qrcode"></i> Show All QR
                            </a>
                        <% } else { %>
                            <a href="assets.jsp" class="btn">
                                <i class="fa-solid fa-arrow-left"></i> Back to Assets
                            </a>
                        <% } %>
                    </div>
                </div>

                <% if (assetList.isEmpty()) { %>

                    <div class="empty-state">
                        <i class="fa-solid fa-triangle-exclamation"></i>
                        No asset records found for QR tag generation.
                    </div>

                <% } else { %>

                    <div class="qr-card-grid <%= singleAssetMode ? "single-qr-grid" : "" %>">

                        <%
                            for (Map<String, String> asset : assetList) {

                                String qrIdentity = buildQrIdentity(asset);

                                String qrTargetUrl = appBaseUrl
                                        + "/public_scan_result.jsp?qr="
                                        + encodeText(qrIdentity);

                                String encodedQrTargetUrl = encodeText(qrTargetUrl);
                        %>

                        <div class="railway-qr-tag">

                            <div class="qr-tag-header">
                                <img src="images/indian-railway-logo.png" alt="Indian Railway Logo">

                                <div>
                                    <h3>IR-AMS</h3>
                                    <span>East Coast Railway</span>
                                </div>
                            </div>

                            <img class="qr-image"
                                 src="https://api.qrserver.com/v1/create-qr-code/?size=260x260&data=<%= encodedQrTargetUrl %>"
                                 alt="Asset QR Code">

                            <div class="asset-main-title">
                                <h2><%= safe(get(asset, "asset_name")) %></h2>
                                <p><%= safe(get(asset, "category_name")) %></p>
                            </div>

                            <table class="qr-info-table">
                                <tr>
                                    <td>Asset Code</td>
                                    <td><%= safe(get(asset, "asset_code")) %></td>
                                </tr>

                                <tr>
                                    <td>Railway Asset No.</td>
                                    <td><%= safe(get(asset, "railway_asset_no")) %></td>
                                </tr>

                                <tr>
                                    <td>Office Type</td>
                                    <td><%= safe(officeTypeText(get(asset, "office_type_code"))) %></td>
                                </tr>

                                <tr>
                                    <td>Office</td>
                                    <td><%= safe(get(asset, "office_name")) %></td>
                                </tr>

                                <tr>
                                    <td>Section</td>
                                    <td><%= safe(get(asset, "section_name")) %></td>
                                </tr>

                                <tr>
                                    <td>Location</td>
                                    <td><%= safe(get(asset, "location_name")) %></td>
                                </tr>
                            </table>

                            <div class="qr-token-strip">
                                <i class="fa-solid fa-qrcode"></i>
                                <%= safe(qrIdentity) %>
                            </div>

                            <div class="scan-note">
                                Scan to verify live railway asset details from IR-AMS.
                            </div>

                        </div>

                        <%
                            }
                        %>

                    </div>

                <% } %>

            </section>

        </div>

    </main>

</div>
<script>
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
</script>

<script src="js/topbar-search.js?v=28000"></script>
<script src="js/user-dropdown.js?v=28000"></script>
<script src="js/sidebar-role.js?v=28000"></script>
<script src="js/ir-body-watermark.js?v=28000"></script>
<script src="js/dashboard-actions.js?v=28000"></script>

</body>
</html>