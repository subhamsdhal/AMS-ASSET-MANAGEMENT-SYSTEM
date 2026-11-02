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
 * Self-service "I'm done" step for a physical verification officer. Separate
 * from AddPhysicalVerificationServlet's own action=submit (which only fires
 * alongside a specific asset in that request) so an officer who already
 * submitted every asset they were assigned across several earlier draft
 * batches can close the duty out without being forced to pick one more asset
 * just to have a submit button to click.
 *
 * Only moves a duty from IN_PROGRESS to SUBMITTED - a duty still SCHEDULED
 * (zero reports saved yet) is rejected with a clear error rather than being
 * allowed to jump straight to "awaiting review" with nothing in it.
 * SUBMITTED is deliberately not the end of the line: a SUPER_ADMIN/ADMIN/
 * ASSET_MANAGER reviewer (ReviewPhysicalVerificationDutyServlet) still has to
 * approve it to COMPLETED, or send it back to IN_PROGRESS for revision -
 * this servlet only ever hands the duty off for that review, it never closes
 * it itself.
 */
@WebServlet(name = "CompletePhysicalVerificationDutyServlet", urlPatterns = {"/CompletePhysicalVerificationDutyServlet"})
public class CompletePhysicalVerificationDutyServlet extends HttpServlet {

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
            int userId = getSessionUserId(session);
            int selfEmployeeId = getSessionEmployeeId(session);

            int dutyId = parseIntSafe(request.getParameter("dutyId"), 0);

            if (dutyId <= 0 || selfEmployeeId <= 0) {
                response.sendRedirect("my_physical_verification_duties.jsp?error=invalidDuty");
                return;
            }

            con = DBConnection.getConnection();
            con.setAutoCommit(false);

            int dutyOfficerEmployeeId = getDutyOfficerEmployeeId(con, dutyId);

            if (dutyOfficerEmployeeId <= 0 || dutyOfficerEmployeeId != selfEmployeeId) {
                con.rollback();
                response.sendRedirect("my_physical_verification_duties.jsp?error=accessDenied");
                return;
            }

            String currentStatus = getDutyStatus(con, dutyId);

            if ("SCHEDULED".equals(currentStatus)) {
                con.rollback();
                response.sendRedirect("my_physical_verification_duties.jsp?error=noReportsYet");
                return;
            }

            if ("SUBMITTED".equals(currentStatus) || "COMPLETED".equals(currentStatus)) {
                con.rollback();
                response.sendRedirect("my_physical_verification_duties.jsp?error=alreadySubmitted");
                return;
            }

            if ("CANCELLED".equals(currentStatus)) {
                con.rollback();
                response.sendRedirect("my_physical_verification_duties.jsp?error=dutyCancelled");
                return;
            }

            // Idempotency guard, same pattern used across every other
            // approve/reject workflow in this app (asset disposal, asset
            // transfer, physical verification report review): the WHERE
            // clause re-checks the expected prior state, so a double-click or
            // a stale replayed POST can never move an already-moved duty
            // again.
            String sql = "UPDATE physical_verification_duties "
                    + "SET duty_status = 'SUBMITTED' "
                    + "WHERE duty_id = ? AND duty_status = 'IN_PROGRESS'";

            int rowsUpdated;
            try (PreparedStatement ps = con.prepareStatement(sql)) {
                ps.setInt(1, dutyId);
                rowsUpdated = ps.executeUpdate();
            }

            if (rowsUpdated == 0) {
                con.rollback();
                response.sendRedirect("my_physical_verification_duties.jsp?error=submitFailed");
                return;
            }

            con.commit();

            safeAuditLog(
                    userId,
                    "PHYSICAL_VERIFICATION_DUTY_SUBMITTED",
                    "physical_verification_duties",
                    dutyId,
                    "Physical verification duty #" + dutyId + " marked complete and submitted for review by " + username
            );

            response.sendRedirect("my_physical_verification_duties.jsp?success=dutySubmitted");

        } catch (Exception e) {
            e.printStackTrace();

            try {
                if (con != null) {
                    con.rollback();
                }
            } catch (Exception rollbackEx) {
                rollbackEx.printStackTrace();
            }

            response.sendRedirect("my_physical_verification_duties.jsp?error=saveFailed");

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

    private int getDutyOfficerEmployeeId(Connection con, int dutyId) throws Exception {
        String sql = "SELECT assigned_employee_id FROM physical_verification_duties WHERE duty_id = ?";

        try (PreparedStatement ps = con.prepareStatement(sql)) {
            ps.setInt(1, dutyId);

            try (ResultSet rs = ps.executeQuery()) {
                if (rs.next()) {
                    return rs.getInt("assigned_employee_id");
                }
            }
        }

        return 0;
    }

    private String getDutyStatus(Connection con, int dutyId) throws Exception {
        String sql = "SELECT duty_status FROM physical_verification_duties WHERE duty_id = ?";

        try (PreparedStatement ps = con.prepareStatement(sql)) {
            ps.setInt(1, dutyId);

            try (ResultSet rs = ps.executeQuery()) {
                if (rs.next()) {
                    String status = rs.getString("duty_status");
                    return status == null ? "" : status.trim().toUpperCase();
                }
            }
        }

        return "";
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

    private int getSessionEmployeeId(HttpSession session) {
        try {
            Object employeeIdObj = session.getAttribute("employee_id");

            if (employeeIdObj == null) {
                return 0;
            }

            return Integer.parseInt(String.valueOf(employeeIdObj));
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
