package com.mycompany.asset_management_system_ams;

import java.util.ArrayList;
import java.util.List;
import java.util.Locale;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.concurrent.TimeUnit;
import java.util.logging.Level;
import java.util.logging.Logger;

import jakarta.servlet.http.HttpSession;

/**
 * CopilotAgentLoop — the reasoning loop that makes the Copilot understand,
 * plan, look at real data, and then answer.
 *
 * This inverts the old pipeline. Previously the LLM sat at the very END as a
 * cosmetic layer: a keyword scorer picked one of ~40 fixed intents, ran its one
 * pre-written query, and the model was only allowed to re-word the resulting
 * table. Anything that didn't match a bucket got "please rephrase".
 *
 * Here the model sits at the FRONT (planner) and MIDDLE (reasoner), and the
 * existing CopilotToolExecutor methods become its hands:
 *
 *     user text
 *       -> [LLM: plan]      which tool(s), with which arguments?
 *       -> [Java: execute]  role-filtered, PreparedStatement-backed DAO calls
 *       -> [LLM: reason]    sees the real rows; may call MORE tools, or answer
 *       -> grounded answer
 *
 * That loop is what lets it handle a compound question like "which laptops are
 * out of warranty and who is holding them?" — warranty tool, then holder
 * lookups, then one answer over both — instead of silently dropping half the
 * question.
 *
 * Failure is always soft: if no key is configured, the provider errors, or the
 * model produces nothing usable, answer() returns null and CopilotEngine falls
 * back to the original keyword pipeline. The Copilot never gets worse than it
 * was; it only gets better when a key is present and the call succeeds.
 */
public final class CopilotAgentLoop {

    private static final Logger LOGGER = Logger.getLogger(CopilotAgentLoop.class.getName());

    private static final boolean DEBUG =
            "true".equalsIgnoreCase(System.getProperty("COPILOT_DEBUG", "false"));

    /**
     * Hard cap on plan/execute round trips. Real questions in this domain
     * resolve in 1-3; the cap exists so a confused model cannot spin up an
     * unbounded number of billed calls.
     *
     * Fault, found live: a genuinely compound question ("which laptops are
     * out of warranty AND who is holding them?") needs one warranty lookup
     * plus one get_asset_holder call per asset found - and the model
     * sometimes spends a round or two re-querying the first tool with
     * near-duplicate arguments (e.g. retrying get_warranty with no args,
     * then status=ACTIVE) before moving on. At 4 that combination hit the
     * cap before a single get_asset_holder call happened, so answer()
     * returned null and CopilotEngine silently fell all the way back to the
     * keyword pipeline - which then mis-parsed "who is holding them" as part
     * of a search term and answered a different, wrong question. Raised to
     * 6, and the system prompt below now tells the model directly not to
     * re-call a tool with near-duplicate arguments, so most of that slack
     * goes to legitimate per-asset follow-ups instead of retries.
     */
    private static final int MAX_ITERATIONS = 6;

    /** Conversation turns replayed for follow-up context ("and what about IT?"). */
    private static final int HISTORY_TURNS = 6;

    /**
     * Runs the individual tool calls within ONE model round concurrently
     * instead of one at a time.
     *
     * Fault, found by inspection: a compound question ("which laptops are
     * out of warranty and who is holding them?") makes the model request one
     * get_warranty call plus one get_asset_holder call per asset found, all
     * in the SAME round (response.toolCalls) - but the old code ran them in
     * a plain sequential for-loop, so five holder lookups meant five
     * sequential DB round trips before the model ever got to reason over any
     * of them. Each tool call is an independent, read-only DAO lookup
     * (CopilotToolCatalog.execute -> CopilotToolExecutor, its own fresh
     * DBConnection.getConnection() per call, no shared mutable state) so
     * there is nothing to serialize on. Bounded well below typical container
     * thread-pool sizes since these are quick DB reads, not another slow LLM
     * round trip. Daemon threads so an idle pool never blocks JVM/webapp
     * shutdown.
     */
    private static final ExecutorService TOOL_EXECUTOR = Executors.newFixedThreadPool(8, runnable -> {
        Thread thread = new Thread(runnable, "copilot-tool-exec");
        thread.setDaemon(true);
        return thread;
    });

    /** Per-tool-call ceiling when running a round concurrently — generous for a single DB read. */
    private static final int TOOL_CALL_TIMEOUT_SECONDS = 20;

    /**
     * Shown when every configured provider genuinely fails to respond at all
     * (rate-limited, unreachable, 5xx) - as opposed to "no provider is
     * configured", which is a permanent, by-design state where the keyword
     * pipeline IS the intended answer path (see the NO CLIENT check below).
     *
     * Fault, found live: this case used to return null just like the
     * "nothing configured" case, and CopilotEngine can't tell those two
     * apart - both silently landed on the keyword pipeline. For a question
     * phrased for the LLM (multi-part, needing context, natural language),
     * that pipeline often fragment-matched stray words into a wrong answer
     * ("no matching records for Printer named laptops" - confirmed live
     * after Gemini and Groq both hit their free-tier rate limits on the same
     * request). A temporary outage should say so, not hand the question to a
     * cruder engine that answers confidently anyway.
     *
     * Package-private (not private) solely so CopilotContextUnderstandingTest
     * can assert on it directly rather than duplicating the literal text -
     * same reasoning as CopilotToolCatalog.toPlan()'s visibility.
     */
    static final String PROVIDER_UNAVAILABLE_MESSAGE =
            "🤖 The AI assistant is temporarily unavailable right now — every configured "
                    + "AI provider is rate-limited or unreachable. Please try again in a moment.";

    private CopilotAgentLoop() {
    }

    /**
     * @return the grounded answer, an honest unavailability notice
     *         (PROVIDER_UNAVAILABLE_MESSAGE) if every configured provider
     *         genuinely failed to respond, or null to tell CopilotEngine to
     *         fall back to its keyword pipeline (no provider configured, the
     *         role has no tools, or the model answered with nothing usable).
     */
    public static String answer(String question, int userId, String username, String role, HttpSession session) {
        return answer(question, userId, username, role, session, null, null);
    }

    /**
     * Overload accepting one optional attached image (raw base64, no
     * "data:...;base64," prefix, plus its mime type) - a photo of an asset
     * tag, QR code, nameplate, or physical damage from the chat UI's attach
     * control. Only ever attached to THIS turn's user message (see
     * LlmMessage.userWithImage()); replayed history from CopilotChatMemory
     * never carries images - re-sending a possibly-large image on every
     * subsequent turn of a conversation would balloon token cost for no
     * benefit once the model has already described what it saw.
     */
    public static String answer(String question, int userId, String username, String role, HttpSession session,
            String imageBase64, String imageMimeType) {
        if (question == null || question.trim().isEmpty()) {
            return null;
        }

        // Ordered provider chain: configured primary first, then any other
        // provider that has a key saved. Free and low-tier plans are exactly
        // the ones that rate-limit or briefly 5xx, and without a chain a single
        // transient 429 would drop the user all the way to keyword matching.
        List<LlmClient> chain = LlmClientFactory.createChain();
        if (chain.isEmpty()) {
            debug("NO CLIENT", "No API key configured - using local keyword pipeline.");
            return null;
        }

        List<LlmToolSpec> tools = CopilotToolCatalog.forRole(role);
        if (tools.isEmpty()) {
            debug("NO TOOLS", "Role " + role + " has no permitted tools.");
            return null;
        }

        try {
            List<LlmMessage> conversation = new ArrayList<LlmMessage>();
            conversation.addAll(CopilotChatMemory.recent(session, userId, HISTORY_TURNS));
            conversation.add(LlmMessage.userWithImage(question, imageBase64, imageMimeType));

            String systemPrompt = buildSystemPrompt(username, role);

            int providerIndex = 0;
            int toolRounds = 0;

            // Bounded by both the tool-round cap and the chain length, so no
            // combination of provider failures and tool calls can loop forever.
            int maxCalls = MAX_ITERATIONS + chain.size();

            for (int call = 1; call <= maxCalls; call++) {

                // Skip straight past any provider we already know is still
                // rate-limited from a recent 429, as long as a later provider
                // in the chain can be tried instead - this is what turns a
                // still-cooling-down provider from "one wasted network round
                // trip on THIS question too" into "skipped instantly." Never
                // skips the last remaining candidate - something must always
                // be attempted rather than silently giving up on a hunch.
                while (providerIndex < chain.size() - 1
                        && LlmProviderCooldown.isCoolingDown(chain.get(providerIndex).providerName())) {
                    debug("COOLDOWN SKIP", chain.get(providerIndex).providerName()
                            + " is still rate-limited from a recent call - trying the next provider directly.");
                    providerIndex++;
                }

                LlmClient client = chain.get(providerIndex);

                LlmRequest request = new LlmRequest()
                        .system(systemPrompt)
                        .addAll(conversation)
                        .withTools(tools);
                request.model = client.modelName();
                request.temperature = SettingsDAO.getCopilotTemperature();
                request.maxTokens = SettingsDAO.getCopilotMaxTokens();

                LlmResponse response = client.chat(request);

                if (response.isError()) {
                    // Provider error strings are never shown to the user - a
                    // railway officer looking for an asset should not be reading
                    // an HTTP status. Log it, then try the next provider.
                    LOGGER.log(Level.WARNING, "Copilot provider {0} failed: {1}",
                            new Object[]{client.providerName(), response.error});
                    debug("PROVIDER FAIL", client.providerName() + " - " + response.error);

                    if (looksRateLimited(response)) {
                        LlmProviderCooldown.recordRateLimited(client.providerName(), response.rateLimitHeaders);
                    }

                    providerIndex++;
                    if (providerIndex < chain.size()) {
                        // The conversation so far is provider-neutral (that is the
                        // point of the LlmMessage types), so the next provider
                        // picks up mid-question with every tool result intact.
                        debug("FAILOVER", "Switching to " + chain.get(providerIndex).providerName());
                        continue;
                    }

                    debug("CHAIN EXHAUSTED", "All " + chain.size()
                            + " provider(s) failed - telling the user honestly instead of "
                            + "falling back to keyword matching.");
                    return PROVIDER_UNAVAILABLE_MESSAGE;
                }

                if (!response.hasToolCalls()) {
                    String answer = response.text == null ? "" : response.text.trim();
                    if (answer.isEmpty()) {
                        debug("EMPTY", "Model returned no text and no tool calls.");
                        return null;
                    }

                    CopilotChatMemory.record(session, userId, question, answer);
                    debug("ANSWER", "Resolved by " + client.providerName()
                            + " after " + toolRounds + " tool round(s).");
                    return answer;
                }

                if (toolRounds >= MAX_ITERATIONS) {
                    debug("MAX ITERATIONS", "Hit the " + MAX_ITERATIONS
                            + " tool-round cap - forcing a final answer from data already gathered.");
                    return forceFinalAnswer(chain, providerIndex, systemPrompt, conversation, question, userId, session);
                }
                toolRounds++;

                // Model wants data. Run every requested tool, then loop so it can
                // reason over the real rows (and request more if it needs them).
                conversation.add(LlmMessage.toolCall(response.toolCalls));

                List<LlmToolCall> toolCalls = response.toolCalls;
                if (toolCalls.size() == 1) {
                    // No concurrency to gain — skip the executor/Future overhead.
                    LlmToolCall toolCall = toolCalls.get(0);
                    debug("TOOL", toolCall.name + " " + toolCall.arguments);
                    String result = CopilotToolCatalog.execute(toolCall, role, session);
                    conversation.add(LlmMessage.toolResult(toolCall.id, toolCall.name, result));
                } else {
                    // Independent read-only lookups requested in the same round —
                    // fire them concurrently and wait for all of them, rather than
                    // paying for their sum. See TOOL_EXECUTOR's javadoc above.
                    List<Future<String>> futures = new ArrayList<Future<String>>(toolCalls.size());
                    for (LlmToolCall toolCall : toolCalls) {
                        debug("TOOL", toolCall.name + " " + toolCall.arguments);
                        futures.add(TOOL_EXECUTOR.submit(
                                () -> CopilotToolCatalog.execute(toolCall, role, session)));
                    }
                    for (int i = 0; i < toolCalls.size(); i++) {
                        LlmToolCall toolCall = toolCalls.get(i);
                        String result;
                        try {
                            result = futures.get(i).get(TOOL_CALL_TIMEOUT_SECONDS, TimeUnit.SECONDS);
                        } catch (Exception e) {
                            // Same soft-failure contract as a normal tool error: the
                            // model sees it as data and can retry, use partial
                            // results, or say so - not an exception that kills the
                            // whole answer.
                            result = "{\"error\":\"Tool execution timed out or failed: "
                                    + CopilotJson.escape(String.valueOf(e.getMessage())) + "\"}";
                        }
                        conversation.add(LlmMessage.toolResult(toolCall.id, toolCall.name, result));
                    }
                }
            }

            debug("CALL CAP", "Hit the overall call cap - forcing a final answer from data already gathered.");
            return forceFinalAnswer(chain, providerIndex, systemPrompt, conversation, question, userId, session);

        } catch (Exception e) {
            LOGGER.log(Level.WARNING, "Copilot agent loop failed", e);
            return null;
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // FORCED FINAL ANSWER — budget exhausted, but real progress exists
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * Called when the tool-round or provider-call budget runs out mid-question.
     * Found live: a compound question ("which laptops are out of warranty and
     * who is holding them?") had already gathered the warranty list and one or
     * two holder lookups by the time the budget ran out, and the old code just
     * returned null here - discarding all of that grounded progress so
     * CopilotEngine would fall back to the keyword pipeline, which has never
     * seen any of it and answered a different, wrong question instead
     * ("no matching records for Laptop named holding them").
     *
     * This makes one last request with tools turned off, so the model MUST
     * answer in text from what is already in the conversation instead of
     * asking for data it can no longer get. A partial, honest answer grounded
     * in real rows beats discarding everything for the keyword fallback's
     * wrong one.
     *
     * Tries providers starting at providerIndex (not from the start of the
     * chain) since earlier providers may already have failed on this request.
     *
     * @return the model's grounded (possibly partial) answer, or
     *         PROVIDER_UNAVAILABLE_MESSAGE if every remaining provider also
     *         failed - never plain null, so a caller can always show this
     *         result to the user directly.
     */
    private static String forceFinalAnswer(List<LlmClient> chain, int providerIndex, String systemPrompt,
            List<LlmMessage> conversation, String question, int userId, HttpSession session) {

        List<LlmMessage> withInstruction = new ArrayList<LlmMessage>(conversation);
        withInstruction.add(LlmMessage.user(
                "You are out of data-lookup rounds for this question. Do not request any more "
                        + "tools. Answer now using only the information already gathered above. If "
                        + "part of the question is still unanswered, say plainly what you found and "
                        + "what you could not determine - do not guess."));

        for (int i = Math.max(providerIndex, 0); i < chain.size(); i++) {
            LlmClient client = chain.get(i);

            LlmRequest request = new LlmRequest()
                    .system(systemPrompt)
                    .addAll(withInstruction);
            request.model = client.modelName();
            request.temperature = SettingsDAO.getCopilotTemperature();
            request.maxTokens = SettingsDAO.getCopilotMaxTokens();

            LlmResponse response;
            try {
                response = client.chat(request);
            } catch (Exception e) {
                debug("FORCED ANSWER FAIL", client.providerName() + " - " + e.getMessage());
                continue;
            }

            if (response.isError()) {
                debug("FORCED ANSWER FAIL", client.providerName() + " - " + response.error);
                continue;
            }

            String answer = response.text == null ? "" : response.text.trim();
            if (answer.isEmpty()) {
                continue;
            }

            CopilotChatMemory.record(session, userId, question, answer);
            debug("FORCED ANSWER", "Resolved by " + client.providerName()
                    + " from data gathered before the budget ran out.");
            return answer;
        }

        // Every remaining provider failed this attempt too - not "the model
        // had nothing to add", but a genuine outage. Same honest message as
        // the CHAIN EXHAUSTED case above, for the same reason: say the AI is
        // down rather than silently handing a real, in-progress question to
        // the keyword pipeline as if this were a plain understanding gap.
        debug("FORCED ANSWER FAIL", "Every remaining provider failed - telling the user honestly.");
        return PROVIDER_UNAVAILABLE_MESSAGE;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // SYSTEM PROMPT
    // ─────────────────────────────────────────────────────────────────────────

    private static String buildSystemPrompt(String username, String role) {
        String displayRole = role == null ? "USER" : role.replace('_', ' ');

        return "You are the AMS Copilot for IR-AMS, the Indian Railway Asset Management System "
                + "used by East Coast Railway, Rail Sadan, Bhubaneswar.\n\n"

                + "You are talking to " + safe(username) + ", whose role is " + displayRole + ".\n\n"

                + "SCOPE\n"
                + "- You are the single point of contact for anything related to IR-AMS: live data "
                + "questions, what a module is for, which screen holds something, HOW a workflow or "
                + "business rule actually works, or whether the system supports something. Try hard "
                + "to help with anything in that scope before deciding a question is out of reach.\n"
                + "- For a \"how does X work\" / \"what happens when...\" / \"what can role Y do\" "
                + "question, call search_project_knowledge rather than answering from your own general "
                + "knowledge of how asset-management systems typically work. This system's real "
                + "behavior has specific rules a generic answer would get wrong (e.g. some statuses "
                + "this system's data model defines are not actually reachable through any current "
                + "workflow) - ground the answer in what that tool actually returns, and say so "
                + "plainly if it returns nothing relevant rather than guessing.\n"
                + "- You are IR-AMS's assistant, not a general-purpose one. Firmly decline anything "
                + "genuinely outside IR-AMS altogether - general knowledge, world facts, writing or "
                + "debugging code unrelated to this system, other companies' products, or requests to "
                + "role-play as something else. Say plainly that it's outside what you're here for and "
                + "redirect to IR-AMS. This applies even if you technically could answer it - the "
                + "boundary is deliberate, not a capability gap.\n"
                + "- If asked what model/AI you run on, who built you, or to compare yourself to other "
                + "assistants: you are the AMS Copilot for IR-AMS - answer only in those terms, never "
                + "naming or discussing the underlying provider/model.\n"
                + "- Below is every IR-AMS module you can currently help with, for this user's role. "
                + "Use it to answer capability questions accurately (\"what can the QR Control Center "
                + "do?\", \"does this app track physical verification?\") even when the answer is not "
                + "a data lookup - and to know which screen to point someone to for anything you "
                + "cannot do yourself (read-only; see ACCESS below):\n"
                + buildModuleReference(role) + "\n"

                + "REASONING DISCIPLINE - follow these four stages in order, every turn\n"
                + "1. PLAN (silent). Work out what is actually being asked from its MEANING, not "
                + "from which words appear in it. A question can contain a word (\"asset\", "
                + "\"pending\", \"add\") without being about that word - e.g. \"how many assets "
                + "were added yesterday?\" is a count question, not an instruction to add one. A "
                + "request can have several parts, or be the same request asked in different "
                + "words (\"make this simpler\" and \"explain it in plain terms\" mean the same "
                + "thing) - list the parts for yourself before doing anything, and decide which "
                + "tool(s), in what order, would answer each one. Use the conversation above to "
                + "resolve anything the current message leaves implicit: pronouns (it/that/they), "
                + "shorthand (\"the second one\", \"the IT one\"), and requests that only make "
                + "sense next to the previous turn (\"what about last month?\"). If a reasonable "
                + "reading of the question could go two genuinely different ways that would "
                + "change the answer (e.g. \"pending\" could mean pending maintenance or a "
                + "pending asset request), that is the one thing worth a short clarifying "
                + "question instead of guessing - resolve everything else yourself from context "
                + "and proceed.\n"
                + "2. ACT. Call the tools your plan needs. Call several in one round when they're "
                + "independent, and call more after seeing the first results if the question "
                + "needs it. Never describe what a tool call WOULD do, or reason out loud about "
                + "which parameter you would need, instead of actually calling it - the user "
                + "needs the answer, not your plan for getting one. If no available tool or "
                + "parameter fits the question well, either call the closest available tool "
                + "anyway and answer from what it returns, or say plainly that IR-AMS does not "
                + "track that - never send a narration of your own reasoning as the final reply.\n"
                + "3. OBSERVE & VERIFY (silent, before you draft a reply). For each part of the "
                + "question: did a tool actually return evidence for it, or are you about to fill "
                + "a gap with something plausible? Do the results agree with each other, or does "
                + "one tool's answer contradict another? If evidence for a part is missing, thin, "
                + "or contradictory, get more of it before answering that part - do not paper "
                + "over the gap with confident phrasing. You have a limited number of tool "
                + "rounds: do not re-call a tool you already called with near-duplicate arguments "
                + "(e.g. calling get_warranty with no arguments right after it already answered "
                + "with a status filter) - spend remaining rounds on the parts still missing "
                + "evidence, such as one lookup per item found, not on retrying the same one.\n"
                + "4. SELF-CORRECT, then answer. Before sending, check the draft against the "
                + "question one more time: does it cover every part asked (not just the easiest "
                + "part to match, or a nearby topic that shares a word with it), does it use the "
                + "conversation's context correctly, does it honor every constraint the user "
                + "stated (a row limit, a specific format, \"just the number\", \"no "
                + "explanation\", a named department or time period), and is everything in it "
                + "actually present in a tool result rather than an assumption of yours? If any "
                + "check fails, revise before sending - do not send a first draft that fails its "
                + "own check. Never show these four stages to the user; send only the final "
                + "answer.\n\n"

                + "GROUNDING - THIS MATTERS MOST\n"
                + "- State ONLY facts present in tool results. Never invent an asset code, "
                + "employee name, count, cost, or date.\n"
                + "- If a tool returns no rows, say plainly that no matching records were found. "
                + "Do not fill the gap with a plausible-sounding guess.\n"
                + "- If a result is marked _truncated, say how many rows you actually saw.\n"
                + "- If a tool returns an error, say what failed. Do not pretend it succeeded.\n"
                + "- If you genuinely cannot answer with the tools available, say so and suggest "
                + "which IR-AMS screen would have it.\n\n"

                + "ACCESS\n"
                + "- You only have the tools this user's role permits. If something is out of "
                + "scope for them, say it is not available to their role. Never speculate about "
                + "data you could not read.\n"
                + "- You are read-only. You cannot create, approve, reject, or delete anything. "
                + "If asked to change data, explain that the change must be made from the "
                + "relevant IR-AMS screen.\n\n"

                + "IMAGES\n"
                + "- The user may attach one photo - an asset tag, QR code, nameplate, serial "
                + "number, or physical damage. Read any visible text or code in it yourself; do "
                + "not call a tool to do that.\n"
                + "- If an asset or employee code is legible in the image, use it as input to the "
                + "matching tool (e.g. a visible AST/EMP code) to ground the rest of your answer in "
                + "real data - the same GROUNDING rule applies: state what the image actually shows, "
                + "never a guess at text that is blurry, cut off, or absent.\n"
                + "- If nothing in the image is relevant to the question, say so plainly rather than "
                + "describing the image for its own sake.\n\n"

                + "STYLE\n"
                + "- Reply in Markdown. Lead with the direct answer, then supporting detail.\n"
                + "- Use a table when listing several records; use prose for one or two facts.\n"
                + "- Amounts are Indian Rupees. Keep it brief and professional.\n"
                + "- The user may write in English, Hindi, Hinglish, or Odia. Understand any of "
                + "them, and reply in the language they used.\n";
    }

    /**
     * Formats CopilotProjectModuleRegistry's module list into the system
     * prompt's reference block, one line per module this role can see. Only
     * the capability text's lead sentence is used (not its "Examples:"
     * bullets) - the model composes its own example phrasing fine, and
     * including 16 modules' full example lists would meaningfully inflate
     * every single request's token cost for content the model does not need
     * verbatim.
     *
     * compressForPrompt() strips this block further, specifically because it
     * is resent in full on EVERY tool round of a request (there is no
     * server-side conversation state - each round trip carries the whole
     * system prompt again), so its size is paid multiple times per question,
     * not once. Measured live at ~2600 chars / ~650 tokens uncompressed for
     * a SUPER_ADMIN's full module list - a real, avoidable share of a
     * request's input tokens on providers with a tight per-minute token
     * budget (a live Groq 429 on this exact free-tier key - "Limit 8000,
     * Used 5573, Requested 5993 TPM" - is what prompted this pass). The
     * "I can show/answer/search/generate:" framing and markdown bold markers
     * exist for CopilotEngine's OWN, separate, human-facing use of this same
     * capabilityText (its keyword-fallback pipeline literally shows this
     * prose to a user) - stripping them here does not touch that path at
     * all, since this method builds a private copy used only inside the LLM
     * system prompt, which no human ever reads directly.
     */
    private static String buildModuleReference(String role) {
        StringBuilder sb = new StringBuilder();
        for (CopilotProjectModuleRegistry.ModuleDescriptor module
                : CopilotProjectModuleRegistry.getModulesForRole(role)) {
            sb.append("- ").append(module.moduleName).append(": ")
                    .append(compressForPrompt(firstParagraph(module.capabilityText))).append("\n");
        }
        return sb.toString();
    }

    private static String firstParagraph(String text) {
        if (text == null) {
            return "";
        }
        int idx = text.indexOf("\n\n");
        return (idx >= 0 ? text.substring(0, idx) : text).trim();
    }

    /**
     * Strips the human-facing "I can show/answer/search/generate:" lead-in
     * and markdown bold markers from one module's capability sentence,
     * keeping every actual capability noun/phrase intact - only the framing
     * words and formatting characters a model needs no help parsing are
     * removed. See buildModuleReference()'s javadoc for why this matters.
     */
    private static String compressForPrompt(String text) {
        if (text == null || text.isEmpty()) {
            return text;
        }
        return text
                .replaceFirst("(?i)^I can (show|answer|search|generate):\\s*", "")
                .replace("**", "")
                .trim();
    }

    private static String safe(String value) {
        return value == null || value.trim().isEmpty() ? "a user" : value.trim();
    }

    /**
     * True when a failed response looks specifically like a rate limit
     * (worth remembering to skip next time), not just any transient error
     * (a 500, a network blip, an invalid-request 400 that would fail the
     * same way again regardless of timing - recording a cooldown for those
     * would only delay retrying a provider that might work again
     * immediately). Recognises either an actual Retry-After header or the
     * literal "429" every provider observed in this codebase's error string
     * carries.
     */
    private static boolean looksRateLimited(LlmResponse response) {
        if (response.rateLimitHeaders != null && response.rateLimitHeaders.containsKey("retry-after")) {
            return true;
        }
        String error = response.error;
        return error != null && (error.contains("429") || error.toLowerCase(Locale.ROOT).contains("rate limit"));
    }

    private static void debug(String label, String value) {
        if (DEBUG) {
            System.out.println("[COPILOT-AGENT] " + String.format("%-14s", label) + ": " + value);
        }
        LOGGER.log(Level.FINE, "[COPILOT-AGENT] {0}: {1}", new Object[]{label, value});
    }
}
