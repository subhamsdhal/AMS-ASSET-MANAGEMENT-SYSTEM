package com.mycompany.asset_management_system_ams;

import java.util.ArrayList;
import java.util.Iterator;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.logging.Level;
import java.util.logging.Logger;

import org.json.JSONArray;
import org.json.JSONObject;

/**
 * OpenAiCompatibleClient — one client for every provider that speaks the
 * OpenAI /chat/completions format with tool calling.
 *
 * That is deliberately most of them. Rather than writing and maintaining a
 * separate client per vendor, this covers OpenAI itself plus any service that
 * implements the same wire format, with the endpoint supplied from Settings:
 *
 *   OpenAI       https://api.openai.com/v1/chat/completions
 *   OpenRouter   https://openrouter.ai/api/v1/chat/completions
 *   Groq         https://api.groq.com/openai/v1/chat/completions
 *   DeepSeek     https://api.deepseek.com/v1/chat/completions
 *   Together     https://api.together.xyz/v1/chat/completions
 *   Ollama       http://localhost:11434/v1/chat/completions      (local, no key)
 *   LM Studio    http://localhost:1234/v1/chat/completions       (local, no key)
 *
 * So "add another provider" becomes a Settings change — endpoint, key, model —
 * with no new Java and no redeploy.
 *
 * Wire-format notes that differ from the other clients:
 *  - tool arguments arrive as a JSON *string* that must be parsed, not as an object
 *  - tool results are their own {"role":"tool"} message, not a content block
 */
public class OpenAiCompatibleClient implements LlmClient {

    private static final Logger LOGGER = Logger.getLogger(OpenAiCompatibleClient.class.getName());

    private static final String DEFAULT_ENDPOINT = "https://api.openai.com/v1/chat/completions";
    private static final String DEFAULT_MODEL = "gpt-4o-mini";

    private final String apiKey;
    private final String model;
    private final String endpoint;
    private final String label;

    public OpenAiCompatibleClient(String apiKey, String model, String endpoint, String label) {
        this.apiKey = apiKey == null ? "" : apiKey.trim();
        this.model = model == null || model.trim().isEmpty() ? DEFAULT_MODEL : model.trim();
        this.endpoint = normalizeEndpoint(endpoint);
        this.label = label == null || label.trim().isEmpty() ? "OPENAI_COMPATIBLE" : label.trim();
    }

    /**
     * Accepts either a full URL or just a base, so an admin pasting
     * "https://openrouter.ai/api/v1" from a provider's docs still works.
     */
    private static String normalizeEndpoint(String configured) {
        if (configured == null || configured.trim().isEmpty()) {
            return DEFAULT_ENDPOINT;
        }
        String url = configured.trim();
        while (url.endsWith("/")) {
            url = url.substring(0, url.length() - 1);
        }
        if (url.endsWith("/chat/completions")) {
            return url;
        }
        return url + "/chat/completions";
    }

    @Override
    public String providerName() {
        return label;
    }

    @Override
    public String modelName() {
        return model;
    }

    @Override
    public boolean isConfigured() {
        // A local runtime (Ollama, LM Studio) needs no key, so a localhost
        // endpoint counts as configured on its own.
        return !apiKey.isEmpty() || isLocalEndpoint();
    }

    private boolean isLocalEndpoint() {
        String lower = endpoint.toLowerCase();
        return lower.contains("localhost") || lower.contains("127.0.0.1") || lower.contains("0.0.0.0");
    }

    @Override
    public LlmResponse chat(LlmRequest request) {
        if (!isConfigured()) {
            return LlmResponse.error("API key is not configured in Settings for " + label + ".");
        }

        try {
            JSONObject payload = buildPayload(request);

            Map<String, String> headers = new LinkedHashMap<String, String>();
            if (!apiKey.isEmpty()) {
                headers.put("Authorization", "Bearer " + apiKey);
            }

            LlmHttp.Result result = LlmHttp.postJson(endpoint, headers, payload.toString());
            Map<String, String> rateLimitInfo = extractRateLimitHeaders(result.headers);

            if (!result.ok()) {
                // Captured even on failure - a 429 carries these headers too,
                // and that is often the single most useful moment to read
                // them (see the Settings page's quota check).
                return LlmResponse.error(label + " HTTP " + result.status + ": " + briefError(result.body))
                        .withRateLimitHeaders(rateLimitInfo);
            }
            return parseResponse(result.body).withRateLimitHeaders(rateLimitInfo);

        } catch (Exception e) {
            LOGGER.log(Level.WARNING, label + " call failed", e);
            return LlmResponse.error(label + " call failed: " + e.getMessage());
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // REQUEST
    // ─────────────────────────────────────────────────────────────────────────

    // Package-private (not private) solely so OpenAiCompatibleClientTest can
    // assert on the built request payload directly without a live network
    // call - same reasoning as GeminiClient.buildPayload()'s visibility.
    JSONObject buildPayload(LlmRequest request) {
        JSONObject payload = new JSONObject();
        payload.put("model", model);
        payload.put("max_tokens", request.maxTokens);
        payload.put("temperature", request.temperature);

        JSONArray messages = new JSONArray();

        if (request.systemPrompt != null && !request.systemPrompt.trim().isEmpty()) {
            messages.put(new JSONObject()
                    .put("role", "system")
                    .put("content", request.systemPrompt));
        }

        for (LlmMessage message : request.messages) {
            switch (message.role) {
                case USER:
                    if (message.hasImage()) {
                        // Standard OpenAI vision format: content becomes an
                        // array of parts (text + image_url as a data URI)
                        // instead of a plain string the moment an image is
                        // attached. A model/provider with no vision support
                        // typically 400s on this - the existing provider
                        // failover chain (LlmClientFactory.createChain())
                        // already treats any such error as "try the next
                        // configured provider", so no special handling is
                        // needed here for that case.
                        JSONArray parts = new JSONArray();
                        parts.put(new JSONObject().put("type", "text").put("text", message.text));
                        parts.put(new JSONObject()
                                .put("type", "image_url")
                                .put("image_url", new JSONObject().put("url",
                                        "data:" + message.imageMimeType + ";base64," + message.imageBase64)));
                        messages.put(new JSONObject().put("role", "user").put("content", parts));
                    } else {
                        messages.put(new JSONObject().put("role", "user").put("content", message.text));
                    }
                    break;

                case ASSISTANT:
                    messages.put(new JSONObject().put("role", "assistant").put("content", message.text));
                    break;

                case TOOL_CALL: {
                    JSONArray calls = new JSONArray();
                    for (LlmToolCall call : message.toolCalls) {
                        JSONObject args = new JSONObject();
                        for (Map.Entry<String, String> entry : call.arguments.entrySet()) {
                            args.put(entry.getKey(), entry.getValue());
                        }
                        calls.put(new JSONObject()
                                .put("id", call.id)
                                .put("type", "function")
                                .put("function", new JSONObject()
                                        .put("name", call.name)
                                        // arguments is a JSON *string* here, not an object
                                        .put("arguments", args.toString())));
                    }
                    JSONObject assistant = new JSONObject()
                            .put("role", "assistant")
                            .put("tool_calls", calls);
                    // Some strict implementations reject a missing content key.
                    assistant.put("content", message.text == null ? "" : message.text);
                    messages.put(assistant);
                    break;
                }

                case TOOL_RESULT:
                default:
                    messages.put(new JSONObject()
                            .put("role", "tool")
                            .put("tool_call_id", message.toolCallId == null ? "" : message.toolCallId)
                            .put("name", message.toolName == null ? "" : message.toolName)
                            .put("content", message.text));
                    break;
            }
        }

        payload.put("messages", messages);

        if (!request.tools.isEmpty()) {
            JSONArray tools = new JSONArray();
            for (LlmToolSpec spec : request.tools) {
                tools.put(toTool(spec));
            }
            payload.put("tools", tools);
        }

        return payload;
    }

    private JSONObject toTool(LlmToolSpec spec) {
        JSONObject properties = new JSONObject();

        for (LlmToolSpec.Param param : spec.parameters.values()) {
            // Fault, found live: every LlmToolSpec param is optional (this
            // catalog has no "required" concept at all - see LlmToolSpec),
            // but the declared JSON type was a bare "string". A model that
            // decides not to use an optional field commonly emits a literal
            // JSON null for it rather than omitting the key, and Groq's tool
            // schema validator - unlike Gemini's, which tolerated it -
            // enforces the declared type strictly and REJECTS the whole tool
            // call: "parameters for tool get_available_assets did not match
            // schema: /category: expected string, but got null" (confirmed
            // live). Declaring the type as ["string","null"] is the standard
            // JSON Schema way to say "string OR absent", which is what every
            // one of these params actually means.
            JSONObject property = new JSONObject()
                    .put("type", new JSONArray().put("string").put("null"))
                    .put("description", param.description);
            if (!param.allowedValues.isEmpty()) {
                property.put("enum", new JSONArray(param.allowedValues));
            }
            properties.put(param.name, property);
        }

        JSONObject parameters = new JSONObject()
                .put("type", "object")
                .put("properties", properties)
                .put("required", new JSONArray());

        return new JSONObject()
                .put("type", "function")
                .put("function", new JSONObject()
                        .put("name", spec.name)
                        .put("description", spec.description)
                        .put("parameters", parameters));
    }

    // ─────────────────────────────────────────────────────────────────────────
    // RESPONSE
    // ─────────────────────────────────────────────────────────────────────────

    // Package-private (not private) solely so CopilotContextUnderstandingTest
    // can assert on null-argument parsing directly without a live network
    // call - same reasoning as CopilotToolCatalog.toPlan()'s visibility.
    LlmResponse parseResponse(String body) {
        JSONObject root = new JSONObject(body);

        JSONArray choices = root.optJSONArray("choices");
        if (choices == null || choices.length() == 0) {
            return LlmResponse.error(label + " returned no choices.");
        }

        JSONObject message = choices.getJSONObject(0).optJSONObject("message");
        if (message == null) {
            return LlmResponse.error(label + " choice had no message.");
        }

        String text = message.isNull("content") ? "" : message.optString("content", "");

        JSONArray toolCalls = message.optJSONArray("tool_calls");
        if (toolCalls != null && toolCalls.length() > 0) {
            List<LlmToolCall> calls = new ArrayList<LlmToolCall>();

            for (int i = 0; i < toolCalls.length(); i++) {
                JSONObject call = toolCalls.getJSONObject(i);
                JSONObject function = call.optJSONObject("function");
                if (function == null) {
                    continue;
                }

                String name = function.optString("name", "");
                Map<String, String> arguments = new LinkedHashMap<String, String>();

                // arguments is a JSON string, and a model can emit malformed
                // JSON here. Treat that as "no arguments" rather than failing
                // the whole turn - the tool can still run with defaults.
                String rawArgs = function.optString("arguments", "");
                if (!rawArgs.trim().isEmpty()) {
                    try {
                        JSONObject parsed = new JSONObject(rawArgs);
                        Iterator<String> keys = parsed.keys();
                        while (keys.hasNext()) {
                            String key = keys.next();
                            Object value = parsed.get(key);
                            // Fault, found live: org.json represents a JSON
                            // null as the JSONObject.NULL singleton, not Java
                            // null - String.valueOf(JSONObject.NULL) returns
                            // the literal four-character text "null", not an
                            // absent value. Every param here is optional (see
                            // LlmToolSpec), so a model explicitly nulling one
                            // out means "not using this filter" - the same
                            // thing as omitting it. Confirmed live: a null
                            // category argument was becoming the STRING
                            // "null", which CopilotToolCatalog.toPlan() then
                            // treated as a real (nonsense) category filter
                            // ("category = 'null'") instead of no filter at
                            // all. Skipped entirely here so LlmToolCall.arg()
                            // correctly falls back to "" for the missing key.
                            if (JSONObject.NULL.equals(value)) {
                                continue;
                            }
                            arguments.put(key, String.valueOf(value));
                        }
                    } catch (Exception e) {
                        LOGGER.log(Level.FINE, "Unparseable tool arguments from {0}: {1}",
                                new Object[]{label, rawArgs});
                    }
                }

                calls.add(new LlmToolCall(call.optString("id", "call_" + i), name, arguments));
            }

            if (!calls.isEmpty()) {
                return LlmResponse.tools(text, calls);
            }
        }

        return LlmResponse.text(text);
    }

    /**
     * Pulls out only the rate-limit-related response headers (x-ratelimit-*,
     * retry-after), lower-casing keys since header casing is not guaranteed
     * to be consistent across providers even though HTTP headers are
     * case-insensitive. Everything else in the response is ignored here.
     */
    private static Map<String, String> extractRateLimitHeaders(Map<String, List<String>> headers) {
        Map<String, String> result = new LinkedHashMap<String, String>();
        if (headers == null) {
            return result;
        }
        for (Map.Entry<String, List<String>> entry : headers.entrySet()) {
            String key = entry.getKey();
            if (key == null) {
                continue;
            }
            String lower = key.toLowerCase();
            if (lower.contains("ratelimit") || lower.equals("retry-after")) {
                result.put(lower, String.join(", ", entry.getValue()));
            }
        }
        return result;
    }

    private String briefError(String body) {
        if (body == null || body.trim().isEmpty()) {
            return "(empty response body)";
        }
        try {
            Object error = new JSONObject(body).opt("error");
            if (error instanceof JSONObject) {
                return ((JSONObject) error).optString("message", body);
            }
            if (error != null) {
                return String.valueOf(error);
            }
        } catch (Exception ignored) {
            // Not JSON — fall through and return the raw text below.
        }
        return body.length() > 300 ? body.substring(0, 300) + "..." : body;
    }
}
