package com.mycompany.asset_management_system_ams;

import org.mindrot.jbcrypt.BCrypt;
import java.util.logging.Logger;

/**
 * PasswordUtil — BCrypt password hashing utility for IR-AMS.
 *
 * All passwords stored in the database MUST be hashed using this class.
 * Plain-text password storage is not permitted for authentication.
 */
public class PasswordUtil {

    private static final Logger LOGGER = Logger.getLogger(PasswordUtil.class.getName());

    private PasswordUtil() {
        // Utility class — do not instantiate
    }

    /**
     * Returns the BCrypt hash of the given plain-text password.
     * Returns null if the input is null or empty (caller must validate).
     */
    public static String hash(String plainText) {
        if (plainText == null || plainText.isEmpty()) {
            return null;
        }

        return BCrypt.hashpw(plainText, BCrypt.gensalt());
    }

    /**
     * Returns true if the plain-text password matches the stored BCrypt hash.
     *
     * Also handles legacy plain-text passwords or SHA-256 hashes gracefully during migration.
     *
     * NOTE (security debt, tracked in CHANGELOG-fixes.md Login-7): the SHA-256 and
     * plaintext branches below should be removed once every row in users.password_crypt
     * is confirmed to be a BCrypt hash (SELECT COUNT(*) FROM users WHERE password_crypt
     * NOT LIKE '$2%'). They are left in place for now because removing them blind, with
     * no way to query the live database from this environment, risks locking out any
     * account that hasn't been migrated yet. Each time a non-BCrypt match succeeds it is
     * now logged at WARNING so it shows up in server logs and can be monitored until the
     * migration is confirmed complete.
     */
    public static boolean matches(String plainText, String storedValue) {
        if (plainText == null || storedValue == null) {
            return false;
        }

        // The candidate password is intentionally NOT trimmed: PasswordUtil.hash()
        // never trims when a password is first set, so trimming only here would
        // reject a correct password that happens to have leading/trailing spaces.
        String storedTrimmed = storedValue.trim();

        // Check if the stored hash is a valid BCrypt hash
        if (storedTrimmed.startsWith("$2a$") || storedTrimmed.startsWith("$2y$") || storedTrimmed.startsWith("$2b$")) {
            try {
                return BCrypt.checkpw(plainText, storedTrimmed);
            } catch (Exception e) {
                return false;
            }
        } else if (storedTrimmed.length() == 64 && storedTrimmed.matches("(?i)[0-9a-f]+")) {
            // Legacy SHA-256 fallback (if needed during migration)
            try {
                java.security.MessageDigest digest = java.security.MessageDigest.getInstance("SHA-256");
                byte[] bytes = digest.digest(plainText.getBytes(java.nio.charset.StandardCharsets.UTF_8));
                StringBuilder sb = new StringBuilder();
                for (byte b : bytes) {
                    sb.append(String.format("%02x", b));
                }
                String hashed = sb.toString();
                boolean matched = hashed.equalsIgnoreCase(storedTrimmed);
                if (matched) {
                    LOGGER.warning("PasswordUtil: authenticated via legacy SHA-256 fallback, not BCrypt. "
                            + "This account still needs migrating.");
                }
                return matched;
            } catch (java.security.NoSuchAlgorithmException e) {
                return false;
            }
        } else {
            // Plaintext fallback (if needed during migration)
            boolean matched = plainText.equals(storedTrimmed);
            if (matched) {
                LOGGER.warning("PasswordUtil: authenticated via legacy plaintext fallback, not BCrypt. "
                        + "This account still needs migrating.");
            }
            return matched;
        }
    }
}
