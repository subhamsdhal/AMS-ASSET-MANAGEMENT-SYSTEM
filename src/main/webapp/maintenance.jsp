<%@page contentType="text/html" pageEncoding="UTF-8"%>
<%@page import="com.mycompany.asset_management_system_ams.MaintenanceLog"%>
<%@page import="com.mycompany.asset_management_system_ams.MaintenanceLogDAO"%>
<%@page import="com.mycompany.asset_management_system_ams.MaintenanceRequestDAO"%>
<%@page import="java.util.List"%>
<%@page import="java.util.Map"%>
<%@page import="java.util.Locale"%>
<%@page import="java.text.DecimalFormat"%>

<%!
    public String formatNumber(int number) {
        if (number >= 100000) {
            return String.format("%.1fL", number / 100000.0);
        } else if (number >= 1000) {
            return String.format("%.1fK", number / 1000.0);
        }
        return String.valueOf(number);
    }

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

    private String statusClass(String status) {
        if (status == null || status.trim().isEmpty()) {
            return "UNKNOWN";
        }

        return status.trim().toUpperCase(Locale.ENGLISH).replace(" ", "_");
    }

    private String typeClass(String type) {
        if (type == null || type.trim().isEmpty()) {
            return "UNKNOWN";
        }

        return type.trim().toUpperCase(Locale.ENGLISH).replace(" ", "_");
    }

    private String moneyNoDecimal(double value) {
        return String.format("%,.0f", value);
    }

    private String compactNumber(int value) {
        DecimalFormat df = new DecimalFormat("0.#");

        if (value >= 10000000) {
            return df.format(value / 10000000.0) + "Cr";
        }

        if (value >= 100000) {
            return df.format(value / 100000.0) + "L";
        }

        if (value >= 1000) {
            return df.format(value / 1000.0) + "K";
        }

        return String.valueOf(value);
    }

    private String compactMoney(double value) {
        DecimalFormat df = new DecimalFormat("0.#");

        if (value >= 10000000) {
            return df.format(value / 10000000.0) + "Cr";
        }

        if (value >= 100000) {
            return df.format(value / 100000.0) + "L";
        }

        if (value >= 1000) {
            return df.format(value / 1000.0) + "K";
        }

        return String.format("%.0f", value);
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

    boolean canExportMaintenance = ("SUPER_ADMIN".equals(role) || "ADMIN".equals(role))
            || "ASSET_MANAGER".equalsIgnoreCase(role)
            || "AUDITOR".equalsIgnoreCase(role);

    MaintenanceLogDAO dao = new MaintenanceLogDAO();
    List<MaintenanceLog> maintenanceList = dao.getAllMaintenanceLogs();

    String msg = request.getParameter("msg");
    String success = request.getParameter("success");
    String error = request.getParameter("error");
    String access = request.getParameter("access");

    int userId = 0;
    if (session.getAttribute("user_id") != null) {
        userId = (Integer) session.getAttribute("user_id");
    }

    MaintenanceRequestDAO mrDao = new MaintenanceRequestDAO();
    List<Map<String, String>> empRequests = mrDao.getEmployeeMaintenanceRequestsForRole(role, userId);

    int preventive = 0;
    int corrective = 0;
    int repair = 0;
    int inspection = 0;
    int underMaintenance = 0;
    int resolvedAvailable = 0;
    double totalCost = 0;

    for (MaintenanceLog log : maintenanceList) {
        if ("PREVENTIVE".equalsIgnoreCase(log.getMaintenanceType())) {
            preventive++;
        }

        if ("CORRECTIVE".equalsIgnoreCase(log.getMaintenanceType())) {
            corrective++;
        }

        if ("REPAIR".equalsIgnoreCase(log.getMaintenanceType())) {
            repair++;
        }

        if ("INSPECTION".equalsIgnoreCase(log.getMaintenanceType())) {
            inspection++;
        }

        if ("UNDER_MAINTENANCE".equalsIgnoreCase(log.getAssetStatus())) {
            underMaintenance++;
        }

        if ("AVAILABLE".equalsIgnoreCase(log.getAssetStatus())
                || "ALLOCATED".equalsIgnoreCase(log.getAssetStatus())) {
            resolvedAvailable++;
        }

        totalCost += log.getCost();
    }

    String userInitial = username.substring(0, Math.min(2, username.length())).toUpperCase(Locale.ENGLISH);
%>

<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>Maintenance - IR-AMS</title>

    <link rel="stylesheet"
          href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.0/css/all.min.css">

    <link rel="stylesheet" href="css/ir-glass.css?v=final-reference-1">
    <link rel="stylesheet" href="css/ams-pro.css?v=final-reference-1">
    <link rel="stylesheet" href="css/ir-ams-railway-ui.css?v=final-reference-1">
<link rel="stylesheet" href="css/maintenance.css?v=topbarfix1">
</head>

<body class="railway-ui">
<div class="app ams-shell">

    
    <jsp:include page="sidebar.jsp" />

    <main class="main railway-main">
        <jsp:include page="topbar.jsp" />

        <div class="main-scroll-content maintenance-board">

            <% if ("denied".equals(access)) { %>
                <div class="page-error">
                    <i class="fa-solid fa-triangle-exclamation"></i>
                    Access denied. You do not have permission to manage maintenance records.
                </div>
            <% } %>

            <% if ("added".equals(msg)) { %>
                <div class="page-success">
                    <i class="fa-solid fa-circle-check"></i>
                    Maintenance log added successfully and asset status updated.
                </div>
            <% } else if ("updated".equals(msg)) { %>
                <div class="page-success">
                    <i class="fa-solid fa-circle-check"></i>
                    Maintenance record updated successfully.
                </div>
            <% } %>

            <% if ("resolved".equals(success)) { %>
                <div class="page-success">
                    <i class="fa-solid fa-circle-check"></i>
                    Maintenance resolved successfully. Asset status updated to AVAILABLE.
                </div>
            <% } else if ("scheduled".equals(success)) { %>
                <div class="page-success">
                    <i class="fa-solid fa-circle-check"></i>
                    Maintenance service scheduled successfully. Asset status updated to UNDER MAINTENANCE.
                </div>
            <% } else if ("already_resolved".equals(success)) { %>
                <div class="page-success">
                    <i class="fa-solid fa-circle-check"></i>
                    Maintenance was already resolved. Asset is already AVAILABLE.
                </div>
            <% } %>

            <% if (error != null && !error.trim().isEmpty()) { %>
                <div class="page-error">
                    <i class="fa-solid fa-triangle-exclamation"></i>
                    Action failed: <%= display(error) %>
                </div>
            <% } %>

            <section class="maintenance-hero-new">
                <h1>Maintenance Service Console</h1>

                <p>
                    Monitor preventive checks, corrective service, repairs, maintenance cost,
                    asset health status and resolution control for railway operational inventory.
                </p>

                <div class="hero-pills">
                    <div class="hero-pill"><i class="fa-solid fa-screwdriver-wrench"></i> Service Tracking</div>
                    <div class="hero-pill"><i class="fa-solid fa-shield-halved"></i> Preventive Checks</div>
                    <div class="hero-pill"><i class="fa-solid fa-triangle-exclamation"></i> Repair Alerts</div>
                    <div class="hero-pill"><i class="fa-solid fa-indian-rupee-sign"></i> Cost Monitoring</div>
                </div>
            </section>

            <section class="kpi-grid">

                <div class="kpi-card">
                    <div class="kpi-icon"><i class="fa-solid fa-toolbox"></i></div>
                    <h3 class="kpi-title">Total Logs</h3>
                    <div class="kpi-value" title="<%= maintenanceList.size() %>"><%= compactNumber(maintenanceList.size()) %></div>
                </div>

                <div class="kpi-card">
                    <div class="kpi-icon"><i class="fa-solid fa-circle-check"></i></div>
                    <h3 class="kpi-title">Resolved Assets</h3>
                    <div class="kpi-value" title="<%= resolvedAvailable %>"><%= compactNumber(resolvedAvailable) %></div>
                </div>

                <div class="kpi-card">
                    <div class="kpi-icon"><i class="fa-solid fa-triangle-exclamation"></i></div>
                    <h3 class="kpi-title">Under Maintenance</h3>
                    <div class="kpi-value" title="<%= underMaintenance %>"><%= compactNumber(underMaintenance) %></div>
                </div>

                <div class="kpi-card">
                    <div class="kpi-icon"><i class="fa-solid fa-shield-halved"></i></div>
                    <h3 class="kpi-title">Preventive</h3>
                    <div class="kpi-value" title="<%= preventive %>"><%= compactNumber(preventive) %></div>
                </div>

                <div class="kpi-card">
                    <div class="kpi-icon"><i class="fa-solid fa-wrench"></i></div>
                    <h3 class="kpi-title">Repair</h3>
                    <div class="kpi-value" title="<%= repair %>"><%= compactNumber(repair) %></div>
                </div>

                <div class="kpi-card">
                    <div class="kpi-icon"><i class="fa-solid fa-clipboard-check"></i></div>
                    <h3 class="kpi-title">Inspection</h3>
                    <div class="kpi-value" title="<%= inspection %>"><%= compactNumber(inspection) %></div>
                </div>

                <div class="kpi-card">
                    <div class="kpi-icon"><i class="fa-solid fa-indian-rupee-sign"></i></div>
                    <h3 class="kpi-title">Total Cost</h3>
                    <div class="kpi-value" title="₹<%= moneyNoDecimal(totalCost) %>">₹<%= compactMoney(totalCost) %></div>
                </div>

            </section>

            <section class="glass-panel">

                <div class="registry-toolbar">

                    <div>
                        <h2>Maintenance Logs Table</h2>
                        <p class="table-subtext">
                            Showing <%= maintenanceList.size() %> live maintenance records from railway database.
                        </p>
                    </div>

                    <div class="registry-actions">
                        <% if (canManageMaintenance) { %>
                            <a href="add_maintenance.jsp" class="btn primary">
                                <i class="fa-solid fa-plus"></i>
                                New Log
                            </a>

                            <a href="schedule_service.jsp" class="btn">
                                <i class="fa-solid fa-calendar-check"></i>
                                Schedule Service
                            </a>
                        <% } %>

                        <% if (canExportMaintenance) { %>
                            <a href="export_maintenance.jsp" class="btn">
                                <i class="fa-solid fa-file-export"></i>
                                Export
                            </a>
                        <% } %>
                    </div>

                </div>

                <div class="registry-filter-grid maintenance-filter-grid">

                    <div class="registry-search">
                        <i class="fa-solid fa-magnifying-glass"></i>
                        <input type="text"
                               id="maintenanceSearch"
                               placeholder="Search maintenance id, asset, type, status, performed by, description...">
                    </div>

                    <select id="maintenanceTypeFilter" class="status-filter-select">
                        <option value="ALL">All Type</option>
                        <option value="PREVENTIVE">PREVENTIVE</option>
                        <option value="CORRECTIVE">CORRECTIVE</option>
                        <option value="REPAIR">REPAIR</option>
                        <option value="INSPECTION">INSPECTION</option>
                    </select>

                    <select id="maintenanceStatusFilter" class="status-filter-select">
                        <option value="ALL">All Asset Status</option>
                        <option value="AVAILABLE">AVAILABLE</option>
                        <option value="UNDER_MAINTENANCE">UNDER_MAINTENANCE</option>
                        <option value="ALLOCATED">ALLOCATED</option>
                        <option value="DISPOSED">DISPOSED</option>
                    </select>

                </div>

                <div class="registry-table-wrap">

                    <table class="maintenance-table" id="maintenanceTable">
                        <colgroup>
                            <col style="width: 9%;">
                            <col style="width: 12%;">
                            <col style="width: 10%;">
                            <col style="width: 8%;">
                            <col style="width: 8%;">
                            <col style="width: 11%;">
                            <col style="width: 13%;">
                            <col style="width: 7%;">
                            <col style="width: 7%;">
                            <col style="width: 15%;">
                        </colgroup>

                        <thead>
                            <tr>
                                <th class="maintenance-id-header" onclick="sortTable(0)" style="cursor: pointer;" title="Click to sort">
                                    <span class="maintenance-id-heading">
                                        <span class="maintenance-id-heading-line">Maintenance</span>
                                        <span class="maintenance-id-heading-line">ID <i class="fa-solid fa-sort" style="color: #cbd5e1; margin-left: 4px;"></i></span>
                                    </span>
                                </th>
                                <th onclick="sortTable(1)" style="cursor: pointer;" title="Click to sort">Asset <i class="fa-solid fa-sort" style="color: #cbd5e1; margin-left: 4px;"></i></th>
                                <th onclick="sortTable(2)" style="cursor: pointer;" title="Click to sort">Category <i class="fa-solid fa-sort" style="color: #cbd5e1; margin-left: 4px;"></i></th>
                                <th onclick="sortTable(3)" style="cursor: pointer;" title="Click to sort">Date <i class="fa-solid fa-sort" style="color: #cbd5e1; margin-left: 4px;"></i></th>
                                <th onclick="sortTable(4)" style="cursor: pointer;" title="Click to sort">Type <i class="fa-solid fa-sort" style="color: #cbd5e1; margin-left: 4px;"></i></th>
                                <th onclick="sortTable(5)" style="cursor: pointer;" title="Click to sort">Asset Status <i class="fa-solid fa-sort" style="color: #cbd5e1; margin-left: 4px;"></i></th>
                                <th onclick="sortTable(6)" style="cursor: pointer;" title="Click to sort">Description <i class="fa-solid fa-sort" style="color: #cbd5e1; margin-left: 4px;"></i></th>
                                <th onclick="sortTable(7)" style="cursor: pointer;" title="Click to sort">Cost <i class="fa-solid fa-sort" style="color: #cbd5e1; margin-left: 4px;"></i></th>
                                <th onclick="sortTable(8)" style="cursor: pointer;" title="Click to sort">Performed By <i class="fa-solid fa-sort" style="color: #cbd5e1; margin-left: 4px;"></i></th>
                                <th>Control Actions</th>
                            </tr>
                        </thead>

                        <tbody>
                        <%
                            if (maintenanceList == null || maintenanceList.isEmpty()) {
                        %>

                            <tr>
                                <td colspan="10" style="text-align:center; padding:45px;">
                                    <i class="fa-solid fa-screwdriver-wrench" style="font-size:34px; opacity:0.7;"></i>
                                    <br><br>
                                    <strong>No Maintenance Records Found</strong>
                                    <br>
                                    <span class="table-subtext">
                                        No maintenance logs are available for the current search/filter.
                                    </span>
                                </td>
                            </tr>

                        <%
                            } else {
                                for (MaintenanceLog log : maintenanceList) {

                                    String assetStatus = log.getAssetStatus();
                                    String currentStatusClass = statusClass(assetStatus);
                                    String currentTypeClass = typeClass(log.getMaintenanceType());

                                    boolean canResolveThis = canManageMaintenance
                                            && "UNDER_MAINTENANCE".equalsIgnoreCase(assetStatus);

                                    String resolutionClass = "running";
                                    String resolutionIcon = "fa-circle-info";
                                    String resolutionText = cleanLabel(assetStatus);

                                    if ("AVAILABLE".equalsIgnoreCase(assetStatus)) {
                                        resolutionClass = "resolved";
                                        resolutionIcon = "fa-circle-check";
                                        resolutionText = "Resolved";
                                    } else if ("ALLOCATED".equalsIgnoreCase(assetStatus)) {
                                        resolutionClass = "resolved";
                                        resolutionIcon = "fa-right-left";
                                        resolutionText = "Reassigned";
                                    } else if ("DISPOSED".equalsIgnoreCase(assetStatus)) {
                                        resolutionClass = "blocked";
                                        resolutionIcon = "fa-ban";
                                        resolutionText = "Disposed";
                                    } else if ("UNDER_MAINTENANCE".equalsIgnoreCase(assetStatus)) {
                                        resolutionClass = "running";
                                        resolutionIcon = "fa-screwdriver-wrench";
                                        resolutionText = "In Service";
                                    }
                        %>

                            <tr class="maintenance-row"
                                data-type="<%= safe(typeClass(log.getMaintenanceType())) %>"
                                data-status="<%= safe(statusClass(assetStatus)) %>">

                                <td>
                                    <span class="maintenance-id-pill">
                                        <i class="fa-solid fa-hashtag"></i>
                                        MNT-<%= log.getMaintenanceId() %>
                                    </span>
                                </td>

                                <td>
                                    <span class="asset-mini-pill">
                                        <i class="fa-solid fa-cube"></i>
                                        <%= display(log.getAssetCode()) %>
                                    </span>
                                    <br>
                                    <span class="table-subtext">
                                        <%= display(log.getAssetName()) %>
                                    </span>
                                </td>

                                <td>
                                    <%= display(log.getCategoryName()) %>
                                </td>

                                <td>
                                    <%= display(log.getMaintenanceDate()) %>
                                </td>

                                <td>
                                    <span class="status-badge type-<%= safe(currentTypeClass) %>">
                                        <%= display(log.getMaintenanceType()) %>
                                    </span>
                                </td>

                                <td>
                                    <span class="asset-status-pill status-<%= safe(currentStatusClass) %>">
                                        <%= display(cleanLabel(assetStatus)) %>
                                    </span>
                                </td>

                                <td>
                                    <%= display(log.getDescription()) %>
                                </td>

                                <td>
                                    <span class="cost-pill">
                                        ₹<%= moneyNoDecimal(log.getCost()) %>
                                    </span>
                                </td>

                                <td>
                                    <%= display(log.getPerformedBy()) %>
                                </td>

                                <td>
                                    <div class="maintenance-actions">

                                        <a href="view_maintenance.jsp?id=<%= log.getMaintenanceId() %>"
                                           class="maintenance-action-btn view-btn" title="View details of this maintenance log">
                                            <i class="fa-solid fa-eye"></i> View
                                        </a>

                                        <% if (canManageMaintenance) { %>
                                            <a href="edit_maintenance.jsp?id=<%= log.getMaintenanceId() %>"
                                               class="maintenance-action-btn edit-btn" title="Edit this record">
                                                <i class="fa-solid fa-pen-to-square"></i> Edit
                                            </a>
                                        <% } %>

                                        <% if (canResolveThis) { %>
                                            <form action="resolve_maintenance.jsp" method="post" style="display:inline;" onsubmit="return confirm('Mark this maintenance as resolved and make asset AVAILABLE?');">
                                                <input type="hidden" name="id" value="<%= log.getMaintenanceId() %>">
                                                <button type="submit" class="maintenance-action-btn resolve-btn" style="border:none; cursor:pointer;" title="Resolve maintenance issue">
                                                    <i class="fa-solid fa-clipboard-check"></i> Resolve
                                                </button>
                                            </form>
                                        <% } else { %>
                                            <span class="resolution-pill <%= resolutionClass %>" title="Current resolution status">
                                                <i class="fa-solid <%= resolutionIcon %>"></i>
                                                <%= display(resolutionText) %>
                                            </span>
                                        <% } %>

                                        <a href="maintenance_history.jsp?id=<%= log.getMaintenanceId() %>"
                                           class="maintenance-action-btn history-btn" title="View asset history">
                                            <i class="fa-solid fa-clock-rotate-left"></i> History
                                        </a>

                                    </div>
                                </td>
                            </tr>

                        <%
                                }
                            }
                        %>

                        </tbody>

                    </table>

                    <div id="maintenanceNoRecords" class="no-records-message" style="display:none;">
                        <i class="fa-solid fa-circle-info"></i>
                        <strong>No matching maintenance records found.</strong>
                        Try changing search keyword, maintenance type or asset status filter.
                    </div>

                </div>

            </section>

            <section class="glass-panel" style="margin-top: 30px;">
                <div class="registry-toolbar">
                    <div>
                        <h2>Employee Maintenance Requests</h2>
                        <p class="table-subtext">
                            Showing <%= empRequests.size() %> employee-initiated maintenance requests.
                        </p>
                    </div>
                </div>

                <div class="registry-table-wrap">
                    <table class="maintenance-table">
                        <thead>
                            <tr>
                                <th>Request ID</th>
                                <th>Employee</th>
                                <th>Asset</th>
                                <th>Date</th>
                                <th>Priority</th>
                                <th>Description</th>
                                <th>Status</th>
                                <th>Remarks</th>
                                <th>Control Actions</th>
                            </tr>
                        </thead>
                        <tbody>
                            <%
                                if (empRequests.isEmpty()) {
                            %>
                                <tr>
                                    <td colspan="9" style="text-align:center; padding:45px;">
                                        <i class="fa-solid fa-clipboard-question" style="font-size:34px; opacity:0.7;"></i>
                                        <br><br>
                                        <strong>No employee maintenance requests found.</strong>
                                    </td>
                                </tr>
                            <%
                                } else {
                                    for (Map<String, String> req : empRequests) {
                                        String reqStatus = req.get("request_status");
                                        String statusCls = reqStatus.toUpperCase(Locale.ENGLISH).replace(" ", "_");
                            %>
                                <tr>
                                    <td>MREQ-<%= safe(req.get("request_id")) %></td>
                                    <td><%= safe(req.get("employee_code")) %> - <%= safe(req.get("employee_name")) %></td>
                                    <td><%= safe(req.get("asset_code")) %></td>
                                    <td><%= safe(req.get("request_date")) %></td>
                                    <td><%= safe(req.get("priority")) %></td>
                                    <td><%= safe(req.get("issue_description")) %></td>
                                    <td><span class="asset-status-pill status-<%= statusCls %>"><%= safe(reqStatus) %></span></td>
                                    <td>
                                        <%= req.get("remarks") != null && !req.get("remarks").isEmpty() ? safe(req.get("remarks")) : "-" %>
                                        <% if (req.get("resolved_maintenance_id") != null && !req.get("resolved_maintenance_id").isEmpty()) { %>
                                            <br><span style="font-size:11px; color:#64748b;">
                                                <i class="fa-solid fa-link"></i> Resolved by Log #<%= safe(req.get("resolved_maintenance_id")) %>
                                                (<%= safe(req.get("resolved_maintenance_type")) %>, <%= safe(req.get("resolved_maintenance_date")) %>)
                                            </span>
                                        <% } %>
                                    </td>
                                    <td>
                                        <div style="display:flex; gap: 8px;">
                                            <% if (canManageMaintenance || "ADMIN".equalsIgnoreCase(role)) { %>
                                                <% if ("PENDING".equals(reqStatus)) { %>
                                                <form action="UpdateMaintenanceRequestStatusServlet" method="POST" style="display:inline;" onsubmit="return confirm('Approve this request?');">
                                                    <input type="hidden" name="requestId" value="<%= req.get("request_id") %>">
                                                    <input type="hidden" name="requestStatus" value="APPROVED">
                                                    <input type="hidden" name="remarks" value="Approved">
                                                    <button type="submit" class="btn primary" style="padding:4px 8px; font-size:12px;" title="Approve"><i class="fa-solid fa-check"></i></button>
                                                </form>
                                                <form action="UpdateMaintenanceRequestStatusServlet" method="POST" style="display:inline;" onsubmit="return confirm('Reject this request?');">
                                                    <input type="hidden" name="requestId" value="<%= req.get("request_id") %>">
                                                    <input type="hidden" name="requestStatus" value="REJECTED">
                                                    <input type="hidden" name="remarks" value="Rejected">
                                                    <button type="submit" class="btn" style="padding:4px 8px; font-size:12px; background:#ef4444; color:#fff;" title="Reject"><i class="fa-solid fa-xmark"></i></button>
                                                </form>
                                                <% } else if ("APPROVED".equals(reqStatus) || "IN_PROGRESS".equals(reqStatus)) {
                                                    // Resolution-log picker: lets the actor link this request to the
                                                    // maintenance_logs row that actually resolved it (Future Scope
                                                    // traceability fix). Scoped to this request's own asset - queried
                                                    // inline per row, only for rows that can actually reach Complete,
                                                    // same style as this JSP's other per-row lookups.
                                                    List<Map<String, String>> resolutionLogs =
                                                            mrDao.getMaintenanceLogsForAsset(Integer.parseInt(req.get("asset_id")));
                                                %>
                                                <form action="UpdateMaintenanceRequestStatusServlet" method="POST" style="display:inline; display:flex; gap:4px; align-items:center;" onsubmit="return confirm('Mark as Completed?');">
                                                    <input type="hidden" name="requestId" value="<%= req.get("request_id") %>">
                                                    <input type="hidden" name="requestStatus" value="COMPLETED">
                                                    <input type="hidden" name="remarks" value="Maintenance completed">
                                                    <% if (!resolutionLogs.isEmpty()) { %>
                                                        <select name="resolvedMaintenanceId" style="font-size:11px; padding:2px; max-width:150px;" title="Which maintenance log resolved this request?">
                                                            <option value="0">-- No log link --</option>
                                                            <% for (Map<String, String> logRow : resolutionLogs) { %>
                                                                <option value="<%= logRow.get("maintenance_id") %>">
                                                                    Log #<%= logRow.get("maintenance_id") %> - <%= safe(logRow.get("maintenance_type")) %> (<%= safe(logRow.get("maintenance_date")) %>)
                                                                </option>
                                                            <% } %>
                                                        </select>
                                                    <% } %>
                                                    <button type="submit" class="btn" style="padding:4px 8px; font-size:12px; background:#10b981; color:#fff;" title="Complete"><i class="fa-solid fa-check-double"></i></button>
                                                </form>
                                                <% } else { %>
                                                    <span style="color:#64748b; font-size:12px;">No Actions</span>
                                                <% } %>
                                            <% } else { %>
                                                <span style="color:#64748b; font-size:12px;">View Only</span>
                                            <% } %>
                                        </div>
                                    </td>
                                </tr>
                            <%
                                    }
                                }
                            %>
                        </tbody>
                    </table>
                </div>
            </section>

        </div>
    </main>

</div>

<script>
    const maintenanceSearch = document.getElementById("maintenanceSearch");
    const maintenanceTypeFilter = document.getElementById("maintenanceTypeFilter");
    const maintenanceStatusFilter = document.getElementById("maintenanceStatusFilter");
    const maintenanceRows = document.querySelectorAll("#maintenanceTable tbody tr");
    const maintenanceNoRecords = document.getElementById("maintenanceNoRecords");

    function normalizeText(text) {
        return text
                .toLowerCase()
                .replace(/\s+/g, " ")
                .trim();
    }

    function applyMaintenanceFilters() {
        const keyword = maintenanceSearch ? normalizeText(maintenanceSearch.value) : "";
        const selectedType = maintenanceTypeFilter ? maintenanceTypeFilter.value : "ALL";
        const selectedStatus = maintenanceStatusFilter ? maintenanceStatusFilter.value : "ALL";

        let visibleCount = 0;

        maintenanceRows.forEach(row => {
            const rowText = normalizeText(row.textContent);
            const rowType = row.getAttribute("data-type") || "";
            const rowStatus = row.getAttribute("data-status") || "";

            const matchesSearch =
                    keyword === "" || rowText.indexOf(keyword) !== -1;

            const matchesType =
                    selectedType === "ALL" || rowType === selectedType;

            const matchesStatus =
                    selectedStatus === "ALL" || rowStatus === selectedStatus;

            if (matchesSearch && matchesType && matchesStatus) {
                row.style.display = "";
                visibleCount++;
            } else {
                row.style.display = "none";
            }
        });

        if (maintenanceNoRecords) {
            maintenanceNoRecords.style.display = visibleCount === 0 ? "block" : "none";
        }
    }

    if (maintenanceSearch) {
        maintenanceSearch.addEventListener("input", applyMaintenanceFilters);
    }

    if (maintenanceTypeFilter) {
        maintenanceTypeFilter.addEventListener("change", applyMaintenanceFilters);
    }

    if (maintenanceStatusFilter) {
        maintenanceStatusFilter.addEventListener("change", applyMaintenanceFilters);
    }

    applyMaintenanceFilters();
    
    var sortDirections = [true, true, true, true, true, true, true, true, true];
    function sortTable(columnIndex) {
        var table = document.getElementById("maintenanceTable");
        if (!table) return;
        
        var tbody = table.querySelector("tbody");
        if (!tbody) return;
        
        var rows = Array.from(tbody.querySelectorAll("tr"));
        if (rows.length === 1 && rows[0].querySelector("td[colspan]")) return;

        var asc = sortDirections[columnIndex];
        sortDirections[columnIndex] = !asc;

        rows.sort(function(a, b) {
            var cellA = a.querySelectorAll("td")[columnIndex];
            var cellB = b.querySelectorAll("td")[columnIndex];

            if (!cellA || !cellB) return 0;
            
            var valA = cellA.innerText || cellA.textContent;
            var valB = cellB.innerText || cellB.textContent;
            
            valA = valA.trim().toLowerCase();
            valB = valB.trim().toLowerCase();
            
            if (valA < valB) return asc ? -1 : 1;
            if (valA > valB) return asc ? 1 : -1;
            return 0;
        });

        rows.forEach(function(row) {
            tbody.appendChild(row);
        });
        
        var headers = table.querySelectorAll("thead th");
        headers.forEach(function(th, idx) {
            var icon = th.querySelector("i.fa-sort, i.fa-sort-up, i.fa-sort-down");
            if (icon) {
                icon.className = "fa-solid fa-sort";
                if (idx === columnIndex) {
                    icon.className = asc ? "fa-solid fa-sort-up" : "fa-solid fa-sort-down";
                }
            }
        });
    }
</script>

<script src="js/topbar-search.js?v=final-reference-1"></script>
<script src="js/user-dropdown.js?v=final-reference-1"></script>
<script src="js/sidebar-role.js?v=final-reference-1"></script>
<script src="js/ir-body-watermark.js?v=final-reference-1"></script>
<script src="js/dashboard-actions.js?v=final-reference-1"></script>

</body>
</html>
