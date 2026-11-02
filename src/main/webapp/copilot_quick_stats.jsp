<%@page contentType="text/html" pageEncoding="UTF-8"%>
<%@page import="com.mycompany.asset_management_system_ams.CopilotQuickStatsServlet.ModuleStats"%>
<%@page import="java.util.List"%>
<%@page import="java.text.SimpleDateFormat"%>
<%
    String username = (String) session.getAttribute("username");
    if (username == null) { response.sendRedirect("login.jsp"); return; }

    response.setHeader("Cache-Control", "no-cache,no-store,must-revalidate");
    response.setHeader("Pragma", "no-cache");
    response.setDateHeader("Expires", 0);

    @SuppressWarnings("unchecked")
    List<ModuleStats> stats = (List<ModuleStats>) request.getAttribute("stats");

    // This page only ever has real data when CopilotQuickStatsServlet
    // forwards to it - direct access (a bookmark, browser history, someone
    // retyping the URL) shows a blank "No data available" page otherwise
    // (confirmed live). The whole point of this page is to be reliable
    // during a live demo, so send it through the servlet instead of ever
    // showing that broken state.
    if (stats == null) {
        response.sendRedirect("CopilotQuickStatsServlet");
        return;
    }

    Long generatedAtMs = (Long) request.getAttribute("generatedAtMs");
    Long elapsedMs = (Long) request.getAttribute("elapsedMs");
    String generatedAt = generatedAtMs == null ? "" :
            new SimpleDateFormat("dd MMM yyyy, hh:mm:ss a").format(new java.util.Date(generatedAtMs));
%>
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width,initial-scale=1">
    <title>Quick Stats — Instant Records Added</title>
    <meta name="description" content="Instant, AI-free record counts by module and period — a presentation-safe fallback for the AI Copilot.">
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.0/css/all.min.css">
    <link rel="stylesheet" href="css/ir-ams-railway-ui.css?v=copilot-v2">
    <style>
        <%--
            Fault, found live: this page uses body class "ams-copilot-settings-page"
            (same as ams_copilot.jsp and settings.jsp) to pick up their shared
            look, but that class ALSO triggers page-specific sidebar-brand
            positioning in the shared CSS that ams_copilot.jsp and settings.jsp
            each separately compensate for with this exact block - copied here
            verbatim rather than duplicated-with-drift a third time, since it
            has already drifted once between those two (see their own comments).
            Without it, the logo/title block renders shifted left instead of
            centered - confirmed live via screenshot.
        --%>
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
    <style>
        .qs-wrap { padding: 24px 28px 40px; }
        .qs-head {
            display: flex; align-items: center; justify-content: space-between;
            flex-wrap: wrap; gap: 12px; margin-bottom: 18px;
        }
        .qs-title { display: flex; align-items: center; gap: 12px; }
        .qs-title i { font-size: 26px; color: var(--ir-blue, #2563eb); }
        .qs-title h1 { font-size: 22px; margin: 0; }
        .qs-title p { margin: 2px 0 0; font-size: 13px; color: var(--ir-muted, #64748b); }
        .qs-meta { font-size: 12px; color: var(--ir-muted, #64748b); text-align: right; }
        .qs-actions { display: flex; gap: 8px; }
        .qs-btn {
            display: inline-flex; align-items: center; gap: 6px;
            padding: 8px 14px; border-radius: 8px; font-size: 13px; font-weight: 600;
            border: 1.5px solid var(--ir-line, #e2e8f0); background: #fff; color: var(--ir-text, #1e293b);
            text-decoration: none; cursor: pointer;
        }
        .qs-btn.primary { background: var(--ir-blue, #2563eb); color: #fff; border-color: var(--ir-blue, #2563eb); }
        .qs-note {
            background: #eff6ff; border: 1px solid #bfdbfe; color: #1e40af;
            border-radius: 10px; padding: 10px 14px; font-size: 13px; margin-bottom: 20px;
            display: flex; align-items: center; gap: 10px;
        }
        table.qs-table {
            width: 100%; border-collapse: collapse; background: #fff;
            border: 1px solid var(--ir-line, #e2e8f0); border-radius: 12px; overflow: hidden;
        }
        .qs-table th, .qs-table td {
            padding: 16px 18px; text-align: center; border-bottom: 1px solid var(--ir-line, #eef2f7);
        }
        .qs-table th {
            background: #f8fafc; font-size: 12.5px; text-transform: uppercase; letter-spacing: .04em;
            color: var(--ir-muted, #64748b); font-weight: 700;
        }
        .qs-table th:first-child, .qs-table td:first-child {
            text-align: left; font-weight: 600; color: var(--ir-text, #1e293b); font-size: 14.5px;
        }
        .qs-table tbody tr:last-child td { border-bottom: none; }
        .qs-table tbody tr:hover { background: #fafcff; }
        .qs-num { font-size: 26px; font-weight: 800; color: var(--ir-blue, #1d4ed8); font-variant-numeric: tabular-nums; }
        .qs-num.zero { color: #94a3b8; }
        .qs-err { color: #b91c1c; font-size: 13px; font-weight: 600; }
        @media (max-width: 720px) {
            .qs-table th, .qs-table td { padding: 10px 8px; }
            .qs-num { font-size: 19px; }
        }
        @media print {
            aside.sidebar, header.topbar, .qs-actions { display: none !important; }
            .qs-wrap { padding: 0; }
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

            <div class="qs-wrap">
                <div class="qs-head">
                    <div class="qs-title">
                        <i class="fa-solid fa-bolt"></i>
                        <div>
                            <h1>Quick Stats — Records Added</h1>
                            <p>Direct database counts, no AI involved — instant and reliable for live demos.</p>
                        </div>
                    </div>
                    <div class="qs-actions">
                        <a class="qs-btn" href="ams_copilot.jsp"><i class="fa-solid fa-robot"></i> Back to AI Copilot</a>
                        <a class="qs-btn primary" href="CopilotQuickStatsServlet"><i class="fa-solid fa-rotate"></i> Refresh</a>
                    </div>
                </div>

                <div class="qs-note">
                    <i class="fa-solid fa-circle-info"></i>
                    <span>
                        "Added" means when the record was entered into IR-AMS — the same column
                        (<code>created_at</code>) the AI Copilot itself uses for "added"/"joined" questions.
                        Generated <%= safeQs(generatedAt) %><% if (elapsedMs != null) { %> in <%= elapsedMs %>ms<% } %>.
                    </span>
                </div>

                <table class="qs-table">
                    <thead>
                        <tr>
                            <th>Module</th>
                            <th>Today</th>
                            <th>Yesterday</th>
                            <th>This Month</th>
                            <th>Last Month</th>
                        </tr>
                    </thead>
                    <tbody>
                    <% if (stats != null) { for (ModuleStats s : stats) { %>
                        <tr>
                            <td><%= safeQs(s.label) %></td>
                            <% if (s.error != null) { %>
                                <td colspan="4" class="qs-err"><i class="fa-solid fa-triangle-exclamation"></i> <%= safeQs(s.error) %></td>
                            <% } else { %>
                                <td><span class="qs-num<%= s.today == 0 ? " zero" : "" %>"><%= s.today %></span></td>
                                <td><span class="qs-num<%= s.yesterday == 0 ? " zero" : "" %>"><%= s.yesterday %></span></td>
                                <td><span class="qs-num<%= s.thisMonth == 0 ? " zero" : "" %>"><%= s.thisMonth %></span></td>
                                <td><span class="qs-num<%= s.lastMonth == 0 ? " zero" : "" %>"><%= s.lastMonth %></span></td>
                            <% } %>
                        </tr>
                    <% } } else { %>
                        <tr><td colspan="5" class="qs-err">No data available.</td></tr>
                    <% } %>
                    </tbody>
                </table>
            </div>
        </div>
    </main>
</div>
</body>
</html>
<%!
    private String safeQs(String value) {
        if (value == null) return "";
        return value.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
                .replace("\"", "&quot;").replace("'", "&#39;");
    }
%>
