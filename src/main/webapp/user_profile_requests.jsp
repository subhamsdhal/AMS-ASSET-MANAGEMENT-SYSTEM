<%@page contentType="text/html" pageEncoding="UTF-8"%>
<%@page import="com.mycompany.asset_management_system_ams.HtmlEscapeUtil"%>
<%@page import="com.mycompany.asset_management_system_ams.ProfileChangeRequest"%>
<%@page import="com.mycompany.asset_management_system_ams.ProfileChangeRequestDAO"%>
<%@page import="com.mycompany.asset_management_system_ams.DBConnection"%>
<%@page import="java.sql.Connection"%>
<%@page import="java.sql.PreparedStatement"%>
<%@page import="java.sql.ResultSet"%>
<%@page import="java.util.ArrayList"%>
<%@page import="java.util.List"%>
<%@page import="java.util.Set"%>
<%@page import="java.util.TreeSet"%>

<%!
    // Same initials() as employees.jsp - kept local rather than shared so this
    // page doesn't take on a cross-file dependency for one small helper.
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

    boolean isSuperAdmin = "SUPER_ADMIN".equals(role) || "ADMIN".equals(role);
    boolean isDepartmentHead = "DEPARTMENT_HEAD".equals(role);

    if (!isSuperAdmin && !isDepartmentHead) {
        response.sendRedirect("dashboard.jsp?access=denied");
        return;
    }

    // Fix: DEPARTMENT_HEAD can now review requests too, but only for
    // employees in a department they head - same scoping pattern
    // employees.jsp already uses (query departments.department_head_user_id,
    // then filter by department name) rather than a separate new mechanism.
    int reviewerUserId = 0;
    try {
        Object userIdObj = session.getAttribute("user_id");
        if (userIdObj != null) {
            reviewerUserId = Integer.parseInt(String.valueOf(userIdObj));
        }
    } catch (Exception e) {
        reviewerUserId = 0;
    }

    Set<String> managedDepartmentSet = new TreeSet<String>();
    if (isDepartmentHead && reviewerUserId > 0) {
        String deptSql = "SELECT department_name FROM departments WHERE department_head_user_id = ?";
        try (Connection deptCon = DBConnection.getConnection();
             PreparedStatement deptPs = deptCon.prepareStatement(deptSql)) {
            deptPs.setInt(1, reviewerUserId);
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

    String statusFilter = request.getParameter("status");
    if (statusFilter == null || statusFilter.trim().isEmpty()) {
        statusFilter = "PENDING";
    }
    statusFilter = statusFilter.trim().toUpperCase();
    if (!statusFilter.equals("PENDING") && !statusFilter.equals("APPROVED")
            && !statusFilter.equals("REJECTED") && !statusFilter.equals("ALL")) {
        statusFilter = "PENDING";
    }

    ProfileChangeRequestDAO dao = new ProfileChangeRequestDAO();
    List<ProfileChangeRequest> requests = dao.listByStatus(statusFilter);
    int pendingCount;

    if (isDepartmentHead) {
        List<ProfileChangeRequest> scopedRequests = new ArrayList<ProfileChangeRequest>();
        for (ProfileChangeRequest req : requests) {
            if (req.getDepartmentName() != null && managedDepartmentSet.contains(req.getDepartmentName().trim())) {
                scopedRequests.add(req);
            }
        }
        requests = scopedRequests;

        int scopedPending = 0;
        for (ProfileChangeRequest req : dao.listByStatus("PENDING")) {
            if (req.getDepartmentName() != null && managedDepartmentSet.contains(req.getDepartmentName().trim())) {
                scopedPending++;
            }
        }
        pendingCount = scopedPending;
    } else {
        pendingCount = dao.countPending();
    }

    String msg = request.getParameter("msg");
    String error = request.getParameter("error");
    String bannerText = "";
    String bannerClass = "";

    if ("approved".equals(msg)) {
        bannerText = "Request approved and the employee's profile has been updated.";
        bannerClass = "page-success";
    } else if ("rejected".equals(msg)) {
        bannerText = "Request rejected.";
        bannerClass = "page-success";
    } else if ("conflict".equals(error)) {
        bannerText = "Could not approve: the requested value conflicts with an existing record (e.g. that email is already in use). Reject the request or ask the employee to resubmit.";
        bannerClass = "page-error";
    } else if ("already_reviewed".equals(error)) {
        bannerText = "That request was already reviewed by someone else.";
        bannerClass = "page-error";
    } else if ("invalid".equals(error) || "server".equals(error)) {
        bannerText = "Unable to process that request. Please try again.";
        bannerClass = "page-error";
    }
%>
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>IR-AMS Profile Change Requests</title>

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
                            <i class="fa-solid fa-user-pen"></i>
                            Employees Module · Profile Change Requests
                        </span>

                        <h1>Profile Change Requests</h1>

                        <p>
                            Review, approve, or reject profile field change requests submitted by ECoR railway
                            personnel. Approving a request immediately updates the employee's record.
                        </p>

                        <div class="employee-hero-pills">
                            <div class="employee-hero-pill"><i class="fa-solid fa-user-pen"></i> Self-Service Requests</div>
                            <div class="employee-hero-pill"><i class="fa-solid fa-hourglass-half"></i> <%= pendingCount %> Pending</div>
                            <div class="employee-hero-pill"><i class="fa-solid fa-envelope"></i> Email &amp; Phone Updates</div>
                            <div class="employee-hero-pill"><i class="fa-solid fa-user-shield"></i> Admin &amp; Dept Head Review</div>
                        </div>
                    </div>
                </section>

                <% if (!bannerText.isEmpty()) { %>
                    <div class="employee-message <%= "page-success".equals(bannerClass) ? "success" : "error" %>">
                        <i class="fa-solid <%= "page-success".equals(bannerClass) ? "fa-circle-check" : "fa-triangle-exclamation" %>"></i>
                        <%= HtmlEscapeUtil.escape(bannerText) %>
                    </div>
                <% } %>

                <section class="employee-control-panel">
                    <div class="employee-panel-head">
                        <div>
                            <h2>Requests</h2>
                            <p>
                                Current value vs. requested value shown side by side for review.
                            </p>
                        </div>

                        <div class="employee-toolbar">
                            <a href="user_profile_requests.jsp?status=PENDING" class="employee-btn <%= "PENDING".equals(statusFilter) ? "primary" : "" %>">Pending</a>
                            <a href="user_profile_requests.jsp?status=APPROVED" class="employee-btn <%= "APPROVED".equals(statusFilter) ? "primary" : "" %>">Approved</a>
                            <a href="user_profile_requests.jsp?status=REJECTED" class="employee-btn <%= "REJECTED".equals(statusFilter) ? "primary" : "" %>">Rejected</a>
                            <a href="user_profile_requests.jsp?status=ALL" class="employee-btn <%= "ALL".equals(statusFilter) ? "primary" : "" %>">All</a>
                        </div>
                    </div>

                    <% if (requests.isEmpty()) { %>
                        <div class="no-records-message">
                            <i class="fa-solid fa-circle-info"></i>
                            <strong>No matching profile requests found.</strong>
                        </div>
                    <% } else { %>
                        <div class="employee-table-wrap">
                            <table class="employee-table">
                                <colgroup>
                                    <col style="width: 7%;">
                                    <col style="width: 18%;">
                                    <col style="width: 10%;">
                                    <col style="width: 14%;">
                                    <col style="width: 14%;">
                                    <col style="width: 15%;">
                                    <col style="width: 10%;">
                                    <col style="width: 12%;">
                                </colgroup>
                                <thead>
                                    <tr>
                                        <th>Req ID</th>
                                        <th>Personnel Details</th>
                                        <th>Request Type</th>
                                        <th>Current Value</th>
                                        <th>Requested Value</th>
                                        <th>Reason</th>
                                        <th>Status</th>
                                        <th>Actions</th>
                                    </tr>
                                </thead>
                                <tbody>
                                    <% for (ProfileChangeRequest req : requests) {
                                        String statusPillClass = "APPROVED".equals(req.getStatus()) ? "success"
                                                : "REJECTED".equals(req.getStatus()) ? "danger" : "neutral";
                                    %>
                                        <tr>
                                            <td><span class="employee-main-text">#<%= req.getRequestId() %></span></td>
                                            <td>
                                                <div class="employee-identity">
                                                    <div class="employee-avatar">
                                                        <%= HtmlEscapeUtil.escape(initials(req.getEmployeeName())) %>
                                                    </div>
                                                    <div>
                                                        <strong><%= HtmlEscapeUtil.escape(req.getEmployeeName(), "N/A") %></strong>
                                                        <span><%= HtmlEscapeUtil.escape(req.getEmployeeCode(), "-") %></span>
                                                    </div>
                                                </div>
                                            </td>
                                            <td><span class="employee-main-text"><%= "email".equals(req.getFieldName()) ? "Email" : "Phone Number" %></span></td>
                                            <td><span class="employee-main-text"><%= HtmlEscapeUtil.escape(req.getCurrentValue(), "N/A") %></span></td>
                                            <td><span class="employee-main-text"><strong><%= HtmlEscapeUtil.escape(req.getRequestedValue(), "-") %></strong></span></td>
                                            <td><span class="employee-sub-text"><%= HtmlEscapeUtil.escape(req.getReason(), "-") %></span></td>
                                            <td>
                                                <span class="employee-status <%= statusPillClass %>">
                                                    <%= HtmlEscapeUtil.escape(req.getStatus()) %>
                                                </span>
                                                <% if (!"PENDING".equals(req.getStatus()) && req.getReviewedByUsername() != null && !req.getReviewedByUsername().isEmpty()) { %>
                                                    <br><span class="employee-sub-text">by <%= HtmlEscapeUtil.escape(req.getReviewedByUsername()) %></span>
                                                <% } %>
                                            </td>
                                            <td>
                                                <% if ("PENDING".equals(req.getStatus())) { %>
                                                    <div class="employee-action-grid">
                                                        <form method="post" action="ReviewProfileChangeRequestServlet" style="display:contents;">
                                                            <input type="hidden" name="requestId" value="<%= req.getRequestId() %>">
                                                            <input type="hidden" name="action" value="approve">
                                                            <button type="submit" class="employee-action-btn" style="border:none;" onclick="return confirm('Approve this request and update the employee record?');">
                                                                <i class="fa-solid fa-check"></i> Approve
                                                            </button>
                                                        </form>
                                                        <form method="post" action="ReviewProfileChangeRequestServlet" style="display:contents;">
                                                            <input type="hidden" name="requestId" value="<%= req.getRequestId() %>">
                                                            <input type="hidden" name="action" value="reject">
                                                            <button type="submit" class="employee-action-btn red" style="border:none;" onclick="return confirm('Reject this request?');">
                                                                <i class="fa-solid fa-xmark"></i> Reject
                                                            </button>
                                                        </form>
                                                    </div>
                                                <% } else { %>
                                                    <span class="employee-sub-text"><%= HtmlEscapeUtil.escape(req.getReviewedAt(), "-") %></span>
                                                <% } %>
                                            </td>
                                        </tr>
                                    <% } %>
                                </tbody>
                            </table>
                        </div>
                    <% } %>

                </section>

            </div>
        </div>

    </main>

</div>

<script src="js/topbar-search.js?v=28000"></script>
<script src="js/user-dropdown.js?v=28000"></script>
<script src="js/sidebar-role.js?v=28000"></script>
<script src="js/ir-body-watermark.js?v=28000"></script>
<script src="js/dashboard-actions.js?v=28000"></script>

</body>
</html>
