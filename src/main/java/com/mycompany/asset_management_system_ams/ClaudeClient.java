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
 * ClaudeClient — LlmClient over Anthropic's Messages API.
 *
 * Translates the neutral types into Claude's messages/content-block shape:
 *   LlmMessage.USER        -> {role:"user",      content:"..."}
 *   LlmMessage.ASSISTANT   -> {role:"assistant", content:"..."}
 *   LlmMessage.TOOL_CALL   -> {role:"assistant", content:[{type:"tool_use"}]}
 *   LlmMessage.TOOL_RESULT -> {role:"user",      content:[{type:"tool_result"}]}
 *   LlmToolSpec            -> tools[] with an input_schema
 *
 * Unused unless an Anthropic key is set in Settings — the Copilot runs on
 * whichever provider LlmClientFactory resolves.
 */
public class ClaudeClient implements LlmClient {

    private static final Logger LOGGER = Logger.getLogger(ClaudeClient.class.getName());

    private static final String ENDPOINT = "https://api.anthropic.com/v1/messages";
    private static final String API_VERSION = "2023-06-01";
    private static final String DEFAULT_MODEL = "claude-sonnet-5";

    /**
     * Current Claude models think by default and that reasoning counts against
     * max_tokens, so a budget tuned for a plain completion can truncate the
     * answer mid-sentence. Floor it well above the Copilot's normal setting.
     */
    private static final int MIN_MAX_TOKENS = 8000;

    private final String apiKey;
    private final String model;

    public ClaudeClient(String apiKey, String model) {
        this.apiKey = apiKey == null ? "" : apiKey.trim();
        this.model = model == null || model.trim().isEmpty() ? DEFAULT_MODEL : model.trim();
    }

    @Override
    public String providerName() {
        return "CLAUDE";
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
            return LlmResponse.error("Anthropic API key is not configured in Settings.");
        }

        try {
            JSONObject payload = buildPayload(request);

            Map<String, String> headers = new LinkedHashMap<String, String>();
            headers.put("x-api-key", apiKey);
            headers.put("anthropic-version", API_VERSION);

            LlmHttp.Result result = LlmHttp.postJson(ENDPOINT, headers, payload.toString());

            if (!result.ok()) {
                return LlmResponse.error("Claude HTTP " + result.status + ": " + briefError(result.body));
            }
            return parseResponse(result.body);

        } catch (Exception e) {
            LOGGER.log(Level.WARNING, "Claude call failed", e);
            return LlmResponse.error("Claude call failed: " + e.getMessage());
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // REQUEST
    // ─────────────────────────────────────────────────────────────────────────

    // Package-private (not private) solely so ClaudeClientTest can assert on
    // the built request payload directly without a live network call - same
    // reasoning as GeminiClient.buildPayload()'s visibility.
    JSONObject buildPayload(LlmRequest request) {
        JSONObject payload = new JSONObject();
        payload.put("model", model);
        payload.put("max_tokens", Math.max(request.maxTokens, MIN_MAX_TOKENS));

        // NOTE: temperature is deliberately NOT sent. Current Claude models
        // reject sampling parameters (temperature/top_p/top_k) with a 400.
        // Response style is steered through the system prompt instead.

        if (request.systemPrompt != null && !request.systemPrompt.trim().isEmpty()) {
            payload.put("system", request.systemPrompt);
        }

        JSONArray messages = new JSONArray();
        for (LlmMessage message : request.messages) {
            messages.put(toMessage(message));
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

    private JSONObject toMessage(LlmMessage message) {
        JSONObject json = new JSONObject();

        switch (message.role) {
            case USER:
                if (message.hasImage()) {
                    // Claude requires content BLOCKS (not a plain string) the
                    // moment an image is involved - a text block plus an
                    // image block, both inside the same content array.
                    JSONArray blocks = new JSONArray();
                    blocks.put(new JSONObject().put("type", "text").put("text", message.text));
                    blocks.put(new JSONObject()
                            .put("type", "image")
                            .put("source", new JSONObject()
                                    .put("type", "base64")
                                    .put("media_type", message.imageMimeType)
                                    .put("data", message.imageBase64)));
                    json.put("role", "user").put("content", blocks);
                } else {
                    json.put("role", "user").put("content", message.text);
                }
                break;

            case ASSISTANT:
                json.put("role", "assistant").put("content", message.text);
                break;

            case TOOL_CALL: {
                JSONArray blocks = new JSONArray();
                if (message.text != null && !message.text.trim().isEmpty()) {
                    blocks.put(new JSONObject().put("type", "text").put("text", message.text));
                }
                for (LlmToolCall call : message.toolCalls) {
                    JSONObject input = new JSONObject();
                    for (Map.Entry<String, String> entry : call.arguments.entrySet()) {
                        input.put(entry.getKey(), entry.getValue());
                    }
                    blocks.put(new JSONObject()
                            .put("type", "tool_use")
                            .put("id", call.id)
                            .put("name", call.name)
                            .put("input", input));
                }
                json.put("role", "assistant").put("content", blocks);
                break;
            }

            case TOOL_RESULT:
            default: {
                JSONArray blocks = new JSONArray();
                blocks.put(new JSONObject()
                        .put("type", "tool_result")
                        .put("tool_use_id", message.toolCallId == null ? "" : message.toolCallId)
                        .put("content", message.text));
                json.put("role", "user").put("content", blocks);
                break;
            }
        }

        return json;
    }

    private JSONObject toTool(LlmToolSpec spec) {
        JSONObject properties = new JSONObject();

        for (LlmToolSpec.Param param : spec.parameters.values()) {
            JSONObject property = new JSONObject()
                    .put("type", "string")
                    .put("description", param.description);
            if (!param.allowedValues.isEmpty()) {
                property.put("enum", new JSONArray(param.allowedValues));
            }
            properties.put(param.name, property);
        }

        JSONObject schema = new JSONObject()
                .put("type", "object")
                .put("properties", properties)
                .put("required", new JSONArray());

        return new JSONObject()
                .put("name", spec.name)
                .put("description", spec.description)
                .put("input_schema", schema);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // RESPONSE
    // ─────────────────────────────────────────────────────────────────────────

    private LlmResponse parseResponse(String body) {
        JSONObject root = new JSONObject(body);

        // Safety classifiers can decline with a normal 200 — check before
        // reading content, which is empty or partial on a refusal.
        if ("refusal".equals(root.optString("stop_reason", ""))) {
            return LlmResponse.error("Claude declined this request (safety refusal).");
        }

        JSONArray content = root.optJSONArray("content");
        if (content == null) {
            return LlmResponse.error("Claude returned no content.");
        }

        StringBuilder text = new StringBuilder();
        List<LlmToolCall> calls = new ArrayList<LlmToolCall>();

        for (int i = 0; i < content.length(); i++) {
            JSONObject block = content.getJSONObject(i);
            String type = block.optString("type", "");

            if ("text".equals(type)) {
                text.append(block.optString("text", ""));

            } else if ("tool_use".equals(type)) {
                Map<String, String> arguments = new LinkedHashMap<String, String>();
                JSONObject input = block.optJSONObject("input");
                if (input != null) {
                    Iterator<String> keys = input.keys();
                    while (keys.hasNext()) {
                        String key = keys.next();
                        arguments.put(key, String.valueOf(input.get(key)));
                    }
                }
                calls.add(new LlmToolCall(
                        block.optString("id", ""), block.optString("name", ""), arguments));
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
