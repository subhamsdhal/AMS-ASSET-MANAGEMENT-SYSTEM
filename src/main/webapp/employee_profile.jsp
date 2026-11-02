<%@page contentType="text/html" pageEncoding="UTF-8"%>
<%@page import="java.sql.*"%>
<%@page import="java.util.List"%>
<%@page import="com.mycompany.asset_management_system_ams.DBConnection"%>
<%@page import="com.mycompany.asset_management_system_ams.EmployeeDAO"%>
<%@page import="com.mycompany.asset_management_system_ams.Employee"%>
<%@page import="com.mycompany.asset_management_system_ams.HtmlEscapeUtil"%>
<%@page import="com.mycompany.asset_management_system_ams.ProfileChangeRequest"%>
<%@page import="com.mycompany.asset_management_system_ams.ProfileChangeRequestDAO"%>

<%
    String username = (String) session.getAttribute("username");
    String role = (String) session.getAttribute("role");
    Object userIdObj = session.getAttribute("user_id");
    Object employeeIdObj = session.getAttribute("employee_id");

    response.setHeader("Cache-Control", "no-cache, no-store, must-revalidate");
    response.setHeader("Pragma", "no-cache");
    response.setDateHeader("Expires", 0);

    if (username == null || role == null || userIdObj == null || employeeIdObj == null) {
        response.sendRedirect("login.jsp");
        return;
    }

    int employeeId = Integer.parseInt(employeeIdObj.toString());

    EmployeeDAO empDao = new EmployeeDAO();
    Employee employee = empDao.getEmployeeById(employeeId);

    if (employee == null) {
        response.sendRedirect("login.jsp?error=employee_not_found");
        return;
    }

    List<ProfileChangeRequest> myRequests = new ProfileChangeRequestDAO().listForEmployee(employeeId);

    String profileMsg = request.getParameter("msg");
    String profileError = request.getParameter("error");
    String profileBannerText = "";
    String profileBannerClass = "";

    if ("request_submitted".equals(profileMsg)) {
        profileBannerText = "Your request was submitted and is awaiting admin review.";
        profileBannerClass = "page-success";
    } else if ("already_pending".equals(profileError)) {
        profileBannerText = "You already have a pending request for that field. Wait for it to be reviewed before submitting another.";
        profileBannerClass = "page-error";
    } else if ("no_change".equals(profileError)) {
        profileBannerText = "That's already your current value - nothing to request.";
        profileBannerClass = "page-error";
    } else if ("invalid_email".equals(profileError)) {
        profileBannerText = "Enter a valid email address.";
        profileBannerClass = "page-error";
    } else if ("invalid_phone".equals(profileError)) {
        profileBannerText = "Enter a valid phone number.";
        profileBannerClass = "page-error";
    } else if ("missing_value".equals(profileError) || "invalid_field".equals(profileError)) {
        profileBannerText = "Please choose a field and enter the new value.";
        profileBannerClass = "page-error";
    } else if ("server".equals(profileError)) {
        profileBannerText = "Unable to submit your request. Please try again.";
        profileBannerClass = "page-error";
    }
%>

<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>My Profile - IR-AMS</title>
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.0/css/all.min.css">
    <link rel="stylesheet" href="css/ir-glass.css?v=28000">
    <link rel="stylesheet" href="css/ams-pro.css?v=28000">
    <link rel="stylesheet" href="css/ir-ams-railway-ui.css?v=28000">
    <style>
        h1, h2, h3, h4, h5, h6, .hero-banner h1, .panel-header h2, .section-title, .module-title, .card-title {
            color: #0f172a !important;
        }
        .hero-banner {
            background: linear-gradient(135deg, #f0f7ff, #e0f2fe);
            padding: 24px 30px;
            border-radius: 12px;
            margin-bottom: 24px;
            border: 1px solid #bae6fd;
            display: flex;
            align-items: center;
            justify-content: space-between;
            box-shadow: 0 2px 4px rgba(0,0,0,0.02);
        }
        .hero-banner h1 {
            margin: 0;
            color: #0f172a;
            font-size: 24px;
            font-weight: 700;
        }
        .hero-banner p {
            margin: 8px 0 0 0;
            color: #475569;
            font-size: 15px;
        }
        .panel {
            background: #ffffff;
            border: 1px solid #e2e8f0;
            border-radius: 12px;
            padding: 24px;
            box-shadow: 0 4px 6px -1px rgba(0, 0, 0, 0.05);
            margin-bottom: 24px;
        }
        .panel-header {
            display: flex;
            justify-content: space-between;
            align-items: center;
            margin-bottom: 20px;
            border-bottom: 1px solid #f1f5f9;
            padding-bottom: 10px;
        }
        .panel-header h2 { margin: 0; font-size: 18px; color: #0f172a; font-weight: 700; }
        
        .profile-grid {
            display: grid;
            grid-template-columns: 1fr 1fr;
            gap: 20px;
        }
        .profile-item {
            background: #f8fafc;
            padding: 16px;
            border-radius: 8px;
            border: 1px solid #e2e8f0;
        }
        .profile-item label {
            display: block;
            color: #64748b;
            font-size: 13px;
            font-weight: 700;
            text-transform: uppercase;
            margin-bottom: 5px;
            letter-spacing: 0.5px;
        }
        .profile-item div {
            color: #0f172a;
            font-size: 16px;
            font-weight: 600;
        }
    </style>
</head>
<body class="railway-ui">
<div class="app ams-shell">

    <jsp:include page="sidebar.jsp" />

    <main class="main railway-main">
        <jsp:include page="topbar.jsp" />

        <div class="main-scroll-content">
            
            <div class="hero-banner">
                <div>
                    <h1>My Profile</h1>
                    <p>View your personal and employment details.</p>
                </div>
            </div>

            <% if (!profileBannerText.isEmpty()) { %>
                <div class="<%= profileBannerClass %>">
                    <i class="fa-solid <%= "page-success".equals(profileBannerClass) ? "fa-circle-check" : "fa-triangle-exclamation" %>"></i>
                    <%= HtmlEscapeUtil.escape(profileBannerText) %>
                </div>
            <% } %>

            <div class="panel">
                <div class="panel-header">
                    <h2>Personal Details</h2>
                </div>
                <div class="profile-grid">
                    <div class="profile-item">
                        <label>Name</label>
                        <div><%= HtmlEscapeUtil.escape(employee.getEmployeeName(), "N/A") %></div>
                    </div>
                    <div class="profile-item">
                        <label>Employee Code</label>
                        <div><%= HtmlEscapeUtil.escape(employee.getEmployeeCode(), "N/A") %></div>
                    </div>
                    <div class="profile-item">
                        <label>Email</label>
                        <div><%= HtmlEscapeUtil.escape(employee.getEmail(), "N/A") %></div>
                    </div>
                    <div class="profile-item">
                        <label>Phone</label>
                        <div><%= HtmlEscapeUtil.escape(employee.getPhone(), "N/A") %></div>
                    </div>
                </div>
            </div>

            <div class="panel">
                <div class="panel-header">
                    <h2>Employment Details</h2>
                </div>
                <div class="profile-grid">
                    <div class="profile-item">
                        <label>Department</label>
                        <div><%= HtmlEscapeUtil.escape(employee.getDepartmentName(), "N/A") %></div>
                    </div>
                    <div class="profile-item">
                        <label>Designation</label>
                        <div><%= HtmlEscapeUtil.escape(employee.getDesignation(), "N/A") %></div>
                    </div>
                    <div class="profile-item">
                        <label>Joining Date</label>
                        <div><%= HtmlEscapeUtil.escape(employee.getJoiningDate(), "N/A") %></div>
                    </div>
                    <div class="profile-item">
                        <label>Status</label>
                        <div><span class="badge" style="background: #dcfce7; color: #166534; padding: 4px 10px; border-radius: 20px; font-size: 12px; font-weight: 600;"><%= HtmlEscapeUtil.escape(employee.getStatus(), "ACTIVE") %></span></div>
                    </div>
                </div>
            </div>

            <div class="panel">
                <div class="panel-header">
                    <h2>Request a Profile Change</h2>
                </div>
                <p style="color:#64748b;font-size:14px;margin-top:-8px;margin-bottom:16px;">
                    Email and phone number changes go to an admin for approval before they take effect -
                    this keeps your official contact record accurate and reviewed.
                </p>
                <form action="SubmitProfileChangeRequestServlet" method="post" class="profile-grid" style="align-items:end;">
                    <div class="profile-item">
                        <label for="fieldName">Field</label>
                        <select id="fieldName" name="fieldName" required style="padding:10px;border-radius:8px;border:1px solid #e2e8f0;width:100%;">
                            <option value="email">Email</option>
                            <option value="phone">Phone Number</option>
                        </select>
                    </div>
                    <div class="profile-item">
                        <label for="requestedValue">Requested New Value</label>
                        <input type="text" id="requestedValue" name="requestedValue" required maxlength="120"
                               placeholder="new.value@ecor.railnet.gov.in"
                               style="padding:10px;border-radius:8px;border:1px solid #e2e8f0;width:100%;box-sizing:border-box;">
                    </div>
                    <div class="profile-item" style="grid-column:1 / -1;">
                        <label for="reason">Reason</label>
                        <input type="text" id="reason" name="reason" maxlength="500"
                               placeholder="e.g. changed personal number, official email correction..."
                               style="padding:10px;border-radius:8px;border:1px solid #e2e8f0;width:100%;box-sizing:border-box;">
                    </div>
                    <div class="profile-item" style="grid-column:1 / -1;">
                        <button type="submit" class="btn submit-btn">
                            <i class="fa-solid fa-paper-plane"></i>
                            Submit Request
                        </button>
                    </div>
                </form>
            </div>

            <% if (!myRequests.isEmpty()) { %>
            <div class="panel">
                <div class="panel-header">
                    <h2>My Requests</h2>
                </div>
                <div class="registry-table-wrap">
                    <table class="asset-table">
                        <thead>
                            <tr>
                                <th>Field</th>
                                <th>Requested Value</th>
                                <th>Status</th>
                                <th>Submitted</th>
                            </tr>
                        </thead>
                        <tbody>
                            <% for (ProfileChangeRequest req : myRequests) {
                                String myStatusPillClass = "PENDING".equals(req.getStatus()) ? "warranty-expiring"
                                        : "APPROVED".equals(req.getStatus()) ? "warranty-active" : "warranty-expired";
                            %>
                                <tr>
                                    <td><%= "email".equals(req.getFieldName()) ? "Email" : "Phone Number" %></td>
                                    <td><%= HtmlEscapeUtil.escape(req.getRequestedValue(), "-") %></td>
                                    <td>
                                        <span class="warranty-status-pill <%= myStatusPillClass %>">
                                            <%= HtmlEscapeUtil.escape(req.getStatus()) %>
                                        </span>
                                    </td>
                                    <td><%= HtmlEscapeUtil.escape(req.getCreatedAt(), "-") %></td>
                                </tr>
                            <% } %>
                        </tbody>
                    </table>
                </div>
            </div>
            <% } %>

        </div>
    </main>
</div>

<script src="js/topbar-search.js?v=employee-maintenance-inner-1"></script>
<script src="js/user-dropdown.js?v=employee-maintenance-inner-1"></script>
<script src="js/sidebar-role.js?v=employee-maintenance-inner-1"></script>
<script src="js/ir-body-watermark.js?v=employee-maintenance-inner-1"></script>
<script src="js/dashboard-actions.js?v=employee-maintenance-inner-1"></script>
</body>
</html>
