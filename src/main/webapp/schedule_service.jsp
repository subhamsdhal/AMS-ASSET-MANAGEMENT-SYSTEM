<%@page contentType="text/html" pageEncoding="UTF-8"%>
<%@page import="com.mycompany.asset_management_system_ams.DBConnection"%>
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
    <title>Schedule Service - IR-AMS</title>

    <link rel="stylesheet"
          href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.0/css/all.min.css">

    <link rel="stylesheet" href="css/ir-glass.css?v=28000">
    <link rel="stylesheet" href="css/ams-pro.css?v=28000">
    <link rel="stylesheet" href="css/ir-ams-railway-ui.css?v=schedule-service-ui-1">

    <link rel="stylesheet" href="css/schedule_service.css?v=28001">
</head>

<body class="railway-ui">
<div class="app ams-shell">

    <jsp:include page="sidebar.jsp" />

    <main class="main railway-main">

        <jsp:include page="topbar.jsp" />

        <div class="main-scroll-content service-board">

            <section class="service-hero">
                <h1>Schedule Maintenance Service</h1>

                <p>
                    Create a service entry and keep the selected asset under maintenance until work is completed.
                    This uses the existing maintenance save flow safely.
                </p>

                <div class="hero-pills">
                    <div class="hero-pill"><i class="fa-solid fa-calendar-check"></i> Service Planning</div>
                    <div class="hero-pill"><i class="fa-solid fa-screwdriver-wrench"></i> Under Maintenance</div>
                    <div class="hero-pill"><i class="fa-solid fa-cube"></i> Asset Based</div>
                    <div class="hero-pill"><i class="fa-solid fa-shield-halved"></i> Admin Controlled</div>
                </div>
            </section>

            <section class="service-panel">

                <div class="panel-head">
                    <div>
                        <h2>Service Schedule Form</h2>
                        <p>This will add a maintenance log and set the asset status to under maintenance.</p>
                    </div>
                </div>

                <% if (error != null && !error.trim().isEmpty()) { %>
                    <div class="alert-error">
                        <i class="fa-solid fa-triangle-exclamation"></i>
                        Service could not be scheduled: <%= display(error) %>
                    </div>
                <% } %>

                <form action="AddMaintenanceServlet" method="post" id="scheduleServiceForm">

                    <input type="hidden" name="assetStatusAfterMaintenance" value="UNDER_MAINTENANCE">

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
                            <label><i class="fa-regular fa-calendar-days"></i> Service Date</label>

                            <input type="date"
                                   name="maintenanceDate"
                                   id="maintenanceDate"
                                   max="<%= todayDate %>"
                                   value="<%= todayDate %>"
                                   required>
                        </div>

                        <div class="form-group">
                            <label><i class="fa-solid fa-screwdriver-wrench"></i> Service Type</label>

                            <select name="maintenanceType" required>
                                <option value="PREVENTIVE">PREVENTIVE - Routine service</option>
                                <option value="CORRECTIVE">CORRECTIVE - Corrective service</option>
                                <option value="REPAIR">REPAIR - Repair service</option>
                            </select>
                        </div>

                        <div class="form-group">
                            <label><i class="fa-solid fa-indian-rupee-sign"></i> Estimated / Service Cost</label>

                            <input type="number"
                                   name="cost"
                                   step="0.01"
                                   min="0"
                                   value="0"
                                   required>
                        </div>

                        <div class="form-group">
                            <label><i class="fa-solid fa-user-gear"></i> Performed By / Team</label>

                            <input type="text"
                                   name="performedBy"
                                   placeholder="Example: Railway IT Maintenance Team"
                                   required>
                        </div>

                        <div class="form-group full-width">
                            <label><i class="fa-solid fa-align-left"></i> Service Description</label>

                            <textarea name="description"
                                      placeholder="Write service purpose, issue, repair note or inspection reason..."
                                      required></textarea>
                        </div>

                    </div>

                    <div class="form-actions">
                        <button type="submit" class="service-btn">
                            <i class="fa-solid fa-calendar-check"></i>
                            Schedule Service
                        </button>

                        <a href="maintenance.jsp" class="service-btn secondary">
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
    const scheduleServiceForm = document.getElementById("scheduleServiceForm");

    function getLocalToday() {
        const today = new Date();
        const timezoneOffset = today.getTimezoneOffset() * 60000;
        const localToday = new Date(today.getTime() - timezoneOffset);
        return localToday.toISOString().split("T")[0];
    }

    if (maintenanceDateInput) {
        maintenanceDateInput.max = getLocalToday();
    }

    if (scheduleServiceForm) {
        scheduleServiceForm.addEventListener("submit", function (event) {
            const today = getLocalToday();

            if (maintenanceDateInput && maintenanceDateInput.value && maintenanceDateInput.value > today) {
                event.preventDefault();
                alert("Service Date cannot be a future date in the current maintenance flow.");
                maintenanceDateInput.focus();
            }
        });
    }
</script>

<script src="js/topbar-search.js?v=global-search-ready-1"></script>
<script src="js/user-dropdown.js?v=5"></script>
<script src="js/sidebar-role.js?v=schedule-service-ui-1"></script>
<script src="js/dashboard-actions.js?v=2"></script>

</body>
</html>