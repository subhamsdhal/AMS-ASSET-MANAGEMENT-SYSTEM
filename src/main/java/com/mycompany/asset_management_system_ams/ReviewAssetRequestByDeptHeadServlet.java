package com.mycompany.asset_management_system_ams;

import java.io.IOException;

import jakarta.servlet.ServletException;
import jakarta.servlet.annotation.WebServlet;
import jakarta.servlet.http.HttpServlet;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import jakarta.servlet.http.HttpSession;

/**
 * The Department Head's own review stage for an employee's asset request,
 * kept as a separate servlet from UpdateRequestStatusServlet rather than a
 * branch inside it - mirroring this codebase's existing Physical
 * Verification Submit/Review split (PhysicalVerificationServlet vs.
 * ReviewPhysicalVerificationServlet), one servlet per distinct actor stage.
 *
 * Forward -> request_status becomes PENDING, handed off to the Asset
 * Manager/Admin/Super Admin exactly like a request that started there.
 * Reject -> request_status becomes REJECTED, ending the request; it never
 * reaches the Asset Manager queue.
 *
 * Ownership + idempotency/concurrency safety both live in
 * AssetRequestDAO.forwardOrRejectByDeptHead()'s single guarded UPDATE
 * (department_id must belong to a department this exact user_id heads, and
 * request_status must still be PENDING_DEPT_HEAD) rather than a
 * check-then-act pair here, closing the TOCTOU window that pattern would
 * otherwise leave open.
 */
@WebServlet(name = "ReviewAssetRequestByDeptHeadServlet", urlPatterns = {"/ReviewAssetRequestByDeptHeadServlet"})
public class ReviewAssetRequestByDeptHeadServlet extends HttpServlet {

    @Override
    protected void doPost(HttpServletRequest request, HttpServletResponse response)
            throws ServletException, IOException {

        try {
            request.setCharacterEncoding("UTF-8");
            HttpSession session = request.getSession(false);

            if (session == null || session.getAttribute("username") == null || session.getAttribute("role") == null) {
                response.sendRedirect("login.jsp");
                return;
            }

            String username = String.valueOf(session.getAttribute("username"));
            String role = String.valueOf(session.getAttribute("role"));
            int userId = getSessionUserId(session);

            // Double-layered RBAC: RoleAccessUtil's ROLE_MAP already gates
            // /ReviewAssetRequestByDeptHeadServlet to SUPER_ADMIN/ADMIN/
            // DEPARTMENT_HEAD at the filter level; this re-check is the same
            // per-servlet defense-in-depth every write servlet in this
            // codebase applies. Only DEPARTMENT_HEAD actually has requests
            // routed to it by forwardOrRejectByDeptHead()'s ownership guard -
            // SUPER_ADMIN/ADMIN pass this check but the DAO's WHERE clause
            // (department_head_user_id = their own user_id) will simply
            // affect 0 rows for them unless they are also literally set as a
            // department's head, which is the correct behavior: this stage
            // belongs to the Department Head, Super Admin/Admin access here
            // is an emergency-override path only, not a routine one.
            boolean canReview = "SUPER_ADMIN".equalsIgnoreCase(role)
                    || "ADMIN".equalsIgnoreCase(role)
                    || "DEPARTMENT_HEAD".equalsIgnoreCase(role);

            if (!canReview) {
                response.sendRedirect("dept_head_asset_requests.jsp?error=accessDenied");
                return;
            }

            int requestId = parseIntSafe(request.getParameter("requestId"), 0);
            String action = request.getParameter("action");
            String remarks = request.getParameter("remarks");

            boolean forward = "forward".equalsIgnoreCase(action);
            boolean reject = "reject".equalsIgnoreCase(action);

            if (requestId <= 0 || (!forward && !reject)) {
                response.sendRedirect("dept_head_asset_requests.jsp?error=invalidRequest");
                return;
            }

            AssetRequestDAO dao = new AssetRequestDAO();
            boolean updated = dao.forwardOrRejectByDeptHead(
                    requestId,
                    forward ? "FORWARD" : "REJECT",
                    userId,
                    remarks
            );

            if (!updated) {
                // Either this request no longer belongs to this Department
                // Head's own department, or it has already moved past
                // PENDING_DEPT_HEAD (already reviewed, or was never routed
                // through this stage). Either way this is a safe no-op, not
                // a partial write.
                response.sendRedirect("dept_head_asset_requests.jsp?error=reviewFailed");
                return;
            }

            String reviewAction = forward ? "FORWARDED" : "REJECTED";

            safeAuditLog(
                    userId,
                    "ASSET_REQUEST_DEPT_HEAD_" + reviewAction,
                    "asset_requests",
                    requestId,
                    "Asset request " + reviewAction.toLowerCase() + " by Department Head " + username
            );

            sendReviewNotification(requestId, forward);

            response.sendRedirect("dept_head_asset_requests.jsp?success=" + reviewAction.toLowerCase());

        } catch (Exception e) {
            e.printStackTrace();
            response.sendRedirect("dept_head_asset_requests.jsp?error=reviewFailed");
        }
    }

    private void sendReviewNotification(int requestId, boolean forward) {
        try {
            AssetRequestDAO dao = new AssetRequestDAO();
            String[] details = dao.getRequestNotificationDetails(requestId);
            if (details == null) {
                return;
            }

            int employeeId = dao.getEmployeeIdByRequestId(requestId);
            String employeeName = getArrayValue(details, 1, "Employee");
            String employeeCode = getArrayValue(details, 2, "N/A");
            String categoryName = getArrayValue(details, 3, "Requested Asset Category");
            String departmentName = getArrayValue(details, 9, "N/A");
            String currentStatus = getArrayValue(details, 5, forward ? "PENDING" : "REJECTED");

            String notifyAction = forward ? "FORWARDED" : "DEPT_HEAD_REJECTED";
            NotificationEventService.EmailRouting routing = NotificationEventService.buildAssetRequestRecipients(notifyAction, employeeId);

            String subject = forward
                    ? "Asset Request Forwarded for Approval - Request #" + requestId
                    : "Asset Request Rejected by Department Head - Request #" + requestId;

            String actionNote = forward
                    ? "This request has been reviewed and forwarded by the Department Head for Asset Manager approval."
                    : "This request has been rejected by the Department Head and will not proceed further.";

            String detailsTable = "<tr><th>Request ID:</th><td>" + requestId + "</td></tr>"
                    + "<tr><th>Employee:</th><td>" + employeeName + " (" + employeeCode + ")</td></tr>"
                    + "<tr><th>Department:</th><td>" + departmentName + "</td></tr>"
                    + "<tr><th>Requested Category:</th><td>" + categoryName + "</td></tr>"
                    + "<tr><th>Current Status:</th><td>" + currentStatus + "</td></tr>";

            String body = NotificationHelper.buildHtmlEmail("Asset Manager", "Asset Request Update", detailsTable,
                    actionNote + "<br><br>Please log in to IR-AMS for further review or action.");

            NotificationHelper.sendAssetRequestAlert(
                    getServletContext(),
                    requestId,
                    routing.getToEmail(),
                    routing.getCcEmail(),
                    "",
                    subject,
                    body
            );
        } catch (Exception e) {
            e.printStackTrace();
        }
    }

    private String getArrayValue(String[] array, int index, String fallback) {
        if (array == null || index < 0 || index >= array.length || array[index] == null || array[index].trim().isEmpty()) {
            return fallback;
        }
        return array[index].trim();
    }

    private int parseIntSafe(String value, int defaultValue) {
        if (value == null || value.trim().isEmpty()) {
            return defaultValue;
        }
        try {
            return Integer.parseInt(value.trim());
        } catch (NumberFormatException e) {
            return defaultValue;
        }
    }

    private int getSessionUserId(HttpSession session) {
        try {
            Object userIdObj = session.getAttribute("user_id");
            if (userIdObj == null) {
                userIdObj = session.getAttribute("userId");
            }
            if (userIdObj == null) {
                return 0;
            }
            return Integer.parseInt(String.valueOf(userIdObj));
        } catch (Exception e) {
            return 0;
        }
    }

    private void safeAuditLog(int userId, String action, String tableName, int recordId, String description) {
        try {
            AuditDAO.log(userId, action, tableName, recordId, description);
        } catch (Exception e) {
            e.printStackTrace();
        }
    }
}
