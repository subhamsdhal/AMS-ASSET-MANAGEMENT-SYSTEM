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

@WebServlet(name = "UpdateNotificationSettingsServlet", urlPatterns = {"/UpdateNotificationSettingsServlet"})
public class UpdateNotificationSettingsServlet extends HttpServlet {

    @Override
    protected void doPost(HttpServletRequest request, HttpServletResponse response)
            throws ServletException, IOException {

        Connection con = null;
        PreparedStatement ps = null;

        try {
            request.setCharacterEncoding("UTF-8");

            HttpSession session = request.getSession(false);

            if (session == null
                    || session.getAttribute("username") == null
                    || session.getAttribute("role") == null) {
                response.sendRedirect("login.jsp");
                return;
            }

            String username = session.getAttribute("username").toString();
            String role = session.getAttribute("role").toString();

            if (!("SUPER_ADMIN".equals(role) || "ADMIN".equals(role))) {
                response.sendRedirect("settings.jsp?access=denied");
                return;
            }

            int maintenanceAlerts = request.getParameter("maintenanceAlerts") == null ? 0 : 1;
            int requestAlerts = request.getParameter("requestAlerts") == null ? 0 : 1;
            int returnAlerts = request.getParameter("returnAlerts") == null ? 0 : 1;
            int auditAlerts = request.getParameter("auditAlerts") == null ? 0 : 1;
            int emailAlerts = request.getParameter("emailAlerts") == null ? 0 : 1;
            int dashboardAlerts = request.getParameter("dashboardAlerts") == null ? 0 : 1;
            int warrantyAlerts = request.getParameter("warrantyAlerts") == null ? 0 : 1;
            int copilotDigestAlerts = request.getParameter("copilotDigestAlerts") == null ? 0 : 1;

            con = DBConnection.getConnection();

            int[] oldSettings = getOldSettings(con);

            String changedSettings = buildChangedSettingsSummary(
                    oldSettings,
                    maintenanceAlerts,
                    requestAlerts,
                    returnAlerts,
                    auditAlerts,
                    emailAlerts,
                    dashboardAlerts,
                    warrantyAlerts,
                    copilotDigestAlerts
            );

            boolean hasActualChange = changedSettings != null && !changedSettings.trim().isEmpty();

            ps = con.prepareStatement(
                    "UPDATE notification_settings SET "
                    + "maintenance_alerts = ?, "
                    + "request_alerts = ?, "
                    + "return_alerts = ?, "
                    + "audit_alerts = ?, "
                    + "email_alerts = ?, "
                    + "dashboard_alerts = ?, "
                    + "warranty_alerts = ?, "
                    + "copilot_digest_alerts = ? "
                    + "WHERE setting_id = 1"
            );

            ps.setInt(1, maintenanceAlerts);
            ps.setInt(2, requestAlerts);
            ps.setInt(3, returnAlerts);
            ps.setInt(4, auditAlerts);
            ps.setInt(5, emailAlerts);
            ps.setInt(6, dashboardAlerts);
            ps.setInt(7, warrantyAlerts);
            ps.setInt(8, copilotDigestAlerts);

            int updatedRows = ps.executeUpdate();
            ps.close();
            ps = null;

            if (updatedRows == 0) {
                ps = con.prepareStatement(
                        "INSERT INTO notification_settings "
                        + "(setting_id, maintenance_alerts, request_alerts, return_alerts, audit_alerts, email_alerts, dashboard_alerts, warranty_alerts, copilot_digest_alerts) "
                        + "VALUES (1, ?, ?, ?, ?, ?, ?, ?, ?)"
                );

                ps.setInt(1, maintenanceAlerts);
                ps.setInt(2, requestAlerts);
                ps.setInt(3, returnAlerts);
                ps.setInt(4, auditAlerts);
                ps.setInt(5, emailAlerts);
                ps.setInt(6, dashboardAlerts);
                ps.setInt(7, warrantyAlerts);
                ps.setInt(8, copilotDigestAlerts);

                ps.executeUpdate();
                ps.close();
                ps = null;

                hasActualChange = true;

                if (changedSettings == null || changedSettings.trim().isEmpty()) {
                    changedSettings = buildInitialSettingsSummary(
                            maintenanceAlerts,
                            requestAlerts,
                            returnAlerts,
                            auditAlerts,
                            emailAlerts,
                            dashboardAlerts,
                            warrantyAlerts,
                            copilotDigestAlerts
                    );
                }
            }

            int userId = getSessionUserId(session);
            String loginEmail = NotificationHelper.getUserEmailByUsername(username);

            String auditMessage;

            if (hasActualChange) {
                auditMessage = "Notification control settings updated by " + username
                        + ". Changed settings: "
                        + changedSettings.replace("\n", " | ");
            } else {
                auditMessage = "Notification settings save submitted by " + username
                        + ". No effective configuration change detected.";
            }

            try {
                AuditDAO.log(
                        userId,
                        hasActualChange ? "UPDATE" : "NO_CHANGE",
                        "notification_settings",
                        1,
                        auditMessage
                );
            } catch (Exception auditException) {
                System.err.println("AuditDAO error: " + auditException.getMessage());
            }

            if (hasActualChange) {
                sendProfessionalNotificationSettingsAlert(
                        userId,
                        username,
                        role,
                        loginEmail,
                        changedSettings
                );
            }

            response.sendRedirect("notification_settings.jsp?msg=updated");

        } catch (Exception e) {
            System.err.println("UpdateNotificationSettingsServlet error: " + e.getMessage());
            response.sendRedirect("notification_settings.jsp?error=server");

        } finally {
            try {
                if (ps != null) {
                    ps.close();
                }

                if (con != null) {
                    con.close();
                }
            } catch (Exception ex) {
                System.err.println("Resource close error: " + ex.getMessage());
            }
        }
    }

    private void sendProfessionalNotificationSettingsAlert(
            int userId,
            String username,
            String role,
            String loginEmail,
            String changedSettings
    ) {
        try {
            NotificationEventService.EmailRouting routing = NotificationEventService.buildSettingsSecurityRecipients("SETTINGS_UPDATE", userId);
            String toEmail = routing.getToEmail();
            String ccEmail = routing.getCcEmail();

            String subject = "IR-AMS Configuration Notice | Notification Controls Updated";

            String body = "IR-AMS Configuration Notice\n\n"
                    + "Recipient: Super Admin\n"
                    + "Severity: Medium\n"
                    + "Category: Notification Control Settings\n"
                    + "Status: Configuration Updated\n\n"
                    + "A notification control configuration was updated in IR-AMS. "
                    + "This change may affect how operational, request, return, maintenance, audit, email, or dashboard alerts are generated and delivered.\n\n"
                    + "Changed Configuration\n"
                    + changedSettings + "\n"
                    + "Configuration Details\n"
                    + "Setting ID: 1\n"
                    + "Updated By: " + safe(username, "N/A") + "\n"
                    + "Role: " + formatRoleName(role) + "\n"
                    + "Account: " + safe(loginEmail, "N/A") + "\n\n"
                    + "Routing Basis\n"
                    + "System configuration changes are restricted to Super Admin review.\n\n"
                    + "Recommended Review\n"
                    + "Please verify that the updated notification controls match the current operational and administrative requirements.\n\n"
                    + "IR-AMS Notification System";

            NotificationHelper.sendNotification(
                    getServletContext(),
                    "ADMIN_SECURITY_ALERT",
                    "NOTIFICATION_SETTINGS",
                    1,
                    toEmail,
                    ccEmail,
                    "",
                    subject,
                    body
            );

        } catch (Exception e) {
            System.err.println("Notification alert error: " + e.getMessage());
        }
    }

    private String buildChangedSettingsSummary(
            int[] oldSettings,
            int maintenanceAlerts,
            int requestAlerts,
            int returnAlerts,
            int auditAlerts,
            int emailAlerts,
            int dashboardAlerts,
            int warrantyAlerts,
            int copilotDigestAlerts
    ) {
        StringBuilder changes = new StringBuilder();

        appendChange(changes, "Maintenance Alerts", oldSettings[0], maintenanceAlerts);
        appendChange(changes, "Request Alerts", oldSettings[1], requestAlerts);
        appendChange(changes, "Return Alerts", oldSettings[2], returnAlerts);
        appendChange(changes, "Audit Alerts", oldSettings[3], auditAlerts);
        appendChange(changes, "Email Alerts", oldSettings[4], emailAlerts);
        appendChange(changes, "Dashboard Alerts", oldSettings[5], dashboardAlerts);
        appendChange(changes, "Warranty Alerts", oldSettings[6], warrantyAlerts);
        appendChange(changes, "Copilot Daily Digest", oldSettings[7], copilotDigestAlerts);

        return changes.toString();
    }

    private String buildInitialSettingsSummary(
            int maintenanceAlerts,
            int requestAlerts,
            int returnAlerts,
            int auditAlerts,
            int emailAlerts,
            int dashboardAlerts,
            int warrantyAlerts,
            int copilotDigestAlerts
    ) {
        StringBuilder settings = new StringBuilder();

        settings.append("Maintenance Alerts: ").append(formatSettingValue(maintenanceAlerts)).append("\n");
        settings.append("Request Alerts: ").append(formatSettingValue(requestAlerts)).append("\n");
        settings.append("Return Alerts: ").append(formatSettingValue(returnAlerts)).append("\n");
        settings.append("Audit Alerts: ").append(formatSettingValue(auditAlerts)).append("\n");
        settings.append("Email Alerts: ").append(formatSettingValue(emailAlerts)).append("\n");
        settings.append("Dashboard Alerts: ").append(formatSettingValue(dashboardAlerts)).append("\n");
        settings.append("Warranty Alerts: ").append(formatSettingValue(warrantyAlerts)).append("\n");
        settings.append("Copilot Daily Digest: ").append(formatSettingValue(copilotDigestAlerts)).append("\n\n");

        return settings.toString();
    }

    private void appendChange(StringBuilder changes, String settingName, int oldValue, int newValue) {

        if (oldValue == -1) {
            changes.append(settingName)
                    .append(": ")
                    .append(formatSettingValue(newValue))
                    .append("\n");
            return;
        }

        if (oldValue != newValue) {
            changes.append(settingName)
                    .append(": ")
                    .append(formatSettingValue(oldValue))
                    .append(" → ")
                    .append(formatSettingValue(newValue))
                    .append("\n");
        }
    }

    private int[] getOldSettings(Connection con) {

        int[] settings = new int[]{-1, -1, -1, -1, -1, -1, -1, -1};

        String sql = "SELECT maintenance_alerts, request_alerts, return_alerts, "
                + "audit_alerts, email_alerts, dashboard_alerts, warranty_alerts, copilot_digest_alerts "
                + "FROM notification_settings "
                + "WHERE setting_id = 1";

        try (
                PreparedStatement ps = con.prepareStatement(sql);
                ResultSet rs = ps.executeQuery()
        ) {
            if (rs.next()) {
                settings[0] = rs.getInt("maintenance_alerts");
                settings[1] = rs.getInt("request_alerts");
                settings[2] = rs.getInt("return_alerts");
                settings[3] = rs.getInt("audit_alerts");
                settings[4] = rs.getInt("email_alerts");
                settings[5] = rs.getInt("dashboard_alerts");
                settings[6] = rs.getInt("warranty_alerts");
                settings[7] = rs.getInt("copilot_digest_alerts");
            }

        } catch (Exception e) {
            System.err.println("getOldSettings error: " + e.getMessage());
        }

        return settings;
    }

    private String formatSettingValue(int value) {

        if (value == -1) {
            return "N/A";
        }

        if (value == 1) {
            return "ON";
        }

        return "OFF";
    }

    private String formatRoleName(String roleName) {

        if (roleName == null || roleName.trim().isEmpty()) {
            return "N/A";
        }

        return roleName.trim().replace("_", " ");
    }

    private String safe(String value, String fallback) {

        if (value == null || value.trim().isEmpty()) {
            return fallback;
        }

        return value.trim();
    }

    private int getSessionUserId(HttpSession session) {

        // Defaulting to 1 here would misattribute this audit-log entry to whichever
        // real account happens to be user_id 1. AuditDAO.log() resolves 0/null to a
        // NULL "system" row instead, so 0 is the safe default when the session
        // attribute is missing or unparseable.
        Object userIdObj = session.getAttribute("user_id");

        if (userIdObj == null) {
            userIdObj = session.getAttribute("userId");
        }

        if (userIdObj instanceof Integer) {
            return (Integer) userIdObj;
        }

        if (userIdObj != null) {
            try {
                return Integer.parseInt(userIdObj.toString());
            } catch (Exception e) {
                return 0;
            }
        }

        return 0;
    }
}