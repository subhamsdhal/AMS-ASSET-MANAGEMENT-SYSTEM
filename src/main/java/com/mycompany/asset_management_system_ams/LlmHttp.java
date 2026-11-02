package com.mycompany.asset_management_system_ams;

import java.io.BufferedReader;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.io.OutputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.nio.charset.StandardCharsets;
import java.util.LinkedHashMap;
import java.util.Map;

/** Shared JSON-over-HTTPS POST used by the LlmClient implementations. */
final class LlmHttp {

    /**
     * Agent turns can be slower than a UI click, but 60s was tuned for the
     * slowest possible provider response rather than the common case - and
     * CopilotAgentLoop tries providers one at a time on failure (see its
     * chain loop), so a rate-limited or wedged primary used to cost up to
     * 70s PER provider before failing over, up to ~3.5 minutes across a
     * 3-provider chain on a bad request. Every provider actually in use here
     * (Gemini, Claude, Groq, Cerebras/CUSTOM) responds within single-digit
     * seconds even on their slower "thinking" calls (see GeminiClient's
     * documented 3-4s floor, occasionally low double digits) - 25s leaves
     * generous headroom above that while cutting worst-case chain failover
     * from minutes to well under a minute.
     */
    private static final int CONNECT_TIMEOUT_MS = 6000;
    private static final int READ_TIMEOUT_MS = 25000;

    static class Result {
        final int status;
        final String body;
        /** Raw response headers, exactly as the provider sent them (key casing preserved). */
        final Map<String, java.util.List<String>> headers;

        Result(int status, String body, Map<String, java.util.List<String>> headers) {
            this.status = status;
            this.body = body == null ? "" : body;
            this.headers = headers == null ? new LinkedHashMap<String, java.util.List<String>>() : headers;
        }

        boolean ok() {
            return status >= 200 && status < 300;
        }
    }

    private LlmHttp() {
    }

    static Result postJson(String url, Map<String, String> headers, String jsonBody) throws Exception {
        HttpURLConnection conn = (HttpURLConnection) new URL(url).openConnection();
        try {
            conn.setRequestMethod("POST");
            conn.setRequestProperty("Content-Type", "application/json");
            conn.setDoOutput(true);
            conn.setConnectTimeout(CONNECT_TIMEOUT_MS);
            conn.setReadTimeout(READ_TIMEOUT_MS);

            Map<String, String> allHeaders = headers == null
                    ? new LinkedHashMap<String, String>() : headers;
            for (Map.Entry<String, String> header : allHeaders.entrySet()) {
                conn.setRequestProperty(header.getKey(), header.getValue());
            }

            try (OutputStream out = conn.getOutputStream()) {
                out.write(jsonBody.getBytes(StandardCharsets.UTF_8));
            }

            int status = conn.getResponseCode();

            // Captured on every response, success or failure - several
            // providers (Groq, and other OpenAI-compatible ones) report
            // remaining rate-limit budget via x-ratelimit-* headers on EVERY
            // call, including a 429. That is often the most useful moment to
            // read them (see OpenAiCompatibleClient's quota-check usage).
            Map<String, java.util.List<String>> responseHeaders = conn.getHeaderFields();

            // Read the error stream on failure - provider error bodies explain
            // WHY (bad key, unknown model, quota) and that message is far more
            // useful in the log than a bare status code.
            InputStream stream = status >= 400 ? conn.getErrorStream() : conn.getInputStream();
            if (stream == null) {
                return new Result(status, "", responseHeaders);
            }

            StringBuilder sb = new StringBuilder();
            try (BufferedReader reader = new BufferedReader(
                    new InputStreamReader(stream, StandardCharsets.UTF_8))) {
                String line;
                while ((line = reader.readLine()) != null) {
                    sb.append(line);
                }
            }
            return new Result(status, sb.toString(), responseHeaders);

        } finally {
            conn.disconnect();
        }
    }
}
