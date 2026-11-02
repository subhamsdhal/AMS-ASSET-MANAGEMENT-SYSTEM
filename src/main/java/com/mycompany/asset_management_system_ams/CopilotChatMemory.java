package com.mycompany.asset_management_system_ams;

import java.io.Serializable;
import java.util.ArrayList;
import java.util.List;

import jakarta.servlet.http.HttpSession;

/**
 * CopilotChatMemory — the rolling user/assistant transcript for follow-ups.
 *
 * Distinct from CopilotSessionMemory, which stores the last DAO *result* so
 * "export this" can reuse it. That is not enough for real conversation: for
 * "and what about the IT department?" to resolve, the model needs the previous
 * QUESTION and ANSWER replayed into the next request. This holds those turns.
 *
 * Deliberately stores only the final text of each turn, not tool calls or raw
 * DAO payloads — replaying every tool result would grow the session object (and
 * the token bill) without end, and the model can always re-fetch data it needs.
 *
 * Two tiers, not one:
 *   1. The HttpSession list below - fast, no DB round trip, and what every
 *      turn within one unbroken session reads/writes.
 *   2. CopilotChatHistoryDAO - a durable, per-user record in
 *      copilot_chat_history. Every recorded turn is persisted here too, and
 *      recent() rehydrates the session from it (once, then continues from
 *      the session copy) whenever the session's own list is empty - a fresh
 *      login, a session that timed out, or a different device. Before this,
 *      "what about last month?" only worked if the session that asked the
 *      first half of the question was still alive; a timeout mid-conversation
 *      silently reset the Copilot to knowing nothing, with no sign to the
 *      user that context had been lost.
 *      Best-effort throughout: any DB failure here degrades to session-only
 *      behaviour (recent() returns what the session already has, even if
 *      empty; record() still updates the session) rather than surfacing an
 *      error - a follow-up question inside the current session must never
 *      break because the durability layer had a problem.
 */
public final class CopilotChatMemory {

    private static final String SESSION_KEY = "copilotChatHistory";

    /** Turns kept. Each turn is one user message plus one assistant reply. */
    private static final int MAX_TURNS = 8;

    /** Guards against one pathological reply bloating the session object. */
    private static final int MAX_CHARS_PER_TURN = 2000;

    /** Serializable so the servlet container can passivate the session. */
    public static class Turn implements Serializable {
        private static final long serialVersionUID = 1L;
        public final String question;
        public final String answer;

        public Turn(String question, String answer) {
            this.question = question;
            this.answer = answer;
        }
    }

    private CopilotChatMemory() {
    }

    /**
     * The last {@code turns} exchanges, flattened into replayable messages.
     * Falls back to CopilotChatHistoryDAO (keyed by {@code userId}) and
     * rehydrates the session from it when the session has nothing yet -
     * pass 0/negative userId to skip that fallback entirely (e.g. no
     * authenticated user available), in which case this behaves exactly as
     * it always did: session-only.
     */
    public static List<LlmMessage> recent(HttpSession session, int userId, int turns) {
        List<Turn> history = history(session);

        if (history.isEmpty() && userId > 0) {
            List<Turn> fromDb = CopilotChatHistoryDAO.recent(userId, MAX_TURNS);
            if (!fromDb.isEmpty()) {
                history = fromDb;
                trySetSessionHistory(session, history);
            }
        }

        List<LlmMessage> messages = new ArrayList<LlmMessage>();
        if (history.isEmpty()) {
            return messages;
        }

        int from = Math.max(0, history.size() - Math.max(1, turns));
        for (int i = from; i < history.size(); i++) {
            Turn turn = history.get(i);
            messages.add(LlmMessage.user(turn.question));
            messages.add(LlmMessage.assistant(turn.answer));
        }
        return messages;
    }

    public static void record(HttpSession session, int userId, String question, String answer) {
        if (question == null || answer == null) {
            return;
        }

        String clippedQuestion = clip(question);
        String clippedAnswer = clip(answer);

        if (session != null) {
            List<Turn> history = history(session);
            history.add(new Turn(clippedQuestion, clippedAnswer));

            while (history.size() > MAX_TURNS) {
                history.remove(0);
            }

            trySetSessionHistory(session, history);
        }

        if (userId > 0) {
            CopilotChatHistoryDAO.append(userId, clippedQuestion, clippedAnswer);
        }
    }

    private static void trySetSessionHistory(HttpSession session, List<Turn> history) {
        if (session == null) {
            return;
        }
        try {
            session.setAttribute(SESSION_KEY, history);
        } catch (IllegalStateException alreadyInvalidated) {
            // Session died mid-request (timeout, redeploy, logout elsewhere) -
            // the answer this turn still returns fine, it just won't be
            // remembered in-session for a follow-up that will need a fresh
            // session (which will rehydrate from the DB tier) anyway.
        }
    }

    /** Called when the user explicitly starts a new conversation. */
    public static void clear(HttpSession session) {
        if (session == null) {
            return;
        }
        try {
            session.removeAttribute(SESSION_KEY);
        } catch (IllegalStateException alreadyInvalidated) {
            // Nothing left to clear.
        }
    }

    @SuppressWarnings("unchecked")
    private static List<Turn> history(HttpSession session) {
        if (session == null) {
            return new ArrayList<Turn>();
        }
        Object stored;
        try {
            stored = session.getAttribute(SESSION_KEY);
        } catch (IllegalStateException alreadyInvalidated) {
            return new ArrayList<Turn>();
        }
        if (stored instanceof List) {
            return (List<Turn>) stored;
        }
        return new ArrayList<Turn>();
    }

    private static String clip(String text) {
        String value = text.trim();
        if (value.length() <= MAX_CHARS_PER_TURN) {
            return value;
        }
        return value.substring(0, MAX_CHARS_PER_TURN) + "...";
    }
}
