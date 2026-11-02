﻿<%@page contentType="text/html" pageEncoding="UTF-8"%>
<%@page import="com.mycompany.asset_management_system_ams.DBConnection"%>
<%@page import="com.mycompany.asset_management_system_ams.HtmlEscapeUtil"%>
<%@page import="com.mycompany.asset_management_system_ams.WarrantyRenewal"%>
<%@page import="com.mycompany.asset_management_system_ams.WarrantyRenewalDAO"%>
<%@page import="java.sql.Connection"%>
<%@page import="java.sql.PreparedStatement"%>
<%@page import="java.sql.ResultSet"%>
<%@page import="java.util.List"%>

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

    // Read-only - same access level as warranty_report.jsp itself
    // (SUPER_ADMIN/ADMIN/ASSET_MANAGER/AUDITOR), unlike renew_warranty.jsp
    // which is a mutating action restricted to fewer roles.
    boolean canView = "SUPER_ADMIN".equals(role) || "ADMIN".equals(role)
            || "ASSET_MANAGER".equals(role) || "AUDITOR".equals(role);
    if (!canView) {
        response.sendRedirect("dashboard.jsp?access=denied");
        return;
    }

    boolean canRenew = "SUPER_ADMIN".equals(role) || "ADMIN".equals(role) || "ASSET_MANAGER".equals(role);

    int assetId = 0;
    try {
        assetId = Integer.parseInt(request.getParameter("id"));
    } catch (Exception e) {
        assetId = 0;
    }

    if (assetId <= 0) {
        response.sendRedirect("warranty_report.jsp?error=invalid_asset");
        return;
    }

    String assetCode = "";
    String assetName = "";
    boolean assetFound = false;

    try (Connection con = DBConnection.getConnection();
         PreparedStatement ps = con.prepareStatement(
                 "SELECT asset_code, asset_name FROM assets WHERE asset_id = ?")) {
        ps.setInt(1, assetId);
        try (ResultSet rs = ps.executeQuery()) {
            if (rs.next()) {
                assetFound = true;
                assetCode = rs.getString("asset_code");
                assetName = rs.getString("asset_name");
            }
        }
    } catch (Exception e) {
        e.printStackTrace();
    }

    if (!assetFound) {
        response.sendRedirect("warranty_report.jsp?error=invalid_asset");
        return;
    }

    List<WarrantyRenewal> history = new WarrantyRenewalDAO().getHistoryForAsset(assetId);
%>
<!DOCTYPE html>
<html>
<head>
    <title>IR-AMS Warranty Renewal History</title>

    <link rel="stylesheet"
          href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.0/css/all.min.css">

    <link rel="stylesheet" href="css/ir-glass.css?v=28000">
    <link rel="stylesheet" href="css/ams-pro.css?v=28000">
    <link rel="stylesheet" href="css/ir-ams-railway-ui.css?v=28000">
    <link rel="stylesheet" href="css/warranty_report.css?v=topbarfix1">
</head>

<body class="railway-ui">

<div class="app">

    <jsp:include page="sidebar.jsp" />

    <main class="main railway-main">
        <jsp:include page="topbar.jsp" />

        <div class="main-scroll-content">

            <section class="asset-hero">
                <h1>Warranty Renewal History</h1>

                <p>
                    Full renewal timeline for
                    <strong><%= HtmlEscapeUtil.escape(assetName, "this asset") %></strong>
                    (<%= HtmlEscapeUtil.escape(assetCode, "-") %>).
                </p>

                <br>

                <div class="hero-pills">
                    <div class="hero-pill">
                        <i class="fa-solid fa-clock-rotate-left"></i>
                        <%= history.size() %> renewal<%= history.size() == 1 ? "" : "s" %> on record
                    </div>
                </div>
            </section>

            <section class="glass-panel">

                <div class="registry-toolbar">
                    <div>
                        <h2>Renewal Timeline</h2>
                        <p class="table-subtext">
                            Each entry below also updated the asset's live warranty expiry at the time it was recorded.
                        </p>
                    </div>

                    <div class="registry-actions">
                        <% if (canRenew) { %>
                            <a href="renew_warranty.jsp?id=<%= assetId %>" class="btn">
                                <i class="fa-solid fa-rotate"></i>
                                Renew Warranty
                            </a>
                        <% } %>
                        <a href="warranty_report.jsp" class="btn secondary-btn">
                            <i class="fa-solid fa-arrow-left"></i>
                            Back to Warranty Report
                        </a>
                    </div>
                </div>

                <% if (history.isEmpty()) { %>
                    <div class="no-records-message">
                        <i class="fa-solid fa-circle-info"></i>
                        <strong>No renewal history found for this asset.</strong>
                        <span>Renewals recorded from now on will appear here chronologically.</span>
                    </div>
                <% } else { %>
                    <div class="registry-table-wrap">
                        <table class="asset-table">
                            <thead>
                                <tr>
                                    <th>Renewed On</th>
                                    <th>Previous Expiry</th>
                                    <th>New Expiry</th>
                                    <th>Extension</th>
                                    <th>Cost</th>
                                    <th>Renewed By</th>
                                    <th>Notes</th>
                                </tr>
                            </thead>
                            <tbody>
                                <% for (WarrantyRenewal renewal : history) { %>
                                    <tr>
                                        <td><%= HtmlEscapeUtil.escape(renewal.getCreatedAt(), "-") %></td>
                                        <td><%= HtmlEscapeUtil.escape(renewal.getPreviousExpiry(), "No prior warranty") %></td>
                                        <td><strong><%= HtmlEscapeUtil.escape(renewal.getNewExpiry(), "-") %></strong></td>
                                        <td><%= renewal.getExtensionMonths() == null ? "-" : renewal.getExtensionMonths() + " months" %></td>
                                        <td>₹<%= String.format("%,.2f", renewal.getRenewalCost()) %></td>
                                        <td><%= HtmlEscapeUtil.escape(renewal.getRenewedByUsername(), "System") %></td>
                                        <td><%= HtmlEscapeUtil.escape(renewal.getNotes(), "-") %></td>
                                    </tr>
                                <% } %>
                            </tbody>
                        </table>
                    </div>
                <% } %>

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
