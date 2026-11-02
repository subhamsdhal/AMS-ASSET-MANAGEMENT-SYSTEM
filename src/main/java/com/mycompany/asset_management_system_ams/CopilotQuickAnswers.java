package com.mycompany.asset_management_system_ams;

import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.time.LocalDate;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.logging.Level;
import java.util.logging.Logger;

import jakarta.servlet.http.HttpSession;

/**
 * CopilotQuickAnswers — a deterministic, zero-LLM fast path for a small set
 * of pre-vetted "how many X were added/happened <period>?" questions.
 *
 * Added because the real, external LLM providers (Groq/Gemini free tiers)
 * are genuinely rate-limited under sustained use, and can take anywhere from
 * a couple of seconds to (after a failover chain) 30-60+ seconds, or in the
 * worst case run out of every configured provider and return the honest
 * "temporarily unavailable" message (see CopilotAgentLoop). That is fine for
 * normal use, but unacceptable risk live in front of an audience. This class
 * answers a curated set of count-by-period questions directly from the
 * database in milliseconds, matched by plain keyword rules (no LLM, no
 * network call) - checked BEFORE the AI path in CopilotEngine.answer(), so a
 * question that matches here never waits on a provider at all.
 *
 * Deliberately conservative: if a question does not clearly match both a
 * known module and a known time period, this returns null and the question
 * falls through to the normal AI/keyword pipeline completely unchanged -
 * this class only ever intercepts the exact class of question it was built
 * for, never anything else.
 *
 * By design, this lives entirely in the existing chat input on
 * ams_copilot.jsp - no new button, shortcut, or UI element. Typing one of
 * these questions (or a close variant) is the only way to reach it.
 */
final class CopilotQuickAnswers {

    private static final Logger LOGGER = Logger.getLogger(CopilotQuickAnswers.class.getName());

    private CopilotQuickAnswers() {
    }

    /** One countable module: a human label, the table+date column, and which "added" phrasing selects it. */
    private static final class Module {
        final String label;
        final String table;
        final String dateColumn;
        /** All of these must appear in the normalized question for this module to match. */
        final String[] requiredPhrases;
        /** If any of these appear, this module is skipped even if requiredPhrases matched (avoids stepping on a DIFFERENT date's meaning - e.g. "purchased" belongs to purchase_date, not created_at). */
        final String[] excludedPhrases;

        Module(String label, String table, String dateColumn, String[] requiredPhrases, String[] excludedPhrases) {
            this.label = label;
            this.table = table;
            this.dateColumn = dateColumn;
            this.requiredPhrases = requiredPhrases;
            this.excludedPhrases = excludedPhrases;
        }
    }

    // Ordered most-specific-first: "asset request" must be checked before a
    // bare "request" or "asset" trigger could ever apply to it.
    private static final Module[] MODULES = new Module[] {
        new Module("employees added", "employees", "created_at",
                new String[]{"employee", "add"}, new String[]{"join"}),
        new Module("maintenance requests raised", "maintenance_requests", "request_date",
                new String[]{"maintenance"}, new String[]{}),
        new Module("asset requests raised", "asset_requests", "request_date",
                new String[]{"asset request"}, new String[]{}),
        new Module("assets disposed (requested)", "asset_disposal", "created_at",
                new String[]{"dispos"}, new String[]{}),
        new Module("allocations made", "asset_allocation", "allocation_date",
                new String[]{"allocat"}, new String[]{}),
        new Module("assets returned", "asset_returns", "return_date",
                new String[]{"return"}, new String[]{}),
        // Checked LAST: "asset" alone is the broadest trigger, so anything
        // more specific above (asset request, asset disposed) must have
        // already been tried and failed to reach here.
        new Module("assets added", "assets", "created_at",
                new String[]{"asset", "add"}, new String[]{"purchas"}),
    };

    private static final class Period {
        final String label;
        final LocalDate start;
        final LocalDate endExclusive;

        Period(String label, LocalDate start, LocalDate endExclusive) {
            this.label = label;
            this.start = start;
            this.endExclusive = endExclusive;
        }
    }

    /**
     * Tries to answer instantly. Returns null (never throws) when the
     * question does not confidently match a known module + period, or on
     * any DB error - either way CopilotEngine falls through to the normal
     * AI/keyword pipeline exactly as if this class did not exist.
     */
    static String tryAnswer(String question, String role, HttpSession session) {
        if (question == null || question.trim().isEmpty()) {
            return null;
        }
        String normalized = question.toLowerCase();

        // A counting intent must actually be present - "show assets added
        // this month" is a list request (belongs to the normal pipeline,
        // which can display real rows), not a count this class answers.
        boolean countingIntent = normalized.contains("how many") || normalized.contains("count")
                || normalized.contains("number of") || normalized.contains("total number");
        if (!countingIntent) {
            return null;
        }

        Period period = matchPeriod(normalized);
        if (period == null) {
            return null;
        }

        Module module = matchModule(normalized);
        if (module == null) {
            return null;
        }

        if ("EMPLOYEE".equalsIgnoreCase(role)) {
            // Same NON_EMPLOYEE boundary every comparable tool in
            // CopilotToolCatalog already enforces for org-wide operational
            // counts - fail closed, same as everywhere else in this module.
            return "🔒 **Access Denied**: This count is not available for the employee role.";
        }

        Integer count = countRows(module, period);
        if (count == null) {
            return null;
        }

        return "**" + count + "** " + module.label + " " + period.label + ".";
    }

    private static Period matchPeriod(String normalized) {
        LocalDate today = LocalDate.now();
        if (normalized.contains("today")) {
            return new Period("today", today, today.plusDays(1));
        }
        if (normalized.contains("yesterday")) {
            return new Period("yesterday", today.minusDays(1), today);
        }
        if (normalized.contains("last month")) {
            LocalDate firstOfThisMonth = today.withDayOfMonth(1);
            return new Period("last month", firstOfThisMonth.minusMonths(1), firstOfThisMonth);
        }
        if (normalized.contains("this month")) {
            LocalDate firstOfThisMonth = today.withDayOfMonth(1);
            return new Period("this month", firstOfThisMonth, firstOfThisMonth.plusMonths(1));
        }
        return null;
    }

    private static Module matchModule(String normalized) {
        for (Module m : MODULES) {
            boolean allRequired = true;
            for (String req : m.requiredPhrases) {
                if (!normalized.contains(req)) {
                    allRequired = false;
                    break;
                }
            }
            if (!allRequired) {
                continue;
            }
            boolean anyExcluded = false;
            for (String bad : m.excludedPhrases) {
                if (normalized.contains(bad)) {
                    anyExcluded = true;
                    break;
                }
            }
            if (anyExcluded) {
                continue;
            }
            return m;
        }
        return null;
    }

    private static Integer countRows(Module module, Period period) {
        String sql = "SELECT COUNT(*) AS n FROM " + module.table + " WHERE "
                + module.dateColumn + " >= ? AND " + module.dateColumn + " < ?";
        try (Connection conn = DBConnection.getConnection();
             PreparedStatement ps = conn.prepareStatement(sql)) {
            // Timestamp (not Date), matching the convention already used
            // everywhere else in this codebase for the same created_at-style
            // range queries (see searchAssets/searchEmployees) - correct
            // against both DATE and TIMESTAMP columns, since this class
            // covers both (allocation_date/return_date are DATE;
            // created_at/request_date are TIMESTAMP).
            ps.setTimestamp(1, java.sql.Timestamp.valueOf(period.start.atStartOfDay()));
            ps.setTimestamp(2, java.sql.Timestamp.valueOf(period.endExclusive.atStartOfDay()));
            try (ResultSet rs = ps.executeQuery()) {
                if (rs.next()) {
                    return rs.getInt("n");
                }
            }
        } catch (Exception e) {
            LOGGER.log(Level.WARNING, "CopilotQuickAnswers count failed for " + module.table, e);
            return null;
        }
        return null;
    }
}
