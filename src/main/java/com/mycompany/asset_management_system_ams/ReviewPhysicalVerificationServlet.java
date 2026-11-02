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

@WebServlet(name = "ReviewPhysicalVerificationServlet", urlPatterns = {"/ReviewPhysicalVerificationServlet"})
public class ReviewPhysicalVerificationServlet extends HttpServlet {

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

            int verificationId = parseIntSafe(request.getParameter("verificationId"), 0);
            String action = request.getParameter("action");
            String remarks = request.getParameter("remarks");

            if (verificationId <= 0) {
                response.sendRedirect("physical_verification.jsp?error=invalidId");
                return;
            }

            String reviewStatus = "approve".equalsIgnoreCase(action) ? "APPROVED" : "REJECTED";

            con = DBConnection.getConnection();
            con.setAutoCommit(false);

            // Idempotency / concurrency guard: only apply the review decision while
            // the record is still SUBMITTED - matches view_verification.jsp's own
            // gate, which only shows the Approve/Reject buttons when reviewStatus is
            // SUBMITTED. Without this, two asset managers reviewing the same
            // verification at close to the same time (or a stale/replayed
            // Approve/Reject POST) could silently flip an already-decided record
            // again. Same idempotency pattern used for asset request approvals
            // (AssetRequestDAO.updateRequestStatus) and role-duty deactivation
            // (RoleAssignmentDAO.deactivateAssignment).
            //
            // Fault (Critical, fixed): this used to compare against the literal
            // string 'PENDING', a value that does not exist in this column's enum
            // (schema.sql defines review_status as an enum of SUBMITTED/REVIEWED/
            // APPROVED/REJECTED, defaulting to SUBMITTED) - so this WHERE clause
            // could never match any real row, rowsUpdated was always 0, and the
            // entire Approve/Reject workflow was unreachable regardless of session
            // validity or role. view_verification.jsp's button-visibility check had
            // the identical mismatch, so the buttons never even rendered. Both are
            // now keyed on the enum's actual initial value.
            String sql = "UPDATE asset_physical_verification SET review_status = ?";
            if (remarks != null && !remarks.trim().isEmpty()) {
                sql += ", remarks = CONCAT(IFNULL(remarks, ''), '\n[Review]: ', ?) ";
            }
            sql += " WHERE verification_id = ? AND review_status = 'SUBMITTED'";

            int rowsUpdated;
            try (PreparedStatement ps = con.prepareStatement(sql)) {
                ps.setString(1, reviewStatus);
                if (remarks != null && !remarks.trim().isEmpty()) {
                    ps.setString(2, remarks.trim());
                    ps.setInt(3, verificationId);
                } else {
                    ps.setInt(2, verificationId);
                }
                rowsUpdated = ps.executeUpdate();
            }

            if (rowsUpdated == 0) {
                con.rollback();
                response.sendRedirect("view_verification.jsp?id=" + verificationId + "&error=reviewFailed");
                return;
            }

            con.commit();

            safeAuditLog(
                    userId,
                    "PHYSICAL_VERIFICATION_" + reviewStatus,
                    "asset_physical_verification",
                    verificationId,
                    "Physical verification " + reviewStatus.toLowerCase() + " by " + username
            );

            response.sendRedirect("view_verification.jsp?id=" + verificationId + "&success=" + reviewStatus.toLowerCase());

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
        // Default of 0 (not 1) on a missing session attribute - defaulting to 1
        // would silently mis-attribute this Approve/Reject audit-log entry to
        // whichever real account happens to be user_id 1 instead of showing an
        // unknown actor. Same fix applied across the Asset Requests module.
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
