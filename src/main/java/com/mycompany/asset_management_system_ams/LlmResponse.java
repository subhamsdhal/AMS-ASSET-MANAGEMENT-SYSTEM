package com.mycompany.asset_management_system_ams;

import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * LlmResponse — one provider-neutral reply.
 *
 * Either the model produced text (done), or it asked to run tools (loop again),
 * or the call failed (error != null, and CopilotAgentLoop falls back to the
 * existing keyword pipeline rather than showing the user a stack trace).
 */
public class LlmResponse {

    public final String text;
    public final List<LlmToolCall> toolCalls;
    public final String error;

    /**
     * Provider-reported rate-limit info (x-ratelimit-* response headers),
     * lower-cased key -> raw value, exactly as the provider sent it. Empty
     * for providers that don't expose this (Gemini's generateContent API
     * returns none at all - a platform limitation, not a client bug) or when
     * not populated by the calling client. Read by two places: the Settings
     * page's quota check, and (when a "retry-after" key is present on an
     * error response) CopilotAgentLoop's LlmProviderCooldown - so a provider
     * that just reported a rate limit is skipped automatically on the next
     * question instead of paying for the same failed round trip again.
     */
    public Map<String, String> rateLimitHeaders = new LinkedHashMap<String, String>();

    private LlmResponse(String text, List<LlmToolCall> toolCalls, String error) {
        this.text = text == null ? "" : text;
        this.toolCalls = toolCalls == null ? new ArrayList<LlmToolCall>() : toolCalls;
        this.error = error;
    }

    /** Fluent setter so a client can attach headers to its own return without a new constructor overload. */
    public LlmResponse withRateLimitHeaders(Map<String, String> headers) {
        if (headers != null) {
            this.rateLimitHeaders = headers;
        }
        return this;
    }

    public static LlmResponse text(String text) {
        return new LlmResponse(text, null, null);
    }

    public static LlmResponse tools(String text, List<LlmToolCall> calls) {
        return new LlmResponse(text, calls, null);
    }

    public static LlmResponse error(String message) {
        return new LlmResponse("", null, message == null ? "Unknown LLM error" : message);
    }

    public boolean isError() {
        return error != null;
    }

    public boolean hasToolCalls() {
        return toolCalls != null && !toolCalls.isEmpty();
    }
}
