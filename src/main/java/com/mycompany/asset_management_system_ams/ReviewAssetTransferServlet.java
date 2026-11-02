package com.mycompany.asset_management_system_ams;

import java.io.IOException;
import java.util.List;
import java.util.Map;

import jakarta.servlet.ServletException;
import jakarta.servlet.annotation.WebServlet;
import jakarta.servlet.http.HttpServlet;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import jakarta.servlet.http.HttpSession;

/**
 * Checker stage of the employee-to-employee transfer workflow (Approve/
 * Reject a PENDING asset_transfer_requests row). Gated to assetOps (SUPER_
 * ADMIN/ADMIN/ASSET_MANAGER) - the same tier that already manages allocations
 * generally - via RoleAccessUtil; EMPLOYEE, the maker role for a
 * self-submitted request, is structurally excluded from review since it
 * isn't in assetOps at all. All idempotency/concurrency safety lives in
 * AssetTransferDAO.reviewTransfer()'s own guarded transaction, not a
 * check-then-act pair here.
 */
@WebServlet(name = "ReviewAssetTransferServlet", urlPatterns = {"/ReviewAssetTransferServlet"})
public class ReviewAssetTransferServlet extends HttpServlet {

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

            boolean canReview = "SUPER_ADMIN".equalsIgnoreCase(role) || "ADMIN".equalsIgnoreCase(role)
                    || "ASSET_MANAGER".equalsIgnoreCase(role);
            if (!canReview) {
                response.sendRedirect("asset_transfers.jsp?error=accessDenied");
                return;
            }

            int requestId = parseIntSafe(request.getParameter("requestId"), 0);
            String action = request.getParameter("action");
            String remarks = request.getParameter("remarks");

            boolean approve = "approve".equalsIgnoreCase(action);
            boolean reject = "reject".equalsIgnoreCase(action);

            if (requestId <= 0 || (!approve && !reject)) {
                response.sendRedirect("asset_transfers.jsp?error=invalidRequest");
                return;
            }

            AssetTransferDAO dao = new AssetTransferDAO();
            boolean updated = dao.reviewTransfer(requestId, approve ? "APPROVE" : "REJECT", userId, remarks);

            if (!updated) {
                response.sendRedirect("asset_transfers.jsp?error=reviewFailed");
                return;
            }

            String outcome = approve ? "COMPLETED" : "REJECTED";

            AuditDAO.log(
                    userId,
                    "ASSET_TRANSFER_" + outcome,
                    "asset_transfer_requests",
                    requestId,
                    "Asset transfer request " + outcome.toLowerCase() + " by " + username
            );

            sendReviewNotification(requestId, approve);

            response.sendRedirect("asset_transfers.jsp?success=" + outcome.toLowerCase());

        } catch (Exception e) {
            e.printStackTrace();
            response.sendRedirect("asset_transfers.jsp?error=reviewFailed");
        }
    }

    private void sendReviewNotification(int requestId, boolean approve) {
        try {
            AssetTransferDAO dao = new AssetTransferDAO();
            List<Map<String, String>> all = dao.getAllTransferRequests();
            Map<String, String> details = null;
            for (Map<String, String> row : all) {
                if (String.valueOf(requestId).equals(row.get("request_id"))) {
                    details = row;
                    break;
                }
            }
            if (details == null) {
                return;
            }

            String assetManagerEmail = NotificationRecipientResolver.getPrimaryEmailByRole("ASSET_MANAGER");
            String superAdminEmail = NotificationRecipientResolver.getPrimaryEmailByRole("SUPER_ADMIN");

            String subject = approve
                    ? "IR-AMS | Asset Transfer Approved | Request #" + requestId
                    : "IR-AMS | Asset Transfer Rejected | Request #" + requestId;

            String actionNote = approve
                    ? "This transfer has been approved and completed. The receiving employee now holds this asset."
                    : "This transfer request has been rejected. The asset remains with its current holder.";

            String detailsTable = "<tr><th>Request ID:</th><td>" + requestId + "</td></tr>"
                    + "<tr><th>Asset:</th><td>" + HtmlEscapeUtil.escape(details.get("asset_name")) + " (" + HtmlEscapeUtil.escape(details.get("asset_code")) + ")</td></tr>"
                    + "<tr><th>From:</th><td>" + HtmlEscapeUtil.escape(details.get("from_name")) + "</td></tr>"
                    + "<tr><th>To:</th><td>" + HtmlEscapeUtil.escape(details.get("to_name")) + "</td></tr>"
                    + "<tr><th>Outcome:</th><td>" + (approve ? "APPROVED / COMPLETED" : "REJECTED") + "</td></tr>";

            String body = NotificationHelper.buildHtmlEmail("", "Asset Transfer Review Outcome", detailsTable, actionNote);

            // Routed to the ops tier only, not to the two employees directly -
            // getAllTransferRequests()'s row set carries employee names but
            // not employee_id/employee_code, and resolving an email by name
            // would be unreliable. Consistent with how other lifecycle
            // outcome notices in this module (allocation, disposal) default
            // to Asset Manager/Super Admin when no employee_id is on hand.
            String toEmail = assetManagerEmail;
            String ccEmail = NotificationEventService.buildCc("", toEmail, superAdminEmail);

            NotificationHelper.sendAssetRequestAlert(getServletContext(), requestId, toEmail, ccEmail, "", subject, body);
        } catch (Exception e) {
            e.printStackTrace();
        }
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
}
