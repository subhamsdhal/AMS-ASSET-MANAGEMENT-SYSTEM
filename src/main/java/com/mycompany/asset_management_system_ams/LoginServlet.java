package com.mycompany.asset_management_system_ams;

import java.io.IOException;
import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;

import jakarta.servlet.ServletException;
import jakarta.servlet.annotation.WebServlet;
import jakarta.servlet.http.HttpServlet;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import jakarta.servlet.http.HttpSession;

@WebServlet(name = "LoginServlet", urlPatterns = {"/LoginServlet"})
public class LoginServlet extends HttpServlet {

    private static final java.util.logging.Logger LOGGER = java.util.logging.Logger.getLogger(LoginServlet.class.getName());

    private static final int LOGIN_ALERT_THRESHOLD = 1;
    private static final int LOGIN_ALERT_WINDOW_MINUTES = 5;

    // Brute-force / credential-stuffing guard. Independent from the alerting
    // thresholds above: alerting tells an admin something happened, this
    // actually stops further attempts for a short cool-down window.
    private static final int LOGIN_LOCKOUT_THRESHOLD = 5;
    private static final int LOGIN_LOCKOUT_WINDOW_MINUTES = 15;

    /**
     * A direct GET (bookmark, browser refresh after POST, stray link) has no
     * form to process - send the visitor back to the login page instead of
     * letting the container's bare 405 page show.
     */
    @Override
    protected void doGet(HttpServletRequest request, HttpServletResponse response)
            throws ServletException, IOException {
        response.sendRedirect("login.jsp");
    }

    @Override
    protected void doPost(HttpServletRequest request, HttpServletResponse response)
            throws ServletException, IOException {

        Connection con = null;
        PreparedStatement ps = null;
        ResultSet rs = null;

        String usernameInput = request.getParameter("username");
        String passwordInput = request.getParameter("password");

        String usernameOrEmail = usernameInput == null ? "" : usernameInput.trim();
        // Passwords are never trimmed: a stored hash may legitimately have been
        // generated from a value with leading/trailing whitespace, and trimming
        // only on the login path (but not on password-set paths) silently locks
        // those accounts out. See CHANGELOG-fixes.md (Login-17).
        String password = passwordInput == null ? "" : passwordInput;

        try {
            con = DBConnection.getConnection();

            ensureLoginSecurityAttemptTable(con);

            String lockoutIp = RequestUtil.getClientIpAddress(request);
            if (isAccountLocked(con, usernameOrEmail, lockoutIp)) {
                try {
                    AuditDAO.log(
                            1,
                            "LOGIN_BLOCKED",
                            "users",
                            0,
                            "Login temporarily blocked after repeated failed attempts. Login ID: "
                                    + usernameOrEmail + ". Source IP: " + lockoutIp
                    );
                } catch (Exception auditEx) {
                    auditEx.printStackTrace();
                }
                response.sendRedirect("login.jsp?error=locked");
                return;
            }

            String sql = "SELECT user_id, username, password_crypt, current_role, employee_id, status, email, force_password_change "
                    + "FROM users "
                    + "WHERE (username = ? OR email = ?) "
                    + "AND status = 'ACTIVE'";

            ps = con.prepareStatement(sql);
            ps.setString(1, usernameOrEmail);
            ps.setString(2, usernameOrEmail);

            rs = ps.executeQuery();

            boolean authenticated = false;
            int userId = 0;
            String loggedUsername = null;
            String loggedEmail = null;
            String loggedRole = null;
            Integer employeeId = null;
            boolean forcePasswordChange = false;

            if (rs.next()) {

                String storedPassword = rs.getString("password_crypt");

                if (PasswordUtil.matches(password, storedPassword)) {
                    authenticated = true;
                    userId = rs.getInt("user_id");
                    loggedUsername = rs.getString("username");
                    loggedEmail = rs.getString("email");
                    employeeId = (Integer) rs.getObject("employee_id");
                    forcePasswordChange = rs.getBoolean("force_password_change");

                    // Fetch loggedRole from DB current_role
                    loggedRole = rs.getString("current_role").toUpperCase();
                }
            }

            if (authenticated) {

                // Session fixation hardening: never keep a pre-authentication session
                // id alive across the privilege boundary. Invalidate whatever session
                // (if any) the browser walked in with, then start a brand new one.
                HttpSession preAuthSession = request.getSession(false);
                if (preAuthSession != null) {
                    try {
                        preAuthSession.invalidate();
                    } catch (IllegalStateException alreadyInvalid) {
                        // already invalidated elsewhere in this request cycle - ignore
                    }
                }

                HttpSession session = request.getSession(true);

                // Non-sensitive, opaque marker identifying this one login for the
                // client-side session-timer countdown only (see session-timer.js) -
                // NOT the real JSESSIONID, which stays HttpOnly and unreadable to
                // JS by design. This value is printed into the page (topbar.jsp/
                // dashboard.jsp/add_maintenance.jsp) so the countdown can be keyed
                // per-login without weakening that protection: it authenticates
                // nothing and grants no capability by itself, so there's nothing
                // for an XSS read of it to steal.
                session.setAttribute("client_session_marker", java.util.UUID.randomUUID().toString());

                // "Remember me" extends the session lifetime instead of the
                // admin-configured timeout. This is a session-length preference
                // only - it does not bypass authentication on a future visit.
                boolean rememberMe = "on".equalsIgnoreCase(request.getParameter("remember"))
                        || "true".equalsIgnoreCase(request.getParameter("remember"));
                if (rememberMe) {
                    session.setMaxInactiveInterval(60 * 60 * 24 * 30); // 30 days
                } else {
                    // Fault: SettingsDAO.getSessionTimeout() (Settings > Security >
                    // "Session Timeout (minutes)") was saved to the database and
                    // displayed back on the settings page, but nothing ever read it
                    // to actually configure a session - every normal login silently
                    // used the container-level default instead (web.xml's
                    // <session-timeout>30</session-timeout>, fixed at deploy time,
                    // not admin-editable at runtime). This is the fix: apply the
                    // admin's configured value to the session that's actually created.
                    int timeoutMinutes = SettingsDAO.getSessionTimeout();
                    if (timeoutMinutes < 1 || timeoutMinutes > 1440) {
                        timeoutMinutes = 30;
                    }
                    session.setMaxInactiveInterval(timeoutMinutes * 60);
                }

                session.setAttribute("user_id", userId);
                session.setAttribute("username", loggedUsername);
                session.setAttribute("email", loggedEmail);

                if (employeeId != null) {
                    session.setAttribute("employee_id", employeeId);
                }

                // Dynamic Role Assignment Upgrade
                // Fault: the post-login redirect below used to branch on the raw
                // loggedRole (users.current_role) rather than this resolved
                // value - so an employee whose only elevation is a dynamic duty
                // assignment (e.g. DEPARTMENT_HEAD via role_assignment.jsp, with
                // current_role left at its original 'employee') had their real
                // session role set correctly here, but was still sent to
                // employee_dashboard.jsp on login instead of dashboard.jsp,
                // landing on the wrong (self-service) view for what their
                // account can actually do. Captured resolvedRole outside the
                // try so the redirect decision below can use it instead.
                String resolvedRole = loggedRole;
                try {
                    java.util.Map<String, Object> resolved = RoleAssignmentDAO.resolveEffectiveRoleForUser(loggedUsername, userId, employeeId, loggedRole);
                    resolvedRole = String.valueOf(resolved.get("role"));
                    session.setAttribute("role", resolved.get("role"));
                    session.setAttribute("roles", resolved.get("roles"));
                    java.util.List<Integer> departmentIds = (java.util.List<Integer>) resolved.get("departmentIds");
                    if (departmentIds != null && !departmentIds.isEmpty()) {
                        session.setAttribute("departmentIds", departmentIds);
                    }
                } catch (Exception dynamicEx) {
                    dynamicEx.printStackTrace();
                    session.setAttribute("role", loggedRole); // Fallback on failure
                }

                if (forcePasswordChange) {
                    session.setAttribute("force_password_change", true);
                }

                try {
                    AuditDAO.log(
                            userId,
                            "LOGIN",
                            "users",
                            userId,
                            "User logged into system: " + loggedUsername
                    );
                } catch (Exception auditEx) {
                    LOGGER.log(java.util.logging.Level.SEVERE, "Failed to log audit event", auditEx);
                }

                try {
                    NotificationEventService.sendLoginSuccessNotice(
                            getServletContext(),
                            userId,
                            loggedUsername,
                            loggedEmail,
                            loggedRole,
                            employeeId,
                            RequestUtil.getClientIpAddress(request),
                            safe(request.getHeader("User-Agent"), "N/A")
                    );
                } catch (Exception notificationEx) {
                    LOGGER.log(java.util.logging.Level.SEVERE, "Failed to send login success notice", notificationEx);
                }

                closeResultSet(rs);
                closeStatement(ps);

                if (forcePasswordChange) {
                    response.sendRedirect("change_password.jsp");
                } else if ("EMPLOYEE".equalsIgnoreCase(resolvedRole)) {
                    response.sendRedirect("employee_dashboard.jsp");
                } else {
                    response.sendRedirect("dashboard.jsp");
                }
                return;

            } else {

                closeResultSet(rs);
                closeStatement(ps);

                String sourceIpAddress = RequestUtil.getClientIpAddress(request);
                String userAgent = safe(request.getHeader("User-Agent"), "N/A");
                String browserName = detectBrowser(userAgent);
                String operatingSystem = detectOperatingSystem(userAgent);

                ensureLoginSecurityAttemptTable(con);

                LoginFailureDetails failureDetails = getLoginFailureDetails(con, usernameOrEmail);

                int attemptCount = recordFailedLoginAndGetCount(
                        con,
                        usernameOrEmail,
                        failureDetails.failureType,
                        sourceIpAddress,
                        userAgent,
                        failureDetails.recordId
                );

                try {
                    AuditDAO.log(
                            1,
                            "LOGIN_FAILED",
                            "users",
                            failureDetails.recordId,
                            failureDetails.auditMessage
                                    + ". Source IP: " + sourceIpAddress
                                    + ". Browser: " + browserName
                                    + ". System: " + operatingSystem
                                    + ". Authentication attempts within last "
                                    + LOGIN_ALERT_WINDOW_MINUTES
                                    + " minutes: "
                                    + attemptCount
                    );
                } catch (Exception auditEx) {
                    auditEx.printStackTrace();
                }

                boolean alertAlreadySent = hasAlertAlreadySentInWindow(
                        con,
                        usernameOrEmail,
                        failureDetails.failureType,
                        sourceIpAddress
                );

                boolean shouldSendAlert = shouldSendSecurityAlert(
                        failureDetails.failureType,
                        attemptCount,
                        alertAlreadySent
                );

                if (shouldSendAlert) {
                    markAttemptsAsAlerted(
                            con,
                            usernameOrEmail,
                            failureDetails.failureType,
                            sourceIpAddress
                    );

                    sendLoginSecurityAlertAsync(
                            usernameOrEmail,
                            failureDetails,
                            sourceIpAddress,
                            browserName,
                            operatingSystem,
                            userAgent,
                            attemptCount
                    );
                }

                response.sendRedirect("login.jsp?error=invalid");
                return;
            }

        } catch (Exception e) {
            e.printStackTrace();
            response.sendRedirect("login.jsp?error=server");

        } finally {
            try {
                closeResultSet(rs);
                closeStatement(ps);

                if (con != null) {
                    con.close();
                }
            } catch (Exception ex) {
                ex.printStackTrace();
            }
        }
    }

    private boolean shouldSendSecurityAlert(String failureType, int attemptCount, boolean alertAlreadySent) {

        if (alertAlreadySent) {
            return false;
        }

        if ("INACTIVE_USER_LOGIN_ATTEMPT".equals(failureType)) {
            return true;
        }

        if ("WRONG_PASSWORD".equals(failureType)) {
            return attemptCount >= LOGIN_ALERT_THRESHOLD;
        }

        if ("UNKNOWN_USERNAME".equals(failureType)) {
            return attemptCount >= LOGIN_ALERT_THRESHOLD;
        }

        return false;
    }

    private void ensureLoginSecurityAttemptTable(Connection con) {

        PreparedStatement ps = null;

        try {
            String sql = "CREATE TABLE IF NOT EXISTS login_security_attempts ("
                    + "attempt_id INT AUTO_INCREMENT PRIMARY KEY, "
                    + "attempted_username VARCHAR(100) NOT NULL, "
                    + "failure_type VARCHAR(80) NOT NULL, "
                    + "remote_address VARCHAR(100) NOT NULL, "
                    + "user_agent VARCHAR(500) NULL, "
                    + "matched_user_id INT DEFAULT 0, "
                    + "alert_sent TINYINT(1) DEFAULT 0, "
                    + "attempt_time TIMESTAMP DEFAULT CURRENT_TIMESTAMP, "
                    + "INDEX idx_login_security_attempts "
                    + "(attempted_username, failure_type, remote_address, attempt_time)"
                    + ")";

            ps = con.prepareStatement(sql);
            ps.executeUpdate();

        } catch (Exception e) {
            e.printStackTrace();

        } finally {
            closeStatement(ps);
        }
    }

    /**
     * True if this login identifier has racked up LOGIN_LOCKOUT_THRESHOLD or
     * more failed attempts (any failure type) within the lockout window.
     * Checked before the credential comparison, so it actually blocks further
     * guesses instead of just reporting on them after the fact.
     */
    private boolean isAccountLocked(Connection con, String attemptedUsername, String remoteAddress) {

        if (attemptedUsername == null || attemptedUsername.isEmpty()) {
            return false;
        }

        PreparedStatement ps = null;
        ResultSet rs = null;

        try {
            String sql = "SELECT COUNT(*) AS attempt_count "
                    + "FROM login_security_attempts "
                    + "WHERE attempted_username = ? "
                    + "AND attempt_time >= DATE_SUB(NOW(), INTERVAL ? MINUTE)";

            ps = con.prepareStatement(sql);
            ps.setString(1, limit(safe(attemptedUsername, "UNKNOWN"), 100));
            ps.setInt(2, LOGIN_LOCKOUT_WINDOW_MINUTES);

            rs = ps.executeQuery();

            if (rs.next() && rs.getInt("attempt_count") >= LOGIN_LOCKOUT_THRESHOLD) {
                return true;
            }

        } catch (Exception e) {
            e.printStackTrace();

        } finally {
            closeResultSet(rs);
            closeStatement(ps);
        }

        return false;
    }

    private int recordFailedLoginAndGetCount(
            Connection con,
            String attemptedUsername,
            String failureType,
            String remoteAddress,
            String userAgent,
            int matchedUserId
    ) {

        PreparedStatement ps = null;
        ResultSet rs = null;

        int attemptCount = 1;

        try {
            String insertSql = "INSERT INTO login_security_attempts "
                    + "(attempted_username, failure_type, remote_address, user_agent, matched_user_id, alert_sent) "
                    + "VALUES (?, ?, ?, ?, ?, 0)";

            ps = con.prepareStatement(insertSql);
            ps.setString(1, limit(safe(attemptedUsername, "UNKNOWN"), 100));
            ps.setString(2, limit(safe(failureType, "UNKNOWN"), 80));
            ps.setString(3, limit(safe(remoteAddress, "N/A"), 100));
            ps.setString(4, limit(safe(userAgent, "N/A"), 500));
            ps.setInt(5, matchedUserId);

            ps.executeUpdate();
            closeStatement(ps);
            ps = null;

            String countSql = "SELECT COUNT(*) AS attempt_count "
                    + "FROM login_security_attempts "
                    + "WHERE attempted_username = ? "
                    + "AND failure_type = ? "
                    + "AND remote_address = ? "
                    + "AND attempt_time >= DATE_SUB(NOW(), INTERVAL ? MINUTE)";

            ps = con.prepareStatement(countSql);
            ps.setString(1, limit(safe(attemptedUsername, "UNKNOWN"), 100));
            ps.setString(2, limit(safe(failureType, "UNKNOWN"), 80));
            ps.setString(3, limit(safe(remoteAddress, "N/A"), 100));
            ps.setInt(4, LOGIN_ALERT_WINDOW_MINUTES);

            rs = ps.executeQuery();

            if (rs.next()) {
                attemptCount = rs.getInt("attempt_count");
            }

        } catch (Exception e) {
            e.printStackTrace();

        } finally {
            closeResultSet(rs);
            closeStatement(ps);
        }

        return attemptCount;
    }

    private boolean hasAlertAlreadySentInWindow(
            Connection con,
            String attemptedUsername,
            String failureType,
            String remoteAddress
    ) {

        PreparedStatement ps = null;
        ResultSet rs = null;

        boolean alertAlreadySent = false;

        try {
            String sql = "SELECT COUNT(*) AS alert_count "
                    + "FROM login_security_attempts "
                    + "WHERE attempted_username = ? "
                    + "AND failure_type = ? "
                    + "AND remote_address = ? "
                    + "AND alert_sent = 1 "
                    + "AND attempt_time >= DATE_SUB(NOW(), INTERVAL ? MINUTE)";

            ps = con.prepareStatement(sql);
            ps.setString(1, limit(safe(attemptedUsername, "UNKNOWN"), 100));
            ps.setString(2, limit(safe(failureType, "UNKNOWN"), 80));
            ps.setString(3, limit(safe(remoteAddress, "N/A"), 100));
            ps.setInt(4, LOGIN_ALERT_WINDOW_MINUTES);

            rs = ps.executeQuery();

            if (rs.next()) {
                alertAlreadySent = rs.getInt("alert_count") > 0;
            }

        } catch (Exception e) {
            e.printStackTrace();

        } finally {
            closeResultSet(rs);
            closeStatement(ps);
        }

        return alertAlreadySent;
    }

    private void markAttemptsAsAlerted(
            Connection con,
            String attemptedUsername,
            String failureType,
            String remoteAddress
    ) {

        PreparedStatement ps = null;

        try {
            String sql = "UPDATE login_security_attempts "
                    + "SET alert_sent = 1 "
                    + "WHERE attempted_username = ? "
                    + "AND failure_type = ? "
                    + "AND remote_address = ? "
                    + "AND attempt_time >= DATE_SUB(NOW(), INTERVAL ? MINUTE)";

            ps = con.prepareStatement(sql);
            ps.setString(1, limit(safe(attemptedUsername, "UNKNOWN"), 100));
            ps.setString(2, limit(safe(failureType, "UNKNOWN"), 80));
            ps.setString(3, limit(safe(remoteAddress, "N/A"), 100));
            ps.setInt(4, LOGIN_ALERT_WINDOW_MINUTES);

            ps.executeUpdate();

        } catch (Exception e) {
            e.printStackTrace();

        } finally {
            closeStatement(ps);
        }
    }

    private LoginFailureDetails getLoginFailureDetails(Connection con, String usernameOrEmail) {

        LoginFailureDetails details = new LoginFailureDetails();

        details.failureType = "UNKNOWN_USERNAME";
        details.recordId = 0;
        details.targetUsername = usernameOrEmail;
        details.targetEmail = "N/A";
        details.targetRole = "N/A";
        details.targetStatus = "N/A";
        details.failureReason = "Login ID not registered";
        details.auditMessage = "Unsuccessful login attempt using unknown username/email: " + usernameOrEmail;

        PreparedStatement ps = null;
        ResultSet rs = null;

        try {
            String sql = "SELECT u.user_id, u.username, u.email, u.status, r.role_name "
                    + "FROM users u "
                    + "JOIN roles r ON u.role_id = r.role_id "
                    + "WHERE u.username = ? OR u.email = ? "
                    + "LIMIT 1";

            ps = con.prepareStatement(sql);
            ps.setString(1, usernameOrEmail);
            ps.setString(2, usernameOrEmail);

            rs = ps.executeQuery();

            if (rs.next()) {

                details.recordId = rs.getInt("user_id");
                details.targetUsername = safe(rs.getString("username"), usernameOrEmail);
                details.targetEmail = safe(rs.getString("email"), "N/A");
                details.targetRole = safe(rs.getString("role_name"), "N/A");
                details.targetStatus = safe(rs.getString("status"), "N/A");

                if ("INACTIVE".equalsIgnoreCase(details.targetStatus)) {
                    details.failureType = "INACTIVE_USER_LOGIN_ATTEMPT";
                    details.failureReason = "Inactive account used for login";
                    details.auditMessage = "Inactive account login attempt. Username: "
                            + details.targetUsername
                            + ", Email: "
                            + details.targetEmail
                            + ", Role: "
                            + details.targetRole
                            + ", Status: "
                            + details.targetStatus;

                } else {
                    details.failureType = "WRONG_PASSWORD";
                    details.failureReason = "Incorrect password";
                    details.auditMessage = "Unsuccessful login attempt due to incorrect password. Username: "
                            + details.targetUsername
                            + ", Email: "
                            + details.targetEmail
                            + ", Role: "
                            + details.targetRole
                            + ", Status: "
                            + details.targetStatus;
                }
            }

        } catch (Exception e) {
            e.printStackTrace();

        } finally {
            closeResultSet(rs);
            closeStatement(ps);
        }

        return details;
    }

    private void sendLoginSecurityAlertAsync(
            String enteredLoginId,
            LoginFailureDetails failureDetails,
            String sourceIpAddress,
            String browserName,
            String operatingSystem,
            String userAgent,
            int attemptCount
    ) {

        final String finalEnteredLoginId = enteredLoginId;
        final LoginFailureDetails finalFailureDetails = failureDetails;
        final String finalSourceIpAddress = sourceIpAddress;
        final String finalBrowserName = browserName;
        final String finalOperatingSystem = operatingSystem;
        final String finalUserAgent = userAgent;
        final int finalAttemptCount = attemptCount;

        Thread securityEmailThread = new Thread(new Runnable() {
            @Override
            public void run() {
                sendLoginSecurityAlertNow(
                        finalEnteredLoginId,
                        finalFailureDetails,
                        finalSourceIpAddress,
                        finalBrowserName,
                        finalOperatingSystem,
                        finalUserAgent,
                        finalAttemptCount
                );
            }
        });

        securityEmailThread.setDaemon(true);
        securityEmailThread.start();
    }

    private void sendLoginSecurityAlertNow(
            String enteredLoginId,
            LoginFailureDetails failureDetails,
            String sourceIpAddress,
            String browserName,
            String operatingSystem,
            String userAgent,
            int attemptCount
    ) {
        try {
            LoginSecurityRouting routing = getLoginSecurityRouting(failureDetails);

            String subject = getLoginSecuritySubject(failureDetails);

            String body = buildLoginSecurityEmailBody(
                    enteredLoginId,
                    failureDetails,
                    sourceIpAddress,
                    browserName,
                    operatingSystem,
                    userAgent,
                    attemptCount,
                    routing
            );

            NotificationHelper.sendNotification(
                    getServletContext(),
                    "ADMIN_SECURITY_ALERT",
                    NotificationHelper.MODULE_ADMIN_SECURITY,
                    failureDetails.recordId,
                    routing.toEmail,
                    routing.ccEmail,
                    "",
                    subject,
                    body
            );

        } catch (Exception e) {
            e.printStackTrace();
        }
    }

    private LoginSecurityRouting getLoginSecurityRouting(LoginFailureDetails failureDetails) {

        LoginSecurityRouting routing = new LoginSecurityRouting();

        routing.toEmail = NotificationRecipientResolver.getPrimaryEmailByRole("SUPER_ADMIN");
        routing.primaryRecipient = "Super Admin";
        routing.ccEmail = "";
        routing.copyMarkedTo = "";
        routing.routingBasis = "Restricted administrative review.";

        String role = safe(failureDetails.targetRole, "").toUpperCase();

        if ("EMPLOYEE".equals(role)) {
            String departmentHeadEmail = NotificationRecipientResolver.getPrimaryEmailByRole("DEPARTMENT_HEAD");

            routing.ccEmail = safe(departmentHeadEmail, "");
            routing.copyMarkedTo = routing.ccEmail.trim().isEmpty()
                    ? ""
                    : "Department Head (" + routing.ccEmail + ")";
            routing.routingBasis = "Employee account security event routed to Super Admin and Department Head.";
        } else if ("UNKNOWN_USERNAME".equals(failureDetails.failureType)) {
            routing.routingBasis = "Unknown login identity restricted to Super Admin review.";
        } else {
            routing.routingBasis = "Privileged or controlled-role account security event restricted to Super Admin review.";
        }

        return routing;
    }

    private String getLoginSecuritySubject(LoginFailureDetails failureDetails) {

        if ("INACTIVE_USER_LOGIN_ATTEMPT".equals(failureDetails.failureType)) {
            return "IR-AMS Access Security Alert | Inactive Account Review Required";
        }

        if ("UNKNOWN_USERNAME".equals(failureDetails.failureType)) {
            return "IR-AMS Access Security Alert | Unknown Login Identity";
        }

        return "IR-AMS Access Security Alert | Authentication Review Required";
    }

    private String buildLoginSecurityEmailBody(
            String enteredLoginId,
            LoginFailureDetails failureDetails,
            String sourceIpAddress,
            String browserName,
            String operatingSystem,
            String userAgent,
            int attemptCount,
            LoginSecurityRouting routing
    ) {

        StringBuilder detailsTable = new StringBuilder();

        detailsTable.append("<tr><th>Recipient:</th><td>").append(routing.primaryRecipient).append("</td></tr>");

        if (routing.copyMarkedTo != null && !routing.copyMarkedTo.trim().isEmpty()) {
            detailsTable.append("<tr><th>Copy Marked To:</th><td>").append(routing.copyMarkedTo).append("</td></tr>");
        }

        detailsTable.append("<tr><th>Severity:</th><td>").append(getSeverity(failureDetails)).append("</td></tr>");
        detailsTable.append("<tr><th>Category:</th><td>").append(getSecurityCategory(failureDetails)).append("</td></tr>");
        detailsTable.append("<tr><th>Status:</th><td>Access Denied</td></tr>");

        detailsTable.append("<tr><td colspan='2'>A security-relevant login event was recorded by IR-AMS. The system denied access and no active session was created.</td></tr>");

        detailsTable.append("<tr><td colspan='2' style='background-color: #f1f5f9; text-align: center;'><b>ACCOUNT DETAILS</b></td></tr>");
        detailsTable.append("<tr><th>Entered Login ID:</th><td>").append(safe(enteredLoginId, "N/A")).append("</td></tr>");

        if ("UNKNOWN_USERNAME".equals(failureDetails.failureType)) {
            detailsTable.append("<tr><th>Registered Account:</th><td>No matching account found</td></tr>");
        } else {
            // Fault (Medium-High, fixed): targetUsername/targetEmail are the literal
            // strings an UNAUTHENTICATED attacker types into the login form on a failed
            // attempt - the most attacker-controlled input in this entire sweep - and
            // were embedded unescaped into this admin-facing security alert email. Same
            // recurring class as audit/10-maintenance.md Finding 1, but reachable with
            // no account at all.
            detailsTable.append("<tr><th>Registered Username:</th><td>").append(HtmlEscapeUtil.escape(safe(failureDetails.targetUsername, "N/A"))).append("</td></tr>");
            detailsTable.append("<tr><th>Registered Email:</th><td>").append(HtmlEscapeUtil.escape(safe(failureDetails.targetEmail, "N/A"))).append("</td></tr>");
            detailsTable.append("<tr><th>Role:</th><td>").append(formatRoleName(failureDetails.targetRole)).append("</td></tr>");
            detailsTable.append("<tr><th>Account Status:</th><td>").append(formatNormalText(failureDetails.targetStatus)).append("</td></tr>");
        }

        detailsTable.append("<tr><td colspan='2' style='background-color: #f1f5f9; text-align: center;'><b>AUTHENTICATION REVIEW</b></td></tr>");
        detailsTable.append("<tr><th>Reason:</th><td>").append(HtmlEscapeUtil.escape(failureDetails.failureReason)).append("</td></tr>");

        if ("INACTIVE_USER_LOGIN_ATTEMPT".equals(failureDetails.failureType)) {
            detailsTable.append("<tr><th>Review Pattern:</th><td>Immediate review required for inactive account access attempt</td></tr>");
        } else {
            detailsTable.append("<tr><th>Review Pattern:</th><td>Unsuccessful authentication attempt recorded under login security monitoring</td></tr>");
        }

        detailsTable.append("<tr><td colspan='2' style='background-color: #f1f5f9; text-align: center;'><b>ACCESS SOURCE</b></td></tr>");
        detailsTable.append("<tr><th>Source IP Address:</th><td>").append(safe(sourceIpAddress, "N/A")).append("</td></tr>");
        detailsTable.append("<tr><th>Browser:</th><td>").append(safe(browserName, "Unknown Browser")).append("</td></tr>");
        detailsTable.append("<tr><th>Client System:</th><td>").append(safe(operatingSystem, "Unknown System")).append("</td></tr>");
        detailsTable.append("<tr><th>Event Source:</th><td>Web Login Portal</td></tr>");

        detailsTable.append("<tr><td colspan='2' style='background-color: #f1f5f9; text-align: center;'><b>ROUTING BASIS</b></td></tr>");
        detailsTable.append("<tr><td colspan='2'>").append(routing.routingBasis).append("</td></tr>");

        detailsTable.append("<tr><td colspan='2' style='background-color: #f1f5f9; text-align: center;'><b>TECHNICAL REFERENCE</b></td></tr>");
        detailsTable.append("<tr><th>User-Agent:</th><td>").append(safe(userAgent, "N/A")).append("</td></tr>");

        String actionNote = getRecommendedReview(failureDetails);

        return NotificationHelper.buildHtmlEmail("", "Access Security Alert", detailsTable.toString(), actionNote);
    }

    private String getSeverity(LoginFailureDetails failureDetails) {

        if ("INACTIVE_USER_LOGIN_ATTEMPT".equals(failureDetails.failureType)) {
            return "High";
        }

        if ("WRONG_PASSWORD".equals(failureDetails.failureType)) {
            String role = safe(failureDetails.targetRole, "").toUpperCase();

            if (("SUPER_ADMIN".equals(role) || "ADMIN".equals(role))
                    || "ASSET_MANAGER".equals(role)
                    || "DEPARTMENT_HEAD".equals(role)
                    || "AUDITOR".equals(role)) {
                return "High";
            }

            return "Medium";
        }

        if ("UNKNOWN_USERNAME".equals(failureDetails.failureType)) {
            return "Medium";
        }

        return "Medium";
    }

    private String getSecurityCategory(LoginFailureDetails failureDetails) {

        if ("INACTIVE_USER_LOGIN_ATTEMPT".equals(failureDetails.failureType)) {
            return "Inactive Account Access Attempt";
        }

        if ("WRONG_PASSWORD".equals(failureDetails.failureType)) {
            return "Authentication Failure Monitoring";
        }

        if ("UNKNOWN_USERNAME".equals(failureDetails.failureType)) {
            return "Unknown Login Identity";
        }

        return "Access Security Monitoring";
    }

    private String getRecommendedReview(LoginFailureDetails failureDetails) {

        if ("INACTIVE_USER_LOGIN_ATTEMPT".equals(failureDetails.failureType)) {
            return "Review the inactive account and confirm whether the access attempt was authorised. "
                    + "Keep the account disabled if the activity is not verified.";
        }

        if ("UNKNOWN_USERNAME".equals(failureDetails.failureType)) {
            return "Review the entered login ID and source IP address. "
                    + "If similar activity continues, consider server-level monitoring or blocking.";
        }

        return "Verify whether the account holder attempted to access IR-AMS. "
                + "If the activity is not authorised, review audit logs and reset the account credentials.";
    }

    private String detectBrowser(String userAgent) {

        String ua = safe(userAgent, "").toLowerCase();

        if (ua.isEmpty()) {
            return "Unknown Browser";
        }

        if (ua.contains("edg/")) {
            return "Microsoft Edge " + extractVersion(userAgent, "Edg/");
        }

        if (ua.contains("opr/")) {
            return "Opera " + extractVersion(userAgent, "OPR/");
        }

        if (ua.contains("samsungbrowser/")) {
            return "Samsung Internet " + extractVersion(userAgent, "SamsungBrowser/");
        }

        if (ua.contains("chrome/") && !ua.contains("edg/") && !ua.contains("opr/")) {
            return "Google Chrome " + extractVersion(userAgent, "Chrome/");
        }

        if (ua.contains("firefox/")) {
            return "Mozilla Firefox " + extractVersion(userAgent, "Firefox/");
        }

        if (ua.contains("safari/") && ua.contains("version/") && !ua.contains("chrome/")) {
            return "Safari " + extractVersion(userAgent, "Version/");
        }

        if (ua.contains("msie")) {
            return "Internet Explorer";
        }

        if (ua.contains("trident/")) {
            return "Internet Explorer";
        }

        return "Unknown Browser";
    }

    private String detectOperatingSystem(String userAgent) {

        String ua = safe(userAgent, "").toLowerCase();

        if (ua.contains("windows nt 10.0")) {
            return "Windows 10/11";
        }

        if (ua.contains("windows nt 6.3")) {
            return "Windows 8.1";
        }

        if (ua.contains("windows nt 6.2")) {
            return "Windows 8";
        }

        if (ua.contains("windows nt 6.1")) {
            return "Windows 7";
        }

        if (ua.contains("mac os x")) {
            return "macOS";
        }

        if (ua.contains("android")) {
            return "Android";
        }

        if (ua.contains("iphone") || ua.contains("ipad")) {
            return "iOS";
        }

        if (ua.contains("linux")) {
            return "Linux";
        }

        return "Unknown System";
    }

    private String extractVersion(String userAgent, String marker) {

        try {
            int startIndex = userAgent.indexOf(marker);

            if (startIndex == -1) {
                return "";
            }

            startIndex = startIndex + marker.length();

            int endIndex = userAgent.indexOf(" ", startIndex);

            if (endIndex == -1) {
                endIndex = userAgent.length();
            }

            String version = userAgent.substring(startIndex, endIndex).trim();

            if (version.contains(".")) {
                String[] parts = version.split("\\.");
                return parts[0];
            }

            return version;

        } catch (Exception e) {
            return "";
        }
    }

    private String formatRoleName(String roleName) {

        if (roleName == null || roleName.trim().isEmpty()) {
            return "N/A";
        }

        return roleName.trim().replace("_", " ");
    }

    private String formatNormalText(String value) {

        if (value == null || value.trim().isEmpty()) {
            return "N/A";
        }

        String text = value.trim().replace("_", " ").toLowerCase();
        return text.substring(0, 1).toUpperCase() + text.substring(1);
    }

    private String safe(String value, String fallback) {
        if (value == null || value.trim().isEmpty()) {
            return fallback;
        }

        return value.trim();
    }

    private String limit(String value, int maxLength) {
        String cleanValue = safe(value, "");

        if (cleanValue.length() <= maxLength) {
            return cleanValue;
        }

        return cleanValue.substring(0, maxLength);
    }

    private void closeResultSet(ResultSet rs) {
        try {
            if (rs != null) {
                rs.close();
            }
        } catch (Exception e) {
            e.printStackTrace();
        }
    }

    private void closeStatement(PreparedStatement ps) {
        try {
            if (ps != null) {
                ps.close();
            }
        } catch (Exception e) {
            e.printStackTrace();
        }
    }

    private static class LoginFailureDetails {

        String failureType;
        int recordId;
        String targetUsername;
        String targetEmail;
        String targetRole;
        String targetStatus;
        String failureReason;
        String auditMessage;
    }

    private static class LoginSecurityRouting {

        String toEmail;
        String ccEmail;
        String primaryRecipient;
        String copyMarkedTo;
        String routingBasis;
    }
}