package com.mycompany.asset_management_system_ams;

import jakarta.servlet.ServletException;
import jakarta.servlet.annotation.WebServlet;
import jakarta.servlet.http.HttpServlet;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import jakarta.servlet.http.HttpSession;

import java.io.IOException;
import java.io.PrintWriter;
import java.io.OutputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.nio.charset.StandardCharsets;
import java.text.SimpleDateFormat;
import java.util.Date;
import java.util.Map;
import java.util.Scanner;

@WebServlet(name = "TestCopilotConnectionServlet", urlPatterns = {"/TestCopilotConnectionServlet"})
public class TestCopilotConnectionServlet extends HttpServlet {

    @Override
    protected void doPost(HttpServletRequest request, HttpServletResponse response)
            throws ServletException, IOException {

        response.setContentType("text/plain;charset=UTF-8");
        PrintWriter out = response.getWriter();
        
        HttpSession session = request.getSession(false);
        if (session == null || session.getAttribute("username") == null) {
            out.print("Unauthorized");
            return;
        }

        if ("quota".equalsIgnoreCase(request.getParameter("action"))) {
            doQuotaCheck(request, out);
            return;
        }

        String requestedProvider = normalizeProvider(request.getParameter("provider"));
        String configuredProvider = SettingsDAO.getCopilotProvider();
        String provider = "LOCAL_DB".equals(requestedProvider) ? configuredProvider : requestedProvider;
        // Each provider now owns a permanently-dedicated model field (see
        // SettingsDAO.getCopilotGeminiModel/getCopilotGroqModel/
        // getCopilotCustomModel and LlmClientFactory.modelFor) instead of the
        // old shared ams.copilot.model box, whose value meant "whichever
        // provider is currently Primary" and got silently corrupted three
        // times live whenever that didn't match the provider being tested.
        // Testing any provider now reads THAT provider's own field, regardless
        // of which one is Primary.
        String model = modelForProvider(provider);
        String geminiKey = SettingsDAO.getCopilotGeminiKey();
        String openaiKey = SettingsDAO.getCopilotOpenAiKey();

        if ("LOCAL_DB".equalsIgnoreCase(provider)) {
            out.print("Local DB mode does not require an API test.");
            return;
        }

        String endpoint = SettingsDAO.getCopilotAiEndpoint();

        String apiKey;
        if ("GEMINI".equalsIgnoreCase(provider)) {
            apiKey = geminiKey;
        } else if ("ANTHROPIC".equalsIgnoreCase(provider)) {
            apiKey = SettingsDAO.getCopilotClaudeKey();
        } else if ("CUSTOM".equalsIgnoreCase(provider)) {
            apiKey = SettingsDAO.getCopilotCustomKey();
        } else if ("GROQ".equalsIgnoreCase(provider)) {
            apiKey = SettingsDAO.getCopilotGroqKey();
        } else {
            apiKey = openaiKey;
        }

        // Fault: this always tested the key already SAVED in the database,
        // silently ignoring anything just typed into the password field -
        // "Test" after pasting a new key (before clicking Save) tested the
        // OLD key with no indication that's what happened, and looked
        // identical to a real test of the new one. Settings.jsp now sends
        // whatever is currently in the form as pendingKey/pendingModel/
        // pendingEndpoint; a non-blank one here means the field hasn't been
        // saved yet, so it wins over the stored value. Left blank (the
        // normal case, testing an already-saved key) falls through to the
        // saved value exactly as before.
        String pendingKey = clean(request.getParameter("pendingKey"));
        if (!pendingKey.isEmpty()) {
            apiKey = pendingKey;
        }
        String pendingModel = clean(request.getParameter("pendingModel"));
        if (!pendingModel.isEmpty()) {
            model = pendingModel;
        }
        String pendingEndpoint = clean(request.getParameter("pendingEndpoint"));
        if (!pendingEndpoint.isEmpty()) {
            endpoint = pendingEndpoint;
        }

        // A local runtime (Ollama, LM Studio) legitimately has no key, so an
        // empty key is only fatal when the endpoint is remote.
        boolean localEndpoint = endpoint != null
                && (endpoint.contains("localhost") || endpoint.contains("127.0.0.1"));
        if ((apiKey == null || apiKey.isEmpty()) && !localEndpoint) {
            out.print("No API Key configured. Please save settings first.");
            return;
        }

        String resultMessage = "";
        try {
            // Gemini and Claude are tested THROUGH the same LlmClient the
            // Copilot itself uses, rather than through a second hand-rolled
            // request. A test that exercises different code from the real path
            // can pass while the real path is broken - which is the one thing a
            // connection test must never do. (It also stops the Gemini key
            // being placed in a URL query string, where it could reach proxy
            // and server logs; the client sends it as a header.)
            if (!"OPENAI".equalsIgnoreCase(provider)) {
                // model already came from THIS provider's own dedicated field
                // (or from pendingModel, just typed and not yet saved) - no
                // "does this belong to the currently-configured primary?"
                // guard is needed any more, since there is no shared field
                // left for it to have drifted from. Only fall back to a
                // hardcoded default if the provider has no model set at all.
                if (model == null || model.isEmpty()) {
                    model = defaultModelForProvider(provider);
                }

                LlmClient client;
                if ("ANTHROPIC".equalsIgnoreCase(provider)) {
                    client = new ClaudeClient(apiKey, model);
                } else if ("CUSTOM".equalsIgnoreCase(provider)) {
                    if (endpoint == null || endpoint.trim().isEmpty()) {
                        out.print("Set the Custom API Endpoint first, then save settings.");
                        return;
                    }
                    if (model == null || model.trim().isEmpty()) {
                        out.print("Set the AI Model Name for your custom provider, then save settings.");
                        return;
                    }
                    String pendingLabel = clean(request.getParameter("pendingLabel"));
                    String label = !pendingLabel.isEmpty() ? pendingLabel : SettingsDAO.getCopilotCustomLabel();
                    client = new OpenAiCompatibleClient(apiKey, model, endpoint, label);
                } else if ("GROQ".equalsIgnoreCase(provider)) {
                    client = new OpenAiCompatibleClient(apiKey, model, "https://api.groq.com/openai/v1", "GROQ");
                } else {
                    client = new GeminiClient(apiKey, model);
                }

                LlmRequest probe = new LlmRequest()
                        .system("You are a connection test. Reply with exactly one word.")
                        .add(LlmMessage.user("Reply exactly with: Connected"));
                probe.model = model;
                probe.maxTokens = 64;

                LlmResponse probeResult = client.chat(probe);

                if (probeResult.isError()) {
                    resultMessage = client.providerName() + " Error: " + extractSummary(probeResult.error);
                } else {
                    resultMessage = client.providerName() + " connected successfully! (model: "
                            + client.modelName() + ")";
                }

            } else if ("OPENAI".equalsIgnoreCase(provider)) {
                if (model == null || model.isEmpty()) {
                    model = defaultModelForProvider(provider);
                }
                String openAiEndpoint = "https://api.openai.com/v1/chat/completions";
                String payload = "{"
                        + "\"model\": \"" + model + "\","
                        + "\"messages\": [{\"role\": \"user\", \"content\": \"Reply exactly with: Connected\"}],"
                        + "\"max_tokens\": 10"
                        + "}";

                URL url = new URL(openAiEndpoint);
                HttpURLConnection conn = (HttpURLConnection) url.openConnection();
                conn.setRequestMethod("POST");
                conn.setRequestProperty("Content-Type", "application/json");
                conn.setRequestProperty("Authorization", "Bearer " + apiKey);
                conn.setDoOutput(true);
                
                try(OutputStream os = conn.getOutputStream()) {
                    byte[] input = payload.getBytes(StandardCharsets.UTF_8);
                    os.write(input, 0, input.length);
                }
                
                int code = conn.getResponseCode();
                if (code == 200) {
                    resultMessage = "OpenAI connected successfully!";
                } else {
                    String error = readStream(conn.getErrorStream());
                    resultMessage = "OpenAI Error (" + code + "): " + extractSummary(error);
                }
            }
        } catch (Exception e) {
            resultMessage = "Exception: " + e.getMessage();
        }

        // Makes the answer to "do I save first or test first?" visible in
        // the result itself instead of needing to be known in advance: if
        // any pending (unsaved) value was actually used, say so, so it's
        // never ambiguous which key this result is about.
        if (!pendingKey.isEmpty() || !pendingModel.isEmpty() || !pendingEndpoint.isEmpty()) {
            resultMessage += " (tested the key/settings currently in this form, not yet saved.)";
        }

        // Save result
        int userId = getSessionUserId(session);

        String time = new SimpleDateFormat("yyyy-MM-dd HH:mm:ss").format(new Date());
        SettingsDAO.set("ams.copilot.last_test_status", resultMessage, userId);
        SettingsDAO.set("ams.copilot.last_tested_at", time, userId);

        out.print(resultMessage);
    }

    /**
     * Quota check (action=quota) - the Settings page's "Usage" button.
     *
     * Makes the SAME kind of minimal probe request the "Test" button already
     * makes (1 max_tokens), but reads back the provider's own rate-limit
     * response headers instead of just a pass/fail message. Only meaningful
     * for OpenAI-compatible providers (Groq, Custom) that actually expose
     * x-ratelimit-* headers; Gemini and Anthropic do not return any
     * remaining-quota information on their APIs at all - that is reported
     * honestly rather than left blank, so the missing number does not read
     * as a bug in this check.
     */
    private void doQuotaCheck(HttpServletRequest request, PrintWriter out) {
        String provider = normalizeProvider(request.getParameter("provider"));

        if ("LOCAL_DB".equals(provider)) {
            out.print("Local DB mode does not call an API - there is no quota to check.");
            return;
        }
        if ("GEMINI".equalsIgnoreCase(provider) || "ANTHROPIC".equalsIgnoreCase(provider)) {
            out.print((("GEMINI".equalsIgnoreCase(provider)) ? "Gemini" : "Anthropic")
                    + " does not expose remaining-quota information in its API responses. "
                    + "The only signal available is a rate-limit error when the ceiling is actually hit.");
            return;
        }

        String apiKey;
        String model;
        String endpoint = "";
        String label;

        if ("GROQ".equalsIgnoreCase(provider)) {
            apiKey = SettingsDAO.getCopilotGroqKey();
            model = SettingsDAO.getCopilotGroqModel();
            if (model == null || model.trim().isEmpty()) {
                model = "openai/gpt-oss-120b";
            }
            endpoint = "https://api.groq.com/openai/v1";
            label = "GROQ";
        } else if ("CUSTOM".equalsIgnoreCase(provider)) {
            apiKey = SettingsDAO.getCopilotCustomKey();
            // Same fix as LlmClientFactory.build(): Custom's OWN model, not
            // the shared ai_model field that belongs to whichever provider
            // is primary - this quota check must probe with the model
            // Custom actually runs on, not Groq's or Gemini's.
            model = SettingsDAO.getCopilotCustomModel();
            endpoint = SettingsDAO.getCopilotAiEndpoint();
            label = SettingsDAO.getCopilotCustomLabel();
        } else if ("OPENAI".equalsIgnoreCase(provider)) {
            apiKey = SettingsDAO.getCopilotOpenAiKey();
            model = "gpt-4o-mini";
            label = "OPENAI";
        } else {
            out.print("Quota check is not available for this provider.");
            return;
        }

        // Same "test what's in the form right now, not just what's saved" rule as the Test button.
        String pendingKey = clean(request.getParameter("pendingKey"));
        if (!pendingKey.isEmpty()) {
            apiKey = pendingKey;
        }
        String pendingEndpoint = clean(request.getParameter("pendingEndpoint"));
        if (!pendingEndpoint.isEmpty()) {
            endpoint = pendingEndpoint;
        }

        boolean localEndpoint = endpoint != null
                && (endpoint.contains("localhost") || endpoint.contains("127.0.0.1"));
        if ((apiKey == null || apiKey.isEmpty()) && !localEndpoint) {
            out.print("No API key configured for " + label + ". Save settings first.");
            return;
        }
        if ("CUSTOM".equalsIgnoreCase(provider) && (endpoint == null || endpoint.trim().isEmpty())) {
            out.print("Set the Custom API Endpoint first, then save settings.");
            return;
        }

        OpenAiCompatibleClient client = new OpenAiCompatibleClient(apiKey, model, endpoint, label);

        LlmRequest probe = new LlmRequest()
                .system("You are a quota check.")
                .add(LlmMessage.user("hi"));
        probe.model = model;
        probe.maxTokens = 1;

        LlmResponse probeResult;
        try {
            probeResult = client.chat(probe);
        } catch (Exception e) {
            out.print(client.providerName() + ": quota check failed - " + e.getMessage());
            return;
        }

        out.print(formatQuota(client.providerName(), probeResult));
    }

    /** Turns the raw x-ratelimit-* headers into one human-readable line. */
    private String formatQuota(String providerName, LlmResponse result) {
        Map<String, String> h = result.rateLimitHeaders;

        if (h == null || h.isEmpty()) {
            return providerName + ": no rate-limit headers were returned"
                    + (result.isError()
                        ? " (the probe request itself failed: " + extractSummary(result.error) + ")"
                        : " (the probe request succeeded, but this provider does not expose usage headers).");
        }

        String limitTokens = h.get("x-ratelimit-limit-tokens");
        String remainingTokens = h.get("x-ratelimit-remaining-tokens");
        String resetTokens = h.get("x-ratelimit-reset-tokens");
        String limitRequests = h.get("x-ratelimit-limit-requests");
        String remainingRequests = h.get("x-ratelimit-remaining-requests");
        String resetRequests = h.get("x-ratelimit-reset-requests");

        StringBuilder sb = new StringBuilder(providerName).append(" usage — ");
        boolean any = false;

        if (limitTokens != null) {
            sb.append("Tokens: ").append(remainingTokens != null ? remainingTokens : "?")
              .append(" / ").append(limitTokens).append(" remaining");
            if (resetTokens != null) sb.append(" (resets in ").append(resetTokens).append(")");
            any = true;
        }
        if (limitRequests != null) {
            if (any) sb.append(" · ");
            sb.append("Requests: ").append(remainingRequests != null ? remainingRequests : "?")
              .append(" / ").append(limitRequests).append(" remaining");
            if (resetRequests != null) sb.append(" (resets in ").append(resetRequests).append(")");
            any = true;
        }

        // Recognised none of the standard names above but the provider DID
        // send something rate-limit-flavored (a differently-named header, or
        // just retry-after on a 429) - show it raw rather than silently drop it.
        if (!any) {
            for (Map.Entry<String, String> entry : h.entrySet()) {
                sb.append(entry.getKey()).append(": ").append(entry.getValue()).append("  ");
            }
        }

        if (result.isError()) {
            sb.append(" — probe request itself was rejected: ").append(extractSummary(result.error));
        }

        return sb.toString();
    }

    private String clean(String s) {
        return (s == null) ? "" : s.trim();
    }

    private String readStream(java.io.InputStream is) {
        if (is == null) return "No error stream content.";
        try (Scanner scanner = new Scanner(is, StandardCharsets.UTF_8.name())) {
            return scanner.useDelimiter("\\A").hasNext() ? scanner.next() : "";
        }
    }
    
    private String extractSummary(String jsonError) {
        if (jsonError == null) return "Unknown error";
        if (jsonError.length() > 200) {
            return jsonError.substring(0, 200) + "...";
        }
        return jsonError;
    }

    private String normalizeProvider(String provider) {
        if (provider == null) {
            return "LOCAL_DB";
        }
        String p = provider.trim().toUpperCase();
        if ("GEMINI".equals(p) || "OPENAI".equals(p) || "ANTHROPIC".equals(p)
                || "CUSTOM".equals(p) || "GROQ".equals(p)) {
            return p;
        }
        if ("CLAUDE".equals(p)) {
            return "ANTHROPIC";
        }
        if ("OPENAI_COMPATIBLE".equals(p) || "OTHER".equals(p)) {
            return "CUSTOM";
        }
        return "LOCAL_DB";
    }

    /**
     * Reads the model actually saved for {@code provider} out of its own
     * dedicated field. GEMINI/GROQ/CUSTOM each own a permanent field now;
     * ANTHROPIC has no Settings UI yet and OPENAI's hand-rolled test path
     * below never had one either, so both still fall back to the legacy
     * shared getter (which SaveSettingsServlet no longer writes to, so this
     * only ever returns whatever a much older save left behind, or blank -
     * either way {@link #defaultModelForProvider} covers the rest).
     */
    private String modelForProvider(String provider) {
        if ("GEMINI".equalsIgnoreCase(provider)) {
            return SettingsDAO.getCopilotGeminiModel();
        }
        if ("GROQ".equalsIgnoreCase(provider)) {
            return SettingsDAO.getCopilotGroqModel();
        }
        if ("CUSTOM".equalsIgnoreCase(provider)) {
            return SettingsDAO.getCopilotCustomModel();
        }
        return SettingsDAO.getCopilotModel();
    }

    private String defaultModelForProvider(String provider) {
        if ("OPENAI".equalsIgnoreCase(provider)) {
            return "gpt-4o-mini";
        }
        if ("ANTHROPIC".equalsIgnoreCase(provider)) {
            return "claude-sonnet-5";
        }
        if ("CUSTOM".equalsIgnoreCase(provider)) {
            // Fault, found live: this always returned blank, so clicking
            // "Test" on the Custom card while it isn't the primary provider
            // (the normal case - the UI only sends pendingModel when the
            // Primary AI Provider dropdown already matches the button being
            // clicked) always produced "Set the AI Model Name for your
            // custom provider" even with a real model saved for it. Falls
            // back to Custom's own dedicated model setting first - the same
            // one LlmClientFactory.build() and the quota check now use -
            // and only truly has no default left if that was never set
            // either, matching this method's original intent.
            String customModel = SettingsDAO.getCopilotCustomModel();
            return customModel == null ? "" : customModel;
        }
        if ("GROQ".equalsIgnoreCase(provider)) {
            return "openai/gpt-oss-120b";
        }
        // Fault: this was its own separate literal ("gemini-2.5-flash"),
        // independent of GeminiClient's actual default - the same drift that
        // let "gemini-2.0-flash" go stale there once already (confirmed dead,
        // HTTP 404). Testing a model that isn't the one the real Copilot path
        // uses defeats the point of a connection test, so this now reuses the
        // one place that default is allowed to be defined.
        return GeminiClient.DEFAULT_MODEL;
    }

    private int getSessionUserId(HttpSession session) {
        String[] names = {"userId", "user_id"};
        for (String name : names) {
            try {
                Object value = session.getAttribute(name);
                if (value != null) {
                    int parsed = Integer.parseInt(String.valueOf(value));
                    if (parsed > 0) {
                        return parsed;
                    }
                }
            } catch (Exception ignored) {}
        }
        return 0;
    }
}
