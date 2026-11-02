-- Migration: per-answer thumbs-up/down feedback on the AMS Copilot.
--
-- Every existing quality check on this Copilot (CopilotRegressionTest,
-- CopilotContextUnderstandingTest, CopilotWriteIntentClassifierTest, etc.)
-- is a fixed test suite exercised at build time. None of them capture
-- whether a REAL answer, given to a REAL user in production, was actually
-- useful. This table is that missing signal. See
-- CopilotFeedbackDAO/CopilotFeedbackServlet.
--
-- Named copilot_answer_feedback, not copilot_feedback: a table by that
-- exact name already exists live in the dev database this was built
-- against (columns conversation_id/message_id/rating INT/comment/
-- user_code), with no matching code anywhere in this repo - an orphan from
-- something else entirely, discovered while applying this migration.
-- Renamed to avoid it rather than assumed safe to repurpose or drop.

CREATE TABLE IF NOT EXISTS copilot_answer_feedback (
    feedback_id INT AUTO_INCREMENT PRIMARY KEY,
    user_id INT NOT NULL,
    question TEXT NOT NULL,
    answer MEDIUMTEXT NOT NULL,
    rating ENUM('UP','DOWN') NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE CASCADE
);

CREATE INDEX idx_copilot_answer_feedback_user ON copilot_answer_feedback(user_id, created_at);
CREATE INDEX idx_copilot_answer_feedback_rating ON copilot_answer_feedback(rating, created_at);
