package com.mycompany.asset_management_system_ams;

import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.logging.Level;
import java.util.logging.Logger;

/**
 * CopilotChatHistoryDAO — durable storage for the AMS Copilot's per-user
 * conversation transcript, backing CopilotChatMemory's DB fallback.
 *
 * Every method is deliberately best-effort: a failure here must never break
 * answering the user's actual question, so every method catches its own
 * exceptions and degrades to "no history" (append: silently drop the write;
 * recent: return an empty list) rather than propagating - the same
 * "resilience over completeness" contract CopilotChatMemory's own
 * session-attribute methods already follow for an invalidated session.
 */
public final class CopilotChatHistoryDAO {

    private static final Logger LOGGER = Logger.getLogger(CopilotChatHistoryDAO.class.getName());

    /**
     * Rows kept per user, well beyond CopilotChatMemory.MAX_TURNS (8) - this
     * table is the durable record a fresh session rehydrates from, not the
     * window replayed into every request, so it can afford some slack
     * without either growing unbounded or needing a separate cleanup job.
     */
    private static final int MAX_ROWS_PER_USER = 50;

    private CopilotChatHistoryDAO() {
    }

    /** Appends one turn, then trims this user's history back down to MAX_ROWS_PER_USER. */
    public static void append(int userId, String question, String answer) {
        if (userId <= 0 || question == null || answer == null) {
            return;
        }
        try (Connection con = DBConnection.getConnection()) {
            try (PreparedStatement ps = con.prepareStatement(
                    "INSERT INTO copilot_chat_history (user_id, question, answer) VALUES (?, ?, ?)")) {
                ps.setInt(1, userId);
                ps.setString(2, question);
                ps.setString(3, answer);
                ps.executeUpdate();
            }
            trim(con, userId);
        } catch (Exception e) {
            // Best-effort by design - a follow-up question in THIS session
            // still works from CopilotChatMemory's in-memory list either
            // way; only a fresh session's rehydration would miss this turn.
            LOGGER.log(Level.WARNING, "CopilotChatHistoryDAO.append failed for user " + userId, e);
        }
    }

    /** The last {@code limit} turns for this user, oldest first (ready to replay in order). */
    public static List<CopilotChatMemory.Turn> recent(int userId, int limit) {
        if (userId <= 0 || limit <= 0) {
            return Collections.emptyList();
        }
        String sql = "SELECT question, answer FROM copilot_chat_history "
                + "WHERE user_id = ? ORDER BY history_id DESC LIMIT ?";
        List<CopilotChatMemory.Turn> turns = new ArrayList<CopilotChatMemory.Turn>();
        try (Connection con = DBConnection.getConnection();
             PreparedStatement ps = con.prepareStatement(sql)) {
            ps.setInt(1, userId);
            ps.setInt(2, limit);
            try (ResultSet rs = ps.executeQuery()) {
                while (rs.next()) {
                    turns.add(new CopilotChatMemory.Turn(rs.getString("question"), rs.getString("answer")));
                }
            }
        } catch (Exception e) {
            LOGGER.log(Level.WARNING, "CopilotChatHistoryDAO.recent failed for user " + userId, e);
            return Collections.emptyList();
        }
        Collections.reverse(turns); // DESC for LIMIT's sake, chronological for replay's sake
        return turns;
    }

    /** One stored turn, with the timestamp the "recent()" replay list doesn't need but a history view does. */
    public static final class HistoryEntry {
        public final int historyId;
        public final String question;
        public final String answer;
        public final java.sql.Timestamp createdAt;

        HistoryEntry(int historyId, String question, String answer, java.sql.Timestamp createdAt) {
            this.historyId = historyId;
            this.question = question;
            this.answer = answer;
            this.createdAt = createdAt;
        }
    }

    /**
     * This user's stored turns, most recent first, for a browsable history
     * view (copilot_chat_history.jsp) - unlike recent(), which returns the
     * oldest-first replay order a conversation actually reads in.
     */
    public static List<HistoryEntry> listForUser(int userId, int limit) {
        if (userId <= 0 || limit <= 0) {
            return Collections.emptyList();
        }
        String sql = "SELECT history_id, question, answer, created_at FROM copilot_chat_history "
                + "WHERE user_id = ? ORDER BY history_id DESC LIMIT ?";
        List<HistoryEntry> entries = new ArrayList<HistoryEntry>();
        try (Connection con = DBConnection.getConnection();
             PreparedStatement ps = con.prepareStatement(sql)) {
            ps.setInt(1, userId);
            ps.setInt(2, limit);
            try (ResultSet rs = ps.executeQuery()) {
                while (rs.next()) {
                    entries.add(new HistoryEntry(rs.getInt("history_id"), rs.getString("question"),
                            rs.getString("answer"), rs.getTimestamp("created_at")));
                }
            }
        } catch (Exception e) {
            LOGGER.log(Level.WARNING, "CopilotChatHistoryDAO.listForUser failed for user " + userId, e);
            return Collections.emptyList();
        }
        return entries;
    }

    /**
     * Permanently deletes every stored turn for this user. The chat UI's own
     * "Clear Chat" button only ever cleared the visible DOM messages - the
     * durable copilot_chat_history rows survived that click untouched, which
     * is exactly right for THAT button (clearing the screen shouldn't erase
     * the record a fresh session rehydrates from) but left no way to
     * actually delete history at all. This is that real delete, deliberately
     * only reachable from the dedicated history page, not the quick "Clear
     * Chat" action, so the two stay meaningfully different rather than one
     * silently growing teeth.
     */
    public static boolean deleteAllForUser(int userId) {
        if (userId <= 0) {
            return false;
        }
        try (Connection con = DBConnection.getConnection();
             PreparedStatement ps = con.prepareStatement(
                     "DELETE FROM copilot_chat_history WHERE user_id = ?")) {
            ps.setInt(1, userId);
            ps.executeUpdate();
            return true;
        } catch (Exception e) {
            LOGGER.log(Level.WARNING, "CopilotChatHistoryDAO.deleteAllForUser failed for user " + userId, e);
            return false;
        }
    }

    /** Deletes everything but this user's most recent MAX_ROWS_PER_USER rows. */
    private static void trim(Connection con, int userId) throws Exception {
        String sql = "DELETE FROM copilot_chat_history WHERE user_id = ? AND history_id NOT IN "
                + "(SELECT history_id FROM (SELECT history_id FROM copilot_chat_history "
                + "WHERE user_id = ? ORDER BY history_id DESC LIMIT ?) AS keep_rows)";
        try (PreparedStatement ps = con.prepareStatement(sql)) {
            ps.setInt(1, userId);
            ps.setInt(2, userId);
            ps.setInt(3, MAX_ROWS_PER_USER);
            ps.executeUpdate();
        }
    }
}
