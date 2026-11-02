-- Migration: persistent AMS Copilot conversation history
--
-- CopilotChatMemory previously kept the rolling user/assistant transcript
-- only in the HttpSession, so a follow-up question ("what about last
-- month?") could only resolve within one unbroken session - a timeout,
-- logout, or new device lost all context. This table lets it survive across
-- sessions, keyed per user. See CopilotChatHistoryDAO/CopilotChatMemory.

CREATE TABLE IF NOT EXISTS copilot_chat_history (
    history_id INT AUTO_INCREMENT PRIMARY KEY,
    user_id INT NOT NULL,
    question TEXT NOT NULL,
    answer MEDIUMTEXT NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE CASCADE
);

CREATE INDEX idx_copilot_chat_history_user ON copilot_chat_history(user_id, history_id);
