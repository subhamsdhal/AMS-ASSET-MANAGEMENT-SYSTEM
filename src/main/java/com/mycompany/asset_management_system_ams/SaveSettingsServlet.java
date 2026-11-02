package com.mycompany.asset_management_system_ams;

import jakarta.servlet.ServletException;
import jakarta.servlet.annotation.WebServlet;
import jakarta.servlet.http.HttpServlet;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import jakarta.servlet.http.HttpSession;

import java.io.IOException;
import java.util.logging.Logger;

/**
 * SaveSettingsServlet — Handles saving all system settings sections.
 * Supports: organization, smtp, qr, notifications, security, copilot, backup.
 * All writes go through SettingsDAO key-value store.
 */
@WebServlet(name = "SaveSettingsServlet", urlPatterns = {"/SaveSettingsServlet"})
public class SaveSettingsServlet extends HttpServlet {

    private static final Logger LOGGER = Logger.getLogger(SaveSettingsServlet.class.getName());

    @Override
    protected void doPost(HttpServletRequest request, HttpServletResponse response)
            throws ServletException, IOException {

        request.setCharacterEncoding("UTF-8");
        
        String action = request.getParameter("action");
        if ("smtp_test".equals(action)) {
            System.out.println("[SMTP_TEST] servlet reached");
            System.out.println("[SMTP_TEST] content type forced json");
            System.out.println("[SMTP_TEST] action = " + action);
            
            response.setContentType("application/json");
            response.setCharacterEncoding("UTF-8");
            
            HttpSession session = request.getSession(false);
            boolean sessionValid = (session != null && session.getAttribute("username") != null);
            System.out.println("[SMTP_TEST] session user present = " + sessionValid);
            System.out.println("[SMTP_TEST] branch = smtp_test");
            
            if (!sessionValid) {
                System.out.println("[SMTP_TEST] returning json (session expired)");
                response.getWriter().write("{\"status\": \"error\", \"error\": \"Session expired. Please login again.\"}");
                return;
            }
            String role = (String) session.getAttribute("role");
            if (!("SUPER_ADMIN".equals(role) || "ADMIN".equals(role))) {
                System.out.println("[SMTP_TEST] returning json (unauthorized)");
                response.getWriter().write("{\"status\": \"error\", \"error\": \"You are not authorized to send test email.\"}");
                return;
            }
            
            try {
                String testEmail = clean(request.getParameter("testEmail"));
                System.out.println("[SMTP_TEST] recipient = " + testEmail);
                String resultJson = EmailService.testSmtpConnection(testEmail);
                System.out.println("[SMTP_TEST] returning json");
                response.getWriter().write(resultJson);
            } catch (Exception e) {
                System.out.println("[SMTP_TEST] failed: " + e.getClass().getName() + " - " + e.getMessage());
                response.setStatus(HttpServletResponse.SC_INTERNAL_SERVER_ERROR);
                response.getWriter().write("{\"status\":\"error\",\"error\":\"SMTP test failed: " + e.getMessage() + "\"}");
            }
            return;
        }

        HttpSession session = request.getSession(false);

        if (session == null || session.getAttribute("username") == null) {
            response.sendRedirect("login.jsp");
            return;
        }

        String role = (String) session.getAttribute("role");
        if (!("SUPER_ADMIN".equals(role) || "ADMIN".equals(role))) {
            response.sendRedirect("dashboard.jsp?access=denied");
            return;
        }

        int userId = getSessionUserId(session);

        String section = clean(request.getParameter("section"));
        String redirectMsg = "saved";

        try {
            switch (section) {
                case "organization":
                    saveOrganization(request, userId);
                    break;
                case "smtp":
                    saveSmtp(request, userId);
                    redirectMsg = "smtp_saved";
                    break;
                case "qr":
                    saveQr(request, userId);
                    redirectMsg = "qr_saved";
                    break;
                case "notifications":
                    saveNotifications(request, userId);
                    redirectMsg = "notif_saved";
                    break;
                case "security":
                    saveSecurity(request, userId);
                    redirectMsg = "sec_saved";
                    break;
                case "copilot":
                    saveCopilot(request, userId);
                    redirectMsg = "copilot_saved";
                    break;
                case "health":
                    saveHealth(request, userId);
                    redirectMsg = "health_saved";
                    break;
                case "upload":
                    saveUpload(request, userId);
                    redirectMsg = "upload_saved";
                    break;
                case "backup":
                    saveBackup(request, userId);
                    redirectMsg = "backup_saved";
                    break;
                default:
                    redirectMsg = "unknown_section";
            }

            // Audit log
            AuditDAO.log(userId, "UPDATE", "system_settings", 1,
                    "Settings saved by admin. Section: " + section);

        } catch (IllegalArgumentException e) {
            redirectMsg = e.getMessage();
        } catch (Exception e) {
            LOGGER.severe("SaveSettingsServlet error: " + e.getMessage());
            System.err.println("SaveSettingsServlet error: " + e.getMessage());
            redirectMsg = "error";
        }

        response.sendRedirect("settings.jsp?msg=" + redirectMsg + "&section=" + section);
    }

    // -------------------------------------------------------
    // Section Savers
    // -------------------------------------------------------

    private void saveOrganization(HttpServletRequest req, int userId) {
        SettingsDAO.set("ams.organization.name", clean(req.getParameter("org_name")), userId);
        SettingsDAO.set("ams.system.name", clean(req.getParameter("system_name")), userId);
        SettingsDAO.set("ams.organization.location", clean(req.getParameter("office_location")), userId);
        SettingsDAO.set("ams.organization.unit", clean(req.getParameter("org_unit")), userId);
        SettingsDAO.set("ams.organization.zone_code", clean(req.getParameter("zone_code")), userId);
        SettingsDAO.set("ams.system.contact.email", clean(req.getParameter("contact_email")), userId);
        
        String supportPhone = clean(req.getParameter("support_phone"));
        if (!supportPhone.isEmpty()) {
            supportPhone = PhoneValidationUtil.validatePhone(supportPhone);
            if (supportPhone == null) {
                throw new IllegalArgumentException("invalidphone");
            }
        }
        SettingsDAO.set("ams.system.support.phone", supportPhone, userId);
        
        SettingsDAO.set("ams.system.currency", clean(req.getParameter("currency")), userId);
        SettingsDAO.set("ams.system.timezone", clean(req.getParameter("timezone")), userId);
        SettingsDAO.set("ams.system.description", clean(req.getParameter("description")), userId);
    }

    private void saveSmtp(HttpServletRequest req, int userId) {
        String enabled = "1".equals(req.getParameter("smtp_enabled")) ? "true" : "false";
        SettingsDAO.set("ams.smtp.enabled", enabled, userId);
        SettingsDAO.set("ams.smtp.host", clean(req.getParameter("smtp_host")), userId);
        SettingsDAO.set("ams.smtp.port", clean(req.getParameter("smtp_port")), userId);
        String tls = "1".equals(req.getParameter("smtp_tls")) ? "true" : "false";
        SettingsDAO.set("ams.smtp.tls", tls, userId);
        SettingsDAO.set("ams.smtp.username", clean(req.getParameter("smtp_username")), userId);
        // Only update password if provided (don't overwrite with blank). Encrypted
        // at rest, same as the Copilot API keys - SettingsDAO.getSmtpPassword()
        // decrypts it, with a transparent fallback for any password saved before
        // this change (previously stored in plaintext).
        String pass = clean(req.getParameter("smtp_password"));
        if (!pass.isEmpty()) {
            SettingsDAO.set("ams.smtp.password", CryptoUtil.encrypt(pass), userId);
        }
        SettingsDAO.set("ams.smtp.sender_name", clean(req.getParameter("smtp_sender_name")), userId);
        SettingsDAO.set("ams.smtp.reply_to", clean(req.getParameter("smtp_reply_to")), userId);
    }

    private void saveQr(HttpServletRequest req, int userId) {
        String base = clean(req.getParameter("qr_base_url"));
        if (base != null) {
            SettingsDAO.set("ams.qr.public.base_url", base, userId);
        }
        String tunnel = clean(req.getParameter("qr_mobile_tunnel_url"));
        SettingsDAO.set("ams.qr.mobile_tunnel_url", tunnel, userId);
        String enabled = "1".equals(req.getParameter("qr_enabled")) ? "true" : "false";
        SettingsDAO.set("ams.qr.enabled", enabled, userId);
    }

    private void saveNotifications(HttpServletRequest req, int userId) {
        SettingsDAO.set("ams.notify.warranty.days", clean(req.getParameter("warranty_days")), userId);
        SettingsDAO.set("ams.notify.copilot_digest.days", clean(req.getParameter("copilot_digest_days")), userId);

        // Fault: "Maintenance Overdue Alert" and "Request Status Email" here used
        // to write only ams.notify.* SettingsDAO keys that NotificationHelper never
        // reads - the toggle saved successfully but had zero effect. The real live
        // switch for these two alert types is the notification_settings table
        // (maintenance_alerts / request_alerts), the same one the standalone
        // notification_settings.jsp page edits. Write through NotificationHelper so
        // both pages control the same switch and always agree; keep the SettingsDAO
        // key in sync too since settings.jsp's own read path already displays it.
        boolean maintenanceAlert = req.getParameter("notify_maintenance") != null;
        NotificationHelper.setAlertSetting("maintenance_alerts", maintenanceAlert, userId);
        SettingsDAO.set("ams.notify.maintenance.overdue", String.valueOf(maintenanceAlert), userId);

        boolean requestEmail = req.getParameter("notify_request_email") != null;
        NotificationHelper.setAlertSetting("request_alerts", requestEmail, userId);
        SettingsDAO.set("ams.notify.request.email", String.valueOf(requestEmail), userId);

        // These two have no notification_settings column - they now actually gate
        // AddEmployeeServlet's welcome email and NotificationHelper's allocation
        // alert respectively (see those files), so the SettingsDAO key IS the real
        // switch for them.
        String newEmpEmail = req.getParameter("notify_new_employee_email") != null ? "true" : "false";
        SettingsDAO.set("ams.notify.new.employee.email", newEmpEmail, userId);
        String allocEmail = req.getParameter("notify_allocation_email") != null ? "true" : "false";
        SettingsDAO.set("ams.notify.allocation.email", allocEmail, userId);
    }

    private void saveSecurity(HttpServletRequest req, int userId) {
        SettingsDAO.set("ams.security.session.timeout", clean(req.getParameter("session_timeout")), userId);
        SettingsDAO.set("ams.security.max.login.attempts", clean(req.getParameter("max_login_attempts")), userId);
        String auditEnabled = req.getParameter("audit_enabled") != null ? "true" : "false";
        SettingsDAO.set("ams.security.audit.enabled", auditEnabled, userId);
    }

    private void saveCopilot(HttpServletRequest req, int userId) {
        String copilotEnabled = req.getParameter("copilot_enabled") != null ? "true" : "false";
        SettingsDAO.set("ams.copilot.enabled", copilotEnabled, userId);

        String mode = normalizeMode(clean(req.getParameter("copilot_mode")));
        String aiProvider = normalizeProvider(firstNonBlank(
                req.getParameter("copilot_ai_provider"),
                req.getParameter("copilot_provider")
        ));
        if ("LOCAL_DB".equals(aiProvider)) {
            aiProvider = "GEMINI";
        }

        String provider = "AI_API".equals(mode) ? aiProvider : "LOCAL_DB";

        SettingsDAO.set("ams.copilot.provider", provider, userId);
        SettingsDAO.set("ams.copilot.mode", mode, userId);
        SettingsDAO.set("ams.copilot.ai_provider", aiProvider, userId);
        SettingsDAO.set("ams.copilot.ai_endpoint", clean(req.getParameter("copilot_ai_endpoint")), userId);
        SettingsDAO.set("ams.ai.enabled", "AI_API".equals(mode) ? "true" : "false", userId);

        // Fault, found live (three times): a single shared "AI Model Name"
        // box used to hold whichever provider's model happened to be
        // Primary at save time - switching Primary AI Provider without also
        // retyping the model silently attached the WRONG provider's model
        // string to whichever became primary (most recently: Gemini's
        // "gemini-3.6-flash" saved as Groq's model, 404 on every real
        // call). Every provider now has its own dedicated, always-present
        // field in the form (see settings.jsp's provider cards), saved to
        // its own dedicated setting regardless of which one is Primary
        // right now - there is no shared box left to corrupt. Blank is a
        // valid save for any of these: LlmClientFactory.modelFor() and each
        // client's own constructor already know that provider's sensible
        // default.
        SettingsDAO.set("ams.copilot.gemini_model", clean(req.getParameter("copilot_gemini_model")), userId);
        SettingsDAO.set("ams.copilot.groq_model", clean(req.getParameter("copilot_groq_model")), userId);
        SettingsDAO.set("ams.copilot.custom_model", clean(req.getParameter("copilot_custom_model")), userId);

        String geminiKey = clean(req.getParameter("copilot_gemini_key"));
        if (isRealSecret(geminiKey)) {
            SettingsDAO.setCopilotGeminiKey(geminiKey, userId);
            if ("GEMINI".equals(aiProvider)) {
                SettingsDAO.set("ams.copilot.ai_api_key", CryptoUtil.encrypt(geminiKey), userId);
            }
        }

        String openaiKey = clean(req.getParameter("copilot_openai_key"));
        if (isRealSecret(openaiKey)) {
            SettingsDAO.setCopilotOpenAiKey(openaiKey, userId);
            if ("OPENAI".equals(aiProvider)) {
                SettingsDAO.set("ams.copilot.ai_api_key", CryptoUtil.encrypt(openaiKey), userId);
            }
        }

        // Anthropic (Claude) key for the LlmClient-based Copilot. Same
        // write-only handling as the two above: a blank field or the masked
        // placeholder leaves the stored key untouched, so re-saving the
        // Settings form never wipes a configured key.
        String claudeKey = clean(req.getParameter("copilot_claude_key"));
        if (isRealSecret(claudeKey)) {
            SettingsDAO.setCopilotClaudeKey(claudeKey, userId);
            if ("ANTHROPIC".equals(aiProvider)) {
                SettingsDAO.set("ams.copilot.ai_api_key", CryptoUtil.encrypt(claudeKey), userId);
            }
        }

        // Groq - now a selectable primary provider (previously fallback-only
        // with its key set directly in the database, no Settings UI field at
        // all). Same write-only handling as the others.
        String groqKey = clean(req.getParameter("copilot_groq_key"));
        if (isRealSecret(groqKey)) {
            SettingsDAO.setCopilotGroqKey(groqKey, userId);
            if ("GROQ".equals(aiProvider)) {
                SettingsDAO.set("ams.copilot.ai_api_key", CryptoUtil.encrypt(groqKey), userId);
            }
        }

        String fallbackEnabled = req.getParameter("copilot_fallback_enabled") != null ? "true" : "false";
        SettingsDAO.set("ams.copilot.fallback_enabled", fallbackEnabled, userId);

        // Drag-and-drop order for the "Active answer chain" chips. The
        // hidden field only ever contains provider codes joined by commas
        // (written by JS from data-code attributes we render ourselves), but
        // it's still client-submitted, so strip anything that isn't a letter
        // or comma before it's saved and later split() back apart in
        // LlmClientFactory.
        String chainOrder = clean(req.getParameter("copilot_chain_order"));
        if (!chainOrder.isEmpty()) {
            String sanitized = chainOrder.toUpperCase().replaceAll("[^A-Z,]", "");
            SettingsDAO.setCopilotChainOrder(sanitized, userId);
        }

        // Open-ended provider slot: any OpenAI-compatible endpoint the admin
        // configures (OpenRouter, Groq, DeepSeek, a local Ollama, ...). Label is
        // display-only; endpoint + key + model are what actually drive it.
        SettingsDAO.set("ams.copilot.custom_label",
                clean(req.getParameter("copilot_custom_label")), userId);

        String customKey = clean(req.getParameter("copilot_custom_key"));
        if (isRealSecret(customKey)) {
            SettingsDAO.setCopilotCustomKey(customKey, userId);
            if ("CUSTOM".equals(aiProvider)) {
                SettingsDAO.set("ams.copilot.ai_api_key", CryptoUtil.encrypt(customKey), userId);
            }
        }

        String dbContext = req.getParameter("copilot_db_context_enabled") != null ? "true" : "false";
        SettingsDAO.set("ams.copilot.db_context_enabled", dbContext, userId);

        String docSearch = req.getParameter("copilot_document_search_enabled") != null ? "true" : "false";
        SettingsDAO.set("ams.copilot.document_search_enabled", docSearch, userId);

        String sessionMem = req.getParameter("copilot_session_memory_enabled") != null ? "true" : "false";
        SettingsDAO.set("ams.copilot.session_memory_enabled", sessionMem, userId);

        SettingsDAO.set("ams.copilot.max_context_rows", clean(req.getParameter("copilot_max_context_rows")), userId);
        SettingsDAO.set("ams.copilot.temperature", cleanOrDefault(req.getParameter("copilot_temperature"), "0.2"), userId);
        SettingsDAO.set("ams.copilot.max_tokens", cleanOrDefault(req.getParameter("copilot_max_tokens"), "800"), userId);
    }
    private void saveHealth(HttpServletRequest req, int userId) {
        SettingsDAO.set("ams.health.weight.age", clean(req.getParameter("health_weight_age")), userId);
        SettingsDAO.set("ams.health.weight.maintenance", clean(req.getParameter("health_weight_maintenance")), userId);
        SettingsDAO.set("ams.health.weight.warranty", clean(req.getParameter("health_weight_warranty")), userId);
        SettingsDAO.set("ams.health.weight.condition", clean(req.getParameter("health_weight_condition")), userId);
        SettingsDAO.set("ams.health.weight.verification", clean(req.getParameter("health_weight_verification")), userId);
        String enabled = req.getParameter("health_enabled") != null ? "true" : "false";
        SettingsDAO.set("ams.health.enabled", enabled, userId);
    }

    private void saveUpload(HttpServletRequest req, int userId) {
        SettingsDAO.set("ams.upload.max_size_mb", clean(req.getParameter("upload_max_size_mb")), userId);
        SettingsDAO.set("ams.upload.allowed_types", clean(req.getParameter("upload_allowed_types")), userId);
        SettingsDAO.set("ams.upload.folder_path", clean(req.getParameter("upload_folder_path")), userId);
    }

    private void saveBackup(HttpServletRequest req, int userId) {
        SettingsDAO.set("ams.backup.location", clean(req.getParameter("backup_location")), userId);
        SettingsDAO.set("ams.backup.auto_schedule", clean(req.getParameter("backup_auto_schedule")), userId);
    }
    // -------------------------------------------------------
    // Utility
    // -------------------------------------------------------

    private String clean(String s) {
        return (s == null) ? "" : s.trim();
    }

    private String cleanOrDefault(String value, String defaultValue) {
        String cleaned = clean(value);
        return cleaned.isEmpty() ? defaultValue : cleaned;
    }

    private String firstNonBlank(String first, String second) {
        String cleanedFirst = clean(first);
        if (!cleanedFirst.isEmpty()) {
            return cleanedFirst;
        }
        return clean(second);
    }

    private int getSessionUserId(HttpSession session) {
        String[] names = {"userId", "user_id"};
        for (String name : names) {
            try {
                Object value = session.getAttribute(name);
                if (value != null) {
                    int parsed = Integer.parseInt(String.valueOf(value));
                    if (parsed > 0) {
                        return parsed;
                    }
                }
            } catch (Exception ignored) {}
        }
        return 0;
    }

    private String normalizeProvider(String provider) {
        if (provider == null) {
            return "LOCAL_DB";
        }
        String p = provider.trim().toUpperCase();
        // Fault: this accepted "GEMINI"/"OPENAI"/"ANTHROPIC"/"CUSTOM" but not
        // "GROQ" - the dropdown now offers Groq as a selectable primary
        // provider, and without this the submitted value would silently fall
        // through to the LOCAL_DB default below, reverting the Copilot to
        // keyword-only mode instead of actually saving Groq as primary.
        if ("GEMINI".equals(p) || "OPENAI".equals(p) || "ANTHROPIC".equals(p)
                || "GROQ".equals(p) || "CUSTOM".equals(p)) {
            return p;
        }
        // The Settings dropdown labels this provider "CLAUDE"; ANTHROPIC is the
        // vendor name used everywhere in the code. Accept both.
        if ("CLAUDE".equals(p)) {
            return "ANTHROPIC";
        }
        if ("OPENAI_COMPATIBLE".equals(p) || "OTHER".equals(p)) {
            return "CUSTOM";
        }
        return "LOCAL_DB";
    }

    private String normalizeMode(String mode) {
        return "AI_API".equalsIgnoreCase(mode) ? "AI_API" : "RULE_BASED";
    }

    private boolean isRealSecret(String value) {
        if (value == null) {
            return false;
        }
        String trimmed = value.trim();
        return !trimmed.isEmpty()
                && !trimmed.contains("Configured")
                && !trimmed.matches("\\u2022+")
                && !trimmed.contains("••••")
                && !trimmed.contains("****");
    }
}
