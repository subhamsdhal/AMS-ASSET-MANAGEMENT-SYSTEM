<%@page contentType="text/html" pageEncoding="UTF-8"%>
<%@page import="java.sql.*" %>
<%@page import="com.mycompany.asset_management_system_ams.DBConnection" %>
<%@page import="com.mycompany.asset_management_system_ams.SettingsDAO" %>
<%
// Was decorative: Settings > Security > "Session Timeout (minutes)" saved to
// the DB and displayed back, but nothing read it - the real session length
// was a fixed 30 minutes from web.xml, invisible to the user until they
// clicked something and got bounced to login.jsp with no warning. Now
// LoginServlet actually applies this value to the session, and this widget
// shows a live countdown against that same number, ticking down every
// second and forcing a real logout when it reaches zero - not just a
// display, an actual client-side enforcement matching what the server will
// do anyway once the session truly expires.
int topbarSessionTimeoutMinutes = SettingsDAO.getSessionTimeout();
if (topbarSessionTimeoutMinutes < 1 || topbarSessionTimeoutMinutes > 1440) {
    topbarSessionTimeoutMinutes = 30;
}
int navApprovalsPending = 0;
try (Connection con = DBConnection.getConnection();
     PreparedStatement ps = con.prepareStatement("SELECT COUNT(*) FROM asset_requests ar JOIN employees e ON ar.employee_id = e.employee_id WHERE ar.request_status = 'PENDING'");
     ResultSet rs = ps.executeQuery()) {
    if (rs.next()) {
        navApprovalsPending = rs.getInt(1);
    }
} catch (Exception e) {
    navApprovalsPending = 0;
}
 

String topbarRole = session.getAttribute("role") != null ? ((String)session.getAttribute("role")).replace("_", " ") : "User";
String topbarUsername = session.getAttribute("username") != null ? (String)session.getAttribute("username") : "User";
String topbarInitial = topbarUsername.isEmpty() ? "U" : topbarUsername.substring(0, 1).toUpperCase();

// Opaque, non-sensitive per-login marker (see LoginServlet) so the
// session-timer countdown can tell logins apart without ever needing the
// real (HttpOnly, correctly unreadable-to-JS) JSESSIONID. "legacy-session"
// only ever applies to a session that was already open before this marker
// existed - it resolves itself the next time that user logs in.
String topbarSessionMarker = session.getAttribute("client_session_marker") != null
        ? (String) session.getAttribute("client_session_marker") : "legacy-session";
%>
<header class="topbar railway-topbar">
            <button class="nav-toggle" type="button" aria-label="Menu">
                <i class="fa-solid fa-bars"></i>
            </button>

            <a href="dashboard.jsp" class="topbar-title topbar-home-link" title="Open Dashboard">
                <h1>IR-AMS</h1>
                <span>Railway Asset Management System</span>
            </a>

            <button class="hq-selector" type="button" data-dashboard-menu="hq" aria-label="Railway unit menu">
                <i class="fa-solid fa-location-dot"></i>
                <div>
                    <strong>East Coast Railway</strong>
                    <span>Headquarters / Rail Sadan, Bhubaneswar</span>
                </div>
                <i class="fa-solid fa-angle-down"></i>
            </button>

            <div class="search-box">
                <i class="fa-solid fa-magnifying-glass"></i>
                <input type="text" id="globalSearch" placeholder="Search assets, holders, departments, sections, reports...">
            </div>

            <div class="top-right topbar-actions">
                <div class="control-active session-timer-pill" id="sessionTimerPill" title="Time remaining before automatic sign-out"
                     data-total-seconds="<%= topbarSessionTimeoutMinutes * 60 %>" data-context-path="<%= request.getContextPath() %>"
                     data-session-marker="<%= topbarSessionMarker %>">
                    <i class="fa-regular fa-clock"></i>
                    <span id="sessionTimerText">--:--</span>
                </div>

                <button class="control-active" type="button" data-dashboard-menu="control" aria-label="System control menu">
                    <i class="fa-solid fa-shield-halved"></i>
                    Control Active
                    <i class="fa-solid fa-angle-down"></i>
                </button>

                <a class="top-icon-btn" href="asset_requests.jsp" aria-label="Pending approvals" title="Open pending approvals">
                    <i class="fa-regular fa-bell"></i>
                    <% if (navApprovalsPending > 0) { %>
                    <span class="badge"><%= navApprovalsPending %></span>
                    <% } %>
                </a>


                <a class="top-icon-btn ai-copilot-topbar-btn" href="ams_copilot.jsp" aria-label="AI Copilot" title="Open AI Copilot">
                    <i class="fa-solid fa-robot"></i>
                    <span class="ai-pulse-dot" aria-hidden="true"></span>
                </a>


                <a class="top-icon-btn" href="dashboard_help.jsp" aria-label="Help and support" title="Open help and support">
                    <i class="fa-regular fa-circle-question"></i>
                </a>

                <div class="user-card">
                    <div class="avatar"><%= topbarInitial %></div>
                    <div>
                        <strong><%= topbarUsername %></strong>
                        <span style="text-transform:capitalize;"><%= topbarRole.toLowerCase() %></span>
                    </div>
                </div>
            </div>
        </header>

        <style>
            /* Reuses .control-active's exact pill geometry (same file, same
               class) so this sits in the topbar without looking like a
               different component - only the text color differs, and only
               when time is running low. */
            body.railway-ui .session-timer-pill {
                color: var(--ir-text, #06215f) !important;
                cursor: default !important;
            }
            body.railway-ui .session-timer-pill.session-timer-warning {
                color: #b45309 !important;
            }
            body.railway-ui .session-timer-pill.session-timer-critical {
                color: #b91c1c !important;
            }
        </style>

        <script src="${pageContext.request.contextPath}/js/session-timer.js?v=1"></script>

<script src="${pageContext.request.contextPath}/js/form-validation.js?v=1"></script>