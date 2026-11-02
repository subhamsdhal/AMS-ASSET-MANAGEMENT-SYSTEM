<%@page contentType="text/html" pageEncoding="UTF-8"%>
<%@page import="com.mycompany.asset_management_system_ams.Employee"%>
<%@page import="com.mycompany.asset_management_system_ams.EmployeeDAO"%>
<%@page import="com.mycompany.asset_management_system_ams.DBConnection"%>
<%@page import="java.sql.Connection"%>
<%@page import="java.sql.PreparedStatement"%>
<%@page import="java.sql.ResultSet"%>
<%@page import="java.util.List"%>
<%@page import="java.util.ArrayList"%>
<%@page import="java.util.Set"%>
<%@page import="java.util.TreeSet"%>
<%@page import="java.util.Locale"%>
<%@page import="java.text.NumberFormat"%>
<%@page import="java.util.Map"%>
<%@page import="com.mycompany.asset_management_system_ams.RoleAssignmentDAO"%>

<%!
    private String safeText(String value) {
        if (value == null || value.trim().isEmpty()) {
            return "N/A";
        }

        return value.trim()
                .replace("&", "&amp;")
                .replace("<", "&lt;")
                .replace(">", "&gt;")
                .replace("\"", "&quot;")
                .replace("'", "&#39;");
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

    private String shortText(String value, int max) {
        if (value == null || value.trim().isEmpty()) {
            return "N/A";
        }

        String text = value.trim();

        if (text.length() <= max) {
            return text;
        }

        return text.substring(0, max) + "...";
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

    private double percent(long part, long total) {
        if (total <= 0) {
            return 0.0;
        }

        return (part * 100.0) / total;
    }

    private String decimalOne(double value) {
        return String.format(Locale.ENGLISH, "%.1f", value);
    }

    private String fullName(Employee emp) {
        if (emp == null || emp.getEmployeeName() == null || emp.getEmployeeName().trim().isEmpty()) {
            return "N/A";
        }

        return emp.getEmployeeName().trim();
    }

    private String initials(String value) {
        if (value == null || value.trim().isEmpty()) {
            return "IR";
        }

        String[] parts = value.trim().split("\\s+");
        StringBuilder out = new StringBuilder();

        for (String part : parts) {
            if (part.length() > 0 && out.length() < 2) {
                out.append(Character.toUpperCase(part.charAt(0)));
            }
        }

        if (out.length() == 0) {
            return "IR";
        }

        return out.toString();
    }

    private String statusClass(String status) {
        if (status == null) {
            return "neutral";
        }

        String text = status.trim().toUpperCase(Locale.ENGLISH);

        if ("ACTIVE".equals(text)) {
            return "success";
        }

        if ("INACTIVE".equals(text) || "DISABLED".equals(text) || "SUSPENDED".equals(text)) {
            return "danger";
        }

        return "neutral";
    }

    private String safeDepartment(Employee emp) {
        if (emp == null || emp.getDepartmentName() == null || emp.getDepartmentName().trim().isEmpty()) {
            return "Unassigned";
        }

        return emp.getDepartmentName().trim();
    }

    private String safeStatus(Employee emp) {
        if (emp == null || emp.getStatus() == null || emp.getStatus().trim().isEmpty()) {
            return "ACTIVE";
        }

        return emp.getStatus().trim();
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

    int userId = 0;

    try {
        Object userIdObj = session.getAttribute("user_id");

        if (userIdObj == null) {
            userIdObj = session.getAttribute("userId");
        }

        if (userIdObj != null) {
            userId = Integer.parseInt(String.valueOf(userIdObj));
        }
    } catch (Exception e) {
        userId = 0;
    }

    boolean isSuperAdmin = ("SUPER_ADMIN".equals(role) || "ADMIN".equals(role));
    boolean isDepartmentHead = "DEPARTMENT_HEAD".equalsIgnoreCase(role);

    boolean canManageEmployees = isSuperAdmin || isDepartmentHead;

    Set<String> managedDepartmentSet = new TreeSet<>();

    if (isDepartmentHead && userId > 0) {
        String deptSql = "SELECT department_name FROM departments WHERE department_head_user_id = ?";
        try (Connection deptCon = DBConnection.getConnection();
             PreparedStatement deptPs = deptCon.prepareStatement(deptSql)) {
            
            deptPs.setInt(1, userId);
            try (ResultSet deptRs = deptPs.executeQuery()) {
                while (deptRs.next()) {
                    String departmentName = deptRs.getString("department_name");
                    if (departmentName != null && !departmentName.trim().isEmpty()) {
                        managedDepartmentSet.add(departmentName.trim());
                    }
                }
            }
        } catch (Exception e) {
            e.printStackTrace();
        }
    }

    EmployeeDAO dao = new EmployeeDAO();
    List<Employee> employeeList = dao.getAllEmployees();

    if (employeeList == null) {
        employeeList = new ArrayList<Employee>();
    }

    Map<Integer, String> roleSummaryMap = RoleAssignmentDAO.getActiveDutySummaryForEmployees();
    List<Employee> visibleEmployeeList = new ArrayList<Employee>();

    for (Employee emp : employeeList) {
        if (isDepartmentHead) {
            if (emp.getDepartmentName() != null && managedDepartmentSet.contains(emp.getDepartmentName().trim())) {
                visibleEmployeeList.add(emp);
            }
        } else {
            visibleEmployeeList.add(emp);
        }
    }

    String msg = request.getParameter("msg");
    String error = request.getParameter("error");

    // Fault: this read session keys ("new_emp_user"/"new_emp_pass") that
    // AddEmployeeServlet never actually set (it sets "last_created_username"/
    // "last_created_password") - so the "Account Created" credentials popup
    // below could never render under any circumstance; an admin creating an
    // employee with a login had no way to see the generated username/
    // password (e.g. if the welcome email failed to send, or SMTP isn't
    // configured) short of querying the database directly.
    String newEmpUser = (String) session.getAttribute("last_created_username");
    String newEmpPass = (String) session.getAttribute("last_created_password");
    session.removeAttribute("last_created_emp_code");
    session.removeAttribute("last_created_username");
    session.removeAttribute("last_created_password");
    session.removeAttribute("last_created_emp_name");

    int totalEmployees = visibleEmployeeList.size();
    int activeEmployees = 0;
    int inactiveEmployees = 0;
    int totalAssignedAssets = 0;
    int employeesWithAssets = 0;

    Set<String> departmentSet = new TreeSet<>();

    for (Employee emp : visibleEmployeeList) {
        String status = safeStatus(emp);

        if ("ACTIVE".equalsIgnoreCase(status)) {
            activeEmployees++;
        } else {
            inactiveEmployees++;
        }

        int assignedCount = emp.getAssignedAssetCount();

        if (assignedCount > 0) {
            employeesWithAssets++;
        }

        totalAssignedAssets += assignedCount;

        if (emp.getDepartmentName() != null && !emp.getDepartmentName().trim().isEmpty()) {
            departmentSet.add(emp.getDepartmentName().trim());
        }
    }

    String userInitial = username.substring(0, Math.min(2, username.length())).toUpperCase(Locale.ENGLISH);
%>

<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>Employees - IR-AMS</title>

    <link rel="stylesheet"
          href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.0/css/all.min.css">

    <link rel="stylesheet" href="css/ir-glass.css?v=28000">
    <link rel="stylesheet" href="css/ams-pro.css?v=28000">
    <link rel="stylesheet" href="css/ir-ams-railway-ui.css?v=28000">

    <link rel="stylesheet" href="css/employees.css?v=28001">
    </head>

<body class="railway-ui">
<div class="app ams-shell">

    <jsp:include page="sidebar.jsp" />

    <main class="main railway-main">
        <jsp:include page="topbar.jsp" />

        <div class="main-scroll-content">
            <div class="employee-board">

                <section class="employee-hero">
                    <div class="employee-hero-copy">
                        <span class="employee-eyebrow">
                            <i class="fa-solid fa-users"></i>
                            Employees Module · East Coast Railway
                        </span>

                        <h1>Railway Employee Directory</h1>

                        <p>
                            Manage railway employee profiles, departments, designations, contact information,
                            active status and assigned asset responsibility from one secure employee control module.
                        </p>

                        <div class="employee-hero-pills">
                            <div class="employee-hero-pill"><i class="fa-solid fa-users"></i> Employee Directory</div>
                            <div class="employee-hero-pill"><i class="fa-solid fa-building"></i> Department Mapping</div>
                            <div class="employee-hero-pill"><i class="fa-solid fa-id-card"></i> Employee Identity</div>
                            <div class="employee-hero-pill"><i class="fa-solid fa-cubes"></i> Assigned Assets</div>
                        </div>
                    </div>
                </section>

                <% if ("denied".equals(request.getParameter("access"))) { %>
                    <div class="employee-message error">
                        <i class="fa-solid fa-triangle-exclamation"></i>
                        Access denied. You do not have permission to manage employees.
                    </div>
                <% } %>

                <% if ("added".equals(msg)) { %>
                    <div class="employee-message success">
                        <i class="fa-solid fa-circle-check"></i>
                        Employee record added successfully.
                    </div>
                <% } else if ("added_with_login".equals(msg)) { %>
                    <div class="employee-message success">
                        <i class="fa-solid fa-circle-check"></i>
                        Employee record and login account created successfully.
                    </div>
                <% } else if ("added_doc_failed".equals(msg)) { %>
                    <div class="employee-message error" style="background: #fff3cd; color: #856404; border-color: #ffeeba;">
                        <i class="fa-solid fa-triangle-exclamation"></i>
                        Employee created successfully, but document upload failed: invalid file type/size.
                    </div>
                <% } else if ("added_with_login_doc_failed".equals(msg)) { %>
                    <div class="employee-message error" style="background: #fff3cd; color: #856404; border-color: #ffeeba;">
                        <i class="fa-solid fa-triangle-exclamation"></i>
                        Employee & login created successfully, but document upload failed: invalid file type/size.
                    </div>
                <% } else if ("updated".equals(msg)) { %>
                    <div class="employee-message success">
                        <i class="fa-solid fa-circle-check"></i>
                        Employee record updated successfully.
                    </div>
                <% } else if ("disabled".equals(msg)) { %>
                    <div class="employee-message success">
                        <i class="fa-solid fa-circle-check"></i>
                        Employee record deactivated successfully.
                    </div>
                <% } else if ("deleted".equals(msg)) { %>
                    <div class="employee-message success">
                        <i class="fa-solid fa-circle-check"></i>
                        Employee removed from active directory successfully.
                    </div>
                <% } else if ("alreadyinactive".equals(msg)) { %>
                    <div class="employee-message success">
                        <i class="fa-solid fa-circle-info"></i>
                        Employee record is already inactive.
                    </div>
                <% } %>

                <%-- Fault: every error code below (deleteblocked/deletefailed/
                     deleteinvalid/deleteunauthorized/deletewrongdept/disablefailed/
                     invalid/server) fell through to a single generic fallback that
                     printed the raw internal code verbatim ("Error code:
                     deletewrongdept") - technically not silent, but not a real
                     explanation either. Each of these already has a clear, specific
                     reason recorded in the audit log by the servlet that sent it;
                     surfaced the same reasons here instead of the raw code. The
                     generic fallback stays as a safety net for anything unexpected. --%>
                <% if ("deleteblocked".equals(error)) { %>
                    <div class="employee-message error" style="background: #fff3cd; color: #856404; border-color: #ffeeba;">
                        <i class="fa-solid fa-triangle-exclamation"></i>
                        This employee cannot be deleted yet - they are still Active, have active asset allocations, or have pending/approved asset requests. Deactivate them and close out those records first.
                    </div>
                <% } else if ("deletefailed".equals(error)) { %>
                    <div class="employee-message error">
                        <i class="fa-solid fa-triangle-exclamation"></i>
                        Employee could not be removed from the directory. Please try again.
                    </div>
                <% } else if ("deleteinvalid".equals(error)) { %>
                    <div class="employee-message error">
                        <i class="fa-solid fa-triangle-exclamation"></i>
                        Employee record could not be found. It may have already been removed.
                    </div>
                <% } else if ("deleteunauthorized".equals(error)) { %>
                    <div class="employee-message error">
                        <i class="fa-solid fa-triangle-exclamation"></i>
                        You do not have permission to delete employee records.
                    </div>
                <% } else if ("deletewrongdept".equals(error)) { %>
                    <div class="employee-message error">
                        <i class="fa-solid fa-triangle-exclamation"></i>
                        You can only delete employees within your own department.
                    </div>
                <% } else if ("disablefailed".equals(error)) { %>
                    <div class="employee-message error">
                        <i class="fa-solid fa-triangle-exclamation"></i>
                        Employee could not be deactivated. Please try again.
                    </div>
                <% } else if ("invalid".equals(error)) { %>
                    <div class="employee-message error">
                        <i class="fa-solid fa-triangle-exclamation"></i>
                        Employee record could not be found.
                    </div>
                <% } else if ("server".equals(error)) { %>
                    <div class="employee-message error">
                        <i class="fa-solid fa-triangle-exclamation"></i>
                        A server error occurred. Please try again.
                    </div>
                <% } else if (error != null && !error.trim().isEmpty()) { %>
                    <div class="employee-message error">
                        <i class="fa-solid fa-triangle-exclamation"></i>
                        Operation could not be completed. Error code: <%= safeText(error) %>
                    </div>
                <% } %>

                <section class="employee-kpi-grid">
                    <a href="employees.jsp" class="employee-kpi-card">
                        <div class="employee-kpi-icon">
                            <i class="fa-solid fa-users"></i>
                        </div>
                        <h3>Total Employees</h3>
                        <p><%= indianNumber(totalEmployees) %></p>
                        <span><i class="fa-solid fa-arrow-up"></i> Live records</span>
                    </a>

                    <a href="employees.jsp?status=ACTIVE" class="employee-kpi-card">
                        <div class="employee-kpi-icon green">
                            <i class="fa-solid fa-user-check"></i>
                        </div>
                        <h3>Active Employees</h3>
                        <p><%= indianNumber(activeEmployees) %></p>
                        <span><i class="fa-solid fa-arrow-up"></i> <%= decimalOne(percent(activeEmployees, Math.max(totalEmployees, 1))) %>% active</span>
                    </a>

                    <a href="employees.jsp?status=INACTIVE" class="employee-kpi-card">
                        <div class="employee-kpi-icon red">
                            <i class="fa-solid fa-user-xmark"></i>
                        </div>
                        <h3>Inactive</h3>
                        <p><%= indianNumber(inactiveEmployees) %></p>
                        <span><i class="fa-solid fa-arrow-up"></i> <%= decimalOne(percent(inactiveEmployees, Math.max(totalEmployees, 1))) %>% inactive</span>
                    </a>

                    <a href="categories.jsp" class="employee-kpi-card">
                        <div class="employee-kpi-icon orange">
                            <i class="fa-solid fa-building"></i>
                        </div>
                        <h3>Departments</h3>
                        <p><%= indianNumber(departmentSet.size()) %></p>
                        <span><i class="fa-solid fa-arrow-up"></i> mapped units</span>
                    </a>

                    <a href="allocation.jsp" class="employee-kpi-card">
                        <div class="employee-kpi-icon purple">
                            <i class="fa-solid fa-cubes"></i>
                        </div>
                        <h3>Assigned Assets</h3>
                        <p><%= indianNumber(totalAssignedAssets) %></p>
                        <span><i class="fa-solid fa-arrow-up"></i> active allocations</span>
                    </a>

                    <a href="allocation.jsp" class="employee-kpi-card">
                        <div class="employee-kpi-icon">
                            <i class="fa-solid fa-user-shield"></i>
                        </div>
                        <h3>Employees With Assets</h3>
                        <p><%= indianNumber(employeesWithAssets) %></p>
                        <span><i class="fa-solid fa-arrow-up"></i> assigned users</span>
                    </a>
                </section>

                <section class="employee-control-panel">
                    <div class="employee-panel-head">
                        <div>
                            <h2>Employee Control Table</h2>
                            <p>
                                Showing <strong id="visibleEmployeeCount"><%= indianNumber(totalEmployees) %></strong>
                                live employee records from railway database.
                            </p>
                        </div>

                        <div class="employee-toolbar">
                            <% if (canManageEmployees) { %>
                                <a href="add_employee.jsp" class="employee-btn primary">
                                    <i class="fa-solid fa-plus"></i>
                                    Add Employee
                                </a>
                            <% } else { %>
                                <a href="#" class="employee-btn primary disabled">
                                    <i class="fa-solid fa-lock"></i>
                                    Add Employee
                                </a>
                            <% } %>

                            <% if (canManageEmployees) { %>
                                <a href="user_profile_requests.jsp" class="employee-btn">
                                    <i class="fa-solid fa-user-pen"></i>
                                    Profile Change Requests
                                </a>
                            <% } %>

                            <a href="export_employee_report.jsp" class="employee-btn green">
                                <i class="fa-solid fa-file-excel"></i>
                                Export Excel
                            </a>

                            <button type="button" class="employee-btn" onclick="window.print();">
                                <i class="fa-solid fa-print"></i>
                                Print
                            </button>

                            <button type="button" class="employee-btn" id="resetEmployeeFilters">
                                <i class="fa-solid fa-rotate-right"></i>
                                Reset
                            </button>
                        </div>
                    </div>

                    <div class="employee-filter-grid">
                        <div class="employee-search-wrap">
                            <i class="fa-solid fa-magnifying-glass"></i>
                            <input type="text"
                                   id="employeeSearch"
                                   class="employee-search-control"
                                   placeholder="Search employee name, code, department, designation, email, phone...">
                        </div>

                        <select id="employeeStatusFilter" class="employee-select-control">
                            <option value="ALL">All Status</option>
                            <option value="ACTIVE">Active Only</option>
                            <option value="INACTIVE">Inactive Only</option>
                        </select>

                        <select id="employeeDepartmentFilter" class="employee-select-control">
                            <option value="ALL">All Departments</option>
                            <%
                                for (String departmentName : departmentSet) {
                            %>
                                <option value="<%= safeText(departmentName) %>"><%= safeText(departmentName) %></option>
                            <%
                                }
                            %>
                        </select>

                        <button type="button" id="employeeAssignedFilter" class="employee-btn">
                            <i class="fa-solid fa-cubes"></i>
                            With Assets
                        </button>
                    </div>

                    <div class="employee-no-records" id="employeeNoRecords">
                        <i class="fa-solid fa-magnifying-glass"></i>
                        No employee records matched your current search or filter.
                    </div>

                    <div class="employee-table-wrap">
                        <table class="employee-table" id="employeeTable">
                            <colgroup>
                                <col style="width: 18%;">
                                <col style="width: 16%;">
                                <col style="width: 15%;">
                                <col style="width: 15%;">
                                <col style="width: 9%;">
                                <col style="width: 8%;">
                                <col style="width: 8%;">
                                <col style="width: 11%;">
                            </colgroup>
                            <thead>
                                <tr>
                                    <th onclick="sortTable(0)" style="cursor: pointer;" title="Click to sort">Employee <i class="fa-solid fa-sort" style="color: #cbd5e1; margin-left: 4px;"></i></th>
                                    <th onclick="sortTable(1)" style="cursor: pointer;" title="Click to sort">Contact <i class="fa-solid fa-sort" style="color: #cbd5e1; margin-left: 4px;"></i></th>
                                    <th onclick="sortTable(2)" style="cursor: pointer;" title="Click to sort">Department <i class="fa-solid fa-sort" style="color: #cbd5e1; margin-left: 4px;"></i></th>
                                    <th onclick="sortTable(3)" style="cursor: pointer;" title="Click to sort">Designation <i class="fa-solid fa-sort" style="color: #cbd5e1; margin-left: 4px;"></i></th>
                                    <th onclick="sortTable(4)" style="cursor: pointer;" title="Click to sort">Joining Date <i class="fa-solid fa-sort" style="color: #cbd5e1; margin-left: 4px;"></i></th>
                                    <th onclick="sortTable(5)" style="cursor: pointer;" title="Click to sort">Status <i class="fa-solid fa-sort" style="color: #cbd5e1; margin-left: 4px;"></i></th>
                                    <th onclick="sortTable(6)" style="cursor: pointer;" title="Click to sort">Assigned Assets <i class="fa-solid fa-sort" style="color: #cbd5e1; margin-left: 4px;"></i></th>
                                    <th>Control Actions</th>
                                </tr>
                            </thead>

                            <tbody>
                                <%
                                    for (Employee emp : visibleEmployeeList) {
                                        String employeeName = fullName(emp);
                                        String employeeCode = emp.getEmployeeCode();
                                        String departmentName = safeDepartment(emp);
                                        String employeeStatus = safeStatus(emp);
                                        String rowSearchText = (
                                                employeeName + " "
                                                + employeeCode + " "
                                                + emp.getEmail() + " "
                                                + emp.getPhone() + " "
                                                + departmentName + " "
                                                + emp.getDesignation() + " "
                                                + employeeStatus
                                        ).toLowerCase(Locale.ENGLISH);
                                %>
                                    <tr class="employee-row"
                                        data-search="<%= safeText(rowSearchText) %>"
                                        data-status="<%= safeText(employeeStatus.toUpperCase(Locale.ENGLISH)) %>"
                                        data-department="<%= safeText(departmentName) %>"
                                        data-assigned="<%= emp.getAssignedAssetCount() %>">

                                        <td>
                                            <div class="employee-identity">
                                                <div class="employee-avatar">
                                                    <% if (emp.getProfileImagePath() != null && !emp.getProfileImagePath().trim().isEmpty()) { %>
                                                        <img src="<%= safeText(request.getContextPath() + "/" + emp.getProfileImagePath()) %>" class="employee-avatar-img" alt="Profile">
                                                    <% } else { %>
                                                        <%= safeText(initials(employeeName)) %>
                                                    <% } %>
                                                </div>
                                                <div>
                                                    <strong><%= safeText(shortText(employeeName, 28)) %></strong>
                                                    <span><%= safeText(employeeCode) %></span>
                                                </div>
                                            </div>
                                        </td>

                                        <td>
                                            <span class="employee-main-text"><%= safeText(shortText(emp.getEmail(), 30)) %></span>
                                            <span class="employee-sub-text"><%= safeText(emp.getPhone()) %></span>
                                        </td>

                                        <td>
                                            <span class="employee-main-text"><%= safeText(shortText(departmentName, 28)) %></span>
                                            <span class="employee-sub-text">Railway department</span>
                                        </td>

                                        <td>
                                            <% 
                                                String roleSummary = "Employee";
                                                if (roleSummaryMap != null && roleSummaryMap.containsKey(emp.getEmployeeId())) {
                                                    roleSummary = roleSummaryMap.get(emp.getEmployeeId());
                                                }
                                            %>
                                            <span class="employee-main-text"><%= safeText(shortText(emp.getDesignation(), 28)) %></span>
                                            <span class="employee-sub-text"><%= safeText(roleSummary) %></span>
                                        </td>

                                        <td>
                                            <span class="employee-main-text"><%= safeText(emp.getJoiningDate()) %></span>
                                            <span class="employee-sub-text">Joining date</span>
                                        </td>

                                        <td>
                                            <span class="employee-status <%= statusClass(employeeStatus) %>">
                                                <%= safeText(cleanLabel(employeeStatus)) %>
                                            </span>
                                        </td>

                                        <td>
                                            <span class="assigned-pill <%= emp.getAssignedAssetCount() > 0 ? "green" : "" %>">
                                                <i class="fa-solid fa-cubes"></i>
                                                <span><%= indianNumber(emp.getAssignedAssetCount()) %></span>
                                            </span>
                                        </td>

                                        <td>
                                            <div class="employee-action-grid">
                                                <a href="view_employee.jsp?id=<%= emp.getEmployeeId() %>"
                                                   class="employee-action-btn" title="View employee details">
                                                    <i class="fa-solid fa-eye"></i> View
                                                </a>

                                                <% if (canManageEmployees) { %>
                                                    <a href="edit_employee.jsp?id=<%= emp.getEmployeeId() %>"
                                                       class="employee-action-btn orange" title="Edit employee record">
                                                        <i class="fa-solid fa-pen-to-square"></i> Edit
                                                    </a>

                                                    <% if ("ACTIVE".equalsIgnoreCase(employeeStatus)) { %>
                                                        <a href="transfer_employee.jsp?id=<%= emp.getEmployeeId() %>"
                                                           class="employee-action-btn" title="Transfer to a new department">
                                                            <i class="fa-solid fa-right-left"></i> Transfer
                                                        </a>

                                                        <a href="retire_employee.jsp?id=<%= emp.getEmployeeId() %>"
                                                           class="employee-action-btn" title="Mark as retired">
                                                            <i class="fa-solid fa-user-clock"></i> Retire
                                                        </a>

                                                        <form action="DisableEmployeeServlet" method="post" style="display:inline;" onsubmit="return confirm('Deactivate this employee record?');">
                                                            <input type="hidden" name="id" value="<%= emp.getEmployeeId() %>">
                                                            <button type="submit" class="employee-action-btn red" style="border:none; cursor:pointer;" title="Deactivate this employee">
                                                                <i class="fa-solid fa-user-slash"></i> Disable
                                                            </button>
                                                        </form>
                                                    <% } else { %>
                                                        <span class="employee-action-btn" title="Employee is currently inactive">
                                                            <i class="fa-solid fa-circle-info"></i> Inactive
                                                        </span>
                                                    <% } %>

                                                    <form action="DeleteEmployeeServlet" method="post" style="display:inline;" onsubmit="return confirm('Remove this employee from active directory? This will be blocked if linked records exist.');">
                                                        <input type="hidden" name="id" value="<%= emp.getEmployeeId() %>">
                                                        <button type="submit" class="employee-action-btn red" style="border:none; cursor:pointer;" title="Remove employee from directory">
                                                            <i class="fa-solid fa-trash"></i> Remove
                                                        </button>
                                                    </form>
                                                <% } else { %>
                                                    <span class="employee-action-btn" title="You do not have permission to modify">
                                                        <i class="fa-solid fa-lock"></i> Locked
                                                    </span>
                                                <% } %>
                                            </div>
                                        </td>
                                    </tr>
                                <%
                                    }
                                %>
                            </tbody>
                        </table>
                    </div>
                </section>
            </div>
        </div>
    </main>
</div>

<script>
    (function () {
        "use strict";

        const employeeSearch = document.getElementById("employeeSearch");
        const employeeStatusFilter = document.getElementById("employeeStatusFilter");
        const employeeDepartmentFilter = document.getElementById("employeeDepartmentFilter");
        const employeeAssignedFilter = document.getElementById("employeeAssignedFilter");
        const employeeNoRecords = document.getElementById("employeeNoRecords");
        const visibleEmployeeCount = document.getElementById("visibleEmployeeCount");
        const rows = Array.prototype.slice.call(document.querySelectorAll(".employee-row"));

        let assignedOnly = false;

        function normalizeText(value) {
            if (!value) {
                return "";
            }

            return value.toString().replace(/\s+/g, " ").trim().toLowerCase();
        }

        function applyFilters() {
            const searchValue = normalizeText(employeeSearch ? employeeSearch.value : "");
            const selectedStatus = employeeStatusFilter ? employeeStatusFilter.value : "ALL";
            const selectedDepartment = employeeDepartmentFilter ? employeeDepartmentFilter.value : "ALL";

            let visibleCount = 0;

            rows.forEach(function (row) {
                const rowSearch = normalizeText(row.getAttribute("data-search"));
                const rowStatus = row.getAttribute("data-status") || "";
                const rowDepartment = row.getAttribute("data-department") || "";
                const assignedCount = parseInt(row.getAttribute("data-assigned") || "0", 10);

                const matchesSearch = searchValue === "" || rowSearch.indexOf(searchValue) !== -1;
                const matchesStatus = selectedStatus === "ALL" || rowStatus === selectedStatus;
                const matchesDepartment = selectedDepartment === "ALL" || rowDepartment === selectedDepartment;
                const matchesAssigned = !assignedOnly || assignedCount > 0;

                if (matchesSearch && matchesStatus && matchesDepartment && matchesAssigned) {
                    row.style.display = "";
                    visibleCount++;
                } else {
                    row.style.display = "none";
                }
            });

            if (employeeNoRecords) {
                employeeNoRecords.style.display = visibleCount === 0 ? "block" : "none";
            }

            if (visibleEmployeeCount) {
                visibleEmployeeCount.textContent = visibleCount;
            }

            if (employeeAssignedFilter) {
                if (assignedOnly) {
                    employeeAssignedFilter.classList.add("green");
                } else {
                    employeeAssignedFilter.classList.remove("green");
                }
            }
        }

        if (employeeSearch) {
            employeeSearch.addEventListener("input", applyFilters);
        }

        if (employeeStatusFilter) {
            employeeStatusFilter.addEventListener("change", applyFilters);
        }

        if (employeeDepartmentFilter) {
            employeeDepartmentFilter.addEventListener("change", applyFilters);
        }

        if (employeeAssignedFilter) {
            employeeAssignedFilter.addEventListener("click", function () {
                assignedOnly = !assignedOnly;
                applyFilters();
            });
        }

        const resetButton = document.getElementById("resetEmployeeFilters");

        if (resetButton) {
            resetButton.addEventListener("click", function () {
                assignedOnly = false;

                if (employeeSearch) {
                    employeeSearch.value = "";
                }

                if (employeeStatusFilter) {
                    employeeStatusFilter.value = "ALL";
                }

                if (employeeDepartmentFilter) {
                    employeeDepartmentFilter.value = "ALL";
                }

                applyFilters();
            });
        }

        applyFilters();
    })();
    
    var sortDirections = [true, true, true, true, true, true, true];
    function sortTable(columnIndex) {
        var table = document.getElementById("employeeTable");
        if (!table) return;
        
        var tbody = table.querySelector("tbody");
        if (!tbody) return;
        
        var rows = Array.from(tbody.querySelectorAll("tr.employee-row"));
        if (rows.length === 0) return;

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

<script src="js/topbar-search.js?v=employees-assets-match-clean-1"></script>
<script src="js/user-dropdown.js?v=employees-assets-match-clean-1"></script>
<script src="js/sidebar-role.js?v=employees-assets-match-clean-1"></script>
<script src="js/ir-body-watermark.js?v=employees-assets-match-clean-1"></script>
<script src="js/dashboard-actions.js?v=employees-assets-match-clean-1"></script>

<% if (newEmpUser != null && newEmpPass != null) { %>
    <div id="newEmpCredModal" style="position:fixed; top:0; left:0; width:100%; height:100%; background:rgba(0,0,0,0.5); display:flex; align-items:center; justify-content:center; z-index:9999;">
        <div style="background:#fff; padding:30px; border-radius:12px; max-width:450px; width:90%; box-shadow:0 10px 30px rgba(0,0,0,0.2); position:relative; border-top:5px solid var(--ir-blue);">
            <div style="display:flex; justify-content:space-between; align-items:center; margin-bottom:15px;">
                <h3 style="margin:0; color:var(--ir-blue); font-size:20px;"><i class="fa-solid fa-envelope-circle-check"></i> Account Created</h3>
                <button onclick="document.getElementById('newEmpCredModal').style.display='none'" style="background:none; border:none; font-size:20px; cursor:pointer; color:#999;">&times;</button>
            </div>
            <p style="margin:0 0 15px 0; color:#444; font-size:14px; line-height:1.5;">An system login account was successfully created. The credentials have been sent via email to the employee.</p>
            <div style="background:#f4f7fb; border:1px solid #c9d8eb; border-radius:8px; padding:15px; margin-bottom:20px;">
                <div style="margin-bottom:10px;"><strong style="color:var(--ir-blue);">Username (Email):</strong> <span style="user-select:all; background:#fff; padding:2px 6px; border-radius:4px; border:1px solid #ddd; font-family:monospace; color:#333;"><%= safeText(newEmpUser) %></span></div>
                <div><strong style="color:var(--ir-blue);">Temporary Password:</strong> <span style="user-select:all; background:#fff; padding:2px 6px; border-radius:4px; border:1px solid #ddd; font-family:monospace; color:#333;"><%= safeText(newEmpPass) %></span></div>
            </div>
            <div style="text-align:right;">
                <button onclick="document.getElementById('newEmpCredModal').style.display='none'" style="background:var(--ir-blue); color:white; border:none; padding:10px 20px; border-radius:8px; cursor:pointer; font-weight:bold;">Close</button>
            </div>
        </div>
    </div>
<% } %>

</body>
</html>