<%@page contentType="text/html" pageEncoding="UTF-8"%>
<%@page import="com.mycompany.asset_management_system_ams.AuditDAO"%>

<%
    // Fault: this used to hand-roll an INSERT INTO audit_logs(action, table_name,
    // remarks, ...) - none of those columns exist (the real ones are action_type,
    // module_name, action_details). Every logout silently failed to write an audit
    // row; the SQLException was caught and printStackTrace()'d, never surfaced.
    // Fixed by routing through the same AuditDAO.log() every other module uses -
    // correct columns, plus it now picks up IP/User-Agent automatically via
    // RequestContext (SecurityHeadersFilter binds it per-request).
    String username = (String) session.getAttribute("username");
    Object userIdAttr = session.getAttribute("user_id");

    if (username != null && userIdAttr != null) {
        try {
            int userId = Integer.parseInt(String.valueOf(userIdAttr));
            String reason = request.getParameter("reason");
            String remark = "session_timeout".equalsIgnoreCase(reason) || "timeout".equalsIgnoreCase(reason)
                    ? "User was automatically signed out after the session timed out: " + username
                    : "User logged out from system: " + username;
            AuditDAO.log(userId, "LOGOUT", "users", userId, remark);
        } catch (Exception e) {
            e.printStackTrace();
        }
    }

    session.invalidate();
    response.sendRedirect("login.jsp");
%>