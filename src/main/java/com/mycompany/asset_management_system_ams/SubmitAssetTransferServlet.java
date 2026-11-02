package com.mycompany.asset_management_system_ams;

import java.io.IOException;
import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;

import jakarta.servlet.ServletException;
import jakarta.servlet.annotation.WebServlet;
import jakarta.servlet.http.HttpServlet;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import jakarta.servlet.http.HttpSession;

/**
 * Maker stage of the employee-to-employee transfer workflow. An EMPLOYEE may
 * only submit for their own allocation (verified server-side against the
 * session's linked employee_id, never trusted from the form); ops roles
 * (SUPER_ADMIN/ADMIN/ASSET_MANAGER/AUDITOR/DEPARTMENT_HEAD) may submit for
 * any employee, mirroring AddAssetRequestServlet's own on-behalf-of pattern.
 * All ownership/state validation happens inside AssetTransferDAO.submitTransfer().
 */
@WebServlet(name = "SubmitAssetTransferServlet", urlPatterns = {"/SubmitAssetTransferServlet"})
public class SubmitAssetTransferServlet extends HttpServlet {

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

            boolean isOpsRole = "SUPER_ADMIN".equalsIgnoreCase(role) || "ADMIN".equalsIgnoreCase(role)
                    || "ASSET_MANAGER".equalsIgnoreCase(role) || "AUDITOR".equalsIgnoreCase(role)
                    || "DEPARTMENT_HEAD".equalsIgnoreCase(role);
            boolean isEmployee = "EMPLOYEE".equalsIgnoreCase(role);

            if (!isOpsRole && !isEmployee) {
                response.sendRedirect("employee_assets.jsp?error=accessDenied");
                return;
            }

            int allocationId = parseIntSafe(request.getParameter("allocationId"), 0);
            int toEmployeeId = parseIntSafe(request.getParameter("toEmployeeId"), 0);
            String reason = request.getParameter("transferReason");

            if (isEmployee) {
                // The allocation must belong to the linked employee's own
                // records - re-derived from the session, never trusted from
                // the posted allocationId alone, so an employee can never
                // submit a transfer request against someone else's allocation
                // by guessing/tampering with the form's hidden field.
                int linkedEmployeeId = getLinkedEmployeeId(userId);
                if (linkedEmployeeId <= 0 || !allocationBelongsToEmployee(allocationId, linkedEmployeeId)) {
                    response.sendRedirect("employee_assets.jsp?error=accessDenied");
                    return;
                }
            }

            if (allocationId <= 0 || toEmployeeId <= 0) {
                response.sendRedirect(isEmployee ? "employee_assets.jsp?error=invalidRequest" : "allocation.jsp?error=invalidRequest");
                return;
            }

            AssetTransferDAO dao = new AssetTransferDAO();
            int requestId = dao.submitTransfer(allocationId, toEmployeeId, reason, userId);

            if (requestId <= 0) {
                response.sendRedirect((isEmployee ? "employee_assets.jsp" : "allocation.jsp")
                        + "?error=transferFailed");
                return;
            }

            AuditDAO.log(
                    userId,
                    "ASSET_TRANSFER_SUBMITTED",
                    "asset_transfer_requests",
                    requestId,
                    "Asset transfer requested (allocation #" + allocationId + " -> employee #" + toEmployeeId
                    + ") by " + username
            );

            sendSubmitNotification(requestId);

            response.sendRedirect((isEmployee ? "employee_assets.jsp" : "allocation.jsp") + "?success=transferSubmitted");

        } catch (Exception e) {
            e.printStackTrace();
            response.sendRedirect("employee_assets.jsp?error=server");
        }
    }

    private void sendSubmitNotification(int requestId) {
        try {
            AssetTransferDAO dao = new AssetTransferDAO();
            java.util.List<java.util.Map<String, String>> pending = dao.getPendingTransfers();
            java.util.Map<String, String> details = null;
            for (java.util.Map<String, String> row : pending) {
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
            String toEmail = assetManagerEmail;
            String ccEmail = NotificationEventService.buildCc("", toEmail, superAdminEmail);

            String subject = "IR-AMS | Asset Transfer Requested | Request #" + requestId;
            String detailsTable = "<tr><th>Request ID:</th><td>" + requestId + "</td></tr>"
                    + "<tr><th>Asset:</th><td>" + HtmlEscapeUtil.escape(details.get("asset_name")) + " (" + HtmlEscapeUtil.escape(details.get("asset_code")) + ")</td></tr>"
                    + "<tr><th>From:</th><td>" + HtmlEscapeUtil.escape(details.get("from_name")) + " (" + HtmlEscapeUtil.escape(details.get("from_code")) + ")</td></tr>"
                    + "<tr><th>To:</th><td>" + HtmlEscapeUtil.escape(details.get("to_name")) + " (" + HtmlEscapeUtil.escape(details.get("to_code")) + ")</td></tr>"
                    + "<tr><th>Reason:</th><td>" + HtmlEscapeUtil.escape(details.get("transfer_reason")) + "</td></tr>";

            String actionNote = "This transfer request is awaiting review. Please log in to IR-AMS to approve or reject it.";
            String body = NotificationHelper.buildHtmlEmail("", "Asset Transfer Requested", detailsTable, actionNote);

            NotificationHelper.sendAssetRequestAlert(getServletContext(), requestId, toEmail, ccEmail, "", subject, body);
        } catch (Exception e) {
            e.printStackTrace();
        }
    }

    private boolean allocationBelongsToEmployee(int allocationId, int employeeId) {
        if (allocationId <= 0) {
            return false;
        }
        String sql = "SELECT allocation_id FROM asset_allocation WHERE allocation_id = ? AND employee_id = ?";
        try (Connection con = DBConnection.getConnection();
             PreparedStatement ps = con.prepareStatement(sql)) {
            ps.setInt(1, allocationId);
            ps.setInt(2, employeeId);
            try (ResultSet rs = ps.executeQuery()) {
                return rs.next();
            }
        } catch (Exception e) {
            e.printStackTrace();
            return false;
        }
    }

    private int getLinkedEmployeeId(int userId) {
        if (userId <= 0) {
            return 0;
        }
        String sql = "SELECT employee_id FROM users WHERE user_id = ? AND employee_id IS NOT NULL";
        try (Connection con = DBConnection.getConnection();
             PreparedStatement ps = con.prepareStatement(sql)) {
            ps.setInt(1, userId);
            try (ResultSet rs = ps.executeQuery()) {
                if (rs.next()) {
                    return rs.getInt("employee_id");
                }
            }
        } catch (Exception e) {
            e.printStackTrace();
        }
        return 0;
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
