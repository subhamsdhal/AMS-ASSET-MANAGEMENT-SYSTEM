<%@page contentType="text/html" pageEncoding="UTF-8"%>
<%@page import="com.mycompany.asset_management_system_ams.SettingsDAO"%>
<%@page import="com.mycompany.asset_management_system_ams.NotificationHelper"%>
<%@page import="com.mycompany.asset_management_system_ams.LlmClientFactory"%>
<%@page import="com.mycompany.asset_management_system_ams.DBConnection"%>
<%@page import="java.sql.*"%>
<%
    String username = (String) session.getAttribute("username");
    String role = (String) session.getAttribute("role");

    response.setHeader("Cache-Control", "no-cache,no-store,must-revalidate");
    response.setHeader("Pragma", "no-cache");
    response.setDateHeader("Expires", 0);

    if (username == null || role == null) {
        response.sendRedirect("login.jsp");
        return;
    }
    if (!("SUPER_ADMIN".equals(role) || "ADMIN".equals(role))) {
        response.sendRedirect("dashboard.jsp?access=denied");
        return;
    }

    SettingsDAO.ensureDefaults();

    String activeSection = request.getParameter("section");
    if ("health".equals(activeSection) || "upload".equals(activeSection) || "backup".equals(activeSection)) {
        activeSection = "operations";
    }
    if (!"organization".equals(activeSection)
            && !"smtp".equals(activeSection)
            && !"qr".equals(activeSection)
            && !"copilot".equals(activeSection)
            && !"notifications".equals(activeSection)
            && !"security".equals(activeSection)
            && !"operations".equals(activeSection)
            && !"system".equals(activeSection)) {
        activeSection = "organization";
    }

    String orgName = SettingsDAO.getOrgName();
    String systemName = SettingsDAO.getSystemName();
    String officeLocation = SettingsDAO.getOrgLocation();
    String orgUnit = SettingsDAO.getOrgUnit();
    String zoneCode = SettingsDAO.getZoneCode();
    String contactEmail = SettingsDAO.getContactEmail();
    String supportPhone = SettingsDAO.getSupportPhone();
    String currency = SettingsDAO.getCurrency();
    String timezone = SettingsDAO.get("ams.system.timezone", "Asia/Kolkata");
    String sysDescription = SettingsDAO.get("ams.system.description", "");

    boolean smtpEnabled = SettingsDAO.isSmtpEnabled();
    String smtpHost = SettingsDAO.getSmtpHost();
    int smtpPort = SettingsDAO.getSmtpPort();
    boolean smtpTls = SettingsDAO.isSmtpTls();
    String smtpUser = SettingsDAO.getSmtpUsername();
    String smtpSender = SettingsDAO.getSmtpSenderName();
    String smtpReplyTo = SettingsDAO.getSmtpReplyTo();
    boolean smtpPasswordConfigured = !SettingsDAO.getSmtpPassword().trim().isEmpty();

    boolean qrEnabled = SettingsDAO.isQrEnabled();
    String qrBaseUrl = SettingsDAO.get("ams.qr.public.base_url", "https://ams.example.org");
    String qrTunnelUrl = SettingsDAO.getMobileTunnelUrl();
    String qrTunnelProvider = SettingsDAO.getQrTunnelProvider();
    String effectiveQrUrl = SettingsDAO.getQrBaseUrl();

    boolean copilotEnabled = SettingsDAO.isCopilotEnabled();
    String copilotMode = SettingsDAO.getCopilotMode();
    String copilotProvider = SettingsDAO.getCopilotAiProvider();
    // Each provider owns its own permanently-dedicated model field now,
    // instead of one shared box whose value meant "whichever provider is
    // currently Primary" and got silently corrupted three times live by
    // switching Primary (or testing a non-primary provider) without
    // retyping it. See SettingsDAO.getCopilotGeminiModel/GroqModel/
    // CustomModel and LlmClientFactory.modelFor.
    String copilotGeminiModel = SettingsDAO.getCopilotGeminiModel();
    String copilotGroqModel = SettingsDAO.getCopilotGroqModel();
    String copilotCustomModel = SettingsDAO.getCopilotCustomModel();
    String copilotEndpoint = SettingsDAO.getCopilotAiEndpoint();
    boolean geminiKeyConfigured = !SettingsDAO.getGeminiApiKey().trim().isEmpty();
    boolean groqKeyConfigured = !SettingsDAO.getCopilotGroqKey().trim().isEmpty();
    boolean claudeKeyConfigured = !SettingsDAO.getCopilotClaudeKey().trim().isEmpty();
    boolean customKeyConfigured = !SettingsDAO.getCopilotCustomKey().trim().isEmpty();
    String copilotCustomLabel = SettingsDAO.getCopilotCustomLabel();
    boolean copilotFallbackEnabled = SettingsDAO.isCopilotFallbackEnabled();
    java.util.List<LlmClientFactory.ChainEntry> copilotChainEntries = LlmClientFactory.describeChainEntries();
    StringBuilder copilotChainOrderSb = new StringBuilder();
    for (LlmClientFactory.ChainEntry copilotChainEntry : copilotChainEntries) {
        if (copilotChainOrderSb.length() > 0) {
            copilotChainOrderSb.append(",");
        }
        copilotChainOrderSb.append(copilotChainEntry.code);
    }
    String copilotChainOrderValue = copilotChainOrderSb.toString();
    boolean dbContextEnabled = SettingsDAO.isDbContextEnabled();
    boolean documentSearchEnabled = SettingsDAO.isDocumentSearchEnabled();
    boolean sessionMemoryEnabled = SettingsDAO.isSessionMemoryEnabled();
    int maxContextRows = SettingsDAO.getMaxContextRows();
    double copilotTemperature = SettingsDAO.getCopilotTemperature();
    int copilotMaxTokens = SettingsDAO.getCopilotMaxTokens();
    // Fault: a "Last Test" box here used to show whatever was in
    // ams.copilot.last_test_status at PAGE LOAD time - server-rendered once,
    // never updated again. The AJAX Test button (testAiConnection() below)
    // correctly writes a fresh result to that same DB value on every click,
    // but nothing told this already-rendered page to re-read it, so the box
    // sat showing a stale, possibly different provider's result until the
    // next full reload - confirmed live: testing Groq showed the inline
    // result correctly, while this box kept showing an earlier Gemini test.
    // The inline per-card result (testAiConnection() -> showTestResult() in
    // the script below) already covers this correctly and live; removed
    // this redundant, stale duplicate rather than wire it up to also stay
    // in sync.

    int sessionTimeout = SettingsDAO.getSessionTimeout();
    int maxLoginAttempts = SettingsDAO.getMaxLoginAttempts();
    boolean auditEnabled = SettingsDAO.getBoolean("ams.security.audit.enabled", true);

    int warrantyDays = SettingsDAO.getWarrantyAlertDays();
    int copilotDigestDays = SettingsDAO.getCopilotDigestAgingDays();
    // Maintenance + request alerts are gated by notification_settings, not the
    // SettingsDAO key - read the same live value NotificationHelper actually
    // checks, so this tab and the standalone notification_settings.jsp page never
    // disagree about whether the alert is really on.
    boolean notifyMaintenance = NotificationHelper.isAlertSettingEnabled("maintenance_alerts", true);
    boolean notifyNewEmpEmail = SettingsDAO.getBoolean("ams.notify.new.employee.email", true);
    boolean notifyAllocEmail = SettingsDAO.getBoolean("ams.notify.allocation.email", true);
    boolean notifyRequestEmail = NotificationHelper.isAlertSettingEnabled("request_alerts", true);

    boolean healthEnabled = SettingsDAO.isHealthScoreEnabled();
    int healthAge = SettingsDAO.getHealthWeightAge();
    int healthMaintenance = SettingsDAO.getHealthWeightMaintenance();
    int healthWarranty = SettingsDAO.getHealthWeightWarranty();
    int healthCondition = SettingsDAO.getHealthWeightCondition();
    int healthVerification = SettingsDAO.getHealthWeightVerification();

    int uploadMaxSizeMb = SettingsDAO.getUploadMaxSizeMb();
    String uploadAllowedTypes = SettingsDAO.getUploadAllowedTypes();
    String uploadFolderPath = SettingsDAO.getUploadFolderPath();
    String backupLocation = SettingsDAO.getBackupLocation();
    String backupAutoSchedule = SettingsDAO.getBackupAutoSchedule();

    int totalAssets = 0;
    int totalEmployees = 0;
    int totalUsers = 0;
    int totalAudit = 0;
    try (Connection con = DBConnection.getConnection()) {
        if (con != null) {
            try (Statement st = con.createStatement();
                 ResultSet rs = st.executeQuery(
                         "SELECT (SELECT COUNT(*) FROM assets) AS a, "
                                 + "(SELECT COUNT(*) FROM employees WHERE is_deleted=0 OR is_deleted IS NULL) AS e, "
                                 + "(SELECT COUNT(*) FROM users) AS u, "
                                 + "(SELECT COUNT(*) FROM audit_logs) AS al")) {
                if (rs.next()) {
                    totalAssets = rs.getInt("a");
                    totalEmployees = rs.getInt("e");
                    totalUsers = rs.getInt("u");
                    totalAudit = rs.getInt("al");
                }
            }
        }
    } catch (Exception ex) {
        ex.printStackTrace();
    }

    String msg = request.getParameter("msg");
    String msgText = "";
    String msgClass = "";
    if ("saved".equals(msg)
            || "smtp_saved".equals(msg)
            || "qr_saved".equals(msg)
            || "notif_saved".equals(msg)
            || "sec_saved".equals(msg)
            || "copilot_saved".equals(msg)
            || "health_saved".equals(msg)
            || "upload_saved".equals(msg)
            || "backup_saved".equals(msg)) {
        msgText = "Settings saved successfully.";
        msgClass = "success";
    } else if ("smtp_test_ok".equals(msg)) {
        msgText = "Test email sent successfully.";
        msgClass = "success";
    } else if ("smtp_test_fail".equals(msg)) {
        msgText = "Test email failed. Verify SMTP account, app password, and network access.";
        msgClass = "error";
    } else if ("error".equals(msg)) {
        msgText = "Unable to save settings. Please review the values and try again.";
        msgClass = "error";
    } else if ("unknown_section".equals(msg)) {
        msgText = "Unknown settings section.";
        msgClass = "error";
    }
%>
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width,initial-scale=1">
    <title>System Settings - IR-AMS | <%= h(orgName) %></title>
    <meta name="description" content="Railway AMS administrative settings for organization, SMTP, QR, Copilot, security and system controls.">
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.0/css/all.min.css">
    <link rel="stylesheet" href="css/ir-ams-railway-ui.css?v=settings-formal-v1">
    <link rel="stylesheet" href="css/settings.css?v=settings-hero-custom-image-v2">


    <style>
        /* AMS Copilot + Settings ONLY: force the shared sidebar brand to the true visual center. */
        body.railway-ui.ams-copilot-settings-page aside.sidebar.railway-sidebar .logo-box,
        body.railway-ui.ams-copilot-settings-page aside.railway-sidebar .logo-box,
        body.railway-ui.ams-copilot-settings-page .railway-sidebar .logo-box,
        body.railway-ui.ams-copilot-settings-page .railway-sidebar .railway-brand {
            position: relative !important;
            left: 50% !important;
            right: auto !important;
            width: var(--ir-sidebar-width) !important;
            max-width: var(--ir-sidebar-width) !important;
            margin: 0 0 12px 0 !important;
            padding: 6px 0 13px 0 !important;
            transform: translateX(-50%) !important;
            display: flex !important;
            flex-direction: column !important;
            align-items: center !important;
            justify-content: center !important;
            text-align: center !important;
            box-sizing: border-box !important;
            overflow: visible !important;
        }

        body.railway-ui.ams-copilot-settings-page aside.sidebar.railway-sidebar .railway-sidebar-brand-center,
        body.railway-ui.ams-copilot-settings-page aside.railway-sidebar .railway-sidebar-brand-center,
        body.railway-ui.ams-copilot-settings-page .railway-sidebar .railway-sidebar-brand-center {
            position: relative !important;
            left: auto !important;
            right: auto !important;
            width: 100% !important;
            max-width: 100% !important;
            margin: 0 auto !important;
            padding: 6px 10px 14px 10px !important;
            transform: translateX(30px) !important;
            display: flex !important;
            flex-direction: column !important;
            align-items: center !important;
            justify-content: center !important;
            text-align: center !important;
            box-sizing: border-box !important;
            overflow: visible !important;
        }

        body.railway-ui.ams-copilot-settings-page aside.sidebar.railway-sidebar .railway-sidebar-brand-center > img,
        body.railway-ui.ams-copilot-settings-page aside.railway-sidebar .railway-sidebar-brand-center > img,
        body.railway-ui.ams-copilot-settings-page .railway-sidebar .railway-sidebar-brand-center > img,
        body.railway-ui.ams-copilot-settings-page aside.sidebar.railway-sidebar .railway-sidebar-brand-center .logo-text,
        body.railway-ui.ams-copilot-settings-page aside.railway-sidebar .railway-sidebar-brand-center .logo-text,
        body.railway-ui.ams-copilot-settings-page .railway-sidebar .railway-sidebar-brand-center .logo-text {
            position: relative !important;
            left: auto !important;
            right: auto !important;
            margin-left: auto !important;
            margin-right: auto !important;
            transform: none !important;
            text-align: center !important;
            box-sizing: border-box !important;
        }

        body.railway-ui.ams-copilot-settings-page aside.sidebar.railway-sidebar .railway-sidebar-brand-center .logo-text,
        body.railway-ui.ams-copilot-settings-page aside.railway-sidebar .railway-sidebar-brand-center .logo-text,
        body.railway-ui.ams-copilot-settings-page .railway-sidebar .railway-sidebar-brand-center .logo-text {
            width: 100% !important;
            max-width: 225px !important;
            padding: 0 !important;
        }

        body.railway-ui.ams-copilot-settings-page aside.sidebar.railway-sidebar .railway-title-hindi,
        body.railway-ui.ams-copilot-settings-page aside.sidebar.railway-sidebar .railway-title-english,
        body.railway-ui.ams-copilot-settings-page aside.sidebar.railway-sidebar .railway-zone-name,
        body.railway-ui.ams-copilot-settings-page aside.sidebar.railway-sidebar .railway-office-block,
        body.railway-ui.ams-copilot-settings-page aside.railway-sidebar .railway-title-hindi,
        body.railway-ui.ams-copilot-settings-page aside.railway-sidebar .railway-title-english,
        body.railway-ui.ams-copilot-settings-page aside.railway-sidebar .railway-zone-name,
        body.railway-ui.ams-copilot-settings-page aside.railway-sidebar .railway-office-block,
        body.railway-ui.ams-copilot-settings-page .railway-sidebar .railway-title-hindi,
        body.railway-ui.ams-copilot-settings-page .railway-sidebar .railway-title-english,
        body.railway-ui.ams-copilot-settings-page .railway-sidebar .railway-zone-name,
        body.railway-ui.ams-copilot-settings-page .railway-sidebar .railway-office-block {
            display: block !important;
            width: 100% !important;
            max-width: 225px !important;
            margin-left: auto !important;
            margin-right: auto !important;
            padding-left: 0 !important;
            padding-right: 0 !important;
            text-align: center !important;
            transform: none !important;
            left: auto !important;
            right: auto !important;
            white-space: normal !important;
            box-sizing: border-box !important;
        }
    </style>

    <style>
        /* AMS Copilot + Settings ONLY: final right-shift for sidebar brand visual centering. */
        body.railway-ui.ams-copilot-settings-page aside.sidebar.railway-sidebar .logo-box.railway-brand {
            overflow: visible !important;
        }

        body.railway-ui.ams-copilot-settings-page aside.sidebar.railway-sidebar .railway-sidebar-brand-center,
        body.railway-ui.ams-copilot-settings-page aside.railway-sidebar .railway-sidebar-brand-center,
        body.railway-ui.ams-copilot-settings-page .railway-sidebar .railway-sidebar-brand-center {
            position: relative !important;
            left: 26px !important;
            right: auto !important;
            transform: none !important;
            width: calc(100% - 26px) !important;
            max-width: calc(100% - 26px) !important;
            margin-left: 0 !important;
            margin-right: 0 !important;
            padding-left: 0 !important;
            padding-right: 0 !important;
            text-align: center !important;
            box-sizing: border-box !important;
        }

        body.railway-ui.ams-copilot-settings-page aside.sidebar.railway-sidebar .railway-sidebar-brand-center img,
        body.railway-ui.ams-copilot-settings-page aside.sidebar.railway-sidebar .railway-sidebar-brand-center .logo-text,
        body.railway-ui.ams-copilot-settings-page aside.sidebar.railway-sidebar .railway-title-hindi,
        body.railway-ui.ams-copilot-settings-page aside.sidebar.railway-sidebar .railway-title-english,
        body.railway-ui.ams-copilot-settings-page aside.sidebar.railway-sidebar .railway-zone-name,
        body.railway-ui.ams-copilot-settings-page aside.sidebar.railway-sidebar .railway-office-block {
            margin-left: auto !important;
            margin-right: auto !important;
            text-align: center !important;
        }
    </style>
</head>
<body class="railway-ui ams-copilot-settings-page">
<div class="app">
    <%@ include file="sidebar.jsp" %>
    <main class="main">
        <%@ include file="topbar.jsp" %>
        <div class="main-scroll-content">
            <div class="settings-wrap">
                <div class="ir-breadcrumb">
                    <a href="dashboard.jsp"><i class="fa fa-home"></i> Dashboard</a>
                    <span class="sep">&gt;</span>
                    <span>System Settings</span>
                </div>

                <section class="settings-hero">
                    <div class="settings-hero-copy">
                        <span class="settings-eyebrow">
                            <i class="fa-solid fa-gear"></i>
                            Settings Module · East Coast Railway
                        </span>

                        <h1>System Settings Console</h1>

                        <p>
                            Manage administrative controls, organization identity, QR access, email delivery,
                            AI Copilot configuration, security rules and system operations from one secure settings module.
                        </p>

                        <div class="settings-hero-pills">
                            <div class="settings-hero-pill"><i class="fa-solid fa-building"></i> Organization</div>
                            <div class="settings-hero-pill"><i class="fa-solid fa-envelope"></i> Email / SMTP</div>
                            <div class="settings-hero-pill"><i class="fa-solid fa-qrcode"></i> QR & Mobile</div>
                            <div class="settings-hero-pill"><i class="fa-solid fa-robot"></i> AI Copilot</div>
                        </div>
                    </div>
                </section>

                <div class="settings-status">
                    <div class="status-tile">
                        <div class="status-icon blue"><i class="fa-solid fa-cubes"></i></div>
                        <div>
                            <span>Total Assets</span>
                            <strong><%= totalAssets %></strong>
                            <em>live records</em>
                        </div>
                    </div>
                    <div class="status-tile">
                        <div class="status-icon green"><i class="fa-solid fa-users"></i></div>
                        <div>
                            <span>Employees</span>
                            <strong><%= totalEmployees %></strong>
                            <em>registered users</em>
                        </div>
                    </div>
                    <div class="status-tile">
                        <div class="status-icon purple"><i class="fa-solid fa-user-shield"></i></div>
                        <div>
                            <span>User Accounts</span>
                            <strong><%= totalUsers %></strong>
                            <em>system access</em>
                        </div>
                    </div>
                    <div class="status-tile">
                        <div class="status-icon orange"><i class="fa-solid fa-scroll"></i></div>
                        <div>
                            <span>Audit Logs</span>
                            <strong><%= totalAudit %></strong>
                            <em>tracked actions</em>
                        </div>
                    </div>
                </div>

                <% if (!msgText.isEmpty()) { %>
                <div class="alert-msg <%= msgClass %>" id="topAlert">
                    <i class="fa fa-<%= "success".equals(msgClass) ? "check-circle" : "exclamation-circle" %>"></i>
                    <span><%= h(msgText) %></span>
                    <button type="button" class="close-alert" onclick="document.getElementById('topAlert').remove()" aria-label="Close alert">&times;</button>
                </div>
                <% } %>

                <nav class="settings-tabs" aria-label="Settings sections">
                    <button type="button" class="stab <%= "organization".equals(activeSection) ? "active" : "" %>" data-tab="organization"><i class="fa fa-building"></i> Organization</button>
                    <button type="button" class="stab <%= "smtp".equals(activeSection) ? "active" : "" %>" data-tab="smtp"><i class="fa fa-envelope"></i> Email / SMTP</button>
                    <button type="button" class="stab <%= "qr".equals(activeSection) ? "active" : "" %>" data-tab="qr"><i class="fa fa-qrcode"></i> QR & Mobile</button>
                    <button type="button" class="stab <%= "copilot".equals(activeSection) ? "active" : "" %>" data-tab="copilot"><i class="fa fa-robot"></i> AI Copilot</button>
                    <button type="button" class="stab <%= "notifications".equals(activeSection) ? "active" : "" %>" data-tab="notifications"><i class="fa fa-bell"></i> Notifications</button>
                    <button type="button" class="stab <%= "security".equals(activeSection) ? "active" : "" %>" data-tab="security"><i class="fa fa-shield-alt"></i> Security</button>
                    <button type="button" class="stab <%= "operations".equals(activeSection) ? "active" : "" %>" data-tab="operations"><i class="fa fa-sliders"></i> Operations</button>
                    <button type="button" class="stab <%= "system".equals(activeSection) ? "active" : "" %>" data-tab="system"><i class="fa fa-server"></i> System Info</button>
                </nav>

                <section class="stab-panel <%= "organization".equals(activeSection) ? "active" : "" %>" id="panel-organization">
                    <form method="post" action="SaveSettingsServlet">
                        <input type="hidden" name="section" value="organization">
                        <div class="settings-card">
                            <div class="settings-card-header">
                                <div>
                                    <h2><i class="fa fa-building"></i> Organization Profile</h2>
                                    <p class="subtext">Official identity and display values used across the application.</p>
                                </div>
                            </div>
                            <div class="form-row">
                                <div class="form-group">
                                    <label>Organization Name</label>
                                    <input type="text" name="org_name" value="<%= h(orgName) %>" placeholder="East Coast Railway" required>
                                </div>
                                <div class="form-group">
                                    <label>System Name</label>
                                    <input type="text" name="system_name" value="<%= h(systemName) %>" placeholder="Railway Asset Management System">
                                </div>
                            </div>
                            <div class="form-row">
                                <div class="form-group">
                                    <label>Organizational Unit</label>
                                    <input type="text" name="org_unit" value="<%= h(orgUnit) %>" placeholder="Headquarters / Rail Sadan">
                                </div>
                                <div class="form-group">
                                    <label>Railway Zone Code</label>
                                    <input type="text" name="zone_code" value="<%= h(zoneCode) %>" placeholder="ECoR">
                                </div>
                            </div>
                            <div class="form-row single">
                                <div class="form-group">
                                    <label>Office Location / Address</label>
                                    <input type="text" name="office_location" value="<%= h(officeLocation) %>" placeholder="Rail Sadan, Samant Vihar, Bhubaneswar, Odisha">
                                </div>
                            </div>
                            <div class="form-row">
                                <div class="form-group">
                                    <label>Contact Email</label>
                                    <input type="email" name="contact_email" value="<%= h(contactEmail) %>" placeholder="admin@ecor.railnet.gov.in">
                                </div>
                                <div class="form-group">
                                    <label>Support Phone</label>
                                    <input type="text" name="support_phone" value="<%= h(supportPhone) %>" placeholder="+91-0674-0000000">
                                </div>
                            </div>
                            <div class="form-row triple">
                                <div class="form-group">
                                    <label>Currency</label>
                                    <select name="currency">
                                        <option value="INR" <%= "INR".equals(currency) ? "selected" : "" %>>INR - Indian Rupee</option>
                                        <option value="USD" <%= "USD".equals(currency) ? "selected" : "" %>>USD - US Dollar</option>
                                    </select>
                                </div>
                                <div class="form-group">
                                    <label>Timezone</label>
                                    <select name="timezone">
                                        <option value="Asia/Kolkata" <%= "Asia/Kolkata".equals(timezone) ? "selected" : "" %>>Asia/Kolkata (IST, +05:30)</option>
                                        <option value="UTC" <%= "UTC".equals(timezone) ? "selected" : "" %>>UTC</option>
                                        <option value="Asia/Singapore" <%= "Asia/Singapore".equals(timezone) ? "selected" : "" %>>Asia/Singapore</option>
                                    </select>
                                </div>
                                <div class="form-group">
                                    <label>Currency Code</label>
                                    <input type="text" value="<%= h(currency) %>" class="readonly-field" readonly>
                                </div>
                            </div>
                            <div class="form-row single">
                                <div class="form-group">
                                    <label>System Description</label>
                                    <textarea name="description"><%= h(sysDescription) %></textarea>
                                </div>
                            </div>
                            <div class="form-actions">
                                <button type="submit" class="btn-save"><i class="fa fa-save"></i> Save Organization Settings</button>
                            </div>
                        </div>
                    </form>
                </section>

                <section class="stab-panel <%= "smtp".equals(activeSection) ? "active" : "" %>" id="panel-smtp">
                    <form method="post" action="SaveSettingsServlet" id="smtpForm">
                        <input type="hidden" name="section" value="smtp">
                        <div class="settings-card">
                            <div class="settings-card-header">
                                <div>
                                    <h2><i class="fa fa-envelope"></i> Email / SMTP Configuration</h2>
                                    <p class="subtext">Configure official notification delivery. Passwords are never displayed.</p>
                                </div>
                                <span class="pill <%= smtpEnabled ? "ok" : "muted" %>"><i class="fa fa-circle"></i> <%= smtpEnabled ? "Enabled" : "Disabled" %></span>
                            </div>
                            <div class="toggle-row">
                                <div>
                                    <label>Enable Email Notifications</label>
                                    <div class="toggle-desc">Send emails for employee creation, asset alerts and workflow updates.</div>
                                </div>
                                <label class="toggle-switch">
                                    <input type="checkbox" name="smtp_enabled" value="1" id="smtpEnabledToggle" <%= smtpEnabled ? "checked" : "" %>>
                                    <span class="toggle-slider"></span>
                                </label>
                            </div>
                            <div id="smtpFields">
                                <div class="section-divider">Account Details</div>
                                <div class="form-row">
                                    <div class="form-group">
                                        <label>SMTP Username / Gmail Address</label>
                                        <input type="email" name="smtp_username" id="smtpUser" value="<%= h(smtpUser) %>" placeholder="yourname@gmail.com">
                                    </div>
                                    <div class="form-group">
                                        <label>SMTP Password / Gmail App Password</label>
                                        <div class="pw-field">
                                            <input type="password" name="smtp_password" id="smtpPass" placeholder="<%= smtpPasswordConfigured ? "Configured - leave blank to keep existing password" : "Enter app password" %>" autocomplete="new-password">
                                            <button type="button" class="pw-toggle" onclick="togglePwd('smtpPass', this)" aria-label="Show or hide SMTP password"><i class="fa fa-eye"></i></button>
                                        </div>
                                    </div>
                                </div>
                                <div class="form-row">
                                    <div class="form-group">
                                        <label>Sender Display Name</label>
                                        <input type="text" name="smtp_sender_name" value="<%= h(smtpSender) %>" placeholder="IR-AMS Notification System">
                                    </div>
                                    <div class="form-group">
                                        <label>Reply-To Address</label>
                                        <input type="email" name="smtp_reply_to" value="<%= h(smtpReplyTo) %>" placeholder="noreply@ecor.in">
                                    </div>
                                </div>
                                <div class="section-divider">Server Details</div>
                                <div class="form-row triple">
                                    <div class="form-group">
                                        <label>SMTP Host</label>
                                        <input type="text" name="smtp_host" value="<%= h(smtpHost) %>" placeholder="smtp.gmail.com">
                                    </div>
                                    <div class="form-group">
                                        <label>SMTP Port</label>
                                        <input type="number" name="smtp_port" value="<%= smtpPort %>" min="1" max="65535" placeholder="587">
                                    </div>
                                    <div class="form-group">
                                        <label>TLS Encryption</label>
                                        <label class="toggle-switch">
                                            <input type="checkbox" name="smtp_tls" value="1" <%= smtpTls ? "checked" : "" %>>
                                            <span class="toggle-slider"></span>
                                        </label>
                                    </div>
                                </div>
                                <div class="notice warning">
                                    Use a Gmail App Password when Gmail is selected. Do not enter the normal Gmail account password.
                                </div>
                                <div class="notice">
                                    <strong>Send Test Email</strong>
                                    <div class="inline-test">
                                        <input type="email" id="testEmailAddr" placeholder="test@example.gov.in">
                                        <button type="button" class="btn-secondary" onclick="sendTestEmail(this)"><i class="fa fa-paper-plane"></i> Send Test Email</button>
                                        <span id="testEmailResult" class="hint"></span>
                                    </div>
                                </div>
                            </div>
                            <div class="form-actions">
                                <button type="submit" class="btn-save"><i class="fa fa-save"></i> Save SMTP Settings</button>
                            </div>
                        </div>
                    </form>
                </section>

                <section class="stab-panel <%= "qr".equals(activeSection) ? "active" : "" %>" id="panel-qr">
                    <div class="settings-card">
                        <div class="settings-card-header">
                            <div>
                                <h2><i class="fa fa-qrcode"></i> QR Code & Mobile Access</h2>
                                <p class="subtext">Manage QR base URL, public scanning and optional mobile tunnel access.</p>
                            </div>
                            <span class="pill <%= qrEnabled ? "ok" : "muted" %>"><i class="fa fa-qrcode"></i> <%= qrEnabled ? "QR Enabled" : "QR Disabled" %></span>
                        </div>
                        <div class="tunnel-box">
                            <div class="tunnel-head">
                                <div>
                                    <div class="tunnel-title">Mobile Tunnel for QR Scanning</div>
                                    <div class="tunnel-text">Start or save a tunnel URL when mobile phones must scan assets from a machine running on localhost.</div>
                                </div>
                                <span class="tunnel-status <%= !qrTunnelUrl.isEmpty() ? "running" : "stopped" %>" id="tunnelStatusBadge">
                                    <i class="fa fa-circle"></i> <%= !qrTunnelUrl.isEmpty() ? "Running" : "Stopped" %>
                                </span>
                            </div>
                            
                            <div class="form-row" style="margin-top: 15px; margin-bottom: 0;">
                                <div class="form-group" style="margin-bottom: 5px;">
                                    <label>Tunnel Provider</label>
                                    <select id="tunnelProvider" class="form-control" onchange="onProviderChange()">
                                        <option value="ngrok" <%= "ngrok".equals(qrTunnelProvider) ? "selected" : "" %>>Ngrok (Preferred)</option>
                                        <option value="cloudflare" <%= "cloudflare".equals(qrTunnelProvider) ? "selected" : "" %>>Cloudflare Tunnel</option>
                                        <option value="custom" <%= "custom".equals(qrTunnelProvider) ? "selected" : "" %>>Custom URL</option>
                                    </select>
                                </div>
                            </div>
                            
                            <div class="tunnel-url-display" id="tunnelUrlDisplay">
                                <% if (!qrTunnelUrl.isEmpty()) { %>
                                    <a href="<%= h(qrTunnelUrl) %>" target="_blank"><%= h(qrTunnelUrl) %></a>
                                <% } else { %>
                                    No tunnel active. QR uses: <%= h(effectiveQrUrl) %>
                                <% } %>
                            </div>
                            
                            <div class="form-actions" id="tunnelActionButtons" style="border-top:0;margin-top:0;padding-top:0; <%= "custom".equals(qrTunnelProvider) ? "display:none;" : "" %>">
                                <button type="button" class="btn-secondary" onclick="startTunnel()"><i class="fa fa-play"></i> Start Tunnel</button>
                                <button type="button" class="btn-secondary" onclick="stopTunnel()"><i class="fa fa-stop"></i> Stop Tunnel</button>
                                <button type="button" class="btn-secondary" onclick="checkTunnelStatus()"><i class="fa fa-rotate"></i> Refresh Status</button>
                            </div>
                            <div id="tunnelMsg" class="hint" style="color:#dbeafe;margin-top:10px;"></div>
                        </div>
                        <div class="notice">
                            <strong>Manual Tunnel URL Override</strong>
                            <div class="inline-test">
                                <input type="text" id="manualTunnelUrl" value="<%= h(qrTunnelUrl) %>" placeholder="<%= "ngrok".equals(qrTunnelProvider) ? "https://your-ngrok-url.ngrok-free.app" : ("cloudflare".equals(qrTunnelProvider) ? "https://example.trycloudflare.com" : "https://your-public-domain.com") %>">
                                <button type="button" class="btn-save" onclick="setManualUrl()"><i class="fa fa-save"></i> Save URL</button>
                                <button type="button" class="btn-danger" onclick="clearTunnelUrl()"><i class="fa fa-xmark"></i> Clear URL</button>
                            </div>
                        </div>
                        <form method="post" action="SaveSettingsServlet">
                            <input type="hidden" name="section" value="qr">
                            <div class="section-divider">QR Configuration</div>
                            <div class="form-row">
                                <div class="form-group">
                                    <label>Localhost Base URL</label>
                                    <input type="text" name="qr_base_url" value="<%= h(qrBaseUrl) %>" placeholder="https://ams.example.org">
                                </div>
                                <div class="form-group">
                                    <label>Currently Effective URL</label>
                                    <input type="text" value="<%= h(effectiveQrUrl) %>" readonly class="readonly-field" id="effectiveUrlDisplay">
                                </div>
                            </div>
                            <div class="toggle-row">
                                <div>
                                    <label>Enable QR Code System</label>
                                    <div class="toggle-desc">Allow QR tag generation and public asset scanning.</div>
                                </div>
                                <label class="toggle-switch">
                                    <input type="checkbox" name="qr_enabled" value="1" <%= qrEnabled ? "checked" : "" %>>
                                    <span class="toggle-slider"></span>
                                </label>
                            </div>
                            <div class="form-actions">
                                <button type="submit" class="btn-save"><i class="fa fa-save"></i> Save QR Settings</button>
                            </div>
                        </form>
                    </div>
                </section>

                <section class="stab-panel <%= "copilot".equals(activeSection) ? "active" : "" %>" id="panel-copilot">
                    <form action="SaveSettingsServlet" method="post">
                        <input type="hidden" name="section" value="copilot">
                        <div class="settings-card copilot-card">
                            <div class="settings-card-header">
                                <div>
                                    <h2><i class="fa fa-robot"></i> AI Copilot Settings</h2>
                                    <p class="subtext">Configure Copilot availability and provider credentials.</p>
                                </div>
                                <span class="pill <%= copilotEnabled ? "ok" : "muted" %>"><i class="fa fa-comments"></i> <%= copilotEnabled ? "Enabled" : "Disabled" %></span>
                            </div>
                            <div class="toggle-row">
                                <div>
                                    <label>Enable AMS Copilot</label>
                                    <div class="toggle-desc">Lets authorized users access the AI Copilot page and actions.</div>
                                </div>
                                <label class="toggle-switch">
                                    <input type="checkbox" name="copilot_enabled" <%= copilotEnabled ? "checked" : "" %>>
                                    <span class="toggle-slider"></span>
                                </label>
                            </div>

                            <div class="copilot-section-head">
                                <i class="fa fa-microchip"></i>
                                <h3>Engine &amp; Provider</h3>
                            </div>
                            <div class="form-row">
                                <div class="form-group">
                                    <label>Copilot Mode</label>
                                    <select name="copilot_mode" id="copilotModeSelect">
                                        <option value="RULE_BASED" <%= "RULE_BASED".equals(copilotMode) ? "selected" : "" %>>Rule-Based Only - No external API</option>
                                        <option value="AI_API" <%= "AI_API".equals(copilotMode) ? "selected" : "" %>>AI API - Gemini, Groq or Custom</option>
                                    </select>
                                </div>
                                <div class="form-group">
                                    <label>Primary AI Provider</label>
                                    <select name="copilot_ai_provider" id="copilotProviderSelect">
                                        <option value="GEMINI" <%= "GEMINI".equals(copilotProvider) ? "selected" : "" %>>Google Gemini</option>
                                        <option value="GROQ" <%= "GROQ".equals(copilotProvider) ? "selected" : "" %>>Groq</option>
                                        <option value="CUSTOM" <%= "CUSTOM".equals(copilotProvider) ? "selected" : "" %>>Custom / Other (OpenAI-compatible)</option>
                                    </select>
                                </div>
                            </div>

                            <div id="aiApiFields">
                                <div class="notice">
                                    <i class="fa fa-circle-info"></i>
                                    API keys are encrypted and never displayed. Leave a field blank to keep the saved key.
                                </div>

                                <div class="copilot-section-head">
                                    <i class="fa fa-key"></i>
                                    <h3>Provider Credentials</h3>
                                </div>

                                <div class="copilot-provider-grid">
                                    <div class="copilot-provider-card">
                                        <div class="copilot-provider-card-head">
                                            <span class="copilot-provider-icon gemini"><i class="fa fa-star"></i></span>
                                            <div>
                                                <div class="copilot-provider-name">Google Gemini</div>
                                                <div class="copilot-provider-sub"><%= copilotGeminiModel.isEmpty() ? "gemini-3.6-flash (default)" : h(copilotGeminiModel) %></div>
                                            </div>
                                            <span class="copilot-status-pill <%= geminiKeyConfigured ? "set" : "unset" %>"><%= geminiKeyConfigured ? "Configured" : "Not set" %></span>
                                        </div>
                                        <div class="form-row single" style="margin:0 0 12px;">
                                            <div class="form-group">
                                                <label>Model</label>
                                                <input type="text" name="copilot_gemini_model" id="geminiModelInput" value="<%= h(copilotGeminiModel) %>" placeholder="gemini-3.6-flash (default)">
                                            </div>
                                        </div>
                                        <div class="copilot-provider-actions">
                                            <div class="pw-field">
                                                <input type="password" name="copilot_gemini_key" id="geminiKeyInput" placeholder="<%= geminiKeyConfigured ? "Configured - leave blank to keep existing key" : "Paste Gemini API key" %>" autocomplete="new-password">
                                                <button type="button" class="pw-toggle" onclick="togglePwd('geminiKeyInput', this)" aria-label="Show or hide Gemini key"><i class="fa fa-eye"></i></button>
                                            </div>
                                            <button type="button" class="btn-secondary" onclick="testAiConnection(this, 'GEMINI')"><i class="fa fa-plug"></i> Test</button>
                                            <button type="button" class="btn-secondary" onclick="checkAiQuota(this, 'GEMINI')"><i class="fa fa-gauge"></i> Usage</button>
                                        </div>
                                    </div>

                                    <div class="copilot-provider-card">
                                        <div class="copilot-provider-card-head">
                                            <span class="copilot-provider-icon groq"><i class="fa fa-bolt"></i></span>
                                            <div>
                                                <div class="copilot-provider-name">Groq</div>
                                                <div class="copilot-provider-sub"><%= copilotGroqModel.isEmpty() ? "openai/gpt-oss-120b (default)" : h(copilotGroqModel) %></div>
                                            </div>
                                            <span class="copilot-status-pill <%= groqKeyConfigured ? "set" : "unset" %>"><%= groqKeyConfigured ? "Configured" : "Not set" %></span>
                                        </div>
                                        <div class="form-row single" style="margin:0 0 12px;">
                                            <div class="form-group">
                                                <label>Model</label>
                                                <input type="text" name="copilot_groq_model" id="groqModelInput" value="<%= h(copilotGroqModel) %>" placeholder="openai/gpt-oss-120b (default)">
                                            </div>
                                        </div>
                                        <div class="copilot-provider-actions">
                                            <div class="pw-field">
                                                <input type="password" name="copilot_groq_key" id="groqKeyInput" placeholder="<%= groqKeyConfigured ? "Configured - leave blank to keep existing key" : "Paste Groq API key" %>" autocomplete="new-password">
                                                <button type="button" class="pw-toggle" onclick="togglePwd('groqKeyInput', this)" aria-label="Show or hide Groq key"><i class="fa fa-eye"></i></button>
                                            </div>
                                            <button type="button" class="btn-secondary" onclick="testAiConnection(this, 'GROQ')"><i class="fa fa-plug"></i> Test</button>
                                            <button type="button" class="btn-secondary" onclick="checkAiQuota(this, 'GROQ')"><i class="fa fa-gauge"></i> Usage</button>
                                        </div>
                                    </div>
                                </div>

                                <div class="copilot-section-head">
                                    <i class="fa fa-shield-halved"></i>
                                    <h3>Fallback &amp; Reliability</h3>
                                </div>
                                <div class="toggle-row">
                                    <div>
                                        <label>Automatic Provider Fallback</label>
                                        <div class="toggle-desc">
                                            On failure, retry on the next configured provider before
                                            falling back to local keyword matching.
                                        </div>
                                    </div>
                                    <label class="toggle-switch"><input type="checkbox" name="copilot_fallback_enabled" <%= copilotFallbackEnabled ? "checked" : "" %>><span class="toggle-slider"></span></label>
                                </div>

                                <div class="notice <%= copilotChainEntries.isEmpty() ? "warning" : "" %>" style="margin-bottom:0;">
                                    <strong>Active answer chain</strong>
                                    <% if (copilotChainEntries.isEmpty()) { %>
                                        <div class="hint" style="margin-top:6px;">
                                            No AI provider is configured yet &mdash; the Copilot is answering from
                                            local keyword matching only. Add a key above and save to activate AI mode.
                                        </div>
                                    <% } else { %>
                                        <div class="copilot-chain-flow" id="chainFlow">
                                            <% for (LlmClientFactory.ChainEntry chainEntry : copilotChainEntries) { %>
                                                <span class="copilot-chain-chip" draggable="true" data-code="<%= chainEntry.code %>">
                                                    <i class="fa fa-grip-vertical chain-drag-handle" aria-hidden="true"></i>
                                                    <i class="fa fa-check"></i> <%= h(chainEntry.display) %>
                                                </span>
                                            <% } %>
                                            <span class="copilot-chain-chip fallback-node"><i class="fa fa-layer-group"></i> Local keyword engine</span>
                                        </div>
                                        <input type="hidden" name="copilot_chain_order" id="chainOrderInput" value="<%= h(copilotChainOrderValue) %>">
                                        <div class="hint" style="margin-top:8px;">Drag a chip to reorder &mdash; tried left to right, and the leftmost chip becomes your Primary AI Provider above. Click <strong>Save Copilot Settings</strong> below to keep the change.</div>
                                    <% } %>
                                </div>

                                <div class="copilot-section-head">
                                    <i class="fa fa-puzzle-piece"></i>
                                    <h3>Add Another AI Provider</h3>
                                    <span class="copilot-section-sub">Any OpenAI-compatible endpoint</span>
                                </div>
                                <div class="notice">
                                    <i class="fa fa-circle-info"></i>
                                    Fill in the endpoint, key and model below &mdash; Custom / Other has its own dedicated model and endpoint, so it works whether or not it's your Primary AI Provider. Works with OpenRouter, Groq, DeepSeek, Together, or a local Ollama / LM Studio runtime &mdash; any service that supports tool calling on the <code>/chat/completions</code> format.
                                </div>
                                <div class="copilot-provider-grid single">
                                    <div class="copilot-provider-card">
                                        <div class="copilot-provider-card-head">
                                            <span class="copilot-provider-icon custom"><i class="fa fa-plug"></i></span>
                                            <div>
                                                <div class="copilot-provider-name">Custom / Other</div>
                                                <div class="copilot-provider-sub"><%= copilotCustomLabel.isEmpty() ? "e.g. OpenRouter, Groq, Local Ollama" : h(copilotCustomLabel) %></div>
                                            </div>
                                            <span class="copilot-status-pill <%= customKeyConfigured ? "set" : "unset" %>"><%= customKeyConfigured ? "Configured" : "Not set" %></span>
                                        </div>
                                        <div class="form-row" style="margin:0 0 12px;">
                                            <div class="form-group">
                                                <label>Provider Name (label only)</label>
                                                <input type="text" name="copilot_custom_label" id="customLabelInput" value="<%= h(copilotCustomLabel) %>" placeholder="e.g. OpenRouter, Groq, Local Ollama">
                                            </div>
                                            <div class="form-group">
                                                <label>Model</label>
                                                <input type="text" name="copilot_custom_model" id="customModelInput" value="<%= h(copilotCustomModel) %>" placeholder="Required - model id from your provider">
                                            </div>
                                        </div>
                                        <div class="form-row single" style="margin:0 0 12px;">
                                            <div class="form-group">
                                                <label>API Endpoint</label>
                                                <input type="text" name="copilot_ai_endpoint" id="aiEndpointInput" value="<%= h(copilotEndpoint) %>" placeholder="e.g. https://api.groq.com/openai/v1">
                                            </div>
                                        </div>
                                        <div class="copilot-provider-actions">
                                            <div class="pw-field">
                                                <input type="password" name="copilot_custom_key" id="customKeyInput" placeholder="<%= customKeyConfigured ? "Configured - leave blank to keep existing key" : "Paste API key (leave blank for local runtimes)" %>" autocomplete="new-password">
                                                <button type="button" class="pw-toggle" onclick="togglePwd('customKeyInput', this)" aria-label="Show or hide custom provider key"><i class="fa fa-eye"></i></button>
                                            </div>
                                            <button type="button" class="btn-secondary" onclick="testAiConnection(this, 'CUSTOM')"><i class="fa fa-plug"></i> Test</button>
                                            <button type="button" class="btn-secondary" onclick="checkAiQuota(this, 'CUSTOM')"><i class="fa fa-gauge"></i> Usage</button>
                                        </div>
                                    </div>
                                </div>

                                <div class="copilot-section-head">
                                    <i class="fa fa-database"></i>
                                    <h3>Data Controls &amp; Limits</h3>
                                </div>
                                <div class="toggle-row">
                                    <div>
                                        <label>Database Context</label>
                                        <div class="toggle-desc">Allow Copilot to answer using AMS database records.</div>
                                    </div>
                                    <label class="toggle-switch"><input type="checkbox" name="copilot_db_context_enabled" <%= dbContextEnabled ? "checked" : "" %>><span class="toggle-slider"></span></label>
                                </div>
                                <div class="toggle-row">
                                    <div>
                                        <label>Document Search</label>
                                        <div class="toggle-desc">Allow Copilot to include uploaded document text where supported.</div>
                                    </div>
                                    <label class="toggle-switch"><input type="checkbox" name="copilot_document_search_enabled" <%= documentSearchEnabled ? "checked" : "" %>><span class="toggle-slider"></span></label>
                                </div>
                                <div class="toggle-row">
                                    <div>
                                        <label>Session Memory</label>
                                        <div class="toggle-desc">Allow short conversation context during a Copilot session.</div>
                                    </div>
                                    <label class="toggle-switch"><input type="checkbox" name="copilot_session_memory_enabled" <%= sessionMemoryEnabled ? "checked" : "" %>><span class="toggle-slider"></span></label>
                                </div>
                                <div class="form-row triple" style="margin-top:16px;">
                                    <div class="form-group">
                                        <label>Max Context Rows</label>
                                        <input type="number" name="copilot_max_context_rows" value="<%= maxContextRows %>" min="1" max="500">
                                    </div>
                                    <div class="form-group">
                                        <label>Temperature</label>
                                        <input type="number" name="copilot_temperature" value="<%= copilotTemperature %>" min="0" max="2" step="0.1">
                                    </div>
                                    <div class="form-group">
                                        <label>Max Tokens</label>
                                        <input type="number" name="copilot_max_tokens" value="<%= copilotMaxTokens %>" min="128" max="4096">
                                    </div>
                                </div>
                            </div>
                            <div class="form-actions">
                                <button type="submit" class="btn-save"><i class="fa fa-save"></i> Save Copilot Settings</button>
                                <a href="ams_copilot.jsp" class="btn-secondary"><i class="fa fa-comments"></i> Open Copilot</a>
                            </div>
                        </div>
                    </form>
                </section>

                <section class="stab-panel <%= "notifications".equals(activeSection) ? "active" : "" %>" id="panel-notifications">
                    <form method="post" action="SaveSettingsServlet">
                        <input type="hidden" name="section" value="notifications">
                        <div class="settings-card">
                            <div class="settings-card-header">
                                <div>
                                    <h2><i class="fa fa-bell"></i> Notification Rules</h2>
                                    <p class="subtext">Configure operational alerts and official email notifications.</p>
                                </div>
                            </div>
                            <div class="form-row">
                                <div class="form-group">
                                    <label>Warranty Expiry Alert - Days Before</label>
                                    <input type="number" name="warranty_days" value="<%= warrantyDays %>" min="1" max="365" placeholder="30">
                                </div>
                                <div class="form-group">
                                    <label>Copilot Digest - Aging Threshold (Days)</label>
                                    <input type="number" name="copilot_digest_days" value="<%= copilotDigestDays %>" min="1" max="90" placeholder="3">
                                </div>
                            </div>
                            <div class="section-divider">Alert Types</div>
                            <div class="toggle-row">
                                <div><label>Maintenance Overdue Alert</label><div class="toggle-desc">Alert administrators when maintenance is overdue.</div></div>
                                <label class="toggle-switch"><input type="checkbox" name="notify_maintenance" value="1" <%= notifyMaintenance ? "checked" : "" %>><span class="toggle-slider"></span></label>
                            </div>
                            <div class="toggle-row">
                                <div><label>New Employee Welcome Email</label><div class="toggle-desc">Send login and onboarding information to new employees.</div></div>
                                <label class="toggle-switch"><input type="checkbox" name="notify_new_employee_email" value="1" <%= notifyNewEmpEmail ? "checked" : "" %>><span class="toggle-slider"></span></label>
                            </div>
                            <div class="toggle-row">
                                <div><label>Asset Allocation Email</label><div class="toggle-desc">Notify employees when an asset is allocated.</div></div>
                                <label class="toggle-switch"><input type="checkbox" name="notify_allocation_email" value="1" <%= notifyAllocEmail ? "checked" : "" %>><span class="toggle-slider"></span></label>
                            </div>
                            <div class="toggle-row">
                                <div><label>Request Status Email</label><div class="toggle-desc">Notify users when an asset request status changes.</div></div>
                                <label class="toggle-switch"><input type="checkbox" name="notify_request_email" value="1" <%= notifyRequestEmail ? "checked" : "" %>><span class="toggle-slider"></span></label>
                            </div>
                            <div class="form-actions">
                                <button type="submit" class="btn-save"><i class="fa fa-save"></i> Save Notification Settings</button>
                            </div>
                        </div>
                    </form>
                </section>

                <section class="stab-panel <%= "security".equals(activeSection) ? "active" : "" %>" id="panel-security">
                    <form method="post" action="SaveSettingsServlet">
                        <input type="hidden" name="section" value="security">
                        <div class="settings-card">
                            <div class="settings-card-header">
                                <div>
                                    <h2><i class="fa fa-shield-alt"></i> Security Controls</h2>
                                    <p class="subtext">Manage session policy, login protection and audit logging.</p>
                                </div>
                            </div>
                            <div class="form-row">
                                <div class="form-group">
                                    <label>Session Timeout (minutes)</label>
                                    <input type="number" name="session_timeout" value="<%= sessionTimeout %>" min="5" max="1440" placeholder="30">
                                </div>
                                <div class="form-group">
                                    <label>Max Login Attempts Before Lockout</label>
                                    <input type="number" name="max_login_attempts" value="<%= maxLoginAttempts %>" min="1" max="20" placeholder="5">
                                </div>
                            </div>
                            <div class="toggle-row">
                                <div><label>Enable Audit Logging</label><div class="toggle-desc">Record user actions in the audit log for administrative review.</div></div>
                                <label class="toggle-switch"><input type="checkbox" name="audit_enabled" value="1" <%= auditEnabled ? "checked" : "" %>><span class="toggle-slider"></span></label>
                            </div>
                            <div class="form-actions">
                                <button type="submit" class="btn-save"><i class="fa fa-save"></i> Save Security Settings</button>
                            </div>
                        </div>
                    </form>
                </section>

                <section class="stab-panel <%= "operations".equals(activeSection) ? "active" : "" %>" id="panel-operations">
                    <div class="settings-card">
                        <div class="settings-card-header">
                            <div>
                                <h2><i class="fa fa-sliders"></i> Operational Controls</h2>
                                <p class="subtext">Tune health score, file upload and backup settings used by operational modules.</p>
                            </div>
                        </div>
                        <form method="post" action="SaveSettingsServlet">
                            <input type="hidden" name="section" value="health">
                            <div class="section-divider">Asset Health Score</div>
                            <div class="toggle-row">
                                <div><label>Enable Health Score</label><div class="toggle-desc">Use weighted asset condition, maintenance and verification signals.</div></div>
                                <label class="toggle-switch"><input type="checkbox" name="health_enabled" value="1" <%= healthEnabled ? "checked" : "" %>><span class="toggle-slider"></span></label>
                            </div>
                            <div class="form-row triple" style="margin-top:16px;">
                                <div class="form-group"><label>Age Weight</label><input type="number" name="health_weight_age" value="<%= healthAge %>" min="0" max="100"></div>
                                <div class="form-group"><label>Maintenance Weight</label><input type="number" name="health_weight_maintenance" value="<%= healthMaintenance %>" min="0" max="100"></div>
                                <div class="form-group"><label>Warranty Weight</label><input type="number" name="health_weight_warranty" value="<%= healthWarranty %>" min="0" max="100"></div>
                            </div>
                            <div class="form-row">
                                <div class="form-group"><label>Condition Weight</label><input type="number" name="health_weight_condition" value="<%= healthCondition %>" min="0" max="100"></div>
                                <div class="form-group"><label>Verification Weight</label><input type="number" name="health_weight_verification" value="<%= healthVerification %>" min="0" max="100"></div>
                            </div>
                            <div class="form-actions">
                                <button type="submit" class="btn-save"><i class="fa fa-save"></i> Save Health Settings</button>
                            </div>
                        </form>
                    </div>
                    <div class="settings-card">
                        <form method="post" action="SaveSettingsServlet">
                            <input type="hidden" name="section" value="upload">
                            <div class="settings-card-header">
                                <div>
                                    <h3><i class="fa fa-upload"></i> Upload Settings</h3>
                                    <p class="subtext">Control accepted file types and storage location for uploaded documents.</p>
                                </div>
                            </div>
                            <div class="form-row">
                                <div class="form-group">
                                    <label>Maximum Upload Size (MB)</label>
                                    <input type="number" name="upload_max_size_mb" value="<%= uploadMaxSizeMb %>" min="1" max="200">
                                </div>
                                <div class="form-group">
                                    <label>Allowed File Types</label>
                                    <input type="text" name="upload_allowed_types" value="<%= h(uploadAllowedTypes) %>" placeholder="jpg,jpeg,png,pdf,doc,docx,xls,xlsx">
                                </div>
                            </div>
                            <div class="form-row single">
                                <div class="form-group">
                                    <label>Upload Folder Path</label>
                                    <input type="text" name="upload_folder_path" value="<%= h(uploadFolderPath) %>" placeholder="/var/ams/uploads">
                                </div>
                            </div>
                            <div class="form-actions">
                                <button type="submit" class="btn-save"><i class="fa fa-save"></i> Save Upload Settings</button>
                            </div>
                        </form>
                    </div>
                    <div class="settings-card">
                        <form method="post" action="SaveSettingsServlet">
                            <input type="hidden" name="section" value="backup">
                            <div class="settings-card-header">
                                <div>
                                    <h3><i class="fa fa-database"></i> Backup Settings</h3>
                                    <p class="subtext">Set default database backup storage and scheduling preference.</p>
                                </div>
                            </div>
                            <div class="form-row">
                                <div class="form-group">
                                    <label>Backup Location</label>
                                    <input type="text" name="backup_location" value="<%= h(backupLocation) %>" placeholder="/var/ams/backups">
                                </div>
                                <div class="form-group">
                                    <label>Auto Schedule</label>
                                    <select name="backup_auto_schedule">
                                        <option value="NEVER" <%= "NEVER".equals(backupAutoSchedule) ? "selected" : "" %>>Never</option>
                                        <option value="DAILY" <%= "DAILY".equals(backupAutoSchedule) ? "selected" : "" %>>Daily</option>
                                        <option value="WEEKLY" <%= "WEEKLY".equals(backupAutoSchedule) ? "selected" : "" %>>Weekly</option>
                                        <option value="MONTHLY" <%= "MONTHLY".equals(backupAutoSchedule) ? "selected" : "" %>>Monthly</option>
                                    </select>
                                </div>
                            </div>
                            <div class="form-actions">
                                <button type="submit" class="btn-save"><i class="fa fa-save"></i> Save Backup Settings</button>
                                <a href="backup_restore.jsp" class="btn-secondary"><i class="fa fa-database"></i> Open Backup / Restore</a>
                            </div>
                        </form>
                    </div>
                </section>

                <section class="stab-panel <%= "system".equals(activeSection) ? "active" : "" %>" id="panel-system">
                    <div class="settings-card">
                        <div class="settings-card-header">
                            <div>
                                <h2><i class="fa fa-server"></i> System Information</h2>
                                <p class="subtext">Read-only administrative summary of active configuration values.</p>
                            </div>
                        </div>
                        <table class="system-table">
                            <%
                                String displayProvider = "AI_API".equals(copilotMode) ? copilotProvider : "LOCAL_DB";
                                String[][] info = {
                                        {"Organization", orgName},
                                        {"System Name", systemName},
                                        {"Zone Code", zoneCode},
                                        {"Office Location", officeLocation},
                                        {"Contact Email", contactEmail},
                                        {"Currency", currency},
                                        {"Timezone", timezone},
                                        {"QR Base URL", effectiveQrUrl},
                                        {"SMTP Enabled", String.valueOf(smtpEnabled)},
                                        {"Copilot Mode", copilotMode},
                                        {"Copilot Provider", displayProvider},
                                        {"Session Timeout", sessionTimeout + " minutes"},
                                        {"Audit Logging", String.valueOf(auditEnabled)},
                                        {"Upload Folder", uploadFolderPath},
                                        {"Backup Location", backupLocation}
                                };
                                for (String[] row : info) {
                            %>
                            <tr>
                                <td><%= h(row[0]) %></td>
                                <td><%= h(row[1]) %></td>
                            </tr>
                            <% } %>
                        </table>
                        <div class="form-actions">
                            <a href="audit_logs.jsp" class="btn-secondary"><i class="fa fa-scroll"></i> View Audit Logs</a>
                            <a href="backup_restore.jsp" class="btn-secondary"><i class="fa fa-database"></i> Backup / Restore</a>
                            <a href="db_status.jsp" class="btn-secondary"><i class="fa fa-heartbeat"></i> DB Status</a>
                        </div>
                    </div>
                </section>
            </div>
        </div>
    </main>
</div>

<script>
function switchTab(name) {
    const panel = document.getElementById('panel-' + name);
    if (!panel) return;

    document.querySelectorAll('.stab-panel').forEach(item => item.classList.remove('active'));
    document.querySelectorAll('.stab').forEach(item => {
        item.classList.toggle('active', item.dataset.tab === name);
        item.setAttribute('aria-selected', item.dataset.tab === name ? 'true' : 'false');
    });

    panel.classList.add('active');
    history.replaceState(null, '', location.pathname + '?section=' + encodeURIComponent(name));
}

function togglePwd(id, btn) {
    const input = document.getElementById(id);
    if (!input) return;
    const isPassword = input.type === 'password';
    input.type = isPassword ? 'text' : 'password';
    btn.innerHTML = isPassword ? '<i class="fa fa-eye-slash"></i>' : '<i class="fa fa-eye"></i>';
}

function toggleSmtpFields() {
    const enabled = document.getElementById('smtpEnabledToggle');
    const fields = document.getElementById('smtpFields');
    if (!enabled || !fields) return;
    fields.style.opacity = enabled.checked ? '1' : '0.55';
    fields.style.pointerEvents = enabled.checked ? '' : 'none';
}

function toggleAiFields() {
    const mode = document.getElementById('copilotModeSelect');
    const fields = document.getElementById('aiApiFields');
    if (!mode || !fields) return;
    const aiMode = mode.value === 'AI_API';
    fields.style.display = aiMode ? 'block' : 'none';
}

// Fault that recurred three times live, now structurally impossible: "AI
// Model Name" used to be one box shared by whichever provider was Primary,
// so switching the dropdown from Gemini to Groq and saving, without also
// retyping the box, silently saved "gemini-3.6-flash" as GROQ's model - a
// model Groq doesn't have, so every real Copilot request failed even though
// the provider itself switched correctly. Gemini, Groq and Custom each now
// have their own permanent field (geminiModelInput/groqModelInput/
// customModelInput) that never changes meaning when Primary changes, so
// there is no shared box left to clear or resync on a dropdown change.

function sendTestEmail(btn) {
    const emailInput = document.getElementById('testEmailAddr');
    const result = document.getElementById('testEmailResult');
    if (!emailInput || !result) return;

    const email = emailInput.value.trim();
    if (!email) {
        result.textContent = 'Enter a test email address.';
        result.style.color = '#92400e';
        return;
    }

    const form = document.getElementById('smtpForm');
    const data = new FormData(form);
    data.set('section', 'smtp_test');
    data.set('testEmail', email);

    const oldText = btn.innerHTML;
    btn.disabled = true;
    btn.innerHTML = '<i class="fa fa-spinner fa-spin"></i> Sending';
    result.textContent = 'Sending test email...';
    result.style.color = 'var(--ir-muted)';

    const contextPath = '<%= request.getContextPath() %>';
    fetch(contextPath + '/SaveSettingsServlet', {
        method: 'POST',
        credentials: 'same-origin',
        headers: {
            'Content-Type': 'application/x-www-form-urlencoded;charset=UTF-8',
            'Accept': 'application/json'
        },
        body: new URLSearchParams({
            action: 'smtp_test',
            testEmail: email
        })
    })
        .then(async response => {
            if (!response.ok) {
                const text = await response.text();
                throw new Error("HTTP " + response.status + ": " + text);
            }
            const contentType = response.headers.get("content-type");
            if (!contentType || !contentType.includes("application/json")) {
                const text = await response.text();
                console.error("Non-JSON response:", text);
                throw new Error("Server returned invalid response. Check servlet mapping/session.");
            }
            return response.json();
        })
        .then(data => {
            if (data.status === 'ok') {
                result.textContent = 'Test email sent to ' + email;
                result.style.color = '#15803d';
            } else {
                result.textContent = data.error;
                result.style.color = '#b91c1c';
            }
        })
        .catch((error) => {
            console.error(error);
            if (error.message.includes('Server returned invalid response')) {
                result.textContent = error.message;
            } else {
                result.textContent = 'Network error while sending test email. Check console.';
            }
            result.style.color = '#b91c1c';
        })
        .finally(() => {
            btn.disabled = false;
            btn.innerHTML = oldText;
        });
}

function getSelectedProvider() {
    const el = document.getElementById('tunnelProvider');
    return el ? el.value : 'ngrok';
}

function onProviderChange() {
    const p = getSelectedProvider();
    const input = document.getElementById('manualTunnelUrl');
    const actions = document.getElementById('tunnelActionButtons');
    
    if (p === 'ngrok') {
        if (input) input.placeholder = 'https://your-ngrok-url.ngrok-free.app';
        if (actions) actions.style.display = 'block';
    } else if (p === 'cloudflare') {
        if (input) input.placeholder = 'https://example.trycloudflare.com';
        if (actions) actions.style.display = 'block';
    } else {
        if (input) input.placeholder = 'https://your-public-domain.com';
        if (actions) actions.style.display = 'none';
    }
}

// Fault, found live: none of the five tunnel functions below checked
// response.ok before treating the parsed JSON as a success payload. Mobile
// tunnel control is deliberately disabled by default for every deployment
// (TunnelControlServlet.isMobileTunnelEnabled() gate, a real security
// hardening decision - see that servlet's own comment) and returns a 403
// with a real, honest {"error": "..."} body when it is. fetch() does NOT
// reject on a 4xx/5xx status - only response.json() ran, so every one of
// these functions silently swallowed the real reason and either showed a
// vague, misleading "No active tunnel" (checkTunnelStatus) or, worse, a
// false SUCCESS message (setManualUrl said "Tunnel URL saved" and
// clearTunnelUrl said "Tunnel URL cleared" even though the servlet had
// rejected the request before ever touching the database) - confirmed live:
// a stale "Running" badge plus a dead saved ngrok URL stayed displayed as an
// apparently-live clickable link even after clicking "Refresh Status", which
// itself reported the deployment-honest 403 as "No active tunnel" instead.
// parseTunnelResponse() below is the single place that now checks ok/status
// for every one of the five actions, so a disabled deployment (or any other
// non-2xx) is always surfaced as what it actually is, and no function can
// apply an "as if it worked" UI update for a request the server refused.
function parseTunnelResponse(response) {
    return response.json().then(data => ({ok: response.ok, data: data || {}}));
}

function startTunnel() {
    const provider = getSelectedProvider();
    fetch('TunnelControlServlet', {method: 'POST', body: new URLSearchParams({action: 'start', provider: provider})})
        .then(parseTunnelResponse)
        .then(({ok, data}) => {
            if (!ok) {
                setTunnelMsg(data.error || 'Unable to start tunnel.', '#fecaca');
                return;
            }
            if (data.url) {
                applyTunnelUrl(data.url);
                setTunnelMsg(data.message || 'Tunnel started successfully.', '#bbf7d0');
            } else if (data.status === 'starting') {
                setTunnelMsg(data.message || 'Tunnel is starting. Refresh status in a few seconds.', '#dbeafe');
                setTimeout(checkTunnelStatus, 5000);
            } else {
                setTunnelMsg(data.message || data.error || 'Unable to start tunnel.', '#fecaca');
            }
        })
        .catch(error => setTunnelMsg('Tunnel error: ' + error.message, '#fecaca'));
}

function stopTunnel() {
    fetch('TunnelControlServlet', {method: 'POST', body: new URLSearchParams({action: 'stop'})})
        .then(parseTunnelResponse)
        .then(({ok, data}) => {
            if (!ok) {
                setTunnelMsg(data.error || 'Unable to stop tunnel.', '#fecaca');
                return;
            }
            setTunnelMsg('Tunnel stopped. QR codes now use localhost.', '#dbeafe');
            const display = document.getElementById('tunnelUrlDisplay');
            if (display) display.textContent = 'No tunnel active. QR uses localhost.';
            const badge = document.getElementById('tunnelStatusBadge');
            if (badge) {
                badge.className = 'tunnel-status stopped';
                badge.innerHTML = '<i class="fa fa-circle"></i> Stopped';
            }
        })
        .catch(error => setTunnelMsg('Tunnel error: ' + error.message, '#fecaca'));
}

function checkTunnelStatus() {
    fetch('TunnelControlServlet', {method: 'POST', body: new URLSearchParams({action: 'status'})})
        .then(parseTunnelResponse)
        .then(({ok, data}) => {
            if (!ok) {
                // Honest, specific reason (e.g. "disabled for this
                // deployment") instead of a vague "No active tunnel" that
                // implies tunnels are simply off right now rather than not
                // controllable at all - and the badge/link are reset here
                // too, rather than left showing a stale "Running" state and
                // a dead URL as if it were still a live, clickable tunnel.
                setTunnelMsg(data.error || 'Tunnel status unavailable.', '#fecaca');
                const badge = document.getElementById('tunnelStatusBadge');
                if (badge) {
                    badge.className = 'tunnel-status stopped';
                    badge.innerHTML = '<i class="fa fa-circle"></i> Unavailable';
                }
                return;
            }
            if (data.status === 'running' && data.tunnelUrl) {
                applyTunnelUrl(data.tunnelUrl);
                setTunnelMsg('Tunnel is running.', '#bbf7d0');
            } else if (data.savedUrl) {
                applyTunnelUrl(data.savedUrl);
                setTunnelMsg('Saved tunnel URL loaded.', '#dbeafe');
            } else {
                setTunnelMsg('No active tunnel.', '#dbeafe');
            }
        })
        .catch(error => setTunnelMsg('Tunnel status error: ' + error.message, '#fecaca'));
}

function setManualUrl() {
    const input = document.getElementById('manualTunnelUrl');
    if (!input) return;
    const url = input.value.trim();
    if (!url) {
        alert('Please enter a tunnel URL.');
        return;
    }
    const provider = getSelectedProvider();
    fetch('TunnelControlServlet', {method: 'POST', body: new URLSearchParams({action: 'set_manual', url: url, provider: provider})})
        .then(parseTunnelResponse)
        .then(({ok, data}) => {
            if (!ok) {
                setTunnelMsg(data.error || 'Unable to save tunnel URL.', '#fecaca');
                return;
            }
            applyTunnelUrl(url);
            setTunnelMsg(data.message || 'Tunnel URL saved.', '#bbf7d0');
        })
        .catch(error => setTunnelMsg('Unable to save tunnel URL: ' + error.message, '#fecaca'));
}

function clearTunnelUrl() {
    const input = document.getElementById('manualTunnelUrl');
    const provider = getSelectedProvider();
    fetch('TunnelControlServlet', {method: 'POST', body: new URLSearchParams({action: 'set_manual', url: '', provider: provider})})
        .then(parseTunnelResponse)
        .then(({ok, data}) => {
            if (!ok) {
                setTunnelMsg(data.error || 'Unable to clear tunnel URL.', '#fecaca');
                return;
            }
            if (input) input.value = '';
            const display = document.getElementById('tunnelUrlDisplay');
            if (display) display.textContent = 'No tunnel active. QR uses localhost.';
            setTunnelMsg('Tunnel URL cleared.', '#dbeafe');
        })
        .catch(error => setTunnelMsg('Unable to clear tunnel URL: ' + error.message, '#fecaca'));
}

function applyTunnelUrl(url) {
    const display = document.getElementById('tunnelUrlDisplay');
    if (display) {
        display.innerHTML = '<a href="' + encodeURI(url) + '" target="_blank" style="color:#bfdbfe;">' + escapeHtml(url) + '</a>';
    }
    const manual = document.getElementById('manualTunnelUrl');
    if (manual) manual.value = url;
    const effective = document.getElementById('effectiveUrlDisplay');
    if (effective) effective.value = url;
    const badge = document.getElementById('tunnelStatusBadge');
    if (badge) {
        badge.className = 'tunnel-status running';
        badge.innerHTML = '<i class="fa fa-circle"></i> Running';
    }
}

function setTunnelMsg(message, color) {
    const el = document.getElementById('tunnelMsg');
    if (el) {
        el.textContent = message;
        el.style.color = color;
    }
}

function testAiConnection(btn, provider) {
    const oldText = btn.innerHTML;
    btn.disabled = true;
    btn.innerHTML = '<i class="fa fa-spinner fa-spin"></i> Testing';

    // Fault: this used to send only {provider}, so "Test" always probed
    // whatever key was already SAVED in the database - pasting a new key
    // and clicking Test before Save silently tested the OLD key with no
    // indication that's what happened. Now sends whatever is currently
    // typed in the form; the server prefers a non-blank pending value over
    // the saved one, so Test reflects the form as it stands right now,
    // saved or not. An empty field still just falls back to the saved key.
    const keyFieldByProvider = {
        GEMINI: 'geminiKeyInput',
        GROQ: 'groqKeyInput',
        CUSTOM: 'customKeyInput'
    };
    const keyField = document.getElementById(keyFieldByProvider[provider]);
    const endpointField = document.getElementById('aiEndpointInput');
    const labelField = document.getElementById('customLabelInput');

    const params = {provider: provider};
    if (keyField && keyField.value.trim()) params.pendingKey = keyField.value.trim();
    if (endpointField && endpointField.value.trim()) params.pendingEndpoint = endpointField.value.trim();
    if (provider === 'CUSTOM' && labelField && labelField.value.trim()) {
        params.pendingLabel = labelField.value.trim();
    }

    // Each provider owns its own permanent model field now, so the button's
    // provider always tells us exactly which field to read - no need to
    // check whether that provider happens to be the selected Primary.
    const modelFieldByProvider = {
        GEMINI: 'geminiModelInput',
        GROQ: 'groqModelInput',
        CUSTOM: 'customModelInput'
    };
    const modelField = document.getElementById(modelFieldByProvider[provider]);
    if (modelField && modelField.value.trim()) {
        params.pendingModel = modelField.value.trim();
    }

    fetch('TestCopilotConnectionServlet', {
        method: 'POST',
        headers: {'Content-Type': 'application/x-www-form-urlencoded;charset=UTF-8'},
        body: new URLSearchParams(params)
    })
        .then(response => response.text())
        .then(message => {
            const ok = message.toLowerCase().includes('successfully');
            showTestResult(btn, ok, message);
        })
        .catch(() => showTestResult(btn, false, 'Network error while testing connection.'))
        .finally(() => {
            btn.disabled = false;
            btn.innerHTML = oldText;
        });
}

// Mirrors testAiConnection's param-building exactly (same "test what's in
// the form right now" rule), but hits the quota-check action instead: reads
// back the provider's own rate-limit response headers rather than a plain
// pass/fail. Gemini has none to show (Google's API doesn't expose them) -
// the server says so honestly rather than this looking broken.
function checkAiQuota(btn, provider) {
    const oldText = btn.innerHTML;
    btn.disabled = true;
    btn.innerHTML = '<i class="fa fa-spinner fa-spin"></i> Checking';

    const keyFieldByProvider = {
        GEMINI: 'geminiKeyInput',
        GROQ: 'groqKeyInput',
        CUSTOM: 'customKeyInput'
    };
    const keyField = document.getElementById(keyFieldByProvider[provider]);
    const endpointField = document.getElementById('aiEndpointInput');

    const params = {action: 'quota', provider: provider};
    if (keyField && keyField.value.trim()) params.pendingKey = keyField.value.trim();
    if (endpointField && endpointField.value.trim()) params.pendingEndpoint = endpointField.value.trim();

    fetch('TestCopilotConnectionServlet', {
        method: 'POST',
        headers: {'Content-Type': 'application/x-www-form-urlencoded;charset=UTF-8'},
        body: new URLSearchParams(params)
    })
        .then(response => response.text())
        .then(message => {
            const ok = !/unauthorized|no api key|not available|network error/i.test(message);
            showTestResult(btn, ok, message);
        })
        .catch(() => showTestResult(btn, false, 'Network error while checking usage.'))
        .finally(() => {
            btn.disabled = false;
            btn.innerHTML = oldText;
        });
}

// Fault: this used to report the result via alert(). Chrome (and other
// browsers) silently blocks native dialogs after a page has shown a few in
// a row - "Prevent this page from creating additional dialogs" - and some
// privacy extensions block them outright. The request completes fine and
// the server genuinely answers; the alert() call itself just returns
// immediately with nothing shown, which is indistinguishable from the
// button doing nothing at all. Confirmed live: clicking Test produced a
// real, correct server response with no visible sign of it. Shown inline in
// the card instead, so nothing depends on the browser's dialog policy.
function showTestResult(btn, ok, message) {
    const card = btn.closest('.copilot-provider-card') || btn.parentElement;
    let result = card.querySelector('.test-result-inline');
    if (!result) {
        result = document.createElement('div');
        result.className = 'test-result-inline';
        card.appendChild(result);
    }
    result.className = 'test-result-inline ' + (ok ? 'ok' : 'fail');
    result.innerHTML = '<i class="fa ' + (ok ? 'fa-circle-check' : 'fa-circle-exclamation') + '"></i> '
        + escapeHtml(message);
}

function escapeHtml(value) {
    return String(value)
        .replace(/&/g, '&amp;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;')
        .replace(/"/g, '&quot;')
        .replace(/'/g, '&#39;');
}

// Drag-and-drop reorder for the "Active answer chain" chips. Only the real
// provider chips (draggable="true", carrying data-code) can move; the fixed
// "Local keyword engine" chip at the end has neither attribute and is never
// touched. Dropping just reorders the DOM nodes in place and re-serializes
// their data-code order into the hidden #chainOrderInput field - actually
// persisting the new order still requires clicking Save Copilot Settings,
// same as every other field on this form.
function initChainDragDrop() {
    const flow = document.getElementById('chainFlow');
    const orderInput = document.getElementById('chainOrderInput');
    if (!flow || !orderInput) return;

    let dragged = null;

    function draggableChips() {
        return Array.prototype.slice.call(flow.querySelectorAll('.copilot-chain-chip[draggable="true"]'));
    }

    function syncOrderInput() {
        orderInput.value = draggableChips().map(chip => chip.dataset.code).join(',');
    }

    function clearDragOverMarkers() {
        draggableChips().forEach(chip => chip.classList.remove('drag-over'));
    }

    // Dragging a different chip to the front changes which provider is
    // actually tried first - the Primary AI Provider dropdown needs to
    // follow that, otherwise Save would still write the OLD primary's
    // provider code even though the chain (and therefore what actually
    // answers first) has changed. Each provider's model field is
    // permanently its own now, so there's nothing left to resync on this
    // change beyond the dropdown value itself.
    function syncPrimaryProviderFromFirstChip() {
        const providerSelect = document.getElementById('copilotProviderSelect');
        const firstChip = draggableChips()[0];
        if (!providerSelect || !firstChip) return;
        const code = firstChip.dataset.code;
        if (!code || providerSelect.value === code) return;
        // Anthropic/Claude deliberately has no option in this dropdown at
        // all (it's "backend only" - primary selection isn't offered for
        // it). It can still be dragged to the front and will still be
        // TRIED first by the saved chain order; there's just no dropdown
        // value to mirror it onto, so leave the dropdown alone in that case
        // rather than silently failing to select a nonexistent option.
        const hasOption = Array.prototype.some.call(
            providerSelect.options, (opt) => opt.value === code);
        if (!hasOption) return;
        providerSelect.value = code;
    }

    flow.addEventListener('dragstart', (e) => {
        const chip = e.target.closest('.copilot-chain-chip[draggable="true"]');
        if (!chip) return;
        dragged = chip;
        chip.classList.add('dragging');
        e.dataTransfer.effectAllowed = 'move';
        // Firefox requires data actually be set for drag to start at all.
        e.dataTransfer.setData('text/plain', chip.dataset.code || '');
    });

    flow.addEventListener('dragover', (e) => {
        if (!dragged) return;
        const chip = e.target.closest('.copilot-chain-chip[draggable="true"]');
        if (!chip || chip === dragged) return;
        e.preventDefault();
        e.dataTransfer.dropEffect = 'move';
        clearDragOverMarkers();
        chip.classList.add('drag-over');
        const rect = chip.getBoundingClientRect();
        const insertBefore = (e.clientX - rect.left) < rect.width / 2;
        flow.insertBefore(dragged, insertBefore ? chip : chip.nextSibling);
    });

    flow.addEventListener('drop', (e) => {
        if (!dragged) return;
        e.preventDefault();
        clearDragOverMarkers();
        syncOrderInput();
    });

    flow.addEventListener('dragend', () => {
        if (dragged) dragged.classList.remove('dragging');
        clearDragOverMarkers();
        dragged = null;
        syncOrderInput();
        syncPrimaryProviderFromFirstChip();
    });
}

document.addEventListener('DOMContentLoaded', () => {
    document.querySelectorAll('.stab').forEach(button => {
        button.addEventListener('click', () => switchTab(button.dataset.tab));
        button.setAttribute('aria-selected', button.classList.contains('active') ? 'true' : 'false');
    });

    const smtpToggle = document.getElementById('smtpEnabledToggle');
    if (smtpToggle) smtpToggle.addEventListener('change', toggleSmtpFields);

    const mode = document.getElementById('copilotModeSelect');
    if (mode) mode.addEventListener('change', toggleAiFields);

    toggleSmtpFields();
    toggleAiFields();
    initChainDragDrop();

    if (window.setActiveMenu) setActiveMenu('settings.jsp');

    // Fault, found live: this fired after only 5 seconds. Confirmed the
    // server renders the "Settings saved successfully" banner correctly on
    // every save (checked the raw HTML directly), but a save-then-reload
    // round trip plus actually noticing something at the top of a long,
    // tab-heavy settings page easily eats 5 seconds on its own - by the
    // time anyone looked, it was already gone, which is indistinguishable
    // from "the message never showed". Scrolled into view so it doesn't
    // depend on where the page happened to load scrolled to, and given
    // enough time to actually be read before it dismisses itself.
    const alert = document.getElementById('topAlert');
    if (alert) {
        alert.scrollIntoView({block: 'start', behavior: 'smooth'});
        setTimeout(() => {
            alert.style.opacity = '0';
            alert.style.transition = 'opacity .5s';
            setTimeout(() => alert.remove(), 500);
        }, 9000);
    }
});
</script>
<script src="js/sidebar-role.js"></script>


<script>
(function () {
    function bindCopilotSettingsSidebarToggle() {
        var toggle = document.querySelector('.nav-toggle');
        if (!toggle || toggle.getAttribute('data-ams-sidebar-bound') === 'true') {
            return;
        }
        toggle.setAttribute('data-ams-sidebar-bound', 'true');
        toggle.addEventListener('click', function () {
            document.body.classList.toggle('sidebar-collapsed');
            try {
                localStorage.setItem('irAmsSidebarState', document.body.classList.contains('sidebar-collapsed') ? 'collapsed' : 'expanded');
            } catch (e) {}
        });
    }

    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', bindCopilotSettingsSidebarToggle);
    } else {
        bindCopilotSettingsSidebarToggle();
    }
})();
</script>

<script>
(function () {
    function forceCopilotSettingsSidebarBrandCenter() {
        var brand = document.querySelector('aside.sidebar.railway-sidebar .railway-sidebar-brand-center, aside.railway-sidebar .railway-sidebar-brand-center, .railway-sidebar .railway-sidebar-brand-center');
        if (!brand) {
            return;
        }

        brand.style.setProperty('position', 'relative', 'important');
        brand.style.setProperty('left', '26px', 'important');
        brand.style.setProperty('right', 'auto', 'important');
        brand.style.setProperty('transform', 'none', 'important');
        brand.style.setProperty('width', 'calc(100% - 26px)', 'important');
        brand.style.setProperty('max-width', 'calc(100% - 26px)', 'important');
        brand.style.setProperty('margin-left', '0', 'important');
        brand.style.setProperty('margin-right', '0', 'important');
        brand.style.setProperty('padding-left', '0', 'important');
        brand.style.setProperty('padding-right', '0', 'important');
        brand.style.setProperty('text-align', 'center', 'important');
        brand.style.setProperty('box-sizing', 'border-box', 'important');

        var logoBox = document.querySelector('aside.sidebar.railway-sidebar .logo-box.railway-brand, aside.railway-sidebar .logo-box.railway-brand, .railway-sidebar .logo-box.railway-brand');
        if (logoBox) {
            logoBox.style.setProperty('overflow', 'visible', 'important');
        }
    }

    function runSidebarBrandCenterFix() {
        forceCopilotSettingsSidebarBrandCenter();
        setTimeout(forceCopilotSettingsSidebarBrandCenter, 80);
        setTimeout(forceCopilotSettingsSidebarBrandCenter, 250);
    }

    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', runSidebarBrandCenterFix);
    } else {
        runSidebarBrandCenterFix();
    }
    window.addEventListener('load', runSidebarBrandCenterFix);
})();
</script>
</body>
</html>
<%!
    private String h(String s) {
        if (s == null) {
            return "";
        }
        return s.replace("&", "&amp;")
                .replace("<", "&lt;")
                .replace(">", "&gt;")
                .replace("\"", "&quot;")
                .replace("'", "&#39;");
    }
%>
