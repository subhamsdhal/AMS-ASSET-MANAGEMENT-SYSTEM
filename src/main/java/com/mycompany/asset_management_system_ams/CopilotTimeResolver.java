package com.mycompany.asset_management_system_ams;

import java.time.DayOfWeek;
import java.time.LocalDate;
import java.time.temporal.TemporalAdjusters;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * CopilotTimeResolver
 *
 * Extracts time/date constraints from normalized user text.
 *
 * IMPORTANT WARRANTY LOGIC:
 *   - "expiring next N days"  → warranty_expiry >= CURDATE() AND <= DATE_ADD(CURDATE(), INTERVAL N DAY)
 *   - "expired"              → warranty_expiry < CURDATE()
 *   Never mix the two.
 */
public class CopilotTimeResolver {

    public static class TimeMatch {
        public LocalDate startDate;
        public LocalDate endDate;
        public Integer days;
        public String dateRangeRaw;

        public TimeMatch(LocalDate startDate, LocalDate endDate, Integer days, String dateRangeRaw) {
            this.startDate   = startDate;
            this.endDate     = endDate;
            this.days        = days;
            this.dateRangeRaw = dateRangeRaw;
        }
    }

    public static TimeMatch extractTime(String query) {
        if (query == null) return null;
        String q = query.toLowerCase();

        // ── Expired / Overdue ─────────────────────────────────────────────────
        // "expired" must NOT match "expiring" — check only the standalone word
        if (containsWord(q, "expired") || containsWord(q, "overdue")) {
            return new TimeMatch(null, LocalDate.now().minusDays(1), null, "EXPIRED");
        }

        // ── Today ─────────────────────────────────────────────────────────────
        if (containsWord(q, "today") || containsWord(q, "aaj") || containsWord(q, "ajki")) {
            return new TimeMatch(LocalDate.now(), LocalDate.now(), 0, "TODAY");
        }

        // ── Yesterday ─────────────────────────────────────────────────────────
        // Fault: this phrase - reported live, "how many asset added
        // yesterday?" - had no handler at all, so it silently fell through
        // to no time filter whatsoever rather than an error; combined with
        // the tool executors ignoring startDate/endDate entirely (see
        // CopilotToolExecutor.searchAssets/searchEmployees), the question
        // always answered with the unfiltered total instead of "yesterday"'s
        // count specifically.
        if (containsWord(q, "yesterday") || containsWord(q, "kal")) {
            LocalDate y = LocalDate.now().minusDays(1);
            return new TimeMatch(y, y, 1, "YESTERDAY");
        }

        // ── This Week ─────────────────────────────────────────────────────────
        if (q.contains("this week") || q.contains("current week")) {
            LocalDate start = LocalDate.now().with(TemporalAdjusters.previousOrSame(DayOfWeek.MONDAY));
            LocalDate end   = LocalDate.now().with(TemporalAdjusters.nextOrSame(DayOfWeek.SUNDAY));
            return new TimeMatch(start, end, null, "THIS_WEEK");
        }

        // ── This Month ───────────────────────────────────────────────────────
        if (q.contains("this month") || q.contains("is maah") || q.contains("is mahine")) {
            LocalDate start = LocalDate.now().with(TemporalAdjusters.firstDayOfMonth());
            LocalDate end   = LocalDate.now().with(TemporalAdjusters.lastDayOfMonth());
            return new TimeMatch(start, end, null, "THIS_MONTH");
        }

        // ── Last Month ────────────────────────────────────────────────────────
        if (q.contains("last month") || q.contains("pichle maah") || q.contains("pichle mahine")) {
            LocalDate start = LocalDate.now().minusMonths(1).with(TemporalAdjusters.firstDayOfMonth());
            LocalDate end   = LocalDate.now().minusMonths(1).with(TemporalAdjusters.lastDayOfMonth());
            return new TimeMatch(start, end, null, "LAST_MONTH");
        }

        // ── This Year ────────────────────────────────────────────────────────
        if (q.contains("this year") || q.contains("is saal") || q.contains("current year")) {
            LocalDate start = LocalDate.now().with(TemporalAdjusters.firstDayOfYear());
            LocalDate end   = LocalDate.now().with(TemporalAdjusters.lastDayOfYear());
            return new TimeMatch(start, end, null, "THIS_YEAR");
        }

        // ── Last Year ────────────────────────────────────────────────────────
        if (q.contains("last year") || q.contains("pichle saal")) {
            LocalDate start = LocalDate.now().minusYears(1).with(TemporalAdjusters.firstDayOfYear());
            LocalDate end   = LocalDate.now().minusYears(1).with(TemporalAdjusters.lastDayOfYear());
            return new TimeMatch(start, end, null, "LAST_YEAR");
        }

        // ── Next N Days (e.g. "next 30 days", "within 7 days", "30 days") ───
        // Note: "expiring" is NOT "expired" — future-facing query
        Matcher m = Pattern.compile("\\b(?:next|within|coming)?\\s*(\\d+)\\s+days?\\b").matcher(q);
        if (m.find()) {
            int days = Integer.parseInt(m.group(1));
            // Future window: today → today + N days
            return new TimeMatch(LocalDate.now(), LocalDate.now().plusDays(days), days, "NEXT_" + days + "_DAYS");
        }

        // ── Next N Months ─────────────────────────────────────────────────────
        Matcher mm = Pattern.compile("\\b(?:next|within)\\s*(\\d+)\\s+months?\\b").matcher(q);
        if (mm.find()) {
            int months = Integer.parseInt(mm.group(1));
            return new TimeMatch(LocalDate.now(), LocalDate.now().plusMonths(months), null, "NEXT_" + months + "_MONTHS");
        }

        return null;
    }

    /** Check for a whole word in query without regex overhead */
    private static boolean containsWord(String query, String word) {
        int idx = query.indexOf(word);
        if (idx < 0) return false;
        boolean before = (idx == 0) || !Character.isLetterOrDigit(query.charAt(idx - 1));
        int end = idx + word.length();
        boolean after = (end >= query.length()) || !Character.isLetterOrDigit(query.charAt(end));
        return before && after;
    }
}
