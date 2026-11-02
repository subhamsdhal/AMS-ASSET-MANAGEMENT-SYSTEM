package com.mycompany.asset_management_system_ams;

import jakarta.servlet.http.HttpSession;

/**
 * CopilotReasoningPlanner
 *
 * Sits between CopilotIntentDetector and CopilotToolExecutor.
 * Validates entity completeness, applies role-based access control,
 * and routes the query to the right execution path.
 *
 * Routing rules:
 *   confidence >= 0.6 AND all required entities present → execute immediately
 *   confidence >= 0.4 AND at least one entity clear     → execute safest read tool
 *   confidence >= 0.2 AND at least one entity           → fallback ASSET_SEARCH
 *   confidence < 0.2                                    → generate targeted clarification
 *   role not allowed for this module                    → access denied
 *
 * This class NEVER generates SQL. NEVER calls the DB.
 */
public class CopilotReasoningPlanner {

    private static final boolean DEBUG =
        "true".equalsIgnoreCase(System.getProperty("COPILOT_DEBUG", "false"));

    /**
     * Validate and enrich the raw plan from the intent detector.
     * Returns a (possibly modified) plan ready for tool execution.
     *
     * @param plan    raw plan from CopilotIntentDetector
     * @param session current HTTP session (for role and follow-up context)
     * @return validated, enriched CopilotQueryPlan
     */
    public static CopilotQueryPlan plan(CopilotQueryPlan rawPlan, HttpSession session) {
        if (rawPlan == null) return unknownPlan("Null plan received.");

        // Fault, found live: a session that is non-null but was invalidated
        // out from under this request (redeploy, timeout, or a slow
        // multi-provider LLM fallback outliving the session) makes EVERY
        // method on it throw IllegalStateException, not just return null -
        // "session != null" alone doesn't mean "session usable". That
        // propagated up through CopilotEngine's outer catch as a generic
        // "internal server issue" for what should have been a normal
        // graceful degrade, exactly like the session==null case already is.
        String role = safeSessionAttribute(session, "role");
        if (role == null) {
            role = "UNKNOWN";
        }

        debugLog("PLANNER IN", rawPlan.intent + " conf=" +
            String.format("%.2f", rawPlan.confidence));

        // ── Step 1: Follow-up detection ─────────────────────────────────────
        if (rawPlan.intent == CopilotIntentType.UNKNOWN
                && CopilotSessionMemory.isFollowUp(session, rawPlan)) {
            CopilotQueryPlan merged = CopilotSessionMemory.buildFollowUpPlan(session, rawPlan);
            debugLog("PLANNER", "Follow-up detected → " + merged.intent);
            return merged;
        }

        // ── Step 2: "show more" → reuse last plan ───────────────────────────
        if (rawPlan.normalizedTextForNLU != null) {
            String q = rawPlan.normalizedTextForNLU.toLowerCase();
            if (q.contains("show more") || q.equals("more") || q.equals("continue")
                    || q.equals("next page")) {
                CopilotQueryPlan lastPlan = CopilotSessionMemory.loadLastPlan(session);
                if (lastPlan != null) {
                    debugLog("PLANNER", "Pagination → reusing last plan");
                    lastPlan.rawUserMessage = rawPlan.rawUserMessage;
                    lastPlan.isFollowUp = true;
                    lastPlan.followUpContext = "Showing more of previous result.";
                    return lastPlan;
                }
            }
        }

        // ── Step 3: "What can you do in [module]?" ───────────────────────────
        if (rawPlan.intent == CopilotIntentType.HELP_NAVIGATION) {
            rawPlan.targetModule = detectModuleFromQuery(rawPlan.normalizedTextForNLU);
            debugLog("PLANNER", "Help → module=" + rawPlan.targetModule);
            return rawPlan;
        }

        // ── Step 4: Role-based access control check ──────────────────────────
        if (!CopilotProjectModuleRegistry.isToolAllowed(rawPlan.intent, role)) {
            CopilotQueryPlan denied = new CopilotQueryPlan();
            denied.intent     = CopilotIntentType.UNKNOWN;
            denied.confidence = 0.0;
            denied.clarificationNeeded = true;
            denied.clarificationPrompt =
                "🔒 **Access Denied**: Your role (**" + role + "**) does not have " +
                "permission to view this information.";
            debugLog("PLANNER", "Access denied for role=" + role +
                " intent=" + rawPlan.intent);
            return denied;
        }

        // ── Step 5: Enrich plan with target module ───────────────────────────
        CopilotProjectModuleRegistry.ModuleDescriptor mod =
            CopilotProjectModuleRegistry.findModuleForIntent(rawPlan.intent);
        if (mod != null) {
            rawPlan.targetModule = mod.moduleName;
        }

        // ── Step 6: Confidence routing ───────────────────────────────────────

        // HIGH confidence → execute as-is
        if (rawPlan.confidence >= 0.55) {
            // Fill smart defaults for specific intents
            fillSmartDefaults(rawPlan);
            debugLog("PLANNER", "HIGH confidence → direct execute");
            return rawPlan;
        }

        // MEDIUM confidence → execute if entities are clear
        if (rawPlan.confidence >= 0.35) {
            if (hasUsefulEntities(rawPlan)) {
                fillSmartDefaults(rawPlan);
                debugLog("PLANNER", "MEDIUM confidence + entities → execute");
                return rawPlan;
            }
            // No entities → targeted clarification
            rawPlan.clarificationNeeded = true;
            rawPlan.clarificationPrompt = buildTargetedClarification(rawPlan);
            rawPlan.intent = CopilotIntentType.UNKNOWN;
            debugLog("PLANNER", "MEDIUM confidence, no entities → clarify");
            return rawPlan;
        }

        // LOW confidence but entities present → fallback ASSET_SEARCH
        if (rawPlan.confidence >= 0.15 && hasUsefulEntities(rawPlan)) {
            rawPlan.intent       = CopilotIntentType.ASSET_SEARCH;
            rawPlan.confidence   = 0.35;
            rawPlan.needsDatabase = true;
            rawPlan.sqlTemplateName = "ASSET_SEARCH_FALLBACK";
            debugLog("PLANNER", "LOW confidence + entities → ASSET_SEARCH fallback");
            return rawPlan;
        }

        // UNKNOWN → targeted clarification prompt
        if (rawPlan.intent == CopilotIntentType.UNKNOWN || rawPlan.confidence < 0.15) {
            rawPlan.clarificationNeeded = true;
            rawPlan.clarificationPrompt = buildGeneralClarification();
            debugLog("PLANNER", "UNKNOWN/very low → general clarification");
        }

        return rawPlan;
    }

    // ── Smart defaults ────────────────────────────────────────────────────────

    private static void fillSmartDefaults(CopilotQueryPlan plan) {
        // Default warranty days to 30 if not set
        if (plan.intent == CopilotIntentType.WARRANTY_EXPIRING_NEXT_N_DAYS
                && plan.days == null) {
            plan.days = 30;
        }
    }

    // ── Entity check ──────────────────────────────────────────────────────────

    private static boolean hasUsefulEntities(CopilotQueryPlan plan) {
        return plan.normalizedCategory != null
            || plan.departmentName != null
            || plan.assetCode != null
            || plan.employeeCode != null
            || plan.employeeName != null
            || plan.status != null;
    }

    // ── Module detection from query ───────────────────────────────────────────

    private static String detectModuleFromQuery(String normalizedText) {
        if (normalizedText == null) return null;
        CopilotProjectModuleRegistry.ModuleDescriptor d =
            CopilotProjectModuleRegistry.findModuleByPhrase(normalizedText);
        return d != null ? d.moduleName : null;
    }

    // ── Clarification builders ────────────────────────────────────────────────

    private static String buildTargetedClarification(CopilotQueryPlan plan) {
        switch (plan.intent) {
            case WARRANTY_EXPIRING_NEXT_N_DAYS:
                return "How many days ahead should I check for warranty expiry? " +
                       "(e.g. **30**, **60**, or **90 days**)";
            case EMPLOYEE_ALLOCATIONS:
            case EMPLOYEE_DETAILS:
                return "Which employee? Please provide an employee code " +
                       "(e.g. **EMP006**) or type a name.";
            case MAINTENANCE_HISTORY:
                return "Which asset's maintenance history? Please provide an asset code " +
                       "(e.g. **AST003**).";
            case ASSET_HOLDER:
                return "Which asset are you asking about? Please provide an asset code " +
                       "(e.g. **AST001**).";
            case ASSET_SEARCH:
                return "What would you like to filter by? You can say a **category** " +
                       "(e.g. Laptop), **department** (e.g. IT department), or **status** " +
                       "(e.g. available, disposed).";
            default:
                return buildGeneralClarification();
        }
    }

    private static String buildGeneralClarification() {
        return "I can help with many things. Here are some examples:\n\n" +
               "- 🖥️ **Asset cost**: `total cost of laptops`\n" +
               "- 📋 **Asset list**: `show laptops in IT department`\n" +
               "- 👤 **Employee**: `employee details of EMP006`\n" +
               "- 🔧 **Maintenance**: `pending maintenance` / `history of AST003`\n" +
               "- 🔑 **Warranty**: `warranty expiring in 30 days`\n" +
               "- 📊 **Reports**: `total value of assets department wise`\n" +
               "- 📝 **Requests**: `show pending asset requests`\n" +
               "- 🔲 **QR**: `show QR scan logs`\n" +
               "- 📁 **Audit**: `show audit logs`\n\n" +
               "Please rephrase your question or type **help** for more examples.";
    }

    // ── Unknown plan helper ───────────────────────────────────────────────────

    private static CopilotQueryPlan unknownPlan(String reason) {
        CopilotQueryPlan p = new CopilotQueryPlan();
        p.intent = CopilotIntentType.UNKNOWN;
        p.confidence = 0.0;
        p.clarificationNeeded = true;
        p.clarificationPrompt = reason + " " + buildGeneralClarification();
        return p;
    }

    private static void debugLog(String label, String value) {
        if (DEBUG) System.out.println("[COPILOT-DEBUG] " + label + ": " + value);
    }

    /**
     * session.getAttribute() throws IllegalStateException (not "returns
     * null") once the session has been invalidated - by a timeout, a logout
     * in another tab, or a deploy racing a slow request. A null-check on the
     * session reference does not catch that. Treated the same as "no
     * session" rather than left to blow up the whole request.
     */
    private static String safeSessionAttribute(HttpSession session, String key) {
        if (session == null) {
            return null;
        }
        try {
            Object value = session.getAttribute(key);
            return value == null ? null : String.valueOf(value);
        } catch (IllegalStateException invalidated) {
            return null;
        }
    }
}
