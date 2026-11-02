package com.mycompany.asset_management_system_ams;

import java.sql.Connection;
import java.sql.PreparedStatement;
import java.util.Properties;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.logging.Level;
import java.util.logging.Logger;

import jakarta.mail.Authenticator;
import jakarta.mail.Message;
import jakarta.mail.PasswordAuthentication;
import jakarta.mail.Session;
import jakarta.mail.Transport;
import jakarta.mail.internet.InternetAddress;
import jakarta.mail.internet.MimeMessage;

/**
 * EmailService — Sends Gmail SMTP emails for Railway AMS.
 * Reads configuration from system_settings via SettingsDAO.
 * Non-blocking: uses a background thread pool.
 * Logs every send attempt to email_logs table.
 * Safe: never crashes the app if SMTP is not configured.
 */
public class EmailService {

    private static final Logger LOGGER = Logger.getLogger(EmailService.class.getName());

    private static final ExecutorService EMAIL_POOL = Executors.newFixedThreadPool(3, r -> {
        Thread t = new Thread(r, "IR-AMS-Mailer");
        t.setDaemon(true);
        return t;
    });

    // -------------------------------------------------------
    // Public API
    // -------------------------------------------------------

    /**
     * Send an email asynchronously.
     * Returns immediately; actual send happens in background thread.
     */
    public static void sendAsync(String toEmail, String subject, String htmlBody) {
        sendAsync(toEmail, subject, htmlBody, 0);
    }

    public static void sendAsync(String toEmail, String subject, String htmlBody, int sentBy) {
        if (toEmail == null || toEmail.trim().isEmpty()) {
            LOGGER.info("EmailService.sendAsync skipped: no recipient.");
            return;
        }

        EMAIL_POOL.submit(() -> {
            boolean success = sendNow(toEmail, subject, htmlBody);
            logEmail(toEmail, subject, htmlBody, success ? "SENT" : "FAILED", null, sentBy);
        });
    }

    /**
     * Send synchronously. Returns true if sent, false if failed or not configured.
     */
    public static boolean sendNow(String toEmail, String subject, String htmlBody) {
        if (!SettingsDAO.isSmtpEnabled()) {
            LOGGER.info("EmailService: SMTP disabled. Email not sent to " + toEmail);
            return false;
        }

        String smtpUser = SettingsDAO.getSmtpUsername();
        String smtpPass = SettingsDAO.getSmtpPassword();
        String smtpHost = SettingsDAO.getSmtpHost();
        int smtpPort = SettingsDAO.getSmtpPort();
        String senderName = SettingsDAO.getSmtpSenderName();

        if (smtpUser.isEmpty() || smtpPass.isEmpty()) {
            LOGGER.warning("EmailService: SMTP credentials not configured.");
            return false;
        }

        try {
            Properties props = new Properties();
            props.put("mail.smtp.auth", "true");
            props.put("mail.smtp.starttls.enable", SettingsDAO.isSmtpTls() ? "true" : "false");
            props.put("mail.smtp.host", smtpHost);
            props.put("mail.smtp.port", String.valueOf(smtpPort));
            props.put("mail.smtp.ssl.protocols", "TLSv1.2");
            props.put("mail.smtp.connectiontimeout", "10000");
            props.put("mail.smtp.timeout", "10000");

            final String finalUser = smtpUser;
            final String finalPass = smtpPass;

            Session session = Session.getInstance(props, new Authenticator() {
                @Override
                protected PasswordAuthentication getPasswordAuthentication() {
                    return new PasswordAuthentication(finalUser, finalPass);
                }
            });

            MimeMessage message = new MimeMessage(session);
            message.setFrom(new InternetAddress(smtpUser, senderName));
            message.setRecipients(Message.RecipientType.TO, InternetAddress.parse(toEmail));

            String replyTo = SettingsDAO.getSmtpReplyTo();
            if (!replyTo.isEmpty()) {
                message.setReplyTo(InternetAddress.parse(replyTo));
            }

            message.setSubject(subject, "UTF-8");
            message.setContent(wrapHtml(htmlBody), "text/html; charset=UTF-8");

            Transport.send(message);
            LOGGER.info("EmailService: Email sent successfully to " + toEmail);
            return true;

        } catch (Exception e) {
            LOGGER.log(Level.SEVERE, "EmailService: Failed to send email to " + toEmail, e);
            return false;
        }
    }

    /**
     * Test connection — send a test email.
     */
    public static String testSmtpConnection(String testRecipient) {
        if (testRecipient == null || testRecipient.trim().isEmpty()) {
            return "{\"status\":\"error\", \"error\":\"Invalid recipient email address.\"}";
        }

        String smtpUser = SettingsDAO.getSmtpUsername();
        String smtpPass = SettingsDAO.getSmtpPassword();
        String smtpHost = SettingsDAO.getSmtpHost();
        int smtpPort = SettingsDAO.getSmtpPort();
        boolean tls = SettingsDAO.isSmtpTls();

        System.out.println("[SMTP_TEST] started");
        System.out.println("[SMTP_TEST] recipient = " + testRecipient);
        System.out.println("[SMTP_TEST] host = " + smtpHost);
        System.out.println("[SMTP_TEST] port = " + smtpPort);
        System.out.println("[SMTP_TEST] tls = " + tls);
        System.out.println("[SMTP_TEST] username = " + smtpUser);
        System.out.println("[SMTP_TEST] password configured = " + (!smtpPass.isEmpty()));

        if (smtpPass.isEmpty()) {
            System.out.println("[SMTP_TEST] failed: No password - SMTP password/app password is not configured.");
            return "{\"status\":\"error\", \"error\":\"SMTP password/app password is not configured.\"}";
        }

        try {
            Properties props = new Properties();
            props.put("mail.smtp.auth", "true");
            props.put("mail.smtp.starttls.enable", tls ? "true" : "false");
            props.put("mail.smtp.host", smtpHost);
            props.put("mail.smtp.port", String.valueOf(smtpPort));
            props.put("mail.smtp.ssl.trust", smtpHost);
            props.put("mail.smtp.connectiontimeout", "10000");
            props.put("mail.smtp.timeout", "10000");
            props.put("mail.smtp.writetimeout", "10000");

            Session session = Session.getInstance(props, new Authenticator() {
                @Override
                protected PasswordAuthentication getPasswordAuthentication() {
                    return new PasswordAuthentication(smtpUser, smtpPass);
                }
            });

            MimeMessage message = new MimeMessage(session);
            message.setFrom(new InternetAddress(smtpUser, SettingsDAO.getSmtpSenderName()));
            message.setRecipients(Message.RecipientType.TO, InternetAddress.parse(testRecipient));
            
            String replyTo = SettingsDAO.getSmtpReplyTo();
            if (!replyTo.isEmpty()) {
                message.setReplyTo(InternetAddress.parse(replyTo));
            }

            String subject = "[IR-AMS] Email Configuration Test — " + SettingsDAO.getOrgName();
            String body = "<h2>✅ Email Configuration Successful</h2>"
                    + "<p>This is a test email from <strong>" + SettingsDAO.getSystemName() + "</strong>.</p>"
                    + "<p>Your Gmail SMTP is configured correctly for IR-AMS notifications.</p>"
                    + "<hr><p style='color:#888;font-size:12px;'>East Coast Railway — Rail Sadan, Bhubaneswar</p>";

            message.setSubject(subject, "UTF-8");
            message.setContent(wrapHtml(body), "text/html; charset=UTF-8");

            System.out.println("[SMTP_TEST] Transport.send started");
            Transport.send(message);
            System.out.println("[SMTP_TEST] Transport.send success");
            return "{\"status\":\"ok\"}";
            
        } catch (jakarta.mail.AuthenticationFailedException e) {
            System.out.println("[SMTP_TEST] failed: " + e.getClass().getName() + " - " + e.getMessage());
            return "{\"status\":\"error\", \"error\":\"SMTP authentication failed. Use Gmail App Password, not normal Gmail password.\"}";
        } catch (jakarta.mail.MessagingException e) {
            System.out.println("[SMTP_TEST] failed: " + e.getClass().getName() + " - " + e.getMessage());
            return "{\"status\":\"error\", \"error\":\"SMTP connection failed. Check host, port, TLS and internet.\"}";
        } catch (Exception e) {
            System.out.println("[SMTP_TEST] failed: " + e.getClass().getName() + " - " + e.getMessage());
            return "{\"status\":\"error\", \"error\":\"SMTP connection failed. Check host, port, TLS and internet.\"}";
        }
    }

    // -------------------------------------------------------
    // Email Templates
    // -------------------------------------------------------

    /**
     * Welcome email for new employee with login credentials.
     */
    public static void sendEmployeeWelcomeEmail(
            String toEmail, String employeeName, String employeeCode,
            String username, String tempPassword, String role, String departmentName) {

        String subject = "Welcome to IR-AMS — Your Login Credentials | " + SettingsDAO.getOrgName();
        String body = "<div style='font-family:Segoe UI,Arial,sans-serif;max-width:600px;margin:0 auto;border:1px solid #e0e8f5;border-radius:12px;overflow:hidden;'>"
                + "<div style='background:linear-gradient(135deg,#08348f,#0b4db8);padding:28px 32px;color:white;'>"
                + "<div style='font-size:22px;font-weight:900;letter-spacing:0.5px;'>🚂 IR-AMS — " + SettingsDAO.getOrgName() + "</div>"
                + "<div style='font-size:13px;opacity:0.85;margin-top:4px;'>Indian Railway Asset Management System</div>"
                + "</div>"
                + "<div style='padding:32px;background:#ffffff;'>"
                + "<h2 style='color:#08348f;margin-top:0;'>Welcome, " + employeeName + "!</h2>"
                + "<p style='color:#374151;'>Your employee account has been created in the Railway Asset Management System. Below are your login credentials:</p>"
                + "<div style='background:#f0f7ff;border-left:4px solid #08348f;border-radius:8px;padding:20px 24px;margin:20px 0;'>"
                + "<table style='width:100%;border-collapse:collapse;'>"
                + "<tr><td style='color:#6b7280;padding:6px 0;font-size:13px;'>Employee Code</td><td style='font-weight:700;color:#111827;'>" + employeeCode + "</td></tr>"
                + "<tr><td style='color:#6b7280;padding:6px 0;font-size:13px;'>Department</td><td style='font-weight:700;color:#111827;'>" + departmentName + "</td></tr>"
                + "<tr><td style='color:#6b7280;padding:6px 0;font-size:13px;'>Role</td><td style='font-weight:700;color:#111827;'>" + role + "</td></tr>"
                + "<tr><td colspan='2'><hr style='border:none;border-top:1px solid #dbeafe;margin:10px 0;'></td></tr>"
                + "<tr><td style='color:#6b7280;padding:6px 0;font-size:13px;'>Username</td><td style='font-weight:900;color:#08348f;font-size:16px;'>" + username + "</td></tr>"
                + "<tr><td style='color:#6b7280;padding:6px 0;font-size:13px;'>Temporary Password</td><td style='font-weight:900;color:#e93d3d;font-size:16px;'>" + tempPassword + "</td></tr>"
                + "</table>"
                + "</div>"
                + "<p style='color:#374151;'>⚠️ Please change your password immediately after first login.</p>"
                + "<p style='color:#374151;'>Login at: <a href='" + SettingsDAO.getQrBaseUrl() + "/login.jsp' style='color:#08348f;'>IR-AMS Login Portal</a></p>"
                + "</div>"
                + "<div style='background:#f8fafc;padding:16px 32px;text-align:center;border-top:1px solid #e5e7eb;'>"
                + "<p style='color:#9ca3af;font-size:12px;margin:0;'>This is an automated message from " + SettingsDAO.getSystemName() + " | " + SettingsDAO.getOrgLocation() + "</p>"
                + "</div>"
                + "</div>";

        sendAsync(toEmail, subject, body);
    }

    /**
     * Asset allocation notification email.
     */
    public static void sendAllocationEmail(
            String toEmail, String employeeName, String assetName,
            String assetCode, String allocationDate, String allocatedBy) {

        String subject = "[IR-AMS] Asset Allocated — " + assetCode + " | " + SettingsDAO.getOrgName();
        String body = "<div style='font-family:Segoe UI,Arial,sans-serif;max-width:600px;margin:0 auto;'>"
                + "<div style='background:#08348f;padding:24px;color:white;border-radius:12px 12px 0 0;'>"
                + "<b>🚂 IR-AMS — Asset Allocation Notice</b>"
                + "</div>"
                + "<div style='padding:28px;background:white;border:1px solid #e0e8f5;border-top:none;'>"
                + "<p>Dear <strong>" + employeeName + "</strong>,</p>"
                + "<p>The following asset has been allocated to you:</p>"
                + "<table style='width:100%;border-collapse:collapse;background:#f0f7ff;border-radius:8px;padding:16px;'>"
                + "<tr><td style='padding:8px;color:#6b7280;'>Asset</td><td style='padding:8px;font-weight:700;'>" + assetName + "</td></tr>"
                + "<tr><td style='padding:8px;color:#6b7280;'>Asset Code</td><td style='padding:8px;font-weight:700;color:#08348f;'>" + assetCode + "</td></tr>"
                + "<tr><td style='padding:8px;color:#6b7280;'>Date</td><td style='padding:8px;'>" + allocationDate + "</td></tr>"
                + "<tr><td style='padding:8px;color:#6b7280;'>Allocated By</td><td style='padding:8px;'>" + allocatedBy + "</td></tr>"
                + "</table>"
                + "<p>Please ensure the asset is kept in proper condition and returned when no longer needed.</p>"
                + "</div></div>";

        sendAsync(toEmail, subject, body);
    }

    /**
     * Warranty expiry alert email.
     */
    public static void sendWarrantyAlert(String toEmail, String assetName, String assetCode, String expiryDate, int daysLeft) {
        String urgency = daysLeft <= 7 ? "🔴 URGENT: " : daysLeft <= 15 ? "🟡 WARNING: " : "🔔 REMINDER: ";
        String subject = urgency + "Warranty Expiring in " + daysLeft + " days — " + assetCode;
        String body = "<div style='font-family:Segoe UI,Arial,sans-serif;max-width:600px;'>"
                + "<div style='background:#e93d3d;padding:20px;color:white;border-radius:12px 12px 0 0;'><b>⚠️ Warranty Alert — IR-AMS</b></div>"
                + "<div style='padding:24px;border:1px solid #fee2e2;border-top:none;background:white;'>"
                + "<p>The warranty for the following asset is expiring soon:</p>"
                + "<table style='width:100%;background:#fff5f5;border-radius:8px;padding:12px;'>"
                + "<tr><td style='color:#6b7280;padding:6px;'>Asset</td><td style='font-weight:700;padding:6px;'>" + assetName + "</td></tr>"
                + "<tr><td style='color:#6b7280;padding:6px;'>Code</td><td style='color:#08348f;font-weight:700;padding:6px;'>" + assetCode + "</td></tr>"
                + "<tr><td style='color:#6b7280;padding:6px;'>Expiry Date</td><td style='color:#e93d3d;font-weight:700;padding:6px;'>" + expiryDate + "</td></tr>"
                + "<tr><td style='color:#6b7280;padding:6px;'>Days Left</td><td style='color:#e93d3d;font-weight:900;font-size:20px;padding:6px;'>" + daysLeft + "</td></tr>"
                + "</table>"
                + "<p>Please renew the warranty or take appropriate action.</p>"
                + "</div></div>";
        sendAsync(toEmail, subject, body);
    }

    // -------------------------------------------------------
    // Internal Helpers
    // -------------------------------------------------------

    private static String wrapHtml(String body) {
        if (body.trim().startsWith("<html") || body.trim().startsWith("<!DOCTYPE")) {
            return body;
        }
        return "<!DOCTYPE html><html><head><meta charset='UTF-8'><meta name='viewport' content='width=device-width,initial-scale=1'></head>"
                + "<body style='margin:0;padding:20px;background:#f3f4f6;font-family:Segoe UI,Arial,sans-serif;'>"
                + body
                + "</body></html>";
    }

    private static void logEmail(String recipient, String subject, String body, String status, String error, int createdBy) {
        String preview = body != null && body.length() > 200
                ? body.replaceAll("<[^>]+>", "").substring(0, 200) + "..."
                : (body != null ? body.replaceAll("<[^>]+>", "") : "");

        String sql = "INSERT INTO email_logs (recipient, subject, body_preview, status, error_msg, created_by) VALUES (?,?,?,?,?,?)";
        try (Connection con = DBConnection.getConnection();
             PreparedStatement ps = con.prepareStatement(sql)) {
            ps.setString(1, recipient);
            ps.setString(2, subject);
            ps.setString(3, preview.length() > 500 ? preview.substring(0, 500) : preview);
            ps.setString(4, status);
            ps.setString(5, error);
            ps.setInt(6, createdBy);
            ps.executeUpdate();
        } catch (Exception ex) {
            LOGGER.log(Level.WARNING, "EmailService: Failed to log email.", ex);
        }
    }
}
