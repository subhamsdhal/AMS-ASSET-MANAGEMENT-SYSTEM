package com.mycompany.asset_management_system_ams;

import java.io.IOException;

import jakarta.servlet.ServletException;
import jakarta.servlet.annotation.WebServlet;
import jakarta.servlet.http.HttpServlet;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import jakarta.servlet.http.HttpSession;

/**
 * Checker stage of the disposal approval workflow (Approve/Reject a PENDING
 * asset_disposal proposal). Open to SUPER_ADMIN/ADMIN/ASSET_MANAGER, matching
 * the reviewer set for ReviewAssetTransferServlet. Note: ASSET_MANAGER is
 * also the role that submits proposals via
 * DisposeAssetServlet/dispose_asset.jsp, so this does not prevent a single
 * Asset Manager from proposing and then approving their own disposal - a
 * deliberate product choice; SUPER_ADMIN/ADMIN-only review (the original,
 * stricter design) is preserved in history if that separation is wanted
 * back. All idempotency/concurrency safety lives in
 * AssetDAO.reviewDisposal()'s own guarded UPDATE (WHERE disposal_status =
 * 'PENDING'), not a check-then-act pair here.
 */
@WebServlet(name = "ReviewAssetDisposalServlet", urlPatterns = {"/ReviewAssetDisposalServlet"})
public class ReviewAssetDisposalServlet extends HttpServlet {

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
                response.sendRedirect("asset_disposals.jsp?error=accessDenied");
                return;
            }

            int disposalId = parseIntSafe(request.getParameter("disposalId"), 0);
            String action = request.getParameter("action");
            String remarks = request.getParameter("remarks");

            boolean approve = "approve".equalsIgnoreCase(action);
            boolean reject = "reject".equalsIgnoreCase(action);

            if (disposalId <= 0 || (!approve && !reject)) {
                response.sendRedirect("asset_disposals.jsp?error=invalidRequest");
                return;
            }

            AssetDAO dao = new AssetDAO();
            int assetId = dao.getAssetIdByDisposalId(disposalId);

            boolean updated = dao.reviewDisposal(disposalId, approve ? "APPROVE" : "REJECT", userId, remarks);

            if (!updated) {
                response.sendRedirect("asset_disposals.jsp?error=reviewFailed");
                return;
            }

            String outcome = approve ? "APPROVED" : "REJECTED";

            if (approve && assetId > 0) {
                // Only now, on actual approval, does the asset really become
                // DISPOSED - keep the QR public snapshot in sync at the same
                // point the old single-actor disposeAsset() used to (mirrors
                // AddAssetRequestServlet/UpdateAssetServlet's own use of this
                // same quiet-sync helper after any asset_status change).
                QrSnapshotService.syncAssetQuietly(assetId);
            }

            safeAuditLog(
                    userId,
                    "DISPOSAL_" + outcome,
                    "assets",
                    assetId,
                    "Asset disposal " + outcome.toLowerCase() + " by " + username
            );

            sendReviewNotification(disposalId, assetId, approve);

            response.sendRedirect("asset_disposals.jsp?success=" + outcome.toLowerCase());

        } catch (Exception e) {
            e.printStackTrace();
            response.sendRedirect("asset_disposals.jsp?error=reviewFailed");
        }
    }

    private void sendReviewNotification(int disposalId, int assetId, boolean approve) {
        try {
            AssetDAO dao = new AssetDAO();
            String[] details = dao.getDisposalNotificationDetails(assetId);
            if (details == null) {
                return;
            }

            String assetCode = getArrayValue(details, 1, "N/A");
            String assetName = getArrayValue(details, 2, "N/A");
            String departmentName = getArrayValue(details, 14, "N/A");

            String notifyAction = approve ? "DISPOSED" : "DISPOSAL_REJECTED";
            NotificationEventService.EmailRouting routing = NotificationEventService.buildAssetRecipients(notifyAction, assetId);

            String subject = approve
                    ? "IR-AMS | Asset Disposal Approved | Asset #" + assetId
                    : "IR-AMS | Asset Disposal Rejected | Asset #" + assetId;

            String actionNote = approve
                    ? "This disposal proposal has been approved. The asset is now marked DISPOSED and its record is retained for audit history."
                    : "This disposal proposal has been rejected. The asset's status is unchanged. It may be resubmitted with updated details.";

            String detailsTable = "<tr><th>Disposal ID:</th><td>" + disposalId + "</td></tr>"
                    + "<tr><th>Asset:</th><td>" + HtmlEscapeUtil.escape(assetName) + " (" + HtmlEscapeUtil.escape(assetCode) + ")</td></tr>"
                    + "<tr><th>Department:</th><td>" + HtmlEscapeUtil.escape(departmentName) + "</td></tr>"
                    + "<tr><th>Outcome:</th><td>" + (approve ? "APPROVED / DISPOSED" : "REJECTED") + "</td></tr>";

            String body = NotificationHelper.buildHtmlEmail("", "Asset Disposal Review Outcome", detailsTable, actionNote);

            NotificationHelper.sendDisposalAlert(
                    getServletContext(),
                    assetId,
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
