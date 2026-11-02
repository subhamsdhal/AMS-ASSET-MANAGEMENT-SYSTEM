<%@page contentType="text/html" pageEncoding="UTF-8"%>
<%@ page import="java.sql.*" %>
<%@ page import="java.util.*" %>
<%@ page import="com.mycompany.asset_management_system_ams.DBConnection" %>
<%@ page import="com.mycompany.asset_management_system_ams.RoleAssignmentDAO" %>
<%@ page import="com.mycompany.asset_management_system_ams.HtmlEscapeUtil" %>

<%!
    private int safeSessionInt(jakarta.servlet.http.HttpSession session, String key, int fallback) {
        try {
            Object value = session.getAttribute(key);
            return value == null ? fallback : Integer.parseInt(String.valueOf(value));
        } catch (Exception e) {
            return fallback;
        }
    }
%>

<%
    String username = (String) session.getAttribute("username");
    String role = (String) session.getAttribute("role");

    if (username == null || role == null) {
        response.sendRedirect("login.jsp");
        return;
    }

    if (!("DEPARTMENT_HEAD".equals(role) || "ADMIN".equals(role))) {
        response.sendRedirect("dashboard.jsp?error=unauthorized");
        return;
    }

    String msg = request.getParameter("msg");
    String error = request.getParameter("error");

    Integer departmentIdScope = null;
    if ("DEPARTMENT_HEAD".equals(role)) {
        // Was a raw (Integer) cast with no fallback - see the matching fix note
        // in RoleAssignmentServlet.java.
        int userId = safeSessionInt(session, "user_id", 0);
        com.mycompany.asset_management_system_ams.EmployeeDAO empDao = new com.mycompany.asset_management_system_ams.EmployeeDAO();
        int empId = empDao.getEmployeeIdByUserId(userId);
        if (empId > 0) {
            com.mycompany.asset_management_system_ams.Employee emp = empDao.getEmployeeById(empId);
            if (emp != null) {
                departmentIdScope = emp.getDepartmentId();
            }
        }
    }

    List<Map<String, Object>> activeAssignments = RoleAssignmentDAO.getActiveAssignments(departmentIdScope);
    List<Map<String, Object>> assignmentHistory = RoleAssignmentDAO.getAssignmentHistory(departmentIdScope);
%>

<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>Role & Duty Assignment | IR-AMS</title>
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.0/css/all.min.css">
    <link rel="stylesheet" href="css/ir-glass.css">
    <link rel="stylesheet" href="css/ams-pro.css">
    <link rel="stylesheet" href="css/ir-ams-railway-ui.css">
    <style>
        .assignment-grid {
            display: grid;
            grid-template-columns: 1fr 2fr;
            gap: 20px;
        }
        .form-section, .table-section {
            background: rgba(255, 255, 255, 0.9);
            padding: 20px;
            border-radius: 8px;
            box-shadow: 0 4px 6px rgba(0,0,0,0.1);
        }
        .railway-form-group {
            margin-bottom: 15px;
        }
        .railway-form-group label {
            display: block;
            margin-bottom: 5px;
            font-weight: bold;
        }
        .railway-form-group input, .railway-form-group select, .railway-form-group textarea {
            width: 100%;
            padding: 8px;
            border: 1px solid #ccc;
            border-radius: 4px;
        }
        .railway-btn {
            background: #0056b3;
            color: white;
            padding: 10px 15px;
            border: none;
            border-radius: 4px;
            cursor: pointer;
        }
        .railway-btn:hover {
            background: #004494;
        }
        table {
            width: 100%;
            border-collapse: collapse;
        }
        th, td {
            padding: 10px;
            border: 1px solid #eee;
            text-align: left;
        }
        th {
            background: #f8f9fa;
        }
    </style>
</head>
<body class="railway-ui">

<div class="app">
    <jsp:include page="sidebar.jsp" />

    <main class="main railway-main">
        <jsp:include page="topbar.jsp" />

        <div class="main-scroll-content">
            <section class="add-employee-hero" style="margin-bottom: 20px; padding: 20px; background: white; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.05);">
                <h1><i class="fa-solid fa-user-shield"></i> Role & Duty Assignment</h1>
                <p>Manage dynamic system roles and duties for employees.</p>
                <% if ("assigned".equals(msg)) { %><p style="color: green;"><b>Role assigned successfully.</b></p><% } %>
                <% if ("deactivated".equals(msg)) { %><p style="color: green;"><b>Role deactivated successfully.</b></p><% } %>
                <% if (error != null) { %><p style="color: red;"><b>Error: <%= HtmlEscapeUtil.escape(java.net.URLDecoder.decode(error, "UTF-8")) %></b></p><% } %>
            </section>

            <div class="assignment-grid">
                <!-- FORM SECTION -->
                <div class="form-section">
                    <h3>Assign New Duty</h3>
                    <br>
                    <form action="RoleAssignmentServlet" method="POST" onsubmit="return validateForm()">
                        <input type="hidden" name="action" value="ASSIGN">
                        
                        <div class="railway-form-group">
                            <label>Employee</label>
                            <select name="employee_id" id="employee_id" required>
                                <option value="">-- Select Employee --</option>
                                <%
                                    List<Map<String, Object>> assignableEmployees = RoleAssignmentDAO.getAssignableEmployeesForDropdown(departmentIdScope);
                                    for (Map<String, Object> emp : assignableEmployees) {
                                        int empId = (Integer) emp.get("employee_id");
                                        String empCode = (String) emp.get("employee_code");
                                        String empName = (String) emp.get("employee_name");
                                        String designation = (String) emp.get("designation");
                                        String currentRoles = (String) emp.get("current_role_label");
                                        boolean hasLogin = Boolean.TRUE.equals(emp.get("has_login"));
                                %>
                                <% if (hasLogin) { %>
                                <option value="<%= empId %>" data-code="<%= HtmlEscapeUtil.escape(empCode) %>"><%= HtmlEscapeUtil.escape(empCode) %> - <%= HtmlEscapeUtil.escape(empName) %> - <%= HtmlEscapeUtil.escape(designation) %> - Current: <%= HtmlEscapeUtil.escape(currentRoles) %></option>
                                <% } else { %>
                                <option value="" disabled title="No login account yet — generate one from Employees first"><%= HtmlEscapeUtil.escape(empCode) %> - <%= HtmlEscapeUtil.escape(empName) %> - <%= HtmlEscapeUtil.escape(designation) %> - (No login account yet)</option>
                                <% } %>
                                <%  } %>
                            </select>
                        </div>

                        <div class="railway-form-group">
                            <label>System Role</label>
                            <select name="role_code" id="role_code" onchange="checkRole()" required>
                                <option value="">-- Select Role --</option>
                                <option value="ADMIN">Admin</option>
                                <option value="ASSET_MANAGER">Asset Manager</option>
                                <option value="DEPARTMENT_HEAD">Department Head</option>
                                <option value="AUDITOR">Auditor</option>
                                <option value="EMPLOYEE">Employee</option>
                            </select>
                            <small class="form-text text-muted" id="admin_warning" style="display:none; color: #d9534f; margin-top: 5px;">
                                Only one active dynamic Admin duty is allowed. Assigning Admin to a new employee will replace the previous dynamic Admin.
                            </small>
                        </div>

                        <div class="railway-form-group">
                            <label>Department (Required for Dept Head)</label>
                            <select name="department_id" id="department_id">
                                <option value="">-- Global / None --</option>
                                <% 
                                    try (Connection con = DBConnection.getConnection(); 
                                         PreparedStatement ps = con.prepareStatement("SELECT department_id, department_name FROM departments ORDER BY department_name");
                                         ResultSet rs = ps.executeQuery()) {
                                        while (rs.next()) {
                                %>
                                <option value="<%= rs.getInt("department_id") %>"><%= HtmlEscapeUtil.escape(rs.getString("department_name")) %></option>
                                <%      } 
                                    } catch(Exception e){}
                                %>
                            </select>
                        </div>


                        <button type="submit" class="railway-btn"><i class="fa-solid fa-check"></i> Assign Role</button>
                    </form>
                </div>

                <!-- TABLE SECTION -->
                <div class="table-section">
                    <h3>Active Duties</h3>
                    <br>
                    <div style="overflow-x: auto;">
                        <table>
                            <thead>
                                <tr>
                                    <th>Employee</th>
                                    <th>Role</th>
                                    <th>Department</th>
                                    <th>Designation</th>
                                    <th>Actions</th>
                                </tr>
                            </thead>
                            <tbody>
                                <% if (activeAssignments.isEmpty()) { %>
                                    <tr><td colspan="5">No active duty assignments found.</td></tr>
                                <% } else {
                                    for (Map<String, Object> a : activeAssignments) { %>
                                    <tr>
                                        <td><%= HtmlEscapeUtil.escape((String) a.get("employee_name")) %> (<%= HtmlEscapeUtil.escape((String) a.get("employee_code")) %>)</td>
                                        <td style="white-space: nowrap !important;"><b><%= HtmlEscapeUtil.escape((String) a.get("role_code")) %></b></td>
                                        <td><%= a.get("department_name") != null && !a.get("department_name").toString().trim().isEmpty() ? HtmlEscapeUtil.escape(a.get("department_name").toString()) : "-" %></td>
                                        <td><%= a.get("designation") != null && !a.get("designation").toString().trim().isEmpty() ? HtmlEscapeUtil.escape(a.get("designation").toString()) : "-" %></td>
                                        <td>
                                            <form action="RoleAssignmentServlet" method="POST" style="display:inline;" onsubmit="return confirmDeactivate('<%= a.get("role_code") %>')">
                                                <input type="hidden" name="action" value="DEACTIVATE">
                                                <input type="hidden" name="assignment_id" value="<%= a.get("assignment_id") %>">
                                                <input type="hidden" name="target_role" value="<%= HtmlEscapeUtil.escape((String) a.get("role_code")) %>">
                                                <button type="submit" class="railway-btn" style="background:#dc3545; padding:5px 10px; font-size: 12px; white-space: nowrap !important;">Deactivate</button>
                                            </form>
                                        </td>
                                    </tr>
                                <%  }
                                   } %>
                            </tbody>
                        </table>
                    </div>
                </div>
            </div>

            <div class="table-section" style="margin-top: 20px;">
                <h3>Assignment History</h3>
                <br>
                <div style="overflow-x: auto;">
                    <table>
                        <thead>
                            <tr>
                                <th>Status</th>
                                <th>Employee</th>
                                <th>Role</th>
                                <th>Department</th>
                                <th>From</th>
                                <th>To</th>
                                <th>Remarks</th>
                            </tr>
                        </thead>
                        <tbody>
                            <% if (assignmentHistory.isEmpty()) { %>
                                <tr><td colspan="7">No history found.</td></tr>
                            <% } else {
                                for (Map<String, Object> h : assignmentHistory) { %>
                                <tr>
                                    <td>
                                        <% if ("ACTIVE".equals(h.get("assignment_status"))) { %>
                                            <span style="color:green; font-weight:bold;">ACTIVE</span>
                                        <% } else { %>
                                            <span style="color:gray;">INACTIVE</span>
                                        <% } %>
                                    </td>
                                    <td><%= HtmlEscapeUtil.escape((String) h.get("employee_name")) %> (<%= HtmlEscapeUtil.escape((String) h.get("employee_code")) %>)</td>
                                    <td><%= HtmlEscapeUtil.escape((String) h.get("role_code")) %></td>
                                    <td><%= h.get("department_name") != null && !h.get("department_name").toString().trim().isEmpty() ? HtmlEscapeUtil.escape(h.get("department_name").toString()) : "-" %></td>
                                    <td><%= h.get("effective_from") %></td>
                                    <td><%= h.get("effective_to") != null ? h.get("effective_to") : "-" %></td>
                                    <td><%= h.get("remarks") != null ? HtmlEscapeUtil.escape(h.get("remarks").toString()) : "-" %></td>
                                </tr>
                            <%  }
                               } %>
                        </tbody>
                    </table>
                </div>
            </div>

        </div>
    </main>
</div>

<script>
    function checkRole() {
        var role = document.getElementById("role_code").value;
        var dept = document.getElementById("department_id");
        var adminWarning = document.getElementById("admin_warning");
        if (role === 'DEPARTMENT_HEAD') {
            dept.setAttribute("required", "true");
        } else {
            dept.removeAttribute("required");
        }
        
        if (role === 'ADMIN') {
            adminWarning.style.display = 'block';
        } else {
            adminWarning.style.display = 'none';
        }
    }

    function validateForm() {
        var role = document.getElementById("role_code").value;
        var empSelect = document.getElementById("employee_id");
        var empCode = "";
        if (empSelect.selectedIndex > 0) {
            empCode = empSelect.options[empSelect.selectedIndex].getAttribute("data-code");
        }
        
        if (role === 'EMPLOYEE') {
            if (!confirm("Are you sure you want to remove all active elevated duties for " + empCode + " and return the user to Employee role?")) {
                return false;
            }
        }
        
        if (role === 'SUPER_ADMIN' || role === 'ADMIN') {
            if (!confirm("Are you sure you want to assign Admin duty? This may replace the previous dynamic Admin.")) {
                return false;
            }
        }
        return true;
    }

    function confirmDeactivate(role) {
        if (role === 'SUPER_ADMIN' || role === 'ADMIN') {
            return confirm("Are you sure you want to deactivate this Admin duty?");
        }
        return confirm("Are you sure you want to deactivate this duty assignment? This will only remove this specific duty.");
    }
</script>

<script src="js/topbar-search.js?v=role-duty-1"></script>
<script src="js/user-dropdown.js?v=role-duty-1"></script>
<script src="js/sidebar-role.js?v=role-duty-1"></script>
<script src="js/ir-body-watermark.js?v=role-duty-1"></script>
<script src="js/dashboard-actions.js?v=role-duty-1"></script>

</body>
</html>
