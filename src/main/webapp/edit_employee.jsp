<%@page contentType="text/html" pageEncoding="UTF-8"%>
<%@page import="com.mycompany.asset_management_system_ams.Employee"%>
<%@page import="com.mycompany.asset_management_system_ams.EmployeeDAO"%>
<%@page import="com.mycompany.asset_management_system_ams.DBConnection"%>
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

    boolean isDepartmentHead = "DEPARTMENT_HEAD".equalsIgnoreCase(role);
    boolean canManageEmployees = ("SUPER_ADMIN".equals(role) || "ADMIN".equals(role))
            || isDepartmentHead;

    if (!canManageEmployees) {
        response.sendRedirect("employees.jsp?access=denied");
        return;
    }

    String error = request.getParameter("error");

    int employeeId = 0;

    try {
        employeeId = Integer.parseInt(request.getParameter("id"));
    } catch (Exception e) {
        response.sendRedirect("employees.jsp");
        return;
    }

    int userId = 1;
    if (session.getAttribute("user_id") != null) {
        userId = Integer.parseInt(session.getAttribute("user_id").toString());
    } else if (session.getAttribute("userId") != null) {
        userId = Integer.parseInt(session.getAttribute("userId").toString());
    }

    EmployeeDAO dao = new EmployeeDAO();
    
    if (isDepartmentHead && !dao.isEmployeeUnderDepartmentHead(employeeId, userId)) {
        response.sendRedirect("employees.jsp?access=denied");
        return;
    }

    Employee employee = dao.getEmployeeById(employeeId);

    if (employee == null) {
        response.sendRedirect("employees.jsp");
        return;
    }
%>

<!DOCTYPE html>
<html>
<head>
    <title>IR-AMS Edit Employee</title>

    <link rel="stylesheet"
          href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.0/css/all.min.css">

    <link rel="stylesheet" href="css/ir-glass.css?v=28000">
    <link rel="stylesheet" href="css/ams-pro.css?v=28000">
    <link rel="stylesheet" href="css/ir-ams-railway-ui.css?v=28000">
<link rel="stylesheet" href="css/edit_employee.css?v=topbarfix1">
</head>

<body class="railway-ui">

<div class="app">

    <jsp:include page="sidebar.jsp" />

    <main class="main railway-main">
        <jsp:include page="topbar.jsp" />

        <div class="main-scroll-content">

            <section class="add-employee-hero">
                <h1>Edit Railway Employee</h1>

                <p>
                    Update employee name, department, designation, contact details,
                    joining date and active/inactive status. Employee code is system-controlled.
                </p>

                <br>

                <div class="hero-pills">
                    <div class="hero-pill"><i class="fa-solid fa-pen-to-square"></i> Update Employee</div>
                    <div class="hero-pill"><i class="fa-solid fa-building"></i> Department Mapping</div>
                    <div class="hero-pill"><i class="fa-solid fa-id-card"></i> Employee Identity</div>
                    <div class="hero-pill"><i class="fa-solid fa-database"></i> MySQL Update</div>
                </div>
            </section>

            <section class="glass-panel">

                <h2>Edit Employee Form</h2>
                <br>

                <%
                    if ("invaliddate".equals(error)) {
                %>
                    <div class="page-error">
                        <i class="fa-solid fa-triangle-exclamation"></i>
                        Invalid date selected. Future joining date is not allowed.
                    </div>
                <%
                    } else if ("failed".equals(error)) {
                %>
                    <div class="page-error">
                        <i class="fa-solid fa-triangle-exclamation"></i>
                        Employee could not be updated. Please check the details.
                    </div>
                <%
                    } else if ("invaliddepartment".equals(error)) {
                %>
                    <div class="page-error">
                        <i class="fa-solid fa-triangle-exclamation"></i>
                        Please select an active department from the database.
                    </div>
                <%
                    } else if ("server".equals(error)) {
                %>
                    <div class="page-error">
                        <i class="fa-solid fa-triangle-exclamation"></i>
                        Server error occurred while updating employee record.
                    </div>
                <%
                    /* Fault: UpdateEmployeeServlet redirects here with error=invalidphone
                       (rejected by PhoneValidationUtil.validatePhone()) and error=invalid
                       (getEmployeeSnapshot() couldn't find the record) - neither had a
                       branch on this page, same gap as add_employee.jsp. */
                    } else if ("invalidphone".equals(error)) {
                %>
                    <div class="page-error">
                        <i class="fa-solid fa-triangle-exclamation"></i>
                        Invalid phone number. Please enter a valid contact number.
                    </div>
                <%
                    } else if ("invalid".equals(error)) {
                %>
                    <div class="page-error">
                        <i class="fa-solid fa-triangle-exclamation"></i>
                        Employee record could not be found. It may have been removed.
                    </div>
                <%
                    }
                %>

                <form action="UpdateEmployeeServlet" method="post">

                    <input type="hidden" name="employeeId" value="<%= employee.getEmployeeId() %>">

                    <div class="form-grid">

                        <div class="form-group">
                            <label>Employee Code</label>
                            <input type="text"
                                   name="employeeCode"
                                   value="<%= employee.getEmployeeCode() %>"
                                   readonly>
                        </div>

                        <div class="form-group">
                            <label>Full Name</label>
                            <input type="text"
                                   name="employeeName"
                                   value="<%= employee.getEmployeeName() %>"
                                   required>
                        </div>

                        <div class="form-group">
                            <label>Email</label>
                            <input type="email"
                                   name="email"
                                   value="<%= employee.getEmail() %>"
                                   required>
                        </div>

                        <div class="form-group">
                            <label>Phone</label>
                            <input type="text"
                                   name="phone"
                                   value="<%= employee.getPhone() %>"
                                   maxlength="15"
                                   required>
                        </div>

                        <div class="form-group">
                            <label>Department</label>
                            <select name="departmentId" required>
                                <option value="">Select Department</option>

                                <%
                                    String sql = "SELECT department_id, department_name "
                                            + "FROM departments "
                                            + "WHERE status = 'ACTIVE' OR department_id = ? "
                                            + "ORDER BY department_name ASC";

                                    try (Connection con = DBConnection.getConnection();
                                         PreparedStatement ps = con.prepareStatement(sql)) {
                                        
                                        ps.setInt(1, employee.getDepartmentId());
                                        try (ResultSet rs = ps.executeQuery()) {
                                            while (rs.next()) {
                                                String deptName = rs.getString("department_name");
                                                boolean selected = rs.getInt("department_id") == employee.getDepartmentId();
                                %>
                                            <option value="<%= rs.getInt("department_id") %>"
                                                    <%= selected ? "selected" : "" %>>
                                                <%= deptName %>
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

                        <div class="form-group">
                            <label>Designation</label>
                            <input type="text"
                                   name="designation"
                                   value="<%= employee.getDesignation() %>"
                                   required>
                        </div>

                        <div class="form-group">
                            <label>Joining Date</label>
                            <input type="date"
                                   name="joiningDate"
                                   value="<%= employee.getJoiningDate() %>"
                                   required>
                        </div>

                        <div class="form-group">
                            <label>Status</label>
                            <select name="status" required>
                                <option value="ACTIVE" <%= "ACTIVE".equalsIgnoreCase(employee.getStatus()) ? "selected" : "" %>>
                                    ACTIVE
                                </option>
                                <option value="INACTIVE" <%= "INACTIVE".equalsIgnoreCase(employee.getStatus()) ? "selected" : "" %>>
                                    INACTIVE
                                </option>
                            </select>
                        </div>

                    </div>

                    <div class="form-actions">
                        <button type="submit" class="btn">
                            <i class="fa-solid fa-floppy-disk"></i> Update Employee
                        </button>

                        <a href="employees.jsp" class="btn">
                            <i class="fa-solid fa-arrow-left"></i> Back to Employees
                        </a>
                    </div>

                </form>

            </section>

        </div>

    </main>

</div>
<script>
    const contextPath = "<%= request.getContextPath() %>";

    const railBackgrounds = [
        contextPath + "/images/rail-bg-1.jpg",
        contextPath + "/images/rail-bg-2.jpg",
        contextPath + "/images/rail-bg-3.jpg",
        contextPath + "/images/rail-bg-4.jpg",
        contextPath + "/images/rail-bg-5.jpg",
        contextPath + "/images/rail-bg-6.jpg",
        contextPath + "/images/rail-bg-7.jpg"
    ];

    let currentBgIndex = 0;

    function changeRailBackground() {
        currentBgIndex++;

        if (currentBgIndex >= railBackgrounds.length) {
            currentBgIndex = 0;
        }

        document.body.style.setProperty(
            "--rail-bg",
            "url('" + railBackgrounds[currentBgIndex] + "')"
        );
    }

    setInterval(changeRailBackground, 90000);
</script>
<script src="js/date-rules.js?v=1000"></script>


<script src="js/topbar-search.js?v=employee-maintenance-inner-1"></script>
<script src="js/user-dropdown.js?v=employee-maintenance-inner-1"></script>
<script src="js/sidebar-role.js?v=employee-maintenance-inner-1"></script>
<script src="js/ir-body-watermark.js?v=employee-maintenance-inner-1"></script>
<script src="js/dashboard-actions.js?v=employee-maintenance-inner-1"></script>

</body>
</html>
