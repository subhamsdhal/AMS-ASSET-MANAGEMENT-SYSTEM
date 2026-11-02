package com.mycompany.asset_management_system_ams;

import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.sql.Statement;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.ThreadFactory;

import jakarta.servlet.ServletContext;

public class NotificationHelper {

    public static final String MODULE_ASSET_REQUEST = "ASSET_REQUEST";
    public static final String MODULE_ALLOCATION = "ALLOCATION";
    public static final String MODULE_RETURN = "RETURN";
    public static final String MODULE_MAINTENANCE = "MAINTENANCE";
    public static final String MODULE_DISPOSAL = "DISPOSAL";
    public static final String MODULE_ADMIN_SECURITY = "ADMIN_SECURITY";
    public static final String MODULE_WARRANTY = "WARRANTY";
    public static final String MODULE_COPILOT_DIGEST = "COPILOT_DIGEST";

    private static final ExecutorService EMAIL_EXECUTOR = Executors.newFixedThreadPool(
            3,
            new ThreadFactory() {
        private int count = 1;

        @Override
        public Thread newThread(Runnable runnable) {
            Thread thread = new Thread(runnable);
            thread.setName("IR-AMS-Background-Mailer-" + count++);
            thread.setDaemon(true);
            return thread;
        }
    }
    );

    public static boolean sendAssetRequestAlert(
            ServletContext context,
            Integer referenceId,
            String recipientEmail,
            String subject,
            String messageBody
    ) {
        return sendAssetRequestAlert(
                context,
                referenceId,
                recipientEmail,
                "",
                "",
                subject,
                messageBody
        );
    }

    public static boolean sendAssetRequestAlert(
            ServletContext context,
            Integer referenceId,
            String recipientEmail,
            String ccEmail,
            String replyToEmail,
            String subject,
            String messageBody
    ) {
        return sendNotification(
                context,
                "ASSET_REQUEST_ALERT",
                MODULE_ASSET_REQUEST,
                referenceId,
                recipientEmail,
                ccEmail,
                replyToEmail,
                subject,
                messageBody
        );
    }

    public static boolean sendAllocationAlert(
            ServletContext context,
            Integer referenceId,
            String recipientEmail,
            String ccEmail,
            String replyToEmail,
            String subject,
            String messageBody
    ) {
        return sendNotification(
                context,
                "ALLOCATION_ALERT",
                MODULE_ALLOCATION,
                referenceId,
                recipientEmail,
                ccEmail,
                replyToEmail,
                subject,
                messageBody
        );
    }

    public static boolean sendReturnAlert(
            ServletContext context,
            Integer referenceId,
            String recipientEmail,
            String ccEmail,
            String replyToEmail,
            String subject,
            String messageBody
    ) {
        return sendNotification(
                context,
                "RETURN_ALERT",
                MODULE_RETURN,
                referenceId,
                recipientEmail,
                ccEmail,
                replyToEmail,
                subject,
                messageBody
        );
    }

    public static boolean sendMaintenanceAlert(
            ServletContext context,
            Integer referenceId,
            String recipientEmail,
            String ccEmail,
            String replyToEmail,
            String subject,
            String messageBody
    ) {
        return sendNotification(
                context,
                "MAINTENANCE_ALERT",
                MODULE_MAINTENANCE,
                referenceId,
                recipientEmail,
                ccEmail,
                replyToEmail,
                subject,
                messageBody
        );
    }

    public static boolean sendDisposalAlert(
            ServletContext context,
            Integer referenceId,
            String recipientEmail,
            String ccEmail,
            String replyToEmail,
            String subject,
            String messageBody
    ) {
        return sendNotification(
                context,
                "DISPOSAL_ALERT",
                MODULE_DISPOSAL,
                referenceId,
                recipientEmail,
                ccEmail,
                replyToEmail,
                subject,
                messageBody
        );
    }

    public static boolean sendAdminSecurityAlert(
            ServletContext context,
            Integer referenceId,
            String subject,
            String messageBody
    ) {
        String adminEmail = getAdminNotifyEmail(context);

        return sendNotification(
                context,
                "ADMIN_SECURITY_ALERT",
                MODULE_ADMIN_SECURITY,
                referenceId,
                adminEmail,
                "",
                "",
                subject,
                messageBody
        );
    }

    public static boolean sendNotification(
            ServletContext context,
            String notificationType,
            String moduleName,
            Integer referenceId,
            String recipientEmail,
            String ccEmail,
            String replyToEmail,
            String subject,
            String messageBody
    ) {
        String cleanNotificationType = clean(notificationType);
        String cleanModuleName = clean(moduleName);
        String cleanRecipientEmail = clean(recipientEmail);
        String cleanCcEmail = clean(ccEmail);
        String cleanReplyToEmail = clean(replyToEmail);
        String cleanSubject = clean(subject);
        String cleanMessageBody = clean(messageBody);

        if (cleanNotificationType.isEmpty()) {
            cleanNotificationType = "GENERAL_ALERT";
        }

        if (cleanModuleName.isEmpty()) {
            cleanModuleName = "GENERAL";
        }

        if (cleanSubject.isEmpty()) {
            cleanSubject = "IR-AMS Notification";
        }

        if (cleanMessageBody.isEmpty()) {
            cleanMessageBody = "This is an automated notification from IR-AMS.";
        }

        try {
            if (!isNotificationAllowed(cleanModuleName)) {
                logNotificationAndReturnId(
                        cleanNotificationType,
                        cleanModuleName,
                        referenceId,
                        cleanRecipientEmail,
                        cleanCcEmail,
                        cleanSubject,
                        cleanMessageBody,
                        "SKIPPED",
                        "Notification disabled in notification settings."
                );

                return false;
            }

            if (cleanRecipientEmail.isEmpty()) {
                cleanRecipientEmail = getAdminNotifyEmail(context);
            }

            if (cleanRecipientEmail.isEmpty()) {
                logNotificationAndReturnId(
                        cleanNotificationType,
                        cleanModuleName,
                        referenceId,
                        "NOT_AVAILABLE",
                        cleanCcEmail,
                        cleanSubject,
                        cleanMessageBody,
                        "FAILED",
                        "Recipient email missing and admin.notify.email not configured."
                );

                return false;
            }

            final ServletContext finalContext = context;
            final String finalNotificationType = cleanNotificationType;
            final String finalModuleName = cleanModuleName;
            final Integer finalReferenceId = referenceId;
            final String finalRecipientEmail = cleanRecipientEmail;
            final String finalCcEmail = cleanCcEmail;
            final String finalReplyToEmail = cleanReplyToEmail;
            final String finalSubject = cleanSubject;
            final String finalMessageBody = cleanMessageBody;

            final int notificationLogId = logNotificationAndReturnId(
                    finalNotificationType,
                    finalModuleName,
                    finalReferenceId,
                    finalRecipientEmail,
                    finalCcEmail,
                    finalSubject,
                    finalMessageBody,
                    "QUEUED",
                    "Email queued for background delivery."
            );

            EMAIL_EXECUTOR.submit(new Runnable() {
                @Override
                public void run() {
                    try {
                        NotificationService.sendEmail(
                                finalContext,
                                finalRecipientEmail,
                                finalCcEmail,
                                finalReplyToEmail,
                                finalSubject,
                                finalMessageBody
                        );

                        updateNotificationStatus(
                                notificationLogId,
                                "SENT",
                                buildErrorMessage(null, finalCcEmail)
                        );

                        System.out.println("IR-AMS EMAIL: Background email sent. Log ID: " + notificationLogId);

                    } catch (Exception e) {
                        updateNotificationStatus(
                                notificationLogId,
                                "FAILED",
                                buildErrorMessage(
                                        e.getClass().getSimpleName() + ": " + e.getMessage(),
                                        finalCcEmail
                                )
                        );

                        System.out.println("IR-AMS EMAIL: Background email failed. Log ID: " + notificationLogId);
                        e.printStackTrace();
                    }
                }
            });

            return true;

        } catch (Exception e) {
            String finalRecipient = cleanRecipientEmail;

            if (finalRecipient.isEmpty()) {
                finalRecipient = "NOT_AVAILABLE";
            }

            logNotificationAndReturnId(
                    cleanNotificationType,
                    cleanModuleName,
                    referenceId,
                    finalRecipient,
                    cleanCcEmail,
                    cleanSubject,
                    cleanMessageBody,
                    "FAILED",
                    e.getClass().getSimpleName() + ": " + e.getMessage()
            );

            e.printStackTrace();
            return false;
        }
    }

    public static String getUserEmailByUsername(String username) {

        String email = "";

        String sql = "SELECT email FROM users WHERE username = ? AND status = 'ACTIVE' LIMIT 1";

        try (
                Connection con = DBConnection.getConnection();
                PreparedStatement ps = con.prepareStatement(sql)
        ) {
            ps.setString(1, clean(username));

            ResultSet rs = ps.executeQuery();

            if (rs.next()) {
                email = clean(rs.getString("email"));
            }

            rs.close();

        } catch (Exception e) {
            e.printStackTrace();
        }

        return email;
    }

    public static String getEmailByRoleName(String roleName) {

        String email = "";

        String sql = "SELECT u.email "
                + "FROM users u "
                + "JOIN roles r ON u.role_id = r.role_id "
                + "WHERE r.role_name = ? "
                + "AND u.status = 'ACTIVE' "
                + "AND u.email IS NOT NULL "
                + "AND u.email <> '' "
                + "ORDER BY u.user_id ASC "
                + "LIMIT 1";

        try (
                Connection con = DBConnection.getConnection();
                PreparedStatement ps = con.prepareStatement(sql)
        ) {
            ps.setString(1, clean(roleName));

            ResultSet rs = ps.executeQuery();

            if (rs.next()) {
                email = clean(rs.getString("email"));
            }

            rs.close();

        } catch (Exception e) {
            e.printStackTrace();
        }

        return email;
    }

    public static String combineEmails(String firstEmail, String secondEmail) {

        String first = clean(firstEmail);
        String second = clean(secondEmail);

        if (first.isEmpty()) {
            return second;
        }

        if (second.isEmpty()) {
            return first;
        }

        if (first.equalsIgnoreCase(second)) {
            return first;
        }

        return first + "," + second;
    }

    private static boolean isNotificationAllowed(String moduleName) {

        boolean emailAlertsEnabled = isSettingEnabled("email_alerts", true);

        if (!emailAlertsEnabled) {
            return false;
        }

        String cleanModuleName = clean(moduleName).toUpperCase();

        switch (cleanModuleName) {
            case MODULE_ASSET_REQUEST:
                return isSettingEnabled("request_alerts", true);

            case MODULE_RETURN:
                return isSettingEnabled("return_alerts", true);

            case MODULE_MAINTENANCE:
                return isSettingEnabled("maintenance_alerts", true);

            case MODULE_ALLOCATION:
                // Was hardcoded true - the "Asset Allocation Email" toggle on
                // Settings > Notifications saved successfully but could never
                // actually turn allocation emails off. There's no notification_settings
                // column for this one (only request/return/maintenance/audit exist
                // there), so it's gated on the SettingsDAO flag SaveSettingsServlet
                // already writes.
                return SettingsDAO.getBoolean("ams.notify.allocation.email", true);

            case MODULE_DISPOSAL:
                return true;

            case MODULE_ADMIN_SECURITY:
                return isSettingEnabled("audit_alerts", true);

            case MODULE_WARRANTY:
                // warranty_alerts already existed as a notification_settings column
                // (schema.sql) but nothing ever read or exposed it - the scheduled
                // warranty check (WarrantyAlertScheduler) is the first real consumer.
                return isSettingEnabled("warranty_alerts", true);

            case MODULE_COPILOT_DIGEST:
                // Same defense-in-depth as every other gated module here:
                // CopilotDigestScheduler already checks copilot_digest_alerts itself
                // before ever calling sendNotification(), but a module-level re-check
                // here means the toggle is honoured even if some future caller sends
                // a COPILOT_DIGEST notification without going through that scheduler.
                return isSettingEnabled("copilot_digest_alerts", true);

            default:
                return true;
        }
    }

    private static boolean isSettingEnabled(String columnName, boolean defaultValue) {

        String sql = "SELECT " + columnName + " FROM notification_settings WHERE setting_id = 1";

        try (
                Connection con = DBConnection.getConnection();
                PreparedStatement ps = con.prepareStatement(sql);
                ResultSet rs = ps.executeQuery()
        ) {
            if (rs.next()) {
                return rs.getInt(1) == 1;
            }

            return defaultValue;

        } catch (SQLException e) {
            return defaultValue;

        } catch (Exception e) {
            return defaultValue;
        }
    }

    /**
     * Columns on notification_settings that isNotificationAllowed() actually
     * consults. Whitelisted because column names get concatenated into SQL below
     * (JDBC has no placeholder syntax for identifiers) - every caller in this
     * codebase passes a hardcoded literal, never request input, but the whitelist
     * makes that a checked invariant instead of an assumption.
     */
    private static final java.util.Set<String> ALERT_COLUMNS = new java.util.HashSet<String>(java.util.Arrays.asList(
            "maintenance_alerts", "request_alerts", "return_alerts",
            "audit_alerts", "email_alerts", "dashboard_alerts", "warranty_alerts",
            "copilot_digest_alerts"
    ));

    /**
     * Public read for a notification_settings alert column. Lets other admin
     * surfaces (Settings > Notifications) display the same live value
     * isNotificationAllowed() actually gates on, instead of a disconnected
     * SettingsDAO flag nothing ever checked.
     */
    public static boolean isAlertSettingEnabled(String columnName, boolean defaultValue) {
        if (columnName == null || !ALERT_COLUMNS.contains(columnName)) {
            return defaultValue;
        }
        return isSettingEnabled(columnName, defaultValue);
    }

    /**
     * Public write for a notification_settings alert column, so a second admin
     * surface (Settings > Notifications) can flip the same live switch
     * UpdateNotificationSettingsServlet/notification_settings.jsp uses, instead
     * of writing to a SettingsDAO key nothing ever reads.
     */
    public static boolean setAlertSetting(String columnName, boolean value, int updatedBy) {
        if (columnName == null || !ALERT_COLUMNS.contains(columnName)) {
            return false;
        }

        String sql = "UPDATE notification_settings SET " + columnName + " = ? WHERE setting_id = 1";

        try (Connection con = DBConnection.getConnection();
             PreparedStatement ps = con.prepareStatement(sql)) {
            ps.setInt(1, value ? 1 : 0);
            return ps.executeUpdate() > 0;
        } catch (Exception e) {
            return false;
        }
    }

    private static int logNotificationAndReturnId(
            String notificationType,
            String moduleName,
            Integer referenceId,
            String recipientEmail,
            String ccEmail,
            String subject,
            String messageBody,
            String status,
            String errorMessage
    ) {
        String sql = "INSERT INTO notification_logs "
                + "(notification_type, module_name, reference_id, recipient_email, subject, message_body, status, error_message) "
                + "VALUES (?, ?, ?, ?, ?, ?, ?, ?)";

        int notificationLogId = 0;

        String finalErrorMessage = buildErrorMessage(errorMessage, ccEmail);

        try (
                Connection con = DBConnection.getConnection();
                PreparedStatement ps = con.prepareStatement(sql, Statement.RETURN_GENERATED_KEYS)
        ) {
            ps.setString(1, limit(clean(notificationType), 80));
            ps.setString(2, limit(clean(moduleName), 80));

            if (referenceId == null || referenceId <= 0) {
                ps.setNull(3, java.sql.Types.INTEGER);
            } else {
                ps.setInt(3, referenceId);
            }

            String safeRecipient = clean(recipientEmail);

            if (safeRecipient.isEmpty()) {
                safeRecipient = "NOT_AVAILABLE";
            }

            ps.setString(4, limit(safeRecipient, 150));
            ps.setString(5, limit(clean(subject), 200));
            ps.setString(6, clean(messageBody));
            ps.setString(7, limit(clean(status), 20));
            ps.setString(8, limit(finalErrorMessage, 1000));

            ps.executeUpdate();

            ResultSet generatedKeys = ps.getGeneratedKeys();

            if (generatedKeys.next()) {
                notificationLogId = generatedKeys.getInt(1);
            }

            generatedKeys.close();

        } catch (Exception e) {
            System.out.println("IR-AMS Notification Log Insert Failed:");
            e.printStackTrace();
        }

        return notificationLogId;
    }

    private static void updateNotificationStatus(
            int notificationLogId,
            String status,
            String errorMessage
    ) {
        if (notificationLogId <= 0) {
            return;
        }

        String sql = "UPDATE notification_logs "
                + "SET status = ?, error_message = ? "
                + "WHERE notification_id = ?";

        try (
                Connection con = DBConnection.getConnection();
                PreparedStatement ps = con.prepareStatement(sql)
        ) {
            ps.setString(1, limit(clean(status), 20));
            ps.setString(2, limit(clean(errorMessage), 1000));
            ps.setInt(3, notificationLogId);

            ps.executeUpdate();

        } catch (Exception e) {
            System.out.println("IR-AMS Notification Log Update Failed:");
            e.printStackTrace();
        }
    }

    private static String buildErrorMessage(String errorMessage, String ccEmail) {

        String finalErrorMessage = clean(errorMessage);
        String finalCcEmail = clean(ccEmail);

        if (!finalCcEmail.isEmpty()) {
            if (finalErrorMessage.isEmpty()) {
                finalErrorMessage = "CC: " + finalCcEmail;
            } else {
                finalErrorMessage = finalErrorMessage + " | CC: " + finalCcEmail;
            }
        }

        return finalErrorMessage;
    }

    // Fault (Critical, fixed - audit/22 Findings 1 & 2): this used to read a
    // fallback admin-notify address from /WEB-INF/notification.properties -
    // the same static file that also held this application's real, live,
    // plaintext Gmail SMTP credential, checked into source control. The real
    // send path (NotificationService.sendEmail) had already been migrated to
    // read host/port/username/password/sender-name exclusively from
    // SettingsDAO (the encrypted-at-rest, admin-editable path), leaving this
    // one small fallback as the file's only remaining live reader in this
    // class. Moving it onto SettingsDAO too removes the last code dependency
    // on notification.properties, so the file can be fully retired - see
    // that file's own header comment for the remaining manual step (the
    // actual credential still needs rotating; no code change can do that).
    private static String getAdminNotifyEmail(ServletContext context) {
        String adminEmail = SettingsDAO.getSmtpUsername();
        return adminEmail == null ? "" : adminEmail.trim();
    }

    private static String clean(String value) {
        if (value == null) {
            return "";
        }

        return value.trim();
    }

    private static String limit(String value, int maxLength) {
        String cleanValue = clean(value);

        if (cleanValue.length() <= maxLength) {
            return cleanValue;
        }

        return cleanValue.substring(0, maxLength);
    }

    public static String buildHtmlEmail(String recipientName, String eventName, String detailsTableHtml, String actionNote) {
        StringBuilder html = new StringBuilder();
        html.append("<!DOCTYPE html><html><head><meta charset=\"UTF-8\">");
        html.append("<style>");
        html.append("body { font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; background-color: #f4f6f9; color: #333; margin: 0; padding: 0; }");
        html.append(".email-container { max-width: 600px; margin: 20px auto; background-color: #fff; border-radius: 8px; overflow: hidden; box-shadow: 0 4px 10px rgba(0,0,0,0.1); }");
        html.append(".email-header { background-color: #1a365d; color: #fff; padding: 20px; text-align: center; }");
        html.append(".email-header h2 { margin: 0; font-size: 20px; letter-spacing: 1px; }");
        html.append(".email-body { padding: 30px; line-height: 1.6; }");
        html.append(".greeting { font-size: 16px; font-weight: bold; margin-bottom: 15px; color: #2d3748; }");
        html.append(".event-summary { font-size: 15px; margin-bottom: 25px; padding: 10px; background-color: #ebf8fa; border-left: 4px solid #3182ce; color: #2b6cb0; }");
        html.append(".details-table { width: 100%; border-collapse: collapse; margin-bottom: 25px; }");
        html.append(".details-table th, .details-table td { padding: 12px 15px; border-bottom: 1px solid #e2e8f0; text-align: left; }");
        html.append(".details-table th { background-color: #f7fafc; color: #4a5568; width: 35%; font-weight: 600; }");
        html.append(".details-table td { color: #2d3748; }");
        html.append(".action-note { font-size: 14px; margin-bottom: 30px; color: #4a5568; }");
        html.append(".closing { font-size: 14px; color: #4a5568; margin-top: 20px; }");
        html.append(".email-footer { background-color: #edf2f7; color: #718096; text-align: center; padding: 15px; font-size: 12px; }");
        html.append("</style>");
        html.append("</head><body>");
        html.append("<div class=\"email-container\">");
        html.append("<div class=\"email-header\"><h2>Railway Asset Management System</h2></div>");
        html.append("<div class=\"email-body\">");
        
        if (recipientName != null && !recipientName.isEmpty()) {
            html.append("<div class=\"greeting\">Dear ").append(recipientName).append(",</div>");
        } else {
            html.append("<div class=\"greeting\">Dear Officer,</div>");
        }
        
        html.append("<p>This is an official notification from the Railway Asset Management System.</p>");
        
        if (eventName != null && !eventName.isEmpty()) {
            html.append("<div class=\"event-summary\"><strong>Event:</strong> ").append(eventName).append("</div>");
        }
        
        if (detailsTableHtml != null && !detailsTableHtml.isEmpty()) {
            html.append("<strong>Details:</strong>");
            html.append("<table class=\"details-table\">").append(detailsTableHtml).append("</table>");
        }
        
        if (actionNote != null && !actionNote.isEmpty()) {
            html.append("<div class=\"action-note\">").append(actionNote).append("</div>");
        } else {
            html.append("<div class=\"action-note\">Please log in to IR-AMS for further review or action.</div>");
        }
        
        html.append("<div class=\"closing\">");
        html.append("Regards,<br>");
        html.append("<strong>IR-AMS Notification Desk</strong><br>");
        html.append("East Coast Railway<br>");
        html.append("Rail Sadan, Bhubaneswar");
        html.append("</div>");
        html.append("</div>");
        html.append("<div class=\"email-footer\">");
        html.append("This is an auto-generated email. Please do not reply to this message.");
        html.append("</div>");
        html.append("</div>");
        html.append("</body></html>");
        return html.toString();
    }
}