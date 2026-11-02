package com.mycompany.asset_management_system_ams;

import java.util.ArrayList;
import java.util.List;
import java.util.Properties;

import jakarta.mail.Authenticator;
import jakarta.mail.Message;
import jakarta.mail.PasswordAuthentication;
import jakarta.mail.Session;
import jakarta.mail.Transport;
import jakarta.mail.internet.InternetAddress;
import jakarta.mail.internet.MimeMessage;
import jakarta.servlet.ServletContext;

public class NotificationService {

    public static boolean sendEmail(ServletContext context, String toEmail, String subject, String body) throws Exception {
        return sendEmail(context, toEmail, "", "", subject, body);
    }

    public static boolean sendEmail(ServletContext context, String toEmail, String ccEmail, String replyToEmail,
            String subject, String body) throws Exception {

        System.setProperty("java.net.preferIPv4Stack", "true");
        System.setProperty("java.net.preferIPv6Addresses", "false");

        if (!SettingsDAO.isSmtpEnabled()) {
            System.out.println("IR-AMS EMAIL: SMTP is disabled in system settings. Email skipped.");
            return false;
        }

        String smtpHost = SettingsDAO.getSmtpHost();
        if (smtpHost == null || smtpHost.trim().isEmpty()) {
            smtpHost = "smtp.gmail.com";
        }

        String primaryPort = String.valueOf(SettingsDAO.getSmtpPort());
        if (primaryPort.equals("0")) {
            primaryPort = "587";
        }
        String fallbackPort = "465";

        String gmailUsername = SettingsDAO.getSmtpUsername();
        String gmailAppPassword = SettingsDAO.getSmtpPassword();
        String fromName = SettingsDAO.getSmtpSenderName();
        if (fromName == null || fromName.trim().isEmpty()) {
            fromName = "IR-AMS Notification System";
        }

        if (gmailUsername == null || gmailUsername.trim().isEmpty() || gmailAppPassword == null || gmailAppPassword.trim().isEmpty()) {
            throw new Exception("Gmail username or app password is missing in system settings");
        }

        if (toEmail == null || toEmail.trim().isEmpty()) {
            throw new Exception("Receiver email is empty.");
        }

        List<String> portsToTry = new ArrayList<>();

        if (!primaryPort.isEmpty()) {
            portsToTry.add(primaryPort);
        }

        if (!fallbackPort.isEmpty() && !fallbackPort.equals(primaryPort)) {
            portsToTry.add(fallbackPort);
        }

        Exception lastException = null;

        for (String port : portsToTry) {
            try {
                System.out.println("IR-AMS EMAIL: Trying SMTP port " + port);

                sendEmailUsingPort(
                        smtpHost,
                        port,
                        gmailUsername,
                        gmailAppPassword,
                        fromName,
                        toEmail,
                        ccEmail,
                        replyToEmail,
                        subject,
                        body
                );

                System.out.println("IR-AMS EMAIL: Sent successfully using SMTP port " + port);
                return true;

            } catch (Exception e) {
                lastException = e;
                System.out.println("IR-AMS EMAIL: Failed using SMTP port " + port);
                System.out.println("Reason: " + e.getClass().getName() + " - " + e.getMessage());
            }
        }

        throw new Exception(
                "Email sending failed on all SMTP ports. Tried primary port "
                + primaryPort
                + " and fallback port "
                + fallbackPort
                + ". Last error: "
                + (lastException != null ? lastException.getMessage() : "Unknown error"),
                lastException
        );
    }

    private static void sendEmailUsingPort(
            String smtpHost,
            String smtpPort,
            String gmailUsername,
            String gmailAppPassword,
            String fromName,
            String toEmail,
            String ccEmail,
            String replyToEmail,
            String subject,
            String body
    ) throws Exception {

        Properties mailProperties = new Properties();

        mailProperties.put("mail.smtp.auth", "true");
        mailProperties.put("mail.smtp.host", smtpHost);
        mailProperties.put("mail.smtp.port", smtpPort);
        mailProperties.put("mail.smtp.ssl.trust", smtpHost);
        
        boolean useTls = SettingsDAO.isSmtpTls();

        if ("465".equals(smtpPort)) {
            mailProperties.put("mail.smtp.ssl.enable", "true");
            mailProperties.put("mail.smtp.starttls.enable", "false");
        } else {
            mailProperties.put("mail.smtp.ssl.enable", "false");
            mailProperties.put("mail.smtp.starttls.enable", useTls ? "true" : "false");
            if (useTls) {
                mailProperties.put("mail.smtp.starttls.required", "true");
            }
        }

        mailProperties.put("mail.smtp.connectiontimeout", "15000");
        mailProperties.put("mail.smtp.timeout", "15000");
        mailProperties.put("mail.smtp.writetimeout", "15000");

        Session mailSession = Session.getInstance(mailProperties, new Authenticator() {
            @Override
            protected PasswordAuthentication getPasswordAuthentication() {
                return new PasswordAuthentication(gmailUsername, gmailAppPassword);
            }
        });

        MimeMessage message = new MimeMessage(mailSession);

        message.setFrom(new InternetAddress(gmailUsername, fromName));
        message.setRecipients(Message.RecipientType.TO, InternetAddress.parse(toEmail));

        if (ccEmail != null && !ccEmail.trim().isEmpty()) {
            message.setRecipients(Message.RecipientType.CC, InternetAddress.parse(ccEmail));
        }

        if (replyToEmail != null && !replyToEmail.trim().isEmpty() && replyToEmail.contains("@")) {
            message.setReplyTo(InternetAddress.parse(replyToEmail));
        }

        message.setSubject(subject, "UTF-8");
        message.setContent(body, "text/html; charset=utf-8");

        Transport.send(message);
    }
    // Fault (fixed - audit/22 Findings 1 & 2, dead-code cleanup): this class
    // used to also define loadNotificationProperties(), reading SMTP config
    // from the static /WEB-INF/notification.properties file - the file that
    // held this application's leaked, live Gmail App Password. sendEmail()
    // above never actually called it (a second, disconnected code path -
    // NotificationHelper.getAdminNotifyEmail() - was the file's only real
    // reader, now moved onto SettingsDAO too), so this was pure dead code
    // left over from before this class was migrated onto the SettingsDAO-
    // backed configuration EmailService already correctly used. Removed
    // entirely so notification.properties has no remaining code reader
    // anywhere in this application.
}