package com.mycompany.asset_management_system_ams;

import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
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
 * CopilotDigestScheduler — the Copilot's one proactive (not just reactive)
 * behaviour: a daily consolidated email listing pending asset requests and
 * pending maintenance requests that have been sitting unactioned longer than
 * a configurable threshold ("Copilot Digest - Aging Threshold", Settings >
 * General; on/off switch "Copilot Daily Digest", Settings > Notifications).
 *
 * Everything else the Copilot does is reactive - it only ever speaks when
 * asked. Nothing surfaces an aging pending request or an ignored maintenance
 * ticket unless someone happens to ask about it. This closes that gap the
 * same way WarrantyAlertScheduler closed it for warranty expiry: a scheduled
 * background check, not a user-triggered one.
 *
 * Deliberately a SINGLE consolidated email per run, not one per item (unlike
 * WarrantyAlertScheduler, which fires one email per asset) - a "digest" that
 * fragments into a dozen separate emails defeats its own purpose. Dedup is
 * therefore at the RUN level (has a digest already gone out in roughly the
 * last day?), not the per-item level WarrantyAlertScheduler uses, since
 * there is only ever one digest to send or not send per day.
 *
 * Runs once shortly after server startup, then every 24h for the life of the
 * application (a daemon thread, so it never blocks Tomcat shutdown). Each run:
 *
 *   1. Skips entirely if SMTP isn't configured, the copilot_digest_alerts
 *      switch is off, or a digest already went out within the last 20 hours
 *      (a server restart landing inside the same day must not double-send).
 *   2. Finds pending asset requests (PENDING or PENDING_DEPT_HEAD) and
 *      pending maintenance requests whose request_date is older than the
 *      configured threshold.
 *   3. If both lists are empty, sends nothing at all - a digest with nothing
 *      to report is noise, not a service.
 *   4. Otherwise sends ONE email, routed the same way other asset-lifecycle
 *      notices are (ASSET_MANAGER, cc SUPER_ADMIN, via
 *      NotificationEventService.buildMasterDataRecipients() - the same
 *      routing "asset added/updated" notices already use).
 */
@WebListener
public class CopilotDigestScheduler implements ServletContextListener {

    private static final Logger LOGGER = Logger.getLogger(CopilotDigestScheduler.class.getName());

    private static final long INITIAL_DELAY_MINUTES = 3;
    private static final long PERIOD_MINUTES = 24 * 60;

    /** Defensive cap so one run cannot list an unbounded number of rows in a single email. */
    private static final int MAX_ITEMS_PER_CATEGORY = 15;

    /**
     * Higher than get_maintenance_cost_outliers' own on-demand default
     * (1.5x, in CopilotToolExecutor) deliberately: an unsolicited email
     * should only interrupt someone's day for something clearly notable,
     * where a user who explicitly asks the Copilot for this insight can
     * reasonably want the more sensitive, lower bar.
     */
    private static final double DIGEST_COST_OUTLIER_THRESHOLD = 2.0;

    /**
     * Under 24h on purpose: a server restart that lands inside the same
     * calendar day as an already-sent digest must not trigger a second one
     * just because the scheduler's initial delay fired again. Comfortably
     * over the 24h period's own natural variance either way.
     */
    private static final int DEDUP_WINDOW_HOURS = 20;

    private ScheduledExecutorService executor;

    @Override
    public void contextInitialized(ServletContextEvent sce) {
        final ServletContext context = sce.getServletContext();

        executor = Executors.newSingleThreadScheduledExecutor(new ThreadFactory() {
            @Override
            public Thread newThread(Runnable r) {
                Thread t = new Thread(r, "IR-AMS-Copilot-Digest-Scheduler");
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
                    LOGGER.log(Level.WARNING, "Copilot digest check failed", e);
                }
            }
        }, INITIAL_DELAY_MINUTES, PERIOD_MINUTES, TimeUnit.MINUTES);

        LOGGER.info("IR-AMS: Copilot digest scheduler started - checks every 24h, first run in "
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
        if (!NotificationHelper.isAlertSettingEnabled("copilot_digest_alerts", true)) {
            return;
        }
        if (alreadySentRecently()) {
            return;
        }

        int days = SettingsDAO.getCopilotDigestAgingDays();
        if (days < 1 || days > 365) {
            days = 3;
        }

        List<PendingItem> pendingRequests = findPendingAssetRequests(days);
        List<PendingItem> pendingMaintenance = findPendingMaintenanceRequests(days);
        List<PendingItem> costOutliers = findMaintenanceCostOutliers();

        if (pendingRequests.isEmpty() && pendingMaintenance.isEmpty() && costOutliers.isEmpty()) {
            return;
        }

        sendDigest(context, days, pendingRequests, pendingMaintenance, costOutliers);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // QUERIES
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * One row worth of digest content - deliberately just display strings,
     * not a domain object. Package-private (not private) for the same
     * testing reason as the query methods above.
     */
    static final class PendingItem {
        final String label;
        final String detail;
        final int daysPending;

        PendingItem(String label, String detail, int daysPending) {
            this.label = label;
            this.detail = detail;
            this.daysPending = daysPending;
        }
    }

    // Package-private (not private), solely so CopilotDigestSchedulerTest can
    // exercise each query/gate directly rather than only through the full
    // runCheck()->sendNotification() path - which this test suite
    // deliberately never invokes for real, since NotificationHelper is
    // mocked out entirely in every test (no live SMTP is ever touched by
    // running this suite, regardless of what's configured in any real
    // environment).
    static List<PendingItem> findPendingAssetRequests(int days) {
        List<PendingItem> items = new ArrayList<PendingItem>();

        String sql = "SELECT ar.request_id, ar.priority, "
                + "COALESCE(e.employee_name, 'Unknown Employee') AS employee_name, "
                + "COALESCE(e.employee_code, '') AS employee_code, "
                + "COALESCE(c.category_name, 'Unspecified category') AS category_name, "
                + "DATEDIFF(CURDATE(), ar.request_date) AS days_pending "
                + "FROM asset_requests ar "
                + "LEFT JOIN employees e ON ar.employee_id = e.employee_id "
                + "LEFT JOIN asset_categories c ON ar.category_id = c.category_id "
                + "WHERE ar.request_status IN ('PENDING', 'PENDING_DEPT_HEAD') "
                + "AND ar.request_date <= DATE_SUB(CURDATE(), INTERVAL ? DAY) "
                + "ORDER BY ar.request_date ASC "
                + "LIMIT ?";

        try (Connection con = DBConnection.getConnection();
             PreparedStatement ps = con.prepareStatement(sql)) {
            ps.setInt(1, days);
            ps.setInt(2, MAX_ITEMS_PER_CATEGORY);
            try (ResultSet rs = ps.executeQuery()) {
                while (rs.next()) {
                    int daysPending = rs.getInt("days_pending");
                    items.add(new PendingItem(
                            "Request #" + rs.getInt("request_id"),
                            rs.getString("category_name") + " requested by "
                                    + rs.getString("employee_name")
                                    + (rs.getString("employee_code").isEmpty() ? "" : " (" + rs.getString("employee_code") + ")")
                                    + " - priority " + safe(rs.getString("priority"), "NORMAL")
                                    + " - pending " + daysPending + " day" + (daysPending == 1 ? "" : "s"),
                            daysPending));
                }
            }
        } catch (Exception e) {
            LOGGER.log(Level.WARNING, "Copilot digest: pending asset request query failed", e);
        }

        return items;
    }

    static List<PendingItem> findPendingMaintenanceRequests(int days) {
        List<PendingItem> items = new ArrayList<PendingItem>();

        String sql = "SELECT mr.request_id, mr.issue_description, "
                + "COALESCE(a.asset_code, CONCAT('AST-', mr.asset_id)) AS asset_code, "
                + "COALESCE(a.asset_name, 'Unknown Asset') AS asset_name, "
                + "DATEDIFF(CURDATE(), mr.request_date) AS days_pending "
                + "FROM maintenance_requests mr "
                + "LEFT JOIN assets a ON mr.asset_id = a.asset_id "
                + "WHERE mr.request_status = 'PENDING' "
                + "AND mr.request_date <= DATE_SUB(CURDATE(), INTERVAL ? DAY) "
                + "ORDER BY mr.request_date ASC "
                + "LIMIT ?";

        try (Connection con = DBConnection.getConnection();
             PreparedStatement ps = con.prepareStatement(sql)) {
            ps.setInt(1, days);
            ps.setInt(2, MAX_ITEMS_PER_CATEGORY);
            try (ResultSet rs = ps.executeQuery()) {
                while (rs.next()) {
                    int daysPending = rs.getInt("days_pending");
                    String issue = safe(rs.getString("issue_description"), "No description given");
                    items.add(new PendingItem(
                            "Maintenance #" + rs.getInt("request_id"),
                            rs.getString("asset_code") + " (" + rs.getString("asset_name") + ") - "
                                    + issue + " - pending " + daysPending + " day" + (daysPending == 1 ? "" : "s"),
                            daysPending));
                }
            }
        } catch (Exception e) {
            LOGGER.log(Level.WARNING, "Copilot digest: pending maintenance request query failed", e);
        }

        return items;
    }

    /**
     * Reuses CopilotToolExecutor.queryMaintenanceCostOutliers() - the exact
     * same analytical query get_maintenance_cost_outliers answers on
     * request - so the digest surfaces this insight PROACTIVELY instead of
     * only when a user with the right role happens to think to ask. A
     * scheduled job has no HttpSession/role to gate a tool call through in
     * the first place, so this calls the shared query method directly
     * rather than going through the role-checked tool wrapper.
     */
    static List<PendingItem> findMaintenanceCostOutliers() {
        List<PendingItem> items = new ArrayList<PendingItem>();
        try {
            for (Map<String, String> row : CopilotToolExecutor.queryMaintenanceCostOutliers(DIGEST_COST_OUTLIER_THRESHOLD)) {
                items.add(new PendingItem(
                        row.get("asset_code"),
                        row.get("asset_name") + " (" + row.get("category_name") + ") - total maintenance cost "
                                + row.get("total_maintenance_cost") + ", " + row.get("times_above_average")
                                + " its category's average (" + row.get("category_average_cost") + ")",
                        0));
            }
        } catch (Exception e) {
            LOGGER.log(Level.WARNING, "Copilot digest: maintenance cost outlier query failed", e);
        }
        return items;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // DEDUP
    // ─────────────────────────────────────────────────────────────────────────

    static boolean alreadySentRecently() {
        String sql = "SELECT COUNT(*) FROM notification_logs "
                + "WHERE module_name = ? AND status IN ('SENT', 'QUEUED') "
                + "AND sent_at >= DATE_SUB(NOW(), INTERVAL ? HOUR)";

        try (Connection con = DBConnection.getConnection();
             PreparedStatement ps = con.prepareStatement(sql)) {
            ps.setString(1, NotificationHelper.MODULE_COPILOT_DIGEST);
            ps.setInt(2, DEDUP_WINDOW_HOURS);
            try (ResultSet rs = ps.executeQuery()) {
                return rs.next() && rs.getInt(1) > 0;
            }
        } catch (Exception e) {
            LOGGER.log(Level.WARNING, "Copilot digest: dedup check failed - sending anyway rather than "
                    + "silently going dark on a real backlog", e);
            return false;
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // EMAIL
    // ─────────────────────────────────────────────────────────────────────────

    static void sendDigest(ServletContext context, int days, List<PendingItem> pendingRequests,
            List<PendingItem> pendingMaintenance, List<PendingItem> costOutliers) {

        int agingCount = pendingRequests.size() + pendingMaintenance.size();
        String subject = "IR-AMS Copilot Daily Digest - " + agingCount
                + " item" + (agingCount == 1 ? "" : "s") + " pending over " + days + " day"
                + (days == 1 ? "" : "s")
                + (costOutliers.isEmpty() ? "" : ", " + costOutliers.size() + " cost outlier"
                        + (costOutliers.size() == 1 ? "" : "s"));

        StringBuilder rows = new StringBuilder();
        appendSection(rows, "Pending Asset Requests", pendingRequests);
        appendSection(rows, "Pending Maintenance Requests", pendingMaintenance);
        appendSection(rows, "Maintenance Cost Outliers (" + DIGEST_COST_OUTLIER_THRESHOLD + "x category average)",
                costOutliers);

        String body = NotificationHelper.buildHtmlEmail(
                "Asset Manager",
                "Daily Copilot Digest",
                rows.toString(),
                "This is an automated summary from AMS Copilot, not a request needing a reply. "
                        + "Review and action these items from the Asset Requests / Maintenance modules.");

        try {
            NotificationEventService.EmailRouting routing =
                    NotificationEventService.buildMasterDataRecipients("ADDED");

            NotificationHelper.sendNotification(
                    context,
                    "COPILOT_DIGEST",
                    NotificationHelper.MODULE_COPILOT_DIGEST,
                    0,
                    routing.getToEmail(),
                    routing.getCcEmail(),
                    "",
                    subject,
                    body
            );
        } catch (Exception e) {
            LOGGER.log(Level.WARNING, "Failed to send Copilot daily digest", e);
        }
    }

    private static void appendSection(StringBuilder rows, String sectionTitle, List<PendingItem> items) {
        if (items.isEmpty()) {
            return;
        }
        rows.append("<tr><th colspan=\"1\" style=\"background:#e2e8f0;\">")
                .append(sectionTitle).append(" (").append(items.size()).append(")</th>"
                        + "<td style=\"background:#e2e8f0;\"></td></tr>");
        for (PendingItem item : items) {
            rows.append("<tr><th>").append(escape(item.label)).append("</th><td>")
                    .append(escape(item.detail)).append("</td></tr>");
        }
        // Generic wording deliberately - this list's own query LIMIT varies
        // by section (pending requests/maintenance cap at MAX_ITEMS_PER_CATEGORY;
        // cost outliers cap at a different limit inside
        // CopilotToolExecutor.queryMaintenanceCostOutliers()) and pending
        // items are ordered oldest-first while outliers are ordered by
        // ratio - "capped at N oldest items" would be both the wrong number
        // and the wrong claim for that section.
        if (items.size() >= MAX_ITEMS_PER_CATEGORY) {
            rows.append("<tr><th></th><td><em>List may be capped - more could exist beyond what's shown "
                    + "here.</em></td></tr>");
        }
    }

    private static String escape(String value) {
        if (value == null) {
            return "";
        }
        return value.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;");
    }

    private static String safe(String value, String fallback) {
        return (value == null || value.trim().isEmpty()) ? fallback : value;
    }
}
