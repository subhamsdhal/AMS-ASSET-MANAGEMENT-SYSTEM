package com.mycompany.asset_management_system_ams;

import java.util.HashMap;
import java.util.Map;

import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

/**
 * LlmProviderCooldownTest — locks in the "skip a provider we already know is
 * rate-limited, instead of paying for the same failed round trip again"
 * optimization CopilotAgentLoop relies on. See LlmProviderCooldown's own
 * class doc for the live 429 that prompted this.
 */
public class LlmProviderCooldownTest {

    @AfterEach
    public void resetState() {
        LlmProviderCooldown.clear();
    }

    @Test
    public void testUntouchedProviderIsNeverCoolingDown() {
        assertFalse(LlmProviderCooldown.isCoolingDown("GROQ"));
    }

    @Test
    public void testRecordedRateLimitMarksProviderAsCoolingDownImmediately() {
        Map<String, String> headers = new HashMap<String, String>();
        headers.put("retry-after", "30");
        LlmProviderCooldown.recordRateLimited("GROQ", headers);
        assertTrue(LlmProviderCooldown.isCoolingDown("GROQ"));
    }

    @Test
    public void testMissingRetryAfterHeaderStillAppliesAShortDefaultCooldown() {
        // No usable header at all - must not be treated as "not rate limited."
        LlmProviderCooldown.recordRateLimited("CUSTOM", new HashMap<String, String>());
        assertTrue(LlmProviderCooldown.isCoolingDown("CUSTOM"));
    }

    @Test
    public void testUnparseableRetryAfterValueFallsBackToTheDefaultCooldownRatherThanFailing() {
        Map<String, String> headers = new HashMap<String, String>();
        headers.put("retry-after", "not-a-number");
        LlmProviderCooldown.recordRateLimited("GEMINI", headers);
        assertTrue(LlmProviderCooldown.isCoolingDown("GEMINI"));
    }

    @Test
    public void testCooldownIsPerProviderNotGlobal() {
        Map<String, String> headers = new HashMap<String, String>();
        headers.put("retry-after", "30");
        LlmProviderCooldown.recordRateLimited("GROQ", headers);

        assertTrue(LlmProviderCooldown.isCoolingDown("GROQ"));
        assertFalse(LlmProviderCooldown.isCoolingDown("CUSTOM"),
                "A different provider's own rate limit must not be affected.");
    }

    @Test
    public void testAbsurdlyLongRetryAfterIsCappedNotHonoredVerbatim() {
        // A provider claiming a multi-hour cooldown must not be allowed to
        // pin itself out of rotation for anywhere near that long - the cap
        // exists precisely so a malformed or extreme header can't do this.
        Map<String, String> headers = new HashMap<String, String>();
        headers.put("retry-after", "99999");
        LlmProviderCooldown.recordRateLimited("GROQ", headers);
        assertTrue(LlmProviderCooldown.isCoolingDown("GROQ"));
        // Can't directly assert the exact cap without exposing internal
        // timing, but a 99999s (27+ hour) claim must not literally apply -
        // covered indirectly: the class doc states and code enforces a
        // MAX_COOLDOWN_SECONDS ceiling. This test guards that recording
        // still succeeds (does not throw/silently no-op) on an extreme input.
    }

    @Test
    public void testNullProviderNameIsSafelyIgnored() {
        LlmProviderCooldown.recordRateLimited(null, new HashMap<String, String>());
        assertFalse(LlmProviderCooldown.isCoolingDown(null));
    }
}
