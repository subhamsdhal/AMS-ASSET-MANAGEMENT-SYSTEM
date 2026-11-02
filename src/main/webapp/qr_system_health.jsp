<%@page contentType="text/html" pageEncoding="UTF-8"%>
<%@page import="com.mycompany.asset_management_system_ams.DBConnection"%>
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

    private boolean tableExists(Connection con, String tableName) {
        String sql = "SELECT COUNT(*) FROM information_schema.tables "
                + "WHERE table_schema = DATABASE() AND table_name = ?";

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

    private boolean tableHasColumn(Connection con, String tableName, String columnName) {
        String sql =
                "SELECT COUNT(*) FROM information_schema.columns "
                + "WHERE table_schema = DATABASE() AND table_name = ? AND column_name = ?";

        try (PreparedStatement ps = con.prepareStatement(sql)) {
            ps.setString(1, tableName);
            ps.setString(2, columnName);

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

    private String okClass(boolean ok) {
        return ok ? "good" : "bad";
    }

    private String okLabel(boolean ok) {
        return ok ? "OK" : "Needs Attention";
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

    boolean canViewQrHealth = ("SUPER_ADMIN".equals(role) || "ADMIN".equals(role))
            || "ASSET_MANAGER".equals(role)
            || "AUDITOR".equals(role);

    if (!canViewQrHealth) {
        response.sendRedirect("dashboard.jsp?access=denied");
        return;
    }

    String userInitial = username.substring(0, Math.min(2, username.length())).toUpperCase(Locale.ENGLISH);
    String baseUrl = appBaseUrl(request);

    boolean dbConnected = false;
    boolean assetsTable = false;
    boolean scanLogTable = false;
    boolean assetTokenColumn = false;
    boolean assetQrCodeColumn = false;
    boolean scanTokenColumn = false;
    boolean scanStatusColumn = false;

    int totalAssets = 0;
    int qrGenerated = 0;
    int qrMissing = 0;
    int qrUrlMismatch = 0;
    int totalScans = 0;
    int successScans = 0;
    int invalidScans = 0;
    int todayScans = 0;

    try (Connection con = DBConnection.getConnection()) {
        dbConnected = con != null && !con.isClosed();

        if (dbConnected) {
            assetsTable = tableExists(con, "assets");
            scanLogTable = tableExists(con, "asset_qr_scan_logs");

            if (assetsTable) {
                assetTokenColumn = tableHasColumn(con, "assets", "qr_public_token");
                assetQrCodeColumn = tableHasColumn(con, "assets", "qr_code");

                totalAssets = countRows(con, "SELECT COUNT(*) FROM assets");

                if (assetTokenColumn) {
                    qrGenerated = countRows(con,
                            "SELECT COUNT(*) FROM assets "
                            + "WHERE qr_public_token IS NOT NULL AND TRIM(qr_public_token) <> ''");

                    qrMissing = totalAssets - qrGenerated;
                }

                if (assetTokenColumn && assetQrCodeColumn) {
                    qrUrlMismatch = countPrepared(con,
                            "SELECT COUNT(*) FROM assets "
                            + "WHERE qr_public_token IS NOT NULL AND TRIM(qr_public_token) <> '' "
                            + "AND (qr_code IS NULL OR TRIM(qr_code) = '' "
                            + "OR qr_code <> CONCAT(?, '/public_asset_view.jsp?token=', qr_public_token))",
                            baseUrl);
                }
            }

            if (scanLogTable) {
                scanTokenColumn = tableHasColumn(con, "asset_qr_scan_logs", "qr_public_token");
                scanStatusColumn = tableHasColumn(con, "asset_qr_scan_logs", "scan_status");

                totalScans = countRows(con, "SELECT COUNT(*) FROM asset_qr_scan_logs");
                todayScans = countRows(con, "SELECT COUNT(*) FROM asset_qr_scan_logs WHERE DATE(scanned_at) = CURDATE()");

                if (scanStatusColumn) {
                    successScans = countRows(con, "SELECT COUNT(*) FROM asset_qr_scan_logs WHERE scan_status = 'SUCCESS'");
                    invalidScans = countRows(con, "SELECT COUNT(*) FROM asset_qr_scan_logs WHERE scan_status = 'INVALID_TOKEN'");
                }
            }
        }

    } catch (Exception e) {
        System.err.println("QR Module DB Error: " + e.getMessage());
    }

    boolean qrCoreReady = dbConnected && assetsTable && assetTokenColumn && assetQrCodeColumn;
    boolean scanAuditReady = scanLogTable && scanTokenColumn && scanStatusColumn;
    boolean urlHealthy = qrUrlMismatch == 0;
%>

<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>QR System Health - IR-AMS</title>

    <link rel="stylesheet"
          href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.0/css/all.min.css">

    <link rel="stylesheet" href="css/ir-glass.css?v=28000">
    <link rel="stylesheet" href="css/ams-pro.css?v=28000">
    <link rel="stylesheet" href="css/ir-ams-railway-ui.css?v=28000">
<link rel="stylesheet" href="css/qr_system_health.css?v=topbarfix1">
</head>

<body class="railway-ui">
<div class="app ams-shell">

        <jsp:include page="sidebar.jsp" />

    <main class="main railway-main">
                <jsp:include page="topbar.jsp" />

        <div class="main-scroll-content health-board">

            <section class="health-hero">
                <div>
                    <h1>QR System Health</h1>
                    <p>
                        Technical health check for dynamic asset QR system, scan audit table,
                        live public URL, token coverage and deployment link readiness.
                    </p>
                </div>

                <div class="hero-actions">
                    <a href="qr_url_refresh.jsp" class="action-btn primary">
                        <i class="fa-solid fa-link"></i>
                        Refresh URLs
                    </a>

                    <a href="qr_bulk_generate.jsp" class="action-btn">
                        <i class="fa-solid fa-wand-magic-sparkles"></i>
                        Generate QR
                    </a>

                    <a href="qr_scan_logs.jsp" class="action-btn">
                        <i class="fa-solid fa-list-check"></i>
                        Scan Logs
                    </a>

                    <a href="qr_control_center.jsp" class="action-btn green">
                        <i class="fa-solid fa-arrow-left"></i>
                        Control Center
                    </a>
                </div>
            </section>

            <section class="panel">
                <h2>Detected Current Public Base URL</h2>
                <div class="base-box">
                    <%= safeText(baseUrl) %>
                    <br><br>
                    Expected QR format:
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
                    <h3>QR Generated</h3>
                    <p><%= qrGenerated %></p>
                </div>

                <div class="kpi-card">
                    <div class="kpi-icon"><i class="fa-solid fa-link-slash"></i></div>
                    <h3>URL Mismatch</h3>
                    <p><%= qrUrlMismatch %></p>
                </div>

                <div class="kpi-card">
                    <div class="kpi-icon"><i class="fa-solid fa-list-check"></i></div>
                    <h3>Total Scans</h3>
                    <p><%= totalScans %></p>
                </div>
            </section>

            <section class="split-grid">
                <div class="panel">
                    <h2>Core QR Readiness</h2>

                    <div class="health-list">
                        <div class="health-row">
                            <div>
                                <strong>Database Connection</strong>
                                <span>AMS database connection availability.</span>
                            </div>
                            <span class="pill <%= okClass(dbConnected) %>"><%= okLabel(dbConnected) %></span>
                        </div>

                        <div class="health-row">
                            <div>
                                <strong>Assets Table</strong>
                                <span>Required for QR generation and public asset lookup.</span>
                            </div>
                            <span class="pill <%= okClass(assetsTable) %>"><%= okLabel(assetsTable) %></span>
                        </div>

                        <div class="health-row">
                            <div>
                                <strong>assets.qr_public_token</strong>
                                <span>Stores permanent dynamic QR token.</span>
                            </div>
                            <span class="pill <%= okClass(assetTokenColumn) %>"><%= okLabel(assetTokenColumn) %></span>
                        </div>

                        <div class="health-row">
                            <div>
                                <strong>assets.qr_code</strong>
                                <span>Stores full public live QR URL field.</span>
                            </div>
                            <span class="pill <%= okClass(assetQrCodeColumn) %>"><%= okLabel(assetQrCodeColumn) %></span>
                        </div>

                        <div class="health-row">
                            <div>
                                <strong>URL Matching Current Domain</strong>
                                <span>Mismatch count should become 0 after QR URL refresh.</span>
                            </div>
                            <span class="pill <%= okClass(urlHealthy) %>"><%= qrUrlMismatch %> mismatch</span>
                        </div>
                    </div>
                </div>

                <div class="panel">
                    <h2>Scan Audit Readiness</h2>

                    <div class="health-list">
                        <div class="health-row">
                            <div>
                                <strong>asset_qr_scan_logs Table</strong>
                                <span>Stores public QR scan records and invalid token attempts.</span>
                            </div>
                            <span class="pill <%= okClass(scanLogTable) %>"><%= okLabel(scanLogTable) %></span>
                        </div>

                        <div class="health-row">
                            <div>
                                <strong>Scan Token Column</strong>
                                <span>Stores token used during QR scan.</span>
                            </div>
                            <span class="pill <%= okClass(scanTokenColumn) %>"><%= okLabel(scanTokenColumn) %></span>
                        </div>

                        <div class="health-row">
                            <div>
                                <strong>Scan Status Column</strong>
                                <span>Stores SUCCESS / INVALID_TOKEN / FAILED status.</span>
                            </div>
                            <span class="pill <%= okClass(scanStatusColumn) %>"><%= okLabel(scanStatusColumn) %></span>
                        </div>

                        <div class="health-row">
                            <div>
                                <strong>Successful Scans</strong>
                                <span>Total successful public QR views.</span>
                            </div>
                            <span class="pill good"><%= successScans %></span>
                        </div>

                        <div class="health-row">
                            <div>
                                <strong>Invalid Token Scans</strong>
                                <span>Invalid or unknown QR token attempts.</span>
                            </div>
                            <span class="pill <%= invalidScans == 0 ? "good" : "bad" %>"><%= invalidScans %></span>
                        </div>

                        <div class="health-row">
                            <div>
                                <strong>Today Scans</strong>
                                <span>QR scans recorded today.</span>
                            </div>
                            <span class="pill good"><%= todayScans %></span>
                        </div>
                    </div>
                </div>
            </section>

            <section class="panel">
                <h2>Recommended Next Action</h2>

                <div class="health-list">
                    <% if (!qrCoreReady) { %>
                        <div class="health-row">
                            <div>
                                <strong>QR core is not fully ready</strong>
                                <span>Check assets table and QR columns before printing labels.</span>
                            </div>
                            <span class="pill bad">Fix Required</span>
                        </div>
                    <% } else if (qrGenerated == 0 || qrMissing > 0) { %>
                        <div class="health-row">
                            <div>
                                <strong>Generate missing QR tokens</strong>
                                <span><%= qrMissing %> asset(s) still do not have QR token.</span>
                            </div>
                            <a href="qr_bulk_generate.jsp" class="action-btn primary">Generate QR</a>
                        </div>
                    <% } else if (qrUrlMismatch > 0) { %>
                        <div class="health-row">
                            <div>
                                <strong>Refresh QR URL field</strong>
                                <span><%= qrUrlMismatch %> stored QR URL(s) do not match current application base URL.</span>
                            </div>
                            <a href="qr_url_refresh.jsp" class="action-btn primary">Refresh URLs</a>
                        </div>
                    <% } else if (!scanAuditReady) { %>
                        <div class="health-row">
                            <div>
                                <strong>Scan audit is not fully ready</strong>
                                <span>Check asset_qr_scan_logs table and required scan columns.</span>
                            </div>
                            <span class="pill bad">Fix Required</span>
                        </div>
                    <% } else { %>
                        <div class="health-row">
                            <div>
                                <strong>QR system is healthy</strong>
                                <span>QR tokens, URL field, public view, and scan audit are ready for use.</span>
                            </div>
                            <span class="pill good">Ready</span>
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