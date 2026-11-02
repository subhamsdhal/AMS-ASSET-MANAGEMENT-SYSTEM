<%@page contentType="text/html" pageEncoding="UTF-8"%>
<%@page import="com.mycompany.asset_management_system_ams.DBConnection"%>
<%@page import="com.mycompany.asset_management_system_ams.QrUrlUtil"%>
<%@page import="java.sql.*"%>
<%@page import="java.util.*"%>
<%@page import="java.net.URLEncoder"%>
<%@page import="jakarta.servlet.http.HttpServletRequest"%>

<%!
    public static class LabelRow {
        String assetId = "";
        String assetCode = "";
        String assetName = "";
        String categoryName = "";
        String departmentName = "";
        String locationName = "";
        String assetStatus = "";
        String token = "";
        String qrCode = "";
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

    private String finalToken(String token, String qrCode) {
        if (token != null && !token.trim().isEmpty()) {
            return token.trim();
        }

        if (qrCode != null && !qrCode.trim().isEmpty()) {
            return qrCode.trim();
        }

        return "";
    }

    private String liveUrl(String publicBaseUrl, String token, String qrCode) {
        String value = finalToken(token, qrCode);

        if (value.isEmpty() || publicBaseUrl == null || publicBaseUrl.trim().isEmpty()) {
            return "";
        }

        return publicBaseUrl.trim() + "/public_asset_view.jsp?token=" + value;
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

    boolean canPrintQrLabels = ("SUPER_ADMIN".equals(role) || "ADMIN".equals(role))
            || "ASSET_MANAGER".equals(role)
            || "AUDITOR".equals(role);

    if (!canPrintQrLabels) {
        response.sendRedirect("dashboard.jsp?access=denied");
        return;
    }

    String q = request.getParameter("q");
    String qrFilter = request.getParameter("qr");
    String statusFilter = request.getParameter("status");
    String assetId = request.getParameter("asset_id");

    if (assetId == null || assetId.trim().isEmpty()) {
        assetId = request.getParameter("id");
    }

    if (q == null) {
        q = "";
    }

    if (qrFilter == null || qrFilter.trim().isEmpty()) {
        qrFilter = "GENERATED";
    }

    if (statusFilter == null || statusFilter.trim().isEmpty()) {
        statusFilter = "ALL";
    }

    q = q.trim();
    qrFilter = qrFilter.trim().toUpperCase(Locale.ENGLISH);
    statusFilter = statusFilter.trim().toUpperCase(Locale.ENGLISH);

    List<LabelRow> rows = new ArrayList<LabelRow>();

    try (Connection con = DBConnection.getConnection()) {
        StringBuilder sql = new StringBuilder();

        sql.append("SELECT ")
                .append("a.asset_id, a.asset_code, a.asset_name, a.asset_status, ")
                .append("a.qr_public_token, a.qr_code, ")
                .append("COALESCE(ac.category_name, 'Uncategorized') AS category_name, ")
                .append("COALESCE(d.department_name, 'Unassigned') AS department_name, ")
                .append("COALESCE(rl.location_name, a.location, 'Not Mentioned') AS location_name ")
                .append("FROM assets a ")
                .append("LEFT JOIN asset_categories ac ON a.category_id = ac.category_id ")
                .append("LEFT JOIN departments d ON a.department_id = d.department_id ")
                .append("LEFT JOIN railway_locations rl ON a.location_id = rl.location_id ")
                .append("WHERE 1 = 1 ");

        List<String> params = new ArrayList<String>();

        if (assetId != null && !assetId.trim().isEmpty()) {
            sql.append("AND a.asset_id = ? ");
            params.add(assetId.trim());
        } else {
            sql.append("AND (")
                    .append("(a.qr_public_token IS NOT NULL AND TRIM(a.qr_public_token) <> '') ")
                    .append("OR (a.qr_code IS NOT NULL AND TRIM(a.qr_code) <> '')")
                    .append(") ");

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
                        .append("OR rl.location_name LIKE ? ")
                        .append("OR a.qr_public_token LIKE ? ")
                        .append("OR a.qr_code LIKE ? ")
                        .append(") ");

                String searchValue = "%" + q + "%";

                for (int i = 0; i < 7; i++) {
                    params.add(searchValue);
                }
            }
        }

        sql.append("ORDER BY a.asset_code ASC LIMIT 120");

        try (PreparedStatement ps = con.prepareStatement(sql.toString())) {
            for (int i = 0; i < params.size(); i++) {
                ps.setString(i + 1, params.get(i));
            }

            try (ResultSet rs = ps.executeQuery()) {
                while (rs.next()) {
                    LabelRow row = new LabelRow();

                    row.assetId = rs.getString("asset_id");
                    row.assetCode = rs.getString("asset_code");
                    row.assetName = rs.getString("asset_name");
                    row.categoryName = rs.getString("category_name");
                    row.departmentName = rs.getString("department_name");
                    row.locationName = rs.getString("location_name");
                    row.assetStatus = rs.getString("asset_status");
                    row.token = rs.getString("qr_public_token");
                    row.qrCode = rs.getString("qr_code");

                    rows.add(row);
                }
            }
        }

    } catch (Exception e) {
        System.err.println("QR Module DB Error: " + e.getMessage());
    }

    String publicBaseUrl = QrUrlUtil.getConfiguredPublicBaseUrl();
    String userInitial = username.substring(0, Math.min(2, username.length())).toUpperCase(Locale.ENGLISH);
%>

<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>QR Label Print - IR-AMS</title>

    <link rel="stylesheet"
          href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.0/css/all.min.css">

    <link rel="stylesheet" href="css/qr_print_labels.css?v=28000">
</head>

<body>
    <div class="no-print">
        <div class="toolbar">
            <div>
                <h1>IR-AMS QR Label Print</h1>
                <p>
                    User: <%= safeText(username) %> &middot; Role: <%= safeText(cleanLabel(role)) %> &middot;
                    Labels loaded: <%= rows.size() %>
                </p>
            </div>

            <div class="btn-row">
                <button class="btn primary" onclick="window.print();">
                    <i class="fa-solid fa-print"></i>
                    Print Labels
                </button>

                <a class="btn" href="qr_asset_register.jsp">
                    <i class="fa-solid fa-table-list"></i>
                    QR Register
                </a>

                <a class="btn" href="qr_control_center.jsp">
                    <i class="fa-solid fa-arrow-left"></i>
                    Control Center
                </a>
            </div>
        </div>
    </div>

    <main class="print-area">
        <% if (rows.isEmpty()) { %>
            <div class="empty">
                <i class="fa-solid fa-qrcode"></i>
                <strong>No printable QR label found</strong>
                <span>Generate QR tokens first, then open this print page again.</span>
            </div>
        <% } else { %>
            <section class="label-grid">
                <% for (LabelRow row : rows) {
                    String currentLiveUrl = liveUrl(publicBaseUrl, row.token, row.qrCode);
                    String currentToken = finalToken(row.token, row.qrCode);
                    String qrImageUrl = currentLiveUrl.trim().isEmpty()
                            ? ""
                            : "https://api.qrserver.com/v1/create-qr-code/?size=260x260&margin=10&data="
                            + URLEncoder.encode(currentLiveUrl, "UTF-8");
                %>
                    <article class="asset-label">
                        <div class="qr-side">
                            <% if (qrImageUrl.trim().isEmpty()) { %>
                                <div class="empty" style="min-height:160px;padding:12px;">
                                    <i class="fa-solid fa-triangle-exclamation"></i>
                                    <span>Set public QR base URL before printing.</span>
                                </div>
                            <% } else { %>
                                <img src="<%= qrImageUrl %>" alt="QR">
                            <% } %>
                            <strong><%= safeText(row.assetCode) %></strong>
                        </div>

                        <div class="label-info">
                            <div class="org">
                                <h2>East Coast Railway</h2>
                                <span>Indian Railways &middot; Asset Management System</span>
                            </div>

                            <div class="field">
                                <b>Asset</b>
                                <span><%= safeText(row.assetName) %></span>
                            </div>

                            <div class="field">
                                <b>Code</b>
                                <span><%= safeText(row.assetCode) %></span>
                            </div>

                            <div class="field">
                                <b>Category</b>
                                <span><%= safeText(row.categoryName) %></span>
                            </div>

                            <div class="field">
                                <b>Dept.</b>
                                <span><%= safeText(row.departmentName) %></span>
                            </div>

                            <div class="field">
                                <b>Location</b>
                                <span><%= safeText(row.locationName) %></span>
                            </div>

                            <div class="field">
                                <b>Status</b>
                                <span class="status-pill"><%= safeText(cleanLabel(row.assetStatus)) %></span>
                            </div>

                            <div class="field">
                                <b>Token</b>
                                <span><%= safeText(currentToken) %></span>
                            </div>

                            <div class="footer-line">
                                Scan QR to view live database record. If asset details are updated later,
                                this printed QR will show the latest information automatically.
                            </div>
                        </div>
                    </article>
                <% } %>
            </section>
        <% } %>
    </main>
</body>
</html>
