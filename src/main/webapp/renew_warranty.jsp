﻿<%@page contentType="text/html" pageEncoding="UTF-8"%>
<%@page import="com.mycompany.asset_management_system_ams.DBConnection"%>
<%@page import="com.mycompany.asset_management_system_ams.HtmlEscapeUtil"%>
<%@page import="java.sql.Connection"%>
<%@page import="java.sql.PreparedStatement"%>
<%@page import="java.sql.ResultSet"%>

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

    if (!("SUPER_ADMIN".equals(role) || "ADMIN".equals(role) || "ASSET_MANAGER".equals(role))) {
        response.sendRedirect("warranty_report.jsp?access=denied");
        return;
    }

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
    String currentExpiry = "";
    boolean assetFound = false;

    try (Connection con = DBConnection.getConnection();
         PreparedStatement ps = con.prepareStatement(
                 "SELECT asset_code, asset_name, warranty_expiry FROM assets WHERE asset_id = ?")) {
        ps.setInt(1, assetId);
        try (ResultSet rs = ps.executeQuery()) {
            if (rs.next()) {
                assetFound = true;
                assetCode = rs.getString("asset_code");
                assetName = rs.getString("asset_name");
                currentExpiry = rs.getString("warranty_expiry");
            }
        }
    } catch (Exception e) {
        e.printStackTrace();
    }

    if (!assetFound) {
        response.sendRedirect("warranty_report.jsp?error=invalid_asset");
        return;
    }

    String error = request.getParameter("error");
    String errorMsg = "";
    if ("invalid_extension".equals(error)) {
        errorMsg = "Enter a valid extension between 1 and 240 months.";
    } else if ("missing_date".equals(error)) {
        errorMsg = "Provide either a new expiry date or an extension period.";
    } else if ("invalid_date".equals(error)) {
        errorMsg = "The new expiry date could not be read. Please re-select it.";
    } else if ("date_in_past".equals(error)) {
        errorMsg = "The new expiry date must not be in the past.";
    } else if ("server".equals(error)) {
        errorMsg = "Unable to save the renewal. Please try again.";
    }
%>
<!DOCTYPE html>
<html>
<head>
    <title>IR-AMS Renew Warranty</title>

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
                <h1>Renew Asset Warranty</h1>

                <p>
                    Log a warranty extension or replacement policy for
                    <strong><%= HtmlEscapeUtil.escape(assetName, "this asset") %></strong>
                    (<%= HtmlEscapeUtil.escape(assetCode, "-") %>) and update its live coverage status.
                </p>

                <br>

                <div class="hero-pills">
                    <div class="hero-pill">
                        <i class="fa-solid fa-shield-halved"></i> Warranty Control
                    </div>
                    <div class="hero-pill">
                        <i class="fa-solid fa-rotate"></i> Renewal Log
                    </div>
                </div>
            </section>

            <% if (!errorMsg.isEmpty()) { %>
                <div class="page-error">
                    <i class="fa-solid fa-triangle-exclamation"></i>
                    <%= HtmlEscapeUtil.escape(errorMsg) %>
                </div>
            <% } %>

            <section class="settings-form-grid">

                <div class="settings-form-card">
                    <h2>
                        <i class="fa-solid fa-file-shield"></i>
                        Renewal Details
                    </h2>

                    <p>
                        Current expiry on record:
                        <strong><%= currentExpiry == null || currentExpiry.trim().isEmpty() ? "No warranty on record" : HtmlEscapeUtil.escape(currentExpiry) %></strong>
                    </p>

                    <form action="RenewAssetWarrantyServlet" method="post">
                        <input type="hidden" name="assetId" value="<%= assetId %>">

                        <div class="form-group">
                            <label>
                                <i class="fa-solid fa-calendar-check"></i>
                                New Expiry Date
                            </label>
                            <input type="date" name="newExpiry">
                            <small>Set this directly if you know the exact new expiry date from the vendor's renewal document.</small>
                        </div>

                        <p style="text-align:center;margin:6px 0;color:var(--ir-muted, #62708d);">— or —</p>

                        <div class="form-group">
                            <label>
                                <i class="fa-solid fa-hourglass-half"></i>
                                Extension (Months from current expiry)
                            </label>
                            <input type="number" name="extensionMonths" min="1" max="240" placeholder="e.g. 12">
                            <small>Leave "New Expiry Date" blank to use this instead - calculated from the current expiry (or from today, if there's no warranty on record).</small>
                        </div>

                        <div class="form-group">
                            <label>
                                <i class="fa-solid fa-indian-rupee-sign"></i>
                                Renewal Cost (₹)
                            </label>
                            <input type="number" name="renewalCost" min="0" step="0.01" placeholder="0.00">
                        </div>

                        <div class="form-group">
                            <label>
                                <i class="fa-solid fa-note-sticky"></i>
                                Notes
                            </label>
                            <textarea name="notes" maxlength="1000" placeholder="Renewal document reference, new provider, terms..."></textarea>
                        </div>

                        <br>

                        <button type="submit" class="btn submit-btn">
                            <i class="fa-solid fa-floppy-disk"></i>
                            Save Renewal
                        </button>

                        <a href="view_warranty_history.jsp?id=<%= assetId %>" class="btn">
                            <i class="fa-solid fa-clock-rotate-left"></i>
                            View History
                        </a>

                        <a href="warranty_report.jsp" class="btn secondary-btn">
                            <i class="fa-solid fa-arrow-left"></i>
                            Back to Warranty Report
                        </a>
                    </form>
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
