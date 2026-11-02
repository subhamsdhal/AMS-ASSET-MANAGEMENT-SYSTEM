<%@page contentType="text/html" pageEncoding="UTF-8"%>
<%@ page import="java.sql.Connection" %>
<%@ page import="java.sql.PreparedStatement" %>
<%@ page import="java.sql.ResultSet" %>
<%@ page import="com.mycompany.asset_management_system_ams.DBConnection" %>

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

    String error = request.getParameter("error");

    String nextEmployeeCode = "EMP001";

    String codeSql = "SELECT COALESCE(MAX(CAST(SUBSTRING(employee_code, 4) AS UNSIGNED)), 0) + 1 AS next_no "
            + "FROM employees "
            + "WHERE employee_code REGEXP '^EMP[0-9]+$'";

    try (Connection codeCon = DBConnection.getConnection();
         PreparedStatement codePs = codeCon.prepareStatement(codeSql);
         ResultSet codeRs = codePs.executeQuery()) {
        
        if (codeRs.next()) {
            int nextNo = codeRs.getInt("next_no");
            nextEmployeeCode = String.format("EMP%03d", nextNo);
        }
    } catch (Exception e) {
        e.printStackTrace();
    }
%>

<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>IR-AMS Add Employee</title>

    <link rel="stylesheet"
          href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.0/css/all.min.css">

    <link rel="stylesheet" href="css/ir-glass.css?v=28000">
    <link rel="stylesheet" href="css/ams-pro.css?v=28000">
    <link rel="stylesheet" href="css/ir-ams-railway-ui.css?v=28000">
<link rel="stylesheet" href="css/add_employee.css?v=topbarfix1">
    </head>

<body class="railway-ui">

<div class="app">

    <jsp:include page="sidebar.jsp" />

    <main class="main railway-main">
        <jsp:include page="topbar.jsp" />

        <div class="main-scroll-content">

            <section class="add-employee-hero">
                <h1>Employee Registration Form</h1>

                <p>
                    Register railway employee records with system-generated employee code,
                    department, designation, contact information and joining date.
                    New employee records are activated automatically.
                </p>

                <br>

                <div class="hero-pills">
                    <div class="hero-pill"><i class="fa-solid fa-user-plus"></i> Add Employee</div>
                    <div class="hero-pill"><i class="fa-solid fa-hashtag"></i> Auto Employee Code</div>
                    <div class="hero-pill"><i class="fa-solid fa-building"></i> Department Mapping</div>
                    <div class="hero-pill"><i class="fa-solid fa-circle-check"></i> Auto Active Status</div>
                </div>
            </section>

            <section class="glass-panel">

                <h2>Employee Registration Form</h2>
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
                        Employee record could not be saved. Please check the details and try again.
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
                        Server error occurred while creating employee record.
                    </div>
                <%
                    /* Fault: AddEmployeeServlet redirects here with error=invalidphone
                       when PhoneValidationUtil.validatePhone() rejects the submitted
                       number, but this page never had a branch for it - a real,
                       common mistake (typo'd or too-short phone number) reloaded the
                       form with zero feedback. */
                    } else if ("invalidphone".equals(error)) {
                %>
                    <div class="page-error">
                        <i class="fa-solid fa-triangle-exclamation"></i>
                        Invalid phone number. Please enter a valid contact number.
                    </div>
                <%
                    }
                %>

                <form action="AddEmployeeServlet" method="post" enctype="multipart/form-data">
                    <input type="hidden" name="employeeCode" value="<%= nextEmployeeCode %>">

                    <div class="form-grid">

                        <div class="form-group">
                            <label>Employee Code</label>
                            <input type="text"
                                   name="employeeCodePreview"
                                   value="<%= nextEmployeeCode %>"
                                   readonly
                                   style="cursor:not-allowed; opacity:0.90;">
                        </div>

                        <div class="form-group">
                            <label>Full Name</label>
                            <input type="text"
                                   name="employeeName"
                                   placeholder="Example: Rahul Sharma"
                                   required>
                        </div>

                        <div class="form-group">
                            <label>Email</label>
                            <input type="email"
                                   name="email"
                                   placeholder="Example: rahul.sharma@railway.in"
                                   required>
                        </div>

                        <div class="form-group">
                            <label>Phone</label>
                            <input type="text"
                                   name="phone"
                                   placeholder="Example: 9876543210"
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
                                            + "WHERE status = 'ACTIVE' "
                                            + "ORDER BY department_name ASC";
                                    
                                    try (Connection con = DBConnection.getConnection();
                                         PreparedStatement ps = con.prepareStatement(sql);
                                         ResultSet rs = ps.executeQuery()) {
                                        
                                        while (rs.next()) {
                                %>
                                            <option value="<%= rs.getInt("department_id") %>">
                                                <%= rs.getString("department_name") %>
                                            </option>
                                <%
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
                                   placeholder="Example: Junior Engineer"
                                   required>
                        </div>

                        <div class="form-group">
                            <label>Joining Date</label>
                            <input type="date"
                                   name="joiningDate"
                                   required>
                        </div>

                        <div class="form-group" style="grid-column: 1 / -1; margin-top: 20px; border-top: 1px solid var(--ir-border); padding-top: 20px;">
                            <h3 style="margin-bottom: 15px; color: var(--ir-blue); font-size: 16px;">Optional Document Upload</h3>
                            <p style="font-size: 13px; color: var(--text-secondary); margin-bottom: 15px;">You can optionally attach one document (e.g. ID Proof, Joining Letter) now. More documents can be added later from the Employee Profile.</p>
                            
                            <div style="display: grid; grid-template-columns: 1fr 1fr 1fr; gap: 15px;">
                                <div>
                                    <label class="form-label" style="display:block; margin-bottom: 5px;">Document Title</label>
                                    <input type="text" name="documentTitle" class="form-control" placeholder="e.g. Aadhar Card">
                                </div>
                                <div>
                                    <label class="form-label" style="display:block; margin-bottom: 5px;">Document Type</label>
                                    <select name="documentType" class="form-control">
                                        <option value="">Select Type</option>
                                        <option value="ID_PROOF">ID Proof</option>
                                        <option value="JOINING_LETTER">Joining Letter</option>
                                        <option value="APPOINTMENT_LETTER">Appointment Letter</option>
                                        <option value="CERTIFICATE">Certificate</option>
                                        <option value="SERVICE_DOCUMENT">Service Document</option>
                                        <option value="OTHER">Other</option>
                                    </select>
                                </div>
                                <div>
                                    <label class="form-label" style="display:block; margin-bottom: 5px;">Select File</label>
                                    <input type="file" name="employeeDocument" class="form-control" accept=".pdf,.jpg,.jpeg,.png,.doc,.docx" style="padding: 8px; border: 1px solid #ccc; border-radius: 4px; width: 100%;">
                                    <small style="display:block; margin-top:5px; color:var(--text-secondary); font-size: 11px;">Allowed: PDF, JPG, PNG, DOC, DOCX. Max: 5 MB.</small>
                                </div>
                            </div>
                        </div>

                        <div class="form-group" style="grid-column: 1 / -1;">
                            <label class="toggle-switch" style="display:flex; align-items:center; gap: 10px; cursor: pointer; width: max-content;">
                                <input type="checkbox" name="createLogin" value="1" checked style="width:18px; height:18px;">
                                <span style="font-size: 14px; font-weight: 700; color: var(--ir-blue);">Create System Login Account & Send Email</span>
                            </label>
                            <p style="font-size:12px; color:var(--ir-muted); margin-top: 4px;">If checked, an Employee role account will be created with a secure password, and the credentials will be emailed to the employee.</p>
                        </div>

                    </div>

                    <div class="form-actions">
                        <button type="submit" class="btn">
                            <i class="fa-solid fa-floppy-disk"></i>
                            Save Employee
                        </button>

                        <button type="reset" class="btn">
                            <i class="fa-solid fa-rotate-left"></i>
                            Reset Form
                        </button>

                        <a href="employees.jsp" class="btn">
                            <i class="fa-solid fa-arrow-left"></i>
                            Back to Employees
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
<script src="js/sidebar-role.js?v=20260630-sidebar-scroll-lock"></script>
<script src="js/ir-body-watermark.js?v=employee-maintenance-inner-1"></script>
<script src="js/dashboard-actions.js?v=employee-maintenance-inner-1"></script>

</body>
</html>
