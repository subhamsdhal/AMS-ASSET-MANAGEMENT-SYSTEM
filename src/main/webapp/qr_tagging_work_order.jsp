<%@page contentType="text/html" pageEncoding="UTF-8"%>
<%@page import="com.mycompany.asset_management_system_ams.DBConnection"%>
<%@page import="com.mycompany.asset_management_system_ams.QrUrlUtil"%>
<%@page import="java.sql.*"%>
<%@page import="java.util.*"%>
<%@page import="java.net.URLEncoder"%>
<%@page import="jakarta.servlet.http.HttpServletRequest"%>

<%!
    public static class WorkRow {
        String assetId = "";
        String assetCode = "";
        String assetName = "";
        String departmentName = "";
        String categoryName = "";
        String locationName = "";
        String token = "";
        String qrUrl = "";
        String printStatus = "";
        String tagStatus = "";
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

    private void ensureTaggingTable(Connection con) {
        String sql =
                "CREATE TABLE IF NOT EXISTS asset_qr_tagging_status ("
                + "tagging_id INT AUTO_INCREMENT PRIMARY KEY, "
                + "asset_id INT NOT NULL UNIQUE, "
                + "qr_public_token VARCHAR(120), "
                + "print_status VARCHAR(40) DEFAULT 'PENDING', "
                + "tag_status VARCHAR(40) DEFAULT 'PENDING', "
                + "printed_by_user_id INT, "
                + "tagged_by_user_id INT, "
                + "printed_at TIMESTAMP NULL, "
                + "tagged_at TIMESTAMP NULL, "
                + "remarks VARCHAR(500), "
                + "created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP, "
                + "updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP"
                + ") ENGINE=InnoDB DEFAULT CHARSET=utf8mb4";

        try (PreparedStatement ps = con.prepareStatement(sql)) {
            ps.executeUpdate();
        } catch (Exception e) {
            System.err.println("QR Module DB Error: " + e.getMessage());
        }
    }
%>

<%
    String username = (String) session.getAttribute("username");
    String role = (String) session.getAttribute("role");

    if (username == null || role == null) {
        response.sendRedirect("login.jsp");
        return;
    }

    boolean canView = ("SUPER_ADMIN".equals(role) || "ADMIN".equals(role))
            || "ASSET_MANAGER".equals(role)
            || "AUDITOR".equals(role);

    if (!canView) {
        response.sendRedirect("dashboard.jsp?access=denied");
        return;
    }

    String q = request.getParameter("q");
    String printFilter = request.getParameter("print");
    String tagFilter = request.getParameter("tag");

    if (q == null) {
        q = "";
    }

    if (printFilter == null || printFilter.trim().isEmpty()) {
        printFilter = "ALL";
    }

    if (tagFilter == null || tagFilter.trim().isEmpty()) {
        tagFilter = "PENDING";
    }

    q = q.trim();
    printFilter = printFilter.trim().toUpperCase(Locale.ENGLISH);
    tagFilter = tagFilter.trim().toUpperCase(Locale.ENGLISH);

    String publicBaseUrl = QrUrlUtil.getConfiguredPublicBaseUrl();
    List<WorkRow> rows = new ArrayList<WorkRow>();

    try (Connection con = DBConnection.getConnection()) {
        ensureTaggingTable(con);

        StringBuilder sql = new StringBuilder();

        sql.append("SELECT ")
                .append("a.asset_id, a.asset_code, a.asset_name, a.qr_public_token, a.qr_code, ")
                .append("COALESCE(d.department_name, 'Unassigned') AS department_name, ")
                .append("COALESCE(ac.category_name, 'Uncategorized') AS category_name, ")
                .append("COALESCE(rl.location_name, a.location, 'Not Mentioned') AS location_name, ")
                .append("COALESCE(t.print_status, 'PENDING') AS print_status, ")
                .append("COALESCE(t.tag_status, 'PENDING') AS tag_status ")
                .append("FROM assets a ")
                .append("LEFT JOIN departments d ON a.department_id = d.department_id ")
                .append("LEFT JOIN asset_categories ac ON a.category_id = ac.category_id ")
                .append("LEFT JOIN railway_locations rl ON a.location_id = rl.location_id ")
                .append("LEFT JOIN asset_qr_tagging_status t ON a.asset_id = t.asset_id ")
                .append("WHERE a.qr_public_token IS NOT NULL AND TRIM(a.qr_public_token) <> '' ");

        List<String> params = new ArrayList<String>();

        if (!"ALL".equals(printFilter)) {
            sql.append("AND COALESCE(t.print_status, 'PENDING') = ? ");
            params.add(printFilter);
        }

        if (!"ALL".equals(tagFilter)) {
            sql.append("AND COALESCE(t.tag_status, 'PENDING') = ? ");
            params.add(tagFilter);
        }

        if (!q.isEmpty()) {
            sql.append("AND (a.asset_code LIKE ? OR a.asset_name LIKE ? OR d.department_name LIKE ? OR ac.category_name LIKE ? OR rl.location_name LIKE ?) ");

            String searchValue = "%" + q + "%";

            for (int i = 0; i < 5; i++) {
                params.add(searchValue);
            }
        }

        sql.append("ORDER BY d.department_name ASC, rl.location_name ASC, a.asset_code ASC LIMIT 150");

        try (PreparedStatement ps = con.prepareStatement(sql.toString())) {
            for (int i = 0; i < params.size(); i++) {
                ps.setString(i + 1, params.get(i));
            }

            try (ResultSet rs = ps.executeQuery()) {
                while (rs.next()) {
                    WorkRow row = new WorkRow();

                    row.assetId = rs.getString("asset_id");
                    row.assetCode = rs.getString("asset_code");
                    row.assetName = rs.getString("asset_name");
                    row.departmentName = rs.getString("department_name");
                    row.categoryName = rs.getString("category_name");
                    row.locationName = rs.getString("location_name");
                    row.token = rs.getString("qr_public_token");
                    row.qrUrl = rs.getString("qr_code");
                    row.printStatus = rs.getString("print_status");
                    row.tagStatus = rs.getString("tag_status");

                    if (row.token != null
                            && !row.token.trim().isEmpty()
                            && !publicBaseUrl.trim().isEmpty()) {
                        row.qrUrl = publicBaseUrl + "/public_asset_view.jsp?token=" + row.token;
                    }

                    rows.add(row);
                }
            }
        }

    } catch (Exception e) {
        System.err.println("QR Module DB Error: " + e.getMessage());
    }

    String generatedAt = new java.text.SimpleDateFormat("dd MMM yyyy, hh:mm a").format(new java.util.Date());
%>

<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>QR Tagging Work Order - IR-AMS</title>

    <link rel="stylesheet"
          href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.0/css/all.min.css">

    <link rel="stylesheet" href="css/qr_tagging_work_order.css?v=28000">
</head>

<body>
    <div class="no-print">
        <div class="toolbar">
            <div>
                <h1>QR Tagging Work Order</h1>
                <p>Rows loaded: <%= rows.size() %> &middot; Generated by <%= safeText(username) %> &middot; <%= generatedAt %></p>
            </div>

            <div class="btn-row">
                <button class="btn primary" onclick="window.print();">
                    <i class="fa-solid fa-print"></i>
                    Print Work Order
                </button>

                <a class="btn" href="qr_tagging_status.jsp">
                    <i class="fa-solid fa-tags"></i>
                    Tagging Status
                </a>

                <a class="btn" href="qr_control_center.jsp">
                    <i class="fa-solid fa-arrow-left"></i>
                    Control Center
                </a>
            </div>
        </div>
    </div>

    <main class="page">
        <section class="header">
            <img src="images/indian-railway-logo.png" alt="Indian Railways">

            <div>
                <h2>East Coast Railway - Asset QR Tagging Work Order</h2>
                <p>
                    Indian Railways &middot; Asset Management System<br>
                    Headquarters / Rail Sadan, Bhubaneswar, Odisha
                </p>
            </div>

            <div class="meta-box">
                Generated At:<br>
                <%= generatedAt %><br><br>
                Generated By:<br>
                <%= safeText(username) %> / <%= safeText(cleanLabel(role)) %>
            </div>
        </section>

        <section class="summary">
            <div>
                <b><%= rows.size() %></b>
                <span>Total Work Items</span>
            </div>

            <div>
                <b><%= safeText(cleanLabel(printFilter)) %></b>
                <span>Print Filter</span>
            </div>

            <div>
                <b><%= safeText(cleanLabel(tagFilter)) %></b>
                <span>Tagging Filter</span>
            </div>

            <div>
                <b><%= q.isEmpty() ? "All" : safeText(q) %></b>
                <span>Search Filter</span>
            </div>
        </section>

        <table>
            <thead>
                <tr>
                    <th>Sl.</th>
                    <th>QR</th>
                    <th>Asset Code</th>
                    <th>Asset Name</th>
                    <th>Department</th>
                    <th>Category</th>
                    <th>Location</th>
                    <th>Token</th>
                    <th>Print Status</th>
                    <th>Tag Status</th>
                    <th>Tagged Yes/No</th>
                    <th>Condition / Remarks</th>
                    <th>Employee Sign</th>
                </tr>
            </thead>

            <tbody>
                <% int sl = 1; %>
                <% for (WorkRow row : rows) {
                    String qrImageUrl = "https://api.qrserver.com/v1/create-qr-code/?size=160x160&margin=8&data="
                            + URLEncoder.encode(row.qrUrl, "UTF-8");
                %>
                    <tr>
                        <td><%= sl++ %></td>
                        <td>
                            <img class="qr-img" src="<%= qrImageUrl %>" alt="QR">
                        </td>
                        <td><strong><%= safeText(row.assetCode) %></strong></td>
                        <td><%= safeText(row.assetName) %></td>
                        <td><%= safeText(row.departmentName) %></td>
                        <td><%= safeText(row.categoryName) %></td>
                        <td><%= safeText(row.locationName) %></td>
                        <td><%= safeText(row.token) %></td>
                        <td><%= safeText(cleanLabel(row.printStatus)) %></td>
                        <td><%= safeText(cleanLabel(row.tagStatus)) %></td>
                        <td></td>
                        <td></td>
                        <td></td>
                    </tr>
                <% } %>

                <% if (rows.isEmpty()) { %>
                    <tr>
                        <td colspan="13">No QR tagging work item found for selected filter.</td>
                    </tr>
                <% } %>
            </tbody>
        </table>

        <section class="sign-section">
            <div class="sign-box">Prepared By / Asset Manager</div>
            <div class="sign-box">Verified By / Department Representative</div>
            <div class="sign-box">Approved By / Authority</div>
        </section>
    </main>
</body>
</html>
