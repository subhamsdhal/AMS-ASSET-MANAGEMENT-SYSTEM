package com.mycompany.asset_management_system_ams;

import java.util.ArrayList;
import java.util.HashSet;
import java.util.Iterator;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.logging.Level;
import java.util.logging.Logger;

import org.json.JSONArray;
import org.json.JSONObject;

/**
 * GeminiClient — LlmClient over Google's generateContent REST API.
 *
 * Translates the neutral types into Gemini's contents/parts shape:
 *   LlmMessage.USER        -> {role: "user",  parts:[{text}]}
 *   LlmMessage.ASSISTANT   -> {role: "model", parts:[{text}]}
 *   LlmMessage.TOOL_CALL   -> {role: "model", parts:[{functionCall}]}
 *   LlmMessage.TOOL_RESULT -> {role: "user",  parts:[{functionResponse}]}
 *   LlmToolSpec            -> tools[0].functionDeclarations[]
 */
public class GeminiClient implements LlmClient {

    private static final Logger LOGGER = Logger.getLogger(GeminiClient.class.getName());

    private static final String BASE_URL =
            "https://generativelanguage.googleapis.com/v1beta/models/";

    /**
     * Function calling is the whole mechanism here, so the default is a model
     * that does it well. Override in Settings (ams.copilot.ai_model) if the
     * account has access to a different one.
     *
     * Fault: this was "gemini-2.0-flash", which Google has since retired -
     * every real request failed with a 404 ("This model ... is no longer
     * available"), confirmed live in the server logs. Updated to the current
     * GA flash model as of Aug 2026.
     *
     * Public (not private) so TestCopilotConnectionServlet's "Test Gemini"
     * button probes the SAME default this client actually answers with,
     * instead of its own separate hardcoded literal drifting out of sync
     * with this one the next time a model is retired - which had already
     * happened once (the servlet still said "gemini-2.5-flash").
     */
    public static final String DEFAULT_MODEL = "gemini-3.6-flash";

    private final String apiKey;
    private final String model;

    public GeminiClient(String apiKey, String model) {
        this.apiKey = apiKey == null ? "" : apiKey.trim();
        this.model = model == null || model.trim().isEmpty() ? DEFAULT_MODEL : model.trim();
    }

    @Override
    public String providerName() {
        return "GEMINI";
    }

    @Override
    public String modelName() {
        return model;
    }

    @Override
    public boolean isConfigured() {
        return !apiKey.isEmpty();
    }

    @Override
    public LlmResponse chat(LlmRequest request) {
        if (!isConfigured()) {
            return LlmResponse.error("Gemini API key is not configured in Settings.");
        }

        try {
            JSONObject payload = buildPayload(request);
            Map<String, String> headers = new LinkedHashMap<String, String>();

            // Key travels as a header, not a query parameter, so it cannot leak
            // into proxy logs or an exception message containing the URL.
            headers.put("x-goog-api-key", apiKey);

            LlmHttp.Result result = LlmHttp.postJson(
                    BASE_URL + model + ":generateContent", headers, payload.toString());

            if (!result.ok()) {
                return LlmResponse.error("Gemini HTTP " + result.status + ": " + briefError(result.body));
            }
            return parseResponse(result.body);

        } catch (Exception e) {
            LOGGER.log(Level.WARNING, "Gemini call failed", e);
            return LlmResponse.error("Gemini call failed: " + e.getMessage());
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // REQUEST
    // ─────────────────────────────────────────────────────────────────────────

    // Package-private (not private) solely so CopilotContextUnderstandingTest
    // can assert on the built request payload directly without a live
    // network call - same reasoning as CopilotToolCatalog.toPlan()'s
    // visibility.
    JSONObject buildPayload(LlmRequest request) {
        JSONObject payload = new JSONObject();

        // Fault, found live: a mid-conversation provider FAILOVER (Groq or
        // NVIDIA made a tool call, then errored on the next round, and Gemini
        // took over) replays that tool call into Gemini's history as a native
        // functionCall part. Gemini 3 requires every functionCall part to
        // carry a thoughtSignature it itself issued - one from a different
        // provider does not exist and cannot be forged, so Gemini hard-400s:
        // "Function call is missing a thought_signature..." (confirmed live,
        // https://ai.google.dev/gemini-api/docs/thought-signatures). Calls
        // Gemini itself made DO carry a real signature and are safe to echo
        // back natively (see toContent's TOOL_CALL case); only a call that
        // arrived here signature-less needs different handling, so it is
        // rendered as plain text context instead of a native functionCall -
        // Gemini can still read what was already tried and found, it is just
        // not asked to validate a structure it never issued.
        Set<String> unsignedCallIds = new HashSet<String>();
        for (LlmMessage message : request.messages) {
            if (message.role == LlmMessage.Role.TOOL_CALL) {
                for (LlmToolCall call : message.toolCalls) {
                    if (call.thoughtSignature == null || call.thoughtSignature.isEmpty()) {
                        unsignedCallIds.add(call.id);
                    }
                }
            }
        }

        String systemPrompt = request.systemPrompt == null ? "" : request.systemPrompt;
        // Fault, found live: downgrading an unsigned call/result to plain
        // text (above) stopped the 400 crash, but Gemini then treated that
        // prose as unverified background rather than a completed lookup - it
        // re-explored from scratch with five extra, mostly redundant tool
        // calls (including re-calling the SAME tool) before landing on the
        // right answer anyway. A short, explicit directive fixes the
        // remaining efficiency problem the structural fix alone didn't:
        // told plainly that the prose IS a real completed result and that
        // repeating the same lookup is unnecessary, there's no more reason
        // for it to distrust text than a native functionResponse.
        if (!unsignedCallIds.isEmpty()) {
            systemPrompt += "\n\nSome tool results below appear as plain text like "
                    + "\"[Result of toolname: ...]\" rather than as a structured function response. "
                    + "That happened only because a different system component ran that lookup before "
                    + "you took over this question - the data itself is exactly as real, current, and "
                    + "already-verified as any tool result you retrieved yourself. Use it directly. Do "
                    + "not call the same tool again with the same or similar arguments just because it "
                    + "appears as text instead of a native result; only call a tool again if you "
                    + "genuinely need different data it has not already given you.";
        }
        if (!systemPrompt.trim().isEmpty()) {
            payload.put("systemInstruction", new JSONObject()
                    .put("parts", new JSONArray().put(new JSONObject().put("text", systemPrompt))));
        }

        JSONArray contents = new JSONArray();
        for (LlmMessage message : request.messages) {
            contents.put(toContent(message, unsignedCallIds));
        }
        payload.put("contents", contents);

        if (!request.tools.isEmpty()) {
            JSONArray declarations = new JSONArray();
            for (LlmToolSpec spec : request.tools) {
                declarations.put(toFunctionDeclaration(spec));
            }
            payload.put("tools", new JSONArray()
                    .put(new JSONObject().put("functionDeclarations", declarations)));
        }

        // Fault, found live: no thinkingConfig was ever set, so this model
        // (a "thinking" model by default) used its own dynamic/auto thinking
        // budget on EVERY call, including a trivial one-word connection
        // probe - confirmed live, a bare "Reply exactly with: Connected"
        // took 15-20s+ against Groq/NVIDIA's ~1-1.5s for the identical
        // probe. thinkingBudget: 0 (fully disabled) was tried first and
        // confirmed live to be REJECTED outright by this model - "Gemini
        // HTTP 400: Request contains an invalid argument" - gemini-3.6-flash
        // requires some non-zero thinking, unlike the 2.5 Flash-Lite line
        // where 0 was valid. 512 is therefore a floor, not a stylistic
        // choice: the smallest budget the API actually accepts, confirmed
        // live to cut the typical probe from ~15-20s to ~3-4s. Occasional
        // slower calls (low double-digit seconds) still happen even at this
        // budget - that appears to be Google-side inference variance for
        // this model/key, not something bounded further from this side.
        payload.put("generationConfig", new JSONObject()
                .put("temperature", request.temperature)
                .put("maxOutputTokens", request.maxTokens)
                .put("thinkingConfig", new JSONObject().put("thinkingBudget", 512)));

        return payload;
    }

    private JSONObject toContent(LlmMessage message, Set<String> unsignedCallIds) {
        JSONObject content = new JSONObject();
        JSONArray parts = new JSONArray();

        switch (message.role) {
            case USER:
                content.put("role", "user");
                parts.put(new JSONObject().put("text", message.text));
                if (message.hasImage()) {
                    // inlineData/mimeType/data, camelCase per the REST JSON
                    // schema - same convention this client already uses for
                    // systemInstruction/functionCall/thoughtSignature.
                    parts.put(new JSONObject().put("inlineData", new JSONObject()
                            .put("mimeType", message.imageMimeType)
                            .put("data", message.imageBase64)));
                }
                break;

            case ASSISTANT:
                content.put("role", "model");
                parts.put(new JSONObject().put("text", message.text));
                break;

            case TOOL_CALL:
                content.put("role", "model");
                for (LlmToolCall call : message.toolCalls) {
                    boolean hasSignature = call.thoughtSignature != null && !call.thoughtSignature.isEmpty();

                    if (!hasSignature) {
                        // This call did not originate from Gemini (see
                        // buildPayload's unsignedCallIds note) - describe it
                        // as plain text instead of a native functionCall, so
                        // Gemini reads it as context rather than a structure
                        // it must validate and cannot. Framed as an
                        // already-completed lookup (not a bare log line) so
                        // it reads the same as a real tool call, not a note
                        // to be re-verified - see buildPayload's system-prompt
                        // addendum for the explicit "don't repeat this" rule.
                        parts.put(new JSONObject().put("text",
                                "[Already looked up: " + call.name + "(" + call.arguments + ")]"));
                        continue;
                    }

                    JSONObject args = new JSONObject();
                    for (Map.Entry<String, String> entry : call.arguments.entrySet()) {
                        args.put(entry.getKey(), entry.getValue());
                    }
                    JSONObject part = new JSONObject().put("functionCall", new JSONObject()
                            .put("name", call.name)
                            .put("args", args));
                    // Fault: thoughtSignature was parsed nowhere and never
                    // echoed back - Gemini 3 models 400 on the very next turn
                    // ("Function call is missing a thought_signature..."),
                    // confirmed live. Must sit as a SIBLING of functionCall
                    // within the same part object, not nested inside it -
                    // https://ai.google.dev/gemini-api/docs/generate-content/thought-signatures
                    part.put("thoughtSignature", call.thoughtSignature);
                    parts.put(part);
                }
                break;

            case TOOL_RESULT:
            default:
                content.put("role", "user");
                // A functionResponse part must pair with a native
                // functionCall part earlier in the conversation - one whose
                // call was rendered as plain text above (no signature) has no
                // such pairing, so its result is described as plain text too,
                // for the same reason as the call itself.
                if (message.toolCallId != null && unsignedCallIds.contains(message.toolCallId)) {
                    // Framed as real, final, already-verified data - not a
                    // note to double-check - matching the directive added to
                    // the system prompt in buildPayload for this same fault.
                    parts.put(new JSONObject().put("text",
                            "[Real, verified result of " + (message.toolName == null ? "" : message.toolName)
                                    + " - use this directly, do not re-call it: " + message.text + "]"));
                } else {
                    parts.put(new JSONObject().put("functionResponse", new JSONObject()
                            .put("name", message.toolName == null ? "" : message.toolName)
                            .put("response", new JSONObject().put("result", message.text))));
                }
                break;
        }

        content.put("parts", parts);
        return content;
    }

    private JSONObject toFunctionDeclaration(LlmToolSpec spec) {
        JSONObject properties = new JSONObject();
        JSONArray required = new JSONArray();

        for (LlmToolSpec.Param param : spec.parameters.values()) {
            // Defensive, same reasoning as OpenAiCompatibleClient.toTool():
            // every param here is optional (LlmToolSpec has no "required"
            // concept), so a model that nulls one out instead of omitting it
            // is describing a valid state, not a schema violation. Gemini
            // has not been observed rejecting this the way Groq's stricter
            // validator did (confirmed live), but declaring it nullable
            // costs nothing and removes the same failure mode here before
            // it ever surfaces.
            JSONObject property = new JSONObject()
                    .put("type", "string")
                    .put("nullable", true)
                    .put("description", param.description);
            if (!param.allowedValues.isEmpty()) {
                property.put("enum", new JSONArray(param.allowedValues));
            }
            properties.put(param.name, property);
        }

        JSONObject parameters = new JSONObject()
                .put("type", "object")
                .put("properties", properties)
                .put("required", required);

        return new JSONObject()
                .put("name", spec.name)
                .put("description", spec.description)
                .put("parameters", parameters);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // RESPONSE
    // ─────────────────────────────────────────────────────────────────────────

    // Package-private (not private) solely so CopilotContextUnderstandingTest
    // can assert on null-argument parsing directly without a live network
    // call - same reasoning as CopilotToolCatalog.toPlan()'s visibility.
    LlmResponse parseResponse(String body) {
        JSONObject root = new JSONObject(body);

        if (!root.has("candidates") || root.getJSONArray("candidates").length() == 0) {
            // A promptFeedback block with no candidates means the request was
            // blocked by a safety filter rather than answered.
            if (root.has("promptFeedback")) {
                return LlmResponse.error("Gemini blocked the request: " + root.get("promptFeedback"));
            }
            return LlmResponse.error("Gemini returned no candidates.");
        }

        JSONObject candidate = root.getJSONArray("candidates").getJSONObject(0);
        if (!candidate.has("content")) {
            return LlmResponse.error("Gemini candidate had no content.");
        }

        JSONObject content = candidate.getJSONObject("content");
        JSONArray parts = content.optJSONArray("parts");
        if (parts == null) {
            return LlmResponse.text("");
        }

        StringBuilder text = new StringBuilder();
        List<LlmToolCall> calls = new ArrayList<LlmToolCall>();

        for (int i = 0; i < parts.length(); i++) {
            JSONObject part = parts.getJSONObject(i);

            if (part.has("text")) {
                text.append(part.getString("text"));
            }

            if (part.has("functionCall")) {
                JSONObject call = part.getJSONObject("functionCall");
                String name = call.optString("name", "");
                Map<String, String> arguments = new LinkedHashMap<String, String>();

                JSONObject args = call.optJSONObject("args");
                if (args != null) {
                    Iterator<String> keys = args.keys();
                    while (keys.hasNext()) {
                        String key = keys.next();
                        Object value = args.get(key);
                        // Fault, same one found live on the Groq/OpenAI-
                        // compatible path (see OpenAiCompatibleClient): a
                        // JSON null here is org.json's JSONObject.NULL
                        // singleton, and String.valueOf(JSONObject.NULL)
                        // produces the literal text "null" - not an absent
                        // value. Every param in this catalog is optional, so
                        // a null argument means "not using this filter", the
                        // same as omitting it; skipped here so it doesn't
                        // get treated downstream as a real filter value of
                        // the literal string "null".
                        if (JSONObject.NULL.equals(value)) {
                            continue;
                        }
                        // Coerced to String deliberately: every downstream field
                        // on CopilotQueryPlan is a String or parsed from one.
                        arguments.put(key, String.valueOf(value));
                    }
                }

                // Sibling of functionCall within this same part, not nested
                // inside it - see toContent()'s TOOL_CALL case for where this
                // gets echoed back.
                String thoughtSignature = part.has("thoughtSignature")
                        ? part.optString("thoughtSignature", null) : null;

                // Gemini assigns no call id, so synthesize a stable one per index.
                calls.add(new LlmToolCall("gem_" + i + "_" + name, name, arguments, thoughtSignature));
            }
        }

        if (!calls.isEmpty()) {
            return LlmResponse.tools(text.toString(), calls);
        }
        return LlmResponse.text(text.toString());
    }

    private String briefError(String body) {
        if (body == null || body.trim().isEmpty()) {
            return "(empty response body)";
        }
        try {
            JSONObject error = new JSONObject(body).optJSONObject("error");
            if (error != null) {
                return error.optString("message", body);
            }
        } catch (Exception ignored) {
            // Not JSON — fall through and return the raw text below.
        }
        return body.length() > 300 ? body.substring(0, 300) + "..." : body;
    }
}
