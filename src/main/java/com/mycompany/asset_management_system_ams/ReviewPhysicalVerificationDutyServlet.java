package com.mycompany.asset_management_system_ams;

import java.io.IOException;
import java.sql.Connection;
import java.sql.PreparedStatement;

import jakarta.servlet.ServletException;
import jakarta.servlet.annotation.WebServlet;
import jakarta.servlet.http.HttpServlet;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import jakarta.servlet.http.HttpSession;

/**
 * Duty-level checker stage, separate from ReviewPhysicalVerificationServlet
 * (which approves/rejects one individual asset_physical_verification report).
 * A SUPER_ADMIN/ADMIN/ASSET_MANAGER reviews the officer's SUBMITTED duty as a
 * whole here, after using the existing per-report Approve/Reject flow on
 * whatever they need to check first:
 *
 *  - approve  -> duty_status = COMPLETED. The duty is done for good; it drops
 *                out of the officer's open-duty list (my_physical_verification_
 *                duties.jsp's openDutyList only ever shows SCHEDULED/
 *                IN_PROGRESS) and becomes pure history from here.
 *  - sendback -> duty_status = IN_PROGRESS. Reopens it for the same officer to
 *                add or correct reports and resubmit - no new duty_id, no data
 *                lost, same row.
 *
 * Both are guarded by an idempotency WHERE clause (duty_status = 'SUBMITTED'),
 * so a double-click or a stale replayed POST can never re-decide an
 * already-decided duty.
 */
@WebServlet(name = "ReviewPhysicalVerificationDutyServlet", urlPatterns = {"/ReviewPhysicalVerificationDutyServlet"})
public class ReviewPhysicalVerificationDutyServlet extends HttpServlet {

    @Override
    protected void doPost(HttpServletRequest request, HttpServletResponse response)
            throws ServletException, IOException {

        Connection con = null;

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

            boolean canManageVerification = "SUPER_ADMIN".equalsIgnoreCase(role)
                    || "ADMIN".equalsIgnoreCase(role)
                    || "ASSET_MANAGER".equalsIgnoreCase(role);

            if (!canManageVerification) {
                response.sendRedirect("physical_verification.jsp?error=accessDenied");
                return;
            }

            int dutyId = parseIntSafe(request.getParameter("dutyId"), 0);
            String action = request.getParameter("action");

            if (dutyId <= 0) {
                response.sendRedirect("physical_verification.jsp?error=invalidDuty");
                return;
            }

            boolean approve = "approve".equalsIgnoreCase(action);
            String newStatus = approve ? "COMPLETED" : "IN_PROGRESS";

            con = DBConnection.getConnection();
            con.setAutoCommit(false);

            String sql = "UPDATE physical_verification_duties "
                    + "SET duty_status = ? "
                    + "WHERE duty_id = ? AND duty_status = 'SUBMITTED'";

            int rowsUpdated;
            try (PreparedStatement ps = con.prepareStatement(sql)) {
                ps.setString(1, newStatus);
                ps.setInt(2, dutyId);
                rowsUpdated = ps.executeUpdate();
            }

            if (rowsUpdated == 0) {
                con.rollback();
                response.sendRedirect("physical_verification.jsp?error=reviewFailed");
                return;
            }

            con.commit();

            safeAuditLog(
                    userId,
                    approve ? "PHYSICAL_VERIFICATION_DUTY_APPROVED" : "PHYSICAL_VERIFICATION_DUTY_SENT_BACK",
                    "physical_verification_duties",
                    dutyId,
                    "Physical verification duty #" + dutyId
                    + (approve ? " approved and marked complete by " : " sent back to the officer by ")
                    + username
            );

            response.sendRedirect("physical_verification.jsp?success=" + (approve ? "dutyApproved" : "dutySentBack"));

        } catch (Exception e) {
            e.printStackTrace();

            try {
                if (con != null) {
                    con.rollback();
                }
            } catch (Exception rollbackEx) {
                rollbackEx.printStackTrace();
            }

            response.sendRedirect("physical_verification.jsp?error=reviewFailed");

        } finally {
            try {
                if (con != null) {
                    con.setAutoCommit(true);
                    con.close();
                }
            } catch (Exception closeEx) {
                closeEx.printStackTrace();
            }
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

    private int parseIntSafe(String value, int defaultValue) {
        try {
            if (value == null || value.trim().isEmpty()) {
                return defaultValue;
            }

            return Integer.parseInt(value.trim());
        } catch (Exception e) {
            return defaultValue;
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
