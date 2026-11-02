<%@page contentType="text/html" pageEncoding="UTF-8"%>
<%@page import="com.mycompany.asset_management_system_ams.DBConnection"%>
<%@page import="com.mycompany.asset_management_system_ams.SettingsDAO"%>
<%@page import="java.sql.*"%>
<%@page import="java.util.*"%>

<%!
    private String safe(Object value) {
        if (value == null) {
            return "";
        }

        return value.toString()
                .replace("&", "&amp;")
                .replace("<", "&lt;")
                .replace(">", "&gt;")
                .replace("\"", "&quot;")
                .replace("'", "&#39;");
    }

    private String display(Object value) {
        if (value == null || value.toString().trim().isEmpty()) {
            return "N/A";
        }

        return safe(value);
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

    boolean canManageMaintenance = ("SUPER_ADMIN".equals(role) || "ADMIN".equals(role))
            || "ASSET_MANAGER".equalsIgnoreCase(role);

    if (!canManageMaintenance) {
        response.sendRedirect("maintenance.jsp?access=denied");
        return;
    }

    String error = request.getParameter("error");
    String userInitial = username.substring(0, Math.min(2, username.length())).toUpperCase(Locale.ENGLISH);

    List<Map<String, String>> assetList = new ArrayList<Map<String, String>>();

    try (Connection con = DBConnection.getConnection()) {

        String sql = "SELECT a.asset_id, a.asset_code, a.asset_name, a.asset_status, "
                + "COALESCE(c.category_name, 'Uncategorized') AS category_name "
                + "FROM assets a "
                + "LEFT JOIN asset_categories c ON a.category_id = c.category_id "
                + "WHERE a.asset_status <> 'DISPOSED' "
                + "ORDER BY a.asset_code ASC";

        try (PreparedStatement ps = con.prepareStatement(sql);
             ResultSet rs = ps.executeQuery()) {

            while (rs.next()) {
                Map<String, String> row = new HashMap<String, String>();
                row.put("asset_id", rs.getString("asset_id"));
                row.put("asset_code", rs.getString("asset_code"));
                row.put("asset_name", rs.getString("asset_name"));
                row.put("asset_status", rs.getString("asset_status"));
                row.put("category_name", rs.getString("category_name"));
                assetList.add(row);
            }
        }

    } catch (Exception e) {
        e.printStackTrace();
    }

    String todayDate = new java.text.SimpleDateFormat("yyyy-MM-dd").format(new java.util.Date());
%>

<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>Add Maintenance - IR-AMS</title>

    <link rel="stylesheet"
          href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.0/css/all.min.css">

    <link rel="stylesheet" href="css/ir-glass.css?v=28000">
    <link rel="stylesheet" href="css/ams-pro.css?v=28000">
    <link rel="stylesheet" href="css/ir-ams-railway-ui.css?v=28000">
<link rel="stylesheet" href="css/add_maintenance.css?v=topbarfix1">
</head>

<body class="railway-ui">
<div class="app ams-shell">

    <jsp:include page="sidebar.jsp" />

    <main class="main railway-main">
        <%
            // Duplicated topbar markup, same as dashboard.jsp (pre-existing, not
            // introduced here) - kept in sync by hand with topbar.jsp's session timer.
            int addMaintSessionTimeoutMinutes = SettingsDAO.getSessionTimeout();
            if (addMaintSessionTimeoutMinutes < 1 || addMaintSessionTimeoutMinutes > 1440) {
                addMaintSessionTimeoutMinutes = 30;
            }
            // See topbar.jsp's identical marker.
            String addMaintSessionMarker = session.getAttribute("client_session_marker") != null
                    ? (String) session.getAttribute("client_session_marker") : "legacy-session";
        %>
                <header class="topbar railway-topbar">
            <button class="nav-toggle" type="button" aria-label="Toggle sidebar">
                <i class="fa-solid fa-bars"></i>
            </button>

            <a href="dashboard.jsp" class="topbar-title topbar-home-link" title="Open Dashboard">
                <h1>IR-AMS</h1>
                <span>Add Maintenance</span>
            </a>

            <button class="hq-selector" type="button" data-dashboard-menu="hq" aria-label="Railway unit">
                <i class="fa-solid fa-location-dot"></i>
                <div>
                    <strong>East Coast Railway</strong>
                    <span>Headquarters / Rail Sadan, Bhubaneswar</span>
                </div>
                <i class="fa-solid fa-angle-down"></i>
            </button>

            <div class="search-box">
                <i class="fa-solid fa-magnifying-glass"></i>
                <input type="text"
                       id="globalSearch"
                       placeholder="Register maintenance log, service type, cost, technician...">
            </div>

            <div class="topbar-actions top-right">
                <div class="control-active session-timer-pill" id="sessionTimerPill" title="Time remaining before automatic sign-out"
                     data-total-seconds="<%= addMaintSessionTimeoutMinutes * 60 %>" data-context-path="<%= request.getContextPath() %>"
                     data-session-marker="<%= addMaintSessionMarker %>">
                    <i class="fa-regular fa-clock"></i>
                    <span id="sessionTimerText">--:--</span>
                </div>

                <button type="button" class="control-active" data-dashboard-menu="alerts">
                    <i class="fa-solid fa-shield-halved"></i>
                    Control Active
                    <i class="fa-solid fa-angle-down"></i>
                </button>

                <button type="button" class="top-icon-btn" title="Notifications">
                    <i class="fa-regular fa-bell"></i>
                </button>

                <button type="button" class="top-icon-btn" title="Messages">
                    <i class="fa-regular fa-envelope"></i>
                </button>

                <button type="button" class="top-icon-btn" title="Help">
                    <i class="fa-regular fa-circle-question"></i>
                </button>

                <div class="user-card" title="User menu">
                    <div class="avatar">IR</div>
                    <div>
                        <strong><%= username %></strong>
                        <span><%= role == null ? "" : role.replace("_", " ") %></span>
                    </div>
                </div>
            </div>
        </header>

        <style>
            body.railway-ui .session-timer-pill { color: var(--ir-text, #06215f) !important; cursor: default !important; }
            body.railway-ui .session-timer-pill.session-timer-warning { color: #b45309 !important; }
            body.railway-ui .session-timer-pill.session-timer-critical { color: #b91c1c !important; }
        </style>
        <script src="<%= request.getContextPath() %>/js/session-timer.js?v=1"></script>

        <div class="main-scroll-content maintenance-board">

            <section class="maintenance-hero">
                <h1>Add Maintenance Log</h1>

                <p>
                    Register preventive maintenance, corrective work or repair activity for railway assets.<br>
                    Asset status can be kept under maintenance or marked available after service.
                </p>

                <div class="hero-pills">
                    <div class="hero-pill"><i class="fa-solid fa-screwdriver-wrench"></i> Service Entry</div>
                    <div class="hero-pill"><i class="fa-solid fa-cube"></i> Asset Based</div>
                    <div class="hero-pill"><i class="fa-solid fa-envelope"></i> Notification Ready</div>
                    <div class="hero-pill"><i class="fa-solid fa-shield-halved"></i> Admin Controlled</div>
                </div>
            </section>

            <section class="maintenance-panel">

                <div class="panel-head">
                    <div>
                        <h2>Maintenance Registration Form</h2>
                        <p>Select an asset, enter service details and choose the final service outcome.</p>
                    </div>

                    <span class="access-pill">
                        <i class="fa-solid fa-shield-halved"></i>
                        <%= display(cleanLabel(role)) %> Access
                    </span>
                </div>

                <% if ("failed".equals(error)) { %>
                    <div class="alert-error">
                        <i class="fa-solid fa-triangle-exclamation"></i>
                        Maintenance log could not be added. Please check all required details.
                    </div>
                <% } else if ("invaliddate".equals(error)) { %>
                    <div class="alert-error">
                        <i class="fa-solid fa-triangle-exclamation"></i>
                        Maintenance Date cannot be a future date.
                    </div>
                <% } else if ("invalidcost".equals(error)) { %>
                    <div class="alert-error">
                        <i class="fa-solid fa-triangle-exclamation"></i>
                        Maintenance cost cannot be negative.
                    </div>
                <% } else if ("blocked".equals(error)) { %>
                    <div class="alert-error">
                        <i class="fa-solid fa-triangle-exclamation"></i>
                        Maintenance blocked. Selected asset may be disposed or invalid.
                    </div>
                <% } else if ("server".equals(error)) { %>
                    <div class="alert-error">
                        <i class="fa-solid fa-triangle-exclamation"></i>
                        Server error occurred while adding maintenance.
                    </div>
                <% } %>

                <form action="AddMaintenanceServlet" method="post" id="addMaintenanceForm">

                    <div class="form-grid">

                        <div class="form-group">
                            <label><i class="fa-solid fa-cube"></i> Asset</label>

                            <select name="assetId" required>
                                <option value="">Select Asset</option>

                                <%
                                    for (Map<String, String> asset : assetList) {
                                %>
                                    <option value="<%= safe(asset.get("asset_id")) %>">
                                        <%= display(asset.get("asset_code")) %> -
                                        <%= display(asset.get("asset_name")) %>
                                        (<%= display(cleanLabel(asset.get("asset_status"))) %>)
                                    </option>
                                <%
                                    }
                                %>
                            </select>
                        </div>

                        <div class="form-group">
                            <label><i class="fa-regular fa-calendar-days"></i> Maintenance Date</label>

                            <input type="date"
                                   name="maintenanceDate"
                                   id="maintenanceDate"
                                   max="<%= todayDate %>"
                                   value="<%= todayDate %>"
                                   required>
                        </div>

                        <div class="form-group">
                            <label><i class="fa-solid fa-screwdriver-wrench"></i> Maintenance Type</label>

                            <select name="maintenanceType" required>
                                <option value="PREVENTIVE">PREVENTIVE - Routine check / cleaning</option>
                                <option value="CORRECTIVE">CORRECTIVE - Issue correction</option>
                                <option value="REPAIR">REPAIR - Repair work</option>
                                <option value="INSPECTION">INSPECTION - Physical / functional check</option>
                            </select>
                        </div>

                        <div class="form-group">
                            <label><i class="fa-solid fa-indian-rupee-sign"></i> Cost</label>

                            <input type="number"
                                   name="cost"
                                   step="0.01"
                                   min="0"
                                   value="0"
                                   required>
                        </div>

                        <div class="form-group">
                            <label><i class="fa-solid fa-user-gear"></i> Performed By</label>

                            <input type="text"
                                   name="performedBy"
                                   placeholder="Example: Railway IT Maintenance Team"
                                   required>
                        </div>

                        <div class="form-group">
                            <label><i class="fa-solid fa-signal"></i> Asset Status After Service</label>

                            <select name="assetStatusAfterMaintenance" required>
                                <option value="UNDER_MAINTENANCE">Keep Under Maintenance</option>
                                <option value="AVAILABLE">Mark Service Completed</option>
                            </select>
                        </div>

                        <div class="form-group full-width">
                            <label><i class="fa-solid fa-align-left"></i> Description</label>

                            <textarea name="description"
                                      placeholder="Write the issue, service work, repair note or preventive maintenance details..."
                                      required></textarea>
                        </div>

                    </div>

                    <div class="note-box" style="margin-top: 28px !important;">
                        <i class="fa-solid fa-circle-info"></i>
                        <div>
                            <strong>Important:</strong>
                            Choose &ldquo;Mark as Available&rdquo; only if the service is completed and the asset is ready for allocation.
                            Otherwise keep it under maintenance.
                        </div>
                    </div>

                    <div class="form-actions">
                        <button type="submit" class="maintenance-btn">
                            <i class="fa-solid fa-circle-check"></i>
                            Save Maintenance
                        </button>

                        <a href="maintenance.jsp" class="maintenance-btn secondary">
                            <i class="fa-solid fa-arrow-left"></i>
                            Back to Maintenance
                        </a>
                    </div>

                </form>

            </section>

        </div>
    </main>
</div>

<script>
    const maintenanceDateInput = document.getElementById("maintenanceDate");
    const addMaintenanceForm = document.getElementById("addMaintenanceForm");

    function getLocalToday() {
        const today = new Date();
        const timezoneOffset = today.getTimezoneOffset() * 60000;
        const localToday = new Date(today.getTime() - timezoneOffset);
        return localToday.toISOString().split("T")[0];
    }

    if (maintenanceDateInput) {
        maintenanceDateInput.max = getLocalToday();
    }

    if (addMaintenanceForm) {
        addMaintenanceForm.addEventListener("submit", function (event) {
            const today = getLocalToday();

            if (maintenanceDateInput && maintenanceDateInput.value && maintenanceDateInput.value > today) {
                event.preventDefault();
                alert("Maintenance Date cannot be a future date.");
                maintenanceDateInput.focus();
            }
        });
    }
</script>

<script src="${pageContext.request.contextPath}/js/date-rules.js"></script>
<script src="js/topbar-search.js?v=28000"></script>
<script src="js/user-dropdown.js?v=28000"></script>
<script src="js/sidebar-role.js?v=28000"></script>
<script src="js/ir-body-watermark.js?v=28000"></script>
<script src="js/dashboard-actions.js?v=28000"></script>

</body>
</html>
