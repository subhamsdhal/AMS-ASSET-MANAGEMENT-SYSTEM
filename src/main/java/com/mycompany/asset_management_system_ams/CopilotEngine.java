package com.mycompany.asset_management_system_ams;

import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.io.OutputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.nio.charset.StandardCharsets;
import java.util.Map;
import java.util.logging.Level;
import java.util.logging.Logger;
import org.json.JSONArray;
import org.json.JSONObject;
import jakarta.servlet.http.HttpSession;

/**
 * CopilotEngine — Main orchestrator for the AMS Copilot pipeline.
 *
 * Stages run in order, each one a fallback for the stage before it:
 *
 *   A. Pending write-command confirmation (session-scoped, see below)
 *   B. CopilotCommandDetector   — strict keyword matching for WRITE actions
 *                                 (create/update/delete/allocate/...) plus a
 *                                 typed-confirmation gate. Deliberately kept
 *                                 keyword-based: an LLM misreading "delete" on
 *                                 live railway asset data is not recoverable
 *                                 the way a misread "show" is.
 *   B1. CopilotWriteIntentClassifier — an LLM-assisted second chance at
 *                                 exactly five NON-destructive, already
 *                                 fully-guarded write actions (allocate,
 *                                 return, approve/reject a request, create a
 *                                 maintenance request) when B's regexes don't
 *                                 match a phrasing but the message still
 *                                 isn't a question. Never create/update/
 *                                 delete - those stay keyword-only for the
 *                                 same reason B does. Builds the same
 *                                 CopilotCommandPlan shape B does and is
 *                                 handed to the identical
 *                                 checkPermission()/confirmation/execute()
 *                                 pipeline (handleCommandPlan() below) - this
 *                                 stage only changes HOW a plan is
 *                                 understood, never how it is authorized or
 *                                 run.
 *   B2. CopilotAgentLoop        — the real understanding layer for everything
 *                                 else. An LLM plans which read-only tools to
 *                                 call (CopilotToolCatalog → CopilotToolExecutor,
 *                                 PreparedStatement-backed DAO only), reasons
 *                                 over the real rows, and answers from meaning,
 *                                 not from a fixed keyword→intent table. Sees
 *                                 recent conversation turns (CopilotChatMemory)
 *                                 so it can resolve "it", "the second one",
 *                                 "what about last month" without those words
 *                                 needing to repeat the earlier context.
 *   C. CopilotIntentDetector    — the ORIGINAL keyword-scoring pipeline
 *      + CopilotResponseFormatter  (normalize → score ~40 fixed intents →
 *                                 one pre-written query → template response).
 *                                 Runs whenever B2 returns null (no LLM key
 *                                 configured, or the model produced nothing
 *                                 usable) OR B2's whole provider chain is
 *                                 temporarily down (see below). This keeps
 *                                 the Copilot fully functional with zero LLM
 *                                 configuration; it is a safety net, not the
 *                                 primary reasoning path.
 *
 *      Fault, found live: when every provider failed, this used to run
 *      SILENTLY and unlabeled — indistinguishable from a real AI answer. For
 *      a compound or context-dependent question the scorer can only pick
 *      ONE of its ~40 fixed intents and fragment-match the rest, producing a
 *      confident-looking WRONG answer ("no matching records for Printer
 *      named laptops" for a two-part warranty+holder question - confirmed
 *      live). So this path is now taken deliberately, not silently: it only
 *      surfaces a keyword-pipeline answer when the scorer actually landed on
 *      a real intent (or a genuine clarification question), always prefixed
 *      with a disclaimer so the answer's lower fidelity is visible rather
 *      than looking like a full AI response. If the scorer ALSO can't land
 *      on anything (its generic "please rephrase" catch-all), that catch-all
 *      is replaced with the honest "AI is temporarily unavailable" message -
 *      showing "please rephrase" there would look like a plain
 *      misunderstanding and hide that the AI is actually down.
 *
 * Debug: start JVM with -DCOPILOT_DEBUG=true to see pipeline details in server log.
 */
public class CopilotEngine {
    private static final Logger LOGGER = Logger.getLogger(CopilotEngine.class.getName());

    private static final boolean DEBUG =
        "true".equalsIgnoreCase(System.getProperty("COPILOT_DEBUG", "false"));

    // Backward-compat: session intent by userId
    private static final java.util.Map<Integer, String> SESSION_INTENTS =
        new java.util.concurrent.ConcurrentHashMap<>();

    public static String getSessionIntent(int userId) {
        Object v = SESSION_INTENTS.get(userId);
        return v == null ? null : String.valueOf(v);
    }

    /**
     * Prefixed onto any keyword-pipeline answer shown ONLY because every AI
     * provider was temporarily down (see aiTemporarilyUnavailable in
     * answer()). Keeps a lower-fidelity fallback answer visually
     * distinguishable from a real AI response, so the user knows to treat it
     * as a best-effort guess - especially important for compound or
     * context-dependent questions the keyword scorer cannot fully express.
     */
    private static final String KEYWORD_FALLBACK_DISCLAIMER =
        "⚠️ *AI assistant is temporarily busy — showing a basic keyword-matched answer, " +
        "which may not fully cover multi-part or context-dependent questions.*\n\n";

    /**
     * Prepends KEYWORD_FALLBACK_DISCLAIMER to a keyword-pipeline response
     * when it is only being shown because the AI provider chain failed.
     * No-op (returns response unchanged) otherwise, so every other caller of
     * the keyword pipeline (no LLM configured at all - the normal,
     * always-on zero-config case) is completely unaffected.
     */
    private static CopilotResponse withFallbackDisclaimer(CopilotResponse response, boolean aiTemporarilyUnavailable) {
        if (!aiTemporarilyUnavailable || response == null) {
            return response;
        }
        return new CopilotResponse(
            KEYWORD_FALLBACK_DISCLAIMER + response.answer, response.mode, response.success, response.type);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // RESPONSE TYPE
    // ─────────────────────────────────────────────────────────────────────────

    public static class CopilotResponse {
        public final String answer;
        public final String mode;
        public final boolean success;
        public final int type;

        public CopilotResponse(String answer) {
            this(answer, "NLU", true, 0);
        }

        public CopilotResponse(String answer, String mode, int type) {
            this(answer, mode, true, type);
        }

        public CopilotResponse(String answer, String mode, boolean success, int type) {
            this.answer  = answer == null ? "" : answer;
            this.mode    = mode == null ? "NLU" : mode;
            this.success = success;
            this.type    = type;
        }

        public String getAnswer()   { return answer; }
        public String getMessage()  { return answer; }
        public String getResponse() { return answer; }
        public String getMode()     { return mode;   }
        public boolean isSuccess()  { return success; }
        public int getType()        { return type;    }
        public String getHtml()     { return answer; }

        @Override
        public String toString() { return answer; }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MAIN ENTRY POINT
    // ─────────────────────────────────────────────────────────────────────────

    public static CopilotResponse answer(
            String question, int userId, String username, String role, HttpSession session) {
        return answer(question, userId, username, role, session, null, null);
    }

    /**
     * Overload accepting one optional attached image - a photo of an asset
     * tag, QR code, nameplate, or physical damage from the chat UI's attach
     * control. imageBase64 is raw base64 with no "data:...;base64," prefix;
     * imageMimeType is e.g. "image/jpeg". Passed only into stage B2
     * (CopilotAgentLoop's LLM reasoning) below - never into the regex
     * command detector (A/B) or the write-intent classifier (B1), which
     * stay text-only by design, same reasoning as why those two never got
     * an LLM in the loop for anything destructive: an image adds
     * interpretation uncertainty exactly where a write action must not have
     * any. Both parameters are null/blank on every existing call site
     * (nothing behavioral changes for a caller that never attaches an
     * image).
     */
    public static CopilotResponse answer(
            String question, int userId, String username, String role, HttpSession session,
            String imageBase64, String imageMimeType) {

        if (question == null || question.trim().isEmpty()) {
            return new CopilotResponse("Please ask a question.", "SYSTEM", 0);
        }

        try {
            // ── A. Pending confirmation (write-commands) ─────────────────────
            // Fault, found live: session.getAttribute() throws
            // IllegalStateException (not "returns null") once the session has
            // been invalidated - a timeout, a logout in another tab, or a
            // deploy racing a slow multi-provider LLM fallback (a real ~30s
            // round trip when every provider is rate-limited, confirmed
            // live). "session != null" alone doesn't catch that. Without this
            // try/catch, that exception would be caught only by this whole
            // method's outer catch below and returned as a generic "internal
            // server issue" - for what should just mean "no pending
            // confirmation, answer the question normally" the same way it
            // already does for session == null.
            try {
            if (session != null) {
                CopilotCommandPlan pendingPlan =
                    (CopilotCommandPlan) session.getAttribute("copilotPendingCommandPlan");
                if (pendingPlan != null) {
                    String q = question.toLowerCase().trim();
                    if (q.equals("cancel")) {
                        session.removeAttribute("copilotPendingCommandPlan");
                        session.removeAttribute("copilotPendingConfirmationToken");
                        session.removeAttribute("copilotPendingStrongConfirmationText");
                        return new CopilotResponse("Action cancelled.", "AI", 0);
                    }

                    if (pendingPlan.requiresConfirmation) {
                        boolean confirmed = false;
                        if (pendingPlan.destructiveAction) {
                            if (question.trim().equalsIgnoreCase(pendingPlan.strongConfirmationText)) {
                                confirmed = true;
                            }
                        } else {
                            if (q.equals("confirm") || q.equals("yes proceed") ||
                                q.equals("yes") || q.equals("proceed")) {
                                confirmed = true;
                            }
                        }

                        if (confirmed) {
                            session.removeAttribute("copilotPendingCommandPlan");
                            session.removeAttribute("copilotPendingConfirmationToken");
                            session.removeAttribute("copilotPendingStrongConfirmationText");

                            // Re-verify permission at the moment of execution, not only at
                            // plan time. `role` is re-read from the live session on every
                            // request (never cached in the stored plan), so this closes the
                            // narrow window where a user's role changes mid-conversation
                            // between the initial request and this confirmation message -
                            // flagged as a defense-in-depth gap in audit/27-ai-copilot.md
                            // (Finding 1's follow-up item), cheap to close before any new
                            // write-capable command is added to this pipeline.
                            if (!CopilotCommandExecutor.checkPermission(pendingPlan, role)) {
                                return new CopilotResponse(
                                    "🚫 **Access Denied**: Your role (" + role + ") no longer permits this action.",
                                    "SYSTEM", 0);
                            }

                            String res = CopilotCommandExecutor.execute(pendingPlan, userId, username, role);
                            return new CopilotResponse(res, "AI", 0);
                        } else {
                            if (pendingPlan.destructiveAction) {
                                return new CopilotResponse(
                                    "⚠️ You must type exactly: **" + pendingPlan.strongConfirmationText +
                                    "** to proceed, or type **cancel**.", "AI", 0);
                            } else {
                                return new CopilotResponse(
                                    "⚠️ Please reply **confirm** to proceed, or **cancel** to abort.", "AI", 0);
                            }
                        }
                    }
                }
            }
            } catch (IllegalStateException sessionInvalidated) {
                // Treated exactly like "no pending confirmation" - fall
                // through to normal question handling below.
                LOGGER.log(Level.INFO,
                        "Session invalidated mid-request while checking for a pending confirmation; "
                                + "proceeding as a fresh question.");
            }

            // ── A2. Quick answers (no LLM, no delay) ──────────────────────────
            // Added for live-demo/presentation safety: the real, external LLM
            // providers are genuinely rate-limited under sustained use and can
            // take anywhere from a few seconds to 30-60+ seconds (a failover
            // chain), or in the worst case exhaust every configured provider
            // and return "temporarily unavailable" - fine for normal use,
            // unacceptable risk live in front of an audience. This answers a
            // curated set of count-by-period questions ("how many employees
            // were added this month?") straight from the database, checked
            // BEFORE anything else so a matching question never waits on a
            // provider at all. Deliberately conservative - see
            // CopilotQuickAnswers' own docs - so it only ever intercepts the
            // narrow class of question it was built for; everything else
            // reaches the AI/keyword pipeline exactly as before.
            String quickAnswer = CopilotQuickAnswers.tryAnswer(question, role, session);
            if (quickAnswer != null) {
                return new CopilotResponse(quickAnswer, "AI", 0);
            }

            // ── B. Write-command detection ───────────────────────────────────
            CopilotCommandPlan cmdPlan = CopilotCommandDetector.detectCommand(question);
            if (cmdPlan != null &&
                cmdPlan.intent != CopilotIntentType.EXPORT_CURRENT_RESULT &&
                cmdPlan.intent != CopilotIntentType.EXPORT_REPORT) {
                return handleCommandPlan(cmdPlan, role, userId, username, session);
            }

            // ── B1. LLM-assisted write-intent classification ─────────────────
            // CopilotCommandDetector's regexes are strict on purpose (see its
            // own comments), which means a real, permitted action phrased
            // differently than expected ("can you hand AST010 over to Priya")
            // fell straight through to a data answer or "please rephrase"
            // instead of ever being offered. CopilotWriteIntentClassifier
            // covers exactly that gap for five NON-destructive, already
            // fully-guarded actions (allocate/return/approve/reject/create
            // maintenance request) - see its own class doc for why those five
            // and not create/update/delete. Whatever plan it builds goes
            // through the EXACT SAME handleCommandPlan() below as a
            // regex-detected one: same checkPermission(), same missing-field
            // handling, same confirm-then-execute round trip, same audit log.
            // Returns null (falls through unchanged to B2) for an ordinary
            // question, an unrecognised phrasing, or when no LLM is
            // configured - this is a pure addition, never a narrowing, of
            // what the Copilot could already do.
            CopilotCommandPlan llmCmdPlan = CopilotWriteIntentClassifier.classify(question, role, session);
            if (llmCmdPlan != null) {
                return handleCommandPlan(llmCmdPlan, role, userId, username, session);
            }

            // ── B2. LLM agent loop (understand -> plan -> execute -> reason) ─
            // Runs BEFORE the keyword pipeline because it is strictly more
            // capable: it can compose several tools, chain on what it finds,
            // and answer compound questions the ~40 fixed intents below cannot
            // express. Returns null whenever it can't help - no API key, a
            // provider error, or an empty result - and we fall through to the
            // original keyword pipeline unchanged. That keeps the Copilot fully
            // functional offline and makes the LLM path a pure upgrade rather
            // than a dependency.
            //
            // Write commands are deliberately NOT routed here: they were
            // already handled in section B above by CopilotCommandDetector's
            // strict keyword matching plus its typed-confirmation gate. An LLM
            // misreading "show" is recoverable; an LLM misreading "delete" on
            // live railway asset data is not.
            String agentAnswer = CopilotAgentLoop.answer(
                    question, userId, username, role, session, imageBase64, imageMimeType);

            // PROVIDER_UNAVAILABLE_MESSAGE is a distinct, non-null signal from
            // agentAnswer's other two cases (a real grounded answer, or null
            // meaning "no LLM configured / nothing usable") - it means every
            // configured provider genuinely failed to respond. Falling
            // through here (instead of returning it immediately) lets the
            // keyword pipeline attempt a lower-fidelity answer rather than a
            // dead end, since a simple single-intent question ("show
            // available assets") is well within what the keyword scorer
            // handles correctly. See the disclaimer handling below for how
            // this stays honest rather than reintroducing silent, wrong
            // fragment-matched answers.
            boolean aiTemporarilyUnavailable =
                CopilotAgentLoop.PROVIDER_UNAVAILABLE_MESSAGE.equals(agentAnswer);

            if (agentAnswer != null && !agentAnswer.trim().isEmpty() && !aiTemporarilyUnavailable) {
                return new CopilotResponse(agentAnswer, "AI", 0);
            }

            if (aiTemporarilyUnavailable) {
                debugLog("AI UNAVAILABLE", "Every provider failed - attempting a labeled keyword-pipeline answer.");
            }

            // ── C. Query intent pipeline (fallback) ──────────────────────────
            CopilotQueryPlan plan = CopilotIntentDetector.detectIntent(question);

            // ── C1b. ReasoningPlanner: validate + enrich + follow-up ─────────
            plan = CopilotReasoningPlanner.plan(plan, session);

            debugLog("INTENT",        plan.intent.name() +
                " (confidence=" + String.format("%.2f", plan.confidence) + ")");
            debugLog("TARGET MODULE",  plan.targetModule  != null ? plan.targetModule  : "n/a");
            debugLog("ENTITIES",
                "category="  + plan.normalizedCategory +
                " dept="     + plan.departmentName +
                " assetCode=" + plan.assetCode +
                " empCode="  + plan.employeeCode +
                " empName="  + plan.employeeName +
                " status="   + plan.status +
                " days="     + plan.days);
            debugLog("SQL TEMPLATE",   plan.sqlTemplateName != null ? plan.sqlTemplateName : "n/a");
            debugLog("PARAM COUNT",    String.valueOf(countPlanParams(plan)));

            // ── C2. EXPORT uses last session result ──────────────────────────
            if (plan.intent == CopilotIntentType.EXPORT_CURRENT_RESULT) {
                if (!CopilotSessionMemory.isLastResultExportable(session)) {
                    return new CopilotResponse(
                        "I couldn't find a recent exportable report. Please generate a report first.", "SYSTEM", 0);
                }
                if ("EMPLOYEE".equalsIgnoreCase(role)) {
                    return new CopilotResponse(
                        "🚫 **Access Denied**: Your role does not permit downloading bulk reports.",
                        "SYSTEM", 0);
                }
                String exportBtn =
                    "<div style='margin-top:10px;'>" +
                    "<a href='CopilotReportExportServlet' target='_blank' " +
                    "style='background:var(--ir-blue,#2563eb);color:#fff;padding:8px 16px;" +
                    "border-radius:4px;text-decoration:none;font-size:13px;display:inline-block;'>" +
                    "<i class='fa fa-download'></i> Download Excel Report</a></div>";
                return new CopilotResponse("Ready to export your last report.\n\n" + exportBtn, "AI", 0);
            }

            // ── C3. UNKNOWN / clarification ──────────────────────────────────
            if (plan.intent == CopilotIntentType.UNKNOWN) {
                if (plan.clarificationNeeded && plan.clarificationPrompt != null) {
                    // A real, on-topic disambiguation question - not a wrong
                    // guess, just disclosed as coming from the simpler engine.
                    return withFallbackDisclaimer(
                        new CopilotResponse(plan.clarificationPrompt, "AI", 0), aiTemporarilyUnavailable);
                }
                if (aiTemporarilyUnavailable) {
                    // The keyword scorer ALSO couldn't land on anything. Its
                    // generic catch-all below would look like a plain
                    // misunderstanding - say the real reason instead.
                    return new CopilotResponse(CopilotAgentLoop.PROVIDER_UNAVAILABLE_MESSAGE, "AI", 0);
                }
                return new CopilotResponse(
                    "I can help with **asset cost, asset lists, employee details, maintenance, " +
                    "warranty, pending requests, or reports**. Please rephrase your question.",
                    "AI", 0);
            }

            // ── C4. HELP ─────────────────────────────────────────────────────
            if (plan.intent == CopilotIntentType.HELP_NAVIGATION) {
                String module = plan.targetModule;
                if (module != null) {
                    String cap = CopilotProjectModuleRegistry.getCapabilityText(module);
                    if (cap != null) return new CopilotResponse(cap, "AI", 0);
                }
                return new CopilotResponse(getHelpText(), "AI", 0);
            }

            // ── C5. Update session intent (backward-compat) ───────────────────
            SESSION_INTENTS.put(userId, plan.intent.name());

            // ── C6. Execute tool (DB fetch) ───────────────────────────────────
            String baseResponse;
            if (plan.needsDatabase) {
                Map<String, Object> dbResult = executeTool(plan, session);

                // Analyze result and save to session memory
                CopilotResultAnalyzer.AnalysisResult analysis =
                    CopilotResultAnalyzer.analyze(plan, dbResult);
                plan.responseStyle = analysis.responseStyle;

                // Save to session memory (enables follow-up + export)
                String resultTitle = buildResultTitle(plan);
                CopilotSessionMemory.save(session, plan, dbResult, resultTitle);

                debugLog("ROW COUNT",     String.valueOf(analysis.rowCount));
                debugLog("RESPONSE STYLE", analysis.responseStyle != null ? analysis.responseStyle : "n/a");

                // Empty result → return the reason directly
                if (analysis.isEmpty) {
                    return withFallbackDisclaimer(
                        new CopilotResponse(analysis.emptyReason, "AI", 0), aiTemporarilyUnavailable);
                }

                baseResponse = CopilotResponseFormatter.formatResponse(plan, dbResult);

                // ── C7. Optional Gemini polish ─────────────────────────────
                if (SettingsDAO.isAiMode() && analysis.callGeminiPolish) {
                    CopilotResponse aiResponse = callAiApiDynamic(question, plan, baseResponse, role);
                    // A genuine (secondary) AI response, not the keyword
                    // template - no disclaimer needed even if the primary
                    // chain had failed above.
                    if (aiResponse != null) return aiResponse;
                }
                return withFallbackDisclaimer(
                    new CopilotResponse(baseResponse, "AI", 0), aiTemporarilyUnavailable);

            } else {
                return withFallbackDisclaimer(
                    new CopilotResponse(getStaticResponse(plan), "AI", 0), aiTemporarilyUnavailable);
            }

        } catch (Exception e) {
            LOGGER.log(Level.SEVERE, "CopilotEngine Error", e);
            return new CopilotResponse(
                "I could not complete this AMS lookup due to an internal server issue. Please try again.",
                "ERROR", 0);
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // COMMAND PLAN HANDLING — shared by the regex path (B) and the
    // LLM-assisted write-intent classifier (B1), so a plan is authorized,
    // confirmed, executed, and audited identically no matter which one built
    // it. Extracted specifically so adding B1 could not accidentally diverge
    // from B's already-hardened checkPermission()/confirmation logic.
    // ─────────────────────────────────────────────────────────────────────────

    private static CopilotResponse handleCommandPlan(
            CopilotCommandPlan cmdPlan, String role, int userId, String username, HttpSession session) {

        if (!CopilotCommandExecutor.checkPermission(cmdPlan, role)) {
            return new CopilotResponse(
                "🚫 **Access Denied**: Your role (" + role + ") does not permit this action.",
                "SYSTEM", 0);
        }

        if (!cmdPlan.missingRequiredFields.isEmpty()) {
            String missing = String.join(", ", cmdPlan.missingRequiredFields);
            return new CopilotResponse(
                "To proceed, I still need: **" + missing + "**. Please provide them.", "AI", 0);
        }

        if (cmdPlan.requiresConfirmation) {
            if (session != null) {
                session.setAttribute("copilotPendingCommandPlan", cmdPlan);
                session.setAttribute("copilotPendingConfirmationToken", cmdPlan.confirmationToken);
                if (cmdPlan.destructiveAction) {
                    session.setAttribute("copilotPendingStrongConfirmationText",
                        cmdPlan.strongConfirmationText);
                }
            }
            String msg = "I understood you want to **" + cmdPlan.previewMessage + "**.\n\n";
            if (cmdPlan.destructiveAction) {
                msg += "⚠️ **WARNING**: This is a destructive action.\nTo proceed, type exactly:\n**" +
                       cmdPlan.strongConfirmationText + "**\nor type **cancel**.";
            } else {
                msg += "Please reply **confirm** to proceed, or **cancel** to abort.";
            }
            return new CopilotResponse(msg, "AI", 0);
        }

        String res = CopilotCommandExecutor.execute(cmdPlan, userId, username, role);
        return new CopilotResponse(res, "AI", 0);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // TOOL EXECUTOR DISPATCH
    // ─────────────────────────────────────────────────────────────────────────

    private static Map<String, Object> executeTool(CopilotQueryPlan plan, HttpSession session) {
        debugLog("TOOL", plan.intent.name());
        switch (plan.intent) {

            // Cost
            case ASSET_TOTAL_COST:
                return CopilotToolExecutor.getAssetTotalCost(plan, session);

            // Asset lists / filters
            case ASSET_SEARCH:
                return CopilotToolExecutor.searchAssets(plan, session);

            case ASSET_COUNT:
                // Count reuses search; formatter counts the list
                return CopilotToolExecutor.searchAssets(plan, session);

            case AVAILABLE_ASSETS:
                return CopilotToolExecutor.getAvailableAssets(plan, session);

            case ALLOCATED_ASSETS:
                return CopilotToolExecutor.getAllocatedAssets(plan, session);

            case DISPOSED_ASSETS:
                return CopilotToolExecutor.getDisposedAssets(plan, session);

            case ASSET_HOLDER:
                return CopilotToolExecutor.getAssetHolder(plan, session);

            // Employee
            case EMPLOYEE_SEARCH:
                return CopilotToolExecutor.searchEmployees(plan, session);

            case EMPLOYEE_DETAILS:
                return CopilotToolExecutor.getEmployeeDetails(plan, session);

            case EMPLOYEE_ALLOCATIONS:
                return CopilotToolExecutor.getEmployeeAllocations(plan, session);

            // Summaries
            case DEPT_SUMMARY:
                return CopilotToolExecutor.getDepartmentSummary(plan, session);

            case CATEGORY_SUMMARY:
                return CopilotToolExecutor.getCategorySummary(plan, session);

            case SUPPLIER_SUMMARY:
                return CopilotToolExecutor.getSupplierSummary(plan, session);

            case DASHBOARD_SUMMARY:
                return CopilotToolExecutor.getDashboardSummary(plan, session);

            // Allocation / return
            case ALLOCATION_SEARCH:
            case RETURN_SEARCH:
                return CopilotToolExecutor.searchAllocations(plan, session);

            // Pending requests
            case PENDING_ASSET_REQUESTS:
                return CopilotToolExecutor.getPendingAssetRequests(plan, session);

            // Maintenance
            case MAINTENANCE_PENDING:
                return CopilotToolExecutor.getPendingMaintenance(plan, session);

            case MAINTENANCE_HISTORY:
                return CopilotToolExecutor.getMaintenanceHistory(plan, session);

            // Warranty
            case WARRANTY_EXPIRING_NEXT_N_DAYS:
            case WARRANTY_EXPIRED:
            case WARRANTY_THIS_MONTH:
                return CopilotToolExecutor.getWarranty(plan, session);

            // Phase 2: Extended asset queries
            case DAMAGED_ASSETS:
            case ASSET_BY_STATUS:
                return CopilotToolExecutor.getDamagedAssets(plan, session);

            case ASSET_VALUE_SUMMARY:
                return CopilotToolExecutor.getAssetValueSummary(plan, session);

            // Phase 2: Asset requests
            case APPROVED_ASSET_REQUESTS:
                return CopilotToolExecutor.getApprovedRequests(plan, session);

            case REJECTED_ASSET_REQUESTS:
                return CopilotToolExecutor.getRejectedRequests(plan, session);

            // Phase 2: Returns
            case RETURN_RECORDS:
                return CopilotToolExecutor.getReturnRecords(plan, session);

            case PENDING_RETURNS:
                return CopilotToolExecutor.getPendingReturns(plan, session);

            // Phase 2: Department employees
            case DEPARTMENT_EMPLOYEES:
                return CopilotToolExecutor.getDepartmentEmployees(plan, session);

            // Phase 2: QR
            case QR_STATUS:
                return CopilotToolExecutor.getQrStatus(plan, session);

            case QR_SCAN_LOGS:
                return CopilotToolExecutor.getQrScanLogs(plan, session);

            // Phase 2: Audit
            case AUDIT_SEARCH:
                return CopilotToolExecutor.getAuditLogs(plan, session);

            // Phase 2: Role / Settings
            case ROLE_DUTY_SUMMARY:
                return CopilotToolExecutor.getRoleDutySummary(plan, session);

            case SETTINGS_SUMMARY:
                return CopilotToolExecutor.getSettingsSummary(plan, session);

            // Phase 2: Physical Verification
            case PHYSICAL_VERIFICATION_SUMMARY:
                return CopilotToolExecutor.getPhysicalVerificationSummary(plan, session);

            // Phase 2: Category-vendor mapping
            case CATEGORY_VENDOR_MAPPING:
                return CopilotToolExecutor.getCategoryVendorMapping(plan, session);

            default:
                return Map.of("error",
                    "This query type (" + plan.intent.name() + ") is not yet supported by the Copilot tool executor.");
        }
    }

    /** Build a short human-readable title for the result (used by export). */
    private static String buildResultTitle(CopilotQueryPlan plan) {
        StringBuilder sb = new StringBuilder();
        if (plan.intent != null) sb.append(plan.intent.name().replace('_', ' '));
        if (plan.normalizedCategory != null) sb.append(" - ").append(plan.normalizedCategory);
        if (plan.departmentName != null) sb.append(" - ").append(plan.departmentName);
        return sb.length() > 0 ? sb.toString() : "AMS Report";
    }

    // ─────────────────────────────────────────────────────────────────────────
    // STATIC RESPONSES
    // ─────────────────────────────────────────────────────────────────────────

    private static String getStaticResponse(CopilotQueryPlan plan) {
        if (plan.intent == CopilotIntentType.HELP_NAVIGATION) return getHelpText();
        return "I can help with **asset cost, asset lists, employee details, maintenance, " +
               "warranty, pending requests, or reports**. Please rephrase your question, " +
               "or type **help** for examples.";
    }

    private static String getHelpText() {
        return "**AMS Copilot — What I can answer:**\n\n" +
               "**Assets**\n" +
               "- `total cost of laptops` / `total cost of all assets`\n" +
               "- `show laptops in IT department`\n" +
               "- `show available assets` / `allocated assets` / `disposed assets` / `damaged assets`\n" +
               "- `who is holding AST001?`\n" +
               "- `asset value summary` / `category wise asset summary`\n" +
               "- `warranty expiring in next 30 days` / `expired warranty`\n\n" +
               "**Employees**\n" +
               "- `employee details of EMP006`\n" +
               "- `which assets are assigned to Subham?`\n" +
               "- `employees in IT department`\n\n" +
               "**Maintenance**\n" +
               "- `show pending maintenance`\n" +
               "- `maintenance history of AST003`\n\n" +
               "**Reports & Summaries**\n" +
               "- `total value of assets department wise`\n" +
               "- `show category wise asset summary`\n" +
               "- `show vendor summary`\n" +
               "- `dashboard summary` / `overview`\n\n" +
               "**Asset Requests**\n" +
               "- `show pending asset requests`\n" +
               "- `show approved requests` / `show rejected requests`\n\n" +
               "**Returns**\n" +
               "- `show return records` / `show pending returns`\n\n" +
               "**Physical Verification**\n" +
               "- `show physical verification summary`\n\n" +
               "**QR Control Center**\n" +
               "- `show QR tagging status` / `show QR scan logs`\n\n" +
               "**Audit** *(ADMIN/AUDITOR only)*\n" +
               "- `show audit logs` / `show audit logs for today`\n\n" +
               "**Admin Only**\n" +
               "- `show role duty summary` / `show system settings`\n" +
               "- `how is the copilot doing?` / `show recent bad copilot answers`\n" +
               "- `show category vendor mapping`\n\n" +
               "**How things work** *(AI mode)*\n" +
               "- `how does asset request approval work?` / `what happens when I mark an asset damaged?`\n" +
               "- `what can a department head do?` / `why did my request go to my department head first?`\n\n" +
               "**Also understands Hinglish/Odia:**\n" +
               "- `mujhe batao saare laptops ka cost kitna hai`\n" +
               "- `kaunse assets available hain stores mein?`\n\n" +
               "Type **export this** to download the last result as Excel.\n" +
               "Type **help [module]** (e.g. `help maintenance`) for module-specific guidance.";
    }

    // ─────────────────────────────────────────────────────────────────────────
    // AI POLISH (optional — Gemini only reads DAO output, never invents)
    // ─────────────────────────────────────────────────────────────────────────

    private static CopilotResponse callAiApiDynamic(
            String question, CopilotQueryPlan plan, String verifiedResponse, String role) {

        String apiKey = SettingsDAO.getGeminiApiKey();
        if (apiKey == null || apiKey.isEmpty()) return null;

        // System prompt explicitly forbids Gemini from inventing facts
        String sysPrompt =
            "You are AMS Copilot for Railway Asset Management System. " +
            "User Role: " + role + ". " +
            "You MUST answer using ONLY the Verified Database Output below. " +
            "Do NOT invent any asset names, employee names, counts, costs, or dates. " +
            "If the verified output says no records found, repeat that clearly. " +
            "Format the answer using Markdown. Do not add any data not present in the verified output.\n\n" +
            "### Verified Database Output ###\n" + verifiedResponse;

        try {
            String jsonPayload =
                "{\"contents\":[{\"parts\":[{\"text\":\"System: " +
                sysPrompt.replace("\"", "\\\"").replace("\n", "\\n") +
                "\\n\\nUser: " + question.replace("\"", "\\\"") + "\"}]}]}";

            String responseStr = executeGeminiApiCall(jsonPayload, apiKey);
            if (responseStr != null && !responseStr.trim().isEmpty()) {
                return new CopilotResponse(parseGeminiText(responseStr), "AI", 0);
            }
        } catch (Exception e) {
            LOGGER.log(Level.WARNING, "AI formatting failed, using local formatter output", e);
        }
        return null;
    }

    private static String executeGeminiApiCall(String jsonPayload, String apiKey) throws Exception {
        URL url = new URL(
            "https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?key=" + apiKey);
        HttpURLConnection conn = (HttpURLConnection) url.openConnection();
        conn.setRequestMethod("POST");
        conn.setRequestProperty("Content-Type", "application/json");
        conn.setDoOutput(true);
        conn.setConnectTimeout(8000);
        conn.setReadTimeout(12000);

        try (OutputStream os = conn.getOutputStream()) {
            os.write(jsonPayload.getBytes(StandardCharsets.UTF_8));
        }

        if (conn.getResponseCode() >= 400) return null;

        try (BufferedReader br = new BufferedReader(
                new InputStreamReader(conn.getInputStream(), StandardCharsets.UTF_8))) {
            StringBuilder sb = new StringBuilder();
            String line;
            while ((line = br.readLine()) != null) sb.append(line.trim());
            return sb.toString();
        }
    }

    private static String parseGeminiText(String jsonResponse) {
        try {
            JSONObject obj = new JSONObject(jsonResponse);
            JSONArray candidates = obj.getJSONArray("candidates");
            if (candidates.length() > 0) {
                JSONArray parts = candidates.getJSONObject(0)
                    .getJSONObject("content").getJSONArray("parts");
                if (parts.length() > 0) return parts.getJSONObject(0).getString("text");
            }
        } catch (Exception e) {
            LOGGER.log(Level.WARNING, "Failed to parse Gemini JSON", e);
        }
        return null;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // DEBUG UTILITY
    // ─────────────────────────────────────────────────────────────────────────

    private static void debugLog(String label, String value) {
        if (DEBUG) {
            // Left-pad label to 14 chars for aligned column output
            String padded = String.format("%-14s", label);
            System.out.println("[COPILOT-DEBUG] " + padded + ": " + value);
        }
        LOGGER.info("[COPILOT] " + label + ": " + value);
    }

    /**
     * Counts the number of non-null bound parameters in the plan.
     * Used only for COPILOT_DEBUG PARAM COUNT output.
     * This is a best-effort count — actual PreparedStatement bind count may
     * vary per DAO method, but this gives a consistent audit-friendly signal.
     */
    private static int countPlanParams(CopilotQueryPlan plan) {
        int n = 0;
        if (plan.normalizedCategory != null) n++;
        if (plan.departmentName     != null) n++;
        if (plan.assetCode          != null) n++;
        if (plan.employeeCode       != null) n++;
        if (plan.employeeName       != null) n++;
        if (plan.status             != null) n++;
        if (plan.startDate          != null) n++;
        if (plan.endDate            != null) n++;
        if (plan.days               != null) n++;
        return n;
    }
}
