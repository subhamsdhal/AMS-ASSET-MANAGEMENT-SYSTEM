INSERT INTO `departments` (`department_name`, `department_code`) VALUES 
('Information Technology', 'IT'),
('Engineering', 'ENG'),
('Operations', 'OPS');

INSERT INTO `employees` (`employee_code`, `employee_name`, `email`, `department_id`) VALUES 
('EMP001', 'Alice Smith', 'alice@railway.gov', 1),
('EMP002', 'Bob Johnson', 'bob@railway.gov', 2),
('EMP003', 'Charlie Brown', 'charlie@railway.gov', 3);

INSERT INTO `asset_categories` (`category_name`) VALUES 
('Laptops'),
('Monitors'),
('Vehicles');

INSERT INTO `assets` (`asset_code`, `asset_name`, `category_id`, `department_id`, `asset_status`, `qr_public_token`) VALUES 
('AST001', 'ThinkPad T14', 1, 1, 'AVAILABLE', 'token123'),
('AST002', 'Dell Ultrasharp', 2, 1, 'ALLOCATED', 'token456'),
('AST003', 'Toyota Hilux', 3, 2, 'UNDER_MAINTENANCE', 'token789');

INSERT INTO `roles` (`role_name`) VALUES ('ADMIN'), ('USER');

-- Fault (Critical, fixed): force_password_change was never set here, so it
-- fell back to the column's schema default of 0 - meaning the well-known
-- default password 'admin123' (checked into this file in plaintext) worked
-- indefinitely instead of only until first login. Forced to 1 unconditionally;
-- rotate this default credential before any real deployment regardless.
INSERT INTO `users` (`username`, `password_plaintext`, `password_crypt`, `role_id`, `employee_id`, `force_password_change`) VALUES
('admin', 'admin123', '$2a$10$15IBNFB3f1MdqXGgRYHLruhDZmVLzRaZ27aAWz4GLnU/V1RQYDTjG', 1, 1, 1);

INSERT IGNORE INTO `system_settings`
(`setting_key`, `setting_value`, `setting_group`, `description`)
VALUES
('ams.organization.name', 'East Coast Railway', 'ORGANIZATION', 'Organization name'),
('ams.system.name', 'Railway Asset Management System', 'ORGANIZATION', 'System name'),
('ams.organization.location', 'Rail Sadan, Bhubaneswar, Odisha', 'ORGANIZATION', 'Office location'),
('ams.organization.unit', 'Headquarters / Rail Sadan', 'ORGANIZATION', 'Organization unit'),
('ams.organization.zone_code', 'ECoR', 'ORGANIZATION', 'Railway zone code'),
('ams.system.contact.email', '', 'ORGANIZATION', 'Contact email'),
('ams.system.support.phone', '', 'ORGANIZATION', 'Support phone'),
('ams.system.currency', 'INR', 'ORGANIZATION', 'System currency'),
('ams.system.timezone', 'Asia/Kolkata', 'ORGANIZATION', 'System timezone'),
('ams.system.description', '', 'ORGANIZATION', 'System description'),

('ams.smtp.enabled', 'false', 'SMTP', 'SMTP enabled'),
('ams.smtp.host', 'smtp.gmail.com', 'SMTP', 'SMTP host'),
('ams.smtp.port', '587', 'SMTP', 'SMTP port'),
('ams.smtp.tls', 'true', 'SMTP', 'SMTP TLS enabled'),
('ams.smtp.username', '', 'SMTP', 'SMTP username'),
('ams.smtp.password', '', 'SMTP', 'SMTP password'),
('ams.smtp.sender_name', 'IR-AMS Notification System', 'SMTP', 'SMTP sender name'),
('ams.smtp.reply_to', '', 'SMTP', 'SMTP reply-to address'),

('ams.qr.public.base_url', 'http://localhost:8080/RailwayAMS', 'QR', 'QR public base URL'),
('ams.qr.public_page', '/public_asset_view.jsp', 'QR', 'QR public page'),
('ams.qr.mobile_tunnel_url', '', 'QR', 'QR mobile tunnel URL'),
('ams.qr.enabled', 'true', 'QR', 'QR enabled'),

('ams.copilot.enabled', 'true', 'COPILOT', 'Copilot enabled'),
('ams.copilot.mode', 'RULE_BASED', 'COPILOT', 'Copilot mode'),
('ams.copilot.provider', 'LOCAL_DB', 'COPILOT', 'Active Copilot provider'),
('ams.copilot.model', '', 'COPILOT', 'Active Copilot model'),
('ams.copilot.ai_provider', 'GEMINI', 'COPILOT', 'Primary AI provider'),
('ams.copilot.ai_model', 'gemini-2.5-flash', 'COPILOT', 'Primary AI model'),
('ams.copilot.ai_endpoint', '', 'COPILOT', 'Custom AI endpoint'),
('ams.copilot.gemini_key', '', 'COPILOT', 'Encrypted Gemini API key'),
('ams.copilot.openai_key', '', 'COPILOT', 'Encrypted OpenAI API key'),
('ams.copilot.ai_api_key', '', 'COPILOT', 'Encrypted active AI API key'),
('ams.ai.enabled', 'false', 'COPILOT', 'External AI enabled'),
('ams.copilot.db_context_enabled', 'true', 'COPILOT', 'Copilot database context enabled'),
('ams.copilot.document_search_enabled', 'false', 'COPILOT', 'Copilot document search enabled'),
('ams.copilot.session_memory_enabled', 'false', 'COPILOT', 'Copilot session memory enabled'),
('ams.copilot.max_context_rows', '50', 'COPILOT', 'Copilot max context rows'),
('ams.copilot.temperature', '0.2', 'COPILOT', 'Copilot AI temperature'),
('ams.copilot.max_tokens', '800', 'COPILOT', 'Copilot max tokens'),
('ams.copilot.last_test_status', '', 'COPILOT', 'Last Copilot test status'),
('ams.copilot.last_tested_at', '', 'COPILOT', 'Last Copilot test timestamp'),

('ams.security.session.timeout', '30', 'SECURITY', 'Session timeout minutes'),
('ams.security.max.login.attempts', '5', 'SECURITY', 'Max login attempts'),
('ams.security.audit.enabled', 'true', 'SECURITY', 'Audit logging enabled'),

('ams.notify.warranty.days', '30', 'NOTIFICATIONS', 'Warranty alert days'),
('ams.notify.maintenance.overdue', 'true', 'NOTIFICATIONS', 'Maintenance overdue notifications'),
('ams.notify.new.employee.email', 'true', 'NOTIFICATIONS', 'New employee email notifications'),
('ams.notify.allocation.email', 'true', 'NOTIFICATIONS', 'Allocation email notifications'),
('ams.notify.request.email', 'true', 'NOTIFICATIONS', 'Request email notifications'),

('ams.health.enabled', 'true', 'HEALTH', 'Health score enabled'),
('ams.health.weight.age', '20', 'HEALTH', 'Health age weight'),
('ams.health.weight.maintenance', '25', 'HEALTH', 'Health maintenance weight'),
('ams.health.weight.warranty', '20', 'HEALTH', 'Health warranty weight'),
('ams.health.weight.condition', '25', 'HEALTH', 'Health condition weight'),
('ams.health.weight.verification', '10', 'HEALTH', 'Health verification weight'),

('ams.upload.max_size_mb', '10', 'UPLOAD', 'Upload max size MB'),
('ams.upload.allowed_types', 'jpg,jpeg,png,gif,pdf,doc,docx,xls,xlsx', 'UPLOAD', 'Allowed upload types'),
('ams.upload.folder_path', 'C:/RailwayAMS_Uploads', 'UPLOAD', 'Upload folder path'),

('ams.backup.location', 'C:/RailwayAMS_Backups', 'BACKUP', 'Backup location'),
('ams.backup.auto_schedule', 'NEVER', 'BACKUP', 'Backup auto schedule');
