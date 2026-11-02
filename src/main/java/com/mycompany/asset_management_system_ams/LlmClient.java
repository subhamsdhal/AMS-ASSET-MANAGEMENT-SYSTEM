package com.mycompany.asset_management_system_ams;

/**
 * LlmClient — the provider seam for the AI Copilot.
 *
 * CopilotAgentLoop talks only to this interface, so switching the Copilot
 * between Gemini and Claude (or adding another provider later) is a Settings
 * change plus one new implementation — no change to the reasoning loop, the
 * tool catalog, or any DAO.
 *
 * Implementations MUST:
 *  - never throw out of chat(); return LlmResponse.error(...) instead, so the
 *    agent loop can fall back to the local keyword pipeline cleanly
 *  - translate LlmToolSpec into their own function/tool-calling format
 *  - return tool calls as LlmToolCall rather than parsing prose for them
 */
public interface LlmClient {

    /** Short provider label for logs and the debug footer, e.g. "GEMINI". */
    String providerName();

    /** The model id this client will actually use for the next call. */
    String modelName();

    /** False when no API key is configured — the loop then skips straight to fallback. */
    boolean isConfigured();

    /** Never throws; failures come back as LlmResponse.error(...). */
    LlmResponse chat(LlmRequest request);
}
