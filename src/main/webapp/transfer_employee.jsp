<%@page contentType="text/html" pageEncoding="UTF-8"%>
<%@ page import="java.sql.Connection" %>
<%@ page import="java.sql.PreparedStatement" %>
<%@ page import="java.sql.ResultSet" %>
<%@ page import="java.util.List" %>
<%@ page import="com.mycompany.asset_management_system_ams.DBConnection" %>
<%@ page import="com.mycompany.asset_management_system_ams.Employee" %>
<%@ page import="com.mycompany.asset_management_system_ams.EmployeeDAO" %>
<%@ page import="com.mycompany.asset_management_system_ams.AssetAllocation" %>
<%@ page import="com.mycompany.asset_management_system_ams.AssetAllocationDAO" %>
<%@ page import="com.mycompany.asset_management_system_ams.HtmlEscapeUtil" %>

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

    boolean canManageEmployees = ("SUPER_ADMIN".equals(role) || "ADMIN".equals(role))
            || "DEPARTMENT_HEAD".equalsIgnoreCase(role);

    if (!canManageEmployees) {
        response.sendRedirect("employees.jsp?access=denied");
        return;
    }

    int employeeId = 0;
    try {
        employeeId = Integer.parseInt(request.getParameter("id"));
    } catch (Exception e) {
        response.sendRedirect("employees.jsp?error=invalid");
        return;
    }

    EmployeeDAO employeeDAO = new EmployeeDAO();

    if ("DEPARTMENT_HEAD".equalsIgnoreCase(role)) {
        int userIdForScope = 0;
        try {
            Object uid = session.getAttribute("user_id");
            userIdForScope = uid == null ? 0 : Integer.parseInt(String.valueOf(uid));
        } catch (Exception e) {
            userIdForScope = 0;
        }

        if (!employeeDAO.isEmployeeUnderDepartmentHead(employeeId, userIdForScope)) {
            response.sendRedirect("employees.jsp?access=denied");
            return;
        }
    }

    Employee employee = employeeDAO.getEmployeeById(employeeId);

    if (employee == null) {
        response.sendRedirect("employees.jsp?error=invalid");
        return;
    }

    if (!"ACTIVE".equalsIgnoreCase(employee.getStatus())) {
        response.sendRedirect("view_employee.jsp?id=" + employeeId + "&error=nottransferable");
        return;
    }

    String error = request.getParameter("error");

    AssetAllocationDAO allocationDAO = new AssetAllocationDAO();
    List<AssetAllocation> allocations = allocationDAO.getAllocationsByEmployeeId(employeeId);

    // Fault: this used to be declared further down, inside the
    // if(allocations.isEmpty()) / else block around the allocation list
    // rendering. That block's closing scriptlet tag ends its scope well before
    // the page's own script section at the bottom reads it to build a JS array -
    // so Jasper could never resolve it there ("activeAllocationIdsJs cannot be
    // resolved"), 500-ing this page on every visit. Fix: declare it here at the
    // outer scriptlet scope (with "allocations" itself) so it survives to the
    // script block; the accumulation loop below still populates it.
    StringBuilder activeAllocationIdsJs = new StringBuilder();
%>

<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>IR-AMS Transfer Employee</title>

    <link rel="stylesheet"
          href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.0/css/all.min.css">

    <link rel="stylesheet" href="css/ir-glass.css?v=28000">
    <link rel="stylesheet" href="css/ams-pro.css?v=28000">
    <link rel="stylesheet" href="css/ir-ams-railway-ui.css?v=28000">
</head>

<body class="railway-ui">

<div class="app ams-shell">

    <jsp:include page="sidebar.jsp" />

    <main class="main railway-main">
        <jsp:include page="topbar.jsp" />

        <div class="main-scroll-content">

            <section class="add-employee-hero">
                <h1>Transfer Employee</h1>

                <p>
                    Move <strong><%= HtmlEscapeUtil.escape(employee.getEmployeeName()) %></strong>
                    (<%= HtmlEscapeUtil.escape(employee.getEmployeeCode()) %>) to a new department.
                    For each currently allocated asset, choose whether it travels with the employee
                    (Retain) or is returned to inventory (Return) before the transfer is completed.
                </p>
            </section>

            <section class="glass-panel">

                <h2>Transfer Details</h2>
                <br>

                <% if ("invaliddepartment".equals(error)) { %>
                    <div class="alert-error">Please select a valid, active destination department.</div>
                <% } else if ("samedepartment".equals(error)) { %>
                    <div class="alert-error">Destination department must be different from the current department.</div>
                <% } else if ("receivedbyrequired".equals(error)) { %>
                    <div class="alert-error">Please enter who is receiving the returned asset(s).</div>
                <% } else if ("returnfailed".equals(error)) { %>
                    <div class="alert-error">One of the selected assets could not be returned (it may already be returned elsewhere). Please review and try again.</div>
                <% } else if ("failed".equals(error)) { %>
                    <div class="alert-error">Transfer could not be completed. Please try again.</div>
                <% } else if ("server".equals(error)) { %>
                    <div class="alert-error">Server error occurred while processing the transfer.</div>
                <% } %>

                <form action="TransferEmployeeServlet" method="post" id="transferForm">
                    <input type="hidden" name="employeeId" value="<%= employee.getEmployeeId() %>">

                    <div class="form-grid">

                        <div class="form-group">
                            <label>Current Department</label>
                            <input type="text" value="<%= HtmlEscapeUtil.escape(employee.getDepartmentName(), "N/A") %>" disabled>
                        </div>

                        <div class="form-group">
                            <label>New Department</label>
                            <select name="newDepartmentId" required>
                                <option value="">Select New Department</option>

                                <%
                                    String deptSql = "SELECT department_id, department_name "
                                            + "FROM departments "
                                            + "WHERE status = 'ACTIVE' AND department_id <> ? "
                                            + "ORDER BY department_name ASC";

                                    try (Connection con = DBConnection.getConnection();
                                         PreparedStatement ps = con.prepareStatement(deptSql)) {
                                        ps.setInt(1, employee.getDepartmentId());

                                        try (ResultSet rs = ps.executeQuery()) {
                                            while (rs.next()) {
                                %>
                                                <option value="<%= rs.getInt("department_id") %>">
                                                    <%= HtmlEscapeUtil.escape(rs.getString("department_name")) %>
                                                </option>
                                <%
                                            }
                                        }
                                    } catch (Exception e) {
                                        e.printStackTrace();
                                    }
                                %>
                            </select>
                        </div>

                        <div class="form-group form-group-full">
                            <label>Transfer Remarks</label>
                            <input type="text" name="remarks"
                                   placeholder="Example: Transferred on administrative order dated ..."
                                   maxlength="255">
                        </div>

                    </div>

                    <br>

                    <h2>Currently Allocated Assets</h2>

                    <% if (allocations.isEmpty()) { %>
                        <p class="table-subtext">This employee currently has no asset allocation records at all.</p>
                    <% } else { %>

                        <%
                            boolean hasActiveAllocation = false;
                            for (AssetAllocation allocation : allocations) {
                                if (!"ALLOCATED".equalsIgnoreCase(allocation.getAllocationStatus())) {
                                    continue;
                                }
                                hasActiveAllocation = true;
                                if (activeAllocationIdsJs.length() > 0) {
                                    activeAllocationIdsJs.append(",");
                                }
                                activeAllocationIdsJs.append(allocation.getAllocationId());
                                String empPref = allocation.getEmployeeTransferPreference();
                                boolean empWantsReturn = "RETURN".equalsIgnoreCase(empPref);
                        %>
                            <div class="form-group form-group-full transfer-asset-row" style="border:1px solid #e2e8f0; border-radius:10px; padding:14px; margin-bottom:12px;">
                                <strong><%= HtmlEscapeUtil.escape(allocation.getAssetCode()) %></strong>
                                &middot; <%= HtmlEscapeUtil.escape(allocation.getAssetName()) %>
                                <span class="table-subtext">(ALLOC-<%= allocation.getAllocationId() %>, allocated <%= HtmlEscapeUtil.escape(allocation.getAllocationDate(), "N/A") %>)</span>

                                <% if (empPref != null && !empPref.trim().isEmpty()) { %>
                                    <div style="margin-top:6px;">
                                        <span style="display:inline-block; padding:3px 10px; border-radius:20px; font-size:12px; font-weight:600; background:#fef3c7; color:#92400e;">
                                            <i class="fa-solid fa-user"></i>
                                            Employee requested: <%= empWantsReturn ? "Return" : "Keep" %>
                                            <% if (allocation.getEmployeeTransferNote() != null && !allocation.getEmployeeTransferNote().trim().isEmpty()) { %>
                                                &mdash; "<%= HtmlEscapeUtil.escape(allocation.getEmployeeTransferNote()) %>"
                                            <% } %>
                                        </span>
                                        <span class="table-subtext">(pre-selected below - you can still override it)</span>
                                    </div>
                                <% } %>

                                <div style="margin-top:8px; display:flex; gap:20px; align-items:center; flex-wrap:wrap;">
                                    <label style="font-weight:normal;">
                                        <input type="radio" name="action_<%= allocation.getAllocationId() %>"
                                               value="retain" <%= empWantsReturn ? "" : "checked" %>
                                               onchange="toggleConditionField(<%= allocation.getAllocationId() %>)">
                                        Retain (stays with employee)
                                    </label>

                                    <label style="font-weight:normal;">
                                        <input type="radio" name="action_<%= allocation.getAllocationId() %>"
                                               value="return" <%= empWantsReturn ? "checked" : "" %>
                                               onchange="toggleConditionField(<%= allocation.getAllocationId() %>)">
                                        Return to inventory
                                    </label>

                                    <span id="conditionWrap_<%= allocation.getAllocationId() %>" style="display:none;">
                                        Condition:
                                        <select name="condition_<%= allocation.getAllocationId() %>">
                                            <option value="GOOD">GOOD</option>
                                            <option value="DAMAGED">DAMAGED</option>
                                            <option value="NEEDS_REPAIR">NEEDS_REPAIR</option>
                                        </select>
                                    </span>
                                </div>
                            </div>
                        <%
                            }

                            if (!hasActiveAllocation) {
                        %>
                            <p class="table-subtext">This employee has no currently active (ALLOCATED) assets.</p>
                        <%
                            } else {
                        %>
                            <div class="form-group form-group-full">
                                <label>Received By (required if returning any asset)</label>
                                <input type="text" name="receivedBy" id="receivedByField"
                                       placeholder="Example: Store Officer">
                            </div>
                        <%
                            }
                        %>
                    <% } %>

                    <div class="form-actions">
                        <button type="submit" class="btn" onclick="return confirm('Complete this employee transfer?');">
                            <i class="fa-solid fa-right-left"></i> Complete Transfer
                        </button>

                        <a href="view_employee.jsp?id=<%= employee.getEmployeeId() %>" class="btn secondary-btn">
                            <i class="fa-solid fa-arrow-left"></i> Cancel
                        </a>
                    </div>

                </form>

            </section>

        </div>
    </main>

</div>

<script>
    function toggleConditionField(allocationId) {
        var wrap = document.getElementById("conditionWrap_" + allocationId);
        var returnRadio = document.querySelector('input[name="action_' + allocationId + '"][value="return"]');
        if (!wrap || !returnRadio) return;
        wrap.style.display = returnRadio.checked ? "inline" : "none";
    }

    // Reveal the Condition dropdown on load for any asset the employee's
    // submitted preference (or a pre-checked "return" radio) already implies
    // Return - without this, the dropdown would stay hidden until the admin
    // manually clicked the radio again.
    (function () {
        var activeAllocationIds = [<%= activeAllocationIdsJs.toString() %>];
        activeAllocationIds.forEach(function (id) {
            toggleConditionField(id);
        });
    })();
</script>

<script src="js/topbar-search.js?v=28000"></script>
<script src="js/user-dropdown.js?v=28000"></script>
<script src="js/sidebar-role.js?v=28000"></script>
<script src="js/ir-body-watermark.js?v=28000"></script>
<script src="js/dashboard-actions.js?v=28000"></script>

</body>
</html>
