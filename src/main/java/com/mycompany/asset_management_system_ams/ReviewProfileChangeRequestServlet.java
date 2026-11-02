package com.mycompany.asset_management_system_ams;

import java.io.IOException;

import jakarta.servlet.ServletException;
import jakarta.servlet.annotation.WebServlet;
import jakarta.servlet.http.HttpServlet;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import jakarta.servlet.http.HttpSession;

/**
 * ReviewProfileChangeRequestServlet - approve/reject for a pending
 * ProfileChangeRequestDAO row. SUPER_ADMIN/ADMIN can review any request -
 * the same tier that already edits employee records directly elsewhere in
 * this app (UpdateEmployeeServlet), since approving one of these requests
 * has the same real-world effect as that direct edit. DEPARTMENT_HEAD can
 * also review, but only for employees in a department they head - enforced
 * below via EmployeeDAO.isEmployeeUnderDepartmentHead(), not just by what
 * user_profile_requests.jsp happens to display (that page's own department
 * filter is a display convenience, not the security boundary - the same
 * "JSP shows a filtered view, servlet re-checks independently" split this
 * app already uses for e.g. token validation in reset_password.jsp).
 */
@WebServlet(name = "ReviewProfileChangeRequestServlet", urlPatterns = {"/ReviewProfileChangeRequestServlet"})
public class ReviewProfileChangeRequestServlet extends HttpServlet {

    @Override
    protected void doPost(HttpServletRequest request, HttpServletResponse response)
            throws ServletException, IOException {

        request.setCharacterEncoding("UTF-8");

        HttpSession session = request.getSession(false);
        if (session == null || session.getAttribute("username") == null) {
            response.sendRedirect("login.jsp");
            return;
        }

        String role = String.valueOf(session.getAttribute("role"));
        boolean isSuperAdmin = "SUPER_ADMIN".equals(role) || "ADMIN".equals(role);
        boolean isDepartmentHead = "DEPARTMENT_HEAD".equals(role);
        if (!isSuperAdmin && !isDepartmentHead) {
            response.sendRedirect("dashboard.jsp?access=denied");
            return;
        }

        String username = String.valueOf(session.getAttribute("username"));
        int userId = getSessionUserId(session);

        int requestId = parseIntOrDefault(request.getParameter("requestId"), 0);
        String action = clean(request.getParameter("action"));
        String reviewNote = clean(request.getParameter("reviewNote"));

        if (requestId <= 0 || (!"approve".equals(action) && !"reject".equals(action))) {
            response.sendRedirect("user_profile_requests.jsp?error=invalid");
            return;
        }

        if (isDepartmentHead) {
            ProfileChangeRequestDAO scopeCheckDao = new ProfileChangeRequestDAO();
            Integer employeeId = scopeCheckDao.getEmployeeIdForRequest(requestId);
            if (employeeId == null || !new EmployeeDAO().isEmployeeUnderDepartmentHead(employeeId, userId)) {
                response.sendRedirect("user_profile_requests.jsp?error=already_reviewed");
                return;
            }
        }

        if (reviewNote.length() > 500) {
            reviewNote = reviewNote.substring(0, 500);
        }

        ProfileChangeRequestDAO dao = new ProfileChangeRequestDAO();

        if ("approve".equals(action)) {
            ProfileChangeRequestDAO.ApprovalResult result = dao.approve(requestId, userId, reviewNote);

            switch (result) {
                case SUCCESS:
                    AuditDAO.log(userId, "APPROVE_PROFILE_CHANGE", "profile_change_requests", requestId,
                            "Profile change request #" + requestId + " approved by " + username
                                    + (reviewNote.isEmpty() ? "" : ". Note: " + reviewNote));
                    response.sendRedirect("user_profile_requests.jsp?msg=approved");
                    return;
                case CONFLICT:
                    response.sendRedirect("user_profile_requests.jsp?error=conflict");
                    return;
                case NOT_FOUND_OR_ALREADY_REVIEWED:
                    response.sendRedirect("user_profile_requests.jsp?error=already_reviewed");
                    return;
                default:
                    response.sendRedirect("user_profile_requests.jsp?error=server");
                    return;
            }
        } else {
            boolean success = dao.reject(requestId, userId, reviewNote);
            if (!success) {
                response.sendRedirect("user_profile_requests.jsp?error=already_reviewed");
                return;
            }
            AuditDAO.log(userId, "REJECT_PROFILE_CHANGE", "profile_change_requests", requestId,
                    "Profile change request #" + requestId + " rejected by " + username
                            + (reviewNote.isEmpty() ? "" : ". Reason: " + reviewNote));
            response.sendRedirect("user_profile_requests.jsp?msg=rejected");
        }
    }

    private int getSessionUserId(HttpSession session) {
        Object userIdObj = session.getAttribute("user_id");
        if (userIdObj != null) {
            try {
                return Integer.parseInt(String.valueOf(userIdObj));
            } catch (Exception ignored) {
            }
        }
        return 0;
    }

    private int parseIntOrDefault(String value, int fallback) {
        if (value == null) {
            return fallback;
        }
        try {
            return Integer.parseInt(value.trim());
        } catch (Exception e) {
            return fallback;
        }
    }

    private String clean(String value) {
        return value == null ? "" : value.trim();
    }
}
