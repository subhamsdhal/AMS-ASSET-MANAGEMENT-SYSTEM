﻿<%@page contentType="text/html" pageEncoding="UTF-8"%>
<%@page import="com.mycompany.asset_management_system_ams.DBConnection"%>
<%@page import="java.sql.*"%>
<%@page import="java.util.*"%>
<%@page import="java.text.NumberFormat"%>

<%!
    private String safeText(String value) {
        if (value == null || value.trim().isEmpty()) return "N/A";
        return value.trim()
                .replace("&", "&amp;")
                .replace("<", "&lt;")
                .replace(">", "&gt;")
                .replace("\"", "&quot;")
                .replace("'", "&#39;");
    }

    private String cleanLabel(String value) {
        if (value == null || value.trim().isEmpty()) return "N/A";
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
        if (value == null || value.trim().isEmpty()) return "N/A";
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
            if (value == null || value.trim().isEmpty()) return "0.00";
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
        Map<String, String> row = new HashMap<>();

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
        List<Map<String, String>> rows = new ArrayList<>();

        try (Connection con = DBConnection.getConnection();
             PreparedStatement ps = con.prepareStatement(sql)) {

            ps.setString(1, id);

            try (ResultSet rs = ps.executeQuery()) {
                ResultSetMetaData meta = rs.getMetaData();
                int columnCount = meta.getColumnCount();

                while (rs.next()) {
                    Map<String, String> row = new HashMap<>();

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
                if (rs.next()) value = rs.getInt(1);
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
                if (rs.next()) value = rs.getString(1);
            }

        } catch (Exception e) {
            e.printStackTrace();
        }

        return value == null ? "0" : value;
    }

    private String rowValue(Map<String, String> row, String key) {
        if (row == null) return "";
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

    String categoryId = request.getParameter("id");
    if (categoryId == null || categoryId.trim().isEmpty()) {
        categoryId = request.getParameter("category_id");
    }

    if (categoryId == null || categoryId.trim().isEmpty()) {
        response.sendRedirect("categories.jsp?error=invalid");
        return;
    }

    categoryId = categoryId.trim();

    boolean canManageCategory = ("SUPER_ADMIN".equals(role) || "ADMIN".equals(role)) || "ASSET_MANAGER".equals(role);
    String userInitial = username.substring(0, Math.min(2, username.length())).toUpperCase(Locale.ENGLISH);

    Map<String, String> category = singleRow(
            "SELECT "
            + "category_id, category_name, description, useful_life_years, default_depreciation_rate, status, "
            + "DATE_FORMAT(created_at, '%d %b %Y, %h:%i %p') AS created_at, "
            + "DATE_FORMAT(updated_at, '%d %b %Y, %h:%i %p') AS updated_at "
            + "FROM asset_categories WHERE category_id = ? LIMIT 1",
            categoryId
    );

    if (category.isEmpty()) {
        response.sendRedirect("categories.jsp?error=notfound");
        return;
    }

    int totalAssets = singleInt("SELECT COUNT(*) FROM assets WHERE category_id = ?", categoryId);
    int serviceableAssets = singleInt("SELECT COUNT(*) FROM assets WHERE category_id = ? AND service_status = 'SERVICEABLE'", categoryId);
    int maintenanceAssets = singleInt("SELECT COUNT(*) FROM assets WHERE category_id = ? AND asset_status = 'UNDER_MAINTENANCE'", categoryId);
    int requestCount = singleInt("SELECT COUNT(*) FROM asset_requests WHERE category_id = ?", categoryId);
    int pendingRequests = singleInt("SELECT COUNT(*) FROM asset_requests WHERE category_id = ? AND request_status = 'PENDING'", categoryId);
    String totalAssetValue = singleText("SELECT COALESCE(SUM(purchase_cost), 0) FROM assets WHERE category_id = ?", categoryId);

    List<Map<String, String>> assetRows = listRows(
            "SELECT "
            + "a.asset_id, a.asset_code, a.asset_name, a.asset_status, a.service_status, "
            + "a.serial_number, a.model_number, DATE_FORMAT(a.warranty_expiry, '%d %b %Y') AS warranty_expiry, "
            + "COALESCE(v.vendor_name, 'No Supplier') AS vendor_name, "
            + "COALESCE(d.department_name, 'Unassigned') AS department_name, "
            + "COALESCE(rl.location_name, a.location, '') AS location_name "
            + "FROM assets a "
            + "LEFT JOIN vendors v ON a.vendor_id = v.vendor_id "
            + "LEFT JOIN departments d ON a.department_id = d.department_id "
            + "LEFT JOIN railway_locations rl ON a.location_id = rl.location_id "
            + "WHERE a.category_id = ? "
            + "ORDER BY a.asset_id DESC LIMIT 12",
            categoryId
    );

    List<Map<String, String>> requestRows = listRows(
            "SELECT "
            + "ar.request_id, ar.request_type, ar.request_status, ar.priority, "
            + "DATE_FORMAT(ar.request_date, '%d %b %Y') AS request_date, "
            + "DATE_FORMAT(ar.required_by_date, '%d %b %Y') AS required_by_date, "
            + "COALESCE(e.employee_name, 'Employee') AS employee_name, "
            + "COALESCE(d.department_name, 'No Department') AS department_name, "
            + "COALESCE(ar.request_reason, '') AS request_reason "
            + "FROM asset_requests ar "
            + "LEFT JOIN employees e ON ar.employee_id = e.employee_id "
            + "LEFT JOIN departments d ON ar.department_id = d.department_id "
            + "WHERE ar.category_id = ? "
            + "ORDER BY ar.request_id DESC LIMIT 12",
            categoryId
    );

    String categoryStatus = rowValue(category, "status");
    String statusClass = "";

    if ("INACTIVE".equalsIgnoreCase(categoryStatus)) {
        statusClass = "danger";
    }
%>

<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>Category Details - IR-AMS</title>

    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.0/css/all.min.css">

    <link rel="stylesheet" href="css/ir-glass.css?v=inner-category-supplier-1">
    <link rel="stylesheet" href="css/ams-pro.css?v=inner-category-supplier-1">
    <link rel="stylesheet" href="css/ir-ams-railway-ui.css?v=inner-category-supplier-1">
<link rel="stylesheet" href="css/view_category.css?v=topbarfix1">
</head>

<body class="railway-ui">
<div class="app ams-shell">

    <jsp:include page="sidebar.jsp" />

    <main class="main railway-main">
        <jsp:include page="topbar.jsp" />

        <div class="main-scroll-content detail-board">

            <section class="detail-hero">
                <div>
                    <h1><%= safeText(rowValue(category, "category_name")) %></h1>
                    <p>
                        Useful Life: <strong><%= safeText(rowValue(category, "useful_life_years")) %> years</strong>
                        · Default Depreciation: <%= safeText(rowValue(category, "default_depreciation_rate")) %>%
                    </p>
                </div>

                <div class="hero-actions">
                    <span class="status-pill <%= statusClass %>">
                        <i class="fa-solid fa-circle-check"></i>
                        <%= safeText(cleanLabel(categoryStatus)) %>
                    </span>

                    <% if (canManageCategory) { %>
                        <a href="edit_category.jsp?id=<%= safeText(categoryId) %>" class="btn btn-primary">
                            <i class="fa-solid fa-pen"></i>
                            Edit
                        </a>
                    <% } %>

                    <a href="categories.jsp" class="btn btn-secondary">
                        <i class="fa-solid fa-arrow-left"></i>
                        Back
                    </a>
                </div>
            </section>

            <section class="summary-grid">
                <div class="summary-card"><span>Total Assets</span><strong><%= indianNumber(totalAssets) %></strong></div>
                <div class="summary-card"><span>Serviceable</span><strong><%= indianNumber(serviceableAssets) %></strong></div>
                <div class="summary-card"><span>Under Maintenance</span><strong><%= indianNumber(maintenanceAssets) %></strong></div>
                <div class="summary-card"><span>Total Requests</span><strong><%= indianNumber(requestCount) %></strong></div>
                <div class="summary-card"><span>Pending Requests</span><strong><%= indianNumber(pendingRequests) %></strong></div>
                <div class="summary-card"><span>Asset Value</span><strong>₹ <%= moneyText(totalAssetValue) %></strong></div>
            </section>

            <section class="detail-grid">
                <div class="detail-panel">
                    <div class="panel-title-row">
                        <h2 class="panel-title">Category Profile</h2>
                    </div>

                    <table class="detail-table">
                        <tr><th>Category Name</th><td><%= safeText(rowValue(category, "category_name")) %></td></tr>
                        <tr><th>Description</th><td><%= safeText(rowValue(category, "description")) %></td></tr>
                        <tr><th>Useful Life</th><td><%= safeText(rowValue(category, "useful_life_years")) %> years</td></tr>
                        <tr><th>Depreciation Rate</th><td><%= safeText(rowValue(category, "default_depreciation_rate")) %>%</td></tr>
                        <tr><th>Status</th><td><%= safeText(cleanLabel(categoryStatus)) %></td></tr>
                        <tr><th>Created On</th><td><%= safeText(rowValue(category, "created_at")) %></td></tr>
                        <tr><th>Updated On</th><td><%= safeText(rowValue(category, "updated_at")) %></td></tr>
                    </table>
                </div>

                <div class="detail-panel">
                    <div class="panel-title-row">
                        <h2 class="panel-title">Assets in this Category</h2>
                    </div>

                    <div class="timeline-list">
                        <% if (assetRows.isEmpty()) { %>
                            <div class="empty-box">
                                <i class="fa-solid fa-cubes"></i>
                                <strong>No asset found</strong>
                                <span>Assets of this category will appear here.</span>
                            </div>
                        <% } else {
                            for (Map<String, String> row : assetRows) {
                        %>
                            <a class="timeline-row" href="view_asset.jsp?id=<%= safeText(rowValue(row, "asset_id")) %>">
                                <div class="timeline-icon"><i class="fa-solid fa-cube"></i></div>
                                <div class="timeline-text">
                                    <strong><%= safeText(rowValue(row, "asset_code")) %> · <%= safeText(rowValue(row, "asset_name")) %></strong>
                                    <span><%= safeText(cleanLabel(rowValue(row, "asset_status"))) %> · <%= safeText(cleanLabel(rowValue(row, "service_status"))) %> · <%= safeText(rowValue(row, "vendor_name")) %> · <%= safeText(rowValue(row, "location_name")) %></span>
                                </div>
                                <div class="timeline-date"><%= safeText(rowValue(row, "warranty_expiry")) %></div>
                            </a>
                        <%  }
                        } %>
                    </div>
                </div>
            </section>

            
            <section class="add-asset-hero-new" style="margin-bottom: 20px; background: url('<%= request.getContextPath() %>/images/categories-hero-bg.png') center center / cover no-repeat, linear-gradient(135deg, rgba(255,255,255,0.95), rgba(232,245,255,0.92)) !important;">
                <h1 style="margin: 0; color: #08348f; font-size: 28px; line-height: 1.1; font-weight: 950; text-transform: uppercase; position: relative; z-index: 2;">VIEW CATEGORY</h1>
                <p style="margin: 8px 0 0 0; color: #18366f; font-size: 13px; font-weight: 800; position: relative; z-index: 2;">Manage your module settings seamlessly</p>
            </section>
            <section class="detail-panel">
                <div class="panel-title-row">
                    <h2 class="panel-title">Requests for this Category</h2>
                </div>

                <div class="timeline-list">
                    <% if (requestRows.isEmpty()) { %>
                        <div class="empty-box">
                            <i class="fa-regular fa-square-plus"></i>
                            <strong>No request found</strong>
                            <span>Planning and demand records for this category will appear here.</span>
                        </div>
                    <% } else {
                        for (Map<String, String> row : requestRows) {
                    %>
                        <a class="timeline-row" href="view_request.jsp?id=<%= safeText(rowValue(row, "request_id")) %>">
                            <div class="timeline-icon"><i class="fa-regular fa-square-plus"></i></div>
                            <div class="timeline-text">
                                <strong>Request #<%= safeText(rowValue(row, "request_id")) %> · <%= safeText(cleanLabel(rowValue(row, "request_status"))) %></strong>
                                <span><%= safeText(rowValue(row, "employee_name")) %> · <%= safeText(cleanLabel(rowValue(row, "request_type"))) %> · <%= safeText(cleanLabel(rowValue(row, "priority"))) %> · <%= safeText(shortText(rowValue(row, "request_reason"), 80)) %></span>
                            </div>
                            <div class="timeline-date"><%= safeText(rowValue(row, "request_date")) %></div>
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
