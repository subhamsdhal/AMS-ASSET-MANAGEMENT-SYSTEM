package com.mycompany.asset_management_system_ams;

import java.util.List;

import org.json.JSONArray;
import org.json.JSONObject;
import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

/**
 * LlmImageSupportTest — locks in that an attached image reaches each
 * provider's wire format correctly, verified against the actual payload-
 * building code (buildPayload(), package-private for exactly this reason -
 * same pattern GeminiClient's own tests already use), with no live network
 * call and no real API key needed.
 *
 * Deliberately does NOT attempt to verify that any provider's model
 * correctly INTERPRETS an image - that would need a live call against a
 * real vision-capable model and real image content, which is neither
 * deterministic nor free to run in CI. What is verified here - that the
 * request this codebase constructs matches each provider's documented
 * multimodal format - is the part a bug could actually hide in silently
 * (a wrong field name never surfaces as a compile error, only as an
 * inscrutable 400 from a real provider, exactly as already happened twice
 * with plain text fields per GeminiClient/OpenAiCompatibleClient's own
 * comments).
 */
public class LlmImageSupportTest {

    private static final String SAMPLE_BASE64 = "/9j/4AAQSkZJRgABAQEAYABgAAD"; // not a real image - only ever inspected as a string here
    private static final String SAMPLE_MIME = "image/jpeg";

    // ─────────────────────────────────────────────────────────────────────
    // LlmMessage
    // ─────────────────────────────────────────────────────────────────────

    @Test
    public void testUserWithImageSetsImageFields() {
        LlmMessage msg = LlmMessage.userWithImage("what is this?", SAMPLE_BASE64, SAMPLE_MIME);
        assertTrue(msg.hasImage());
        assertEquals(SAMPLE_BASE64, msg.imageBase64);
        assertEquals(SAMPLE_MIME, msg.imageMimeType);
        assertEquals("what is this?", msg.text);
    }

    @Test
    public void testUserWithImageFallsBackToPlainTextWhenImageMissing() {
        assertFalse(LlmMessage.userWithImage("hello", null, null).hasImage());
        assertFalse(LlmMessage.userWithImage("hello", "", SAMPLE_MIME).hasImage());
        assertFalse(LlmMessage.userWithImage("hello", SAMPLE_BASE64, "").hasImage());
    }

    @Test
    public void testPlainUserMessageNeverHasAnImage() {
        assertFalse(LlmMessage.user("hello").hasImage());
    }

    // ─────────────────────────────────────────────────────────────────────
    // GeminiClient — inlineData part
    // ─────────────────────────────────────────────────────────────────────

    @Test
    public void testGeminiPayloadIncludesInlineDataPartForImageMessage() {
        GeminiClient client = new GeminiClient("fake-key", "gemini-3.6-flash");
        LlmRequest request = new LlmRequest()
                .add(LlmMessage.userWithImage("what asset is this?", SAMPLE_BASE64, SAMPLE_MIME));

        JSONObject payload = client.buildPayload(request);
        JSONArray contents = payload.getJSONArray("contents");
        JSONObject userContent = contents.getJSONObject(0);
        assertEquals("user", userContent.getString("role"));

        JSONArray parts = userContent.getJSONArray("parts");
        boolean sawText = false;
        boolean sawImage = false;
        for (int i = 0; i < parts.length(); i++) {
            JSONObject part = parts.getJSONObject(i);
            if (part.has("text")) {
                sawText = true;
            }
            if (part.has("inlineData")) {
                sawImage = true;
                JSONObject inlineData = part.getJSONObject("inlineData");
                assertEquals(SAMPLE_MIME, inlineData.getString("mimeType"));
                assertEquals(SAMPLE_BASE64, inlineData.getString("data"));
            }
        }
        assertTrue(sawText, "Expected the text part to still be present alongside the image.");
        assertTrue(sawImage, "Expected an inlineData part for the attached image.");
    }

    @Test
    public void testGeminiPayloadHasNoInlineDataForTextOnlyMessage() {
        GeminiClient client = new GeminiClient("fake-key", "gemini-3.6-flash");
        LlmRequest request = new LlmRequest().add(LlmMessage.user("how many laptops?"));

        JSONObject payload = client.buildPayload(request);
        JSONArray parts = payload.getJSONArray("contents").getJSONObject(0).getJSONArray("parts");
        for (int i = 0; i < parts.length(); i++) {
            assertFalse(parts.getJSONObject(i).has("inlineData"));
        }
    }

    // ─────────────────────────────────────────────────────────────────────
    // ClaudeClient — image content block
    // ─────────────────────────────────────────────────────────────────────

    @Test
    public void testClaudePayloadUsesContentBlocksForImageMessage() {
        ClaudeClient client = new ClaudeClient("fake-key", "claude-sonnet-5");
        LlmRequest request = new LlmRequest()
                .add(LlmMessage.userWithImage("what asset is this?", SAMPLE_BASE64, SAMPLE_MIME));

        JSONObject payload = client.buildPayload(request);
        JSONObject userMessage = payload.getJSONArray("messages").getJSONObject(0);
        assertEquals("user", userMessage.getString("role"));

        // Content must be an ARRAY of blocks the moment an image is
        // involved, not the plain string Claude accepts for text-only turns.
        JSONArray blocks = userMessage.getJSONArray("content");
        boolean sawText = false;
        boolean sawImage = false;
        for (int i = 0; i < blocks.length(); i++) {
            JSONObject block = blocks.getJSONObject(i);
            if ("text".equals(block.optString("type"))) {
                sawText = true;
                assertEquals("what asset is this?", block.getString("text"));
            }
            if ("image".equals(block.optString("type"))) {
                sawImage = true;
                JSONObject source = block.getJSONObject("source");
                assertEquals("base64", source.getString("type"));
                assertEquals(SAMPLE_MIME, source.getString("media_type"));
                assertEquals(SAMPLE_BASE64, source.getString("data"));
            }
        }
        assertTrue(sawText);
        assertTrue(sawImage);
    }

    @Test
    public void testClaudePayloadKeepsPlainStringContentForTextOnlyMessage() {
        ClaudeClient client = new ClaudeClient("fake-key", "claude-sonnet-5");
        LlmRequest request = new LlmRequest().add(LlmMessage.user("how many laptops?"));

        JSONObject payload = client.buildPayload(request);
        JSONObject userMessage = payload.getJSONArray("messages").getJSONObject(0);
        // A text-only message must NOT be upgraded to a content-block array -
        // no behavioral change for every existing (non-image) call.
        assertEquals("how many laptops?", userMessage.get("content"));
    }

    // ─────────────────────────────────────────────────────────────────────
    // OpenAiCompatibleClient — image_url content part
    // ─────────────────────────────────────────────────────────────────────

    @Test
    public void testOpenAiCompatiblePayloadUsesImageUrlDataUriForImageMessage() {
        OpenAiCompatibleClient client = new OpenAiCompatibleClient(
                "fake-key", "gpt-4o-mini", "https://api.openai.com/v1", "OPENAI");
        LlmRequest request = new LlmRequest()
                .add(LlmMessage.userWithImage("what asset is this?", SAMPLE_BASE64, SAMPLE_MIME));

        JSONObject payload = client.buildPayload(request);
        JSONArray messages = payload.getJSONArray("messages");
        JSONObject userMessage = messages.getJSONObject(0);
        assertEquals("user", userMessage.getString("role"));

        JSONArray parts = userMessage.getJSONArray("content");
        boolean sawText = false;
        boolean sawImage = false;
        for (int i = 0; i < parts.length(); i++) {
            JSONObject part = parts.getJSONObject(i);
            if ("text".equals(part.optString("type"))) {
                sawText = true;
            }
            if ("image_url".equals(part.optString("type"))) {
                sawImage = true;
                String url = part.getJSONObject("image_url").getString("url");
                assertEquals("data:" + SAMPLE_MIME + ";base64," + SAMPLE_BASE64, url);
            }
        }
        assertTrue(sawText);
        assertTrue(sawImage);
    }

    @Test
    public void testOpenAiCompatiblePayloadKeepsPlainStringContentForTextOnlyMessage() {
        OpenAiCompatibleClient client = new OpenAiCompatibleClient(
                "fake-key", "gpt-4o-mini", "https://api.openai.com/v1", "OPENAI");
        LlmRequest request = new LlmRequest().add(LlmMessage.user("how many laptops?"));

        JSONObject payload = client.buildPayload(request);
        JSONObject userMessage = payload.getJSONArray("messages").getJSONObject(0);
        assertEquals("how many laptops?", userMessage.get("content"));
    }
}
