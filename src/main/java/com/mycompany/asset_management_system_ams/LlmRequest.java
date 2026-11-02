package com.mycompany.asset_management_system_ams;

import java.util.ArrayList;
import java.util.List;

/** LlmRequest — one provider-neutral call: system prompt + history + allowed tools. */
public class LlmRequest {

    public String systemPrompt = "";
    public final List<LlmMessage> messages = new ArrayList<LlmMessage>();
    public final List<LlmToolSpec> tools = new ArrayList<LlmToolSpec>();

    /** Provider model id. Blank means "use the provider client's default". */
    public String model = "";
    public double temperature = 0.2;
    public int maxTokens = 1200;

    public LlmRequest system(String prompt) {
        this.systemPrompt = prompt == null ? "" : prompt;
        return this;
    }

    public LlmRequest add(LlmMessage message) {
        if (message != null) {
            messages.add(message);
        }
        return this;
    }

    public LlmRequest addAll(List<LlmMessage> history) {
        if (history != null) {
            messages.addAll(history);
        }
        return this;
    }

    public LlmRequest withTools(List<LlmToolSpec> specs) {
        if (specs != null) {
            tools.addAll(specs);
        }
        return this;
    }
}
