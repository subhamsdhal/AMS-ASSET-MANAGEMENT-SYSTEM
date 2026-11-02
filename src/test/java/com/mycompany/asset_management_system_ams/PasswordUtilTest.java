package com.mycompany.asset_management_system_ams;

import org.junit.jupiter.api.Test;
import static org.junit.jupiter.api.Assertions.*;

class PasswordUtilTest {

    @Test
    void testHash_validString_returnsBCryptHash() {
        String input = "password123";
        
        String actualHash = PasswordUtil.hash(input);
        System.out.println("HASH_ADMIN: " + PasswordUtil.hash("admin123"));
        System.out.println("HASH_SUPER: " + PasswordUtil.hash("super_admin123"));
        System.out.println("HASH_AUDITOR: " + PasswordUtil.hash("auditor123"));
        
        assertNotNull(actualHash);
        assertTrue(actualHash.startsWith("$2a$") || actualHash.startsWith("$2y$") || actualHash.startsWith("$2b$"));
    }

    @Test
    void testHash_nullOrEmptyInput_returnsNull() {
        assertNull(PasswordUtil.hash(null));
        assertNull(PasswordUtil.hash(""));
    }

    @Test
    void testMatches_validHash_returnsTrue() {
        String input = "securePassword";
        String hashed = PasswordUtil.hash(input);
        
        assertTrue(PasswordUtil.matches(input, hashed));
    }

    @Test
    void testMatches_invalidHash_returnsFalse() {
        String input = "securePassword";
        String hashed = PasswordUtil.hash("wrongPassword");
        
        assertFalse(PasswordUtil.matches(input, hashed));
    }

    @Test
    void testMatches_legacyPlainText_returnsTrue() {
        String legacyPassword = "myOldPassword";
        // It's plain-text (not 64-char hex), so it should fallback to equals()
        assertTrue(PasswordUtil.matches(legacyPassword, legacyPassword));
    }

    @Test
    void testMatches_nullInputs_returnsFalse() {
        assertFalse(PasswordUtil.matches(null, "hash"));
        assertFalse(PasswordUtil.matches("password", null));
        assertFalse(PasswordUtil.matches(null, null));
    }
}
