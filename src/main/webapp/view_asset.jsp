﻿<%@page contentType="text/html" pageEncoding="UTF-8"%>
<%@page import="com.mycompany.asset_management_system_ams.DBConnection"%>
<%@page import="com.mycompany.asset_management_system_ams.QrUrlUtil"%>
<%@page import="com.mycompany.asset_management_system_ams.AssetDocument"%>
<%@page import="com.mycompany.asset_management_system_ams.AssetDocumentDAO"%>
<%@page import="com.mycompany.asset_management_system_ams.DepreciationUtil"%>
<%@page import="java.text.DecimalFormat"%>
<%@page import="java.sql.*"%>
<%@page import="java.util.*"%>
<%@page import="java.net.URLEncoder"%>
<%@page import="jakarta.servlet.http.HttpServletRequest"%>

<%!
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

    private String rowValue(Map<String, String> row, String key) {
        if (row == null) {
            return "";
        }

        String value = row.get(key);
        return value == null ? "" : value;
    }

    private double parseSafeDouble(String value) {
        try {
            return value == null || value.trim().isEmpty() ? 0.0 : Double.parseDouble(value.trim());
        } catch (Exception e) {
            return 0.0;
        }
    }

    private String statusClass(String status) {
        if (status == null || status.trim().isEmpty()) {
            return "UNKNOWN";
        }

        return status.trim().toUpperCase(Locale.ENGLISH).replace(" ", "_");
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
            e.printStackTrace();
        }

        return false;
    }

    private Map<String, String> singleRow(String sql, String id) {
        Map<String, String> row = new HashMap<String, String>();

        try (Connection con = DBConnection.getConnection();
             PreparedStatement ps = con.prepareStatement(sql)) {

            ps.setString(1, id);

            try (ResultSet rs = ps.executeQuery()) {
                ResultSetMetaData meta = rs.getMetaData();
                int count = meta.getColumnCount();

                if (rs.next()) {
                    for (int i = 1; i <= count; i++) {
                        row.put(meta.getColumnLabel(i), rs.getString(i));
                    }
                }
            }

        } catch (Exception e) {
            e.printStackTrace();
        }

        return row;
    }

    private List<Map<String, String>> listRows(String sql, String id) {
        return listRows(sql, id, 1);
    }

    private List<Map<String, String>> listRows(String sql, String id, int parameterCount) {
        List<Map<String, String>> rows = new ArrayList<Map<String, String>>();

        try (Connection con = DBConnection.getConnection();
             PreparedStatement ps = con.prepareStatement(sql)) {

            int bindCount = Math.max(parameterCount, 1);

            for (int i = 1; i <= bindCount; i++) {
                ps.setString(i, id);
            }

            try (ResultSet rs = ps.executeQuery()) {
                ResultSetMetaData meta = rs.getMetaData();
                int columnCount = meta.getColumnCount();

                while (rs.next()) {
                    Map<String, String> row = new HashMap<String, String>();

                    for (int i = 1; i <= columnCount; i++) {
                        row.put(meta.getColumnLabel(i), rs.getString(i));
                    }

                    rows.add(row);
                }
            }

        } catch (Exception e) {
            e.printStackTrace();
        }

        return rows;
    }

    private int singleInt(String sql, String id) {
        try (Connection con = DBConnection.getConnection();
             PreparedStatement ps = con.prepareStatement(sql)) {

            ps.setString(1, id);

            try (ResultSet rs = ps.executeQuery()) {
                if (rs.next()) {
                    return rs.getInt(1);
                }
            }

        } catch (Exception e) {
            e.printStackTrace();
        }

        return 0;
    }

    private int parseIntValue(String value, int fallback) {
        try {
            return Integer.parseInt(value == null ? "" : value.trim());
        } catch (Exception e) {
            return fallback;
        }
    }

    private String formatFileSize(long bytes) {
        if (bytes <= 0) {
            return "N/A";
        }

        if (bytes < 1024) {
            return bytes + " B";
        }

        double kb = bytes / 1024.0;

        if (kb < 1024) {
            return String.format(Locale.ENGLISH, "%.1f KB", kb);
        }

        return String.format(Locale.ENGLISH, "%.1f MB", kb / 1024.0);
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

    boolean canManageAssets = ("SUPER_ADMIN".equals(role) || "ADMIN".equals(role)) || "ASSET_MANAGER".equals(role);

    String assetId = request.getParameter("id");

    if (assetId == null || assetId.trim().isEmpty()) {
        assetId = request.getParameter("asset_id");
    }

    if (assetId == null || assetId.trim().isEmpty()) {
        response.sendRedirect("assets.jsp?error=invalid_asset");
        return;
    }

    assetId = assetId.trim();

    int assetIdValue = parseIntValue(assetId, 0);

    if (assetIdValue <= 0) {
        response.sendRedirect("assets.jsp?error=invalid_asset");
        return;
    }

    assetId = String.valueOf(assetIdValue);

    Map<String, String> asset = singleRow(
            "SELECT "
            + "a.asset_id, a.asset_code, a.asset_name, a.serial_number, a.model_number, "
            + "DATE_FORMAT(a.purchase_date, '%d %b %Y') AS purchase_date, "
            + "COALESCE(a.purchase_cost, 0) AS purchase_cost, "
            + "COALESCE(TIMESTAMPDIFF(MONTH, a.purchase_date, CURDATE()), 0) AS asset_age_months, "
            + "a.purchase_date AS purchase_date_iso, "
            + "DATE_FORMAT(a.warranty_expiry, '%d %b %Y') AS warranty_expiry, "
            + "CASE "
            + "WHEN a.warranty_expiry IS NULL THEN 'NOT_RECORDED' "
            + "WHEN a.warranty_expiry < CURDATE() THEN 'EXPIRED' "
            + "WHEN a.warranty_expiry <= DATE_ADD(CURDATE(), INTERVAL 90 DAY) THEN 'EXPIRING_SOON' "
            + "ELSE 'ACTIVE' END AS warranty_status, "
            + "DATEDIFF(a.warranty_expiry, CURDATE()) AS warranty_days_remaining, "
            + "a.asset_status, a.condition_status, a.service_status, "
            + "DATE_FORMAT(a.last_physical_verification_date, '%d %b %Y') AS last_physical_verification_date, "
            + "a.qr_code, a.qr_public_token, a.asset_image_path, a.depreciation_rate, a.remarks, "
            + "DATE_FORMAT(a.created_at, '%d %b %Y, %h:%i %p') AS created_at, "
            + "DATE_FORMAT(a.updated_at, '%d %b %Y, %h:%i %p') AS updated_at, "
            + "COALESCE(ac.category_name, 'Uncategorized') AS category_name, "
            + "COALESCE(v.vendor_name, 'No Supplier') AS vendor_name, "
            + "COALESCE(v.contact_person, '') AS vendor_contact_person, "
            + "COALESCE(v.phone, '') AS vendor_phone, "
            + "COALESCE(v.email, '') AS vendor_email, "
            + "COALESCE(d.department_name, 'Unassigned') AS department_name, "
            + "COALESCE(rd.division_name, '') AS division_name, "
            + "COALESCE(rd.division_headquarters, '') AS division_headquarters, "
            + "COALESCE(rl.location_name, a.location, '') AS location_name, "
            + "COALESCE(rl.location_code, '') AS location_code, "
            + "COALESCE(rl.location_type, '') AS location_type, "
            + "COALESCE(rl.building_block, '') AS building_block, "
            + "COALESCE(rl.floor_level, '') AS floor_level, "
            + "COALESCE(rl.room_no, '') AS room_no "
            + "FROM assets a "
            + "LEFT JOIN asset_categories ac ON a.category_id = ac.category_id "
            + "LEFT JOIN vendors v ON a.vendor_id = v.vendor_id "
            + "LEFT JOIN departments d ON a.department_id = d.department_id "
            + "LEFT JOIN railway_divisions rd ON a.division_id = rd.division_id "
            + "LEFT JOIN railway_locations rl ON a.location_id = rl.location_id "
            + "WHERE a.asset_id = ? "
            + "LIMIT 1",
            assetId
    );

    if (asset.isEmpty()) {
        response.sendRedirect("assets.jsp?error=asset_notfound");
        return;
    }

    // Same DepreciationUtil calculation now used everywhere else in the app
    // (depreciation_report.jsp, AssetDAO.reviewDisposal()'s write-off figure) -
    // this used to be its own inline SQL formula here, the only place in the
    // entire codebase that computed a book value at all.
    double purchaseCostVal = parseSafeDouble(rowValue(asset, "purchase_cost"));
    double depreciationRateVal = parseSafeDouble(rowValue(asset, "depreciation_rate"));
    String purchaseDateIso = asset.get("purchase_date_iso");
    DecimalFormat depreciationMoneyFormat = new DecimalFormat("0.00");
    asset.put("estimated_book_value", depreciationMoneyFormat.format(
            DepreciationUtil.computeBookValue(purchaseCostVal, depreciationRateVal, purchaseDateIso, null)));
    asset.put("estimated_depreciation_amount", depreciationMoneyFormat.format(
            DepreciationUtil.computeAccumulatedDepreciation(purchaseCostVal, depreciationRateVal, purchaseDateIso, null)));

    Map<String, String> activeAllocation = singleRow(
            "SELECT "
            + "aa.allocation_id, DATE_FORMAT(aa.allocation_date, '%d %b %Y') AS allocation_date, "
            + "DATE_FORMAT(aa.expected_return_date, '%d %b %Y') AS expected_return_date, "
            + "aa.allocation_status, aa.issue_condition, aa.remarks, "
            + "COALESCE(e.employee_code, '') AS employee_code, "
            + "COALESCE(e.employee_name, '') AS full_name, "
            + "COALESCE(e.designation, '') AS designation, "
            + "COALESCE(e.email, '') AS employee_email, "
            + "COALESCE(e.phone, '') AS employee_phone, "
            + "COALESCE(d.department_name, '') AS holder_department "
            + "FROM asset_allocation aa "
            + "LEFT JOIN employees e ON aa.employee_id = e.employee_id "
            + "LEFT JOIN departments d ON e.department_id = d.department_id "
            + "WHERE aa.asset_id = ? AND aa.allocation_status = 'ALLOCATED' "
            + "ORDER BY aa.allocation_id DESC "
            + "LIMIT 1",
            assetId
    );

    List<Map<String, String>> maintenanceRows = listRows(
            "SELECT "
            + "ml.maintenance_id, ml.maintenance_type, "
            + "DATE_FORMAT(ml.maintenance_date, '%d %b %Y') AS maintenance_date, "
            + "DATE_FORMAT(ml.next_due_date, '%d %b %Y') AS next_due_date, "
            + "ml.maintenance_status, COALESCE(ml.cost, 0) AS cost, "
            + "COALESCE(ml.issue_reported, '') AS issue_reported, "
            + "COALESCE(ml.work_done, '') AS work_done, "
            + "COALESCE(v.vendor_name, '') AS vendor_name "
            + "FROM maintenance_logs ml "
            + "LEFT JOIN vendors v ON ml.vendor_id = v.vendor_id "
            + "WHERE ml.asset_id = ? "
            + "ORDER BY ml.maintenance_id DESC "
            + "LIMIT 5",
            assetId
    );

    List<Map<String, String>> allocationRows = listRows(
            "SELECT "
            + "aa.allocation_id, DATE_FORMAT(aa.allocation_date, '%d %b %Y') AS allocation_date, "
            + "DATE_FORMAT(aa.return_date, '%d %b %Y') AS return_date, "
            + "aa.allocation_status, aa.issue_condition, "
            + "COALESCE(e.employee_code, '') AS employee_code, "
            + "COALESCE(e.employee_name, '') AS full_name "
            + "FROM asset_allocation aa "
            + "LEFT JOIN employees e ON aa.employee_id = e.employee_id "
            + "WHERE aa.asset_id = ? "
            + "ORDER BY aa.allocation_id DESC "
            + "LIMIT 5",
            assetId
    );

    List<Map<String, String>> verificationRows = listRows(
            "SELECT "
            + "pv.verification_id, DATE_FORMAT(pv.verification_date, '%d %b %Y') AS verification_date, "
            + "pv.verification_status, pv.asset_found, pv.physical_condition, COALESCE(pv.remarks, '') AS remarks "
            + "FROM physical_verification pv "
            + "WHERE pv.asset_id = ? "
            + "ORDER BY pv.verification_id DESC "
            + "LIMIT 5",
            assetId
    );

    List<Map<String, String>> lifecycleRows = listRows(
            "SELECT event_type, event_icon, event_date, event_title, event_detail, event_status "
            + "FROM ("
            + "SELECT COALESCE(a.created_at, a.purchase_date) AS event_sort, "
            + "'REGISTERED' AS event_type, 'fa-cube' AS event_icon, "
            + "DATE_FORMAT(COALESCE(a.created_at, a.purchase_date), '%d %b %Y, %h:%i %p') AS event_date, "
            + "CONCAT('Asset registered: ', a.asset_code) AS event_title, "
            + "CONCAT('Category: ', COALESCE(ac.category_name, 'Uncategorized'), ' | Department: ', COALESCE(d.department_name, 'Unassigned')) AS event_detail, "
            + "a.asset_status AS event_status "
            + "FROM assets a "
            + "LEFT JOIN asset_categories ac ON a.category_id = ac.category_id "
            + "LEFT JOIN departments d ON a.department_id = d.department_id "
            + "WHERE a.asset_id = ? "
            + "UNION ALL "
            + "SELECT COALESCE(aa.created_at, aa.allocation_date), "
            + "'ALLOCATION', 'fa-arrow-right-arrow-left', "
            + "DATE_FORMAT(COALESCE(aa.created_at, aa.allocation_date), '%d %b %Y, %h:%i %p'), "
            + "CONCAT('Issued to ', COALESCE(e.employee_name, 'employee')), "
            + "CONCAT('Status: ', aa.allocation_status, ' | Issue condition: ', aa.issue_condition, ' | ', COALESCE(aa.remarks, '')), "
            + "aa.allocation_status "
            + "FROM asset_allocation aa "
            + "LEFT JOIN employees e ON aa.employee_id = e.employee_id "
            + "WHERE aa.asset_id = ? "
            + "UNION ALL "
            + "SELECT COALESCE(ar.created_at, ar.return_date), "
            + "'RETURN', 'fa-rotate-left', "
            + "DATE_FORMAT(COALESCE(ar.created_at, ar.return_date), '%d %b %Y, %h:%i %p'), "
            + "CONCAT('Returned by ', COALESCE(e.employee_name, 'employee')), "
            + "CONCAT('Condition: ', ar.return_condition, ' | Action: ', ar.action_after_return, ' | ', COALESCE(ar.remarks, '')), "
            + "ar.return_condition "
            + "FROM asset_returns ar "
            + "LEFT JOIN employees e ON ar.employee_id = e.employee_id "
            + "WHERE ar.asset_id = ? "
            + "UNION ALL "
            + "SELECT COALESCE(ml.created_at, ml.maintenance_date), "
            + "'MAINTENANCE', 'fa-screwdriver-wrench', "
            + "DATE_FORMAT(COALESCE(ml.created_at, ml.maintenance_date), '%d %b %Y, %h:%i %p'), "
            + "CONCAT(ml.maintenance_type, ' maintenance'), "
            + "CONCAT('Status: ', ml.maintenance_status, ' | Cost: Rs ', COALESCE(ml.cost, 0), ' | ', COALESCE(ml.issue_reported, '')), "
            + "ml.maintenance_status "
            + "FROM maintenance_logs ml "
            + "WHERE ml.asset_id = ? "
            + "UNION ALL "
            + "SELECT COALESCE(pv.created_at, pv.verification_date), "
            + "'PHYSICAL_VERIFICATION', 'fa-shield-halved', "
            + "DATE_FORMAT(COALESCE(pv.created_at, pv.verification_date), '%d %b %Y, %h:%i %p'), "
            + "CONCAT('Physical verification: ', pv.verification_status), "
            + "CONCAT('Found: ', pv.asset_found, ' | Condition: ', pv.physical_condition, ' | ', COALESCE(pv.remarks, '')), "
            + "pv.verification_status "
            + "FROM physical_verification pv "
            + "WHERE pv.asset_id = ? "
            + "UNION ALL "
            + "SELECT q.scanned_at, "
            + "'QR_SCAN', 'fa-qrcode', "
            + "DATE_FORMAT(q.scanned_at, '%d %b %Y, %h:%i %p'), "
            + "CONCAT(q.scan_source, ' QR scan'), "
            + "CONCAT('Result: ', q.scan_status, ' | IP: ', COALESCE(q.scan_ip, 'N/A')), "
            + "q.scan_status "
            + "FROM asset_qr_scan_logs q "
            + "WHERE q.asset_id = ? "
            + ") x "
            + "ORDER BY event_sort DESC "
            + "LIMIT 12",
            assetId,
            6
    );

    List<AssetDocument> assetDocuments = new AssetDocumentDAO().getDocumentsByAssetId(assetIdValue);

    int qrScanCount = 0;

    try (Connection con = DBConnection.getConnection()) {
        if (tableExists(con, "asset_qr_scan_logs")) {
            qrScanCount = singleInt(
                    "SELECT COUNT(*) FROM asset_qr_scan_logs WHERE asset_id = ?",
                    assetId
            );
        }
    } catch (Exception e) {
        e.printStackTrace();
    }

    String token = rowValue(asset, "qr_public_token");
    String liveUrl = "";

    String publicBaseUrl = QrUrlUtil.getConfiguredPublicBaseUrl();

    if (token != null && !token.trim().isEmpty() && !publicBaseUrl.trim().isEmpty()) {
        liveUrl = publicBaseUrl + "/public_asset_view.jsp?token=" + token.trim();
    }

    String qrImageUrl = "";

    if (!liveUrl.trim().isEmpty()) {
        qrImageUrl = "https://api.qrserver.com/v1/create-qr-code/?size=320x320&margin=12&data="
                + URLEncoder.encode(liveUrl, "UTF-8");
    }

    String assetStatus = rowValue(asset, "asset_status");
    String conditionStatus = rowValue(asset, "condition_status");
    String serviceStatus = rowValue(asset, "service_status");
    String assetImagePath = rowValue(asset, "asset_image_path");
    String assetImageSrc = (assetImagePath == null || assetImagePath.trim().isEmpty())
            ? "images/indian-railway-logo.png"
            : assetImagePath.trim();

    String userInitial = username.substring(0, Math.min(2, username.length())).toUpperCase(Locale.ENGLISH);

    String alertMessage = "";
    String alertClass = "success";

    if ("document_added".equalsIgnoreCase(request.getParameter("msg"))) {
        alertMessage = "Asset document uploaded and saved in MySQL successfully.";
    } else if ("document_upload".equalsIgnoreCase(request.getParameter("error"))) {
        alertMessage = "Asset document upload failed. Please check file type, size, and database connection.";
        alertClass = "error";
    } else if ("document_denied".equalsIgnoreCase(request.getParameter("error"))) {
        alertMessage = "You do not have permission to upload documents for this asset.";
        alertClass = "error";
    } else if ("document_missing".equalsIgnoreCase(request.getParameter("error"))) {
        alertMessage = "The requested asset document could not be found.";
        alertClass = "error";
    }
%>

<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>View Asset - IR-AMS</title>

    <link rel="stylesheet"
          href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.0/css/all.min.css">

    <link rel="stylesheet" href="css/ir-glass.css?v=asset-allocation-inner-1">
    <link rel="stylesheet" href="css/ams-pro.css?v=asset-allocation-inner-1">
    <link rel="stylesheet" href="css/ir-ams-railway-ui.css?v=asset-allocation-inner-1">
<link rel="stylesheet" href="css/view_asset.css?v=topbarfix1">
</head>

<body class="railway-ui">
<div class="app ams-shell">

    <jsp:include page="sidebar.jsp" />

    <main class="main railway-main">
        <jsp:include page="topbar.jsp" />

        <div class="main-scroll-content view-board">

            <section class="view-hero">
                <div>
                    <h1><%= safeText(rowValue(asset, "asset_name")) %></h1>
                    <p>
                        <strong><%= safeText(rowValue(asset, "asset_code")) %></strong>
                        · <%= safeText(rowValue(asset, "category_name")) %>
                        · <%= safeText(rowValue(asset, "department_name")) %>
                    </p>
                </div>

                <div class="hero-actions">
                    <a href="assets.jsp" class="action-btn">
                        <i class="fa-solid fa-arrow-left"></i>
                        Back to Assets
                    </a>

                    <% if (canManageAssets && !"DISPOSED".equalsIgnoreCase(assetStatus)) { %>
                        <a href="edit_asset.jsp?id=<%= safeText(assetId) %>" class="action-btn gold">
                            <i class="fa-solid fa-pen-to-square"></i>
                            Edit Asset
                        </a>
                    <% } %>

                    <a href="asset_qr_card.jsp?id=<%= safeText(assetId) %>" class="action-btn primary">
                        <i class="fa-solid fa-qrcode"></i>
                        View QR
                    </a>

                    <a href="qr_print.jsp?id=<%= safeText(assetId) %>" class="action-btn green">
                        <i class="fa-solid fa-print"></i>
                        Print QR
                    </a>
                </div>
            </section>

            <% if (!alertMessage.trim().isEmpty()) { %>
                <div class="page-alert <%= safeText(alertClass) %>">
                    <i class="fa-solid <%= "error".equals(alertClass) ? "fa-circle-exclamation" : "fa-circle-check" %>"></i>
                    <%= safeText(alertMessage) %>
                </div>
            <% } %>

            <section class="status-row">
                <div class="status-card">
                    <span>Asset Status</span>
                    <strong>
                        <span class="status-badge status-<%= safeText(statusClass(assetStatus)) %>">
                            <%= safeText(cleanLabel(assetStatus)) %>
                        </span>
                    </strong>
                </div>

                <div class="status-card">
                    <span>Condition Status</span>
                    <strong>
                        <span class="status-badge status-<%= safeText(statusClass(conditionStatus)) %>">
                            <%= safeText(cleanLabel(conditionStatus)) %>
                        </span>
                    </strong>
                </div>

                <div class="status-card">
                    <span>Service Status</span>
                    <strong>
                        <span class="status-badge status-<%= safeText(statusClass(serviceStatus)) %>">
                            <%= safeText(cleanLabel(serviceStatus)) %>
                        </span>
                    </strong>
                </div>
            </section>

            <section class="info-panel">
                <h2>Depreciation & Warranty Snapshot</h2>

                <div class="asset-value-grid">
                    <div class="asset-value-card">
                        <span>Purchase Cost</span>
                        <strong>Rs <%= safeText(rowValue(asset, "purchase_cost")) %></strong>
                        <small>Original capital value recorded in MySQL.</small>
                    </div>

                    <div class="asset-value-card">
                        <span>Estimated Book Value</span>
                        <strong>Rs <%= safeText(rowValue(asset, "estimated_book_value")) %></strong>
                        <small>Calculated from purchase cost, asset age, and depreciation rate.</small>
                    </div>

                    <div class="asset-value-card">
                        <span>Depreciated Amount</span>
                        <strong>Rs <%= safeText(rowValue(asset, "estimated_depreciation_amount")) %></strong>
                        <small><%= safeText(rowValue(asset, "depreciation_rate")) %>% annual rate over <%= safeText(rowValue(asset, "asset_age_months")) %> months.</small>
                    </div>

                    <div class="asset-value-card">
                        <span>Warranty Status</span>
                        <strong>
                            <span class="status-badge status-<%= safeText(statusClass(rowValue(asset, "warranty_status"))) %>">
                                <%= safeText(cleanLabel(rowValue(asset, "warranty_status"))) %>
                            </span>
                        </strong>
                        <small>Days remaining: <%= safeText(rowValue(asset, "warranty_days_remaining")) %></small>
                    </div>

                    <div class="asset-value-card">
                        <span>Asset Age</span>
                        <strong><%= safeText(rowValue(asset, "asset_age_months")) %> months</strong>
                        <small>Based on purchase date.</small>
                    </div>

                    <div class="asset-value-card">
                        <span>Current Service State</span>
                        <strong>
                            <span class="status-badge status-<%= safeText(statusClass(serviceStatus)) %>">
                                <%= safeText(cleanLabel(serviceStatus)) %>
                            </span>
                        </strong>
                        <small>Used by allocation and maintenance workflows.</small>
                    </div>
                </div>
            </section>

            <section class="view-grid">
                <div class="info-panel">
                    <h2>Asset Master Details</h2>

                    <div class="asset-photo-card">
                        <img src="<%= safeText(assetImageSrc) %>" alt="Asset Photo">
                        <div>
                            <strong><%= safeText(rowValue(asset, "asset_name")) %></strong>
                            <span>
                                Asset photo is stored as a controlled file path in MySQL.
                                Replace it from Edit Asset whenever the physical asset photo changes.
                            </span>
                        </div>
                    </div>

                    <table class="detail-table">
                        <tr><th>Asset Code</th><td><%= safeText(rowValue(asset, "asset_code")) %></td></tr>
                        <tr><th>Asset Name</th><td><%= safeText(rowValue(asset, "asset_name")) %></td></tr>
                        <tr><th>Category</th><td><%= safeText(rowValue(asset, "category_name")) %></td></tr>
                        <tr><th>Serial Number</th><td><%= safeText(rowValue(asset, "serial_number")) %></td></tr>
                        <tr><th>Model Number</th><td><%= safeText(rowValue(asset, "model_number")) %></td></tr>
                        <tr><th>Purchase Date</th><td><%= safeText(rowValue(asset, "purchase_date")) %></td></tr>
                        <tr><th>Purchase Cost</th><td>₹<%= safeText(rowValue(asset, "purchase_cost")) %></td></tr>
                        <tr><th>Depreciation Rate</th><td><%= safeText(rowValue(asset, "depreciation_rate")) %>%</td></tr>
                        <tr><th>Warranty Expiry</th><td><%= safeText(rowValue(asset, "warranty_expiry")) %></td></tr>
                        <tr><th>Last Physical Verification</th><td><%= safeText(rowValue(asset, "last_physical_verification_date")) %></td></tr>
                        <tr><th>Created</th><td><%= safeText(rowValue(asset, "created_at")) %></td></tr>
                        <tr><th>Last Updated</th><td><%= safeText(rowValue(asset, "updated_at")) %></td></tr>
                        <tr><th>Remarks</th><td><%= safeText(rowValue(asset, "remarks")) %></td></tr>
                    </table>
                </div>

                <div class="qr-panel">
                    <h2>Dynamic QR Identity</h2>

                    <div class="qr-box">
                        <% if (liveUrl.trim().isEmpty()) { %>
                            <i class="fa-solid fa-qrcode"></i>
                            <% if (token != null && !token.trim().isEmpty()) { %>
                                <strong>Public QR base URL not configured</strong>
                                <span>Set a non-localhost public QR base URL before printing this asset label.</span>
                            <% } else { %>
                                <strong>QR token not generated</strong>
                                <span>Generate a dynamic QR token before printing this asset label.</span>
                            <% } %>
                        <% } else { %>
                            <img src="<%= qrImageUrl %>" alt="Asset QR Code">
                            <span>Scan to open live asset record from database.</span>
                        <% } %>
                    </div>

                    <% if (!liveUrl.trim().isEmpty()) { %>
                        <div class="qr-url-box">
                            <strong>Live URL:</strong><br>
                            <%-- Fault: this used to print the raw liveUrl (a long,
                                 token-laden querystring) as plain text - correct,
                                 but visually noisy and not even clickable. Shows
                                 the asset code instead (same clean, bold style
                                 already used in the page header above), wrapped
                                 as a real link to the exact same liveUrl - so the
                                 UI reads cleanly while the actual destination
                                 (and the "Copy URL"/"Public View" actions right
                                 below, which already use liveUrl directly) is
                                 completely unchanged. title= keeps the full URL
                                 available on hover for anyone who wants it. --%>
                            <a href="<%= safeText(liveUrl) %>" target="_blank" class="qr-url-code" title="<%= safeText(liveUrl) %>">
                                <%= safeText(rowValue(asset, "asset_code")) %>
                                <i class="fa-solid fa-up-right-from-square"></i>
                            </a>
                        </div>
                    <% } else { %>
                        <div class="qr-url-box">
                            Dynamic QR URL will appear here after token generation and public base URL setup.
                        </div>
                    <% } %>

                    <div class="qr-action-grid">
                        <% if (canManageAssets) { %>
                            <form method="post" action="GenerateAssetQrServlet" style="margin:0;">
                                <input type="hidden" name="asset_id" value="<%= safeText(assetId) %>">
                                <button type="submit" class="action-btn primary">
                                    <i class="fa-solid fa-arrows-rotate"></i>
                                    Generate QR
                                </button>
                            </form>
                        <% } %>

                        <a href="asset_qr_card.jsp?id=<%= safeText(assetId) %>" class="action-btn">
                            <i class="fa-solid fa-id-card"></i>
                            QR Card
                        </a>

                        <a href="qr_print.jsp?id=<%= safeText(assetId) %>" class="action-btn green">
                            <i class="fa-solid fa-print"></i>
                            Print Label
                        </a>

                        <% if (!liveUrl.trim().isEmpty()) { %>
                            <button type="button" class="action-btn" onclick="navigator.clipboard.writeText('<%= safeText(liveUrl) %>'); alert('Public QR URL copied to clipboard!');">
                                <i class="fa-solid fa-copy"></i>
                                Copy URL
                            </button>

                            <a href="<%= safeText(liveUrl) %>" target="_blank" class="action-btn gold">
                                <i class="fa-solid fa-up-right-from-square"></i>
                                Public View
                            </a>
                        <% } %>
                    </div>

                    <div class="note-box" style="margin-top:14px;">
                        <strong>QR Scan Count:</strong> <%= qrScanCount %><br>
                        Printed QR stores only the live URL. If asset details change later,
                        the same printed QR will show updated details automatically.
                    </div>
                </div>
            </section>

            <section class="info-panel">
                <h2>Asset Document Vault</h2>

                <div class="document-vault-grid">
                    <% if (canManageAssets) { %>
                        <form method="post"
                              action="UploadAssetDocumentServlet"
                              enctype="multipart/form-data"
                              class="document-upload-form">
                            <input type="hidden" name="assetId" value="<%= safeText(assetId) %>">

                            <div>
                                <label for="documentType">Document Type</label>
                                <select id="documentType" name="documentType" required>
                                    <option value="INVOICE">Invoice / Purchase Bill</option>
                                    <option value="WARRANTY">Warranty Certificate</option>
                                    <option value="MANUAL">Manual / Service Guide</option>
                                    <option value="OTHER">Other Supporting Record</option>
                                </select>
                            </div>

                            <div>
                                <label for="assetDocument">Upload Document</label>
                                <input id="assetDocument"
                                       type="file"
                                       name="assetDocument"
                                       accept=".pdf,.jpg,.jpeg,.png,.webp,.doc,.docx,.xls,.xlsx,.csv"
                                       required>
                            </div>

                            <button type="submit" class="action-btn primary">
                                <i class="fa-solid fa-cloud-arrow-up"></i>
                                Upload to Vault
                            </button>

                            <div class="note-box">
                                Files are stored under controlled asset upload folders, while document metadata is saved in MySQL.
                                Allowed size: 10 MB.
                            </div>
                        </form>
                    <% } else { %>
                        <div class="empty-box">
                            <i class="fa-solid fa-lock"></i>
                            <strong>Upload restricted</strong>
                            <span>Document upload is available to asset managers and super admins.</span>
                        </div>
                    <% } %>

                    <div>
                        <% if (assetDocuments.isEmpty()) { %>
                            <div class="empty-box">
                                <i class="fa-solid fa-folder-open"></i>
                                <strong>No documents uploaded</strong>
                                <span>Invoice, warranty, manual, and supporting documents will appear here after upload.</span>
                            </div>
                        <% } else { %>
                            <div class="document-list">
                                <% for (AssetDocument document : assetDocuments) { %>
                                    <div class="document-item">
                                        <div class="document-icon">
                                            <i class="fa-solid fa-file-shield"></i>
                                        </div>

                                        <div>
                                            <strong><%= safeText(document.getOriginalFileName()) %></strong>
                                            <span>
                                                <%= safeText(cleanLabel(document.getDocumentType())) %>
                                                &middot;
                                                <%= safeText(formatFileSize(document.getFileSize())) %>
                                                &middot;
                                                Uploaded by <%= safeText(document.getUploadedByUsername()) %>
                                                on <%= safeText(document.getUploadedAt()) %>
                                            </span>
                                        </div>

                                        <a class="action-btn"
                                           href="DownloadAssetDocumentServlet?id=<%= document.getDocumentId() %>">
                                            <i class="fa-solid fa-download"></i>
                                            Download
                                        </a>
                                    </div>
                                <% } %>
                            </div>
                        <% } %>
                    </div>
                </div>
            </section>

            <section class="view-grid">
                <div class="info-panel">
                    <h2>Location & Department</h2>

                    <table class="detail-table">
                        <tr><th>Department</th><td><%= safeText(rowValue(asset, "department_name")) %></td></tr>
                        <tr><th>Division</th><td><%= safeText(rowValue(asset, "division_name")) %></td></tr>
                        <tr><th>Division HQ</th><td><%= safeText(rowValue(asset, "division_headquarters")) %></td></tr>
                        <tr><th>Location Code</th><td><%= safeText(rowValue(asset, "location_code")) %></td></tr>
                        <tr><th>Location Name</th><td><%= safeText(rowValue(asset, "location_name")) %></td></tr>
                        <tr><th>Location Type</th><td><%= safeText(rowValue(asset, "location_type")) %></td></tr>
                        <tr><th>Building / Block</th><td><%= safeText(rowValue(asset, "building_block")) %></td></tr>
                        <tr><th>Floor / Room</th><td><%= safeText(rowValue(asset, "floor_level")) %> / <%= safeText(rowValue(asset, "room_no")) %></td></tr>
                    </table>
                </div>

                <div class="info-panel">
                    <h2>Current Holder</h2>

                    <% if (activeAllocation.isEmpty()) { %>
                        <div class="empty-box">
                            <i class="fa-solid fa-user-slash"></i>
                            <strong>No active holder</strong>
                            <span>This asset is not currently allocated to any employee.</span>
                        </div>
                    <% } else { %>
                        <table class="detail-table">
                            <tr><th>Holder Code</th><td><%= safeText(rowValue(activeAllocation, "employee_code")) %></td></tr>
                            <tr><th>Holder Name</th><td><%= safeText(rowValue(activeAllocation, "full_name")) %></td></tr>
                            <tr><th>Designation</th><td><%= safeText(rowValue(activeAllocation, "designation")) %></td></tr>
                            <tr><th>Department</th><td><%= safeText(rowValue(activeAllocation, "holder_department")) %></td></tr>
                            <tr><th>Email</th><td><%= safeText(rowValue(activeAllocation, "employee_email")) %></td></tr>
                            <tr><th>Phone</th><td><%= safeText(rowValue(activeAllocation, "employee_phone")) %></td></tr>
                            <tr><th>Allocation Date</th><td><%= safeText(rowValue(activeAllocation, "allocation_date")) %></td></tr>
                            <tr><th>Expected Return</th><td><%= safeText(rowValue(activeAllocation, "expected_return_date")) %></td></tr>
                            <tr><th>Issue Condition</th><td><%= safeText(cleanLabel(rowValue(activeAllocation, "issue_condition"))) %></td></tr>
                            <tr>
                                <th>Allocation Link</th>
                                <td>
                                    <a class="action-btn" href="view_allocation.jsp?id=<%= safeText(rowValue(activeAllocation, "allocation_id")) %>">
                                        <i class="fa-solid fa-up-right-from-square"></i>
                                        Open Allocation
                                    </a>
                                </td>
                            </tr>
                        </table>
                    <% } %>
                </div>
            </section>

            <section class="view-grid">
                <div class="info-panel">
                    <h2>Supplier & Warranty</h2>

                    <table class="detail-table">
                        <tr><th>Supplier</th><td><%= safeText(rowValue(asset, "vendor_name")) %></td></tr>
                        <tr><th>Supplier Contact</th><td><%= safeText(rowValue(asset, "vendor_contact_person")) %></td></tr>
                        <tr><th>Supplier Phone</th><td><%= safeText(rowValue(asset, "vendor_phone")) %></td></tr>
                        <tr><th>Supplier Email</th><td><%= safeText(rowValue(asset, "vendor_email")) %></td></tr>
                        <tr><th>Warranty Expiry</th><td><%= safeText(rowValue(asset, "warranty_expiry")) %></td></tr>
                    </table>
                </div>

                <div class="info-panel">
                    <h2>QR Database Fields</h2>

                    <table class="detail-table">
                        <tr><th>QR Code Field</th><td><%= safeText(rowValue(asset, "qr_code")) %></td></tr>
                        <tr><th>Public Token</th><td><%= safeText(rowValue(asset, "qr_public_token")) %></td></tr>
                        <tr><th>Public URL</th><td><%= safeText(liveUrl) %></td></tr>
                        <tr><th>Total Scans</th><td><%= qrScanCount %></td></tr>
                    </table>
                </div>
            </section>

            <section class="info-panel">
                <h2>Asset Lifecycle Timeline</h2>

                <% if (lifecycleRows.isEmpty()) { %>
                    <div class="empty-box">
                        <i class="fa-solid fa-timeline"></i>
                        <strong>No lifecycle events</strong>
                        <span>No lifecycle entries could be derived for this asset.</span>
                    </div>
                <% } else { %>
                    <div class="lifecycle-timeline">
                        <% for (Map<String, String> row : lifecycleRows) { %>
                            <div class="timeline-row lifecycle-row">
                                <div class="lifecycle-icon">
                                    <i class="fa-solid <%= safeText(rowValue(row, "event_icon")) %>"></i>
                                </div>

                                <div>
                                    <strong>
                                        <%= safeText(cleanLabel(rowValue(row, "event_type"))) %>
                                        &middot;
                                        <%= safeText(rowValue(row, "event_title")) %>
                                    </strong>
                                    <span><%= safeText(rowValue(row, "event_detail")) %></span>
                                </div>

                                <div>
                                    <span class="lifecycle-status status-<%= safeText(statusClass(rowValue(row, "event_status"))) %>">
                                        <%= safeText(cleanLabel(rowValue(row, "event_status"))) %>
                                    </span>
                                    <div class="timeline-date" style="margin-top:7px;">
                                        <%= safeText(rowValue(row, "event_date")) %>
                                    </div>
                                </div>
                            </div>
                        <% } %>
                    </div>
                <% } %>
            </section>

            <section class="view-grid">
                <div class="info-panel">
                    <h2>Recent Maintenance</h2>

                    <% if (maintenanceRows.isEmpty()) { %>
                        <div class="empty-box">
                            <i class="fa-solid fa-screwdriver-wrench"></i>
                            <strong>No maintenance history</strong>
                            <span>No maintenance entry found for this asset.</span>
                        </div>
                    <% } else { %>
                        <div class="timeline-list">
                            <% for (Map<String, String> row : maintenanceRows) { %>
                                <div class="timeline-row">
                                    <div>
                                        <strong><%= safeText(cleanLabel(rowValue(row, "maintenance_type"))) %> · <%= safeText(cleanLabel(rowValue(row, "maintenance_status"))) %></strong>
                                        <span>
                                            <%= safeText(rowValue(row, "issue_reported")) %>
                                            <br>
                                            Work: <%= safeText(rowValue(row, "work_done")) %>
                                            <br>
                                            Supplier: <%= safeText(rowValue(row, "vendor_name")) %> · Cost: ₹<%= safeText(rowValue(row, "cost")) %>
                                        </span>
                                    </div>
                                    <div class="timeline-date">
                                        <%= safeText(rowValue(row, "maintenance_date")) %>
                                    </div>
                                </div>
                            <% } %>
                        </div>
                    <% } %>
                </div>

                <div class="info-panel">
                    <h2>Allocation History</h2>

                    <% if (allocationRows.isEmpty()) { %>
                        <div class="empty-box">
                            <i class="fa-solid fa-arrow-right-arrow-left"></i>
                            <strong>No allocation history</strong>
                            <span>No allocation entry found for this asset.</span>
                        </div>
                    <% } else { %>
                        <div class="timeline-list">
                            <% for (Map<String, String> row : allocationRows) { %>
                                <div class="timeline-row">
                                    <div>
                                        <strong><%= safeText(rowValue(row, "employee_code")) %> · <%= safeText(rowValue(row, "full_name")) %></strong>
                                        <span>
                                            Status: <%= safeText(cleanLabel(rowValue(row, "allocation_status"))) %>
                                            <br>
                                            Issue Condition: <%= safeText(cleanLabel(rowValue(row, "issue_condition"))) %>
                                            <br>
                                            Return Date: <%= safeText(rowValue(row, "return_date")) %>
                                        </span>
                                    </div>
                                    <div class="timeline-date">
                                        <%= safeText(rowValue(row, "allocation_date")) %>
                                    </div>
                                </div>
                            <% } %>
                        </div>
                    <% } %>
                </div>
            </section>

            <section class="info-panel">
                <h2>Recent Physical Verification</h2>

                <% if (verificationRows.isEmpty()) { %>
                    <div class="empty-box">
                        <i class="fa-solid fa-shield-halved"></i>
                        <strong>No verification history</strong>
                        <span>No physical verification entry found for this asset.</span>
                    </div>
                <% } else { %>
                    <div class="timeline-list">
                        <% for (Map<String, String> row : verificationRows) { %>
                            <div class="timeline-row">
                                <div>
                                    <strong>
                                        <%= safeText(cleanLabel(rowValue(row, "verification_status"))) %>
                                        · Found: <%= safeText(cleanLabel(rowValue(row, "asset_found"))) %>
                                    </strong>
                                    <span>
                                        Physical Condition: <%= safeText(cleanLabel(rowValue(row, "physical_condition"))) %>
                                        <br>
                                        Remarks: <%= safeText(rowValue(row, "remarks")) %>
                                    </span>
                                </div>
                                <div class="timeline-date">
                                    <%= safeText(rowValue(row, "verification_date")) %>
                                </div>
                            </div>
                        <% } %>
                    </div>
                <% } %>
            </section>

        </div>
    </main>
</div>

<script src="js/topbar-search.js?v=asset-allocation-inner-1"></script>
<script src="js/user-dropdown.js?v=asset-allocation-inner-1"></script>
<script src="js/sidebar-role.js?v=asset-allocation-inner-1"></script>
<script src="js/ir-body-watermark.js?v=asset-allocation-inner-1"></script>
<script src="js/dashboard-actions.js?v=asset-allocation-inner-1"></script>

</body>
</html>
