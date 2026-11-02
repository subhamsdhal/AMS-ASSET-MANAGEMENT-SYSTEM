package com.mycompany.asset_management_system_ams;

import jakarta.servlet.http.HttpServletRequest;
import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;

public final class QrUrlUtil {

    private static final String QR_BASE_SETTING_KEY = "ams.qr.public.base_url";
    private static final String LEGACY_QR_BASE_SETTING_KEY = "ams.qr.base.url";

    private QrUrlUtil() {
    }

    public static String buildPublicAssetUrl(HttpServletRequest request, String token) {
        String baseUrl = resolveBaseUrl(request);
        return baseUrl + "/public_asset_view.jsp?token=" + safe(token);
    }

    public static String resolveBaseUrl(HttpServletRequest request) {
        String configured = getConfiguredPublicBaseUrl();

        if (!configured.isEmpty()) {
            return normalizeBaseUrl(configured);
        }

        String requestBase = getRequestBaseUrl(request);
        return normalizeBaseUrl(requestBase);
    }

    public static String normalizeBaseUrl(String value) {
        if (value == null) {
            return "";
        }

        String baseUrl = value.trim();

        if (baseUrl.endsWith("/public_asset_view.jsp")) {
            baseUrl = baseUrl.substring(0, baseUrl.length() - "/public_asset_view.jsp".length());
        }

        int tokenIndex = baseUrl.indexOf("/public_asset_view.jsp?token=");
        if (tokenIndex >= 0) {
            baseUrl = baseUrl.substring(0, tokenIndex);
        }

        while (baseUrl.endsWith("/")) {
            baseUrl = baseUrl.substring(0, baseUrl.length() - 1);
        }

        return baseUrl;
    }

    public static boolean isPublicBaseUrlReady() {
        return getPublicBaseUrlWarning().isEmpty();
    }

    public static String getPublicBaseUrlWarning() {
        String configured = getConfiguredPublicBaseUrlRaw();

        if (configured.isEmpty()) {
            return "Public QR base URL is not configured.";
        }

        String normalized = normalizeBaseUrl(configured);

        if (isLocalhostUrl(normalized)) {
            return "Public QR base URL points to localhost/127.0.0.1 and will not open from mobile devices.";
        }

        if (!normalized.startsWith("https://") && !normalized.startsWith("http://")) {
            return "Public QR base URL must start with http:// or https://.";
        }

        return "";
    }

    public static String getConfiguredPublicBaseUrlForDisplay() {
        return getConfiguredPublicBaseUrlRaw();
    }

    public static String getConfiguredPublicBaseUrl() {
        String value = getConfiguredPublicBaseUrlRaw();

        if (isLocalhostUrl(value)) {
            return "";
        }

        return value;
    }

    private static String getConfiguredPublicBaseUrlRaw() {
        String envUrl = System.getenv("AMS_PUBLIC_BASE_URL");
        if (envUrl != null && !envUrl.trim().isEmpty()) {
            return normalizeBaseUrl(envUrl);
        }

        String value = "";

        try (Connection con = DBConnection.getConnection()) {
            if (con == null) {
                return "";
            }

            ensureSystemSettingsTableExists(con);
            ensurePublicQrBaseUrlsTableExists(con);

            // First try to get the active URL from the new table
            String sqlNew = "SELECT base_url FROM public_qr_base_urls WHERE is_active = 1 LIMIT 1";
            try (PreparedStatement ps = con.prepareStatement(sqlNew)) {
                try (ResultSet rs = ps.executeQuery()) {
                    if (rs.next()) {
                        String raw = rs.getString("base_url");
                        if (raw != null && !raw.trim().isEmpty()) {
                            return normalizeBaseUrl(raw);
                        }
                    }
                }
            }

            // Fallback to old system_settings
            String sql = "SELECT setting_value "
                    + "FROM system_settings "
                    + "WHERE setting_key IN (?, ?, ?) "
                    + "AND setting_value IS NOT NULL "
                    + "AND TRIM(setting_value) <> '' "
                    + "ORDER BY FIELD(setting_key, ?, ?, ?) "
                    + "LIMIT 1";

            try (PreparedStatement ps = con.prepareStatement(sql)) {
                ps.setString(1, "ams.qr.mobile_tunnel_url");
                ps.setString(2, QR_BASE_SETTING_KEY);
                ps.setString(3, LEGACY_QR_BASE_SETTING_KEY);
                ps.setString(4, "ams.qr.mobile_tunnel_url");
                ps.setString(5, QR_BASE_SETTING_KEY);
                ps.setString(6, LEGACY_QR_BASE_SETTING_KEY);

                try (ResultSet rs = ps.executeQuery()) {
                    if (rs.next()) {
                        value = normalizeBaseUrl(rs.getString("setting_value"));
                    }
                }
            }

        } catch (Exception e) {
            System.err.println("QR Module DB Error: " + e.getMessage());
        }

        return value;
    }

    private static void ensurePublicQrBaseUrlsTableExists(Connection con) {
        String sql = "CREATE TABLE IF NOT EXISTS public_qr_base_urls ("
                + "id INT AUTO_INCREMENT PRIMARY KEY, "
                + "label VARCHAR(100), "
                + "provider_type VARCHAR(50), "
                + "base_url VARCHAR(255), "
                + "is_active TINYINT(1) DEFAULT 0, "
                + "created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP, "
                + "updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP"
                + ") ENGINE=InnoDB DEFAULT CHARSET=utf8mb4";

        try (PreparedStatement ps = con.prepareStatement(sql)) {
            ps.executeUpdate();
        } catch (Exception e) {
            System.err.println("QR Module DB Error: " + e.getMessage());
        }
    }

    private static void ensureSystemSettingsTableExists(Connection con) {
        String sql = "CREATE TABLE IF NOT EXISTS system_settings ("
                + "setting_id INT AUTO_INCREMENT PRIMARY KEY, "
                + "setting_key VARCHAR(100) UNIQUE, "
                + "setting_value TEXT, "
                + "setting_group VARCHAR(80), "
                + "description TEXT, "
                + "updated_by INT NULL, "
                + "updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP"
                + ") ENGINE=InnoDB DEFAULT CHARSET=utf8mb4";

        try (PreparedStatement ps = con.prepareStatement(sql)) {
            ps.executeUpdate();
        } catch (Exception e) {
            System.err.println("QR Module DB Error: " + e.getMessage());
        }
    }

    private static String getRequestBaseUrl(HttpServletRequest request) {
        String scheme = request.getHeader("X-Forwarded-Proto");

        if (scheme == null || scheme.trim().isEmpty()) {
            scheme = request.getScheme();
        }

        String host = request.getHeader("X-Forwarded-Host");

        if (host == null || host.trim().isEmpty()) {
            String serverName = request.getServerName();
            if ("localhost".equalsIgnoreCase(serverName) || "127.0.0.1".equals(serverName) || "0:0:0:0:0:0:0:1".equals(serverName)) {
                try {
                    serverName = java.net.InetAddress.getLocalHost().getHostAddress();
                } catch (Exception e) {
                    // fallback to localhost if we cannot determine the LAN IP
                }
            }
            host = serverName;

            int port = request.getServerPort();

            if (!("http".equalsIgnoreCase(scheme) && port == 80)
                    && !("https".equalsIgnoreCase(scheme) && port == 443)) {
                host = host + ":" + port;
            }
        }

        return scheme + "://" + host + request.getContextPath();
    }

    private static boolean isLocalhostUrl(String value) {
        String text = safe(value).toLowerCase();
        return text.contains("localhost")
                || text.contains("127.0.0.1")
                || text.contains("0.0.0.0")
                || text.contains("[::1]");
    }

    private static String safe(String value) {
        return value == null ? "" : value.trim();
    }
}
