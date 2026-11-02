<%@page contentType="text/html" pageEncoding="UTF-8"%>
<%@page import="com.mycompany.asset_management_system_ams.DBConnection"%>
<%@page import="java.sql.*"%>
<%@page import="java.util.*"%>
<%@page import="java.text.DecimalFormat"%>

<%!
    public String formatNumber(int number) {
        if (number >= 100000) {
            return String.format("%.1fL", number / 100000.0);
        } else if (number >= 1000) {
            return String.format("%.1fK", number / 1000.0);
        }
        return String.valueOf(number);
    }

    public static class CoverageRow {
        String groupName = "";
        String totalAssets = "0";
        String qrGenerated = "0";
        String qrMissing = "0";
        String coveragePercent = "0.0";
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

    private String percent(int part, int total) {
        if (total <= 0) {
            return "0.0";
        }

        DecimalFormat df = new DecimalFormat("0.0");
        return df.format(part * 100.0 / total);
    }

    private List<CoverageRow> getCoverageRows(Connection con, String sql) {
        List<CoverageRow> rows = new ArrayList<CoverageRow>();

        try (PreparedStatement ps = con.prepareStatement(sql);
             ResultSet rs = ps.executeQuery()) {

            while (rs.next()) {
                CoverageRow row = new CoverageRow();

                row.groupName = rs.getString("group_name");
                row.totalAssets = rs.getString("total_assets");
                row.qrGenerated = rs.getString("qr_generated");
                row.qrMissing = rs.getString("qr_missing");
                row.coveragePercent = rs.getString("coverage_percent");

                rows.add(row);
            }

        } catch (Exception e) {
            System.err.println("QR Module DB Error: " + e.getMessage());
        }

        return rows;
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

    boolean canView = ("SUPER_ADMIN".equals(role) || "ADMIN".equals(role))
            || "ASSET_MANAGER".equals(role)
            || "AUDITOR".equals(role);

    if (!canView) {
        response.sendRedirect("dashboard.jsp?access=denied");
        return;
    }

    String userInitial = username.substring(0, Math.min(2, username.length())).toUpperCase(Locale.ENGLISH);

    int totalAssets = 0;
    int qrGenerated = 0;
    int qrMissing = 0;
    int availableAssets = 0;
    int allocatedAssets = 0;
    int maintenanceAssets = 0;

    List<CoverageRow> departmentRows = new ArrayList<CoverageRow>();
    List<CoverageRow> categoryRows = new ArrayList<CoverageRow>();
    List<CoverageRow> statusRows = new ArrayList<CoverageRow>();

    try (Connection con = DBConnection.getConnection()) {
        totalAssets = countRows(con, "SELECT COUNT(*) FROM assets");

        qrGenerated = countRows(con,
                "SELECT COUNT(*) FROM assets "
                + "WHERE qr_public_token IS NOT NULL AND TRIM(qr_public_token) <> ''");

        qrMissing = totalAssets - qrGenerated;

        availableAssets = countRows(con, "SELECT COUNT(*) FROM assets WHERE asset_status = 'AVAILABLE'");
        allocatedAssets = countRows(con, "SELECT COUNT(*) FROM assets WHERE asset_status = 'ALLOCATED'");
        maintenanceAssets = countRows(con, "SELECT COUNT(*) FROM assets WHERE asset_status = 'UNDER_MAINTENANCE'");

        departmentRows = getCoverageRows(con,
                "SELECT "
                + "COALESCE(d.department_name, 'Unassigned Department') AS group_name, "
                + "COUNT(a.asset_id) AS total_assets, "
                + "SUM(CASE WHEN a.qr_public_token IS NOT NULL AND TRIM(a.qr_public_token) <> '' THEN 1 ELSE 0 END) AS qr_generated, "
                + "SUM(CASE WHEN a.qr_public_token IS NULL OR TRIM(a.qr_public_token) = '' THEN 1 ELSE 0 END) AS qr_missing, "
                + "ROUND(SUM(CASE WHEN a.qr_public_token IS NOT NULL AND TRIM(a.qr_public_token) <> '' THEN 1 ELSE 0 END) * 100.0 / NULLIF(COUNT(a.asset_id), 0), 1) AS coverage_percent "
                + "FROM assets a "
                + "LEFT JOIN departments d ON a.department_id = d.department_id "
                + "GROUP BY d.department_name "
                + "ORDER BY coverage_percent ASC, total_assets DESC");

        categoryRows = getCoverageRows(con,
                "SELECT "
                + "COALESCE(ac.category_name, 'Uncategorized') AS group_name, "
                + "COUNT(a.asset_id) AS total_assets, "
                + "SUM(CASE WHEN a.qr_public_token IS NOT NULL AND TRIM(a.qr_public_token) <> '' THEN 1 ELSE 0 END) AS qr_generated, "
                + "SUM(CASE WHEN a.qr_public_token IS NULL OR TRIM(a.qr_public_token) = '' THEN 1 ELSE 0 END) AS qr_missing, "
                + "ROUND(SUM(CASE WHEN a.qr_public_token IS NOT NULL AND TRIM(a.qr_public_token) <> '' THEN 1 ELSE 0 END) * 100.0 / NULLIF(COUNT(a.asset_id), 0), 1) AS coverage_percent "
                + "FROM assets a "
                + "LEFT JOIN asset_categories ac ON a.category_id = ac.category_id "
                + "GROUP BY ac.category_name "
                + "ORDER BY coverage_percent ASC, total_assets DESC");

        statusRows = getCoverageRows(con,
                "SELECT "
                + "COALESCE(a.asset_status, 'UNKNOWN') AS group_name, "
                + "COUNT(a.asset_id) AS total_assets, "
                + "SUM(CASE WHEN a.qr_public_token IS NOT NULL AND TRIM(a.qr_public_token) <> '' THEN 1 ELSE 0 END) AS qr_generated, "
                + "SUM(CASE WHEN a.qr_public_token IS NULL OR TRIM(a.qr_public_token) = '' THEN 1 ELSE 0 END) AS qr_missing, "
                + "ROUND(SUM(CASE WHEN a.qr_public_token IS NOT NULL AND TRIM(a.qr_public_token) <> '' THEN 1 ELSE 0 END) * 100.0 / NULLIF(COUNT(a.asset_id), 0), 1) AS coverage_percent "
                + "FROM assets a "
                + "GROUP BY a.asset_status "
                + "ORDER BY coverage_percent ASC, total_assets DESC");

    } catch (Exception e) {
        System.err.println("QR Module DB Error: " + e.getMessage());
    }

    String overallCoverage = percent(qrGenerated, totalAssets);
%>

<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>QR Coverage Report - IR-AMS</title>

    <link rel="stylesheet"
          href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.0/css/all.min.css">

    <link rel="stylesheet" href="css/ir-glass.css?v=28000">
    <link rel="stylesheet" href="css/ams-pro.css?v=28000">
    <link rel="stylesheet" href="css/ir-ams-railway-ui.css?v=28000">
<link rel="stylesheet" href="css/qr_coverage_report.css?v=topbarfix1">
</head>

<body class="railway-ui">
<div class="app ams-shell">

        <jsp:include page="sidebar.jsp" />

    <main class="main railway-main">
                <jsp:include page="topbar.jsp" />

        <div class="main-scroll-content coverage-board">

            <section class="coverage-hero">
                <div>
                    <h1>QR Coverage Report</h1>
                    <p>
                        Department-wise, category-wise and asset-status-wise QR coverage report for asset tagging readiness,
                        printing readiness and field inspection planning.
                    </p>
                </div>

                <div class="hero-actions">
                    <a href="export_qr_coverage_report_excel.jsp" class="action-btn green">
                        <i class="fa-solid fa-file-excel"></i>
                        Export Excel
                    </a>

                    <a href="qr_missing_qr_report.jsp" class="action-btn primary">
                        <i class="fa-solid fa-hourglass-half"></i>
                        Missing QR
                    </a>

                    <a href="qr_bulk_generate.jsp" class="action-btn">
                        <i class="fa-solid fa-wand-magic-sparkles"></i>
                        Generate QR
                    </a>

                    <a href="qr_control_center.jsp" class="action-btn">
                        <i class="fa-solid fa-arrow-left"></i>
                        Control Center
                    </a>
                </div>
            </section>

            <section class="kpi-grid">
                <div class="kpi-card">
                    <h3>Total Assets</h3>
                    <p title="<%= totalAssets %>"><%= formatNumber(totalAssets) %></p>
                    <span>Assets in register</span>
                </div>

                <div class="kpi-card">
                    <h3>QR Generated</h3>
                    <p title="<%= qrGenerated %>"><%= formatNumber(qrGenerated) %></p>
                    <span>Assets with live QR token</span>
                </div>

                <div class="kpi-card">
                    <h3>QR Missing</h3>
                    <p title="<%= qrMissing %>"><%= formatNumber(qrMissing) %></p>
                    <span>Need QR generation</span>
                </div>

                <div class="kpi-card">
                    <h3>Coverage</h3>
                    <p><%= overallCoverage %>%</p>
                    <span>Overall QR readiness</span>
                </div>

                <div class="kpi-card">
                    <h3>Available</h3>
                    <p title="<%= availableAssets %>"><%= formatNumber(availableAssets) %></p>
                    <span>Available assets</span>
                </div>

                <div class="kpi-card">
                    <h3>Allocated</h3>
                    <p title="<%= allocatedAssets %>"><%= formatNumber(allocatedAssets) %></p>
                    <span>Currently issued assets</span>
                </div>
            </section>

            <section class="split-grid">
                <div class="panel">
                    <h2>Department-wise QR Coverage</h2>

                    <div class="coverage-list">
                        <% for (CoverageRow row : departmentRows) { %>
                            <div class="coverage-row">
                                <div>
                                    <strong><%= safeText(row.groupName) %></strong>
                                    <span>
                                        Total: <%= safeText(row.totalAssets) %> &middot;
                                        Generated: <%= safeText(row.qrGenerated) %> &middot;
                                        Missing: <%= safeText(row.qrMissing) %>
                                    </span>
                                </div>

                                <div class="coverage-meter">
                                    <b><%= safeText(row.coveragePercent) %>%</b>
                                    <div class="bar">
                                        <i style="width:<%= safeText(row.coveragePercent) %>%;"></i>
                                    </div>
                                </div>
                            </div>
                        <% } %>
                    </div>
                </div>

                <div class="panel">
                    <h2>Category-wise QR Coverage</h2>

                    <div class="coverage-list">
                        <% for (CoverageRow row : categoryRows) { %>
                            <div class="coverage-row">
                                <div>
                                    <strong><%= safeText(row.groupName) %></strong>
                                    <span>
                                        Total: <%= safeText(row.totalAssets) %> &middot;
                                        Generated: <%= safeText(row.qrGenerated) %> &middot;
                                        Missing: <%= safeText(row.qrMissing) %>
                                    </span>
                                </div>

                                <div class="coverage-meter">
                                    <b><%= safeText(row.coveragePercent) %>%</b>
                                    <div class="bar">
                                        <i style="width:<%= safeText(row.coveragePercent) %>%;"></i>
                                    </div>
                                </div>
                            </div>
                        <% } %>
                    </div>
                </div>
            </section>

            <section class="panel">
                <h2>Asset Status-wise QR Coverage</h2>

                <div class="coverage-list">
                    <% for (CoverageRow row : statusRows) { %>
                        <div class="coverage-row">
                            <div>
                                <strong><%= safeText(cleanLabel(row.groupName)) %></strong>
                                <span>
                                    Total: <%= safeText(row.totalAssets) %> &middot;
                                    Generated: <%= safeText(row.qrGenerated) %> &middot;
                                    Missing: <%= safeText(row.qrMissing) %>
                                </span>
                            </div>

                            <div class="coverage-meter">
                                <b><%= safeText(row.coveragePercent) %>%</b>
                                <div class="bar">
                                    <i style="width:<%= safeText(row.coveragePercent) %>%;"></i>
                                </div>
                            </div>
                        </div>
                    <% } %>
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

</body>
</html>
