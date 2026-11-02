<%@page contentType="text/html" pageEncoding="UTF-8"%>
<%@page import="com.mycompany.asset_management_system_ams.DBConnection"%>
<%@page import="java.sql.*"%>
<%@page import="java.util.*"%>
<%@page import="java.text.DecimalFormat"%>

<%!
    public static class RecentScanRow {
        String scanId = "";
        String assetId = "";
        String assetCode = "";
        String assetName = "";
        String token = "";
        String status = "";
        String source = "";
        String ip = "";
        String scannedAt = "";
    }

    public static class TopAssetRow {
        String assetId = "";
        String assetCode = "";
        String assetName = "";
        String scanCount = "";
    }

    public static class PublicUrlRow {
        String id = "";
        String label = "";
        String providerType = "";
        String baseUrl = "";
        String isActive = "";
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

    private boolean tableExists(Connection con, String tableName) {
        String sql = "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = DATABASE() AND table_name = ?";

        try (PreparedStatement ps = con.prepareStatement(sql)) {
            ps.setString(1, tableName);

            try (ResultSet rs = ps.executeQuery()) {
                return rs.next() && rs.getInt(1) > 0;
            }

        } catch (Exception e) {
            System.err.println("QR Module DB Error: " + e.getMessage());
        }

        return false;
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

    public String formatNumber(int value) {
        DecimalFormat df = new DecimalFormat("0.#");

        if (value >= 10000000) {
            return df.format(value / 10000000.0) + "Cr+";
        }

        if (value >= 100000) {
            return df.format(value / 100000.0) + "L+";
        }

        if (value >= 1000) {
            return df.format(value / 1000.0) + "K+";
        }

        return String.valueOf(value);
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

    boolean canViewQrControl = ("SUPER_ADMIN".equals(role) || "ADMIN".equals(role))
            || "ASSET_MANAGER".equals(role)
            || "AUDITOR".equals(role);

    boolean canManageQr = ("SUPER_ADMIN".equals(role) || "ADMIN".equals(role))
            || "ASSET_MANAGER".equals(role);

    if (!canViewQrControl) {
        response.sendRedirect("dashboard.jsp?access=denied");
        return;
    }

    String userInitial = username.substring(0, Math.min(2, username.length())).toUpperCase(Locale.ENGLISH);

    int totalAssets = 0;
    int qrGenerated = 0;
    int qrPending = 0;
    int totalScans = 0;
    int todayScans = 0;
    int successfulScans = 0;
    int invalidScans = 0;
    int taggedQr = 0;
    int pendingTagging = 0;

    boolean scanTableExists = false;
    boolean taggingTableExists = false;

    List<RecentScanRow> recentScans = new ArrayList<RecentScanRow>();
    List<TopAssetRow> topAssets = new ArrayList<TopAssetRow>();
    List<PublicUrlRow> publicUrls = new ArrayList<PublicUrlRow>();
    boolean publicUrlsTableExists = false;

    try (Connection con = DBConnection.getConnection()) {
        totalAssets = countRows(con, "SELECT COUNT(*) FROM assets");

        qrGenerated = countRows(con,
                "SELECT COUNT(*) FROM assets "
                + "WHERE qr_public_token IS NOT NULL AND TRIM(qr_public_token) <> ''");

        qrPending = Math.max(totalAssets - qrGenerated, 0);

        scanTableExists = tableExists(con, "asset_qr_scan_logs");
        taggingTableExists = tableExists(con, "asset_qr_tagging_status");

        if (taggingTableExists) {
            taggedQr = countRows(con, "SELECT COUNT(*) FROM asset_qr_tagging_status WHERE tag_status = 'TAGGED'");
            pendingTagging = Math.max(qrGenerated - taggedQr, 0);
        } else {
            taggedQr = 0;
            pendingTagging = qrGenerated;
        }

        if (scanTableExists) {
            totalScans = countRows(con, "SELECT COUNT(*) FROM asset_qr_scan_logs");
            todayScans = countRows(con, "SELECT COUNT(*) FROM asset_qr_scan_logs WHERE DATE(scanned_at) = CURDATE()");
            successfulScans = countRows(con, "SELECT COUNT(*) FROM asset_qr_scan_logs WHERE scan_status = 'SUCCESS'");
            invalidScans = countRows(con, "SELECT COUNT(*) FROM asset_qr_scan_logs WHERE scan_status = 'INVALID_TOKEN'");

            String recentSql =
                    "SELECT "
                    + "q.scan_id, q.asset_id, q.qr_public_token, q.scan_status, q.scan_source, q.scan_ip, "
                    + "DATE_FORMAT(q.scanned_at, '%d %b %Y, %h:%i %p') AS scanned_at, "
                    + "COALESCE(a.asset_code, 'Unknown Asset') AS asset_code, "
                    + "COALESCE(a.asset_name, 'Asset not linked') AS asset_name "
                    + "FROM asset_qr_scan_logs q "
                    + "LEFT JOIN assets a ON q.asset_id = a.asset_id "
                    + "ORDER BY q.scan_id DESC "
                    + "LIMIT 8";

            try (PreparedStatement ps = con.prepareStatement(recentSql);
                 ResultSet rs = ps.executeQuery()) {

                while (rs.next()) {
                    RecentScanRow row = new RecentScanRow();

                    row.scanId = rs.getString("scan_id");
                    row.assetId = rs.getString("asset_id");
                    row.assetCode = rs.getString("asset_code");
                    row.assetName = rs.getString("asset_name");
                    row.token = rs.getString("qr_public_token");
                    row.status = rs.getString("scan_status");
                    row.source = rs.getString("scan_source");
                    row.ip = rs.getString("scan_ip");
                    row.scannedAt = rs.getString("scanned_at");

                    recentScans.add(row);
                }
            }

            String topSql =
                    "SELECT "
                    + "q.asset_id, "
                    + "COALESCE(a.asset_code, 'Unknown Asset') AS asset_code, "
                    + "COALESCE(a.asset_name, 'Asset not linked') AS asset_name, "
                    + "COUNT(*) AS scan_count "
                    + "FROM asset_qr_scan_logs q "
                    + "LEFT JOIN assets a ON q.asset_id = a.asset_id "
                    + "WHERE q.asset_id IS NOT NULL "
                    + "GROUP BY q.asset_id, a.asset_code, a.asset_name "
                    + "ORDER BY scan_count DESC "
                    + "LIMIT 6";

            try (PreparedStatement ps = con.prepareStatement(topSql);
                 ResultSet rs = ps.executeQuery()) {

                while (rs.next()) {
                    TopAssetRow row = new TopAssetRow();

                    row.assetId = rs.getString("asset_id");
                    row.assetCode = rs.getString("asset_code");
                    row.assetName = rs.getString("asset_name");
                    row.scanCount = rs.getString("scan_count");

                    topAssets.add(row);
                }
            }
        }

        publicUrlsTableExists = tableExists(con, "public_qr_base_urls");
        if (publicUrlsTableExists) {
            String urlsSql = "SELECT id, label, provider_type, base_url, is_active FROM public_qr_base_urls ORDER BY id ASC";
            try (PreparedStatement ps = con.prepareStatement(urlsSql);
                 ResultSet rs = ps.executeQuery()) {
                while (rs.next()) {
                    PublicUrlRow pur = new PublicUrlRow();
                    pur.id = rs.getString("id");
                    pur.label = rs.getString("label");
                    pur.providerType = rs.getString("provider_type");
                    pur.baseUrl = rs.getString("base_url");
                    pur.isActive = rs.getString("is_active");
                    publicUrls.add(pur);
                }
            }
        }

    } catch (Exception e) {
        System.err.println("QR Module DB Error: " + e.getMessage());
    }

    double qrCoverage = totalAssets == 0 ? 0 : (qrGenerated * 100.0 / totalAssets);
    DecimalFormat percentFormat = new DecimalFormat("0.0");
%>

<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>QR Control Center - IR-AMS</title>

    <link rel="stylesheet"
          href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.0/css/all.min.css">

    <link rel="stylesheet" href="css/ir-glass.css?v=28000">
    <link rel="stylesheet" href="css/ams-pro.css?v=28000">
    <link rel="stylesheet" href="css/ir-ams-railway-ui.css?v=28000">
<link rel="stylesheet" href="css/qr_control_center.css?v=topbarfix1">
</head>

<body class="railway-ui">
<div class="app ams-shell">

    
    <jsp:include page="sidebar.jsp" />

    <main class="main railway-main">
        
        <jsp:include page="topbar.jsp" />

        <div class="main-scroll-content qr-control-board">

            <section class="qr-hero-new">
                <div class="qr-hero-copy">
                    <div class="eyebrow">
                        <i class="fa-solid fa-qrcode"></i>
                        Railway QR Governance Console
                    </div>

                    <h1>QR Control Center</h1>

                    <p>
                        Central railway-grade QR management workspace for asset QR generation, public verification,
                        scan monitoring, QR tagging, token reissue, audit trail and export-ready QR reports.
                    </p>

                    <div class="hero-pills-new">
                        <% if (canManageQr) { %>
                            <a class="hero-pill-new" href="qr_bulk_generate.jsp">
                                <i class="fa-solid fa-wand-magic-sparkles"></i>
                                Bulk Generate
                            </a>
                        <% } %>

                        <a class="hero-pill-new" href="qr_asset_register.jsp">
                            <i class="fa-solid fa-table-list"></i>
                            QR Register
                        </a>

                        <a class="hero-pill-new" href="qr_scan_logs.jsp">
                            <i class="fa-solid fa-list-check"></i>
                            Scan Logs
                        </a>

                        <a class="hero-pill-new" href="qr_tagging_status.jsp">
                            <i class="fa-solid fa-tags"></i>
                            Tagging Status
                        </a>

                        <a class="hero-pill-new" href="qr_system_health.jsp">
                            <i class="fa-solid fa-heart-pulse"></i>
                            System Health
                        </a>
                    </div>
                </div>
            </section>

            <section class="kpi-grid">
                <div class="kpi-card">
                    <div class="kpi-icon"><i class="fa-solid fa-cubes"></i></div>
                    <h3>Total Assets</h3>
                    <p title="<%= totalAssets %>"><%= formatNumber(totalAssets) %></p>
                </div>

                <div class="kpi-card">
                    <div class="kpi-icon"><i class="fa-solid fa-qrcode"></i></div>
                    <h3>QR Generated</h3>
                    <p title="<%= qrGenerated %>"><%= formatNumber(qrGenerated) %></p>
                </div>

                <div class="kpi-card">
                    <div class="kpi-icon"><i class="fa-solid fa-hourglass-half"></i></div>
                    <h3>QR Pending</h3>
                    <p title="<%= qrPending %>"><%= formatNumber(qrPending) %></p>
                </div>

                <div class="kpi-card">
                    <div class="kpi-icon"><i class="fa-solid fa-chart-pie"></i></div>
                    <h3>Coverage</h3>
                    <p><%= percentFormat.format(qrCoverage) %>%</p>
                </div>

                <div class="kpi-card">
                    <div class="kpi-icon"><i class="fa-solid fa-tags"></i></div>
                    <h3>QR Tagged</h3>
                    <p title="<%= taggedQr %>"><%= formatNumber(taggedQr) %></p>
                </div>

                <div class="kpi-card">
                    <div class="kpi-icon"><i class="fa-solid fa-list-check"></i></div>
                    <h3>Total Scans</h3>
                    <p title="<%= totalScans %>"><%= formatNumber(totalScans) %></p>
                </div>
            </section>

            <section class="report-panel" id="irams-qr-control-final-hub">
                <div class="panel-head">
                    <div>
                        <h2>Complete QR Module Directory</h2>
                        <p>All QR pages are connected here for daily railway office use.</p>
                    </div>

                    <div class="action-row">
                        <a href="qr_asset_register.jsp" class="report-btn green">
                            <i class="fa-solid fa-table-list"></i>
                            QR Register
                        </a>

                        <a href="reports.jsp" class="report-btn">
                            <i class="fa-regular fa-clipboard"></i>
                            Reports
                        </a>
                    </div>
                </div>

                <div class="module-section-title">Monitoring, Reports &amp; Audit</div>

                <div class="module-grid">
                    <a href="qr_system_health.jsp" class="module-card green">
                        <i class="fa-solid fa-heart-pulse"></i>
                        <div>
                            <strong>System Health</strong>
                            <span>Check QR system readiness, tables and configuration.</span>
                        </div>
                    </a>

                    <a href="qr_asset_register.jsp" class="module-card green">
                        <i class="fa-solid fa-table-list"></i>
                        <div>
                            <strong>QR Asset Register</strong>
                            <span>Official QR-enabled asset register.</span>
                        </div>
                    </a>

                    <a href="qr_scan_logs.jsp" class="module-card green">
                        <i class="fa-solid fa-list-check"></i>
                        <div>
                            <strong>QR Scan Logs</strong>
                            <span>View public and internal QR scan entries.</span>
                        </div>
                    </a>

                    <a href="qr_scan_analytics.jsp" class="module-card green">
                        <i class="fa-solid fa-chart-line"></i>
                        <div>
                            <strong>QR Scan Analytics</strong>
                            <span>Scan trends, top assets and source analysis.</span>
                        </div>
                    </a>

                    <a href="qr_coverage_report.jsp" class="module-card green">
                        <i class="fa-solid fa-chart-pie"></i>
                        <div>
                            <strong>QR Coverage Report</strong>
                            <span>Department, category and status-wise QR coverage.</span>
                        </div>
                    </a>

                    <a href="qr_missing_qr_report.jsp" class="module-card red">
                        <i class="fa-solid fa-hourglass-half"></i>
                        <div>
                            <strong>Missing QR Report</strong>
                            <span>Assets where QR token is still missing.</span>
                        </div>
                    </a>

                    <a href="qr_exception_report.jsp" class="module-card red">
                        <i class="fa-solid fa-triangle-exclamation"></i>
                        <div>
                            <strong>QR Exception Report</strong>
                            <span>Missing token, URL mismatch and invalid token scans.</span>
                        </div>
                    </a>

                    <a href="qr_ip_audit_report.jsp" class="module-card red">
                        <i class="fa-solid fa-network-wired"></i>
                        <div>
                            <strong>QR IP Audit</strong>
                            <span>IP-wise invalid token and scan audit.</span>
                        </div>
                    </a>

                    <a href="qr_tagging_status.jsp" class="module-card green">
                        <i class="fa-solid fa-tags"></i>
                        <div>
                            <strong>QR Tagging Status</strong>
                            <span>Track printed, tagged, damaged and reprint labels.</span>
                        </div>
                    </a>

                    <a href="qr_tagging_work_order.jsp" class="module-card green">
                        <i class="fa-solid fa-clipboard-list"></i>
                        <div>
                            <strong>QR Work Order</strong>
                            <span>Printable QR physical tagging work order.</span>
                        </div>
                    </a>

                    <a href="qr_token_lookup.jsp" class="module-card green">
                        <i class="fa-solid fa-magnifying-glass"></i>
                        <div>
                            <strong>QR Token Lookup</strong>
                            <span>Search token, public URL or asset code.</span>
                        </div>
                    </a>

                    <a href="qr_print_labels.jsp" class="module-card green">
                        <i class="fa-solid fa-print"></i>
                        <div>
                            <strong>QR Label Print</strong>
                            <span>Bulk QR printable label sheet.</span>
                        </div>
                    </a>
                </div>

                <% if (canManageQr) { %>
                    <div class="module-section-title">Administrative QR Controls</div>

                    <div class="module-grid">
                        <a href="qr_bulk_generate.jsp" class="module-card orange">
                            <i class="fa-solid fa-wand-magic-sparkles"></i>
                            <div>
                                <strong>Bulk QR Generate</strong>
                                <span>Generate QR tokens for missing assets.</span>
                            </div>
                        </a>

                        <a href="qr_url_refresh.jsp" class="module-card orange">
                            <i class="fa-solid fa-link"></i>
                            <div>
                                <strong>QR URL Refresh</strong>
                                <span>Refresh stored QR URLs after link/domain change.</span>
                            </div>
                        </a>

                        <a href="qr_token_reissue.jsp" class="module-card orange">
                            <i class="fa-solid fa-rotate"></i>
                            <div>
                                <strong>QR Token Reissue</strong>
                                <span>Replace leaked, damaged or wrongly printed QR token.</span>
                            </div>
                        </a>

                        <a href="qr_reissue_history.jsp" class="module-card orange">
                            <i class="fa-solid fa-clock-rotate-left"></i>
                            <div>
                                <strong>QR Reissue History</strong>
                                <span>Official token replacement audit trail.</span>
                            </div>
                        </a>
                    </div>
                <% } %>
            </section>

            <!-- PUBLIC QR LINK CONFIGURATION -->
            <section class="split-grid" id="qr-settings" style="margin-top:20px;">
                <div class="report-panel" style="grid-column: span 2;">
                    <div class="panel-head">
                        <div>
                            <h2>Public QR Link Configuration</h2>
                            <p>Manage and activate the public domains used for QR code scanning (e.g. ngrok, VPS).</p>
                        </div>
                    </div>
                    
                    <div style="padding: 15px; border: 1px solid #d7e5f7; border-radius: 12px; background: #f8fbff; margin-bottom: 20px;">
                        <form action="ManageQrUrlsServlet" method="post" style="display: flex; gap: 10px; align-items: flex-end; flex-wrap: wrap;">
                            <input type="hidden" name="action" value="add">
                            
                            <div style="flex: 1; min-width: 150px;">
                                <label style="display:block; font-size: 11px; font-weight: 800; color: #64748b; margin-bottom: 5px;">Public URL Name / Label</label>
                                <input type="text" name="label" required placeholder="e.g. Current ngrok, VPS" style="width:100%; padding: 8px 12px; border: 1px solid #c9d8eb; border-radius: 8px; font-size: 13px;">
                            </div>
                            
                            <div style="flex: 2; min-width: 250px;">
                                <label style="display:block; font-size: 11px; font-weight: 800; color: #64748b; margin-bottom: 5px;">Public Base URL (Must start with https://)</label>
                                <input type="url" name="base_url" required placeholder="https://your-tunnel.ngrok-free.app" style="width:100%; padding: 8px 12px; border: 1px solid #c9d8eb; border-radius: 8px; font-size: 13px;">
                            </div>
                            
                            <div style="flex: 1; min-width: 150px;">
                                <label style="display:block; font-size: 11px; font-weight: 800; color: #64748b; margin-bottom: 5px;">Provider Type</label>
                                <select name="provider_type" style="width:100%; padding: 8px 12px; border: 1px solid #c9d8eb; border-radius: 8px; font-size: 13px;">
                                    <option value="NGROK">NGROK</option>
                                    <option value="CLOUDFLARE_TUNNEL">CLOUDFLARE_TUNNEL</option>
                                    <option value="LOCALTUNNEL">LOCALTUNNEL</option>
                                    <option value="VPS_DOMAIN">VPS_DOMAIN</option>
                                    <option value="CUSTOM_DOMAIN">CUSTOM_DOMAIN</option>
                                    <option value="OTHER">OTHER</option>
                                </select>
                            </div>
                            
                            <div>
                                <button type="submit" class="action-btn primary" style="height: 35px; border:none;">
                                    <i class="fa-solid fa-plus"></i> Add Public URL
                                </button>
                            </div>
                        </form>
                    </div>

                    <table style="width: 100%; border-collapse: collapse; font-size: 13px; text-align: left;">
                        <thead>
                            <tr style="border-bottom: 2px solid #d7e5f7; color: var(--ir-blue);">
                                <th style="padding: 10px;">Label</th>
                                <th style="padding: 10px;">Provider</th>
                                <th style="padding: 10px;">Base URL</th>
                                <th style="padding: 10px;">Status</th>
                                <th style="padding: 10px; text-align: right;">Actions</th>
                            </tr>
                        </thead>
                        <tbody>
                            <% if (publicUrls.isEmpty()) { %>
                                <tr>
                                    <td colspan="5" style="padding: 20px; text-align: center; color: #64748b;">
                                        <i class="fa-solid fa-circle-info"></i> No public URLs configured yet. Add one above.
                                    </td>
                                </tr>
                            <% } else {
                                for (PublicUrlRow pur : publicUrls) { 
                                    boolean isActive = "1".equals(pur.isActive);
                            %>
                                <tr style="border-bottom: 1px solid #edf2fb;">
                                    <td style="padding: 10px; font-weight: <%= isActive ? "900" : "500" %>;">
                                        <%= safeText(pur.label) %>
                                    </td>
                                    <td style="padding: 10px; color: #64748b;">
                                        <%= safeText(pur.providerType) %>
                                    </td>
                                    <td style="padding: 10px;">
                                        <a href="<%= safeText(pur.baseUrl) %>" target="_blank" style="color: var(--ir-blue); text-decoration: none;">
                                            <%= safeText(pur.baseUrl) %>
                                        </a>
                                    </td>
                                    <td style="padding: 10px;">
                                        <% if (isActive) { %>
                                            <span class="pill status-ACTIVE" style="background: #eaf7ef; color: #04733b;">ACTIVE</span>
                                        <% } else { %>
                                            <span class="pill" style="background: #f1f5f9; color: #64748b;">INACTIVE</span>
                                        <% } %>
                                    </td>
                                    <td style="padding: 10px; text-align: right;">
                                        <div style="display: flex; gap: 8px; justify-content: flex-end;">
                                            <% if (!isActive) { %>
                                                <form action="ManageQrUrlsServlet" method="post" style="margin:0;">
                                                    <input type="hidden" name="action" value="activate">
                                                    <input type="hidden" name="id" value="<%= pur.id %>">
                                                    <button type="submit" class="action-btn green" style="height: 30px; font-size: 11px;">
                                                        Activate
                                                    </button>
                                                </form>
                                                
                                                <form action="ManageQrUrlsServlet" method="post" style="margin:0;" onsubmit="return confirm('Delete this URL?');">
                                                    <input type="hidden" name="action" value="delete">
                                                    <input type="hidden" name="id" value="<%= pur.id %>">
                                                    <button type="submit" class="action-btn" style="height: 30px; font-size: 11px; background: #fff0f0; color: #c62828; border-color: #ffc7c7;">
                                                        Delete
                                                    </button>
                                                </form>
                                            <% } else { %>
                                                <a href="<%= safeText(pur.baseUrl) %>/qr_url_refresh.jsp" target="_blank" class="action-btn" style="height: 30px; font-size: 11px;" title="Test and Refresh Existing">
                                                    <i class="fa-solid fa-vial"></i> Test & Refresh QR Cards
                                                </a>
                                            <% } %>
                                        </div>
                                    </td>
                                </tr>
                            <%  }
                               } %>
                        </tbody>
                    </table>
                </div>
            </section>
            
            <section class="kpi-grid">
                <div class="kpi-card">
                    <div class="kpi-icon"><i class="fa-solid fa-calendar-day"></i></div>
                    <h3>Today Scans</h3>
                    <p title="<%= todayScans %>"><%= formatNumber(todayScans) %></p>
                </div>

                <div class="kpi-card">
                    <div class="kpi-icon"><i class="fa-solid fa-circle-check"></i></div>
                    <h3>Success Scans</h3>
                    <p title="<%= successfulScans %>"><%= formatNumber(successfulScans) %></p>
                </div>

                <div class="kpi-card">
                    <div class="kpi-icon"><i class="fa-solid fa-triangle-exclamation"></i></div>
                    <h3>Invalid Scans</h3>
                    <p title="<%= invalidScans %>"><%= formatNumber(invalidScans) %></p>
                </div>

                <div class="kpi-card">
                    <div class="kpi-icon"><i class="fa-solid fa-clipboard-list"></i></div>
                    <h3>Tag Pending</h3>
                    <p title="<%= pendingTagging %>"><%= formatNumber(pendingTagging) %></p>
                </div>

                <div class="kpi-card">
                    <div class="kpi-icon"><i class="fa-solid fa-database"></i></div>
                    <h3>Scan Table</h3>
                    <p><%= scanTableExists ? "OK" : "N/A" %></p>
                </div>

                <div class="kpi-card">
                    <div class="kpi-icon"><i class="fa-solid fa-tags"></i></div>
                    <h3>Tag Table</h3>
                    <p><%= taggingTableExists ? "OK" : "N/A" %></p>
                </div>
            </section>

            <section class="split-grid">
                <div class="report-panel">
                    <div class="panel-head">
                        <div>
                            <h2>Recent QR Scan Activity</h2>
                            <p>Latest public QR scan events and verification status.</p>
                        </div>

                        <a href="qr_scan_logs.jsp" class="report-btn">
                            <i class="fa-solid fa-list-check"></i>
                            View Logs
                        </a>
                    </div>

                    <% if (!scanTableExists) { %>
                        <div class="empty-box">
                            <i class="fa-solid fa-database"></i>
                            <strong>Scan log table not found</strong>
                            <span>Import/create asset_qr_scan_logs table first.</span>
                        </div>
                    <% } else if (recentScans.isEmpty()) { %>
                        <div class="empty-box">
                            <i class="fa-solid fa-folder-open"></i>
                            <strong>No QR scan activity yet</strong>
                            <span>Open any public QR link to create scan history.</span>
                        </div>
                    <% } else { %>
                        <div class="mini-list">
                            <% for (RecentScanRow row : recentScans) { %>
                                <div class="mini-row">
                                    <div>
                                        <strong><%= safeText(row.assetCode) %> &middot; <%= safeText(row.assetName) %></strong>
                                        <span>
                                            Token: <%= safeText(row.token) %><br>
                                            Source: <%= safeText(cleanLabel(row.source)) %> &middot; IP: <%= safeText(row.ip) %>
                                        </span>
                                    </div>

                                    <div>
                                        <span class="pill status-<%= safeText(statusClass(row.status)) %>">
                                            <%= safeText(cleanLabel(row.status)) %>
                                        </span>
                                        <br><br>
                                        <span class="pill"><%= safeText(row.scannedAt) %></span>
                                    </div>
                                </div>
                            <% } %>
                        </div>
                    <% } %>
                </div>

                <div class="report-panel">
                    <div class="panel-head">
                        <div>
                            <h2>Most Scanned Assets</h2>
                            <p>Assets receiving the highest QR scan activity.</p>
                        </div>

                        <a href="qr_scan_analytics.jsp" class="report-btn">
                            <i class="fa-solid fa-chart-line"></i>
                            Analytics
                        </a>
                    </div>

                    <% if (!scanTableExists || topAssets.isEmpty()) { %>
                        <div class="empty-box">
                            <i class="fa-solid fa-chart-simple"></i>
                            <strong>No ranking available</strong>
                            <span>Scan records will appear here after public QR use.</span>
                        </div>
                    <% } else { %>
                        <div class="mini-list">
                            <% for (TopAssetRow row : topAssets) { %>
                                <div class="mini-row">
                                    <div>
                                        <strong><%= safeText(row.assetCode) %> &middot; <%= safeText(row.assetName) %></strong>
                                        <span>Asset ID: <%= safeText(row.assetId) %></span>
                                    </div>

                                    <div>
                                        <span class="pill">
                                            <i class="fa-solid fa-qrcode"></i>
                                            &nbsp;<%= safeText(row.scanCount) %> scans
                                        </span>
                                        <br><br>
                                        <a class="action-btn" href="view_asset.jsp?id=<%= safeText(row.assetId) %>">
                                            Open
                                        </a>
                                    </div>
                                </div>
                            <% } %>
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
