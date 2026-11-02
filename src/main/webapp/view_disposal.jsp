﻿<%@page contentType="text/html" pageEncoding="UTF-8"%>
<%@page import="com.mycompany.asset_management_system_ams.DBConnection"%>
<%@page import="java.sql.*"%>
<%@page import="java.util.*"%>
<%@page import="java.text.NumberFormat"%>

<%!
    private String safeText(String value) {
        if (value == null || value.trim().isEmpty()) return "N/A";
        return value.trim().replace("&","&amp;").replace("<","&lt;").replace(">","&gt;").replace("\"","&quot;").replace("'","&#39;");
    }

    private String cleanLabel(String value) {
        if (value == null || value.trim().isEmpty()) return "N/A";
        String text = value.trim().replace("_", " ").toLowerCase(Locale.ENGLISH);
        String[] parts = text.split("\\s+");
        StringBuilder out = new StringBuilder();
        for (String part : parts) {
            if (part.length() > 0) out.append(Character.toUpperCase(part.charAt(0))).append(part.substring(1)).append(" ");
        }
        return out.toString().trim();
    }

    private String moneyText(String value) {
        try {
            if (value == null || value.trim().isEmpty()) return "0.00";
            double amount = Double.parseDouble(value);
            NumberFormat nf = NumberFormat.getNumberInstance(new Locale("en", "IN"));
            nf.setMinimumFractionDigits(2);
            nf.setMaximumFractionDigits(2);
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
                int count = meta.getColumnCount();
                if (rs.next()) {
                    for (int i = 1; i <= count; i++) row.put(meta.getColumnLabel(i), rs.getString(i));
                }
            }
        } catch (Exception e) {
            e.printStackTrace();
        }
        return row;
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

    boolean allowed = ("SUPER_ADMIN".equals(role) || "ADMIN".equals(role)) || "ASSET_MANAGER".equals(role) || "AUDITOR".equals(role);
    if (!allowed) {
        response.sendRedirect("dashboard.jsp?access=denied");
        return;
    }

    String disposalId = request.getParameter("id");
    if (disposalId == null || disposalId.trim().isEmpty()) disposalId = request.getParameter("disposal_id");

    if (disposalId == null || disposalId.trim().isEmpty()) {
        response.sendRedirect("assets.jsp?error=invalid_disposal");
        return;
    }

    disposalId = disposalId.trim();

    String userInitial = username.substring(0, Math.min(2, username.length())).toUpperCase(Locale.ENGLISH);

    Map<String, String> disposal = singleRow(
            "SELECT "
            + "ad.disposal_id, ad.asset_id, ad.disposal_reason, ad.disposal_value, ad.calculated_book_value, ad.disposal_status, ad.remarks, "
            + "DATE_FORMAT(ad.disposal_date, '%d %b %Y') AS disposal_date, "
            + "DATE_FORMAT(ad.approved_date, '%d %b %Y') AS approved_date, "
            + "DATE_FORMAT(ad.requested_date, '%d %b %Y') AS requested_date, "
            + "DATE_FORMAT(ad.created_at, '%d %b %Y, %h:%i %p') AS created_at, "
            + "DATE_FORMAT(ad.updated_at, '%d %b %Y, %h:%i %p') AS updated_at, "
            + "a.asset_code, a.asset_name, a.serial_number, a.model_number, a.purchase_cost, a.asset_status, a.service_status, "
            + "COALESCE(ac.category_name, 'Uncategorized') AS category_name, "
            + "COALESCE(v.vendor_name, 'No Vendor') AS vendor_name, "
            + "COALESCE(d.department_name, 'Unassigned') AS department_name, "
            + "COALESCE(rl.location_name, a.location, '') AS location_name, "
            + "COALESCE(u.username, 'System') AS approved_by_name, "
            + "COALESCE(ru.username, 'System') AS requested_by_name "
            + "FROM asset_disposal ad "
            + "LEFT JOIN assets a ON ad.asset_id = a.asset_id "
            + "LEFT JOIN asset_categories ac ON a.category_id = ac.category_id "
            + "LEFT JOIN vendors v ON a.vendor_id = v.vendor_id "
            + "LEFT JOIN departments d ON a.department_id = d.department_id "
            + "LEFT JOIN railway_locations rl ON a.location_id = rl.location_id "
            + "LEFT JOIN users u ON ad.approved_by = u.user_id "
            + "LEFT JOIN users ru ON ad.requested_by = ru.user_id "
            + "WHERE ad.disposal_id = ? LIMIT 1",
            disposalId
    );

    if (disposal.isEmpty()) {
        response.sendRedirect("assets.jsp?error=disposal_notfound");
        return;
    }

    String disposalStatus = rowValue(disposal, "disposal_status");
    String statusClass = "";
    if ("PENDING".equalsIgnoreCase(disposalStatus)) statusClass = "warning";
    if ("REJECTED".equalsIgnoreCase(disposalStatus)) statusClass = "danger";

    // Checker stage - open to SUPER_ADMIN/ADMIN/ASSET_MANAGER. Mirrors
    // ReviewAssetDisposalServlet's RBAC. Note ASSET_MANAGER is also the role
    // that submits proposals from dispose_asset.jsp.
    boolean canReviewDisposal = "SUPER_ADMIN".equals(role) || "ADMIN".equals(role) || "ASSET_MANAGER".equals(role);
%>

<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>Disposal Details - IR-AMS</title>

    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.0/css/all.min.css">

    <link rel="stylesheet" href="css/ir-glass.css?v=system-audit-scanner-1">
    <link rel="stylesheet" href="css/ams-pro.css?v=system-audit-scanner-1">
    <link rel="stylesheet" href="css/ir-ams-railway-ui.css?v=system-audit-scanner-1">
<link rel="stylesheet" href="css/view_disposal.css?v=topbarfix1">
</head>

<body class="railway-ui">
<div class="app ams-shell">

        <jsp:include page="sidebar.jsp" />

    <main class="main railway-main">
                <jsp:include page="topbar.jsp" />

        <div class="main-scroll-content detail-board">

            <section class="detail-hero">
                <div>
                    <h1>Disposal #<%= safeText(rowValue(disposal, "disposal_id")) %></h1>
                    <p>
                        <strong><%= safeText(rowValue(disposal, "asset_code")) %></strong>
                        · <%= safeText(rowValue(disposal, "asset_name")) %>
                        · <%= safeText(cleanLabel(rowValue(disposal, "disposal_reason"))) %>
                    </p>
                </div>

                <div class="hero-actions">
                    <span class="status-pill <%= statusClass %>">
                        <i class="fa-solid fa-recycle"></i>
                        <%= safeText(cleanLabel(disposalStatus)) %>
                    </span>

                    <% if ("PENDING".equalsIgnoreCase(disposalStatus) && canReviewDisposal) { %>
                        <form method="post" action="ReviewAssetDisposalServlet" style="display:inline;"
                              onsubmit="return confirm('Approve this disposal? The asset will be permanently marked as disposed.');">
                            <input type="hidden" name="disposalId" value="<%= safeText(rowValue(disposal, "disposal_id")) %>">
                            <input type="hidden" name="action" value="approve">
                            <button type="submit" class="btn" style="background:#10b981; color:#fff; border:none;">
                                <i class="fa-solid fa-check"></i> Approve
                            </button>
                        </form>
                        <form method="post" action="ReviewAssetDisposalServlet" style="display:inline;"
                              onsubmit="return confirm('Reject this disposal proposal?');">
                            <input type="hidden" name="disposalId" value="<%= safeText(rowValue(disposal, "disposal_id")) %>">
                            <input type="hidden" name="action" value="reject">
                            <button type="submit" class="btn" style="background:#ef4444; color:#fff; border:none;">
                                <i class="fa-solid fa-ban"></i> Reject
                            </button>
                        </form>
                    <% } %>

                    <a href="asset_disposals.jsp" class="btn btn-secondary">
                        <i class="fa-solid fa-arrow-left"></i>
                        Back
                    </a>
                </div>
            </section>

            <section class="summary-grid">
                <div class="summary-card"><span>Asset</span><strong><%= safeText(rowValue(disposal, "asset_code")) %></strong></div>
                <div class="summary-card"><span>Reason</span><strong><%= safeText(cleanLabel(rowValue(disposal, "disposal_reason"))) %></strong></div>
                <div class="summary-card"><span>Disposal Value</span><strong>₹ <%= moneyText(rowValue(disposal, "disposal_value")) %></strong></div>
                <div class="summary-card"><span>Requested By</span><strong><%= safeText(rowValue(disposal, "requested_by_name")) %></strong></div>
            </section>

            <section class="detail-grid">
                <div class="detail-panel">
                    <div class="panel-title-row"><h2 class="panel-title">Disposal Details</h2></div>

                    <table class="detail-table">
                        <tr><th>Disposal ID</th><td><%= safeText(rowValue(disposal, "disposal_id")) %></td></tr>
                        <tr><th>Disposal Date</th><td><%= safeText(rowValue(disposal, "disposal_date")) %></td></tr>
                        <tr><th>Reason</th><td><%= safeText(cleanLabel(rowValue(disposal, "disposal_reason"))) %></td></tr>
                        <tr><th>Disposal Value</th><td>₹ <%= moneyText(rowValue(disposal, "disposal_value")) %></td></tr>
                        <% if (!rowValue(disposal, "calculated_book_value").trim().isEmpty()) { %>
                        <tr>
                            <th>Calculated Book Value (Write-Off)</th>
                            <td>
                                ₹ <%= moneyText(rowValue(disposal, "calculated_book_value")) %>
                                <br><span class="table-subtext">System-computed value at the moment of disposal - a reconciliation figure independent of the disposal value above.</span>
                            </td>
                        </tr>
                        <% } %>
                        <tr><th>Status</th><td><%= safeText(cleanLabel(disposalStatus)) %></td></tr>
                        <tr><th>Requested By</th><td><%= safeText(rowValue(disposal, "requested_by_name")) %></td></tr>
                        <tr><th>Requested Date</th><td><%= safeText(rowValue(disposal, "requested_date")) %></td></tr>
                        <tr><th>Reviewed By</th><td><%= safeText(rowValue(disposal, "approved_by_name")) %></td></tr>
                        <tr><th>Reviewed Date</th><td><%= safeText(rowValue(disposal, "approved_date")) %></td></tr>
                        <tr><th>Remarks</th><td><%= safeText(rowValue(disposal, "remarks")) %></td></tr>
                        <tr><th>Created On</th><td><%= safeText(rowValue(disposal, "created_at")) %></td></tr>
                        <tr><th>Updated On</th><td><%= safeText(rowValue(disposal, "updated_at")) %></td></tr>
                    </table>
                </div>

                <div class="detail-panel">
                    <div class="panel-title-row"><h2 class="panel-title">Disposed Asset</h2></div>

                    <table class="detail-table">
                        <tr><th>Asset Code</th><td><a href="view_asset.jsp?id=<%= safeText(rowValue(disposal, "asset_id")) %>"><%= safeText(rowValue(disposal, "asset_code")) %></a></td></tr>
                        <tr><th>Asset Name</th><td><%= safeText(rowValue(disposal, "asset_name")) %></td></tr>
                        <tr><th>Category</th><td><%= safeText(rowValue(disposal, "category_name")) %></td></tr>
                        <tr><th>Serial Number</th><td><%= safeText(rowValue(disposal, "serial_number")) %></td></tr>
                        <tr><th>Model Number</th><td><%= safeText(rowValue(disposal, "model_number")) %></td></tr>
                        <tr><th>Vendor</th><td><%= safeText(rowValue(disposal, "vendor_name")) %></td></tr>
                        <tr><th>Department</th><td><%= safeText(rowValue(disposal, "department_name")) %></td></tr>
                        <tr><th>Location</th><td><%= safeText(rowValue(disposal, "location_name")) %></td></tr>
                        <tr><th>Purchase Cost</th><td>₹ <%= moneyText(rowValue(disposal, "purchase_cost")) %></td></tr>
                        <tr><th>Asset Status</th><td><%= safeText(cleanLabel(rowValue(disposal, "asset_status"))) %></td></tr>
                        <tr><th>Service Status</th><td><%= safeText(cleanLabel(rowValue(disposal, "service_status"))) %></td></tr>
                    </table>
                </div>
            </section>

        </div>
    </main>
</div>

<script src="js/topbar-search.js?v=system-audit-scanner-1"></script>
<script src="js/user-dropdown.js?v=system-audit-scanner-1"></script>
<script src="js/sidebar-role.js?v=system-audit-scanner-1"></script>
<script src="js/ir-body-watermark.js?v=system-audit-scanner-1"></script>
<script src="js/dashboard-actions.js?v=system-audit-scanner-1"></script>

</body>
</html>