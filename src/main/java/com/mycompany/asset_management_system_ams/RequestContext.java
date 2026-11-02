package com.mycompany.asset_management_system_ams;

/**
 * RequestContext - carries the current HTTP request's client IP and
 * User-Agent for the lifetime of one request, via ThreadLocal.
 *
 * Why this exists: AuditDAO.log() is called from ~40+ places across the
 * codebase with no HttpServletRequest in scope at most of those call sites
 * (it's a static DAO method, often called from deep inside a DAO or service
 * class). Threading a request parameter through every one of those call
 * sites would be a huge, invasive diff. Instead, SecurityHeadersFilter
 * (which already runs on every request, urlPatterns "/*") populates this
 * ThreadLocal once per request; AuditDAO reads it internally when writing
 * the ip_address/user_agent columns that already existed in audit_logs but
 * were never populated.
 *
 * Tomcat reuses worker threads across requests, so the filter MUST clear
 * this in a finally block after each request - never rely on it being
 * naturally overwritten, or a value could leak into a later request on the
 * same thread (e.g. a background/system-triggered audit log picking up a
 * stale IP from whatever request last ran on that thread).
 */
public final class RequestContext {

    private static final ThreadLocal<String> IP_ADDRESS = new ThreadLocal<>();
    private static final ThreadLocal<String> USER_AGENT = new ThreadLocal<>();

    private RequestContext() {
    }

    static void set(String ipAddress, String userAgent) {
        IP_ADDRESS.set(ipAddress);
        USER_AGENT.set(userAgent);
    }

    static void clear() {
        IP_ADDRESS.remove();
        USER_AGENT.remove();
    }

    /** Never null - returns "" if no request is currently bound on this thread. */
    public static String getIpAddress() {
        String value = IP_ADDRESS.get();
        return value == null ? "" : value;
    }

    /** Never null - returns "" if no request is currently bound on this thread. */
    public static String getUserAgent() {
        String value = USER_AGENT.get();
        return value == null ? "" : value;
    }
}
