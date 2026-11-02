package com.mycompany.asset_management_system_ams;

public class PhoneValidationUtil {
    
    /**
     * Sanitizes and validates a phone number according to standard 10-digit Indian constraints.
     * @param phone The raw phone number input
     * @return The cleaned 10-digit phone number, or null if invalid
     */
    public static String validatePhone(String phone) {
        if (phone == null) {
            return null;
        }
        
        // Strip non-digits
        String cleaned = phone.replaceAll("\\D", "");
        
        // Remove +91 or 91 country code
        if (cleaned.length() >= 12 && cleaned.startsWith("91")) {
            cleaned = cleaned.substring(2);
        }
        
        // Cap to exactly 10 digits
        if (cleaned.length() > 10) {
            cleaned = cleaned.substring(0, 10);
        }
        
        if (cleaned.length() == 10) {
            return cleaned;
        }
        
        return null;
    }
}
