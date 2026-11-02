package com.mycompany.asset_management_system_ams;

import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.Timestamp;

/**
 * PasswordResetDAO — CRUD for password_reset_tokens, shared by the
 * "Forgot password?" reset flow and the "Sign up" account-activation flow
 * (they differ only by token_type and by what the servlet does once a valid
 * token comes back — see ResetPasswordServlet).
 *
 * ensureTable() mirrors the defensive CREATE TABLE IF NOT EXISTS pattern
 * LoginServlet already uses for login_security_attempts, so a deployment
 * that hasn't run migrations/002_password_reset_and_activation.sql yet
 * still works rather than 500ing.
 */
public class PasswordResetDAO {

    public static final String TYPE_RESET = "RESET";
    public static final String TYPE_ACTIVATION = "ACTIVATION";

    private PasswordResetDAO() {
        // Utility class — do not instantiate
    }

    public static void ensureTable(Connection con) {
        String sql = "CREATE TABLE IF NOT EXISTS password_reset_tokens ("
                + "token_id INT AUTO_INCREMENT PRIMARY KEY, "
                + "user_id INT NOT NULL, "
                + "token_hash VARCHAR(128) NOT NULL, "
                + "token_type ENUM('RESET','ACTIVATION') NOT NULL DEFAULT 'RESET', "
                + "expires_at TIMESTAMP NOT NULL, "
                + "used_at TIMESTAMP NULL DEFAULT NULL, "
                + "requested_ip VARCHAR(100) NULL, "
                + "created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP, "
                + "UNIQUE KEY uk_prt_token_hash (token_hash), "
                + "KEY idx_prt_user (user_id), "
                + "KEY idx_prt_user_type_time (user_id, token_type, created_at)"
                + ")";

        try (PreparedStatement ps = con.prepareStatement(sql)) {
            ps.executeUpdate();
        } catch (Exception e) {
            e.printStackTrace();
        }

        // Fault (Critical): CREATE TABLE IF NOT EXISTS is a no-op the moment a
        // table with this name already exists - it does NOT reconcile columns.
        // A pre-existing, differently-shaped password_reset_tokens table (an
        // older, incompatible prototype: token/used/expires_at/created_at only -
        // no token_hash, token_type, used_at, or requested_ip) was silently
        // shadowing this one. Confirmed live: every createToken()/
        // countRecentTokens()/resolveValidToken() call was throwing
        // SQLSyntaxErrorException ("Unknown column 'token_hash'"/'token_type'),
        // swallowed by each method's own try/catch, so BOTH the "Forgot
        // password?" reset flow and the "Sign up" self-activation flow (which
        // shares this table) showed the user a friendly "check your email"
        // confirmation while silently never creating a token or sending an
        // email. Fix: detect the missing new-schema signature column and
        // migrate the existing table in place instead of assuming CREATE TABLE
        // IF NOT EXISTS already handled it.
        migrateLegacySchemaIfNeeded(con);
    }

    private static void migrateLegacySchemaIfNeeded(Connection con) {
        if (columnExists(con, "password_reset_tokens", "token_hash")) {
            return; // already on the current schema
        }

        try (PreparedStatement ps = con.prepareStatement(
                "ALTER TABLE password_reset_tokens "
                        + "ADD COLUMN token_hash VARCHAR(128) NULL, "
                        + "ADD COLUMN token_type ENUM('RESET','ACTIVATION') NOT NULL DEFAULT 'RESET', "
                        + "ADD COLUMN used_at TIMESTAMP NULL DEFAULT NULL, "
                        + "ADD COLUMN requested_ip VARCHAR(100) NULL")) {
            ps.executeUpdate();
        } catch (Exception e) {
            e.printStackTrace();
            return;
        }

        // Any rows carrying the old schema were written by code that no longer
        // exists and can never resolve as a valid token going forward (nothing
        // populates their new token_hash, so resolveValidToken()'s lookup can
        // never match them) - these are short-lived, already-expired-by-now
        // reset/activation links, not data worth preserving. Clear them so the
        // table starts clean rather than accumulating permanent dead rows.
        try (PreparedStatement ps = con.prepareStatement("DELETE FROM password_reset_tokens WHERE token_hash IS NULL")) {
            ps.executeUpdate();
        } catch (Exception e) {
            e.printStackTrace();
        }

        try (PreparedStatement ps = con.prepareStatement(
                "ALTER TABLE password_reset_tokens MODIFY COLUMN token_hash VARCHAR(128) NOT NULL")) {
            ps.executeUpdate();
        } catch (Exception e) {
            e.printStackTrace();
        }

        try (PreparedStatement ps = con.prepareStatement(
                "ALTER TABLE password_reset_tokens ADD UNIQUE KEY uk_prt_token_hash (token_hash)")) {
            ps.executeUpdate();
        } catch (Exception e) {
            e.printStackTrace();
        }

        try (PreparedStatement ps = con.prepareStatement(
                "ALTER TABLE password_reset_tokens ADD KEY idx_prt_user_type_time (user_id, token_type, created_at)")) {
            ps.executeUpdate();
        } catch (Exception e) {
            e.printStackTrace();
        }

        // Old columns (token/used) from the legacy shape are dropped last, and
        // only if still present - left as dead columns would be harmless, but
        // dropping keeps the live schema matching migrations/002_password_reset_
        // and_activation.sql exactly, so a fresh install and a self-healed
        // upgrade end up identical.
        if (columnExists(con, "password_reset_tokens", "token")) {
            try (PreparedStatement ps = con.prepareStatement("ALTER TABLE password_reset_tokens DROP COLUMN token")) {
                ps.executeUpdate();
            } catch (Exception e) {
                e.printStackTrace();
            }
        }
        if (columnExists(con, "password_reset_tokens", "used")) {
            try (PreparedStatement ps = con.prepareStatement("ALTER TABLE password_reset_tokens DROP COLUMN used")) {
                ps.executeUpdate();
            } catch (Exception e) {
                e.printStackTrace();
            }
        }
    }

    private static boolean columnExists(Connection con, String tableName, String columnName) {
        String sql = "SELECT COUNT(*) FROM information_schema.columns WHERE table_schema = DATABASE() AND table_name = ? AND column_name = ?";
        try (PreparedStatement ps = con.prepareStatement(sql)) {
            ps.setString(1, tableName);
            ps.setString(2, columnName);
            try (ResultSet rs = ps.executeQuery()) {
                return rs.next() && rs.getInt(1) > 0;
            }
        } catch (Exception e) {
            e.printStackTrace();
        }
        return false;
    }

    /**
     * Creates a new token for the given user, invalidates any previous
     * unused tokens of the same type for that user (so an old email link
     * stops working once a newer one is issued), and returns the RAW token
     * (never persisted — only its hash is stored).
     */
    public static String createToken(Connection con, int userId, String tokenType, int validMinutes, String requestedIp) {

        invalidateOutstanding(con, userId, tokenType);

        String rawToken = TokenUtil.generateRawToken();
        String tokenHash = TokenUtil.hashToken(rawToken);

        String sql = "INSERT INTO password_reset_tokens (user_id, token_hash, token_type, expires_at, requested_ip) "
                + "VALUES (?, ?, ?, DATE_ADD(NOW(), INTERVAL ? MINUTE), ?)";

        try (PreparedStatement ps = con.prepareStatement(sql)) {
            ps.setInt(1, userId);
            ps.setString(2, tokenHash);
            ps.setString(3, tokenType);
            ps.setInt(4, validMinutes);
            ps.setString(5, requestedIp == null ? "N/A" : requestedIp);
            ps.executeUpdate();
        } catch (Exception e) {
            e.printStackTrace();
            return null;
        }

        return rawToken;
    }

    private static void invalidateOutstanding(Connection con, int userId, String tokenType) {
        String sql = "UPDATE password_reset_tokens SET used_at = NOW() "
                + "WHERE user_id = ? AND token_type = ? AND used_at IS NULL";
        try (PreparedStatement ps = con.prepareStatement(sql)) {
            ps.setInt(1, userId);
            ps.setString(2, tokenType);
            ps.executeUpdate();
        } catch (Exception e) {
            e.printStackTrace();
        }
    }

    /** How many tokens of this type have been issued to this user recently — used to throttle repeat requests. */
    public static int countRecentTokens(Connection con, int userId, String tokenType, int windowMinutes) {
        String sql = "SELECT COUNT(*) AS cnt FROM password_reset_tokens "
                + "WHERE user_id = ? AND token_type = ? AND created_at >= DATE_SUB(NOW(), INTERVAL ? MINUTE)";
        try (PreparedStatement ps = con.prepareStatement(sql)) {
            ps.setInt(1, userId);
            ps.setString(2, tokenType);
            ps.setInt(3, windowMinutes);
            try (ResultSet rs = ps.executeQuery()) {
                if (rs.next()) {
                    return rs.getInt("cnt");
                }
            }
        } catch (Exception e) {
            e.printStackTrace();
        }
        return 0;
    }

    /**
     * Looks up a raw token from an incoming request, returning the matching
     * row only if it exists, is unused, AND unexpired. Never trust a token
     * that fails any one of those checks.
     */
    public static ResolvedToken resolveValidToken(Connection con, String rawToken, String expectedType) {

        if (rawToken == null || rawToken.trim().isEmpty()) {
            return null;
        }

        String tokenHash = TokenUtil.hashToken(rawToken.trim());

        String sql = "SELECT token_id, user_id, token_type, expires_at, used_at "
                + "FROM password_reset_tokens WHERE token_hash = ?";

        try (PreparedStatement ps = con.prepareStatement(sql)) {
            ps.setString(1, tokenHash);
            try (ResultSet rs = ps.executeQuery()) {
                if (!rs.next()) {
                    return null;
                }

                Timestamp expiresAt = rs.getTimestamp("expires_at");
                Timestamp usedAt = rs.getTimestamp("used_at");
                String tokenType = rs.getString("token_type");

                if (usedAt != null) {
                    return null;
                }
                if (expiresAt == null || expiresAt.before(new Timestamp(System.currentTimeMillis()))) {
                    return null;
                }
                if (expectedType != null && !expectedType.equals(tokenType)) {
                    return null;
                }

                ResolvedToken resolved = new ResolvedToken();
                resolved.tokenId = rs.getInt("token_id");
                resolved.userId = rs.getInt("user_id");
                resolved.tokenType = tokenType;
                return resolved;
            }
        } catch (Exception e) {
            e.printStackTrace();
            return null;
        }
    }

    public static void markTokenUsed(Connection con, int tokenId) {
        String sql = "UPDATE password_reset_tokens SET used_at = NOW() WHERE token_id = ?";
        try (PreparedStatement ps = con.prepareStatement(sql)) {
            ps.setInt(1, tokenId);
            ps.executeUpdate();
        } catch (Exception e) {
            e.printStackTrace();
        }
    }

    public static class ResolvedToken {
        public int tokenId;
        public int userId;
        public String tokenType;
    }
}
