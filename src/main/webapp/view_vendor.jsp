﻿<%@page contentType="text/html" pageEncoding="UTF-8"%>
<%@page import="com.mycompany.asset_management_system_ams.DBConnection"%>
<%@page import="com.mycompany.asset_management_system_ams.HtmlEscapeUtil"%>
<%@page import="com.mycompany.asset_management_system_ams.VendorDocument"%>
<%@page import="com.mycompany.asset_management_system_ams.VendorDocumentDAO"%>
<%@page import="java.sql.*"%>
<%@page import="java.util.*"%>
<%@page import="java.text.NumberFormat"%>

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

    private String shortText(String value, int max) {
        if (value == null || value.trim().isEmpty()) {
            return "N/A";
        }

        String text = value.trim();
        return text.length() <= max ? text : text.substring(0, max) + "...";
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

    private String moneyText(String value) {
        try {
            if (value == null || value.trim().isEmpty()) {
                return "0.00";
            }

            double amount = Double.parseDouble(value);
            NumberFormat nf = NumberFormat.getNumberInstance(new Locale("en", "IN"));
            nf.setMaximumFractionDigits(2);
            nf.setMinimumFractionDigits(2);

            return nf.format(amount);
        } catch (Exception e) {
            return "0.00";
        }
    }

    private Map<String, String> singleRow(String sql, String id) {
        Map<String, String> row = new HashMap<String, String>();

        try (Connection con = DBConnection.getConnection();
             PreparedStatement ps = con.prepareStatement(sql)) {

            ps.setString(1, id);

            try (ResultSet rs = ps.executeQuery()) {
                ResultSetMetaData meta = rs.getMetaData();
                int columnCount = meta.getColumnCount();

                if (rs.next()) {
                    for (int i = 1; i <= columnCount; i++) {
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
        List<Map<String, String>> rows = new ArrayList<Map<String, String>>();

        try (Connection con = DBConnection.getConnection();
             PreparedStatement ps = con.prepareStatement(sql)) {

            ps.setString(1, id);

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
        int value = 0;

        try (Connection con = DBConnection.getConnection();
             PreparedStatement ps = con.prepareStatement(sql)) {

            ps.setString(1, id);

            try (ResultSet rs = ps.executeQuery()) {
                if (rs.next()) {
                    value = rs.getInt(1);
                }
            }

        } catch (Exception e) {
            e.printStackTrace();
        }

        return value;
    }

    private String singleText(String sql, String id) {
        String value = "0";

        try (Connection con = DBConnection.getConnection();
             PreparedStatement ps = con.prepareStatement(sql)) {

            ps.setString(1, id);

            try (ResultSet rs = ps.executeQuery()) {
                if (rs.next()) {
                    value = rs.getString(1);
                }
            }

        } catch (Exception e) {
            e.printStackTrace();
        }

        return value == null ? "0" : value;
    }

    private String rowValue(Map<String, String> row, String key) {
        if (row == null) {
            return "";
        }

        String value = row.get(key);
        return value == null ? "" : value;
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

    String vendorId = request.getParameter("id");

    if (vendorId == null || vendorId.trim().isEmpty()) {
        vendorId = request.getParameter("vendor_id");
    }

    if (vendorId == null || vendorId.trim().isEmpty()) {
        response.sendRedirect("vendors.jsp?error=invalid");
        return;
    }

    vendorId = vendorId.trim();

    boolean canManageSuppliers = ("SUPER_ADMIN".equals(role) || "ADMIN".equals(role)) || "ASSET_MANAGER".equals(role);
    String userInitial = username.substring(0, Math.min(2, username.length())).toUpperCase(Locale.ENGLISH);

    Map<String, String> vendor = singleRow(
            "SELECT "
            + "vendor_id, vendor_name, contact_person, email, phone, address, gst_number, vendor_status, "
            + "DATE_FORMAT(created_at, '%d %b %Y, %h:%i %p') AS created_at, "
            + "DATE_FORMAT(updated_at, '%d %b %Y, %h:%i %p') AS updated_at "
            + "FROM vendors WHERE vendor_id = ? LIMIT 1",
            vendorId
    );

    if (vendor.isEmpty()) {
        response.sendRedirect("vendors.jsp?error=notfound");
        return;
    }

    int totalAssets = singleInt("SELECT COUNT(*) FROM assets WHERE vendor_id = ?", vendorId);
    int activeAssets = singleInt("SELECT COUNT(*) FROM assets WHERE vendor_id = ? AND asset_status <> 'DISPOSED'", vendorId);
    int warrantyExpiring = singleInt("SELECT COUNT(*) FROM assets WHERE vendor_id = ? AND warranty_expiry BETWEEN CURDATE() AND DATE_ADD(CURDATE(), INTERVAL 30 DAY)", vendorId);
    int maintenanceCount = singleInt("SELECT COUNT(*) FROM maintenance_logs WHERE vendor_id = ?", vendorId);
    String totalPurchaseValue = singleText("SELECT COALESCE(SUM(purchase_cost), 0) FROM assets WHERE vendor_id = ?", vendorId);

    List<Map<String, String>> assetRows = listRows(
            "SELECT "
            + "a.asset_id, a.asset_code, a.asset_name, a.asset_status, a.service_status, "
            + "a.serial_number, a.model_number, DATE_FORMAT(a.purchase_date, '%d %b %Y') AS purchase_date, "
            + "DATE_FORMAT(a.warranty_expiry, '%d %b %Y') AS warranty_expiry, "
            + "COALESCE(ac.category_name, 'Uncategorized') AS category_name, "
            + "COALESCE(d.department_name, 'Unassigned') AS department_name, "
            + "COALESCE(rl.location_name, a.location, '') AS location_name "
            + "FROM assets a "
            + "LEFT JOIN asset_categories ac ON a.category_id = ac.category_id "
            + "LEFT JOIN departments d ON a.department_id = d.department_id "
            + "LEFT JOIN railway_locations rl ON a.location_id = rl.location_id "
            + "WHERE a.vendor_id = ? "
            + "ORDER BY a.asset_id DESC LIMIT 12",
            vendorId
    );

    List<Map<String, String>> maintenanceRows = listRows(
            "SELECT "
            + "ml.maintenance_id, ml.asset_id, ml.maintenance_type, ml.maintenance_status, "
            + "DATE_FORMAT(ml.maintenance_date, '%d %b %Y') AS maintenance_date, "
            + "DATE_FORMAT(ml.next_due_date, '%d %b %Y') AS next_due_date, "
            + "ml.issue_reported, ml.work_done, ml.cost, "
            + "a.asset_code, a.asset_name, "
            + "COALESCE(e.employee_name, 'Not Assigned') AS performed_by "
            + "FROM maintenance_logs ml "
            + "LEFT JOIN assets a ON ml.asset_id = a.asset_id "
            + "LEFT JOIN employees e ON ml.performed_by_employee_id = e.employee_id "
            + "WHERE ml.vendor_id = ? "
            + "ORDER BY ml.maintenance_id DESC LIMIT 12",
            vendorId
    );

    String vendorStatus = rowValue(vendor, "vendor_status");
    String statusClass = "";

    if ("INACTIVE".equalsIgnoreCase(vendorStatus)) {
        statusClass = "danger";
    }

    int vendorIdInt = 0;
    try {
        vendorIdInt = Integer.parseInt(vendorId);
    } catch (Exception e) {
        vendorIdInt = 0;
    }

    List<VendorDocument> vendorDocuments = new VendorDocumentDAO().getDocumentsByVendorId(vendorIdInt);

    String vendorMsg = request.getParameter("msg");
    String vendorError = request.getParameter("error");
    String vendorBannerText = "";
    String vendorBannerClass = "";

    if ("document_added".equals(vendorMsg)) {
        vendorBannerText = "Compliance document uploaded successfully.";
        vendorBannerClass = "page-success";
    } else if ("document_denied".equals(vendorError)) {
        vendorBannerText = "You do not have permission to upload documents for this supplier.";
        vendorBannerClass = "page-error";
    } else if ("document_upload".equals(vendorError)) {
        vendorBannerText = "Document upload failed. Check file type (PDF, JPG, JPEG, PNG, WEBP, DOC, DOCX) and size (max 10 MB).";
        vendorBannerClass = "page-error";
    } else if ("document_missing".equals(vendorError)) {
        vendorBannerText = "The requested document could not be found.";
        vendorBannerClass = "page-error";
    }
%>

<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>Supplier Profile - IR-AMS</title>

    <link rel="stylesheet"
          href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.0/css/all.min.css">

    <link rel="stylesheet" href="css/ir-glass.css?v=inner-category-supplier-1">
    <link rel="stylesheet" href="css/ams-pro.css?v=inner-category-supplier-1">
    <link rel="stylesheet" href="css/ir-ams-railway-ui.css?v=inner-category-supplier-1">
<link rel="stylesheet" href="css/view_vendor.css?v=topbarfix1">
</head>

<body class="railway-ui">
<div class="app ams-shell">

    <jsp:include page="sidebar.jsp" />

    <main class="main railway-main">
        <jsp:include page="topbar.jsp" />

        <div class="main-scroll-content detail-board">

            <section class="detail-hero">
                <div>
                    <h1><%= safeText(rowValue(vendor, "vendor_name")) %></h1>

                    <p>
                        <strong><%= safeText(rowValue(vendor, "contact_person")) %></strong>
                        · <%= safeText(rowValue(vendor, "phone")) %>
                        · <%= safeText(rowValue(vendor, "email")) %>
                    </p>
                </div>

                <div class="hero-actions">
                    <span class="status-pill <%= statusClass %>">
                        <i class="fa-solid fa-circle-check"></i>
                        <%= safeText(cleanLabel(vendorStatus)) %>
                    </span>

                    <% if (canManageSuppliers) { %>
                        <a href="edit_vendor.jsp?id=<%= safeText(vendorId) %>" class="profile-action-btn primary">
                            <i class="fa-solid fa-pen"></i>
                            Edit Supplier
                        </a>
                    <% } %>

                    <a href="vendors.jsp" class="profile-action-btn">
                        <i class="fa-solid fa-arrow-left"></i>
                        Back to Suppliers
                    </a>
                </div>
            </section>

            <% if (!vendorBannerText.isEmpty()) { %>
                <div class="<%= vendorBannerClass %>">
                    <i class="fa-solid <%= "page-success".equals(vendorBannerClass) ? "fa-circle-check" : "fa-triangle-exclamation" %>"></i>
                    <%= HtmlEscapeUtil.escape(vendorBannerText) %>
                </div>
            <% } %>

            <section class="summary-grid">
                <div class="summary-card">
                    <span>Total Assets Supplied</span>
                    <strong><%= indianNumber(totalAssets) %></strong>
                </div>

                <div class="summary-card">
                    <span>Active Assets</span>
                    <strong><%= indianNumber(activeAssets) %></strong>
                </div>

                <div class="summary-card">
                    <span>Warranty Expiring</span>
                    <strong><%= indianNumber(warrantyExpiring) %></strong>
                </div>

                <div class="summary-card">
                    <span>Maintenance Jobs</span>
                    <strong><%= indianNumber(maintenanceCount) %></strong>
                </div>

                <div class="summary-card">
                    <span>Total Purchase Value</span>
                    <strong>₹ <%= moneyText(totalPurchaseValue) %></strong>
                </div>
            </section>

            <section class="detail-grid">
                <div class="detail-panel">
                    <div class="panel-title-row">
                        <h2 class="panel-title">Supplier Profile</h2>
                    </div>

                    <table class="detail-table">
                        <tr><th>Supplier Name</th><td><%= safeText(rowValue(vendor, "vendor_name")) %></td></tr>
                        <tr><th>Contact Person</th><td><%= safeText(rowValue(vendor, "contact_person")) %></td></tr>
                        <tr><th>Email</th><td><%= safeText(rowValue(vendor, "email")) %></td></tr>
                        <tr><th>Phone</th><td><%= safeText(rowValue(vendor, "phone")) %></td></tr>
                        <tr><th>GST Number</th><td><%= safeText(rowValue(vendor, "gst_number")) %></td></tr>
                        <tr><th>Status</th><td><%= safeText(cleanLabel(vendorStatus)) %></td></tr>
                        <tr><th>Address</th><td><%= safeText(rowValue(vendor, "address")) %></td></tr>
                        <tr><th>Created On</th><td><%= safeText(rowValue(vendor, "created_at")) %></td></tr>
                        <tr><th>Updated On</th><td><%= safeText(rowValue(vendor, "updated_at")) %></td></tr>
                    </table>
                </div>

                <div class="detail-panel">
                    <div class="panel-title-row">
                        <h2 class="panel-title">Assets Supplied</h2>
                    </div>

                    <div class="timeline-list">
                        <% if (assetRows.isEmpty()) { %>
                            <div class="empty-box">
                                <i class="fa-solid fa-cubes"></i>
                                <strong>No assets linked</strong>
                                <span>Assets supplied by this supplier will appear here.</span>
                            </div>
                        <% } else {
                            for (Map<String, String> row : assetRows) {
                        %>
                            <a class="timeline-row" href="view_asset.jsp?id=<%= safeText(rowValue(row, "asset_id")) %>">
                                <div class="timeline-icon">
                                    <i class="fa-solid fa-cube"></i>
                                </div>

                                <div class="timeline-text">
                                    <strong>
                                        <%= safeText(rowValue(row, "asset_code")) %> · <%= safeText(rowValue(row, "asset_name")) %>
                                    </strong>

                                    <span>
                                        <%= safeText(rowValue(row, "category_name")) %>
                                        · <%= safeText(cleanLabel(rowValue(row, "asset_status"))) %>
                                        · <%= safeText(rowValue(row, "location_name")) %>
                                    </span>
                                </div>

                                <div class="timeline-date">
                                    <%= safeText(rowValue(row, "warranty_expiry")) %>
                                </div>
                            </a>
                        <%  }
                        } %>
                    </div>
                </div>
            </section>

            
            <section class="add-asset-hero-new" style="margin-bottom: 20px; background: url('<%= request.getContextPath() %>/images/vendors-hero-bg.png') center center / cover no-repeat, linear-gradient(135deg, rgba(255,255,255,0.95), rgba(232,245,255,0.92)) !important;">
                <h1 style="margin: 0; color: #08348f; font-size: 28px; line-height: 1.1; font-weight: 950; text-transform: uppercase; position: relative; z-index: 2;">VIEW VENDOR</h1>
                <p style="margin: 8px 0 0 0; color: #18366f; font-size: 13px; font-weight: 800; position: relative; z-index: 2;">Manage your module settings seamlessly</p>
            </section>

            <section class="detail-panel">
                <div class="panel-title-row">
                    <h2 class="panel-title">Compliance Documents</h2>
                </div>

                <% if (canManageSuppliers) { %>
                <form action="UploadVendorDocumentServlet" method="post" enctype="multipart/form-data"
                      style="display:flex;gap:12px;flex-wrap:wrap;align-items:flex-end;margin-bottom:18px;padding-bottom:18px;border-bottom:1px solid #e2e8f0;">
                    <input type="hidden" name="vendorId" value="<%= safeText(vendorId) %>">
                    <div>
                        <label style="display:block;font-size:12px;font-weight:700;color:#64748b;margin-bottom:5px;text-transform:uppercase;">Document Type</label>
                        <select name="documentType" required style="padding:9px 10px;border-radius:8px;border:1px solid #cbd5e1;">
                            <option value="TRADE_LICENSE">Trade License</option>
                            <option value="GST_CERTIFICATE">GST Certificate</option>
                            <option value="PAN_CARD">PAN Card</option>
                            <option value="COMPLIANCE_CERTIFICATE">Compliance Certificate</option>
                            <option value="OTHER">Other</option>
                        </select>
                    </div>
                    <div>
                        <label style="display:block;font-size:12px;font-weight:700;color:#64748b;margin-bottom:5px;text-transform:uppercase;">Upload File (PDF, JPG, PNG, DOC - Max 10MB)</label>
                        <input type="file" name="vendorDocument" required accept=".pdf,.jpg,.jpeg,.png,.webp,.doc,.docx" style="padding:6px 0;">
                    </div>
                    <button type="submit" class="profile-action-btn primary">
                        <i class="fa-solid fa-upload"></i>
                        Upload
                    </button>
                </form>
                <% } %>

                <div class="timeline-list">
                    <% if (vendorDocuments.isEmpty()) { %>
                        <div class="empty-box">
                            <i class="fa-solid fa-file-shield"></i>
                            <strong>No compliance documents uploaded</strong>
                            <span>Trade license, GST certificate, PAN, and other compliance proof will appear here once uploaded.</span>
                        </div>
                    <% } else {
                        for (VendorDocument doc : vendorDocuments) {
                    %>
                        <a class="timeline-row" href="DownloadVendorDocumentServlet?id=<%= doc.getDocumentId() %>">
                            <div class="timeline-icon">
                                <i class="fa-solid fa-file-shield"></i>
                            </div>

                            <div class="timeline-text">
                                <strong><%= safeText(doc.getOriginalFileName()) %></strong>
                                <span>
                                    <%= safeText(cleanLabel(doc.getDocumentType())) %>
                                    · Uploaded by <%= safeText(doc.getUploadedByUsername()) %>
                                </span>
                            </div>

                            <div class="timeline-date">
                                <%= safeText(doc.getUploadedAt()) %>
                            </div>
                        </a>
                    <%  }
                    } %>
                </div>
            </section>

            <section class="detail-panel">
                <div class="panel-title-row">
                    <h2 class="panel-title">Supplier Maintenance Work</h2>
                </div>

                <div class="timeline-list">
                    <% if (maintenanceRows.isEmpty()) { %>
                        <div class="empty-box">
                            <i class="fa-solid fa-screwdriver-wrench"></i>
                            <strong>No maintenance work linked</strong>
                            <span>Maintenance handled by this supplier will appear here.</span>
                        </div>
                    <% } else {
                        for (Map<String, String> row : maintenanceRows) {
                    %>
                        <a class="timeline-row" href="view_maintenance.jsp?id=<%= safeText(rowValue(row, "maintenance_id")) %>">
                            <div class="timeline-icon">
                                <i class="fa-solid fa-screwdriver-wrench"></i>
                            </div>

                            <div class="timeline-text">
                                <strong>
                                    <%= safeText(rowValue(row, "asset_code")) %> · <%= safeText(rowValue(row, "asset_name")) %>
                                </strong>

                                <span>
                                    <%= safeText(cleanLabel(rowValue(row, "maintenance_type"))) %>
                                    · <%= safeText(cleanLabel(rowValue(row, "maintenance_status"))) %>
                                    · ₹ <%= moneyText(rowValue(row, "cost")) %>
                                    · <%= safeText(shortText(rowValue(row, "issue_reported"), 80)) %>
                                </span>
                            </div>

                            <div class="timeline-date">
                                <%= safeText(rowValue(row, "maintenance_date")) %>
                            </div>
                        </a>
                    <%  }
                    } %>
                </div>
            </section>

        </div>
    </main>
</div>

<script src="js/topbar-search.js?v=inner-category-supplier-1"></script>
<script src="js/user-dropdown.js?v=inner-category-supplier-1"></script>
<script src="js/sidebar-role.js?v=inner-category-supplier-1"></script>
<script src="js/ir-body-watermark.js?v=inner-category-supplier-1"></script>
<script src="js/dashboard-actions.js?v=inner-category-supplier-1"></script>

</body>
</html>
