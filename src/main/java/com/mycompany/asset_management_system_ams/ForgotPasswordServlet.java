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
 * ForgotPasswordServlet — handles the "Forgot password?" request step.
 *
 * Security notes:
 *  - Always redirects to the same "check your email" confirmation whether or
 *    not the identifier matched a real account. Branching the visible
 *    response on match/no-match would let this endpoint be used to
 *    enumerate valid usernames/emails.
 *  - The reset link is only ever emailed to the address already on file for
 *    that account (users.email) — never to an address supplied on this form
 *    — so this cannot be used to redirect a reset to an attacker-controlled
 *    inbox.
 *  - Requests are throttled per account (see MAX_REQUESTS_PER_WINDOW) so
 *    this can't be turned into a mail-bomb against a real user's inbox.
 */
@WebServlet(name = "ForgotPasswordServlet", urlPatterns = {"/ForgotPasswordServlet"})
public class ForgotPasswordServlet extends HttpServlet {

    private static final int RESET_TOKEN_VALID_MINUTES = 30;
    private static final int MAX_REQUESTS_PER_WINDOW = 3;
    private static final int REQUEST_WINDOW_MINUTES = 15;

    @Override
    protected void doGet(HttpServletRequest request, HttpServletResponse response)
            throws ServletException, IOException {
        response.sendRedirect("forgot_password.jsp");
    }

    @Override
    protected void doPost(HttpServletRequest request, HttpServletResponse response)
            throws ServletException, IOException {

        String identifierInput = request.getParameter("identifier");
        String identifier = identifierInput == null ? "" : identifierInput.trim();

        if (identifier.isEmpty()) {
            response.sendRedirect("forgot_password.jsp?error=required");
            return;
        }

        try (Connection con = DBConnection.getConnection()) {

            if (con == null) {
                response.sendRedirect("forgot_password.jsp?error=server");
                return;
            }

            PasswordResetDAO.ensureTable(con);

            Integer userId = null;
            String username = null;
            String email = null;

            String sql = "SELECT user_id, username, email FROM users WHERE (username = ? OR email = ?) AND status = 'ACTIVE'";
            try (PreparedStatement ps = con.prepareStatement(sql)) {
                ps.setString(1, identifier);
                ps.setString(2, identifier);
                try (ResultSet rs = ps.executeQuery()) {
                    if (rs.next()) {
                        userId = rs.getInt("user_id");
                        username = rs.getString("username");
                        email = rs.getString("email");
                    }
                }
            }

            String clientIp = RequestUtil.getClientIpAddress(request);

            if (userId != null && email != null && !email.trim().isEmpty()) {

                int recentRequests = PasswordResetDAO.countRecentTokens(con, userId, PasswordResetDAO.TYPE_RESET, REQUEST_WINDOW_MINUTES);

                if (recentRequests < MAX_REQUESTS_PER_WINDOW) {
                    sendResetEmail(request, con, userId, username, email, clientIp);

                    try {
                        AuditDAO.log(userId, "PASSWORD_RESET_REQUESTED", "users", userId,
                                "Password reset link requested for " + username + ". Source IP: " + clientIp);
                    } catch (Exception auditEx) {
                        auditEx.printStackTrace();
                    }
                }
                // Else: already at the request cap for this window — dropped silently.
                // Not surfaced to the caller, so this can't become a second
                // identifier-enumeration side channel via response timing/content.
            }

            // Identical outcome whether or not the identifier matched an account.
            response.sendRedirect("forgot_password.jsp?sent=1");

        } catch (Exception e) {
            e.printStackTrace();
            response.sendRedirect("forgot_password.jsp?error=server");
        }
    }

    private void sendResetEmail(HttpServletRequest request, Connection con, int userId, String username, String email, String clientIp) {

        String rawToken = PasswordResetDAO.createToken(con, userId, PasswordResetDAO.TYPE_RESET, RESET_TOKEN_VALID_MINUTES, clientIp);

        if (rawToken == null) {
            return;
        }

        String resetLink = RequestUtil.buildAppBaseUrl(request) + "/reset_password.jsp?token=" + rawToken;

        String subject = "IR-AMS | Password Reset Requested";

        String detailsTable = "<tr><th>Account:</th><td>" + escape(username) + "</td></tr>"
                + "<tr><th>Requested From IP:</th><td>" + escape(clientIp) + "</td></tr>"
                + "<tr><th>Link Expires:</th><td>" + RESET_TOKEN_VALID_MINUTES + " minutes from now</td></tr>";

        String actionNote = "<p>Click the button below to choose a new password. "
                + "If you did not request this, you can safely ignore this email — your password will not be changed.</p>"
                + "<p style='text-align:center;margin:24px 0;'>"
                + "<a href='" + resetLink + "' style='background:#08348f;color:#fff;padding:12px 28px;border-radius:8px;text-decoration:none;font-weight:700;display:inline-block;'>Reset Your Password</a>"
                + "</p>"
                + "<p style='font-size:12px;color:#6b7280;word-break:break-all;'>Or copy this link into your browser: " + resetLink + "</p>";

        String body = NotificationHelper.buildHtmlEmail(username, "Password Reset Requested", detailsTable, actionNote);

        NotificationHelper.sendNotification(
                getServletContext(),
                "PASSWORD_RESET_REQUEST",
                NotificationHelper.MODULE_ADMIN_SECURITY,
                userId,
                email,
                "",
                "",
                subject,
                body
        );
    }

    private String escape(String value) {
        if (value == null) {
            return "N/A";
        }
        return value.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;");
    }
}
