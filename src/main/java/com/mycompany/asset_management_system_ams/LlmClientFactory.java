package com.mycompany.asset_management_system_ams;

import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * LlmClientFactory — resolves the configured provider into an LlmClient.
 *
 * Everything is read from system_settings (via SettingsDAO) so the Copilot's
 * provider, model, endpoint, and key are all changeable from the Settings UI
 * with no redeploy:
 *
 *   ams.copilot.ai_provider  GEMINI | ANTHROPIC | GROQ | CUSTOM (selectable as primary)
 *   ams.copilot.ai_model     model id (per-provider default if blank)
 *   ams.copilot.ai_endpoint  base URL — required for CUSTOM, optional elsewhere
 *   ams.copilot.gemini_key   encrypted Gemini key
 *   ams.copilot.claude_key   encrypted Anthropic key (no primary UI - backend only)
 *   ams.copilot.openai_key   encrypted OpenAI key (no UI at all - see note below)
 *   ams.copilot.groq_key     encrypted Groq key
 *   ams.copilot.custom_key   encrypted key for any OpenAI-compatible provider
 *
 * CUSTOM is what makes this open-ended: any service speaking the OpenAI
 * /chat/completions format (OpenRouter, DeepSeek, Together, a local Ollama
 * or LM Studio) can be added from Settings alone.
 *
 * OPENAI is deliberately absent from both the Settings UI and the automatic
 * fallback candidates below - the configured account has no billing credits
 * (confirmed live), so trying it on every fallback would just be a
 * guaranteed-failing round trip. The build() branch and stored key are left
 * in place rather than deleted, so re-adding it later (a funded account) is
 * a one-line change, not a rebuild.
 *
 * Returns null when nothing usable is configured, which is the signal for
 * CopilotAgentLoop to skip the LLM path entirely and let CopilotEngine run its
 * existing keyword pipeline instead.
 */
public final class LlmClientFactory {

    private LlmClientFactory() {
    }

    public static LlmClient create() {
        List<LlmClient> chain = createChain();
        return chain.isEmpty() ? null : chain.get(0);
    }

    /**
     * The ordered provider chain: the configured primary first, then every
     * OTHER provider that has a usable key, as automatic fallback — unless an
     * admin has dragged the chips in Settings into a different order, in
     * which case that saved order wins (see {@link #orderedChain}).
     *
     * Why a chain rather than a single client: free and low-tier API plans are
     * exactly the ones that rate-limit, time out, or briefly 5xx. Without this,
     * one transient 429 on the primary drops the user all the way down to
     * keyword matching for that question. With it, a second configured provider
     * answers instead and the user never notices.
     *
     * Only providers whose key is actually saved are included — a blank key
     * never enters the chain, so a half-configured provider can't add latency
     * by being tried and failing.
     *
     * Fallback can be switched off from Settings, in which case only the
     * primary is returned.
     */
    public static List<LlmClient> createChain() {
        List<LlmClient> chain = new ArrayList<LlmClient>();
        for (Map.Entry<String, LlmClient> entry : orderedChain().entrySet()) {
            chain.add(entry.getValue());
        }
        return chain;
    }

    /**
     * Every provider that currently has a usable key/endpoint, keyed by its
     * canonical code (GEMINI/ANTHROPIC/CUSTOM/GROQ/...), in the built-in
     * default order: primary first, then the fixed candidate order below.
     * This is the set-and-default-order step; {@link #orderedChain} applies
     * any saved drag-and-drop preference on top of it.
     */
    private static LinkedHashMap<String, LlmClient> configuredCandidates() {
        String primary = SettingsDAO.getCopilotAiProvider();
        String endpoint = SettingsDAO.getCopilotAiEndpoint();

        LinkedHashMap<String, LlmClient> configured = new LinkedHashMap<String, LlmClient>();

        // Fault, found live (three times): the primary provider used to get
        // its model from the shared ams.copilot.ai_model field - a box whose
        // correct value depended on whatever Primary AI Provider happened to
        // be selected. Switching primary without also retyping the model
        // silently attached the OLD primary's model string to the NEW one
        // (most recently: Gemini's "gemini-3.6-flash" saved as Groq's model,
        // 404 on every real call). modelFor() below resolves each
        // provider's OWN dedicated field instead - the exact same call used
        // for fallbacks a few lines down - so primary and fallback are now
        // symmetric: whichever role a provider plays, it always runs on its
        // own model, never on whatever a different provider left behind.
        LlmClient primaryClient = build(primary, modelFor(primary), endpoint);
        if (primaryClient != null && primaryClient.isConfigured()) {
            configured.put(primary, primaryClient);
        }

        if (!SettingsDAO.isCopilotFallbackEnabled()) {
            return configured;
        }

        // Fault: GROQ never appeared here even though Settings has a working
        // "Test Connection" flow for it (see getCopilotGroqKey()) - a real,
        // previously-verified Groq key could sit fully configured and still
        // never be reachable as a fallback. Added so a Groq key saved from
        // Settings actually participates in the chain.
        // OpenAI deliberately excluded from automatic fallback (no billing
        // credits on the configured account, confirmed live - a fallback
        // attempt there is a guaranteed-failing round trip on every single
        // request). Still fully working as an explicit CUSTOM/primary choice
        // if the account is ever funded; just not tried silently.
        //
        // CUSTOM ordered ahead of GROQ: confirmed live on this account's own
        // dashboards, the CUSTOM slot (Cerebras, gemma-4-31b) carries far
        // higher throughput than GROQ's tool-calling-capable models
        // (openai/gpt-oss-120b and its 1K-req/day tier) - 30K tokens/min and
        // 1,000,000 tokens/day on Cerebras versus 8K tokens/min and 200,000
        // tokens/day on Groq. Falling back to the thinner quota first would
        // burn it before ever trying the deeper one.
        // CUSTOM/GROQ ordered ahead of GEMINI/ANTHROPIC: this is a latency
        // ranking, not just quota. Both are "thinking"/extended-reasoning
        // models by default on this account - GeminiClient documents its own
        // forced thinkingBudget floor costing 3-4s per call minimum (and
        // "occasional... low double-digit seconds"), and ClaudeClient floors
        // max_tokens at 8000 specifically because current Claude models
        // think by default too. Cerebras/Groq were confirmed live at
        // ~1-1.5s for the same probe. Since CopilotAgentLoop can make
        // several sequential round trips for one compound question, putting
        // the slow reasoning models first by default meant every multi-round
        // question paid their latency repeatedly even when a fast provider
        // was equally capable of answering. This is only the DEFAULT order —
        // an admin can still drag the chips in Settings to override it per
        // account once real quota/latency numbers are known for their keys.
        for (String candidate : new String[]{"CUSTOM", "GROQ", "GEMINI", "ANTHROPIC"}) {
            if (configured.containsKey(candidate)) {
                continue;
            }
            // Fallbacks use each provider's OWN model, not the primary's -
            // "gemini-2.0-flash" is meaningless to Anthropic, and passing it
            // through would turn every failover into a 404.
            LlmClient fallback = build(candidate, modelFor(candidate), endpoint);
            if (fallback != null && fallback.isConfigured()) {
                configured.put(candidate, fallback);
            }
        }

        return configured;
    }

    /**
     * Resolves a provider's OWN model id, regardless of whether it is
     * currently Primary or a fallback - the single source of truth
     * {@link #configuredCandidates} uses for both roles, so there is no
     * longer a "primary reads one field, fallback reads another" split for
     * this class to get out of sync. GEMINI and ANTHROPIC blank out
     * deliberately: neither has anything meaningful stored when unset (no
     * dedicated Settings field for Anthropic - it has no Primary AI
     * Provider option at all), and their clients already fall back to a
     * sensible built-in default for a blank model (see
     * GeminiClient.DEFAULT_MODEL and ClaudeClient's own default).
     */
    private static String modelFor(String provider) {
        if ("GEMINI".equals(provider)) {
            return SettingsDAO.getCopilotGeminiModel();
        }
        if ("GROQ".equals(provider)) {
            return SettingsDAO.getCopilotGroqModel();
        }
        if ("CUSTOM".equals(provider)) {
            return SettingsDAO.getCopilotCustomModel();
        }
        return "";
    }

    /**
     * Applies the admin's saved drag-and-drop order (ams.copilot.chain_order,
     * a comma-separated list of provider codes) on top of the configured
     * candidates. A code in the saved order that isn't actually configured
     * right now is simply skipped. A configured provider NOT mentioned in the
     * saved order — because nothing was ever dragged, or a new key was just
     * added and hasn't been dragged into place yet — keeps its default-order
     * position as a tail, so it is never silently dropped from the chain.
     */
    private static LinkedHashMap<String, LlmClient> orderedChain() {
        LinkedHashMap<String, LlmClient> remaining = configuredCandidates();
        LinkedHashMap<String, LlmClient> ordered = new LinkedHashMap<String, LlmClient>();

        String savedOrder = SettingsDAO.getCopilotChainOrder();
        if (savedOrder != null && !savedOrder.trim().isEmpty()) {
            for (String rawCode : savedOrder.split(",")) {
                String code = rawCode.trim().toUpperCase();
                LlmClient client = remaining.remove(code);
                if (client != null) {
                    ordered.put(code, client);
                }
            }
        }
        ordered.putAll(remaining);
        return ordered;
    }

    /** One entry in the human-readable chain, carrying both its provider code (for the drag-and-drop order) and display text. */
    public static final class ChainEntry {
        public final String code;
        public final String display;

        ChainEntry(String code, String display) {
            this.code = code;
            this.display = display;
        }
    }

    /**
     * The active chain as (code, display) pairs, in the same order
     * {@link #createChain} will actually try them — what the Settings page's
     * draggable chip row is built from.
     */
    public static List<ChainEntry> describeChainEntries() {
        List<ChainEntry> entries = new ArrayList<ChainEntry>();
        for (Map.Entry<String, LlmClient> entry : orderedChain().entrySet()) {
            LlmClient client = entry.getValue();
            entries.add(new ChainEntry(entry.getKey(), client.providerName() + " (" + client.modelName() + ")"));
        }
        return entries;
    }

    /** Builds a client for one provider, or null if the name is unrecognised. */
    private static LlmClient build(String provider, String model, String endpoint) {
        if ("ANTHROPIC".equals(provider)) {
            return new ClaudeClient(SettingsDAO.getCopilotClaudeKey(), model);
        }
        if ("OPENAI".equals(provider)) {
            // This branch was missing entirely, so selecting OpenAI fell through
            // to Gemini and was constructed with the Gemini key.
            return new OpenAiCompatibleClient(
                    SettingsDAO.getCopilotOpenAiKey(), model, endpointFor(provider, endpoint), "OPENAI");
        }
        if ("CUSTOM".equals(provider)) {
            // Fault, found live: this fell back to the SHARED ai_model field
            // (whichever provider is primary's model) whenever Custom was
            // used purely as a fallback - so Custom silently ran with the
            // primary's model string, which frequently isn't valid on
            // Custom's own service (confirmed live: Cerebras 404'd on Groq's
            // "openai/gpt-oss-120b"). Falls back to Custom's OWN dedicated
            // model setting now, mirroring how GROQ already has its own
            // groq_model distinct from the shared field - only reached when
            // Custom is NOT primary, since when it IS primary "model" here
            // is already that provider's real, non-blank ai_model value.
            String customModel = model == null || model.trim().isEmpty()
                    ? SettingsDAO.getCopilotCustomModel() : model;
            if (endpoint == null || endpoint.trim().isEmpty()
                    || customModel == null || customModel.trim().isEmpty()) {
                return null;
            }
            return new OpenAiCompatibleClient(
                    SettingsDAO.getCopilotCustomKey(), customModel, endpoint,
                    SettingsDAO.getCopilotCustomLabel());
        }
        if ("GEMINI".equals(provider)) {
            return new GeminiClient(SettingsDAO.getCopilotGeminiKey(), model);
        }
        if ("GROQ".equals(provider)) {
            // Groq speaks the OpenAI /chat/completions format, so it reuses
            // OpenAiCompatibleClient - same as CUSTOM, but with Groq's fixed,
            // well-known endpoint baked in rather than requiring an admin to
            // type it, since it's not actually arbitrary the way a true
            // CUSTOM provider's endpoint is.
            String groqModel = model == null || model.trim().isEmpty()
                    ? SettingsDAO.getCopilotGroqModel() : model;
            if (groqModel == null || groqModel.trim().isEmpty()) {
                groqModel = "openai/gpt-oss-120b";
            }
            return new OpenAiCompatibleClient(
                    SettingsDAO.getCopilotGroqKey(), groqModel, "https://api.groq.com/openai/v1", "GROQ");
        }
        return null;
    }

    /**
     * A custom endpoint belongs to the CUSTOM provider only. Passing it to
     * OpenAI as a fallback would send OpenAI's key to somebody else's server.
     */
    private static String endpointFor(String provider, String configuredEndpoint) {
        return "CUSTOM".equals(provider) ? configuredEndpoint : "";
    }

    /** True when an LLM-backed Copilot is both enabled and has a usable config. */
    public static boolean isAvailable() {
        return SettingsDAO.isCopilotEnabled() && !createChain().isEmpty();
    }

    /** Human-readable chain for the Settings screen, e.g. "GEMINI -> CLAUDE". */
    public static String describeChain() {
        List<ChainEntry> entries = describeChainEntries();
        if (entries.isEmpty()) {
            return "";
        }
        StringBuilder sb = new StringBuilder();
        for (ChainEntry entry : entries) {
            if (sb.length() > 0) {
                sb.append(" → ");
            }
            sb.append(entry.display);
        }
        return sb.toString();
    }
}
