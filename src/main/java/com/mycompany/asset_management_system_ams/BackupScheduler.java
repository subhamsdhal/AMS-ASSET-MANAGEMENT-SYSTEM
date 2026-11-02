package com.mycompany.asset_management_system_ams;

import java.io.File;
import java.io.FileOutputStream;
import java.io.OutputStreamWriter;
import java.io.PrintWriter;
import java.nio.charset.StandardCharsets;
import java.sql.Connection;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.time.format.DateTimeParseException;
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
 * BackupScheduler — the missing other half of Settings &gt; Operations &gt;
 * Backup's "Auto Backup Schedule" dropdown (Never/Daily/Weekly/Monthly) and
 * "Backup Location" field.
 *
 * Fault (dead setting, fixed): both `ams.backup.auto_schedule` and
 * `ams.backup.location` were correctly saved and displayed by Settings, but
 * grep confirmed neither was ever read anywhere except settings.jsp's own
 * form - there was no scheduler/cron/listener anywhere that acted on them,
 * unlike WarrantyAlertScheduler, which is the working example this class
 * mirrors. Backups only ever happened via a manual click on
 * BackupDatabaseServlet.
 *
 * Runs a lightweight check once a day (checking is cheap; the schedule
 * setting and the last-run timestamp decide whether a backup is actually
 * due today) via a daemon thread, so it never blocks Tomcat shutdown. Each
 * due run reuses BackupDatabaseServlet.writeFullBackup() - the exact same,
 * already-correct dump logic the manual "Download Backup" button and
 * RestoreDatabaseServlet's pre-restore safety copy both already rely on -
 * just pointed at a file in the admin-configured Backup Location instead of
 * an HTTP response or the internal WEB-INF/db_backups safety-net folder.
 */
@WebListener
public class BackupScheduler implements ServletContextListener {

    private static final Logger LOGGER = Logger.getLogger(BackupScheduler.class.getName());

    /** Staggered from WarrantyAlertScheduler(2min)/CopilotDigestScheduler(3min) so their first runs don't collide. */
    private static final long INITIAL_DELAY_MINUTES = 5;
    private static final long PERIOD_MINUTES = 24 * 60;

    private static final String LAST_RUN_KEY = "ams.backup.last_auto_run";

    private ScheduledExecutorService executor;

    @Override
    public void contextInitialized(ServletContextEvent sce) {
        final ServletContext context = sce.getServletContext();

        executor = Executors.newSingleThreadScheduledExecutor(new ThreadFactory() {
            @Override
            public Thread newThread(Runnable r) {
                Thread t = new Thread(r, "IR-AMS-Backup-Scheduler");
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
                    LOGGER.log(Level.WARNING, "Scheduled backup check failed", e);
                }
            }
        }, INITIAL_DELAY_MINUTES, PERIOD_MINUTES, TimeUnit.MINUTES);

        LOGGER.info("IR-AMS: backup scheduler started - checks every 24h whether an auto backup is due, "
                + "first check in " + INITIAL_DELAY_MINUTES + " minute(s).");
    }

    @Override
    public void contextDestroyed(ServletContextEvent sce) {
        if (executor != null) {
            executor.shutdownNow();
        }
    }

    static void runCheck(ServletContext context) {
        String schedule = SettingsDAO.getBackupAutoSchedule();
        int intervalDays = intervalDaysFor(schedule);
        if (intervalDays <= 0) {
            return; // "NEVER" or an unrecognised value - by design, no auto backup
        }

        if (!isDue(intervalDays)) {
            return;
        }

        Connection con = null;
        String backupPath = null;
        try {
            con = DBConnection.getConnection();
            if (con == null) {
                throw new IllegalStateException("Database connection is not available.");
            }
            backupPath = writeScheduledBackup(con);

            // Only advance the "last run" marker on real success - a failed
            // attempt must be retried on tomorrow's check, not silently
            // skipped for the rest of the configured interval.
            SettingsDAO.set(LAST_RUN_KEY, LocalDateTime.now().toString(), 0);

            AuditDAO.log(0, "AUTO_BACKUP", "database", 0,
                    "Scheduled " + schedule + " database backup completed automatically. File: " + backupPath);

            sendBackupAlert("SUCCESS", schedule, backupPath, "");
            LOGGER.info("IR-AMS: scheduled backup completed - " + backupPath);

        } catch (Exception e) {
            LOGGER.log(Level.WARNING, "Scheduled backup failed", e);
            sendBackupAlert("FAILED", schedule, backupPath,
                    e.getClass().getSimpleName() + ": " + e.getMessage());
        } finally {
            if (con != null) {
                try {
                    con.close();
                } catch (Exception ignored) {
                }
            }
        }
    }

    // Package-private (not private) solely so BackupSchedulerTest can assert
    // on the interval/due-date logic directly, without needing a live DB
    // connection or filesystem write - same reasoning as this codebase's
    // other schedulers' test-visibility choices.
    static int intervalDaysFor(String schedule) {
        if (schedule == null) return 0;
        switch (schedule.trim().toUpperCase()) {
            case "DAILY":   return 1;
            case "WEEKLY":  return 7;
            // Simplified to a fixed 30-day interval rather than true
            // calendar-month arithmetic, the same "fixed day count, not
            // calendar-aware" simplification WarrantyAlertScheduler's own
            // 30-day default already uses for this codebase's other
            // scheduled check.
            case "MONTHLY": return 30;
            default:        return 0; // "NEVER" or anything unrecognised
        }
    }

    /** True if no auto backup has ever run, or the last one was at least `intervalDays` ago. */
    private static boolean isDue(int intervalDays) {
        String lastRun = SettingsDAO.get(LAST_RUN_KEY, "");
        return isDue(intervalDays, lastRun);
    }

    // Package-private overload taking the raw stored value directly, so
    // BackupSchedulerTest can exercise the date-math and malformed-value
    // handling without mocking SettingsDAO's static get() - same reasoning
    // as intervalDaysFor()'s visibility above.
    static boolean isDue(int intervalDays, String lastRun) {
        if (lastRun == null || lastRun.trim().isEmpty()) {
            return true;
        }
        try {
            LocalDate lastRunDate = LocalDateTime.parse(lastRun.trim()).toLocalDate();
            long daysSince = java.time.temporal.ChronoUnit.DAYS.between(lastRunDate, LocalDate.now());
            return daysSince >= intervalDays;
        } catch (DateTimeParseException e) {
            // An unparseable stored value must not permanently block future
            // backups - treat it the same as "never run".
            return true;
        }
    }

    /**
     * Writes a full dump to the admin-configured Backup Location (creating
     * the directory if needed), reusing BackupDatabaseServlet's own dump
     * logic - see that class's writeFullBackup() for the actual SQL
     * generation, unchanged here.
     */
    private static String writeScheduledBackup(Connection con) throws Exception {
        File backupDir = new File(SettingsDAO.getBackupLocation());
        if (!backupDir.exists() && !backupDir.mkdirs()) {
            throw new java.io.IOException("Could not create/access backup location: " + backupDir.getAbsolutePath());
        }

        String timestamp = LocalDateTime.now().format(DateTimeFormatter.ofPattern("yyyyMMdd_HHmmss"));
        File backupFile = new File(backupDir, "IR_AMS_Auto_Backup_" + timestamp + ".sql");

        try (PrintWriter writer = new PrintWriter(
                new OutputStreamWriter(new FileOutputStream(backupFile), StandardCharsets.UTF_8))) {
            writer.println("-- Automatic scheduled backup - IR-AMS Backup Scheduler.");
            writer.println("-- Generated: " + LocalDateTime.now().format(DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss")));
            writer.println();
            BackupDatabaseServlet.writeFullBackup(con, writer, "IR-AMS Backup Scheduler (automatic)");
            writer.flush();
            if (writer.checkError()) {
                throw new java.io.IOException("Error writing scheduled backup to " + backupFile.getAbsolutePath());
            }
        }

        return backupFile.getAbsolutePath();
    }

    private static void sendBackupAlert(String status, String schedule, String backupPath, String errorMessage) {
        try {
            String details = "Operation Type: Scheduled Database Backup (" + safe(schedule) + ")\n"
                    + "Status: " + status + "\n"
                    + "Backup File: " + safe(backupPath) + "\n";
            if ("FAILED".equals(status)) {
                details += "Error Message: " + safe(errorMessage) + "\n";
            }
            details += "\nSecurity Note: Database backup contains system data and should be stored securely.";

            NotificationEventService.EmailRouting routing =
                    NotificationEventService.buildSettingsSecurityRecipients("BACKUP", 0);

            NotificationHelper.sendNotification(
                    null, // no live ServletContext available from a background thread's own call chain;
                          // NotificationHelper.sendNotification() tolerates a null context (only used for
                          // an admin-email fallback lookup when no recipient was resolved - not needed here
                          // since buildSettingsSecurityRecipients() always resolves a real recipient).
                    "ADMIN_SECURITY_ALERT",
                    "Backup and Restore",
                    0,
                    routing.getToEmail(),
                    routing.getCcEmail(),
                    "",
                    "Scheduled Database Backup " + status,
                    details.replace("\n", "<br>")
            );
        } catch (Exception e) {
            LOGGER.log(Level.WARNING, "Scheduled backup alert failed", e);
        }
    }

    private static String safe(String value) {
        return value == null || value.trim().isEmpty() ? "N/A" : value.trim();
    }
}
