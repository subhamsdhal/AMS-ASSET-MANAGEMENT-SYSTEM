package com.mycompany.asset_management_system_ams;

import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.Types;

public class AuditDAO {

    public static void log(Integer userId, String action, String tableName, Integer recordId, String remarks) {

        String sql = "INSERT INTO audit_logs "
                + "(user_id, username, user_role, module_name, action_type, record_id, action_details, ip_address, user_agent) "
                + "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)";

        try (Connection con = DBConnection.getConnection();
             PreparedStatement ps = con.prepareStatement(sql)) {

            UserAuditInfo userInfo = getUserAuditInfo(con, userId);

            if (userInfo.userId == null || userInfo.userId <= 0) {
                ps.setNull(1, Types.INTEGER);
            } else {
                ps.setInt(1, userInfo.userId);
            }

            ps.setString(2, userInfo.username);
            ps.setString(3, userInfo.userRole);
            ps.setString(4, safeValue(tableName, "SYSTEM"));
            ps.setString(5, safeValue(action, "GENERAL_ACTION"));

            if (recordId == null) {
                ps.setString(6, null);
            } else {
                ps.setString(6, String.valueOf(recordId));
            }

            ps.setString(7, safeValue(remarks, ""));
            // Columns already existed in schema.sql but were never populated -
            // this is the fix. RequestContext is bound per-request by
            // SecurityHeadersFilter; a background/system-triggered log call
            // (no request on this thread) writes empty strings, not a stale
            // value from an earlier request.
            ps.setString(8, truncate(RequestContext.getIpAddress(), 60));
            ps.setString(9, truncate(RequestContext.getUserAgent(), 255));

            ps.executeUpdate();

        } catch (Exception e) {
            System.err.println("AuditDAO Error: " + e.getMessage());
        }
    }

    public static void log(Integer userId, String action, String tableName, String recordId, String remarks) {

        String sql = "INSERT INTO audit_logs "
                + "(user_id, username, user_role, module_name, action_type, record_id, action_details, ip_address, user_agent) "
                + "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)";

        try (Connection con = DBConnection.getConnection();
             PreparedStatement ps = con.prepareStatement(sql)) {

            UserAuditInfo userInfo = getUserAuditInfo(con, userId);

            if (userInfo.userId == null || userInfo.userId <= 0) {
                ps.setNull(1, Types.INTEGER);
            } else {
                ps.setInt(1, userInfo.userId);
            }

            ps.setString(2, userInfo.username);
            ps.setString(3, userInfo.userRole);
            ps.setString(4, safeValue(tableName, "SYSTEM"));
            ps.setString(5, safeValue(action, "GENERAL_ACTION"));
            ps.setString(6, safeValue(recordId, null));
            ps.setString(7, safeValue(remarks, ""));
            ps.setString(8, truncate(RequestContext.getIpAddress(), 60));
            ps.setString(9, truncate(RequestContext.getUserAgent(), 255));

            ps.executeUpdate();

        } catch (Exception e) {
            System.err.println("AuditDAO Error: " + e.getMessage());
        }
    }

    /** Defensive truncation - ip_address/user_agent are bounded varchar columns. */
    private static String truncate(String value, int maxLength) {
        if (value == null) {
            return "";
        }
        return value.length() <= maxLength ? value : value.substring(0, maxLength);
    }

    private static UserAuditInfo getUserAuditInfo(Connection con, Integer userId) {

        UserAuditInfo info = new UserAuditInfo();

        if (userId == null || userId <= 0) {
            return info;
        }

        String sql = "SELECT u.user_id, u.username, r.role_name "
                + "FROM users u "
                + "LEFT JOIN roles r ON u.role_id = r.role_id "
                + "WHERE u.user_id = ? "
                + "LIMIT 1";

        try (PreparedStatement ps = con.prepareStatement(sql)) {

            ps.setInt(1, userId);

            try (ResultSet rs = ps.executeQuery()) {

                if (rs.next()) {
                    info.userId = rs.getInt("user_id");
                    info.username = rs.getString("username");
                    info.userRole = rs.getString("role_name");
                }
            }

        } catch (Exception e) {
            System.err.println("AuditDAO Error: " + e.getMessage());
        }

        return info;
    }

    private static String safeValue(String value, String defaultValue) {

        if (value == null || value.trim().isEmpty()) {
            return defaultValue;
        }

        return value.trim();
    }

    private static class UserAuditInfo {

        private Integer userId;
        private String username;
        private String userRole;

        private UserAuditInfo() {
            this.userId = null;
            this.username = null;
            this.userRole = null;
        }
    }
}
