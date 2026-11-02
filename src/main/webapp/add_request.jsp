<%@page contentType="text/html" pageEncoding="UTF-8"%>
<%@page import="java.sql.*"%>
<%@page import="com.mycompany.asset_management_system_ams.DBConnection"%>
<%@page import="com.mycompany.asset_management_system_ams.HtmlEscapeUtil"%>

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

    if (!("SUPER_ADMIN".equals(role) || "ADMIN".equals(role))
            && !"ASSET_MANAGER".equals(role)
            && !"DEPARTMENT_HEAD".equals(role)
            && !"EMPLOYEE".equals(role)) {
        response.sendRedirect("asset_requests.jsp?access=denied");
        return;
    }

    int currentUserId = 0;

    try {
        Object userIdObj = session.getAttribute("user_id");
        if (userIdObj == null) {
            userIdObj = session.getAttribute("userId");
        }
        if (userIdObj != null) {
            currentUserId = Integer.parseInt(String.valueOf(userIdObj));
        }
    } catch (Exception e) {
        currentUserId = 0;
    }

    String error = request.getParameter("error");
%>

<!DOCTYPE html>
<html>
<head>
    <title>IR-AMS Add Asset Request</title>

    <link rel="stylesheet"
          href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.0/css/all.min.css">

    <link rel="stylesheet" href="css/ir-glass.css?v=28000">
    <link rel="stylesheet" href="css/ams-pro.css?v=28000">
    <link rel="stylesheet" href="css/ir-ams-railway-ui.css?v=28000">
<link rel="stylesheet" href="css/add_request.css?v=topbarfix1">
    </head>

<body class="railway-ui">

<div class="app">

    <jsp:include page="sidebar.jsp">
        <jsp:param name="activeMenu" value="asset_requests"/>
    </jsp:include>

    <main class="main railway-main">

        <%@ include file="topbar.jsp" %>
        <div class="main-scroll-content">                

        <section class="add-request-hero">
            <h1>New Asset Request</h1>

            <p>
                Register a new employee request for laptops, printers, networking devices,
                projectors, furniture or other railway/company assets with approval status.
            </p>

            <br>

            <div class="hero-pills">
                <div class="hero-pill"><i class="fa-solid fa-file-circle-plus"></i> Request Entry</div>
                <div class="hero-pill"><i class="fa-solid fa-user-check"></i> Employee Mapping</div>
                <div class="hero-pill"><i class="fa-solid fa-layer-group"></i> Category Selection</div>
                <div class="hero-pill"><i class="fa-solid fa-database"></i> MySQL Insert</div>
            </div>
        </section>

        <section class="glass-panel">

            <h2>Asset Request Form</h2>
            <br>

            <%
                if ("failed".equals(error)) {
            %>
                <div class="alert-error">
                    Request could not be added. Please check the details.
                </div>
            <%
                } else if ("server".equals(error)) {
            %>
                <div class="alert-error">
                    Server error occurred. Please check employee/category values.
                </div>
            <%
                } else if ("invaliddate".equals(error)) {
            %>
                <div class="alert-error">
                    Request date must be today or a previous date.
                </div>
            <%
                } else if ("invalidselection".equals(error)) {
            %>
                <div class="alert-error">
                    Please select an active employee and active category from the database.
                </div>
            <%
                } else if ("access".equals(error)) {
            %>
                <div class="alert-error">
                    Your login is not linked to an active employee record. Please contact administrator.
                </div>
            <%
                }
            %>

            <form action="AddAssetRequestServlet" method="post">

                <div class="form-grid">

                    <div class="form-group">
                        <label>Employee</label>
                        <select name="employeeId" required>
                            <option value="">Select Employee</option>

                            <%
                                Connection empCon = null;
                                PreparedStatement empPs = null;
                                ResultSet empRs = null;

                                try {
                                    empCon = DBConnection.getConnection();

                                    String empSql;

                                    if ("EMPLOYEE".equals(role)) {
                                        empSql = "SELECT e.employee_id, e.employee_code, e.employee_name AS full_name "
                                                + "FROM employees e "
                                                + "JOIN users u ON u.employee_id = e.employee_id "
                                                + "WHERE u.user_id = ? "
                                                + "AND e.employee_status = 'ACTIVE' "
                                                + "AND COALESCE(e.is_deleted, 0) = 0 "
                                                + "ORDER BY e.employee_code ASC";
                                    } else {
                                        empSql = "SELECT employee_id, employee_code, employee_name AS full_name "
                                                + "FROM employees "
                                                + "WHERE employee_status = 'ACTIVE' "
                                                + "AND COALESCE(is_deleted, 0) = 0 "
                                                + "ORDER BY employee_code ASC";
                                    }

                                    empPs = empCon.prepareStatement(empSql);
                                    if ("EMPLOYEE".equals(role)) {
                                        empPs.setInt(1, currentUserId);
                                    }
                                    empRs = empPs.executeQuery();

                                    while (empRs.next()) {
                            %>
                                        <option value="<%= empRs.getInt("employee_id") %>">
                                            <%= HtmlEscapeUtil.escape(empRs.getString("employee_code")) %> - <%= HtmlEscapeUtil.escape(empRs.getString("full_name")) %>
                                        </option>
                            <%
                                    }
                                } catch (Exception e) {
                                    e.printStackTrace();
                                } finally {
                                    try { if (empRs != null) empRs.close(); } catch (Exception ignored) {}
                                    try { if (empPs != null) empPs.close(); } catch (Exception ignored) {}
                                    try { if (empCon != null) empCon.close(); } catch (Exception ignored) {}
                                }
                            %>

                        </select>
                    </div>
                    
                    <div class="form-group">
                        <label>Requested Asset Category</label>

                        <select name="categoryId" required>
                            <option value="">Select Category</option>

                            <%
                                try {
                                    Connection catCon = DBConnection.getConnection();

                                    PreparedStatement catPs = catCon.prepareStatement(
                                        "SELECT category_id, category_name " +
                                        "FROM asset_categories " +
                                        "WHERE is_active = 'YES' " +
                                        "ORDER BY category_name"
                                    );

                                    ResultSet catRs = catPs.executeQuery();

                                    while (catRs.next()) {
                            %>

                                        <option value="<%= catRs.getInt("category_id") %>">
                                            <%= HtmlEscapeUtil.escape(catRs.getString("category_name")) %>
                                        </option>

                            <%
                                    }

                                    catRs.close();
                                    catPs.close();
                                    catCon.close();

                                } catch (Exception e) {
                                    e.printStackTrace();
                                }
                            %>

                        </select>
                    </div>
                   
                    <div class="form-group">
                        <label>Request Date</label>
                        <input type="date"
                               name="requestDate"
                               id="requestDate"
                               required>
                    </div>

                    <input type="hidden" name="requestStatus" value="PENDING">

                    <div class="form-group">
                        <label>Remarks</label>
                        <input type="text"
                               name="remarks"
                               placeholder="Example: Laptop required for field inspection"
                               required>
                    </div>

                </div>

                <div class="form-actions">
                    <button type="submit" class="btn">
                        <i class="fa-solid fa-floppy-disk"></i> Save Request
                    </button>

                    <a href="asset_requests.jsp" class="btn">
                        <i class="fa-solid fa-arrow-left"></i> Back to Requests
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

<script src="js/date-rules.js?v=28000"></script>
<script src="js/topbar-search.js?v=28000"></script>
<script src="js/user-dropdown.js?v=28000"></script>
<script src="js/sidebar-role.js?v=28000"></script>
<script src="js/ir-body-watermark.js?v=28000"></script>
<script src="js/dashboard-actions.js?v=28000"></script>

</body>
</html>
