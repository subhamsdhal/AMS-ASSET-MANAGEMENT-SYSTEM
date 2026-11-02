package com.mycompany.asset_management_system_ams;

import java.sql.Connection;
import java.sql.PreparedStatement;
import java.util.logging.Level;
import java.util.logging.Logger;

/**
 * CopilotFeedbackDAO — records per-answer thumbs-up/down feedback into
 * copilot_answer_feedback (named to avoid an unrelated, orphaned
 * copilot_feedback table already present in this database - see
 * migrations/004_copilot_feedback.sql). The one live-usage-quality signal
 * this Copilot has never had: every existing check (CopilotRegressionTest,
 * CopilotWriteIntentClassifierTest, etc.) is a fixed suite run at build
 * time, not a measurement of whether a real answer, given to a real user,
 * was actually useful.
 *
 * Best-effort by design, the same contract CopilotChatHistoryDAO already
 * follows: a failure here must never break the chat experience the feedback
 * is ABOUT. record() swallows its own exceptions and reports success/failure
 * only so the UI can show a brief "thanks" vs. a quiet no-op - never an
 * error that would make giving feedback feel like it broke something.
 */
public final class CopilotFeedbackDAO {

    private static final Logger LOGGER = Logger.getLogger(CopilotFeedbackDAO.class.getName());

    /** Guards against a pathological question/answer bloating a single row. */
    private static final int MAX_CHARS = 4000;

    private CopilotFeedbackDAO() {
    }

    public static boolean record(int userId, String question, String answer, String rating) {
        if (userId <= 0 || question == null || answer == null) {
            return false;
        }
        String cleanRating = "UP".equalsIgnoreCase(rating) ? "UP"
                : "DOWN".equalsIgnoreCase(rating) ? "DOWN" : null;
        if (cleanRating == null) {
            return false;
        }

        try (Connection con = DBConnection.getConnection();
             PreparedStatement ps = con.prepareStatement(
                     "INSERT INTO copilot_answer_feedback (user_id, question, answer, rating) VALUES (?, ?, ?, ?)")) {
            ps.setInt(1, userId);
            ps.setString(2, clip(question));
            ps.setString(3, clip(answer));
            ps.setString(4, cleanRating);
            return ps.executeUpdate() > 0;
        } catch (Exception e) {
            LOGGER.log(Level.WARNING, "CopilotFeedbackDAO.record failed for user " + userId, e);
            return false;
        }
    }

    private static String clip(String text) {
        String value = text.trim();
        return value.length() <= MAX_CHARS ? value : value.substring(0, MAX_CHARS) + "...";
    }
}
