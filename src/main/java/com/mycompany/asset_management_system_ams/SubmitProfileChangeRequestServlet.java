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
 * SubmitProfileChangeRequestServlet - an employee requesting their own
 * email or phone number be changed. Never writes to the employees table
 * directly - only queues a PENDING row an admin must approve
 * (ReviewProfileChangeRequestServlet). Field whitelist is enforced in
 * ProfileChangeRequestDAO.ALLOWED_FIELDS, not just here.
 */
@WebServlet(name = "SubmitProfileChangeRequestServlet", urlPatterns = {"/SubmitProfileChangeRequestServlet"})
public class SubmitProfileChangeRequestServlet extends HttpServlet {

    @Override
    protected void doPost(HttpServletRequest request, HttpServletResponse response)
            throws ServletException, IOException {

        request.setCharacterEncoding("UTF-8");

        HttpSession session = request.getSession(false);
        Object employeeIdObj = session == null ? null : session.getAttribute("employee_id");

        if (session == null || session.getAttribute("username") == null || employeeIdObj == null) {
            response.sendRedirect("login.jsp");
            return;
        }

        int employeeId;
        try {
            employeeId = Integer.parseInt(String.valueOf(employeeIdObj));
        } catch (Exception e) {
            response.sendRedirect("login.jsp");
            return;
        }

        String username = String.valueOf(session.getAttribute("username"));
        int userId = getSessionUserId(session);

        String fieldName = clean(request.getParameter("fieldName"));
        String requestedValue = clean(request.getParameter("requestedValue"));
        String reason = clean(request.getParameter("reason"));

        if (!ProfileChangeRequestDAO.ALLOWED_FIELDS.contains(fieldName)) {
            response.sendRedirect("employee_profile.jsp?error=invalid_field");
            return;
        }

        if (requestedValue.isEmpty()) {
            response.sendRedirect("employee_profile.jsp?error=missing_value");
            return;
        }

        if ("email".equals(fieldName)) {
            if (requestedValue.length() > 120 || !requestedValue.matches("^[A-Za-z0-9+_.-]+@[A-Za-z0-9.-]+$")) {
                response.sendRedirect("employee_profile.jsp?error=invalid_email");
                return;
            }
        } else if ("phone".equals(fieldName)) {
            String validated = PhoneValidationUtil.validatePhone(requestedValue);
            if (validated == null) {
                response.sendRedirect("employee_profile.jsp?error=invalid_phone");
                return;
            }
            requestedValue = validated;
        }

        if (reason.length() > 500) {
            reason = reason.substring(0, 500);
        }

        ProfileChangeRequestDAO dao = new ProfileChangeRequestDAO();

        if (dao.hasPendingRequest(employeeId, fieldName)) {
            response.sendRedirect("employee_profile.jsp?error=already_pending");
            return;
        }

        String currentValue = getCurrentValue(employeeId, fieldName);

        if (currentValue != null && currentValue.equalsIgnoreCase(requestedValue)) {
            response.sendRedirect("employee_profile.jsp?error=no_change");
            return;
        }

        boolean success = dao.submitRequest(employeeId, fieldName, currentValue, requestedValue, reason);

        if (!success) {
            response.sendRedirect("employee_profile.jsp?error=server");
            return;
        }

        AuditDAO.log(userId, "REQUEST_PROFILE_CHANGE", "profile_change_requests", employeeId,
                "Profile change requested by " + username + ". Field: " + fieldName
                        + ", Current: " + (currentValue == null || currentValue.isEmpty() ? "N/A" : currentValue)
                        + ", Requested: " + requestedValue);

        response.sendRedirect("employee_profile.jsp?msg=request_submitted");
    }

    private String getCurrentValue(int employeeId, String fieldName) {
        // fieldName is whitelist-checked by the caller before this is ever
        // reached (ProfileChangeRequestDAO.ALLOWED_FIELDS is exactly
        // {"email", "phone"}), so this string-built column name is never
        // user-controlled despite not being a bind parameter.
        String sql = "SELECT " + fieldName + " FROM employees WHERE employee_id = ?";
        try (Connection con = DBConnection.getConnection();
             PreparedStatement ps = con.prepareStatement(sql)) {
            ps.setInt(1, employeeId);
            try (ResultSet rs = ps.executeQuery()) {
                if (rs.next()) {
                    return rs.getString(1);
                }
            }
        } catch (Exception e) {
            // fall through - treated as "no current value on record"
        }
        return null;
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

    private String clean(String value) {
        return value == null ? "" : value.trim();
    }
}
