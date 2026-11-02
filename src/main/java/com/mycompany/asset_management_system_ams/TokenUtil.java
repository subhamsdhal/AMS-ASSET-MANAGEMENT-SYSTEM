package com.mycompany.asset_management_system_ams;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.SecureRandom;
import java.util.Base64;

/**
 * TokenUtil — generates and hashes the high-entropy, single-use bearer
 * tokens used by the password-reset and account-activation email links.
 *
 * The raw token is only ever held in memory long enough to build the
 * outbound email link; only its SHA-256 hash is persisted in
 * password_reset_tokens, so a database leak alone cannot be replayed as a
 * working reset/activation link (the same principle as never storing a raw
 * password — see PasswordUtil — applied to these bearer tokens instead).
 * SHA-256 rather than BCrypt is the right tool here: this is a 256-bit
 * random value with no human-guessable structure, not a human-chosen
 * password, so it needs no deliberately slow hashing.
 */
public class TokenUtil {

    private static final SecureRandom SECURE_RANDOM = new SecureRandom();

    private TokenUtil() {
        // Utility class — do not instantiate
    }

    /** A fresh 256-bit, URL-safe random token. */
    public static String generateRawToken() {
        byte[] randomBytes = new byte[32];
        SECURE_RANDOM.nextBytes(randomBytes);
        return Base64.getUrlEncoder().withoutPadding().encodeToString(randomBytes);
    }

    /** SHA-256 hex digest of a raw token, for storage/lookup. */
    public static String hashToken(String rawToken) {
        if (rawToken == null) {
            return null;
        }
        try {
            MessageDigest digest = MessageDigest.getInstance("SHA-256");
            byte[] hashBytes = digest.digest(rawToken.getBytes(StandardCharsets.UTF_8));
            StringBuilder sb = new StringBuilder(hashBytes.length * 2);
            for (byte b : hashBytes) {
                sb.append(String.format("%02x", b));
            }
            return sb.toString();
        } catch (Exception e) {
            throw new IllegalStateException("SHA-256 not available", e);
        }
    }
}
