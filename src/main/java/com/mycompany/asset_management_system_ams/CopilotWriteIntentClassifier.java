package com.mycompany.asset_management_system_ams;

import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.util.ArrayList;
import java.util.List;
import java.util.UUID;
import java.util.logging.Level;
import java.util.logging.Logger;

import jakarta.servlet.http.HttpSession;

/**
 * CopilotWriteIntentClassifier — lets natural language trigger the Copilot's
 * five NON-destructive write actions (allocate, return, approve, reject,
 * create maintenance request) even when phrased differently than
 * CopilotCommandDetector's fixed regex patterns expect.
 *
 * Before this class existed, a write request only reached
 * CopilotCommandExecutor if it happened to match one of CopilotCommandDetector's
 * hand-written regexes (e.g. `query.contains("allocate")`). Anything phrased
 * differently ("can you hand AST010 over to Priya in IT") fell straight
 * through to the read-only agent loop or the keyword fallback, which cannot
 * perform an action at all - so the user got a data answer, a clarification
 * request, or "please rephrase" for something that was actually a valid,
 * permitted instruction.
 *
 * Deliberately narrow and deliberately separate from CopilotAgentLoop's main
 * read-only reasoning loop:
 *
 *   - Only these five intents are ever offered - never create/update/delete.
 *     Those stay keyword-gated for the exact reason CopilotEngine's class doc
 *     already gives: an LLM misreading "delete" against live railway asset
 *     data is not recoverable the way a misread "show" is. These five are
 *     different in kind: every one is reversible (return undoes allocate,
 *     reject/approve can be redone by an admin, a maintenance request can be
 *     cancelled), and - since the write-pipeline hardening pass recorded in
 *     audit/27-ai-copilot.md - every one of their CopilotCommandExecutor
 *     methods now routes through the same guarded DAO its real UI screen
 *     uses (row locking, active-employee/allotment checks, etc.), not raw SQL.
 *   - One single-round, tools-only, temperature-0 request - not the full
 *     multi-round reasoning loop CopilotAgentLoop runs. This either
 *     identifies one of the five actions with its fields, or it doesn't;
 *     there is nothing to reason over multiple turns about.
 *   - Only invoked when CopilotCommandDetector's regex found nothing AND the
 *     message doesn't look like a question (the same
 *     looksLikeAnalyticalQuestion() gate CopilotCommandDetector itself runs
 *     first) - so this never spends an extra LLM call on the much more
 *     common case of an ordinary data question, which continues straight to
 *     the normal read-only agent loop exactly as before.
 *   - Builds the exact same CopilotCommandPlan shape the regex detector
 *     builds, then CopilotEngine hands it to the identical
 *     checkPermission()/missing-fields/confirmation/execute() pipeline the
 *     regex path already uses, completely unchanged. This class only ever
 *     replaces HOW the plan is understood - never how it is authorized,
 *     confirmed, executed, or audited. A role that could not perform an
 *     action by typing the exact regex phrasing still cannot perform it by
 *     phrasing it naturally: checkPermission() re-runs on whatever plan this
 *     class builds exactly as it does on a regex-built one.
 *
 * Failure is always soft: no key configured, no tools permitted for this
 * role, a provider error, or a response with no matching tool call all
 * return null, and CopilotEngine falls through to the normal read-only agent
 * loop exactly as if this class did not exist. A confident "this message is
 * not one of the five actions" (a tool-less response from a provider that
 * DID answer) is treated as a real answer, not a failure - providers after
 * it in the chain are not tried, since that would risk a second provider
 * guessing a tool call where the first one correctly found none.
 */
public final class CopilotWriteIntentClassifier {

    private static final Logger LOGGER = Logger.getLogger(CopilotWriteIntentClassifier.class.getName());

    private static final boolean DEBUG =
            "true".equalsIgnoreCase(System.getProperty("COPILOT_DEBUG", "false"));

    /** Deterministic classification, not conversation - a low, fixed budget is plenty for one tool call. */
    private static final double TEMPERATURE = 0.0;
    private static final int MAX_TOKENS = 300;

    private CopilotWriteIntentClassifier() {
    }

    public static CopilotCommandPlan classify(String question, String role, HttpSession session) {
        if (question == null || question.trim().isEmpty()) {
            return null;
        }
        // Same gate CopilotCommandDetector.detectCommand() itself applies
        // first - a question is never an instruction, and skipping the LLM
        // call entirely for the (far more common) analytical-question case
        // keeps this feature from adding latency/cost to normal Copilot use.
        if (CopilotCommandDetector.looksLikeAnalyticalQuestion(question.toLowerCase().trim())) {
            return null;
        }

        List<LlmToolSpec> tools = toolsForRole(role);
        if (tools.isEmpty()) {
            return null;
        }

        List<LlmClient> chain = LlmClientFactory.createChain();
        if (chain.isEmpty()) {
            return null;
        }

        LlmRequest request = new LlmRequest()
                .system(SYSTEM_PROMPT)
                .add(LlmMessage.user(question))
                .withTools(tools);
        request.temperature = TEMPERATURE;
        request.maxTokens = MAX_TOKENS;

        for (LlmClient client : chain) {
            request.model = client.modelName();
            LlmResponse response;
            try {
                response = client.chat(request);
            } catch (Exception e) {
                debug("PROVIDER EXCEPTION", client.providerName() + " - " + e.getMessage());
                continue; // try the next provider
            }

            if (response.isError()) {
                debug("PROVIDER FAIL", client.providerName() + " - " + response.error);
                continue; // try the next provider
            }

            if (!response.hasToolCalls()) {
                // A provider that DID answer and confidently found no
                // matching action - a real "no", not a failure. Do not try
                // another provider, which could easily land a different
                // (wrong) guess where this one correctly found nothing.
                debug("NO ACTION", "Message does not match a write intent.");
                return null;
            }

            LlmToolCall call = response.toolCalls.get(0);
            debug("CLASSIFIED", call.name + " " + call.arguments);
            return buildPlan(call, question);
        }

        debug("CHAIN EXHAUSTED", "Every provider failed during write-intent classification.");
        return null;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // TOOL DEFINITIONS
    // ─────────────────────────────────────────────────────────────────────────

    private static final String SYSTEM_PROMPT =
            "You turn one IR-AMS chat message into at most one structured action call, or none at all.\n"
            + "Only call a tool when the message clearly and unambiguously requests that exact action "
            + "right now. If the message is a question, a data lookup, a vague statement, or does not "
            + "match any tool well, call no tool at all - do not guess, and never call more than one tool.\n"
            + "Extract an asset or employee CODE exactly as written when the message gives one (e.g. "
            + "AST010, EMP004). When it names a person or asset by name or description instead of a code "
            + "(e.g. \"the new laptop\", \"Priya\"), put that text in the matching Name/description field "
            + "instead of guessing a code - the system will resolve it, or ask the user to clarify if it "
            + "can't.";

    private static List<LlmToolSpec> toolsForRole(String role) {
        List<LlmToolSpec> tools = new ArrayList<LlmToolSpec>();

        if (permits(CopilotIntentType.ALLOCATE_ASSET, "ALLOCATION", role)) {
            tools.add(new LlmToolSpec("allocate_asset",
                    "Allocate/assign/hand over an asset to an employee. Only for a direct instruction to "
                            + "do this now, e.g. 'allocate AST010 to EMP004' or 'give the new laptop to Priya'.")
                    .param("asset", "The asset's code if known (e.g. AST010), otherwise its name/description")
                    .param("employee", "The employee's code if known (e.g. EMP004), otherwise their name"));
        }

        if (permits(CopilotIntentType.RETURN_ASSET, "RETURN", role)) {
            tools.add(new LlmToolSpec("return_asset",
                    "Process the return of an allocated asset. Only for a direct instruction to do this "
                            + "now, e.g. 'return AST010' or 'mark the projector as returned'.")
                    .param("asset", "The asset's code if known (e.g. AST010), otherwise its name/description"));
        }

        if (permits(CopilotIntentType.APPROVE_ASSET_REQUEST, "REQUESTS", role)) {
            tools.add(new LlmToolSpec("approve_asset_request",
                    "Approve (or, for a Department Head, forward) a pending asset request. Only for a "
                            + "direct instruction to do this now, e.g. 'approve request 42'.")
                    .param("requestId", "The numeric asset request id"));
        }

        if (permits(CopilotIntentType.REJECT_ASSET_REQUEST, "REQUESTS", role)) {
            tools.add(new LlmToolSpec("reject_asset_request",
                    "Reject a pending asset request. Only for a direct instruction to do this now, e.g. "
                            + "'reject request 42, no budget left'.")
                    .param("requestId", "The numeric asset request id")
                    .param("reason", "The stated reason for rejection"));
        }

        if (permits(CopilotIntentType.CREATE_MAINTENANCE_REQUEST, "MAINTENANCE", role)) {
            tools.add(new LlmToolSpec("create_maintenance_request",
                    "File a maintenance request for an asset. Only for a direct instruction to do this "
                            + "now, e.g. 'raise a maintenance request for AST010, screen is flickering'.")
                    .param("asset", "The asset's code if known (e.g. AST010), otherwise its name/description")
                    .param("issue", "The issue being reported, in the user's own words"));
        }

        return tools;
    }

    /**
     * Delegates to CopilotCommandExecutor.checkPermission() itself, rather
     * than re-deriving each role's allowances here, so this pre-filter can
     * never drift out of sync with the authoritative check that runs again
     * anyway once a plan is built - the same "filter with the same rule you
     * re-verify with" discipline CopilotToolCatalog.forRole()/execute()
     * already follows for the read-only side.
     */
    private static boolean permits(CopilotIntentType intent, String targetModule, String role) {
        CopilotCommandPlan probe = new CopilotCommandPlan();
        probe.intent = intent;
        probe.targetModule = targetModule;
        return CopilotCommandExecutor.checkPermission(probe, role);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // PLAN BUILDING
    // ─────────────────────────────────────────────────────────────────────────

    private static CopilotCommandPlan buildPlan(LlmToolCall call, String rawQuestion) {
        CopilotCommandPlan plan = new CopilotCommandPlan();
        plan.rawUserMessage = rawQuestion;

        if ("allocate_asset".equals(call.name)) {
            plan.intent = CopilotIntentType.ALLOCATE_ASSET;
            plan.targetModule = "ALLOCATION";
            plan.actionType = "CREATE";
            putIfPresent(plan, "assetCode", resolveAssetCode(call.arg("asset")));
            putIfPresent(plan, "employeeCode", resolveEmployeeCode(call.arg("employee")));
            checkRequired(plan, "assetCode", "employeeCode");
            confirm(plan, "allocate asset " + display(plan, "assetCode")
                    + " to employee " + display(plan, "employeeCode"));
            return plan;
        }

        if ("return_asset".equals(call.name)) {
            plan.intent = CopilotIntentType.RETURN_ASSET;
            plan.targetModule = "RETURN";
            plan.actionType = "CREATE";
            putIfPresent(plan, "assetCode", resolveAssetCode(call.arg("asset")));
            checkRequired(plan, "assetCode");
            confirm(plan, "return asset " + display(plan, "assetCode"));
            return plan;
        }

        if ("approve_asset_request".equals(call.name)) {
            plan.intent = CopilotIntentType.APPROVE_ASSET_REQUEST;
            plan.targetModule = "REQUESTS";
            plan.actionType = "UPDATE";
            putIfPresent(plan, "targetId", digitsOnly(call.arg("requestId")));
            checkRequired(plan, "targetId");
            confirm(plan, "approve request " + display(plan, "targetId"));
            return plan;
        }

        if ("reject_asset_request".equals(call.name)) {
            plan.intent = CopilotIntentType.REJECT_ASSET_REQUEST;
            plan.targetModule = "REQUESTS";
            plan.actionType = "UPDATE";
            putIfPresent(plan, "targetId", digitsOnly(call.arg("requestId")));
            putIfPresent(plan, "reason", call.arg("reason"));
            checkRequired(plan, "targetId", "reason");
            confirm(plan, "reject request " + display(plan, "targetId")
                    + " with reason: " + display(plan, "reason"));
            return plan;
        }

        if ("create_maintenance_request".equals(call.name)) {
            plan.intent = CopilotIntentType.CREATE_MAINTENANCE_REQUEST;
            plan.targetModule = "MAINTENANCE";
            plan.actionType = "CREATE";
            putIfPresent(plan, "assetCode", resolveAssetCode(call.arg("asset")));
            putIfPresent(plan, "issue", call.arg("issue"));
            checkRequired(plan, "assetCode", "issue");
            confirm(plan, "create maintenance request for " + display(plan, "assetCode")
                    + " with issue: " + display(plan, "issue"));
            return plan;
        }

        // An unrecognised tool name (a provider hallucinating one outside
        // what was ever offered) - treat exactly like "no tool call".
        return null;
    }

    private static void putIfPresent(CopilotCommandPlan plan, String field, String value) {
        if (value != null && !value.trim().isEmpty()) {
            plan.extractedFields.put(field, value.trim());
        }
    }

    private static String display(CopilotCommandPlan plan, String field) {
        String value = plan.extractedFields.get(field);
        return value != null ? value : "?";
    }

    private static void checkRequired(CopilotCommandPlan plan, String... fields) {
        for (String field : fields) {
            String value = plan.extractedFields.get(field);
            if (value == null || value.isEmpty()) {
                plan.missingRequiredFields.add(field);
            }
        }
    }

    /** All five classified intents are non-destructive - a simple "confirm" gate, never a typed phrase. */
    private static void confirm(CopilotCommandPlan plan, String previewMessage) {
        plan.requiresConfirmation = true;
        plan.destructiveAction = false;
        plan.previewMessage = previewMessage;
        plan.confirmationToken = UUID.randomUUID().toString();
    }

    private static String digitsOnly(String value) {
        if (value == null) {
            return null;
        }
        String digits = value.replaceAll("[^0-9]", "");
        return digits.isEmpty() ? null : digits;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // NAME/CODE RESOLUTION
    // ─────────────────────────────────────────────────────────────────────────

    private static final java.util.regex.Pattern ASSET_CODE = java.util.regex.Pattern.compile("(?i)^ast\\d{3,6}$");
    private static final java.util.regex.Pattern EMPLOYEE_CODE = java.util.regex.Pattern.compile("(?i)^emp\\d{3,6}$");

    /**
     * A code the model already extracted verbatim (AST010) is trusted as-is -
     * CopilotCommandExecutor's own getAssetId() look-up is the real
     * verification step, exactly as it is for the regex-detected path. Any
     * other text is treated as a name/description and resolved only when it
     * matches EXACTLY one asset - ambiguous or no matches deliberately fall
     * through to "missing field" rather than guessing, since a wrong asset
     * code here would carry into a real allocation/return/maintenance
     * request.
     */
    private static String resolveAssetCode(String raw) {
        if (raw == null || raw.trim().isEmpty()) {
            return null;
        }
        String trimmed = raw.trim();
        if (ASSET_CODE.matcher(trimmed).matches()) {
            return trimmed.toUpperCase();
        }
        String sql = "SELECT asset_code FROM assets WHERE asset_name LIKE ? OR asset_code = ? LIMIT 2";
        try (Connection con = DBConnection.getConnection();
             PreparedStatement ps = con.prepareStatement(sql)) {
            ps.setString(1, "%" + trimmed + "%");
            ps.setString(2, trimmed.toUpperCase());
            try (ResultSet rs = ps.executeQuery()) {
                String match = null;
                int count = 0;
                while (rs.next()) {
                    count++;
                    match = rs.getString(1);
                }
                return count == 1 ? match : null;
            }
        } catch (Exception e) {
            LOGGER.log(Level.WARNING, "Asset name resolution failed for '" + trimmed + "'", e);
            return null;
        }
    }

    /** Same reasoning as resolveAssetCode() - trust a real code, resolve a name only when unambiguous. */
    private static String resolveEmployeeCode(String raw) {
        if (raw == null || raw.trim().isEmpty()) {
            return null;
        }
        String trimmed = raw.trim();
        if (EMPLOYEE_CODE.matcher(trimmed).matches()) {
            return trimmed.toUpperCase();
        }
        String sql = "SELECT employee_code FROM employees "
                + "WHERE (employee_name LIKE ? OR employee_code = ?) AND employee_status = 'ACTIVE' LIMIT 2";
        try (Connection con = DBConnection.getConnection();
             PreparedStatement ps = con.prepareStatement(sql)) {
            ps.setString(1, "%" + trimmed + "%");
            ps.setString(2, trimmed.toUpperCase());
            try (ResultSet rs = ps.executeQuery()) {
                String match = null;
                int count = 0;
                while (rs.next()) {
                    count++;
                    match = rs.getString(1);
                }
                return count == 1 ? match : null;
            }
        } catch (Exception e) {
            LOGGER.log(Level.WARNING, "Employee name resolution failed for '" + trimmed + "'", e);
            return null;
        }
    }

    private static void debug(String label, String value) {
        if (DEBUG) {
            System.out.println("[COPILOT-WRITE-CLASSIFIER] " + String.format("%-14s", label) + ": " + value);
        }
        LOGGER.log(Level.FINE, "[COPILOT-WRITE-CLASSIFIER] {0}: {1}", new Object[]{label, value});
    }
}
