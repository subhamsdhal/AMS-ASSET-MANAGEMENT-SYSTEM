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

@WebServlet(name = "ChangePasswordServlet", urlPatterns = {"/ChangePasswordServlet"})
public class ChangePasswordServlet extends HttpServlet {

    @Override
    protected void doPost(HttpServletRequest request, HttpServletResponse response)
            throws ServletException, IOException {

        HttpSession session = request.getSession(false);
        if (session == null || session.getAttribute("user_id") == null) {
            response.sendRedirect("change_password.jsp?error=Session expired. Please login again.");
            return;
        }

        int userId = Integer.parseInt(session.getAttribute("user_id").toString());
        String username = (String) session.getAttribute("username");
        String role = (String) session.getAttribute("role");

        String currentPassword = request.getParameter("currentPassword");
        String newPassword = request.getParameter("newPassword");
        String confirmPassword = request.getParameter("confirmPassword");

        if (currentPassword == null || currentPassword.trim().isEmpty()
                || newPassword == null || newPassword.trim().isEmpty()
                || confirmPassword == null || confirmPassword.trim().isEmpty()) {
            response.sendRedirect("change_password.jsp?error=All password fields are required.");
            return;
        }

        if (!newPassword.equals(confirmPassword)) {
            response.sendRedirect("change_password.jsp?error=New password and confirm password do not match.");
            return;
        }

        if (newPassword.length() < 6) {
            response.sendRedirect("change_password.jsp?error=New password must be at least 6 characters.");
            return;
        }

        if (currentPassword.equals(newPassword)) {
            response.sendRedirect("change_password.jsp?error=New password cannot be same as current password.");
            return;
        }

        try (Connection con = DBConnection.getConnection()) {
            
            String storedPassword = null;
            try (PreparedStatement psCheck = con.prepareStatement("SELECT password_crypt FROM users WHERE user_id = ?")) {
                psCheck.setInt(1, userId);
                try (ResultSet rsCheck = psCheck.executeQuery()) {
                    if (rsCheck.next()) {
                        storedPassword = rsCheck.getString("password_crypt");
                    }
                }
            }

            if (storedPassword == null || !PasswordUtil.matches(currentPassword, storedPassword)) {
                response.sendRedirect("change_password.jsp?error=Current password is incorrect.");
                return;
            }

            // password_plaintext is never populated with the real password (security
            // fix, see CHANGELOG-fixes.md Login-2) - "" matches the convention already
            // used by AddEmployeeServlet for the same NOT NULL column.
            String updateQuery = "UPDATE users SET password_plaintext = ?, password_crypt = ?, force_password_change = 0 WHERE user_id = ?";

            try (PreparedStatement ps = con.prepareStatement(updateQuery)) {
                ps.setString(1, "");
                ps.setString(2, PasswordUtil.hash(newPassword));
                ps.setInt(3, userId);

                int updated = ps.executeUpdate();

                if (updated > 0) {
                    session.removeAttribute("force_password_change");

                    // Previously this ran a hand-written INSERT INTO audit_logs
                    // referencing columns (action, table_name, remarks) that do not
                    // exist on that table (see schema.sql - the real columns are
                    // action_type, module_name, action_details). That threw a
                    // SQLSyntaxErrorException on every single successful password
                    // change, which propagated to the outer catch below and sent the
                    // user to "Something went wrong while changing password" even
                    // though their password had already been updated - misleading,
                    // and exactly the scenario that would have hit every employee
                    // going through the (now-restored) forced first-login password
                    // change. AuditDAO.log() uses the real columns and is the same
                    // helper every other module already calls.
                    AuditDAO.log(
                            userId,
                            "PASSWORD_CHANGE",
                            "users",
                            userId,
                            "Password changed successfully by " + username
                    );

                    try {
                        String loginEmail = NotificationHelper.getUserEmailByUsername(username);
                        if (loginEmail != null && !loginEmail.trim().isEmpty()) {
                            String subject = "IR-AMS Password Changed Successfully";
                            String detailsTableHtml = "<tr><th>Username:</th><td>" + username + "</td></tr>"
                                    + "<tr><th>Status:</th><td>Password Changed</td></tr>";
                                    
                            String body = NotificationHelper.buildHtmlEmail(
                                    username,
                                    "Password Changed",
                                    detailsTableHtml,
                                    "Your password for the IR-AMS portal has been changed successfully. If you did not make this change, please contact your system administrator immediately."
                            );
                                    
                            NotificationEventService.EmailRouting routing = NotificationEventService.buildSettingsSecurityRecipients("PASSWORD_CHANGE", userId);
                            String toEmail = routing.getToEmail();
                            String ccEmail = routing.getCcEmail();

                            NotificationHelper.sendNotification(
                                    request.getServletContext(),
                                    "PASSWORD_CHANGE",
                                    NotificationHelper.MODULE_ADMIN_SECURITY,
                                    userId,
                                    toEmail,
                                    ccEmail,
                                    "",
                                    subject,
                                    body
                            );
                        }
                    } catch (Exception notifyEx) {
                        System.err.println("Failed to send password change email: " + notifyEx.getMessage());
                    }

                    // Fault: redirected with the full sentence "Password changed
                    // successfully." as the msg value, but employee_dashboard.jsp's
                    // banner only ever checked for the short token "password_changed"
                    // (a value this never actually sent) - so a real, successful
                    // password change showed no confirmation at all, for any role.
                    // dashboard.jsp (non-employee roles) didn't even read a msg
                    // parameter to begin with, so it had no banner to show regardless
                    // of what value was sent. Standardized on the short token
                    // employee_dashboard.jsp already expected, and added the matching
                    // banner to dashboard.jsp below.
                    if ("EMPLOYEE".equalsIgnoreCase(role)) {
                        response.sendRedirect("employee_dashboard.jsp?msg=password_changed");
                    } else {
                        response.sendRedirect("dashboard.jsp?msg=password_changed");
                    }
                } else {
                    response.sendRedirect("change_password.jsp?error=Failed to update password. Please try again.");
                }
            }
        } catch (Exception e) {
            e.printStackTrace();
            System.err.println("Error changing password for user " + username + ": " + e.getMessage());
            response.sendRedirect("change_password.jsp?error=Something went wrong while changing password.");
        }
    }
}
