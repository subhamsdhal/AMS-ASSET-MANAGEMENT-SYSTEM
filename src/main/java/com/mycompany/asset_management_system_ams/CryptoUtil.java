package com.mycompany.asset_management_system_ams;

import javax.crypto.Cipher;
import javax.crypto.spec.SecretKeySpec;
import java.util.Base64;
import java.nio.charset.StandardCharsets;

public class CryptoUtil {
    
    // Prefer AMS_CRYPTO_KEY in production. The fallback keeps existing saved keys readable.
    private static final String FALLBACK_SECRET_KEY = "RailwayAMSSecureKeyForAESEncrypt";
    private static final String ALGORITHM = "AES";

    public static String encrypt(String plainText) {
        if (plainText == null || plainText.isEmpty()) {
            return plainText;
        }
        try {
            SecretKeySpec secretKey = new SecretKeySpec(getSecretKey().getBytes(StandardCharsets.UTF_8), ALGORITHM);
            Cipher cipher = Cipher.getInstance(ALGORITHM);
            cipher.init(Cipher.ENCRYPT_MODE, secretKey);
            byte[] encryptedBytes = cipher.doFinal(plainText.getBytes(StandardCharsets.UTF_8));
            return Base64.getEncoder().encodeToString(encryptedBytes);
        } catch (Exception e) {
            System.err.println("Error encrypting string: " + e.getMessage());
        }
        return null;
    }

    public static String decrypt(String encryptedText) {
        if (encryptedText == null || encryptedText.isEmpty()) {
            return encryptedText;
        }
        try {
            SecretKeySpec secretKey = new SecretKeySpec(getSecretKey().getBytes(StandardCharsets.UTF_8), ALGORITHM);
            Cipher cipher = Cipher.getInstance(ALGORITHM);
            cipher.init(Cipher.DECRYPT_MODE, secretKey);
            byte[] plainBytes = cipher.doFinal(Base64.getDecoder().decode(encryptedText));
            return new String(plainBytes, StandardCharsets.UTF_8);
        } catch (Exception e) {
            // Legacy settings may contain plaintext API keys. Callers can fall back to the stored value.
        }
        return null;
    }

    private static String getSecretKey() {
        String envKey = System.getenv("AMS_CRYPTO_KEY");
        if (envKey != null) {
            String trimmed = envKey.trim();
            int len = trimmed.getBytes(StandardCharsets.UTF_8).length;
            if (len == 16 || len == 24 || len == 32) {
                return trimmed;
            }
        }
        return FALLBACK_SECRET_KEY;
    }
}
