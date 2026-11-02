<%@page contentType="text/html" pageEncoding="UTF-8"%>
<%@page import="com.mycompany.asset_management_system_ams.DBConnection"%>
<%@page import="java.sql.*"%>
<%@page import="java.util.*"%>
<%@page import="java.text.NumberFormat"%>
<%@page import="java.text.DecimalFormat"%>

<%!
    private String safeText(Object value) {
        if (value == null || String.valueOf(value).trim().isEmpty()) {
            return "N/A";
        }

        return String.valueOf(value).trim()
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

    private String indianNumber(long value) {
        try {
            NumberFormat nf = NumberFormat.getNumberInstance(new Locale("en", "IN"));
            nf.setMaximumFractionDigits(0);
            return nf.format(value);
        } catch (Exception e) {
            return String.valueOf(value);
        }
    }

    private String compactIndianNumber(long value) {
        long absValue = Math.abs(value);
        String sign = value < 0 ? "-" : "";
        DecimalFormat df = new DecimalFormat("#.#");

        if (absValue >= 10000000L) {
            return sign + df.format(absValue / 10000000.0) + "Cr+";
        }

        if (absValue >= 100000L) {
            return sign + df.format(absValue / 100000.0) + "L+";
        }

        if (absValue >= 1000L) {
            return sign + df.format(absValue / 1000.0) + "K+";
        }

        return indianNumber(value);
    }

    private String compactIndianCurrency(double value) {
        return "₹" + compactIndianNumber(Math.round(value));
    }

    private String decimalOne(double value) {
        return String.format(Locale.ENGLISH, "%.1f", value);
    }

    private double percent(long part, long total) {
        if (total <= 0) {
            return 0.0;
        }

        return (part * 100.0) / total;
    }

    private boolean tableExists(String tableName) {
        String sql = "SELECT COUNT(*) FROM information_schema.tables "
                + "WHERE table_schema = DATABASE() AND table_name = ?";

        try (Connection con = DBConnection.getConnection();
             PreparedStatement ps = con.prepareStatement(sql)) {

            ps.setString(1, tableName);

            try (ResultSet rs = ps.executeQuery()) {
                return rs.next() && rs.getInt(1) > 0;
            }

        } catch (Exception e) {
            e.printStackTrace();
            return false;
        }
    }

    private boolean columnExists(String tableName, String columnName) {
        String sql = "SELECT COUNT(*) FROM information_schema.columns "
                + "WHERE table_schema = DATABASE() AND table_name = ? AND column_name = ?";

        try (Connection con = DBConnection.getConnection();
             PreparedStatement ps = con.prepareStatement(sql)) {

            ps.setString(1, tableName);
            ps.setString(2, columnName);

            try (ResultSet rs = ps.executeQuery()) {
                return rs.next() && rs.getInt(1) > 0;
            }

        } catch (Exception e) {
            e.printStackTrace();
            return false;
        }
    }

    private int sqlInt(String sql) {
        try (Connection con = DBConnection.getConnection();
             PreparedStatement ps = con.prepareStatement(sql);
             ResultSet rs = ps.executeQuery()) {

            if (rs.next()) {
                return rs.getInt(1);
            }

        } catch (Exception e) {
            e.printStackTrace();
        }

        return 0;
    }

    private double sqlDouble(String sql) {
        try (Connection con = DBConnection.getConnection();
             PreparedStatement ps = con.prepareStatement(sql);
             ResultSet rs = ps.executeQuery()) {

            if (rs.next()) {
                return rs.getDouble(1);
            }

        } catch (Exception e) {
            e.printStackTrace();
        }

        return 0.0;
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

    boolean allowedRole = ("SUPER_ADMIN".equals(role) || "ADMIN".equals(role))
            || "ASSET_MANAGER".equalsIgnoreCase(role)
            || "DEPARTMENT_HEAD".equalsIgnoreCase(role)
            || "AUDITOR".equalsIgnoreCase(role);

    if (!allowedRole) {
        response.sendRedirect("dashboard.jsp?access=denied");
        return;
    }

    boolean isSuperAdmin = ("SUPER_ADMIN".equals(role) || "ADMIN".equals(role));
    boolean isAssetManager = "ASSET_MANAGER".equalsIgnoreCase(role);
    boolean isAuditor = "AUDITOR".equalsIgnoreCase(role);

    boolean canExportReports = isSuperAdmin || isAssetManager || isAuditor;

    boolean hasAssets = tableExists("assets");
    boolean hasEmployees = tableExists("employees");
    boolean hasRequests = tableExists("asset_requests");
    boolean hasReturns = tableExists("asset_returns");
    boolean hasMaintenance = tableExists("maintenance_logs");
    boolean hasDisposal = tableExists("asset_disposal");
    boolean hasPV = tableExists("asset_physical_verification");
    boolean hasQrScan = tableExists("asset_qr_scan_logs");
    boolean hasQrTagging = tableExists("asset_qr_tagging_status");

    boolean assetsHasStatus = hasAssets && columnExists("assets", "asset_status");
    boolean assetsHasCost = hasAssets && columnExists("assets", "purchase_cost");
    boolean assetsHasQrPublicToken = hasAssets && columnExists("assets", "qr_public_token");

    int totalAssets = hasAssets ? sqlInt("SELECT COUNT(*) FROM assets") : 0;
    int totalEmployees = hasEmployees ? sqlInt("SELECT COUNT(*) FROM employees") : 0;
    int totalRequests = hasRequests ? sqlInt("SELECT COUNT(*) FROM asset_requests") : 0;
    int totalReturns = hasReturns ? sqlInt("SELECT COUNT(*) FROM asset_returns") : 0;
    int totalMaintenance = hasMaintenance ? sqlInt("SELECT COUNT(*) FROM maintenance_logs") : 0;
    int totalDisposal = hasDisposal ? sqlInt("SELECT COUNT(*) FROM asset_disposal") : 0;

    int availableAssets = assetsHasStatus ? sqlInt("SELECT COUNT(*) FROM assets WHERE asset_status = 'AVAILABLE'") : 0;
    int allocatedAssets = assetsHasStatus ? sqlInt("SELECT COUNT(*) FROM assets WHERE asset_status = 'ALLOCATED'") : 0;
    int underMaintenanceAssets = assetsHasStatus ? sqlInt("SELECT COUNT(*) FROM assets WHERE asset_status = 'UNDER_MAINTENANCE'") : 0;
    int disposedAssets = assetsHasStatus ? sqlInt("SELECT COUNT(*) FROM assets WHERE asset_status = 'DISPOSED'") : 0;

    double totalAssetValue = assetsHasCost ? sqlDouble("SELECT COALESCE(SUM(purchase_cost), 0) FROM assets") : 0.0;

    double availablePercent = percent(availableAssets, totalAssets);
    double allocatedPercent = percent(allocatedAssets, totalAssets);
    double maintenancePercent = percent(underMaintenanceAssets, totalAssets);
    double disposedPercent = percent(disposedAssets, totalAssets);

    int pvTotalRecords = 0;
    int pvVerified = 0;
    int pvMismatch = 0;
    int pvNotFound = 0;
    int pvDamagedReview = 0;

    if (hasPV) {
        pvTotalRecords = sqlInt("SELECT COUNT(*) FROM asset_physical_verification");
        pvVerified = sqlInt("SELECT COUNT(*) FROM asset_physical_verification WHERE verified_status = 'VERIFIED'");
        pvMismatch = sqlInt("SELECT COUNT(*) FROM asset_physical_verification WHERE verified_status IN ('LOCATION_MISMATCH','EMPLOYEE_MISMATCH')");
        pvNotFound = sqlInt("SELECT COUNT(*) FROM asset_physical_verification WHERE verified_status = 'NOT_FOUND'");
        pvDamagedReview = sqlInt("SELECT COUNT(*) FROM asset_physical_verification WHERE verified_status IN ('DAMAGED','UNDER_REPAIR','NEEDS_REVIEW')");
    }

    int qrGenerated = assetsHasQrPublicToken
            ? sqlInt("SELECT COUNT(*) FROM assets WHERE qr_public_token IS NOT NULL AND TRIM(qr_public_token) <> ''")
            : 0;

    int qrMissing = Math.max(totalAssets - qrGenerated, 0);
    int qrTotalScans = hasQrScan ? sqlInt("SELECT COUNT(*) FROM asset_qr_scan_logs") : 0;
    int qrInvalidScans = hasQrScan && columnExists("asset_qr_scan_logs", "scan_status")
            ? sqlInt("SELECT COUNT(*) FROM asset_qr_scan_logs WHERE scan_status = 'INVALID_TOKEN'")
            : 0;

    int qrTagged = hasQrTagging && columnExists("asset_qr_tagging_status", "tag_status")
            ? sqlInt("SELECT COUNT(*) FROM asset_qr_tagging_status WHERE tag_status = 'TAGGED'")
            : 0;

    int qrPendingTagging = Math.max(qrGenerated - qrTagged, 0);

    String userInitial = username.substring(0, Math.min(2, username.length())).toUpperCase(Locale.ENGLISH);
%>

<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>IR-AMS Reports & Analytics</title>

    <link rel="stylesheet"
          href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.0/css/all.min.css">

    <link rel="stylesheet" href="css/ir-glass.css?v=28000">
    <link rel="stylesheet" href="css/ams-pro.css?v=28000">
    <link rel="stylesheet" href="css/ir-ams-railway-ui.css?v=28000">
<link rel="stylesheet" href="css/reports.css?v=topbarfix1">
</head>

<body class="railway-ui">
<div class="app ams-shell">

    <jsp:include page="sidebar.jsp" />

    <main class="main railway-main">
        <jsp:include page="topbar.jsp" />

        <div class="main-scroll-content reports-board">

            <section class="reports-hero-new">
                <div class="reports-hero-copy">
                    <span class="eyebrow">
                        <i class="fa-solid fa-chart-line"></i>
                        Railway Reports &amp; Analytics
                    </span>

                    <h1>Official Asset Reports</h1>

                    <p>
                        Generate railway-grade reports for asset register, allocations, returns,
                        maintenance, warranty, physical verification, disposal and planning requests.
                    </p>

                    <div class="hero-pills-new">
                        <span class="hero-pill-new"><i class="fa-solid fa-file-excel"></i> Excel Ready</span>
                        <span class="hero-pill-new"><i class="fa-solid fa-shield-halved"></i> Audit Logged</span>
                        <span class="hero-pill-new"><i class="fa-solid fa-building-columns"></i> ECoR HQ</span>
                    </div>
                </div>
            </section>

            <section class="reports-kpi-grid">
                <div class="reports-kpi">
                    <div class="kpi-icon"><i class="fa-solid fa-cubes"></i></div>
                    <div>
                        <h3>Total Assets</h3>
                        <p><%= indianNumber(totalAssets) %></p>
                    </div>
                </div>

                <div class="reports-kpi">
                    <div class="kpi-icon"><i class="fa-solid fa-users"></i></div>
                    <div>
                        <h3>Holders</h3>
                        <p><%= indianNumber(totalEmployees) %></p>
                    </div>
                </div>

                <div class="reports-kpi">
                    <div class="kpi-icon"><i class="fa-solid fa-right-left"></i></div>
                    <div>
                        <h3>Allocations</h3>
                        <p><%= indianNumber(allocatedAssets) %></p>
                    </div>
                </div>

                <div class="reports-kpi">
                    <div class="kpi-icon"><i class="fa-solid fa-screwdriver-wrench"></i></div>
                    <div>
                        <h3>Maintenance</h3>
                        <p><%= indianNumber(totalMaintenance) %></p>
                    </div>
                </div>

                <div class="reports-kpi">
                    <div class="kpi-icon"><i class="fa-solid fa-recycle"></i></div>
                    <div>
                        <h3>Disposal</h3>
                        <p><%= indianNumber(totalDisposal) %></p>
                    </div>
                </div>

                <div class="reports-kpi">
                    <div class="kpi-icon"><i class="fa-solid fa-indian-rupee-sign"></i></div>
                    <div>
                        <h3>Asset Value</h3>
                        <p><%= compactIndianCurrency(totalAssetValue) %></p>
                    </div>
                </div>
            </section>

            <section class="report-panel">
                <div class="panel-head">
                    <div>
                        <h2>Report Actions</h2>
                        <p>Export-ready official reports for railway asset management use.</p>
                    </div>
                </div>

                <div class="report-card-grid">
                    <% if (canExportReports) { %>

                        <a href="warranty_report.jsp" class="report-card">
                            <i class="fa-solid fa-shield-halved"></i>
                            <div>
                                <strong>Warranty Report</strong>
                                <span>Open warranty tracking and expiring warranty list.</span>
                            </div>
                        </a>

                        <a href="depreciation_report.jsp" class="report-card">
                            <i class="fa-solid fa-chart-line"></i>
                            <div>
                                <strong>Depreciation Report</strong>
                                <span>Live straight-line book value and accumulated depreciation per asset.</span>
                            </div>
                        </a>

                        <a href="export_asset_report.jsp" class="report-card green">
                            <i class="fa-solid fa-boxes-stacked"></i>
                            <div>
                                <strong>Asset Report Excel</strong>
                                <span>Export complete asset register report.</span>
                            </div>
                        </a>

                        <a href="export_employee_report.jsp" class="report-card green">
                            <i class="fa-solid fa-users"></i>
                            <div>
                                <strong>Employee Report Excel</strong>
                                <span>Export holder and employee report.</span>
                            </div>
                        </a>

                        <a href="export_maintenance.jsp" class="report-card green">
                            <i class="fa-solid fa-screwdriver-wrench"></i>
                            <div>
                                <strong>Maintenance Report Excel</strong>
                                <span>Export maintenance and repair report.</span>
                            </div>
                        </a>

                        <a href="export_allocation_report.jsp" class="report-card green">
                            <i class="fa-solid fa-right-left"></i>
                            <div>
                                <strong>Allocation Report Excel</strong>
                                <span>Export issue, allocation and return status report.</span>
                            </div>
                        </a>

                        <a href="export_returns_report.jsp" class="report-card green">
                            <i class="fa-solid fa-rotate-left"></i>
                            <div>
                                <strong>Returns Report Excel</strong>
                                <span>Export official asset return register.</span>
                            </div>
                        </a>

                        <a href="export_requests_report.jsp" class="report-card orange">
                            <i class="fa-solid fa-file-circle-plus"></i>
                            <div>
                                <strong>Requests Report Excel</strong>
                                <span>Export planning and asset request register.</span>
                            </div>
                        </a>

                        <a href="export_disposal_report.jsp" class="report-card red">
                            <i class="fa-solid fa-recycle"></i>
                            <div>
                                <strong>Disposal Report Excel</strong>
                                <span>Export disposed, retired and written-off asset records.</span>
                            </div>
                        </a>

                        <a href="export_transfer_report.jsp" class="report-card">
                            <i class="fa-solid fa-right-left"></i>
                            <div>
                                <strong>Transfer Report Excel</strong>
                                <span>Export employee-to-employee asset transfer requests and their review history.</span>
                            </div>
                        </a>

                        <a href="export_warranty_report.jsp" class="report-card orange">
                            <i class="fa-solid fa-shield-halved"></i>
                            <div>
                                <strong>Warranty Report Excel</strong>
                                <span>Export warranty expiry and AMC tracking report.</span>
                            </div>
                        </a>

                        <a href="ExportPhysicalVerificationReportServlet?status=ALL" class="report-card orange">
                            <i class="fa-solid fa-clipboard-check"></i>
                            <div>
                                <strong>Physical Verification Excel</strong>
                                <span>Export physical verification report.</span>
                            </div>
                        </a>

                        <%-- Fault: this card linked to export_qr_asset_register_excel.jsp, a
                             212-line stub that sets up the xlsx response headers and then ends -
                             the entire POI workbook-building/query/write body was missing, so
                             Tomcat served a 200 OK with a completely empty (0-byte) body: a
                             silently corrupt "download" with no error shown anywhere. Repointed
                             to export_qr_asset_register.jsp - the complete, 559-line, already
                             working implementation of the exact same export that
                             qr_asset_register.jsp's own "Export" button already uses (confirmed
                             live: real non-empty .xlsx). --%>
                        <a href="export_qr_asset_register.jsp?qr=ALL" class="report-card green">
                            <i class="fa-solid fa-qrcode"></i>
                            <div>
                                <strong>QR Asset Register Excel</strong>
                                <span>Export QR token and asset register coverage.</span>
                            </div>
                        </a>

                        <%-- Fault: same issue as above - export_qr_scan_logs_excel.jsp was a
                             40-line stub whose only content was a corrupted helper method (a
                             catch block referencing `response`, which isn't in scope inside a
                             <%! %> declaration - a genuine JSP compile error, 500 on every
                             request) with no report-generation body at all. Repointed to
                             export_qr_scan_logs.jsp - the complete, 612-line implementation
                             qr_scan_logs.jsp's own "Export Excel" button already uses (confirmed
                             live: real non-empty .xlsx). --%>
                        <a href="export_qr_scan_logs.jsp?status=ALL" class="report-card">
                            <i class="fa-solid fa-list-check"></i>
                            <div>
                                <strong>QR Scan Logs Excel</strong>
                                <span>Export public and internal QR verification scan activity.</span>
                            </div>
                        </a>

                        <a href="export_qr_coverage_report_excel.jsp" class="report-card orange">
                            <i class="fa-solid fa-chart-pie"></i>
                            <div>
                                <strong>QR Coverage Excel</strong>
                                <span>Export QR generated, missing and tagging coverage.</span>
                            </div>
                        </a>

                        <a href="export_audit_logs.jsp" class="report-card">
                            <i class="fa-solid fa-clipboard-list"></i>
                            <div>
                                <strong>Audit Logs Excel</strong>
                                <span>Export inspection and audit activity logs.</span>
                            </div>
                        </a>

                    <% } else { %>

                        <div class="notice-box">
                            <i class="fa-solid fa-lock"></i>
                            Export access is restricted to Super Admin, Asset Manager and Auditor.
                        </div>

                        <%-- This used to also show a "Warranty Report" link to whoever lands in
                             this branch (currently only DEPARTMENT_HEAD). warranty_report.jsp's
                             own RoleAccessUtil entry (matching dashboard.jsp's canViewWarranty,
                             which deliberately routes DEPARTMENT_HEAD to an access-denied page
                             instead of linking there) does NOT include DEPARTMENT_HEAD, so that
                             link always 403'd - the two pages disagreed on this role's access,
                             and RoleAccessUtil + dashboard.jsp's own explicit denial were the
                             better-corroborated source of truth. Removed here to match rather
                             than widening access to a report covering asset data across every
                             department. --%>

                    <% } %>
                </div>
            </section>

            <section class="split-grid">
                <div class="report-panel">
                    <div class="panel-head">
                        <div>
                            <h2>Asset Status Summary</h2>
                            <p>Live asset distribution based on current asset status.</p>
                        </div>
                    </div>

                    <div class="status-grid">
                        <div class="status-card">
                            <h4>Available</h4>
                            <p><%= indianNumber(availableAssets) %></p>
                            <span><%= decimalOne(availablePercent) %>% of total assets</span>
                        </div>

                        <div class="status-card">
                            <h4>Allocated</h4>
                            <p><%= indianNumber(allocatedAssets) %></p>
                            <span><%= decimalOne(allocatedPercent) %>% of total assets</span>
                        </div>

                        <div class="status-card">
                            <h4>Under Maintenance</h4>
                            <p><%= indianNumber(underMaintenanceAssets) %></p>
                            <span><%= decimalOne(maintenancePercent) %>% of total assets</span>
                        </div>

                        <div class="status-card">
                            <h4>Disposed</h4>
                            <p><%= indianNumber(disposedAssets) %></p>
                            <span><%= decimalOne(disposedPercent) %>% of total assets</span>
                        </div>
                    </div>
                </div>

                <div class="report-panel">
                    <div class="panel-head">
                        <div>
                            <h2>Operational Register Summary</h2>
                            <p>Planning, returns, maintenance and disposal register counts.</p>
                        </div>
                    </div>

                    <div class="status-grid">
                        <div class="status-card">
                            <h4>Requests</h4>
                            <p><%= indianNumber(totalRequests) %></p>
                            <span>Planning and asset demand records</span>
                        </div>

                        <div class="status-card">
                            <h4>Returns</h4>
                            <p><%= indianNumber(totalReturns) %></p>
                            <span>Returned asset records</span>
                        </div>

                        <div class="status-card">
                            <h4>Maintenance</h4>
                            <p><%= indianNumber(totalMaintenance) %></p>
                            <span>Repair and service records</span>
                        </div>

                        <div class="status-card">
                            <h4>Disposal</h4>
                            <p><%= indianNumber(totalDisposal) %></p>
                            <span>Retired and written-off assets</span>
                        </div>
                    </div>
                </div>
            </section>

            <section class="report-panel">
                <div class="panel-head">
                    <div>
                        <h2>Physical Verification Summary</h2>
                        <p>Summary of physical inspection and verification outcomes.</p>
                    </div>
                </div>

                <div class="status-grid">
                    <div class="status-card">
                        <h4>Total Verification Records</h4>
                        <p><%= indianNumber(pvTotalRecords) %></p>
                        <span>All submitted verification entries</span>
                    </div>

                    <div class="status-card">
                        <h4>Verified</h4>
                        <p><%= indianNumber(pvVerified) %></p>
                        <span>Assets found correct</span>
                    </div>

                    <div class="status-card">
                        <h4>Mismatch</h4>
                        <p><%= indianNumber(pvMismatch) %></p>
                        <span>Location or holder mismatch</span>
                    </div>

                    <div class="status-card">
                        <h4>Not Found / Review</h4>
                        <p><%= indianNumber(pvNotFound + pvDamagedReview) %></p>
                        <span>Missing, damaged or needs review</span>
                    </div>
                </div>
            </section>

            <section class="report-panel">
                <div class="panel-head">
                    <div>
                        <h2>QR Report Summary</h2>
                        <p>QR generation, tagging and scan activity summary.</p>
                    </div>
                </div>

                <div class="status-grid">
                    <div class="status-card">
                        <h4>QR Generated</h4>
                        <p><%= indianNumber(qrGenerated) %></p>
                        <span>Assets with public QR token</span>
                    </div>

                    <div class="status-card">
                        <h4>QR Missing</h4>
                        <p><%= indianNumber(qrMissing) %></p>
                        <span>Assets pending QR generation</span>
                    </div>

                    <div class="status-card">
                        <h4>Total QR Scans</h4>
                        <p><%= indianNumber(qrTotalScans) %></p>
                        <span>Recorded scan attempts</span>
                    </div>

                    <div class="status-card">
                        <h4>Pending Tagging</h4>
                        <p><%= indianNumber(qrPendingTagging) %></p>
                        <span>Generated but not tagged physically</span>
                    </div>
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
