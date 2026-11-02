<%@page contentType="text/html" pageEncoding="UTF-8"%>
<%@page import="java.util.List"%>
<%@page import="com.mycompany.asset_management_system_ams.AssetAllocation"%>
<%@page import="com.mycompany.asset_management_system_ams.AssetAllocationDAO"%>
<%@page import="com.mycompany.asset_management_system_ams.HtmlEscapeUtil"%>

<%
    String username = (String) session.getAttribute("username");
    String role = (String) session.getAttribute("role");
    Object employeeIdObj = session.getAttribute("employee_id");

    response.setHeader("Cache-Control", "no-cache, no-store, must-revalidate");
    response.setHeader("Pragma", "no-cache");
    response.setDateHeader("Expires", 0);

    if (username == null || role == null || employeeIdObj == null || !"EMPLOYEE".equals(role)) {
        response.sendRedirect("login.jsp");
        return;
    }

    int employeeId = Integer.parseInt(employeeIdObj.toString());

    AssetAllocationDAO allocationDAO = new AssetAllocationDAO();
    List<AssetAllocation> allocations = allocationDAO.getAllocationsByEmployeeId(employeeId);

    String error = request.getParameter("error");
    String msg = request.getParameter("msg");
%>

<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>Transfer Asset Preference - IR-AMS</title>
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.0/css/all.min.css">
    <link rel="stylesheet" href="css/ir-glass.css?v=28000">
    <link rel="stylesheet" href="css/ams-pro.css?v=28000">
    <link rel="stylesheet" href="css/ir-ams-railway-ui.css?v=28000">
    <style>
        h1, h2, h3, h4, h5, h6, .hero-banner h1, .panel-header h2 {
            color: #0f172a !important;
        }
        .hero-banner {
            background: linear-gradient(135deg, #f0f7ff, #e0f2fe);
            padding: 24px 30px;
            border-radius: 12px;
            margin-bottom: 24px;
            border: 1px solid #bae6fd;
        }
        .hero-banner h1 { margin: 0; color: #0f172a; font-size: 24px; font-weight: 700; }
        .hero-banner p { margin: 8px 0 0 0; color: #475569; font-size: 15px; }

        .panel {
            background: #ffffff;
            border: 1px solid #e2e8f0;
            border-radius: 12px;
            padding: 24px;
            box-shadow: 0 4px 6px -1px rgba(0, 0, 0, 0.05);
            margin-bottom: 20px;
        }
        .panel-header h2 { margin: 0 0 16px 0; font-size: 18px; color: #0f172a; font-weight: 700; }

        .asset-pref-row {
            border: 1px solid #e2e8f0;
            border-radius: 10px;
            padding: 16px;
            margin-bottom: 12px;
            background: #f8fafc;
        }
        .asset-pref-row strong { color: #0f172a; }
        .asset-pref-row .table-subtext { color: #64748b; font-size: 12px; }
        .pref-badge {
            display: inline-block;
            margin-top: 6px;
            padding: 3px 10px;
            border-radius: 20px;
            font-size: 12px;
            font-weight: 600;
            background: #fef3c7;
            color: #92400e;
        }
        .pref-options { margin-top: 10px; display: flex; gap: 20px; flex-wrap: wrap; }
        .pref-options label { font-weight: normal; }
        .empty-state { text-align: center; padding: 40px 20px; color: #64748b; font-weight: 500; }
        .empty-state i { font-size: 32px; color: #94a3b8; margin-bottom: 12px; display: block; }
        .page-success, .page-error { margin-bottom: 20px; padding: 15px; border-radius: 8px; }
        .page-success { background: #eaf7ef; color: #04733b; }
        .page-error { background: #ffebee; color: #c62828; }
    </style>
</head>
<body class="railway-ui">
<div class="app ams-shell">
    <jsp:include page="sidebar.jsp" />
    <main class="main railway-main">
        <jsp:include page="topbar.jsp" />
        <div class="main-scroll-content">

            <div class="hero-banner">
                <h1>Transfer Asset Preference</h1>
                <p>
                    If you are being transferred, let us know which of your currently allocated assets
                    you'd like to keep and which you'd like to return. This is a request only - your
                    Department Head / Admin will review it and confirm the final decision when your
                    transfer is processed.
                </p>
            </div>

            <% if ("denied".equals(error)) { %>
                <div class="page-error"><i class="fa-solid fa-triangle-exclamation"></i> This page is only available to employee accounts.</div>
            <% } else if ("nopreference".equals(error)) { %>
                <div class="page-error"><i class="fa-solid fa-triangle-exclamation"></i> Please select a preference for at least one asset before submitting.</div>
            <% } else if ("invalid".equals(error)) { %>
                <div class="page-error"><i class="fa-solid fa-triangle-exclamation"></i> Could not identify your employee record. Please contact your administrator.</div>
            <% } else if ("server".equals(error)) { %>
                <div class="page-error"><i class="fa-solid fa-triangle-exclamation"></i> Server error occurred while submitting your preference.</div>
            <% } %>

            <% if ("submitted".equals(msg)) { %>
                <div class="page-success"><i class="fa-solid fa-circle-check"></i> Your preference has been submitted. It will be reviewed when your transfer is processed.</div>
            <% } %>

            <div class="panel">
                <div class="panel-header"><h2>Your Currently Allocated Assets</h2></div>

                <%
                    boolean hasActiveAllocation = false;
                    for (AssetAllocation allocation : allocations) {
                        if ("ALLOCATED".equalsIgnoreCase(allocation.getAllocationStatus())) {
                            hasActiveAllocation = true;
                            break;
                        }
                    }
                %>

                <% if (!hasActiveAllocation) { %>
                    <div class="empty-state">
                        <i class="fa-solid fa-box-archive"></i>
                        You have no currently allocated assets.
                    </div>
                <% } else { %>

                    <form action="SubmitEmployeeTransferPreferenceServlet" method="post">

                        <%
                            for (AssetAllocation allocation : allocations) {
                                if (!"ALLOCATED".equalsIgnoreCase(allocation.getAllocationStatus())) {
                                    continue;
                                }

                                String existingPref = allocation.getEmployeeTransferPreference();
                        %>
                            <div class="asset-pref-row">
                                <strong><%= HtmlEscapeUtil.escape(allocation.getAssetCode()) %></strong>
                                &middot; <%= HtmlEscapeUtil.escape(allocation.getAssetName()) %>
                                <div class="table-subtext">Allocated on <%= HtmlEscapeUtil.escape(allocation.getAllocationDate(), "N/A") %></div>

                                <% if (existingPref != null && !existingPref.trim().isEmpty()) { %>
                                    <span class="pref-badge">
                                        <i class="fa-solid fa-clock"></i>
                                        Pending review - you requested: <%= "RETURN".equalsIgnoreCase(existingPref) ? "Return" : "Keep" %>
                                    </span>
                                <% } %>

                                <div class="pref-options">
                                    <label>
                                        <input type="radio" name="preference_<%= allocation.getAllocationId() %>"
                                               value="retain" <%= !"RETURN".equalsIgnoreCase(existingPref) ? "checked" : "" %>>
                                        I'd like to keep this
                                    </label>
                                    <label>
                                        <input type="radio" name="preference_<%= allocation.getAllocationId() %>"
                                               value="return" <%= "RETURN".equalsIgnoreCase(existingPref) ? "checked" : "" %>>
                                        I'd like to return this
                                    </label>
                                </div>
                            </div>
                        <%
                            }
                        %>

                        <div class="form-group form-group-full" style="margin-top:16px;">
                            <label>Note (optional)</label>
                            <input type="text" name="note" maxlength="255"
                                   placeholder="Example: Transferring to Delhi division next month">
                        </div>

                        <div class="form-actions" style="margin-top:16px;">
                            <button type="submit" class="btn btn-primary">
                                <i class="fa-solid fa-paper-plane"></i> Submit Preference
                            </button>
                        </div>

                    </form>

                <% } %>
            </div>

        </div>
    </main>
</div>
<script src="js/topbar-search.js?v=1"></script>
<script src="js/user-dropdown.js?v=1"></script>
<script src="js/sidebar-role.js?v=1"></script>
<script src="js/ir-body-watermark.js?v=1"></script>
<script src="js/dashboard-actions.js?v=1"></script>
</body>
</html>
