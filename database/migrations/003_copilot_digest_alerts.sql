-- Migration: adds the on/off switch for CopilotDigestScheduler's daily
-- "aging pending items" digest email (Settings > Notifications), mirroring
-- warranty_alerts' own column/toggle exactly.

ALTER TABLE notification_settings
  ADD COLUMN copilot_digest_alerts TINYINT(1) DEFAULT 1;
