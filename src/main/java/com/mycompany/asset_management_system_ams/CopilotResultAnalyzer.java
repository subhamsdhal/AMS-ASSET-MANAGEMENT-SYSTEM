package com.mycompany.asset_management_system_ams;

import java.util.List;
import java.util.Map;

/**
 * CopilotResultAnalyzer
 *
 * Analyzes raw DAO result before formatting:
 *   - Counts rows
 *   - Detects empty results and builds human-readable reason
 *   - Determines response style (TABLE / DETAIL / SUMMARY / COUNT_ONLY / EMPTY)
 *   - Decides whether Gemini polish is worth calling (skipped for empty/count-only)
 *   - Flags exportable results
 *
 * This class NEVER generates SQL. NEVER calls the DB.
 */
public class CopilotResultAnalyzer {

    // ── Response style constants ──────────────────────────────────────────────
    public static final String STYLE_TABLE      = "TABLE";
    public static final String STYLE_DETAIL     = "DETAIL";
    public static final String STYLE_SUMMARY    = "SUMMARY";
    public static final String STYLE_COUNT_ONLY = "COUNT_ONLY";
    public static final String STYLE_EMPTY      = "EMPTY";

    // ── Analysis result ───────────────────────────────────────────────────────

    public static class AnalysisResult {
        public final int     rowCount;
        public final boolean isEmpty;
        public final boolean isExportable;
        public final String  responseStyle;
        public final String  emptyReason;
        public final boolean callGeminiPolish;

        private AnalysisResult(int rowCount, boolean isEmpty, boolean isExportable,
                               String responseStyle, String emptyReason,
                               boolean callGeminiPolish) {
            this.rowCount        = rowCount;
            this.isEmpty         = isEmpty;
            this.isExportable    = isExportable;
            this.responseStyle   = responseStyle;
            this.emptyReason     = emptyReason;
            this.callGeminiPolish = callGeminiPolish;
        }
    }

    // ── Main analysis entry point ─────────────────────────────────────────────

    /**
     * Analyze a DAO result and produce an AnalysisResult with metadata
     * that helps the formatter decide how to present the answer.
     *
     * @param plan   the finalized query plan
     * @param result the raw DAO result map
     * @return AnalysisResult with row count, style, and export flag
     */
    @SuppressWarnings("unchecked")
    public static AnalysisResult analyze(CopilotQueryPlan plan, Map<String, Object> result) {

        if (result == null) {
            return new AnalysisResult(0, true, false, STYLE_EMPTY,
                "No response from database.", false);
        }

        // Error case
        if (result.containsKey("error")) {
            return new AnalysisResult(0, true, false, STYLE_EMPTY,
                String.valueOf(result.get("error")), false);
        }

        // ── Count rows ────────────────────────────────────────────────────────
        int rowCount = 0;
        boolean hasRecords = result.containsKey("records");

        if (hasRecords) {
            Object recs = result.get("records");
            if (recs instanceof List) rowCount = ((List<?>) recs).size();
        } else if (result.containsKey("count")) {
            Object cnt = result.get("count");
            if (cnt instanceof Number) rowCount = ((Number) cnt).intValue();
        } else if (result.containsKey("total")) {
            // aggregate result (e.g. ASSET_TOTAL_COST)
            rowCount = toInt(result.get("count")); // count of items in the aggregate
        }

        boolean isEmpty = rowCount == 0 && !hasAggregateData(result);
        boolean isExportable = hasRecords && rowCount > 0;

        // ── Determine response style ──────────────────────────────────────────
        String style = determineStyle(plan, rowCount, isEmpty);

        // ── Build empty reason ────────────────────────────────────────────────
        String emptyReason = isEmpty ? buildEmptyReason(plan) : null;

        // ── Decide Gemini polish ──────────────────────────────────────────────
        // Don't call Gemini for empty results, pure counts, or summaries
        boolean callGemini = !isEmpty
            && style != STYLE_COUNT_ONLY
            && style != STYLE_EMPTY;

        return new AnalysisResult(rowCount, isEmpty, isExportable, style,
                                  emptyReason, callGemini);
    }

    // ── Style determination ───────────────────────────────────────────────────

    private static String determineStyle(CopilotQueryPlan plan, int rowCount, boolean isEmpty) {
        if (isEmpty) return STYLE_EMPTY;

        if (plan.intent == null) return STYLE_TABLE;

        switch (plan.intent) {
            // Aggregate counts / totals → compact answer
            case ASSET_TOTAL_COST:
            case ASSET_COUNT:
            case ASSET_VALUE_SUMMARY:
                return STYLE_COUNT_ONLY;

            // Full dashboard summary
            case DASHBOARD_SUMMARY:
                return STYLE_SUMMARY;

            // Group-by summaries
            case DEPT_SUMMARY:
            case CATEGORY_SUMMARY:
            case SUPPLIER_SUMMARY:
            case ROLE_DUTY_SUMMARY:
                return STYLE_SUMMARY;

            // Single-record detail
            case EMPLOYEE_DETAILS:
            case ASSET_HOLDER:
                return rowCount == 1 ? STYLE_DETAIL : STYLE_TABLE;

            // Everything else → table
            default:
                return STYLE_TABLE;
        }
    }

    // ── Empty reason builder ──────────────────────────────────────────────────

    private static String buildEmptyReason(CopilotQueryPlan plan) {
        StringBuilder sb = new StringBuilder(
            "I checked the live AMS database but found **no matching records**");

        boolean first = true;

        if (plan.normalizedCategory != null) {
            sb.append(first ? " for " : " ");
            sb.append("**").append(plan.normalizedCategory).append("**");
            first = false;
        }
        if (plan.departmentName != null) {
            sb.append(first ? " for " : " in ");
            sb.append("**").append(plan.departmentName).append("**");
            first = false;
        }
        if (plan.assetCode != null) {
            sb.append(first ? " for asset " : ", asset ");
            sb.append("**").append(plan.assetCode).append("**");
            first = false;
        }
        if (plan.employeeCode != null) {
            sb.append(first ? " for employee " : ", employee ");
            sb.append("**").append(plan.employeeCode).append("**");
            first = false;
        }
        if (plan.employeeName != null) {
            sb.append(first ? " for " : " named ");
            sb.append("**").append(plan.employeeName).append("**");
            first = false;
        }
        if (plan.status != null) {
            sb.append(" with status **").append(plan.status).append("**");
        }

        sb.append(".");

        // Add a helpful follow-up suggestion
        if (plan.intent != null) {
            switch (plan.intent) {
                case ASSET_SEARCH:
                case AVAILABLE_ASSETS:
                case ALLOCATED_ASSETS:
                    sb.append("\n\n💡 Try: `show all assets` or specify a different department/category.");
                    break;
                case EMPLOYEE_DETAILS:
                case EMPLOYEE_ALLOCATIONS:
                    sb.append("\n\n💡 Try providing the employee code (e.g. `EMP006`) or a different name.");
                    break;
                case WARRANTY_EXPIRING_NEXT_N_DAYS:
                    sb.append("\n\n💡 Try: `warranty expiring in 60 days` to widen the range.");
                    break;
                default:
                    break;
            }
        }

        return sb.toString();
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    /** Returns true if result has aggregate data (total, count > 0) even if no rows. */
    private static boolean hasAggregateData(Map<String, Object> result) {
        if (result.containsKey("total")) {
            Object total = result.get("total");
            if (total != null) {
                try {
                    double d = Double.parseDouble(String.valueOf(total));
                    return d > 0;
                } catch (NumberFormatException ignored) {}
            }
        }
        return false;
    }

    private static int toInt(Object v) {
        if (v == null) return 0;
        try { return Integer.parseInt(String.valueOf(v)); }
        catch (NumberFormatException ignored) { return 0; }
    }
}
