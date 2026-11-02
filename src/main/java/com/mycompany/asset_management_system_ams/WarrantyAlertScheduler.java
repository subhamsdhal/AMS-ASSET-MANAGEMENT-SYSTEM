package com.mycompany.asset_management_system_ams;

import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.util.concurrent.Executors;
import java.util.concurrent.ScheduledExecutorService;
import java.util.concurrent.ThreadFactory;
import java.util.concurrent.TimeUnit;
import java.util.logging.Level;
import java.util.logging.Logger;

import jakarta.servlet.ServletContext;
import jakarta.servlet.ServletContextEvent;
import jakarta.servlet.ServletContextListener;
import jakarta.servlet.annotation.WebListener;

/**
 * WarrantyAlertScheduler - the missing other half of Settings > Notifications'
 * "Warranty Expiry Alert - Days Before" field.
 *
 * That field (ams.notify.warranty.days, SettingsDAO.getWarrantyAlertDays())
 * saved a threshold with nothing anywhere in the codebase ever reading it -
 * no scheduled job existed to act on it. EmailService.sendWarrantyAlert() was
 * already written (a ready HTML template) but had zero callers. This class is
 * that missing caller, built as a scheduled background check instead - unlike
 * maintenance/request/return alerts, which fire reactively off a user action,
 * a warranty date is not tied to any action a user takes, so it has to be
 * polled.
 *
 * Runs once shortly after server startup, then every 24h for the life of the
 * application (a daemon thread, so it never blocks Tomcat shutdown). Each run:
 *
 *   1. Skips entirely if SMTP isn't configured, or the warranty_alerts /
 *      email_alerts switches (Settings > Notifications) are off - no wasted
 *      query.
 *   2. Finds assets whose warranty_expiry falls within the configured window
 *      and hasn't already passed.
 *   3. Skips any asset already alerted within that same window
 *      (notification_logs dedup), so one asset doesn't generate a fresh email
 *      every single day it sits inside the threshold.
 *   4. Sends one alert per remaining asset, routed the same way other
 *      asset-lifecycle emails are (ASSET_MANAGER, cc SUPER_ADMIN).
 *
 * Registered via @WebListener - the same annotation-scanning mechanism this
 * project already relies on for every @WebServlet, no web.xml entry needed.
 */
@WebListener
public class WarrantyAlertScheduler implements ServletContextListener {

    private static final Logger LOGGER = Logger.getLogger(WarrantyAlertScheduler.class.getName());

    private static final long INITIAL_DELAY_MINUTES = 2;
    private static final long PERIOD_MINUTES = 24 * 60;

    /**
     * Defensive cap. If an admin sets the threshold very high on a large asset
     * register, this keeps one run from firing an unbounded number of emails.
     */
    private static final int MAX_ALERTS_PER_RUN = 200;

    private ScheduledExecutorService executor;

    @Override
    public void contextInitialized(ServletContextEvent sce) {
        final ServletContext context = sce.getServletContext();

        executor = Executors.newSingleThreadScheduledExecutor(new ThreadFactory() {
            @Override
            public Thread newThread(Runnable r) {
                Thread t = new Thread(r, "IR-AMS-Warranty-Alert-Scheduler");
                t.setDaemon(true);
                return t;
            }
        });

        executor.scheduleAtFixedRate(new Runnable() {
            @Override
            public void run() {
                try {
                    runCheck(context);
                } catch (Exception e) {
                    LOGGER.log(Level.WARNING, "Warranty alert check failed", e);
                }
            }
        }, INITIAL_DELAY_MINUTES, PERIOD_MINUTES, TimeUnit.MINUTES);

        LOGGER.info("IR-AMS: warranty alert scheduler started - checks every 24h, first run in "
                + INITIAL_DELAY_MINUTES + " minute(s).");
    }

    @Override
    public void contextDestroyed(ServletContextEvent sce) {
        if (executor != null) {
            executor.shutdownNow();
        }
    }

    static void runCheck(ServletContext context) {
        if (!SettingsDAO.isSmtpEnabled()) {
            return;
        }
        if (!NotificationHelper.isAlertSettingEnabled("warranty_alerts", true)) {
            return;
        }

        int days = SettingsDAO.getWarrantyAlertDays();
        if (days < 1 || days > 365) {
            days = 30;
        }

        String sql = "SELECT asset_id, asset_code, asset_name, warranty_expiry, "
                + "DATEDIFF(warranty_expiry, CURDATE()) AS days_left "
                + "FROM assets "
                + "WHERE warranty_expiry IS NOT NULL "
                + "AND warranty_expiry >= CURDATE() "
                + "AND warranty_expiry <= DATE_ADD(CURDATE(), INTERVAL ? DAY) "
                + "ORDER BY warranty_expiry ASC "
                + "LIMIT ?";

        int sent = 0;

        try (Connection con = DBConnection.getConnection();
             PreparedStatement ps = con.prepareStatement(sql)) {

            ps.setInt(1, days);
            ps.setInt(2, MAX_ALERTS_PER_RUN);

            try (ResultSet rs = ps.executeQuery()) {
                while (rs.next()) {
                    int assetId = rs.getInt("asset_id");

                    if (alreadyAlertedRecently(con, assetId, days)) {
                        continue;
                    }

                    sendAlert(
                            context,
                            assetId,
                            rs.getString("asset_code"),
                            rs.getString("asset_name"),
                            rs.getString("warranty_expiry"),
                            rs.getInt("days_left")
                    );
                    sent++;
                }
            }

        } catch (Exception e) {
            LOGGER.log(Level.WARNING, "Warranty alert query failed", e);
            return;
        }

        if (sent > 0) {
            LOGGER.info("IR-AMS: warranty alert check sent " + sent + " alert(s).");
        }
    }

    /**
     * Skip an asset already alerted within the configured window, so it does
     * not generate a fresh email every single day it sits inside the
     * threshold. Once the last alert ages past `days` days it becomes
     * eligible again - covers both "still not renewed, remind again" and
     * "admin changed the threshold" without a dedicated tracking column,
     * reusing the notification_logs audit trail every other alert type
     * already writes to.
     */
    private static boolean alreadyAlertedRecently(Connection con, int assetId, int days) throws Exception {
        String sql = "SELECT COUNT(*) FROM notification_logs "
                + "WHERE module_name = ? AND reference_id = ? "
                + "AND status IN ('SENT', 'QUEUED') "
                + "AND sent_at >= DATE_SUB(NOW(), INTERVAL ? DAY)";

        try (PreparedStatement ps = con.prepareStatement(sql)) {
            ps.setString(1, NotificationHelper.MODULE_WARRANTY);
            ps.setInt(2, assetId);
            ps.setInt(3, days);
            try (ResultSet rs = ps.executeQuery()) {
                return rs.next() && rs.getInt(1) > 0;
            }
        }
    }

    private static void sendAlert(ServletContext context, int assetId, String assetCode,
            String assetName, String expiry, int daysLeft) {

        String urgency = daysLeft <= 7 ? "URGENT: " : daysLeft <= 15 ? "WARNING: " : "REMINDER: ";
        String subject = "IR-AMS " + urgency + "Warranty Expiring in " + daysLeft
                + " day" + (daysLeft == 1 ? "" : "s") + " - " + safe(assetCode);

        // Fault (Medium, fixed): assetName is free text (set at asset creation/edit)
        // embedded unescaped - same recurring class as audit/10-maintenance.md
        // Finding 1, flagged as unconfirmed for this module in
        // audit/14-warranty.md.
        String detailsTable = "<tr><th>Asset:</th><td>" + HtmlEscapeUtil.escape(safe(assetName)) + "</td></tr>"
                + "<tr><th>Asset Code:</th><td>" + safe(assetCode) + "</td></tr>"
                + "<tr><th>Warranty Expiry:</th><td>" + safe(expiry) + "</td></tr>"
                + "<tr><th>Days Remaining:</th><td>" + daysLeft + "</td></tr>";

        String body = NotificationHelper.buildHtmlEmail(
                "Asset Manager",
                "Warranty Expiring Soon",
                detailsTable,
                "Please renew the warranty or plan for asset replacement before it lapses."
        );

        try {
            NotificationEventService.EmailRouting routing =
                    NotificationEventService.buildAssetRecipients("WARRANTY_EXPIRING", assetId);

            NotificationHelper.sendNotification(
                    context,
                    "WARRANTY_ALERT",
                    NotificationHelper.MODULE_WARRANTY,
                    assetId,
                    routing.getToEmail(),
                    routing.getCcEmail(),
                    "",
                    subject,
                    body
            );
        } catch (Exception e) {
            LOGGER.log(Level.WARNING, "Failed to send warranty alert for asset " + assetId, e);
        }
    }

    private static String safe(String value) {
        return value == null ? "" : value;
    }
}
