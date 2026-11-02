package com.mycompany.asset_management_system_ams;

import java.util.ArrayList;
import java.util.List;

/**
 * LlmMessage — one turn in a provider-neutral conversation.
 *
 * Deliberately NOT tied to Gemini's "contents/parts" or Claude's
 * "messages/content blocks" shape: each provider client translates this into
 * its own wire format. That is what lets the Copilot switch providers from
 * Settings without any change to CopilotAgentLoop.
 *
 * Four roles are supported:
 *   USER      - text the person typed (optionally with one attached image)
 *   ASSISTANT - model text reply
 *   TOOL_CALL  - model asked to run one or more tools (toolCalls populated)
 *   TOOL_RESULT- our answer to one tool call (toolCallId/toolName/text)
 */
public class LlmMessage {

    public enum Role { USER, ASSISTANT, TOOL_CALL, TOOL_RESULT }

    public final Role role;
    public final String text;
    public final List<LlmToolCall> toolCalls;

    /** Only set on TOOL_RESULT: which tool call this answers. */
    public final String toolCallId;
    public final String toolName;

    /**
     * Only ever set on a USER message, by userWithImage() - at most one
     * image per message, matching the chat UI's "attach one photo" control.
     * Raw base64 (no "data:image/...;base64," prefix - each provider client
     * builds its own wire format around that prefix differently, and
     * stripping it once here keeps every client's image-handling code from
     * needing to re-derive it).
     */
    public final String imageBase64;
    public final String imageMimeType;

    private LlmMessage(Role role, String text, List<LlmToolCall> toolCalls,
                       String toolCallId, String toolName) {
        this(role, text, toolCalls, toolCallId, toolName, null, null);
    }

    private LlmMessage(Role role, String text, List<LlmToolCall> toolCalls,
                       String toolCallId, String toolName, String imageBase64, String imageMimeType) {
        this.role = role;
        this.text = text == null ? "" : text;
        this.toolCalls = toolCalls == null ? new ArrayList<LlmToolCall>() : toolCalls;
        this.toolCallId = toolCallId;
        this.toolName = toolName;
        this.imageBase64 = imageBase64;
        this.imageMimeType = imageMimeType;
    }

    public static LlmMessage user(String text) {
        return new LlmMessage(Role.USER, text, null, null, null);
    }

    /**
     * A user turn with one attached image - a photo of an asset tag, QR
     * code, nameplate, or physical damage, per CopilotAgentLoop's system
     * prompt. Falls back to a plain text message when either argument is
     * blank, so a caller never needs its own "was there really an image"
     * branch before calling this.
     */
    public static LlmMessage userWithImage(String text, String imageBase64, String imageMimeType) {
        if (imageBase64 == null || imageBase64.trim().isEmpty()
                || imageMimeType == null || imageMimeType.trim().isEmpty()) {
            return user(text);
        }
        return new LlmMessage(Role.USER, text, null, null, null, imageBase64.trim(), imageMimeType.trim());
    }

    public boolean hasImage() {
        return imageBase64 != null && !imageBase64.isEmpty();
    }

    public static LlmMessage assistant(String text) {
        return new LlmMessage(Role.ASSISTANT, text, null, null, null);
    }

    public static LlmMessage toolCall(List<LlmToolCall> calls) {
        return new LlmMessage(Role.TOOL_CALL, "", calls, null, null);
    }

    public static LlmMessage toolResult(String toolCallId, String toolName, String resultJson) {
        return new LlmMessage(Role.TOOL_RESULT, resultJson, null, toolCallId, toolName);
    }

    public boolean hasToolCalls() {
        return toolCalls != null && !toolCalls.isEmpty();
    }
}
