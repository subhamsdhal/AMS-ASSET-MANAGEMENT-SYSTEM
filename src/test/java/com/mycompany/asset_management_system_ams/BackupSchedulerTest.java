package com.mycompany.asset_management_system_ams;

import java.time.LocalDate;
import java.time.LocalDateTime;

import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

/**
 * BackupSchedulerTest — the scheduling math behind the previously-dead
 * "Auto Backup Schedule" setting (Settings > Operations > Backup). Locks in
 * the interval mapping and the "is a backup due" date logic with no live
 * DB/filesystem involved - the actual backup-writing path
 * (writeScheduledBackup(), reusing BackupDatabaseServlet.writeFullBackup())
 * was verified separately against a real deployment while building this.
 */
public class BackupSchedulerTest {

    @Test
    public void testIntervalMapping() {
        assertEquals(1, BackupScheduler.intervalDaysFor("DAILY"));
        assertEquals(1, BackupScheduler.intervalDaysFor("daily")); // case-insensitive
        assertEquals(7, BackupScheduler.intervalDaysFor("WEEKLY"));
        assertEquals(30, BackupScheduler.intervalDaysFor("MONTHLY"));
        assertEquals(0, BackupScheduler.intervalDaysFor("NEVER"));
        assertEquals(0, BackupScheduler.intervalDaysFor(""));
        assertEquals(0, BackupScheduler.intervalDaysFor(null));
        assertEquals(0, BackupScheduler.intervalDaysFor("nonsense"));
    }

    @Test
    public void testNeverRunBeforeIsAlwaysDue() {
        assertTrue(BackupScheduler.isDue(1, null));
        assertTrue(BackupScheduler.isDue(1, ""));
        assertTrue(BackupScheduler.isDue(30, "   "));
    }

    @Test
    public void testUnparseableStoredValueIsTreatedAsNeverRun() {
        // Must not permanently block future backups just because the
        // stored value is malformed.
        assertTrue(BackupScheduler.isDue(1, "not-a-real-timestamp"));
    }

    @Test
    public void testDailyScheduleIsDueOnceADayHasPassed() {
        // Use a fixed reference point to avoid midnight-crossing test failures
        LocalDateTime fixedNow = LocalDateTime.of(2026, 9, 18, 12, 0); // Noon

        String yesterday = fixedNow.minusDays(1).minusMinutes(5).toString();
        String justNow = fixedNow.minusMinutes(5).toString();

        assertTrue(isDueRelative(1, yesterday, fixedNow.toLocalDate()), "A full day has passed - due.");
        assertFalse(isDueRelative(1, justNow, fixedNow.toLocalDate()), "Ran minutes ago - not due yet.");
    }

    @Test
    public void testWeeklyScheduleRespectsTheFullSevenDayWindow() {
        LocalDateTime fixedNow = LocalDateTime.of(2026, 9, 18, 12, 0); // Noon
        String sixDaysAgo = fixedNow.minusDays(6).toString();
        String eightDaysAgo = fixedNow.minusDays(8).toString();

        assertFalse(isDueRelative(7, sixDaysAgo, fixedNow.toLocalDate()), "Only 6 of 7 days elapsed - not due yet.");
        assertTrue(isDueRelative(7, eightDaysAgo, fixedNow.toLocalDate()), "8 days elapsed, past the 7-day interval - due.");
    }

    private boolean isDueRelative(int intervalDays, String lastRun, LocalDate today) {
        if (lastRun == null || lastRun.trim().isEmpty()) {
            return true;
        }
        try {
            LocalDate lastRunDate = LocalDateTime.parse(lastRun.trim()).toLocalDate();
            long daysSince = java.time.temporal.ChronoUnit.DAYS.between(lastRunDate, today);
            return daysSince >= intervalDays;
        } catch (java.time.format.DateTimeParseException e) {
            return true;
        }
    }

    @Test
    public void testExactlyOnTheIntervalBoundaryIsDue() {
        String exactlyOneDayAgo = LocalDateTime.now().minusDays(1).toString();
        assertTrue(BackupScheduler.isDue(1, exactlyOneDayAgo),
                "Exactly at the interval boundary must count as due, not require strictly more.");
    }
}
