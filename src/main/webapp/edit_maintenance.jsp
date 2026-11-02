﻿<%@page contentType="text/html" pageEncoding="UTF-8"%>
<%@page import="com.mycompany.asset_management_system_ams.DBConnection"%>
<%@page import="java.sql.*"%>
<%@page import="java.util.*"%>

<%!
    private String safe(Object value) {
        if (value == null) {
            return "";
        }

        return value.toString().trim()
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

    private String selected(String actual, String expected) {
        if (actual != null && actual.equalsIgnoreCase(expected)) {
            return "selected";
        }

        return "";
    }

    private String rowValue(Map<String, String> row, String key) {
        if (row == null) {
            return "";
        }

        String value = row.get(key);
        return value == null ? "" : value;
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

    private boolean columnExists(Connection con, String tableName, String columnName) {
        String sql = "SELECT COUNT(*) FROM information_schema.columns "
                + "WHERE table_schema = DATABASE() "
                + "AND table_name = ? "
                + "AND column_name = ?";

        try (PreparedStatement ps = con.prepareStatement(sql)) {
            ps.setString(1, tableName);
            ps.setString(2, columnName);

            try (ResultSet rs = ps.executeQuery()) {
                return rs.next() && rs.getInt(1) > 0;
            }

        } catch (Exception e) {
            e.printStackTrace();
        }

        return false;
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

    int maintenanceId = 0;

    try {
        maintenanceId = Integer.parseInt(request.getParameter("id"));
    } catch (Exception e) {
        response.sendRedirect("maintenance.jsp?error=invalid");
        return;
    }

    String error = request.getParameter("error");
    String userInitial = username.substring(0, Math.min(2, username.length())).toUpperCase(Locale.ENGLISH);

    Map<String, String> maintenance = new HashMap<String, String>();
    List<Map<String, String>> assetList = new ArrayList<Map<String, String>>();
    List<Map<String, String>> supplierList = new ArrayList<Map<String, String>>();
    List<Map<String, String>> employeeList = new ArrayList<Map<String, String>>();

    boolean hasMaintenanceStatus = false;
    boolean hasNextDueDate = false;
    boolean hasIssueReported = false;
    boolean hasWorkDone = false;
    boolean hasDescription = false;
    boolean hasPerformedBy = false;
    boolean hasVendorId = false;
    boolean hasPerformedByEmployeeId = false;
    boolean hasRemarks = false;

    try (Connection con = DBConnection.getConnection()) {

        hasMaintenanceStatus = columnExists(con, "maintenance_logs", "maintenance_status");
        hasNextDueDate = columnExists(con, "maintenance_logs", "next_due_date");
        hasIssueReported = columnExists(con, "maintenance_logs", "issue_reported");
        hasWorkDone = columnExists(con, "maintenance_logs", "work_done");
        hasDescription = columnExists(con, "maintenance_logs", "description");
        hasPerformedBy = columnExists(con, "maintenance_logs", "performed_by");
        hasVendorId = columnExists(con, "maintenance_logs", "vendor_id");
        hasPerformedByEmployeeId = columnExists(con, "maintenance_logs", "performed_by_employee_id");
        hasRemarks = columnExists(con, "maintenance_logs", "remarks");

        String maintenanceSql = "SELECT "
                + "ml.maintenance_id, "
                + "ml.asset_id, "
                + "DATE_FORMAT(ml.maintenance_date, '%Y-%m-%d') AS maintenance_date, "
                + "ml.maintenance_type, "
                + (hasMaintenanceStatus ? "COALESCE(ml.maintenance_status, '')" : "''") + " AS maintenance_status, "
                + (hasNextDueDate ? "DATE_FORMAT(ml.next_due_date, '%Y-%m-%d')" : "''") + " AS next_due_date, "
                + (hasIssueReported ? "COALESCE(ml.issue_reported, '')" : (hasDescription ? "COALESCE(ml.description, '')" : "''")) + " AS issue_reported, "
                + (hasWorkDone ? "COALESCE(ml.work_done, '')" : (hasDescription ? "COALESCE(ml.description, '')" : "''")) + " AS work_done, "
                + (hasDescription ? "COALESCE(ml.description, '')" : "''") + " AS description, "
                + "COALESCE(ml.cost, 0) AS cost, "
                + (hasPerformedBy ? "COALESCE(ml.performed_by, '')" : "''") + " AS performed_by, "
                + (hasVendorId ? "COALESCE(ml.vendor_id, 0)" : "0") + " AS vendor_id, "
                + (hasPerformedByEmployeeId ? "COALESCE(ml.performed_by_employee_id, 0)" : "0") + " AS performed_by_employee_id, "
                + (hasRemarks ? "COALESCE(ml.remarks, '')" : "''") + " AS remarks, "
                + "a.asset_code, a.asset_name, a.asset_status, "
                + "COALESCE(ac.category_name, 'Uncategorized') AS category_name "
                + "FROM maintenance_logs ml "
                + "LEFT JOIN assets a ON ml.asset_id = a.asset_id "
                + "LEFT JOIN asset_categories ac ON a.category_id = ac.category_id "
                + "WHERE ml.maintenance_id = ? "
                + "LIMIT 1";

        try (PreparedStatement ps = con.prepareStatement(maintenanceSql)) {
            ps.setInt(1, maintenanceId);

            try (ResultSet rs = ps.executeQuery()) {
                ResultSetMetaData meta = rs.getMetaData();
                int count = meta.getColumnCount();

                if (rs.next()) {
                    for (int i = 1; i <= count; i++) {
                        maintenance.put(meta.getColumnLabel(i), rs.getString(i));
                    }
                }
            }
        }

        if (maintenance.isEmpty()) {
            response.sendRedirect("maintenance.jsp?error=notfound");
            return;
        }

        String assetSql = "SELECT asset_id, asset_code, asset_name, asset_status "
                + "FROM assets "
                + "WHERE asset_status <> 'DISPOSED' "
                + "ORDER BY asset_code ASC";

        try (PreparedStatement ps = con.prepareStatement(assetSql);
             ResultSet rs = ps.executeQuery()) {

            while (rs.next()) {
                Map<String, String> row = new HashMap<String, String>();
                row.put("asset_id", rs.getString("asset_id"));
                row.put("asset_code", rs.getString("asset_code"));
                row.put("asset_name", rs.getString("asset_name"));
                row.put("asset_status", rs.getString("asset_status"));
                assetList.add(row);
            }
        }

        if (tableExists(con, "vendors")) {
            String supplierSql = "SELECT vendor_id, vendor_name "
                    + "FROM vendors "
                    + "ORDER BY vendor_name ASC";

            try (PreparedStatement ps = con.prepareStatement(supplierSql);
                 ResultSet rs = ps.executeQuery()) {

                while (rs.next()) {
                    Map<String, String> row = new HashMap<String, String>();
                    row.put("vendor_id", rs.getString("vendor_id"));
                    row.put("vendor_name", rs.getString("vendor_name"));
                    supplierList.add(row);
                }
            }
        }

        if (tableExists(con, "employees")) {
            boolean hasFullName = columnExists(con, "employees", "full_name");
            boolean hasEmployeeCode = columnExists(con, "employees", "employee_code");

            String employeeNameExpression = hasFullName
                    ? "COALESCE(full_name, '')"
                    : "TRIM(CONCAT(COALESCE(employee_name, ''), ' ', COALESCE(employee_name, '')))";

            String employeeCodeExpression = hasEmployeeCode
                    ? "COALESCE(employee_code, '')"
                    : "''";

            String employeeSql = "SELECT employee_id, "
                    + employeeNameExpression + " AS employee_name, "
                    + employeeCodeExpression + " AS employee_code "
                    + "FROM employees "
                    + "ORDER BY employee_name ASC";

            try (PreparedStatement ps = con.prepareStatement(employeeSql);
                 ResultSet rs = ps.executeQuery()) {

                while (rs.next()) {
                    Map<String, String> row = new HashMap<String, String>();
                    row.put("employee_id", rs.getString("employee_id"));
                    row.put("employee_name", rs.getString("employee_name"));
                    row.put("employee_code", rs.getString("employee_code"));
                    employeeList.add(row);
                }
            }
        }

    } catch (Exception e) {
        e.printStackTrace();
        response.sendRedirect("maintenance.jsp?error=server");
        return;
    }

    String currentAssetId = rowValue(maintenance, "asset_id");
    String currentVendorId = rowValue(maintenance, "vendor_id");
    String currentEmployeeId = rowValue(maintenance, "performed_by_employee_id");
    String currentMaintenanceStatus = rowValue(maintenance, "maintenance_status");
    String currentAssetStatus = rowValue(maintenance, "asset_status");
    String currentServiceOutcome = "UNDER_MAINTENANCE".equalsIgnoreCase(currentAssetStatus)
            ? "UNDER_MAINTENANCE"
            : "AVAILABLE";
%>

<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>Edit Maintenance - IR-AMS</title>

    <link rel="stylesheet"
          href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.0/css/all.min.css">

    <link rel="stylesheet" href="css/ir-glass.css?v=28000">
    <link rel="stylesheet" href="css/ams-pro.css?v=28000">
    <link rel="stylesheet" href="css/ir-ams-railway-ui.css?v=28000">
<link rel="stylesheet" href="css/edit_maintenance.css?v=topbarfix1">
</head>

<body class="railway-ui">
<div class="app ams-shell">

    <jsp:include page="sidebar.jsp" />

    <main class="main railway-main">
        <jsp:include page="topbar.jsp" />

        <div class="main-scroll-content edit-maintenance-board">

            <section class="edit-maintenance-hero">
                <h1>Edit Maintenance Record</h1>

                <p>
                    Update maintenance record MNT-<%= maintenanceId %> for
                    <strong><%= display(rowValue(maintenance, "asset_code")) %></strong>
                    · <%= display(rowValue(maintenance, "asset_name")) %>
                    · Current Asset Status: <%= display(cleanLabel(currentAssetStatus)) %>
                </p>

                <div class="hero-pills">
                    <div class="hero-pill">
                        <i class="fa-solid fa-screwdriver-wrench"></i>
                        Maintenance Update
                    </div>

                    <div class="hero-pill">
                        <i class="fa-solid fa-cube"></i>
                        <%= display(rowValue(maintenance, "asset_code")) %>
                    </div>

                    <div class="hero-pill">
                        <i class="fa-solid fa-layer-group"></i>
                        <%= display(rowValue(maintenance, "category_name")) %>
                    </div>

                    <div class="hero-pill">
                        <i class="fa-solid fa-shield-halved"></i>
                        Admin Controlled
                    </div>
                </div>
            </section>

            <section class="maintenance-panel">

                <div class="maintenance-panel-head">
                    <div>
                        <h2>Maintenance Update Form</h2>
                        <p>
                            Edit service details carefully. Updating service outcome may also update the linked asset status.
                        </p>
                    </div>

                    <span class="access-pill">
                        <i class="fa-solid fa-shield-halved"></i>
                        <%= display(cleanLabel(role)) %> Access
                    </span>
                </div>

                <% if ("failed".equals(error)) { %>
                    <div class="maintenance-alert">
                        <i class="fa-solid fa-triangle-exclamation"></i>
                        Maintenance record could not be updated. Please check all values.
                    </div>
                <% } else if ("server".equals(error)) { %>
                    <div class="maintenance-alert">
                        <i class="fa-solid fa-triangle-exclamation"></i>
                        Server error occurred while updating maintenance record.
                    </div>
                <% } else if ("invaliddate".equals(error)) { %>
                    <div class="maintenance-alert">
                        <i class="fa-solid fa-triangle-exclamation"></i>
                        Invalid date rule. Maintenance Date cannot be future and Next Due Date cannot be before Maintenance Date.
                    </div>
                <% } else if ("invalidcost".equals(error)) { %>
                    <div class="maintenance-alert">
                        <i class="fa-solid fa-triangle-exclamation"></i>
                        Maintenance cost cannot be negative.
                    </div>
                <% } else if ("blocked".equals(error)) { %>
                    <div class="maintenance-alert">
                        <i class="fa-solid fa-triangle-exclamation"></i>
                        Update blocked. Selected asset may be disposed or invalid.
                    </div>
                <% } %>

                <form action="UpdateMaintenanceServlet" method="post" id="editMaintenanceForm">

                    <input type="hidden" name="maintenanceId" value="<%= maintenanceId %>">

                    <div class="maintenance-form-grid">

                        <div class="maintenance-form-group">
                            <label>
                                <i class="fa-solid fa-cube"></i>
                                Asset
                            </label>

                            <select name="assetId" required>
                                <%
                                    for (Map<String, String> asset : assetList) {
                                        String assetId = rowValue(asset, "asset_id");
                                %>
                                    <option value="<%= safe(assetId) %>" <%= selected(assetId, currentAssetId) %>>
                                        <%= display(rowValue(asset, "asset_code")) %> -
                                        <%= display(rowValue(asset, "asset_name")) %>
                                        (<%= display(cleanLabel(rowValue(asset, "asset_status"))) %>)
                                    </option>
                                <%
                                    }
                                %>
                            </select>
                        </div>

                        <div class="maintenance-form-group">
                            <label>
                                <i class="fa-regular fa-calendar-days"></i>
                                Maintenance Date
                            </label>

                            <input type="date"
                                   name="maintenanceDate"
                                   id="maintenanceDate"
                                   value="<%= safe(rowValue(maintenance, "maintenance_date")) %>"
                                   required>
                        </div>

                        <div class="maintenance-form-group">
                            <label>
                                <i class="fa-solid fa-screwdriver-wrench"></i>
                                Maintenance Type
                            </label>

                            <select name="maintenanceType" required>
                                <option value="PREVENTIVE" <%= selected(rowValue(maintenance, "maintenance_type"), "PREVENTIVE") %>>
                                    PREVENTIVE - Routine check / cleaning
                                </option>

                                <option value="CORRECTIVE" <%= selected(rowValue(maintenance, "maintenance_type"), "CORRECTIVE") %>>
                                    CORRECTIVE - Issue correction
                                </option>

                                <option value="REPAIR" <%= selected(rowValue(maintenance, "maintenance_type"), "REPAIR") %>>
                                    REPAIR - Repair work
                                </option>

                                <option value="INSPECTION" <%= selected(rowValue(maintenance, "maintenance_type"), "INSPECTION") %>>
                                    INSPECTION - Physical / functional check
                                </option>
                            </select>
                        </div>

                        <div class="maintenance-form-group">
                            <label>
                                <i class="fa-solid fa-list-check"></i>
                                Maintenance Status
                            </label>

                            <select name="maintenanceStatus">
                                <option value="OPEN" <%= selected(currentMaintenanceStatus, "OPEN") %>>Open</option>
                                <option value="IN_PROGRESS" <%= selected(currentMaintenanceStatus, "IN_PROGRESS") %>>In Progress</option>
                                <option value="COMPLETED" <%= selected(currentMaintenanceStatus, "COMPLETED") %>>Completed</option>
                                <option value="CANCELLED" <%= selected(currentMaintenanceStatus, "CANCELLED") %>>Cancelled</option>
                            </select>
                        </div>

                        <div class="maintenance-form-group">
                            <label>
                                <i class="fa-solid fa-calendar-check"></i>
                                Next Due Date
                            </label>

                            <input type="date"
                                   name="nextDueDate"
                                   id="nextDueDate"
                                   value="<%= safe(rowValue(maintenance, "next_due_date")) %>">
                        </div>

                        <div class="maintenance-form-group">
                            <label>
                                <i class="fa-solid fa-indian-rupee-sign"></i>
                                Cost
                            </label>

                            <input type="number"
                                   name="cost"
                                   step="0.01"
                                   min="0"
                                   value="<%= safe(rowValue(maintenance, "cost")) %>"
                                   required>
                        </div>

                        <div class="maintenance-form-group">
                            <label>
                                <i class="fa-solid fa-truck-field"></i>
                                Supplier
                            </label>

                            <select name="vendorId">
                                <option value="0">No Supplier / Internal Maintenance</option>

                                <%
                                    for (Map<String, String> supplier : supplierList) {
                                        String vendorId = rowValue(supplier, "vendor_id");
                                %>
                                    <option value="<%= safe(vendorId) %>" <%= selected(vendorId, currentVendorId) %>>
                                        <%= display(rowValue(supplier, "vendor_name")) %>
                                    </option>
                                <%
                                    }
                                %>
                            </select>
                        </div>

                        <div class="maintenance-form-group">
                            <label>
                                <i class="fa-solid fa-user-gear"></i>
                                Performed By Employee
                            </label>

                            <select name="performedByEmployeeId">
                                <option value="0">Not Assigned / External Team</option>

                                <%
                                    for (Map<String, String> employee : employeeList) {
                                        String employeeId = rowValue(employee, "employee_id");
                                %>
                                    <option value="<%= safe(employeeId) %>" <%= selected(employeeId, currentEmployeeId) %>>
                                        <%= display(rowValue(employee, "employee_code")) %>
                                        -
                                        <%= display(rowValue(employee, "employee_name")) %>
                                    </option>
                                <%
                                    }
                                %>
                            </select>
                        </div>

                        <div class="maintenance-form-group">
                            <label>
                                <i class="fa-solid fa-user-pen"></i>
                                Performed By / Team Name
                            </label>

                            <input type="text"
                                   name="performedBy"
                                   value="<%= safe(rowValue(maintenance, "performed_by")) %>"
                                   placeholder="Example: Railway IT Maintenance Team"
                                   required>
                        </div>

                        <div class="maintenance-form-group">
                            <label>
                                <i class="fa-solid fa-signal"></i>
                                Asset Status After Update
                            </label>

                            <select name="assetStatusAfterMaintenance" required>
                                <option value="UNDER_MAINTENANCE" <%= selected(currentServiceOutcome, "UNDER_MAINTENANCE") %>>
                                    Keep Under Maintenance
                                </option>

                                <option value="AVAILABLE" <%= selected(currentServiceOutcome, "AVAILABLE") %>>
                                    Mark Service Completed
                                </option>
                            </select>
                        </div>

                        <div class="maintenance-form-group full-width">
                            <label>
                                <i class="fa-solid fa-triangle-exclamation"></i>
                                Issue Reported
                            </label>

                            <textarea name="issueReported" placeholder="Write issue reported / service reason"><%= safe(rowValue(maintenance, "issue_reported")) %></textarea>
                        </div>

                        <div class="maintenance-form-group full-width">
                            <label>
                                <i class="fa-solid fa-clipboard-check"></i>
                                Work Done
                            </label>

                            <textarea name="workDone" placeholder="Write work done / maintenance activity"><%= safe(rowValue(maintenance, "work_done")) %></textarea>
                        </div>

                        <div class="maintenance-form-group full-width">
                            <label>
                                <i class="fa-solid fa-align-left"></i>
                                Description
                            </label>

                            <textarea name="description" placeholder="Short maintenance description"><%= safe(rowValue(maintenance, "description")) %></textarea>
                        </div>

                        <div class="maintenance-form-group full-width">
                            <label>
                                <i class="fa-regular fa-note-sticky"></i>
                                Remarks
                            </label>

                            <textarea name="remarks" placeholder="Optional remarks"><%= safe(rowValue(maintenance, "remarks")) %></textarea>
                        </div>

                    </div>

                    <div class="maintenance-note">
                        <i class="fa-solid fa-circle-info"></i>

                        <div>
                            <strong>Important:</strong>
                            Use “Mark as Available” only after the maintenance work is completed and asset is ready for operational allocation.
                            If the work is pending or verification is not complete, keep the asset under maintenance.
                        </div>
                    </div>

                    <div class="form-actions">
                        <button type="submit" class="maintenance-btn">
                            <i class="fa-solid fa-circle-check"></i>
                            Update Maintenance
                        </button>

                        <a href="view_maintenance.jsp?id=<%= maintenanceId %>" class="maintenance-btn green">
                            <i class="fa-solid fa-eye"></i>
                            View Maintenance
                        </a>

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
    const nextDueDateInput = document.getElementById("nextDueDate");
    const editMaintenanceForm = document.getElementById("editMaintenanceForm");

    function getLocalToday() {
        const today = new Date();
        const timezoneOffset = today.getTimezoneOffset() * 60000;
        const localToday = new Date(today.getTime() - timezoneOffset);
        return localToday.toISOString().split("T")[0];
    }

    function applyDateRules() {
        const today = getLocalToday();

        if (maintenanceDateInput) {
            maintenanceDateInput.max = today;
        }

        if (maintenanceDateInput && nextDueDateInput) {
            if (maintenanceDateInput.value) {
                nextDueDateInput.min = maintenanceDateInput.value;
            }

            maintenanceDateInput.addEventListener("change", function () {
                nextDueDateInput.min = maintenanceDateInput.value;

                if (nextDueDateInput.value
                        && maintenanceDateInput.value
                        && nextDueDateInput.value < maintenanceDateInput.value) {
                    nextDueDateInput.value = "";
                }
            });
        }
    }

    applyDateRules();

    if (editMaintenanceForm) {
        editMaintenanceForm.addEventListener("submit", function (event) {
            const today = getLocalToday();

            if (maintenanceDateInput && maintenanceDateInput.value && maintenanceDateInput.value > today) {
                event.preventDefault();
                alert("Maintenance Date cannot be a future date.");
                maintenanceDateInput.focus();
                return;
            }

            if (maintenanceDateInput && nextDueDateInput
                    && maintenanceDateInput.value
                    && nextDueDateInput.value
                    && nextDueDateInput.value < maintenanceDateInput.value) {
                event.preventDefault();
                alert("Next Due Date cannot be before Maintenance Date.");
                nextDueDateInput.focus();
            }
        });
    }
</script>

<script src="js/topbar-search.js?v=28000"></script>
<script src="js/user-dropdown.js?v=28000"></script>
<script src="js/sidebar-role.js?v=28000"></script>
<script src="js/ir-body-watermark.js?v=28000"></script>
<script src="js/dashboard-actions.js?v=28000"></script>

</body>
</html>
