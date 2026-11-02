<%@page contentType="text/html" pageEncoding="UTF-8"%>
<%@page import="com.mycompany.asset_management_system_ams.SettingsDAO"%>
<%@page import="com.mycompany.asset_management_system_ams.CopilotChatHistoryDAO"%>
<%@page import="com.mycompany.asset_management_system_ams.HtmlEscapeUtil"%>
<%@page import="java.util.List"%>
<%@page import="java.text.SimpleDateFormat"%>
<%@page import="java.util.Date"%>
<%
    // Same access rule as ams_copilot.jsp itself: any logged-in role can see
    // this page, because it only ever shows the CURRENT user's own history
    // (queried by their own user_id below) - there is nothing here for a
    // role check to gate.
    String username = (String) session.getAttribute("username");
    String role = (String) session.getAttribute("role");
    String displayName = (String) session.getAttribute("displayName");
    if (displayName == null) displayName = username;

    response.setHeader("Cache-Control", "no-cache,no-store,must-revalidate");
    response.setHeader("Pragma", "no-cache");
    response.setDateHeader("Expires", 0);

    if (username == null || role == null) {
        response.sendRedirect("login.jsp");
        return;
    }

    Object userIdObj = session.getAttribute("user_id");
    int userId = 0;
    if (userIdObj != null) {
        try { userId = Integer.parseInt(userIdObj.toString()); } catch (Exception ignored) {}
    }

    // Self-handling POST for "Clear All History" - same "a simple page
    // handles its own single action inline, no dedicated servlet" pattern
    // already used elsewhere in this codebase (e.g. resolve_maintenance.jsp).
    // A real, permanent delete - see CopilotChatHistoryDAO.deleteAllForUser's
    // own doc for why this is deliberately separate from the chat UI's
    // "Clear Chat" button, which only ever clears the visible screen.
    String clearedMsg = "";
    if ("POST".equalsIgnoreCase(request.getMethod()) && "clear_all".equals(request.getParameter("action"))) {
        if (userId > 0 && CopilotChatHistoryDAO.deleteAllForUser(userId)) {
            clearedMsg = "All chat history has been permanently deleted.";
        } else {
            clearedMsg = "Unable to clear history right now. Please try again.";
        }
    }

    String orgName = SettingsDAO.getOrgName();
    List<CopilotChatHistoryDAO.HistoryEntry> entries = CopilotChatHistoryDAO.listForUser(userId, 50);
    SimpleDateFormat dayFmt = new SimpleDateFormat("d MMM yyyy");
    SimpleDateFormat timeFmt = new SimpleDateFormat("h:mm a");
    String today = dayFmt.format(new Date());
    String yesterday = dayFmt.format(new Date(System.currentTimeMillis() - 24L * 60 * 60 * 1000));
%>
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width,initial-scale=1">
    <title>Chat History — AMS Copilot | <%= HtmlEscapeUtil.escape(orgName) %></title>
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.0/css/all.min.css">
    <link rel="stylesheet" href="css/ir-ams-railway-ui.css?v=copilot-v2">
    <link rel="stylesheet" href="css/ams_copilot.css?v=28001">
    <style>
        .history-wrap { max-width: 900px; margin: 0 auto; padding: 4px 4px 40px; }
        .history-back { display: inline-flex; align-items: center; gap: 8px; color: var(--ir-blue, #2563eb);
            font-weight: 700; font-size: 13px; text-decoration: none; margin-bottom: 14px; }
        .history-back:hover { text-decoration: underline; }
        .history-toolbar { display: flex; align-items: center; justify-content: space-between; gap: 12px;
            margin-bottom: 18px; flex-wrap: wrap; }
        .history-count { color: var(--ir-muted, #64748b); font-size: 13px; font-weight: 600; }
        .history-clear-btn { display: inline-flex; align-items: center; gap: 6px; padding: 8px 14px;
            border: 1.5px solid #fecaca; border-radius: 9px; background: #fff5f5; color: #b91c1c;
            font-size: 12px; font-weight: 700; cursor: pointer; }
        .history-clear-btn:hover { background: #fee2e2; }
        .history-flash { padding: 10px 14px; border-radius: 9px; background: #eff6ff; color: #1e3a8a;
            font-size: 13px; font-weight: 600; margin-bottom: 16px; border: 1px solid #bfdbfe; }
        .history-day-label { font-size: 12px; font-weight: 800; letter-spacing: .04em; text-transform: uppercase;
            color: var(--ir-muted, #64748b); margin: 26px 0 10px; }
        .history-day-label:first-of-type { margin-top: 4px; }
        .history-entry { border: 1px solid var(--ir-line, #e2e8f0); border-radius: 12px; padding: 14px 16px;
            margin-bottom: 10px; background: #fff; }
        .history-entry .h-question { font-weight: 700; color: #111827; font-size: 14px; margin-bottom: 6px;
            display: flex; align-items: baseline; justify-content: space-between; gap: 10px; }
        .history-entry .h-time { font-weight: 500; color: var(--ir-muted, #94a3b8); font-size: 11.5px; white-space: nowrap; }
        .history-entry .h-answer { color: #374151; font-size: 13px; line-height: 1.5; white-space: pre-wrap; }
        .history-entry .h-ask-again { display: inline-flex; align-items: center; gap: 6px; margin-top: 10px;
            font-size: 12px; font-weight: 700; color: var(--ir-blue, #2563eb); text-decoration: none; }
        .history-entry .h-ask-again:hover { text-decoration: underline; }
        .history-empty { text-align: center; padding: 60px 20px; color: var(--ir-muted, #64748b); }
        .history-empty i { font-size: 34px; color: #cbd5e1; margin-bottom: 12px; display: block; }
    </style>
</head>
<body class="railway-ui">
<div class="app">
    <jsp:include page="sidebar.jsp" />
    <main class="main">
        <jsp:include page="topbar.jsp" />
        <div class="main-scroll-content">
            <div class="history-wrap">
                <a class="history-back" href="ams_copilot.jsp"><i class="fa-solid fa-arrow-left"></i> Back to AMS Copilot</a>

                <section class="copilot-hero" style="margin-bottom:18px;">
                    <div class="copilot-hero-copy">
                        <span class="copilot-eyebrow"><i class="fa-solid fa-clock-rotate-left"></i> AMS Copilot</span>
                        <h1>Chat History</h1>
                        <p>Every question you've asked the AI Copilot and the answer it gave, kept across logins and devices.</p>
                    </div>
                </section>

                <% if (!clearedMsg.isEmpty()) { %>
                    <div class="history-flash"><i class="fa-solid fa-circle-info"></i> <%= HtmlEscapeUtil.escape(clearedMsg) %></div>
                <% } %>

                <div class="history-toolbar">
                    <span class="history-count"><%= entries.size() %> conversation<%= entries.size() == 1 ? "" : "s" %> stored (most recent 50 kept)</span>
                    <% if (!entries.isEmpty()) { %>
                        <form method="post" action="copilot_chat_history.jsp" onsubmit="return confirm('Permanently delete all of your AMS Copilot chat history? This cannot be undone.');" style="margin:0;">
                            <input type="hidden" name="action" value="clear_all">
                            <button type="submit" class="history-clear-btn"><i class="fa-solid fa-trash"></i> Clear All History</button>
                        </form>
                    <% } %>
                </div>

                <% if (entries.isEmpty()) { %>
                    <div class="history-empty">
                        <i class="fa-solid fa-comment-slash"></i>
                        <strong>No chat history yet.</strong>
                        <p>Ask the AMS Copilot something and it will show up here.</p>
                    </div>
                <% } else {
                    String lastDayLabel = null;
                    for (CopilotChatHistoryDAO.HistoryEntry entry : entries) {
                        String dayLabel;
                        String timeLabel;
                        if (entry.createdAt != null) {
                            String day = dayFmt.format(entry.createdAt);
                            dayLabel = day.equals(today) ? "Today" : (day.equals(yesterday) ? "Yesterday" : day);
                            timeLabel = timeFmt.format(entry.createdAt);
                        } else {
                            dayLabel = "Earlier";
                            timeLabel = "";
                        }
                        if (!dayLabel.equals(lastDayLabel)) {
                %>
                    <div class="history-day-label"><%= HtmlEscapeUtil.escape(dayLabel) %></div>
                <%
                            lastDayLabel = dayLabel;
                        }
                %>
                    <div class="history-entry">
                        <div class="h-question">
                            <span><i class="fa-solid fa-user" style="color:#94a3b8;margin-right:6px;"></i><%= HtmlEscapeUtil.escape(entry.question) %></span>
                            <span class="h-time"><%= HtmlEscapeUtil.escape(timeLabel) %></span>
                        </div>
                        <div class="h-answer"><%= HtmlEscapeUtil.escape(entry.answer) %></div>
                        <a class="h-ask-again" href="ams_copilot.jsp?q=<%= java.net.URLEncoder.encode(entry.question, "UTF-8") %>">
                            <i class="fa-solid fa-rotate-right"></i> Ask again
                        </a>
                    </div>
                <%
                    }
                } %>
            </div>
        </div>
    </main>
</div>

<script src="js/user-dropdown.js?v=5"></script>
<script src="js/sidebar-role.js?v=7000"></script>
<script src="js/topbar-search.js?v=global-search-ready-1"></script>
</body>
</html>
