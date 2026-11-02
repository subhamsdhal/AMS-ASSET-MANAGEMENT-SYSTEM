package com.mycompany.asset_management_system_ams;

/**
 * HtmlEscapeUtil — shared HTML-escaping helper for JSPs that render
 * database-sourced text directly into the page.
 *
 * dashboard.jsp already has its own private safeText() doing the same thing;
 * this is pulled out to a shared class so other JSPs (starting with
 * employee_dashboard.jsp, which was rendering asset/category names and
 * status values with no escaping at all - a stored-XSS path, since asset
 * and category names are entered by Asset Manager/Admin roles and shown
 * back to every employee who has that asset allocated) don't each need
 * their own copy. dashboard.jsp's own safeText() is left as-is for this
 * pass - not broken, just duplicated; consolidating it onto this class too
 * is a safe follow-up, not urgent.
 */
public class HtmlEscapeUtil {

    private HtmlEscapeUtil() {
        // Utility class — do not instantiate
    }

    /** Escapes the characters that matter for HTML text/attribute context. Never returns null. */
    public static String escape(String value) {
        if (value == null) {
            return "";
        }
        return value
                .replace("&", "&amp;")
                .replace("\"", "&quot;")
                .replace("'", "&#39;")
                .replace("<", "&lt;")
                .replace(">", "&gt;");
    }

    /** Same as escape(), but returns a fallback (already-safe literal) instead of "" for null/blank input. */
    public static String escape(String value, String fallbackIfBlank) {
        if (value == null || value.trim().isEmpty()) {
            return fallbackIfBlank;
        }
        return escape(value);
    }
}
