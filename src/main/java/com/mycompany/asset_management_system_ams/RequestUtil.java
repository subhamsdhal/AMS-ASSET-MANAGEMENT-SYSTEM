package com.mycompany.asset_management_system_ams;

import jakarta.servlet.http.HttpServletRequest;

/**
 * RequestUtil — small shared helpers for reading request metadata.
 *
 * getClientIpAddress() was previously duplicated inside LoginServlet only;
 * it is pulled out here so the new account-recovery servlets (Forgot
 * Password / Activate Account) can reuse the exact same proxy-header
 * handling instead of a fourth ad-hoc copy. See CHANGELOG-fixes.md.
 */
public class RequestUtil {

    private RequestUtil() {
        // Utility class — do not instantiate
    }

    public static String getClientIpAddress(HttpServletRequest request) {

        String ipAddress = getValidHeader(request, "CF-Connecting-IP");

        if (!ipAddress.isEmpty()) {
            return normalizeIp(ipAddress);
        }

        ipAddress = getValidHeader(request, "True-Client-IP");

        if (!ipAddress.isEmpty()) {
            return normalizeIp(ipAddress);
        }

        ipAddress = getValidHeader(request, "X-Forwarded-For");

        if (!ipAddress.isEmpty()) {
            return normalizeIp(ipAddress.split(",")[0].trim());
        }

        ipAddress = getValidHeader(request, "X-Real-IP");

        if (!ipAddress.isEmpty()) {
            return normalizeIp(ipAddress);
        }

        ipAddress = getValidHeader(request, "Proxy-Client-IP");

        if (!ipAddress.isEmpty()) {
            return normalizeIp(ipAddress);
        }

        ipAddress = getValidHeader(request, "WL-Proxy-Client-IP");

        if (!ipAddress.isEmpty()) {
            return normalizeIp(ipAddress);
        }

        ipAddress = request.getRemoteAddr();

        return normalizeIp(ipAddress);
    }

    private static String getValidHeader(HttpServletRequest request, String headerName) {

        String value = request.getHeader(headerName);

        if (value == null) {
            return "";
        }

        value = value.trim();

        if (value.isEmpty()) {
            return "";
        }

        if ("unknown".equalsIgnoreCase(value)) {
            return "";
        }

        return value;
    }

    private static String normalizeIp(String ipAddress) {

        if (ipAddress == null || ipAddress.trim().isEmpty()) {
            return "N/A";
        }

        ipAddress = ipAddress.trim();

        if ("0:0:0:0:0:0:0:1".equals(ipAddress) || "::1".equals(ipAddress)) {
            return "127.0.0.1 (localhost)";
        }

        return ipAddress;
    }

    /** Scheme + host + port + context path, e.g. https://ams.example.org — used to build absolute links in emails. */
    public static String buildAppBaseUrl(HttpServletRequest request) {
        int port = request.getServerPort();
        boolean defaultPort = (port == 80 || port == 443);
        return request.getScheme() + "://" + request.getServerName()
                + (defaultPort ? "" : ":" + port)
                + request.getContextPath();
    }
}
