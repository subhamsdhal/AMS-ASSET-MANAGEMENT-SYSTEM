<%@page contentType="text/html" pageEncoding="UTF-8"%>
<%@page import="com.mycompany.asset_management_system_ams.AssetRequest"%>
<%@page import="com.mycompany.asset_management_system_ams.AssetRequestDAO"%>
<%@page import="com.mycompany.asset_management_system_ams.HtmlEscapeUtil"%>
<%@page import="java.util.List"%>

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

    // Same double-layered RBAC pattern used everywhere else in this app:
    // RoleAccessUtil's ROLE_MAP already gates this path to ADMIN/DEPARTMENT_HEAD
    // (SUPER_ADMIN implicit) at the filter level; this is the per-page re-check.
    boolean canReview = "SUPER_ADMIN".equals(role) || "ADMIN".equals(role) || "DEPARTMENT_HEAD".equals(role);
    if (!canReview) {
        response.sendRedirect("dashboard.jsp?access=denied");
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

    AssetRequestDAO dao = new AssetRequestDAO();
    // Scoped structurally by the DAO's own JOIN (department_head_user_id = ?),
    // not by anything computed here - an ADMIN/SUPER_ADMIN visiting this page
    // without also being set as a department's head simply sees an empty list,
    // which is correct: this queue belongs to the Department Head role.
    List<AssetRequest> requestList = dao.getRequestsPendingForDeptHead(userId);

    String success = request.getParameter("success");
    String error = request.getParameter("error");
%>

<!DOCTYPE html>
<html>
<head>
    <title>Department Head Review Queue - IR-AMS</title>

    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.0/css/all.min.css">

    <link rel="stylesheet" href="css/ir-glass.css?v=28000">
    <link rel="stylesheet" href="css/ams-pro.css?v=28000">
    <link rel="stylesheet" href="css/ir-ams-railway-ui.css?v=28000">
    <link rel="stylesheet" href="css/asset_requests.css?v=topbarfix1">
</head>

<body class="railway-ui">

<div class="app ams-shell">

    <jsp:include page="sidebar.jsp" />

    <main class="main railway-main">
        <jsp:include page="topbar.jsp" />

        <div class="main-scroll-content">

            <section class="request-hero">
                <div class="request-hero-copy">
                    <h1>Department Head Review Queue</h1>

                    <p>
                        Employee asset requests from your department awaiting your review before they reach
                        the Asset Manager for final approval.
                    </p>

                    <div class="hero-pills">
                        <div class="hero-pill">
                            <i class="fa-solid fa-user-clock"></i> Awaiting Your Review
                        </div>
                        <div class="hero-pill">
                            <i class="fa-solid fa-share"></i> Forward to Asset Manager
                        </div>
                        <div class="hero-pill">
                            <i class="fa-solid fa-ban"></i> Reject at Source
                        </div>
                    </div>
                </div>
            </section>

            <% if ("forwarded".equals(success)) { %>
                <div class="page-success">
                    <i class="fa-solid fa-circle-check"></i>
                    Request forwarded to the Asset Manager for approval.
                </div>
            <% } else if ("rejected".equals(success)) { %>
                <div class="page-success">
                    <i class="fa-solid fa-circle-check"></i>
                    Request rejected.
                </div>
            <% } else if ("accessDenied".equals(error)) { %>
                <div class="page-error">
                    <i class="fa-solid fa-triangle-exclamation"></i>
                    Access denied. You do not have permission to perform this action.
                </div>
            <% } else if ("invalidRequest".equals(error)) { %>
                <div class="page-error">
                    <i class="fa-solid fa-triangle-exclamation"></i>
                    Invalid request selected.
                </div>
            <% } else if ("reviewFailed".equals(error)) { %>
                <div class="page-error">
                    <i class="fa-solid fa-triangle-exclamation"></i>
                    This request could not be reviewed. It may already have been forwarded, rejected,
                    or does not belong to your department.
                </div>
            <% } %>

            <section class="glass-panel">

                <div class="registry-toolbar">
                    <div>
                        <h2>Requests Awaiting Your Review</h2>
                        <p class="table-subtext">
                            Showing <%= requestList.size() %> request(s) pending Department Head review.
                        </p>
                    </div>
                </div>

                <div class="registry-table-wrap">

                    <table class="asset-table" id="deptHeadRequestTable">
                        <thead>
                            <tr>
                                <th>Request ID</th>
                                <th>Employee</th>
                                <th>Employee Code</th>
                                <th>Requested Category</th>
                                <th>Request Date</th>
                                <th>Remarks</th>
                                <th>Control Actions</th>
                            </tr>
                        </thead>

                        <tbody>
                            <% if (requestList.isEmpty()) { %>
                                <tr>
                                    <td colspan="7" style="text-align:center; padding: 24px;">
                                        <i class="fa-solid fa-circle-info"></i>
                                        No requests are currently awaiting your review.
                                    </td>
                                </tr>
                            <% } %>

                            <% for (AssetRequest req : requestList) { %>
                            <tr>
                                <td>
                                    <span class="request-id-pill">REQ-<%= req.getRequestId() %></span>
                                </td>

                                <td>
                                    <strong><%= HtmlEscapeUtil.escape(req.getEmployeeName()) %></strong>
                                </td>

                                <td><%= HtmlEscapeUtil.escape(req.getEmployeeCode()) %></td>

                                <td>
                                    <span class="category-pill"><%= HtmlEscapeUtil.escape(req.getCategoryName()) %></span>
                                </td>

                                <td><%= HtmlEscapeUtil.escape(req.getRequestDate()) %></td>

                                <td><%= req.getRemarks() == null ? "-" : HtmlEscapeUtil.escape(req.getRemarks()) %></td>

                                <td>
                                    <div class="request-actions">

                                        <a href="view_request.jsp?id=<%= req.getRequestId() %>"
                                           class="asset-action-btn inspect-btn" title="Review request details">
                                            <i class="fa-solid fa-eye"></i> View
                                        </a>

                                        <form method="post" action="ReviewAssetRequestByDeptHeadServlet" style="display:inline;"
                                              onsubmit="return confirm('Forward this request to the Asset Manager for approval?');">
                                            <input type="hidden" name="requestId" value="<%= req.getRequestId() %>">
                                            <input type="hidden" name="action" value="forward">
                                            <button type="submit" class="asset-action-btn custody-btn" style="border:none; cursor:pointer;" title="Forward to Asset Manager">
                                                <i class="fa-solid fa-share"></i> Forward
                                            </button>
                                        </form>

                                        <form method="post" action="ReviewAssetRequestByDeptHeadServlet" style="display:inline;"
                                              onsubmit="return confirm('Reject this asset request?');">
                                            <input type="hidden" name="requestId" value="<%= req.getRequestId() %>">
                                            <input type="hidden" name="action" value="reject">
                                            <button type="submit" class="asset-action-btn qr-btn" style="border:none; cursor:pointer;" title="Reject request">
                                                <i class="fa-solid fa-ban"></i> Reject
                                            </button>
                                        </form>

                                    </div>
                                </td>
                            </tr>
                            <% } %>
                        </tbody>
                    </table>

                </div>

            </section>

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
