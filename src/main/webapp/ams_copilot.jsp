<%@page contentType="text/html" pageEncoding="UTF-8"%>
<%@page import="com.mycompany.asset_management_system_ams.SettingsDAO"%>
<%
    String username = (String) session.getAttribute("username");
    String role     = (String) session.getAttribute("role");
    String displayName = (String) session.getAttribute("displayName");
    if (displayName == null) displayName = username;
    response.setHeader("Cache-Control","no-cache,no-store,must-revalidate");
    if (username == null || role == null) { response.sendRedirect("login.jsp"); return; }

    boolean copilotEnabled = SettingsDAO.isCopilotEnabled();
    String orgName = SettingsDAO.getOrgName();
    String systemName = SettingsDAO.getSystemName();
    boolean isAiMode = SettingsDAO.isAiMode();
    String aiProvider = SettingsDAO.getCopilotProvider();
%>
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width,initial-scale=1">
    <title>AMS Copilot — <%= orgName %></title>
    <meta name="description" content="IR-AMS AI Copilot — Ask questions about your railway assets, employees, maintenance and more.">
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.0/css/all.min.css">
    <link rel="stylesheet" href="css/ir-ams-railway-ui.css?v=copilot-v2">
    <link rel="stylesheet" href="css/ams_copilot.css?v=28001">
    <script src="https://cdn.jsdelivr.net/npm/marked/marked.min.js"></script>
    <script src="https://cdn.jsdelivr.net/npm/dompurify/dist/purify.min.js"></script>


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

        .chat-mic-btn.listening, .copilot-voice-btn.listening {
            box-shadow: 0 0 0 4px rgba(0, 128, 0, 0.12) !important;
            transform: scale(1.1) !important;
            color: #28a745 !important;
            border-color: #28a745 !important;
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
<div class="app ams-shell">

    <div class="page-fixed-emblem-watermark" aria-hidden="true">
        <img src="images/Emblem_of_India.png" alt="">
    </div>
    <%@ include file="sidebar.jsp" %>
    <main class="main railway-main">
        <%@ include file="topbar.jsp" %>
        <div class="main-scroll-content">
            <div class="copilot-board">

                <section class="copilot-hero">
                    <div class="copilot-hero-copy">
                        <span class="copilot-eyebrow">
                            <i class="fa-solid fa-robot"></i>
                            AI Copilot · East Coast Railway
                        </span>

                        <h1>AI Copilot</h1>

                        <p>
                            Ask AMS questions, generate reports, analyze assets, and perform safe confirmed actions.
                        </p>

                        <div class="copilot-hero-pills">
                            <div class="copilot-hero-pill"><i class="fa-solid fa-comments"></i> Natural Q&amp;A</div>
                            <div class="copilot-hero-pill"><i class="fa-solid fa-file-excel"></i> Excel Export</div>
                            <div class="copilot-hero-pill"><i class="fa-solid fa-microphone"></i> Voice Commands</div>
                            <div class="copilot-hero-pill"><i class="fa-solid fa-shield-halved"></i> Role-Based Controls</div>
                        </div>
                    </div>
                </section>

                <% if (!copilotEnabled) { %>
                <div class="settings-card" style="text-align:center;padding:56px;">
                    <i class="fa fa-robot" style="font-size:56px;color:var(--ir-muted);opacity:.4;"></i>
                    <h2 style="margin:16px 0 8px;color:var(--ir-blue);">AMS Copilot Disabled</h2>
                    <p style="color:var(--ir-muted);">AMS Copilot is currently disabled. Enable it in System Settings.</p>
                    <% if ("SUPER_ADMIN".equals(role) || "ADMIN".equals(role)) { %>
                    <a href="settings.jsp?section=copilot" style="display:inline-block;margin-top:16px;background:var(--ir-blue);color:#fff;border-radius:10px;padding:10px 24px;font-weight:700;text-decoration:none;"><i class="fa fa-cog"></i> Go to Settings</a>
                    <% } %>
                </div>
                <% } else { %>

                <div class="copilot-layout">
                    <!-- Left Sidebar -->
                    <div class="copilot-sidebar">
                        <div class="cop-sidebar-header">
                            <h3>🤖 AMS Copilot</h3>
                            <p><%= orgName %></p>
                            <div class="cop-mode-badge">
                                <i class="fa fa-<%= isAiMode?"brain":"database" %>"></i>
                                <%= isAiMode ? "AI: " + aiProvider : "Live AMS Data" %>
                            </div>
                        </div>

                        <div class="suggested-list">
                            <h4>Quick Queries</h4>
                            <button type="button" class="sug-btn" onclick="askQuestion('Show laptops in IT department')">
                                <i class="fa-solid fa-filter"></i> Laptops in IT
                            </button>
                            <button type="button" class="sug-btn" onclick="askQuestion('Total asset portfolio value')">
                                <i class="fa-solid fa-chart-pie"></i> Portfolio Value
                            </button>
                            <button type="button" class="sug-btn" onclick="askQuestion('Show me a dashboard summary')">
                                <i class="fa-solid fa-columns"></i> Dashboard Summary
                            </button>
                            <button type="button" class="sug-btn" onclick="askQuestion('Pending maintenance requests')">
                                <i class="fa-solid fa-clock"></i> Pending Maintenance
                            </button>
                        </div>

                        <div style="padding:12px;border-top:1.5px solid var(--ir-line);">
                            <!--
                                Replaced "Quick Stats (Instant)" (a deliberate
                                AI-free, direct-SQL safety net for when a
                                provider is slow/rate-limited - moved, not
                                deleted: still reachable directly at
                                CopilotQuickStatsServlet, its own page still
                                works unchanged) with a link to the durable,
                                cross-session chat history this Copilot has
                                quietly kept in copilot_chat_history all
                                along but never had a UI to browse - "Clear
                                Chat" below only ever cleared the visible
                                screen, never that table.
                            -->
                            <a href="copilot_chat_history.jsp" style="display:flex;align-items:center;justify-content:center;gap:6px;width:100%;padding:9px;border:1.5px solid var(--ir-blue,#2563eb);border-radius:9px;background:#eff6ff;color:var(--ir-blue,#2563eb);font-size:12px;font-weight:700;cursor:pointer;text-decoration:none;margin-bottom:8px;box-sizing:border-box;">
                                <i class="fa-solid fa-clock-rotate-left"></i> Chat History
                            </a>
                            <button onclick="clearChat()" style="width:100%;padding:9px;border:1.5px solid var(--ir-line);border-radius:9px;background:#fff;color:var(--ir-muted);font-size:12px;font-weight:700;cursor:pointer;">
                                <i class="fa fa-trash-alt"></i> Clear Chat
                            </button>
                        </div>
                    </div>

            <!-- Main Chat -->
            <div class="copilot-main">
                <div class="cop-header">
                    <div class="cop-avatar">🤖</div>
                    <div class="cop-header-info">
                        <h2>AMS Copilot</h2>
                        <p><%= systemName %> — AI Assistant</p>
                    </div>
                    <div class="cop-status">
                        <span class="cop-status-dot"></span>
                        <span>Online</span>
                        <span style="margin-left:10px;background:var(--ir-soft);border-radius:8px;padding:3px 10px;color:var(--ir-blue);font-size:11px;"><%= isAiMode ? "⚡ " + aiProvider + " AI" : "⚡ Live AMS Data" %></span>
                    </div>
                </div>

                <div class="chat-messages" id="chatMessages">
                    <!-- Welcome message -->
                    <div class="msg bot" id="welcomeMsg">
                        <div class="msg-bubble">
                            <strong>👋 Hello, <%= displayName %>!</strong><br><br>
                            I'm the <strong>AMS Copilot</strong> for <em><%= orgName %></em>.<br><br>
                            I can answer questions about your <strong>assets, employees, maintenance, warranties, allocations</strong> and more — all based on live data from your database.<br><br>
                            Use the suggested questions on the left, or type anything below. Try: <em>"Show me a dashboard summary"</em>
                        </div>
                        <div class="msg-meta">AMS Copilot • Just now</div>
                    </div>

                    <!-- Typing indicator -->
                    <div class="msg bot typing-indicator" id="typingIndicator">
                        <div class="msg-bubble">
                            <div class="typing-dots"><span></span><span></span><span></span></div>
                        </div>
                    </div>
                </div>

                <div class="chat-input-area">
                    <div id="imageAttachPreview" class="image-attach-preview" style="display:none;">
                        <img id="imageAttachThumb" alt="Attached photo preview">
                        <span id="imageAttachName"></span>
                        <button type="button" id="imageAttachRemoveBtn" title="Remove photo"><i class="fa fa-times"></i></button>
                    </div>
                    <div class="chat-input-row">
                        <input type="file" id="imageAttachInput" accept="image/*" style="display:none;">
                        <button class="chat-mic-btn copilot-attach-btn" id="attachBtn" title="Attach a photo (asset tag, QR code, damage)" type="button">
                            <i class="fa fa-camera"></i>
                        </button>
                        <textarea class="chat-input-box" id="chatInput" rows="1"
                            placeholder="Ask anything about your assets, employees, maintenance..."
                            onkeydown="handleInputKey(event)"
                            oninput="autoResize(this)"></textarea>
                        <button class="chat-mic-btn copilot-voice-btn" id="micBtn" title="Voice Input">
                            <i class="fa fa-microphone"></i>
                        </button>
                        <button class="chat-send-btn" id="sendBtn" onclick="sendMessage()">
                            <i class="fa fa-paper-plane"></i>
                        </button>
                    </div>

                    <div id="voiceCorrectionBox" class="voice-correction-box" style="display:none; padding: 10px; background: #fff3cd; border: 1px solid #ffeeba; border-radius: 6px; margin-bottom: 10px; font-size: 13px;">
                        <strong>Did you mean:</strong> "<span id="voiceCorrectionText" style="font-weight: 500; font-style: italic; color: #856404;"></span>"
                        <div style="margin-top: 8px; display: flex; gap: 8px;">
                            <button type="button" id="useVoiceCorrectionBtn" style="padding: 5px 10px; background: #28a745; color: white; border: none; border-radius: 4px; cursor: pointer; font-size: 12px;"><i class="fa fa-check"></i> Use corrected text</button>
                            <button type="button" id="keepVoiceOriginalBtn" style="padding: 5px 10px; background: #6c757d; color: white; border: none; border-radius: 4px; cursor: pointer; font-size: 12px;"><i class="fa fa-times"></i> Keep original</button>
                        </div>
                    </div>
                    <div class="input-hint">
                        Press <kbd style="background:#eef;border:1px solid #ddd;border-radius:4px;padding:1px 5px;font-size:10px;">Enter</kbd> to send, 
                        <kbd style="background:#eef;border:1px solid #ddd;border-radius:4px;padding:1px 5px;font-size:10px;">Shift+Enter</kbd> for new line.
                        <span id="copilotVoiceStatus" class="copilot-voice-status" style="margin-left: 10px; color: #007bff; font-weight: bold; font-size: 11px;"></span>
                    </div>
                </div>
            </div>
        </div>

        <% } %>

        </div><!-- end copilot-board -->
        </div><!-- end main-scroll-content -->
    </main>
</div>

<script>
const chatMessages = document.getElementById('chatMessages');
const chatInput    = document.getElementById('chatInput');
const sendBtn      = document.getElementById('sendBtn');
const typingIndicator = document.getElementById('typingIndicator');
let isWaiting = false;

function askQuestion(q) {
    chatInput.value = q;
    chatInput.focus();
    sendMessage();
}

// Lets copilot_chat_history.jsp's "Ask again" links (ams_copilot.jsp?q=...)
// re-send a past question with one click, instead of the user having to
// retype it from memory after reading it on the history page.
(function autoAskFromQueryParam() {
    const params = new URLSearchParams(window.location.search);
    const q = params.get('q');
    if (!q) return;
    // Strip the param from the visible URL so refreshing the page doesn't
    // silently re-send the same question again.
    window.history.replaceState(null, '', window.location.pathname);
    document.addEventListener('DOMContentLoaded', () => askQuestion(q));
})();

function handleInputKey(e) {
    if (e.key === 'Enter' && !e.shiftKey) {
        e.preventDefault();
        sendMessage();
    }
}

function autoResize(el) {
    el.style.height = 'auto';
    el.style.height = Math.min(el.scrollHeight, 120) + 'px';
}

// ─────────────────────────────────────────────────────────────────────────
// PRE-WARMED RESPONSE CACHE
//
// Solves "flaky network during a live presentation" without inventing
// anything: the first time a question is asked, its REAL CopilotServlet
// answer is cached verbatim. If that exact question is asked again in the
// exact same conversational position, it replays instantly from
// localStorage - no fetch, no AI provider, no network dependency. Every
// value that can ever come out of this cache is something the real server
// actually said at some earlier point; nothing here can show a user data
// that didn't come from a genuine answer.
//
// Cache key includes the PRECEDING question, not just the current one, so
// context-dependent follow-ups replay correctly. Without that, "show the
// full details" asked after "how many employees joined this month?" and
// the same phrase asked after "how many assets are damaged?" would collide
// on one cache slot and replay whichever was cached last - wrong for
// whichever question it wasn't actually asked after. Keying on (previous
// question, current question) disambiguates them the same way the real
// backend's own conversation memory already does, just replayed instead of
// recomputed.
//
// To pre-warm before a presentation: just ask your real demo questions
// once, for real, over a working connection. Each answer is cached
// automatically. Ask the same sequence again later (even offline) and it
// replays instantly.
const CopilotCache = (function () {
    const STORAGE_KEY = 'irAmsCopilotResponseCache';
    let lastQuestion = null; // previous turn's question, for key disambiguation

    function normalize(text) {
        return (text || '').trim().toLowerCase().replace(/\s+/g, ' ');
    }

    function keyFor(prevQuestion, question) {
        return normalize(prevQuestion) + '||' + normalize(question);
    }

    function readStore() {
        try {
            return JSON.parse(localStorage.getItem(STORAGE_KEY) || '{}');
        } catch (e) {
            return {};
        }
    }

    function writeStore(store) {
        try {
            localStorage.setItem(STORAGE_KEY, JSON.stringify(store));
        } catch (e) {
            // Caching is a pure optimization, never a requirement - a full
            // or unavailable localStorage should degrade to "always live",
            // not break the chat.
        }
    }

    return {
        /** A cached {answer, type} for `question` in the current conversational position, or null. */
        get(question) {
            return readStore()[keyFor(lastQuestion, question)] || null;
        },

        /** Cache a REAL server response so this exact question, asked right after the same prior question, replays instantly next time. */
        put(question, answer, type) {
            const store = readStore();
            store[keyFor(lastQuestion, question)] = {
                answer: answer,
                type: type,
                cachedAt: new Date().toISOString()
            };
            writeStore(store);
        },

        /** Call after every turn (cached or live) so the NEXT question's key is disambiguated against the right predecessor. */
        recordTurn(question) {
            lastQuestion = question;
        },

        /** Wipe the pre-warmed cache, e.g. after a demo script changes. */
        clear() {
            try { localStorage.removeItem(STORAGE_KEY); } catch (e) {}
        }
    };
})();

// ─────────────────────────────────────────────────────────────────────────
// IMAGE ATTACH — a photo of an asset tag, QR code, nameplate, or physical
// damage. Downscaled client-side via <canvas> to at most MAX_IMAGE_DIMENSION
// on its longest side and re-encoded as JPEG before ever being sent -  a raw
// phone-camera photo can be several MB, and a model reading a tag or QR code
// needs nowhere near that resolution. Keeps the request comfortably under
// the servlet container's default POST-size limit for a plain form-encoded
// body without needing multipart upload handling at all.
// ─────────────────────────────────────────────────────────────────────────
const MAX_IMAGE_DIMENSION = 1280;
const IMAGE_JPEG_QUALITY = 0.72;
let pendingImage = null; // { base64, mimeType } - base64 has NO "data:...;base64," prefix

(function setupImageAttach() {
    const attachBtn = document.getElementById('attachBtn');
    const fileInput = document.getElementById('imageAttachInput');
    const preview = document.getElementById('imageAttachPreview');
    const thumb = document.getElementById('imageAttachThumb');
    const nameLabel = document.getElementById('imageAttachName');
    const removeBtn = document.getElementById('imageAttachRemoveBtn');
    if (!attachBtn || !fileInput) return;

    attachBtn.addEventListener('click', () => fileInput.click());

    fileInput.addEventListener('change', () => {
        const file = fileInput.files && fileInput.files[0];
        fileInput.value = ''; // allow re-selecting the same file later
        if (!file) return;
        if (!file.type.startsWith('image/')) {
            addMessage('bot', '❌ Please attach an image file.', 'error');
            return;
        }
        downscaleImage(file, MAX_IMAGE_DIMENSION, IMAGE_JPEG_QUALITY)
            .then(({ dataUrl, base64 }) => {
                pendingImage = { base64: base64, mimeType: 'image/jpeg' };
                thumb.src = dataUrl;
                nameLabel.textContent = file.name;
                preview.style.display = 'flex';
            })
            .catch(() => {
                addMessage('bot', '❌ Could not read that image. Please try a different file.', 'error');
            });
    });

    removeBtn.addEventListener('click', () => {
        pendingImage = null;
        preview.style.display = 'none';
        thumb.src = '';
    });
})();

/** Resizes/re-encodes an image File to a JPEG data URL, returning both the data URL (for preview) and bare base64 (for the request). */
function downscaleImage(file, maxDimension, quality) {
    return new Promise((resolve, reject) => {
        const reader = new FileReader();
        reader.onerror = () => reject(reader.error);
        reader.onload = () => {
            const img = new Image();
            img.onerror = () => reject(new Error('Invalid image'));
            img.onload = () => {
                let { width, height } = img;
                if (width > maxDimension || height > maxDimension) {
                    const scale = maxDimension / Math.max(width, height);
                    width = Math.round(width * scale);
                    height = Math.round(height * scale);
                }
                const canvas = document.createElement('canvas');
                canvas.width = width;
                canvas.height = height;
                canvas.getContext('2d').drawImage(img, 0, 0, width, height);
                const dataUrl = canvas.toDataURL('image/jpeg', quality);
                resolve({ dataUrl: dataUrl, base64: dataUrl.split(',')[1] });
            };
            img.src = reader.result;
        };
        reader.readAsDataURL(file);
    });
}

function sendMessage() {
    if (isWaiting) return;
    const typed = chatInput.value.trim();
    const attachedImage = pendingImage;
    if (!typed && !attachedImage) return;

    // A photo with no typed question still needs SOME question text server-
    // side (CopilotServlet rejects a blank one) - a sensible default rather
    // than making the user type something when the photo IS the question.
    const q = typed || (attachedImage ? 'What is shown in this photo?' : '');

    // Add user message - a plain marker so the transcript shows a photo was
    // part of this turn, without re-rendering the (possibly large) image
    // itself into the chat log.
    addMessage('user', attachedImage ? q + '\n\n📷 *Photo attached*' : q);
    chatInput.value = '';
    chatInput.style.height = 'auto';
    if (attachedImage) {
        pendingImage = null;
        document.getElementById('imageAttachPreview').style.display = 'none';
    }

    // Pre-warmed cache is text-only by design - a cached answer was never
    // grounded in whatever photo is attached THIS time, so an attached image
    // always skips both the replay lookup and the write-back below.
    if (!attachedImage) {
        const cached = CopilotCache.get(q);
        if (cached) {
            addMessage('bot', cached.answer, 'ok', cached.type, q);
            CopilotCache.recordTurn(q);
            scrollToBottom();
            return;
        }
    }

    // Show typing
    isWaiting = true;
    sendBtn.disabled = true;
    typingIndicator.style.display = 'flex';
    scrollToBottom();

    let body = 'question=' + encodeURIComponent(q);
    if (attachedImage) {
        body += '&imageData=' + encodeURIComponent(attachedImage.base64)
              + '&imageMimeType=' + encodeURIComponent(attachedImage.mimeType);
    }

    fetch('CopilotServlet', {
        method: 'POST',
        headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
        body: body
    })
    .then(r => r.json())
    .then(data => {
        typingIndicator.style.display = 'none';
        isWaiting = false;
        sendBtn.disabled = false;

        if (data.error) {
            addMessage('bot', '❌ ' + data.error, 'error');
        } else {
            addMessage('bot', data.answer, 'ok', data.type, q);
            // Pre-warm cache, same text-only reasoning as the lookup above -
            // an image-grounded answer must never be replayed for a later
            // question that happens to match the same text but no photo.
            if (!attachedImage) {
                CopilotCache.put(q, data.answer, data.type);
            }
        }
        CopilotCache.recordTurn(q);
    })
    .catch(err => {
        typingIndicator.style.display = 'none';
        isWaiting = false;
        sendBtn.disabled = false;
        addMessage('bot', '❌ Network error. Please check your connection and try again.', 'error');
    });
}

function addMessage(role, text, status, type, question) {
    const now = new Date().toLocaleTimeString('en-IN', {hour:'2-digit', minute:'2-digit'});
    const div = document.createElement('div');
    div.className = 'msg ' + role;

    const bubble = document.createElement('div');
    bubble.className = 'msg-bubble' + (status === 'error' ? ' error-bubble' : '');

    // Parse Markdown using marked.js and sanitize with DOMPurify
    let formatted = 'Error parsing markdown.';
    if (typeof marked !== 'undefined') {
        formatted = marked.parse(text);
        if (typeof DOMPurify !== 'undefined') {
            formatted = DOMPurify.sanitize(formatted);
        }
    } else {
        formatted = text.replace(/\n/g, '<br>');
        if (typeof DOMPurify !== 'undefined') {
            formatted = DOMPurify.sanitize(formatted);
        }
    }

    // Wrap tables for horizontal scrolling
    formatted = formatted.replace(/<table/g, '<div class="table-responsive"><table').replace(/<\/table>/g, '</table></div>');

    bubble.innerHTML = formatted;

    // Add Copy Button
    if (role === 'bot') {
        const copyBtn = document.createElement('button');
        copyBtn.className = 'msg-copy-btn';
        copyBtn.innerHTML = '<i class="fa fa-copy"></i>';
        copyBtn.onclick = () => {
            navigator.clipboard.writeText(text);
            copyBtn.innerHTML = '<i class="fa fa-check"></i>';
            setTimeout(() => { copyBtn.innerHTML = '<i class="fa fa-copy"></i>'; }, 2000);
        };
        bubble.appendChild(copyBtn);
        
        // Add Action Chips based on content
        const chipsDiv = document.createElement('div');
        chipsDiv.className = 'action-chips';
        let hasChips = false;
        
        if (text.includes('| --- |') || text.includes('|---|')) {
            chipsDiv.innerHTML += '<span class="chip" onclick="askQuestion(\'export this to excel\')"><i class="fa fa-file-excel"></i> Export Excel</span>';
            hasChips = true;
        }
        if (text.match(/EMP\d{3,}/)) {
            chipsDiv.innerHTML += '<span class="chip" onclick="askQuestion(\'show allocations for this employee\')"><i class="fa fa-laptop"></i> Show Allocations</span>';
            hasChips = true;
        }
        if (text.match(/AST\d{3,}/)) {
            chipsDiv.innerHTML += '<span class="chip" onclick="askQuestion(\'maintenance history\')"><i class="fa fa-tools"></i> Maintenance History</span>';
            hasChips = true;
        }
        
        if (hasChips) bubble.appendChild(chipsDiv);
    }

    const meta = document.createElement('div');
    meta.className = 'msg-meta';
    let metaContent = role === 'user' ? 'You • ' + now : 'Copilot • ' + now;
    if (type && role === 'bot') {
        let icon = 'circle';
        let typeLabel = type.replace('_', ' ');
        if (type === 'LIVE_DB' || type === 'RULE_BASED' || type === 'LOCAL_DB') { icon = 'database'; typeLabel = 'Live AMS Data'; }
        else if (type === 'FALLBACK_RULE_BASED') { icon = 'database'; typeLabel = 'Rule-based fallback'; }
        else if (type === 'GEMINI' || type === 'OPENAI') { icon = 'brain'; typeLabel = type + ' AI'; }
        else if (type === 'DOCUMENT_VAULT') { icon = 'file-alt'; typeLabel = 'Document Vault'; }
        
        metaContent += ' &nbsp;<span class="msg-type-badge"><i class="fa fa-' + icon + '"></i> ' + typeLabel + '</span>';
    }
    meta.innerHTML = metaContent;

    div.appendChild(bubble);
    div.appendChild(meta);

    // Feedback (thumbs up/down) - only on a real bot answer, not an error
    // bubble or a message with no question to attribute it to (e.g. the
    // initial greeting). This is the one signal this Copilot has never had
    // on whether a REAL answer was actually useful - see CopilotFeedbackServlet.
    if (role === 'bot' && status !== 'error' && question) {
        const feedback = document.createElement('span');
        feedback.className = 'msg-feedback';

        const up = document.createElement('button');
        up.className = 'msg-feedback-btn';
        up.title = 'This was helpful';
        up.innerHTML = '<i class="fa fa-thumbs-up"></i>';

        const down = document.createElement('button');
        down.className = 'msg-feedback-btn';
        down.title = 'This was not helpful';
        down.innerHTML = '<i class="fa fa-thumbs-down"></i>';

        const sendFeedback = (rating, clickedBtn, otherBtn) => {
            // Optimistic, one-shot: disable both immediately so a double
            // click can't send two ratings for the same answer, and show
            // the choice made regardless of whether the network call
            // actually lands - feedback is a nice-to-have signal, not
            // something worth surfacing an error banner over.
            up.disabled = true;
            down.disabled = true;
            clickedBtn.classList.add('msg-feedback-selected');
            otherBtn.classList.add('msg-feedback-dimmed');

            fetch('CopilotFeedbackServlet', {
                method: 'POST',
                headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
                body: 'question=' + encodeURIComponent(question)
                    + '&answer=' + encodeURIComponent(text)
                    + '&rating=' + encodeURIComponent(rating)
            }).catch(() => { /* best-effort - see class doc above */ });
        };

        up.onclick = () => sendFeedback('UP', up, down);
        down.onclick = () => sendFeedback('DOWN', down, up);

        feedback.appendChild(up);
        feedback.appendChild(down);
        meta.appendChild(feedback);
    }

    // Insert before typing indicator
    chatMessages.insertBefore(div, typingIndicator);
    scrollToBottom();
}

function scrollToBottom() {
    setTimeout(() => {
        chatMessages.scrollTop = chatMessages.scrollHeight;
    }, 50);
}

function clearChat() {
    const msgs = chatMessages.querySelectorAll('.msg:not(#typingIndicator)');
    msgs.forEach((m, i) => { if (i > 0) m.remove(); }); // keep welcome msg
    // Reset the cache's "previous question" pointer so the first message of
    // the new conversation is keyed as a fresh start, not as if it followed
    // whatever was last asked before clearing.
    CopilotCache.recordTurn(null);
}

// Voice Recognition using Web Speech API
document.addEventListener("DOMContentLoaded", function () {
    if (window.amsCopilotVoiceBound) return;
    window.amsCopilotVoiceBound = true;

    const micBtn = document.getElementById("micBtn");
    const input = document.getElementById("chatInput");
    const status = document.getElementById("copilotVoiceStatus");

    if (!micBtn || !input) {
        console.warn("AMS Copilot voice elements missing", {
            micBtn: !!micBtn,
            input: !!input
        });
        return;
    }

    const SpeechRecognition = window.SpeechRecognition || window.webkitSpeechRecognition;

    if (!SpeechRecognition) {
        if (status) status.textContent = "Voice input is not supported in this browser.";
        micBtn.disabled = true;
        return;
    }

    let recognition = null;
    let listening = false;
    let baseText = "";
    let finalTranscript = "";

    function correctVoiceTranscript(rawText) {
        if (!rawText) return "";

        let corrected = rawText.trim();

        const replacements = [
            [/\bpurchased calls\b/gi, "purchase cost"],
            [/\bpurchase calls\b/gi, "purchase cost"],
            [/\bpurchased cost\b/gi, "purchase cost"],
            [/\ball purchased cost\b/gi, "all purchase cost"],
            [/\basset coast\b/gi, "asset cost"],
            [/\bassets coast\b/gi, "assets cost"],
            [/\blap top\b/gi, "laptop"],
            [/\blap tops\b/gi, "laptops"],
            [/\bmaintainance\b/gi, "maintenance"],
            [/\bwarrenty\b/gi, "warranty"],
            [/\bcatagory\b/gi, "category"],
            [/\bvender\b/gi, "vendor"],
            [/\bemploy details\b/gi, "employee details"],
            [/\bemployees detail\b/gi, "employee details"],
            [/\bdepart ment\b/gi, "department"],
            [/\balloted\b/gi, "allocated"],
            [/\ballotment\b/gi, "allocation"],
            [/\ballot\b/gi, "allocate"],
            [/\bwritten records\b/gi, "return records"]
        ];

        replacements.forEach(function(rule) {
            corrected = corrected.replace(rule[0], rule[1]);
        });

        corrected = corrected.replace(/\s+/g, " ").trim();

        return corrected;
    }

    function setStatus(message) {
        console.log("Copilot voice:", message);
        if (status) status.textContent = message || "";
    }

    function writeToTextarea(text) {
        input.value = text;
        input.focus();

        if (typeof autoResize === "function") {
            autoResize(input);
        }

        input.dispatchEvent(new Event("input", { bubbles: true }));
        console.log("Textarea updated:", input.value);
    }

    function startVoice() {
        recognition = new SpeechRecognition();
        recognition.lang = "en-IN";
        recognition.interimResults = true;
        recognition.continuous = true;
        recognition.maxAlternatives = 1;

        baseText = input.value.trim();
        finalTranscript = "";

        recognition.onstart = function () {
            listening = true;
            micBtn.classList.add("listening");
            input.placeholder = "Listening...";
            setStatus("Listening... speak now");
            console.log("Speech started");
        };

        recognition.onresult = function (event) {
            let interimTranscript = "";

            console.log("Speech onresult fired. resultIndex:", event.resultIndex, "length:", event.results.length);

            for (let i = 0; i < event.results.length; i++) {
                const transcript = (event.results[i][0].transcript || "").trim();

                console.log("Speech chunk:", transcript, "isFinal:", event.results[i].isFinal);

                if (event.results[i].isFinal) {
                    if (transcript && !finalTranscript.includes(transcript)) {
                        finalTranscript += transcript + " ";
                    }
                } else {
                    interimTranscript += transcript + " ";
                }
            }

            const liveText = [baseText, finalTranscript, interimTranscript]
                .filter(Boolean)
                .join(" ")
                .replace(/\s+/g, " ")
                .trim();

            if (liveText) {
                writeToTextarea(liveText);
                if (interimTranscript.trim()) {
                    setStatus("Listening...");
                } else {
                    setStatus("Voice captured.");
                }
            } else {
                setStatus("Listening... speak clearly");
            }
        };

        recognition.onerror = function (event) {
            console.warn("Speech error:", event.error);

            if (event.error === "not-allowed" || event.error === "service-not-allowed") {
                setStatus("Microphone blocked by browser or Permissions-Policy.");
            } else if (event.error === "no-speech") {
                setStatus("No speech detected. Try again.");
            } else if (event.error === "audio-capture") {
                setStatus("No microphone found or microphone is busy.");
            } else {
                setStatus("Voice input failed: " + event.error);
            }
        };

        recognition.onend = function () {
            listening = false;
            micBtn.classList.remove("listening");
            input.placeholder = "Ask anything about your assets, employees, maintenance...";

            if (input.value.trim()) {
                setStatus("Voice captured.");
                
                const rawTranscript = input.value.trim();
                const correctedTranscript = correctVoiceTranscript(rawTranscript);
                
                const correctionBox = document.getElementById("voiceCorrectionBox");
                const correctionText = document.getElementById("voiceCorrectionText");
                const useBtn = document.getElementById("useVoiceCorrectionBtn");
                const keepBtn = document.getElementById("keepVoiceOriginalBtn");
                
                if (correctedTranscript && correctedTranscript.toLowerCase() !== rawTranscript.toLowerCase() && correctionBox) {
                    correctionText.textContent = correctedTranscript;
                    correctionBox.style.display = "block";
                    
                    useBtn.onclick = function() {
                        writeToTextarea(correctedTranscript);
                        correctionBox.style.display = "none";
                    };
                    
                    keepBtn.onclick = function() {
                        correctionBox.style.display = "none";
                        input.focus();
                    };
                }
            } else {
                setStatus("No voice text detected. Try again.");
            }

            console.log("Speech ended. Final textarea value:", input.value);
        };

        recognition.start();
    }

    function stopVoice() {
        if (recognition) {
            try {
                recognition.stop();
            } catch (e) {
                console.warn("Voice stop failed:", e);
            }
        }
    }

    micBtn.addEventListener("click", function (event) {
        event.preventDefault();

        if (listening) {
            stopVoice();
            return;
        }

        try {
            startVoice();
        } catch (err) {
            console.error("Failed to start voice recognition:", err);
            listening = false;
            micBtn.classList.remove("listening");
            setStatus("Failed to start voice recognition.");
        }
    });
});

// Sidebar active
document.addEventListener('DOMContentLoaded', () => {
    if (window.setActiveMenu) setActiveMenu('ams_copilot.jsp');
    chatInput.focus();
});
</script>
<script src="js/topbar-search.js?v=6000000"></script>
<script src="js/user-dropdown.js?v=dashboard-freeze-role-1"></script>
<script src="js/sidebar-role.js?v=dashboard-freeze-role-1"></script>
<script src="js/dashboard-actions.js?v=dashboard-freeze-role-1"></script>

<%--
    Fault, found live: "minimize sidebar" appeared completely dead on this
    page only. dashboard-actions.js (loaded just above, on every page that
    uses it) already binds its OWN click listener to .nav-toggle that does
    document.body.classList.toggle("sidebar-collapsed") - the same toggle
    every other page in the app relies on. This page ALSO bound a second,
    independent click listener doing the exact same classList.toggle() call
    (under a different localStorage key, irAmsSidebarState vs
    dashboard-actions.js's iramsDashboardSidebar). A single click fired BOTH
    listeners, toggling the class on then immediately back off in the same
    click - net visible effect: nothing ever happened. The
    data-ams-sidebar-bound guard below only stopped THIS script from
    double-binding itself across repeated DOMContentLoaded firings; it had
    no way to know a second, separate script already owned this button.
    settings.jsp has the same page-local pattern but does not load
    dashboard-actions.js, so it never collided - confirming this was a
    this-page-only conflict, not a bug in dashboard-actions.js itself.
    Removed rather than reconciled: dashboard-actions.js already does this
    correctly and consistently with every other page, so there is nothing
    left for a page-local override to add.
--%>

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
