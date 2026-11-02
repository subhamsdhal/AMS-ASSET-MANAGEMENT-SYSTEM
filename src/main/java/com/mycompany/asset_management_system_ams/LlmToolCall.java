package com.mycompany.asset_management_system_ams;

import java.util.LinkedHashMap;
import java.util.Map;

/**
 * LlmToolCall — the model's request to run one tool, normalized across providers.
 *
 * Arguments are kept as plain Strings rather than typed values on purpose: every
 * field they map onto in CopilotQueryPlan is a String (or is parsed from one),
 * and keeping them untyped here means a provider that returns a number where we
 * expected text can't blow up the loop.
 */
public class LlmToolCall {

    /** Provider-assigned id. Gemini does not supply one, so we synthesize it. */
    public final String id;
    public final String name;
    public final Map<String, String> arguments;

    /**
     * Gemini 3.x-only: a per-call opaque token the API returns alongside a
     * functionCall part and requires back, byte-for-byte, in that exact same
     * part when the call is echoed into the next turn's conversation history -
     * omitting it on a Gemini 3 model's first function call of a step is a
     * hard 400 ("Function call is missing a thought_signature..."), confirmed
     * live. Null for every other provider (Claude/OpenAI/Groq/custom), which
     * have no equivalent concept - GeminiClient is the only place that reads
     * or writes this field.
     */
    public final String thoughtSignature;

    public LlmToolCall(String id, String name, Map<String, String> arguments) {
        this(id, name, arguments, null);
    }

    public LlmToolCall(String id, String name, Map<String, String> arguments, String thoughtSignature) {
        this.id = id == null || id.trim().isEmpty() ? ("call_" + Math.abs(String.valueOf(name).hashCode())) : id;
        this.name = name == null ? "" : name.trim();
        this.arguments = arguments == null ? new LinkedHashMap<String, String>() : arguments;
        this.thoughtSignature = thoughtSignature;
    }

    public String arg(String key) {
        String value = arguments.get(key);
        return value == null ? "" : value.trim();
    }

    @Override
    public String toString() {
        return name + arguments;
    }
}
