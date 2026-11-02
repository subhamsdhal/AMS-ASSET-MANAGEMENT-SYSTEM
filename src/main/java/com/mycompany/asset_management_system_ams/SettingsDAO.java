package com.mycompany.asset_management_system_ams;

import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.Types;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.logging.Level;
import java.util.logging.Logger;

/**
 * SettingsDAO — Reads and writes system_settings key-value table.
 * Provides typed getters with fallback defaults.
 * All keys follow the ams.* namespace convention.
 */
public class SettingsDAO {

    private static final Logger LOGGER = Logger.getLogger(SettingsDAO.class.getName());
    private static final Map<String, String> DEFAULT_SETTINGS = createDefaultSettings();

    // -------------------------------------------------------
    // Core Read Methods
    // -------------------------------------------------------

    public static String get(String key, String defaultValue) {
        String effectiveDefault = getDefaultValue(key, defaultValue);
        String sql = "SELECT setting_value FROM system_settings WHERE setting_key = ? LIMIT 1";
        try (Connection con = DBConnection.getConnection();
             PreparedStatement ps = con.prepareStatement(sql)) {
            ps.setString(1, key);
            try (ResultSet rs = ps.executeQuery()) {
                if (rs.next()) {
                    String val = rs.getString("setting_value");
                    return (val != null && !val.trim().isEmpty()) ? val.trim() : effectiveDefault;
                }
            }
            insertDefaultSetting(key, effectiveDefault);
        } catch (Exception e) {
            LOGGER.log(Level.WARNING, "SettingsDAO.get failed for key: " + key, e);
        }
        return effectiveDefault;
    }

    public static boolean getBoolean(String key, boolean defaultValue) {
        String val = get(key, String.valueOf(defaultValue));
        return "true".equalsIgnoreCase(val) || "1".equals(val) || "yes".equalsIgnoreCase(val);
    }

    public static int getInt(String key, int defaultValue) {
        String val = get(key, String.valueOf(defaultValue));
        try {
            return Integer.parseInt(val.trim());
        } catch (NumberFormatException e) {
            return defaultValue;
        }
    }

    public static Map<String, String> getGroup(String group) {
        Map<String, String> map = new HashMap<>();
        String sql = "SELECT setting_key, setting_value FROM system_settings WHERE setting_group = ?";
        try (Connection con = DBConnection.getConnection();
             PreparedStatement ps = con.prepareStatement(sql)) {
            ps.setString(1, group);
            try (ResultSet rs = ps.executeQuery()) {
                while (rs.next()) {
                    String k = rs.getString("setting_key");
                    String v = rs.getString("setting_value");
                    if (k != null) {
                        map.put(k, v == null ? "" : v);
                    }
                }
            }
        } catch (Exception e) {
            LOGGER.log(Level.WARNING, "SettingsDAO.getGroup failed for group: " + group, e);
        }
        return map;
    }

    // -------------------------------------------------------
    // Core Write Methods
    // -------------------------------------------------------

    public static boolean set(String key, String value, int updatedBy) {
        String sql = "INSERT INTO system_settings (setting_key, setting_value, updated_by) VALUES (?, ?, ?) "
                   + "ON DUPLICATE KEY UPDATE setting_value = VALUES(setting_value), updated_by = VALUES(updated_by), "
                   + "updated_at = CURRENT_TIMESTAMP";
        try (Connection con = DBConnection.getConnection();
             PreparedStatement ps = con.prepareStatement(sql)) {
            ps.setString(1, key);
            ps.setString(2, value);
            if (updatedBy > 0) {
                ps.setInt(3, updatedBy);
            } else {
                ps.setNull(3, Types.INTEGER);
            }
            return ps.executeUpdate() > 0;
        } catch (Exception e) {
            LOGGER.log(Level.SEVERE, "SettingsDAO.set failed for key: " + key, e);
            return false;
        }
    }

    public static boolean set(String key, String value) {
        return set(key, value, 0);
    }

    public static void ensureDefaults() {
        for (Map.Entry<String, String> entry : DEFAULT_SETTINGS.entrySet()) {
            insertDefaultSetting(entry.getKey(), entry.getValue());
        }
    }

    // -------------------------------------------------------
    // Convenience Getters — Frequently Used Settings
    // -------------------------------------------------------

    // Organization
    public static String getOrgName() {
        return get("ams.organization.name", "East Coast Railway");
    }

    public static String getSystemName() {
        return get("ams.system.name", "Railway Asset Management System");
    }

    public static String getOrgLocation() {
        return get("ams.organization.location", "Rail Sadan, Bhubaneswar, Odisha");
    }

    public static String getZoneCode() {
        return get("ams.organization.zone_code", "ECoR");
    }

    public static String getOrgUnit() {
        return get("ams.organization.unit", "Headquarters / Rail Sadan");
    }

    public static String getCurrency() {
        return get("ams.system.currency", "INR");
    }

    public static String getContactEmail() {
        return get("ams.system.contact.email", "");
    }

    public static String getSupportPhone() {
        return get("ams.system.support.phone", "");
    }

    // QR
    // Fault: this used to check only system_settings (ams.qr.mobile_tunnel_url,
    // then ams.qr.public.base_url) - but QrUrlUtil, what GenerateAssetQrServlet
    // actually uses to build every real asset's live QR link, checks a THIRD,
    // higher-priority source first: the public_qr_base_urls table (the
    // multi-provider "Public QR Link Configuration" manager on
    // qr_control_center.jsp - add/label/activate any number of saved URLs,
    // not just one). If an admin activates a URL there instead of through
    // Settings' older single-URL "Mobile Tunnel" field, real QR codes
    // immediately started using it (correct), but settings.jsp's "Currently
    // Effective URL" display (and TunnelControlServlet's status responses,
    // which both call this method) kept showing the OLD system_settings
    // value - stale, and actively misleading about what's actually live.
    // Fixed by deferring to QrUrlUtil's resolution (already correct, checks
    // public_qr_base_urls first) instead of re-implementing a second,
    // narrower priority order here - one source of truth for "what's the
    // real effective QR base URL" instead of two that can silently diverge.
    public static String getQrBaseUrl() {
        String envBaseUrl = System.getenv("AMS_PUBLIC_BASE_URL");
        if (envBaseUrl != null && !envBaseUrl.trim().isEmpty()) {
            return envBaseUrl.trim().replaceAll("/$", "");
        }

        String resolved = QrUrlUtil.getConfiguredPublicBaseUrlForDisplay().trim();
        if (!resolved.isEmpty()) {
            return resolved.replaceAll("/$", "");
        }
        String base = get("ams.qr.public.base_url", "https://ams.example.org");
        return base.replaceAll("/$", "");
    }

    public static String getQrPublicPage() {
        return get("ams.qr.public_page", "/public_asset_view.jsp");
    }

    public static boolean isQrEnabled() {
        return getBoolean("ams.qr.enabled", true);
    }

    /** Full URL for a QR token: baseUrl + publicPage + ?token= + token */
    public static String buildQrUrl(String token) {
        if (token == null || token.trim().isEmpty()) return "";
        return getQrBaseUrl() + getQrPublicPage() + "?token=" + token.trim();
    }

    public static String getMobileTunnelUrl() {
        return get("ams.qr.mobile_tunnel_url", "");
    }

    public static boolean setMobileTunnelUrl(String url, int updatedBy) {
        return set("ams.qr.mobile_tunnel_url", url == null ? "" : url.trim(), updatedBy);
    }

    public static String getQrTunnelProvider() {
        return get("ams.qr.tunnel_provider", "ngrok");
    }

    public static boolean setQrTunnelProvider(String provider, int updatedBy) {
        return set("ams.qr.tunnel_provider", provider == null ? "ngrok" : provider.trim(), updatedBy);
    }

    // SMTP
    public static boolean isSmtpEnabled() {
        return getBoolean("ams.smtp.enabled", false);
    }

    public static String getSmtpHost() {
        return get("ams.smtp.host", "smtp.gmail.com");
    }

    public static int getSmtpPort() {
        return getInt("ams.smtp.port", 587);
    }

    public static boolean isSmtpTls() {
        return getBoolean("ams.smtp.tls", true);
    }

    public static String getSmtpUsername() {
        return get("ams.smtp.username", "");
    }

    /**
     * SMTP/Gmail app password, encrypted at rest since Follow-up: settings module
     * hardening. decryptSettingValue() falls back to the raw stored value when it
     * can't be decrypted, so a password saved before this change (plaintext) still
     * reads back correctly instead of breaking mail delivery.
     */
    public static String getSmtpPassword() {
        return decryptSettingValue(get("ams.smtp.password", ""));
    }

    public static String getSmtpSenderName() {
        return get("ams.smtp.sender_name", "IR-AMS Notification System");
    }

    public static String getSmtpReplyTo() {
        return get("ams.smtp.reply_to", "");
    }

    // AI Copilot
    public static boolean isCopilotEnabled() {
        return getBoolean("ams.copilot.enabled", true);
    }

    // Mobile Tunnel (dev/demo convenience - see TunnelControlServlet). Defaults
    // to false/off: this servlet can spawn a real OS-level child process
    // (cloudflared), a capability audit/28-tunnel-ops-control.md flags as
    // categorically inappropriate for a production deployment regardless of
    // how tightly RBAC restricts who can trigger it. RBAC alone controls *who*
    // can use it; this flag controls whether the capability exists at all in
    // this deployment. An operator running a local/demo instance must
    // explicitly opt in (INSERT/UPDATE system_settings SET setting_value='true'
    // WHERE setting_key='ams.mobile_tunnel.enabled') rather than it being
    // reachable by default the moment an ADMIN/SUPER_ADMIN session exists.
    public static boolean isMobileTunnelEnabled() {
        return getBoolean("ams.mobile_tunnel.enabled", false);
    }

    public static String getCopilotMode() {
        String mode = get("ams.copilot.mode", "");
        if ("AI_API".equalsIgnoreCase(mode)) {
            return "AI_API";
        }
        if ("RULE_BASED".equalsIgnoreCase(mode)) {
            return "RULE_BASED";
        }
        return isAiMode() ? "AI_API" : "RULE_BASED";
    }

    public static String getCopilotProvider() {
        String provider = get("ams.copilot.provider", "");
        if (isBlank(provider)) {
            provider = get("ams.copilot.ai_provider", "");
        }
        if (isBlank(provider)) {
            String mode = get("ams.copilot.mode", "RULE_BASED");
            provider = "AI_API".equalsIgnoreCase(mode) ? get("ams.copilot.ai_provider", "") : "LOCAL_DB";
        }
        return normalizeCopilotProvider(provider);
    }

    public static String getCopilotAiProvider() {
        // Default (not an override of any admin choice - only what a brand-new,
        // never-configured install falls back to) is GROQ, not GEMINI.
        //
        // Fault, found by reading LlmClientFactory's own latency-ranking
        // rationale next to this exact setting: that class already benchmarks
        // and documents GEMINI's forced "thinking" floor at 3-4s per call
        // (occasionally low double-digit seconds) versus GROQ/CUSTOM's
        // confirmed ~1-1.5s - and already orders the automatic FALLBACK chain
        // fast-first because of it. But this setting decides the PRIMARY
        // provider, which is always tried first regardless of that ranking -
        // and since GEMINI doesn't error, it never even reaches the fast
        // fallback; every single request on a fresh install (where an admin
        // has entered both a Gemini and a Groq/Custom key, or is relying on
        // Settings' own default selection) would silently eat that "thinking"
        // tax on every call, exactly the "much delay" a slow default produces.
        // An admin who explicitly selects Gemini from the Settings dropdown
        // still gets exactly that choice - this only changes what an
        // UNTOUCHED install defaults to before anyone has chosen anything.
        String provider = get("ams.copilot.ai_provider", "GROQ");
        provider = normalizeCopilotProvider(provider);
        if ("OPENAI".equals(provider)) {
            return "OPENAI";
        }
        if ("ANTHROPIC".equals(provider)) {
            return "ANTHROPIC";
        }
        if ("GEMINI".equals(provider)) {
            return "GEMINI";
        }
        if ("CUSTOM".equals(provider)) {
            return "CUSTOM";
        }
        return "GROQ";
    }

    public static boolean isAiMode() {
        String provider = getCopilotProvider();
        return "GEMINI".equalsIgnoreCase(provider)
                || "OPENAI".equalsIgnoreCase(provider)
                || "ANTHROPIC".equalsIgnoreCase(provider)
                || "GROQ".equalsIgnoreCase(provider)
                || "CUSTOM".equalsIgnoreCase(provider);
    }

    public static String getCopilotModel() {
        String model = get("ams.copilot.model", "");
        if (isBlank(model)) {
            model = get("ams.copilot.ai_model", "");
        }
        return model == null ? "" : model.trim();
    }

    public static String getCopilotAiModel() {
        String model = get("ams.copilot.ai_model", "");
        if (isBlank(model)) {
            model = getCopilotModel();
        }
        if (!isBlank(model)) {
            return model.trim();
        }
        return defaultModelForProvider(getCopilotAiProvider());
    }

    public static String getCopilotAiEndpoint() {
        return get("ams.copilot.ai_endpoint", "");
    }

    public static double getCopilotTemperature() {
        String raw = get("ams.copilot.temperature", "0.2");
        try {
            double value = Double.parseDouble(raw);
            if (value < 0) return 0;
            if (value > 2) return 2;
            return value;
        } catch (Exception e) {
            return 0.2;
        }
    }

    public static int getCopilotMaxTokens() {
        // Default raised from 800 to 1536 (still admin-overridable, still
        // capped at 4096 below). 800 tokens is roughly 600 words - genuinely
        // tight once the system prompt's own STYLE rule ("use a table when
        // listing several records") is followed for anything with more than
        // a handful of rows or columns, risking a table that cuts off
        // mid-row rather than finishing. Raising the CAP costs nothing for a
        // short answer (a one-line count still generates in the same
        // sub-second time on a fast provider - the model stops when it's
        // done, not when it hits the ceiling); it only prevents a longer,
        // genuinely-needed answer from being cut off unfinished.
        int maxTokens = getInt("ams.copilot.max_tokens", 1536);
        if (maxTokens < 128) return 128;
        if (maxTokens > 4096) return 4096;
        return maxTokens;
    }

    public static String getCopilotGeminiKey() {
        String encrypted = get("ams.copilot.gemini_key", "");
        String key = decryptSettingValue(encrypted);
        if (!isBlank(key)) {
            return key;
        }
        if ("GEMINI".equalsIgnoreCase(getCopilotProvider())) {
            return decryptSettingValue(get("ams.copilot.ai_api_key", ""));
        }
        return "";
    }

    public static String getGeminiApiKey() {
        return getCopilotGeminiKey();
    }

    public static boolean setCopilotGeminiKey(String apiKey, int userId) {
        if (apiKey == null || apiKey.trim().isEmpty()) return false;
        return set("ams.copilot.gemini_key", CryptoUtil.encrypt(apiKey), userId);
    }

    /**
     * Gemini's OWN model id - a dedicated field, not the old shared
     * ams.copilot.ai_model box. Root fix for a fault that recurred three
     * times live: that shared field's value meant "whichever provider is
     * currently Primary", so switching Primary AI Provider without also
     * retyping the model silently attached the WRONG provider's model
     * string to whichever became primary (most recently: Gemini's
     * "gemini-3.6-flash" ended up saved as GROQ's model, a 404 on every
     * real call). Every provider now owns its model permanently, regardless
     * of which one is Primary - mirrors getCopilotGroqModel() and
     * getCopilotCustomModel(), which already worked this way. Blank is a
     * valid answer here: GeminiClient falls back to its own DEFAULT_MODEL
     * when given one.
     */
    public static String getCopilotGeminiModel() {
        return get("ams.copilot.gemini_model", "").trim();
    }

    public static String getCopilotOpenAiKey() {
        String encrypted = get("ams.copilot.openai_key", "");
        String key = decryptSettingValue(encrypted);
        if (!isBlank(key)) {
            return key;
        }
        if ("OPENAI".equalsIgnoreCase(getCopilotProvider())) {
            return decryptSettingValue(get("ams.copilot.ai_api_key", ""));
        }
        return "";
    }

    public static String getOpenAIApiKey() {
        return getCopilotOpenAiKey();
    }

    public static boolean setCopilotOpenAiKey(String apiKey, int userId) {
        if (apiKey == null || apiKey.trim().isEmpty()) return false;
        return set("ams.copilot.openai_key", CryptoUtil.encrypt(apiKey), userId);
    }

    /**
     * Groq key for the LlmClient-based Copilot - same pattern as the other
     * providers. Fault: this getter (and the matching "GROQ" branch in
     * LlmClientFactory.build()) never existed, even though Settings has a
     * working "Test Connection" flow that saves a real, previously-verified
     * key to ams.copilot.groq_key/ams.copilot.provider.GROQ.api_key. With
     * Gemini's configured model retired and OpenAI out of credits, Groq sat
     * fully configured and already proven working, but was never actually
     * reachable at runtime - LlmClientFactory's fallback chain only knew
     * about GEMINI/ANTHROPIC/OPENAI/CUSTOM.
     */
    public static String getCopilotGroqKey() {
        String encrypted = get("ams.copilot.groq_key", "");
        String key = decryptSettingValue(encrypted);
        if (!isBlank(key)) {
            return key;
        }
        return decryptSettingValue(get("ams.copilot.provider.GROQ.api_key", ""));
    }

    public static String getCopilotGroqModel() {
        String model = get("ams.copilot.groq_model", "");
        if (!isBlank(model)) {
            return model;
        }
        return get("ams.copilot.provider.GROQ.model", "");
    }

    /**
     * Custom/Other provider's OWN model id, distinct from the shared
     * ams.copilot.ai_model field used by whichever provider is PRIMARY.
     *
     * Fault, found live: LlmClientFactory.build()'s CUSTOM branch used to
     * fall back to the shared ai_model field whenever Custom was used as a
     * FALLBACK (not primary) - so Custom silently inherited whatever model
     * string belonged to the actual primary provider (e.g. Groq's
     * "openai/gpt-oss-120b"), which is frequently not even a valid model id
     * on the Custom provider's own service (confirmed live: Cerebras 404'd
     * on that Groq-specific model name). This mirrors getCopilotGroqModel()'s
     * pattern - a dedicated key, not admin-editable from Settings today
     * (same as Groq's), set directly for whichever service is configured.
     */
    public static String getCopilotCustomModel() {
        return get("ams.copilot.custom_model", "");
    }

    public static boolean setCopilotGroqKey(String apiKey, int userId) {
        if (apiKey == null || apiKey.trim().isEmpty()) return false;
        return set("ams.copilot.groq_key", CryptoUtil.encrypt(apiKey), userId);
    }

    /** Anthropic (Claude) key for the LlmClient-based Copilot. Stored encrypted, same as the others. */
    public static String getCopilotClaudeKey() {
        String encrypted = get("ams.copilot.claude_key", "");
        String key = decryptSettingValue(encrypted);
        if (!isBlank(key)) {
            return key;
        }
        if ("ANTHROPIC".equalsIgnoreCase(getCopilotProvider())) {
            return decryptSettingValue(get("ams.copilot.ai_api_key", ""));
        }
        return "";
    }

    public static boolean setCopilotClaudeKey(String apiKey, int userId) {
        if (apiKey == null || apiKey.trim().isEmpty()) return false;
        return set("ams.copilot.claude_key", CryptoUtil.encrypt(apiKey), userId);
    }

    /**
     * Key for a user-supplied OpenAI-compatible provider (OpenRouter, Groq,
     * DeepSeek, Together, a local Ollama/LM Studio, ...). Paired with
     * ams.copilot.ai_endpoint, this is what lets an admin add a new provider
     * from the Settings UI without any code change.
     */
    public static String getCopilotCustomKey() {
        String encrypted = get("ams.copilot.custom_key", "");
        String key = decryptSettingValue(encrypted);
        if (!isBlank(key)) {
            return key;
        }
        if ("CUSTOM".equalsIgnoreCase(getCopilotProvider())) {
            return decryptSettingValue(get("ams.copilot.ai_api_key", ""));
        }
        return "";
    }

    public static boolean setCopilotCustomKey(String apiKey, int userId) {
        if (apiKey == null || apiKey.trim().isEmpty()) return false;
        return set("ams.copilot.custom_key", CryptoUtil.encrypt(apiKey), userId);
    }

    /** Human-readable label for a CUSTOM provider, shown in the UI and logs. */
    public static String getCopilotCustomLabel() {
        String label = get("ams.copilot.custom_label", "");
        return isBlank(label) ? "Custom Provider" : label.trim();
    }

    /**
     * When true (default), a failing primary provider automatically falls back
     * to any OTHER provider that has a key saved, before the Copilot drops to
     * the local keyword pipeline. Turn off to pin the Copilot to the primary.
     */
    public static boolean isCopilotFallbackEnabled() {
        return getBoolean("ams.copilot.fallback_enabled", true);
    }

    /**
     * Admin-chosen order for the fallback chain, saved from the draggable
     * chip row on the Settings page — a comma-separated list of provider
     * codes (e.g. "CUSTOM,GROQ,GEMINI"), highest priority first. Blank means
     * no override yet, so LlmClientFactory falls back to its own built-in
     * default order.
     */
    public static String getCopilotChainOrder() {
        return get("ams.copilot.chain_order", "");
    }

    public static boolean setCopilotChainOrder(String order, int userId) {
        return set("ams.copilot.chain_order", order == null ? "" : order.trim(), userId);
    }

    public static boolean isDbContextEnabled() {
        return getBoolean("ams.copilot.db_context_enabled", true);
    }

    public static boolean isDocumentSearchEnabled() {
        return getBoolean("ams.copilot.document_search_enabled", false);
    }

    public static boolean isSessionMemoryEnabled() {
        return getBoolean("ams.copilot.session_memory_enabled", false);
    }

    public static int getMaxContextRows() {
        return getInt("ams.copilot.max_context_rows", 50);
    }

    public static String getLastTestStatus() {
        return get("ams.copilot.last_test_status", "");
    }

    public static String getLastTestedAt() {
        return get("ams.copilot.last_tested_at", "");
    }

    // Health Score Weights
    public static int getHealthWeightAge() {
        return getInt("ams.health.weight.age", 20);
    }

    public static int getHealthWeightMaintenance() {
        return getInt("ams.health.weight.maintenance", 25);
    }

    public static int getHealthWeightWarranty() {
        return getInt("ams.health.weight.warranty", 20);
    }

    public static int getHealthWeightCondition() {
        return getInt("ams.health.weight.condition", 25);
    }

    public static int getHealthWeightVerification() {
        return getInt("ams.health.weight.verification", 10);
    }

    // Upload
    public static int getUploadMaxSizeMb() {
        return getInt("ams.upload.max_size_mb", 10);
    }

    public static String getUploadAllowedTypes() {
        return get("ams.upload.allowed_types", "jpg,jpeg,png,gif,pdf,doc,docx,xls,xlsx");
    }

    // Security
    public static int getSessionTimeout() {
        return getInt("ams.security.session.timeout", 30);
    }

    public static int getMaxLoginAttempts() {
        return getInt("ams.security.max.login.attempts", 5);
    }

    // Notifications
    public static int getWarrantyAlertDays() {
        return getInt("ams.notify.warranty.days", 30);
    }

    /** Aging threshold (days) for CopilotDigestScheduler's pending-item digest. */
    public static int getCopilotDigestAgingDays() {
        return getInt("ams.notify.copilot_digest.days", 3);
    }
    public static boolean isHealthScoreEnabled() {
        return getBoolean("ams.health.enabled", true);
    }

    public static String getUploadFolderPath() {
        return get("ams.upload.folder_path", "/var/ams/uploads");
    }

    public static String getBackupLocation() {
        return get("ams.backup.location", "/var/ams/backups");
    }

    public static String getBackupAutoSchedule() {
        return get("ams.backup.auto_schedule", "NEVER");
    }

    private static String normalizeCopilotProvider(String provider) {
        if (provider == null) {
            return "LOCAL_DB";
        }
        String p = provider.trim().toUpperCase();
        if ("OPENAI".equals(p) || "GPT".equals(p) || "OPENAI_GPT".equals(p)) {
            return "OPENAI";
        }
        if ("GEMINI".equals(p) || "GOOGLE".equals(p) || "GOOGLE_GEMINI".equals(p)) {
            return "GEMINI";
        }
        // Third provider for the LlmClient-based Copilot. "CLAUDE" is the label
        // shown in the Settings dropdown; ANTHROPIC is the vendor name — accept
        // both so the UI wording and the stored value don't have to match.
        if ("ANTHROPIC".equals(p) || "CLAUDE".equals(p)) {
            return "ANTHROPIC";
        }
        // Fault, found live: GROQ was missing here entirely, so it fell
        // through to LOCAL_DB - saving "GROQ" as primary via the Settings
        // dropdown persisted correctly to the database, but every read of it
        // back through this method (which is EVERY caller: getCopilotProvider(),
        // getCopilotAiProvider(), isAiMode(), the dropdown's rendered
        // selection, and LlmClientFactory's actual runtime chain-building)
        // silently discarded it. The save looked like it worked; the Copilot
        // just quietly kept using whatever it had before.
        if ("GROQ".equals(p)) {
            return "GROQ";
        }
        // Open-ended slot: any OpenAI-compatible endpoint the admin configures.
        if ("CUSTOM".equals(p) || "OPENAI_COMPATIBLE".equals(p) || "OTHER".equals(p)) {
            return "CUSTOM";
        }
        return "LOCAL_DB";
    }

    private static String defaultModelForProvider(String provider) {
        if ("OPENAI".equalsIgnoreCase(provider)) {
            return "gpt-4o-mini";
        }
        if ("ANTHROPIC".equalsIgnoreCase(provider)) {
            return "claude-sonnet-5";
        }
        if ("GROQ".equalsIgnoreCase(provider)) {
            return "openai/gpt-oss-120b";
        }
        // Fault: this was its own separate literal ("gemini-2.0-flash"),
        // the exact model Google has since retired (confirmed live, HTTP
        // 404) - the same drift already fixed in three other copies of this
        // same method elsewhere in the codebase, missed here because this
        // one lives in SettingsDAO rather than a client/servlet class.
        // Function calling is the mechanism the agent loop runs on, so the
        // default needs to be a model that supports it well - reusing the
        // one place that default is allowed to be defined.
        return GeminiClient.DEFAULT_MODEL;
    }

    private static String getDefaultValue(String key, String fallback) {
        if (DEFAULT_SETTINGS.containsKey(key)) {
            return DEFAULT_SETTINGS.get(key);
        }
        return fallback == null ? "" : fallback;
    }

    private static void insertDefaultSetting(String key, String value) {
        if (!DEFAULT_SETTINGS.containsKey(key)) {
            return;
        }

        String sql = "INSERT IGNORE INTO system_settings "
                + "(setting_key, setting_value, setting_group, description) VALUES (?, ?, ?, ?)";
        try (Connection con = DBConnection.getConnection();
             PreparedStatement ps = con.prepareStatement(sql)) {
            ps.setString(1, key);
            ps.setString(2, value == null ? "" : value);
            ps.setString(3, inferSettingGroup(key));
            ps.setString(4, "Default setting");
            ps.executeUpdate();
        } catch (Exception e) {
            LOGGER.log(Level.WARNING, "SettingsDAO default insert failed for key: " + key, e);
        }
    }

    private static String inferSettingGroup(String key) {
        if (key == null) {
            return "GENERAL";
        }
        if (key.startsWith("ams.copilot") || key.startsWith("ams.ai")) {
            return "COPILOT";
        }
        if (key.startsWith("ams.smtp")) {
            return "SMTP";
        }
        if (key.startsWith("ams.qr")) {
            return "QR";
        }
        if (key.startsWith("ams.notify")) {
            return "NOTIFICATIONS";
        }
        if (key.startsWith("ams.security")) {
            return "SECURITY";
        }
        if (key.startsWith("ams.health")) {
            return "HEALTH";
        }
        if (key.startsWith("ams.upload")) {
            return "UPLOAD";
        }
        if (key.startsWith("ams.backup")) {
            return "BACKUP";
        }
        if (key.startsWith("ams.organization") || key.startsWith("ams.system")) {
            return "ORGANIZATION";
        }
        return "GENERAL";
    }

    private static Map<String, String> createDefaultSettings() {
        Map<String, String> defaults = new LinkedHashMap<>();

        defaults.put("ams.organization.name", "East Coast Railway");
        defaults.put("ams.system.name", "Railway Asset Management System");
        defaults.put("ams.organization.location", "Rail Sadan, Bhubaneswar, Odisha");
        defaults.put("ams.organization.unit", "Headquarters / Rail Sadan");
        defaults.put("ams.organization.zone_code", "ECoR");
        defaults.put("ams.system.contact.email", "");
        defaults.put("ams.system.support.phone", "");
        defaults.put("ams.system.currency", "INR");
        defaults.put("ams.system.timezone", "Asia/Kolkata");
        defaults.put("ams.system.description", "");

        defaults.put("ams.smtp.enabled", "false");
        defaults.put("ams.smtp.host", "smtp.gmail.com");
        defaults.put("ams.smtp.port", "587");
        defaults.put("ams.smtp.tls", "true");
        defaults.put("ams.smtp.username", "");
        defaults.put("ams.smtp.password", "");
        defaults.put("ams.smtp.sender_name", "IR-AMS Notification System");
        defaults.put("ams.smtp.reply_to", "");

        defaults.put("ams.qr.public.base_url", "https://ams.example.org");
        defaults.put("ams.qr.public_page", "/public_asset_view.jsp");
        defaults.put("ams.qr.mobile_tunnel_url", "");
        defaults.put("ams.qr.enabled", "true");

        defaults.put("ams.copilot.enabled", "true");
        defaults.put("ams.copilot.mode", "RULE_BASED");
        defaults.put("ams.copilot.provider", "LOCAL_DB");
        defaults.put("ams.copilot.model", "");
        defaults.put("ams.copilot.ai_provider", "GROQ");
        defaults.put("ams.copilot.ai_model", "gemini-1.5-flash");
        defaults.put("ams.copilot.ai_endpoint", "");
        defaults.put("ams.copilot.gemini_key", "");
        defaults.put("ams.copilot.openai_key", "");
        defaults.put("ams.copilot.ai_api_key", "");
        defaults.put("ams.ai.enabled", "false");
        defaults.put("ams.copilot.db_context_enabled", "true");
        defaults.put("ams.copilot.document_search_enabled", "false");
        defaults.put("ams.copilot.session_memory_enabled", "false");
        defaults.put("ams.copilot.max_context_rows", "50");
        defaults.put("ams.copilot.temperature", "0.2");
        defaults.put("ams.copilot.max_tokens", "1536");
        defaults.put("ams.copilot.last_test_status", "");
        defaults.put("ams.copilot.last_tested_at", "");

        defaults.put("ams.security.session.timeout", "30");
        defaults.put("ams.security.max.login.attempts", "5");
        defaults.put("ams.security.audit.enabled", "true");

        defaults.put("ams.notify.warranty.days", "30");
        defaults.put("ams.notify.copilot_digest.days", "3");
        defaults.put("ams.notify.maintenance.overdue", "true");
        defaults.put("ams.notify.new.employee.email", "true");
        defaults.put("ams.notify.allocation.email", "true");
        defaults.put("ams.notify.request.email", "true");

        defaults.put("ams.health.enabled", "true");
        defaults.put("ams.health.weight.age", "20");
        defaults.put("ams.health.weight.maintenance", "25");
        defaults.put("ams.health.weight.warranty", "20");
        defaults.put("ams.health.weight.condition", "25");
        defaults.put("ams.health.weight.verification", "10");

        defaults.put("ams.upload.max_size_mb", "10");
        defaults.put("ams.upload.allowed_types", "jpg,jpeg,png,gif,pdf,doc,docx,xls,xlsx");
        defaults.put("ams.upload.folder_path", "/var/ams/uploads");

        defaults.put("ams.backup.location", "/var/ams/backups");
        defaults.put("ams.backup.auto_schedule", "NEVER");

        return defaults;
    }

    private static String decryptSettingValue(String storedValue) {
        if (isBlank(storedValue)) {
            return "";
        }
        String decrypted = CryptoUtil.decrypt(storedValue.trim());
        if (!isBlank(decrypted)) {
            return decrypted.trim();
        }
        return storedValue.trim();
    }

    private static boolean isBlank(String value) {
        return value == null || value.trim().isEmpty();
    }
}
