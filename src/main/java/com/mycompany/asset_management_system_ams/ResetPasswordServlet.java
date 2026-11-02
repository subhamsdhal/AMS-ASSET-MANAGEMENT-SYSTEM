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

/**
 * ResetPasswordServlet — completes BOTH the "Forgot password?" reset flow
 * AND the "Sign up" account-activation flow. Both end the same way (the
 * visitor proves ownership of a valid token and chooses a password), so
 * they share this one servlet; token_type only changes the confirmation
 * copy/redirect. reset_password.jsp renders the form and does its own
 * read-only token check for display purposes, but this servlet re-validates
 * the token from scratch server-side before writing anything — the JSP's
 * check is a UX convenience, not the security boundary.
 */
@WebServlet(name = "ResetPasswordServlet", urlPatterns = {"/ResetPasswordServlet"})
public class ResetPasswordServlet extends HttpServlet {

    private static final int MIN_PASSWORD_LENGTH = 6;

    @Override
    protected void doGet(HttpServletRequest request, HttpServletResponse response)
            throws ServletException, IOException {
        String token = request.getParameter("token");
        response.sendRedirect("reset_password.jsp?token=" + (token == null ? "" : token));
    }

    @Override
    protected void doPost(HttpServletRequest request, HttpServletResponse response)
            throws ServletException, IOException {

        String token = request.getParameter("token");
        String newPassword = request.getParameter("newPassword");
        String confirmPassword = request.getParameter("confirmPassword");

        String tokenParamForRedirect = token == null ? "" : token;

        if (newPassword == null || newPassword.isEmpty()
                || confirmPassword == null || confirmPassword.isEmpty()) {
            response.sendRedirect("reset_password.jsp?token=" + tokenParamForRedirect + "&error=required");
            return;
        }

        if (!newPassword.equals(confirmPassword)) {
            response.sendRedirect("reset_password.jsp?token=" + tokenParamForRedirect + "&error=mismatch");
            return;
        }

        if (newPassword.length() < MIN_PASSWORD_LENGTH) {
            response.sendRedirect("reset_password.jsp?token=" + tokenParamForRedirect + "&error=short");
            return;
        }

        try (Connection con = DBConnection.getConnection()) {

            if (con == null) {
                response.sendRedirect("reset_password.jsp?token=" + tokenParamForRedirect + "&error=server");
                return;
            }

            PasswordResetDAO.ensureTable(con);

            PasswordResetDAO.ResolvedToken resolved = PasswordResetDAO.resolveValidToken(con, token, null);

            if (resolved == null) {
                response.sendRedirect("forgot_password.jsp?error=invalid_token");
                return;
            }

            String username = null;
            String email = null;
            try (PreparedStatement ps = con.prepareStatement("SELECT username, email FROM users WHERE user_id = ?")) {
                ps.setInt(1, resolved.userId);
                try (ResultSet rs = ps.executeQuery()) {
                    if (rs.next()) {
                        username = rs.getString("username");
                        email = rs.getString("email");
                    }
                }
            }

            if (username == null) {
                response.sendRedirect("forgot_password.jsp?error=invalid_token");
                return;
            }

            String updateSql = "UPDATE users SET password_plaintext = '', password_crypt = ?, force_password_change = 0 WHERE user_id = ?";
            try (PreparedStatement ps = con.prepareStatement(updateSql)) {
                ps.setString(1, PasswordUtil.hash(newPassword));
                ps.setInt(2, resolved.userId);
                ps.executeUpdate();
            }

            PasswordResetDAO.markTokenUsed(con, resolved.tokenId);

            boolean isActivation = PasswordResetDAO.TYPE_ACTIVATION.equals(resolved.tokenType);

            String action = isActivation ? "ACCOUNT_ACTIVATED" : "PASSWORD_RESET_COMPLETED";
            String remark = isActivation
                    ? "Account activated and password set via email link for " + username
                    : "Password reset via email link for " + username;

            try {
                AuditDAO.log(resolved.userId, action, "users", resolved.userId, remark);
            } catch (Exception auditEx) {
                auditEx.printStackTrace();
            }

            sendConfirmationEmail(username, email, isActivation);

            response.sendRedirect("login.jsp?msg=" + (isActivation ? "account_activated" : "password_reset_success"));

        } catch (Exception e) {
            e.printStackTrace();
            response.sendRedirect("reset_password.jsp?token=" + tokenParamForRedirect + "&error=server");
        }
    }

    private void sendConfirmationEmail(String username, String email, boolean isActivation) {
        if (email == null || email.trim().isEmpty()) {
            return;
        }

        String subject = isActivation
                ? "IR-AMS | Your Account Is Ready"
                : "IR-AMS | Password Changed Successfully";

        String detailsTable = "<tr><th>Username:</th><td>" + username + "</td></tr>"
                + "<tr><th>Status:</th><td>" + (isActivation ? "Account Activated" : "Password Changed") + "</td></tr>";

        String actionNote = isActivation
                ? "Your IR-AMS account is ready to use. If you did not request this, contact your system administrator immediately."
                : "Your password for the IR-AMS portal has been changed successfully. If you did not make this change, please contact your system administrator immediately.";

        String body = NotificationHelper.buildHtmlEmail(username, isActivation ? "Account Activated" : "Password Changed", detailsTable, actionNote);

        NotificationHelper.sendNotification(
                getServletContext(),
                isActivation ? "ACCOUNT_ACTIVATED" : "PASSWORD_CHANGE",
                NotificationHelper.MODULE_ADMIN_SECURITY,
                null,
                email,
                "",
                "",
                subject,
                body
        );
    }
}
