package com.mycompany.asset_management_system_ams;

import java.io.IOException;
import java.net.URLEncoder;
import java.nio.charset.StandardCharsets;

import jakarta.servlet.ServletException;
import jakarta.servlet.annotation.WebServlet;
import jakarta.servlet.http.HttpServlet;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import jakarta.servlet.http.HttpSession;

@WebServlet(name = "SendTestEmailServlet", urlPatterns = {"/SendTestEmailServlet"})
public class SendTestEmailServlet extends HttpServlet {

    @Override
    protected void doPost(HttpServletRequest request, HttpServletResponse response)
            throws ServletException, IOException {

        HttpSession session = request.getSession(false);

        if (session == null
                || session.getAttribute("username") == null
                || session.getAttribute("role") == null) {

            response.sendRedirect("login.jsp");
            return;
        }

        String role = String.valueOf(session.getAttribute("role"));

        if (!("SUPER_ADMIN".equals(role) || "ADMIN".equals(role))) {
            response.sendRedirect("settings.jsp?access=denied");
            return;
        }

        String username = String.valueOf(session.getAttribute("username"));
        int userId = 0;

        try {
            // Was reading session attribute "userId" - LoginServlet (the only place
            // that ever sets it) uses "user_id". userId was always 0 here for every
            // real user, misattributing the audit/notification record for every test
            // email ever sent through this page.
            Object sessionUserId = session.getAttribute("user_id");

            if (sessionUserId != null) {
                userId = Integer.parseInt(String.valueOf(sessionUserId));
            }
        } catch (Exception ignored) {
            userId = 0;
        }

        String toEmail = clean(request.getParameter("toEmail"));
        String subject = clean(request.getParameter("subject"));
        String messageBody = clean(request.getParameter("messageBody"));

        if (toEmail.isEmpty() || subject.isEmpty() || messageBody.isEmpty()) {
            response.sendRedirect("test_email.jsp?error=invalid");
            return;
        }

        try {
            System.out.println("==================================================");
            System.out.println("IR-AMS EMAIL TEST STARTED");
            System.out.println("Receiver Email: " + toEmail);
            System.out.println("Subject: " + subject);
            System.out.println("Triggered By: " + username);
            System.out.println("==================================================");

            NotificationService.sendEmail(getServletContext(), toEmail, subject, messageBody);

            try {
                AuditDAO.log(
                        userId,
                        "SEND_EMAIL",
                        "notification_settings",
                        1,
                        "Test Gmail email sent by " + username + " to " + toEmail
                );
            } catch (Exception auditException) {
                System.out.println("IR-AMS EMAIL SENT, BUT AUDIT LOG FAILED:");
                System.err.println(auditException.getMessage());
            }

            System.out.println("==================================================");
            System.out.println("IR-AMS EMAIL TEST SUCCESS");
            System.out.println("Sent To: " + toEmail);
            System.out.println("==================================================");

            String encodedEmail = URLEncoder.encode(toEmail, StandardCharsets.UTF_8.toString());
            response.sendRedirect("test_email.jsp?msg=sent&toEmail=" + encodedEmail);

        } catch (Exception e) {

            System.out.println("==================================================");
            System.out.println("IR-AMS EMAIL TEST FAILED");
            System.out.println("REAL EMAIL ERROR BELOW:");
            System.err.println(e.getMessage());
            System.out.println("==================================================");

            response.sendRedirect("test_email.jsp?error=server");
        }
    }

    private String clean(String value) {
        if (value == null) {
            return "";
        }

        return value.trim();
    }
}