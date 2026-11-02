package com.mycompany.asset_management_system_ams;

import java.util.concurrent.ConcurrentHashMap;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * LlmProviderCooldown — remembers, in memory only, when a provider last told
 * us it is rate-limited, so the NEXT question doesn't waste a full round trip
 * retrying a provider we already know will fail.
 *
 * Fault, found live: a provider's 429 response already carries a Retry-After
 * header (OpenAiCompatibleClient.extractRateLimitHeaders() already captures
 * it, into LlmResponse.rateLimitHeaders), but CopilotAgentLoop discarded it
 * completely after logging the failure - the very next question, seconds or
 * even the same minute later, tried that SAME still-rate-limited provider
 * again, paid for another failed network round trip, and only THEN fell over
 * to the next provider in the chain. Confirmed live: a Groq 429 mid-session
 * ("Please try again in 26.7s") was retried on the following question well
 * inside that window, adding a fully wasted request on top of the eventual
 * successful (slower fallback) one - directly the kind of "much delay" this
 * pass exists to remove.
 *
 * Deliberately in-memory and per-JVM, not persisted: this is a soft,
 * best-effort optimization, not a correctness guarantee. A restart clears it
 * (fine - the next 429, if still rate-limited, sets it again immediately),
 * and it is NEVER allowed to make a provider permanently unreachable - see
 * CopilotAgentLoop's use of isCoolingDown(), which only skips a cooling-down
 * provider when at least one other configured provider can be tried instead;
 * the last remaining candidate in the chain is always attempted regardless.
 */
final class LlmProviderCooldown {

    /** provider name -> epoch millis it becomes worth trying again. */
    private static final ConcurrentHashMap<String, Long> COOLDOWN_UNTIL = new ConcurrentHashMap<String, Long>();

    /**
     * Hard ceiling on how long a single reported cooldown can block a
     * provider, regardless of what a provider claims - protects against a
     * malformed or absurd Retry-After value (or a provider that reports a
     * much longer window than this Copilot's own per-question patience)
     * pinning a provider out of rotation far longer than intended.
     */
    private static final long MAX_COOLDOWN_SECONDS = 120;

    private LlmProviderCooldown() {
    }

    /** True if this provider reported a rate limit recently enough that its cooldown window hasn't passed yet. */
    static boolean isCoolingDown(String providerName) {
        if (providerName == null) {
            return false;
        }
        Long until = COOLDOWN_UNTIL.get(providerName);
        return until != null && System.currentTimeMillis() < until;
    }

    /**
     * Records a cooldown from a failed response's rate-limit headers (if a
     * usable Retry-After value is present) or, absent that, a short default
     * window - a 429 with no parseable header still means "don't immediately
     * retry this one," just with less precision about how long to wait.
     */
    static void recordRateLimited(String providerName, java.util.Map<String, String> rateLimitHeaders) {
        if (providerName == null) {
            return;
        }
        long seconds = parseRetryAfterSeconds(rateLimitHeaders);
        if (seconds <= 0) {
            seconds = 15; // no usable header - a conservative short default, not a guess at the real window
        }
        seconds = Math.min(seconds, MAX_COOLDOWN_SECONDS);
        COOLDOWN_UNTIL.put(providerName, System.currentTimeMillis() + (seconds * 1000L));
    }

    /** Package-private (not private) so LlmProviderCooldownTest can reset state between test cases. */
    static void clear() {
        COOLDOWN_UNTIL.clear();
    }

    // Matches a plain-integer-seconds Retry-After value, e.g. "27" - the
    // format every provider observed in this codebase (Groq) actually sends.
    // An HTTP-date form of Retry-After is technically legal per RFC 9110 but
    // not something any configured provider here has been seen to use; if
    // one ever did, this simply falls through to the 15s default above
    // rather than mis-parsing a date as a garbage second count.
    private static final Pattern INTEGER_SECONDS = Pattern.compile("^\\s*(\\d+)\\s*$");

    private static long parseRetryAfterSeconds(java.util.Map<String, String> headers) {
        if (headers == null) {
            return -1;
        }
        String raw = headers.get("retry-after");
        if (raw == null || raw.trim().isEmpty()) {
            return -1;
        }
        Matcher m = INTEGER_SECONDS.matcher(raw);
        if (m.matches()) {
            try {
                return Long.parseLong(m.group(1));
            } catch (NumberFormatException ignored) {
                return -1;
            }
        }
        return -1;
    }
}
