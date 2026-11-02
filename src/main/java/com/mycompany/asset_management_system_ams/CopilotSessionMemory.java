package com.mycompany.asset_management_system_ams;

import jakarta.servlet.http.HttpSession;
import java.util.List;
import java.util.Map;

/**
 * CopilotSessionMemory
 *
 * Wraps HttpSession with structured, typed getters/setters for all
 * Copilot memory fields. Eliminates raw getAttribute/setAttribute calls
 * scattered across the codebase.
 *
 * Stored per-session (not per-user), which is correct because one browser
 * tab = one conversation context.
 *
 * Follow-up detection:
 *   "what about stores?"    → reuse last intent, swap department
 *   "same for printers?"    → reuse last intent, swap category
 *   "show more"             → reuse last plan unchanged (pagination)
 *   "export this"           → handled separately in CopilotEngine
 */
public class CopilotSessionMemory {

    // ── Session attribute keys (package-private for testing) ──────────────────
    static final String KEY_LAST_RAW       = "copilotLastRaw";
    static final String KEY_LAST_NORM      = "copilotLastNormalized";
    static final String KEY_LAST_INTENT    = "copilotLastIntent";
    static final String KEY_LAST_PLAN      = "copilotLastQueryPlan";
    static final String KEY_LAST_CATEGORY  = "copilotLastCategory";
    static final String KEY_LAST_DEPT      = "copilotLastDept";
    static final String KEY_LAST_ASSET     = "copilotLastAsset";
    static final String KEY_LAST_EMP_CODE  = "copilotLastEmpCode";
    static final String KEY_LAST_EMP_NAME  = "copilotLastEmpName";
    static final String KEY_LAST_STATUS    = "copilotLastStatus";
    static final String KEY_LAST_MODULE    = "copilotLastModule";
    static final String KEY_LAST_TITLE     = "copilotLastTitle";
    static final String KEY_LAST_ROW_COUNT = "copilotLastResultRows";
    static final String KEY_EXPORTABLE     = "copilotLastResultExportable";

    // ── Save / persist ────────────────────────────────────────────────────────

    /**
     * Save the completed query result to session memory.
     * Call this after the DAO returns and before formatting.
     *
     * @param session   active HTTP session
     * @param plan      the finalized query plan
     * @param result    the DAO result map
     * @param title     a short human title for this result (used by export)
     */
    @SuppressWarnings("unchecked")
    public static void save(HttpSession session, CopilotQueryPlan plan,
                            Map<String, Object> result, String title) {
        if (session == null || plan == null) return;

        safeSet(session, KEY_LAST_RAW,    plan.rawUserMessage);
        safeSet(session, KEY_LAST_NORM,   plan.normalizedTextForNLU);
        safeSet(session, KEY_LAST_INTENT, plan.intent != null ? plan.intent.name() : null);
        safeSet(session, KEY_LAST_PLAN,   plan);
        safeSet(session, KEY_LAST_CATEGORY, plan.normalizedCategory);
        safeSet(session, KEY_LAST_DEPT,     plan.departmentName);
        safeSet(session, KEY_LAST_ASSET,    plan.assetCode);
        safeSet(session, KEY_LAST_EMP_CODE, plan.employeeCode);
        safeSet(session, KEY_LAST_EMP_NAME, plan.employeeName);
        safeSet(session, KEY_LAST_STATUS,   plan.status);
        safeSet(session, KEY_LAST_MODULE,   plan.targetModule);
        safeSet(session, KEY_LAST_TITLE,    title != null ? title : "AMS Report");

        // Count and exportable flag
        int rowCount = 0;
        boolean exportable = false;
        if (result != null) {
            if (result.containsKey("records")) {
                Object recs = result.get("records");
                if (recs instanceof List) {
                    rowCount = ((List<?>) recs).size();
                    exportable = rowCount > 0;
                }
            } else if (result.containsKey("count")) {
                // aggregate result — exportable if there is meaningful data
                exportable = false;
            }
        }
        safeSet(session, KEY_LAST_ROW_COUNT, rowCount);
        safeSet(session, KEY_EXPORTABLE, exportable);
    }

    // ── Load ──────────────────────────────────────────────────────────────────

    /** Returns the last saved CopilotQueryPlan, or null if none. */
    public static CopilotQueryPlan loadLastPlan(HttpSession session) {
        Object v = safeGet(session, KEY_LAST_PLAN);
        return (v instanceof CopilotQueryPlan) ? (CopilotQueryPlan) v : null;
    }

    public static String getLastIntent(HttpSession session) {
        Object v = safeGet(session, KEY_LAST_INTENT);
        return v != null ? String.valueOf(v) : null;
    }

    public static String getLastCategory(HttpSession session) {
        Object v = safeGet(session, KEY_LAST_CATEGORY);
        return v != null ? String.valueOf(v) : null;
    }

    public static String getLastDepartment(HttpSession session) {
        Object v = safeGet(session, KEY_LAST_DEPT);
        return v != null ? String.valueOf(v) : null;
    }

    public static String getLastModule(HttpSession session) {
        Object v = safeGet(session, KEY_LAST_MODULE);
        return v != null ? String.valueOf(v) : null;
    }

    public static boolean isLastResultExportable(HttpSession session) {
        Object v = safeGet(session, KEY_EXPORTABLE);
        return Boolean.TRUE.equals(v);
    }

    public static int getLastRowCount(HttpSession session) {
        Object v = safeGet(session, KEY_LAST_ROW_COUNT);
        if (v instanceof Number) return ((Number) v).intValue();
        return 0;
    }

    // ── Follow-up detection ───────────────────────────────────────────────────

    /**
     * Determines whether the new plan is a follow-up to the last query.
     *
     * Patterns detected:
     *   1. "what about [department]?"   → new dept, reuse last intent
     *   2. "same for [category]?"       → new cat, reuse last intent
     *   3. "show more"                  → reuse entire plan
     *   4. "filter by [status]"         → reuse plan + add status
     *
     * Returns true if the new plan's intent is UNKNOWN but we can resolve
     * it from the session context.
     */
    public static boolean isFollowUp(HttpSession session, CopilotQueryPlan newPlan) {
        if (session == null || newPlan == null) return false;
        String lastIntent = getLastIntent(session);
        if (lastIntent == null) return false;

        // Don't apply follow-up logic if intent was already resolved
        if (newPlan.intent != CopilotIntentType.UNKNOWN) {
            // May still be a partial follow-up (new dept, same intent)
            // Only merge if the new plan has fewer entities than last plan
            return false;
        }

        // UNKNOWN intent + previous context → this is a follow-up
        return true;
    }

    /**
     * Build a follow-up plan by inheriting the last saved plan entities
     * and merging any new entities found in the current plan.
     *
     * New entities always override inherited ones.
     */
    public static CopilotQueryPlan buildFollowUpPlan(HttpSession session,
                                                      CopilotQueryPlan currentPlan) {
        CopilotQueryPlan lastPlan = loadLastPlan(session);
        if (lastPlan == null) return currentPlan;

        CopilotQueryPlan merged = new CopilotQueryPlan();
        merged.rawUserMessage        = currentPlan.rawUserMessage;
        merged.normalizedTextForNLU  = currentPlan.normalizedTextForNLU;
        merged.isFollowUp            = true;

        // Inherit intent from last plan
        merged.intent        = lastPlan.intent;
        merged.confidence    = 0.7; // moderate — inherited context
        merged.needsDatabase = true;
        merged.sqlTemplateName = lastPlan.sqlTemplateName;
        merged.targetModule  = lastPlan.targetModule;

        // Merge entities: new plan values take priority over last plan values
        merged.normalizedCategory = currentPlan.normalizedCategory != null
            ? currentPlan.normalizedCategory : lastPlan.normalizedCategory;
        merged.rawCategory = currentPlan.rawCategory != null
            ? currentPlan.rawCategory : lastPlan.rawCategory;
        merged.departmentName = currentPlan.departmentName != null
            ? currentPlan.departmentName : lastPlan.departmentName;
        merged.assetCode    = currentPlan.assetCode != null
            ? currentPlan.assetCode : lastPlan.assetCode;
        merged.employeeCode = currentPlan.employeeCode != null
            ? currentPlan.employeeCode : lastPlan.employeeCode;
        merged.employeeName = currentPlan.employeeName != null
            ? currentPlan.employeeName : lastPlan.employeeName;
        merged.status       = currentPlan.status != null
            ? currentPlan.status : lastPlan.status;
        merged.days         = currentPlan.days != null
            ? currentPlan.days : lastPlan.days;
        merged.startDate    = currentPlan.startDate != null
            ? currentPlan.startDate : lastPlan.startDate;
        merged.endDate      = currentPlan.endDate != null
            ? currentPlan.endDate : lastPlan.endDate;
        merged.dateRangeRaw = currentPlan.dateRangeRaw != null
            ? currentPlan.dateRangeRaw : lastPlan.dateRangeRaw;

        // Follow-up context description
        StringBuilder ctx = new StringBuilder();
        if (merged.normalizedCategory != null) ctx.append("category=").append(merged.normalizedCategory).append(" ");
        if (merged.departmentName     != null) ctx.append("dept=").append(merged.departmentName).append(" ");
        merged.followUpContext = "Continuing last query: " + lastPlan.intent.name() +
            (ctx.length() > 0 ? " [" + ctx.toString().trim() + "]" : "");

        return merged;
    }

    // ── Clear ─────────────────────────────────────────────────────────────────

    /** Remove all Copilot memory from session. */
    public static void clear(HttpSession session) {
        if (session == null) return;
        for (String key : new String[]{
            KEY_LAST_RAW, KEY_LAST_NORM, KEY_LAST_INTENT, KEY_LAST_PLAN,
            KEY_LAST_CATEGORY, KEY_LAST_DEPT, KEY_LAST_ASSET,
            KEY_LAST_EMP_CODE, KEY_LAST_EMP_NAME, KEY_LAST_STATUS,
            KEY_LAST_MODULE, KEY_LAST_TITLE, KEY_LAST_ROW_COUNT, KEY_EXPORTABLE
        }) {
            try {
                session.removeAttribute(key);
            } catch (IllegalStateException alreadyInvalidated) {
                // Nothing left to clear - same end state either way.
                return;
            }
        }
    }

    // ── Session-safety helpers ──────────────────────────────────────────────
    //
    // session.getAttribute()/setAttribute() throw IllegalStateException (not
    // "return null") once the session has been invalidated - by a timeout, a
    // logout in another tab, or a deploy racing a slow in-flight request.
    // Found live: a 30-second LLM provider-fallback chain outlived the
    // session, and the FIRST unguarded session.getAttribute() call afterward
    // (in CopilotReasoningPlanner, which calls straight into this class)
    // turned a normal "provider chain exhausted, use the keyword fallback"
    // path into an unhandled exception and a generic "internal server issue"
    // for the user. Every read/write in this class goes through these two
    // helpers so a dead session degrades the same way a null one already did
    // - silently, safely - rather than blowing up wherever it is next touched.

    private static Object safeGet(HttpSession session, String key) {
        if (session == null) return null;
        try {
            return session.getAttribute(key);
        } catch (IllegalStateException alreadyInvalidated) {
            return null;
        }
    }

    private static void safeSet(HttpSession session, String key, Object value) {
        if (session == null) return;
        try {
            session.setAttribute(key, value);
        } catch (IllegalStateException alreadyInvalidated) {
            // Nothing to persist to - the caller's own answer still returns fine.
        }
    }
}
