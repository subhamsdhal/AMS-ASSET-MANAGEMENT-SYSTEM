package com.mycompany.asset_management_system_ams;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * CopilotEntityResolver
 *
 * Extracts structured entities from free-form user text:
 *  - asset_code   (AST001, AST002, …)
 *  - employee_code (EMP001, EMP006, …)
 *  - employee_name (natural name after trigger phrases)
 *  - category     (Laptop, Desktop, Printer, …)
 *  - department   (IT Centre, Stores, General Administration, …)
 *  - status       (AVAILABLE, ALLOCATED, DISPOSED, …)
 *
 * Category and department matching use multi-level lookup:
 *   1. Alias table (longest alias first)
 *   2. Fallback partial match against canonical names
 *
 * All matching is case-insensitive and handles plural forms.
 */
public class CopilotEntityResolver {

    // ── Result types ──────────────────────────────────────────────────────────

    public static class EntityMatch {
        public final String raw;
        public final String canonical;
        public EntityMatch(String raw, String canonical) {
            this.raw = raw;
            this.canonical = canonical;
        }
    }

    // ── Category alias table ──────────────────────────────────────────────────

    private static final Map<String, List<String>> CATEGORY_ALIASES = new HashMap<>();

    static {
        CATEGORY_ALIASES.put("Laptop", List.of(
            "lap top", "lap tops", "laptops", "laptop",
            "notebooks", "notebook",
            "laptop ka", "laptops ka", "laptop ra", "laptop guda",
            "लैपटॉप", "लैपटॉप्स", "ଲାପଟପ୍"
        ));
        CATEGORY_ALIASES.put("Desktop", List.of(
            "desktop computers", "desktop computer", "desktops", "desktop",
            "computers", "computer", "pcs", "pc",
            "desk tops", "desk top",
            "कंप्यूटर", "डेस्कटॉप", "କମ୍ପ୍ୟୁଟର"
        ));
        CATEGORY_ALIASES.put("Printer", List.of(
            "multifunction printers", "multifunction printer",
            "printers", "printer",
            "printer scanner", "scanner printer",
            "प्रिंटर", "ପ୍ରିଣ୍ଟର"
        ));
        CATEGORY_ALIASES.put("Scanner", List.of(
            "scanners", "scanner"
        ));
        CATEGORY_ALIASES.put("Monitor", List.of(
            "monitors", "monitor", "display", "displays",
            "मॉनिटर", "ମନିଟର"
        ));
        CATEGORY_ALIASES.put("Projector", List.of(
            "projectors", "projector"
        ));
        CATEGORY_ALIASES.put("Networking", List.of(
            "network devices", "network device", "networking", "network",
            "routers", "router", "switches", "switch",
            "access points", "access point",
            "नेटवर्क", "ନେଟୱର୍କ"
        ));
        CATEGORY_ALIASES.put("Furniture", List.of(
            "furniture", "chairs", "chair", "tables", "table", "desks", "desk"
        ));
        CATEGORY_ALIASES.put("Vehicle", List.of(
            "vehicles", "vehicle", "cars", "car", "jeeps", "jeep"
        ));
        CATEGORY_ALIASES.put("Server", List.of(
            "servers", "server"
        ));
        CATEGORY_ALIASES.put("UPS", List.of(
            "power backups", "power backup", "ups", "inverter", "inverters",
            "uninterruptible power supply"
        ));
        CATEGORY_ALIASES.put("AC", List.of(
            "air conditioner", "air conditioners", "ac", "acs", "split ac",
            "air conditioning"
        ));
        CATEGORY_ALIASES.put("Generator", List.of(
            "generators", "generator", "genset", "gensets"
        ));
    }

    // ── Status alias table ────────────────────────────────────────────────────

    private static final Map<String, List<String>> STATUS_ALIASES = new HashMap<>();

    static {
        STATUS_ALIASES.put("AVAILABLE",        List.of("available", "free", "unused", "not assigned", "unassigned", "in stock"));
        STATUS_ALIASES.put("ALLOCATED",        List.of("allocated", "assigned", "issued", "in use", "allotted"));
        STATUS_ALIASES.put("UNDER_MAINTENANCE", List.of("under maintenance", "maintenance", "repair", "pending repair", "under repair", "servicing"));
        STATUS_ALIASES.put("DISPOSED",         List.of("disposed", "condemned", "scrap", "scrapped", "retired", "written off"));
        STATUS_ALIASES.put("DAMAGED",          List.of("damaged", "broken", "unserviceable", "faulty"));
        STATUS_ALIASES.put("PENDING",          List.of("pending"));
        STATUS_ALIASES.put("APPROVED",         List.of("approved"));
        STATUS_ALIASES.put("REJECTED",         List.of("rejected"));
        STATUS_ALIASES.put("FULFILLED",        List.of("fulfilled"));
        STATUS_ALIASES.put("RETURNED",         List.of("returned"));
    }

    // ── Department alias table ────────────────────────────────────────────────

    /**
     * Map from canonical DB department name → list of aliases (lowercase).
     * The extractDepartment() method iterates this instead of a chain of if-statements
     * so new departments can be added here without logic changes.
     */
    private static final Map<String, List<String>> DEPARTMENT_ALIASES = new HashMap<>();

    static {
        DEPARTMENT_ALIASES.put("IT Centre", List.of(
            "it centre", "it center", "it department", "it dept",
            "information technology", "information tech", "it"
        ));
        DEPARTMENT_ALIASES.put("Personnel", List.of(
            "personnel", "hr", "human resources", "human resource",
            "manpower", "staff department"
        ));
        DEPARTMENT_ALIASES.put("Finance", List.of(
            "finance", "finance department", "finance dept",
            "accounts", "account", "f&a", "accounts department"
        ));
        DEPARTMENT_ALIASES.put("General Administration", List.of(
            "general administration", "general admin", "gen admin",
            "administration", "admin", "ga"
        ));
        DEPARTMENT_ALIASES.put("Engineering", List.of(
            "engineering", "engg", "eng department"
        ));
        DEPARTMENT_ALIASES.put("Operations", List.of(
            "operations", "ops", "operation department"
        ));
        DEPARTMENT_ALIASES.put("Electrical", List.of(
            "electrical", "electrical department", "ee"
        ));
        DEPARTMENT_ALIASES.put("Mechanical", List.of(
            // Fault, found live: "me" is one of the most common words in
            // English (a personal pronoun in constant use - "show ME the old
            // ones", "tell me", "give me"...), and extractDepartment() word-
            // boundary-matches every alias regardless of how common the word
            // is. That silently resolved unrelated questions to department =
            // Mechanical purely because they contained the word "me" -
            // exactly the keyword-collision class this whole effort is about
            // removing, not adding. "mechanical"/"mechanical department"
            // already cover every real way someone names this department;
            // dropped rather than replaced, there is nothing this alias
            // uniquely enabled.
            "mechanical", "mechanical department"
        ));
        DEPARTMENT_ALIASES.put("Civil", List.of(
            "civil", "civil department", "civil engg"
        ));
        DEPARTMENT_ALIASES.put("Medical", List.of(
            "medical", "medical department", "health", "hospital"
        ));
        DEPARTMENT_ALIASES.put("Security", List.of(
            "security", "security department", "vigilance"
        ));
        DEPARTMENT_ALIASES.put("Commercial", List.of(
            "commercial", "commercial department", "ticketing"
        ));
        DEPARTMENT_ALIASES.put("Stores", List.of(
            "stores", "store", "stores department", "warehouse", "storeroom"
        ));
        DEPARTMENT_ALIASES.put("Signal & Telecom", List.of(
            "signal & telecom", "signal and telecom", "signal telecom",
            "s&t", "signal", "telecom", "telecommunications"
        ));
        DEPARTMENT_ALIASES.put("Audit", List.of(
            "audit", "audit department", "internal audit", "vigilance audit"
        ));
        DEPARTMENT_ALIASES.put("Traffic", List.of(
            "traffic", "traffic department", "train operations"
        ));
        DEPARTMENT_ALIASES.put("Planning", List.of(
            "planning", "planning department", "projects"
        ));
        DEPARTMENT_ALIASES.put("Raj Bhasha", List.of(
            "raj bhasha", "rajbhasha", "hindi department", "hindi"
        ));
    }

    // ── Trigger phrases for employee name extraction ──────────────────────────
    // Pattern: trigger phrase followed by a capitalized word (name)
    private static final Pattern EMPLOYEE_NAME_PATTERN = Pattern.compile(
        "(?:assigned to|details of|allocations of|assets of|held by|" +
        "holding by|employee named?|staff named?|for employee|for staff|" +
        "of employee|who is|about|assets held by|assets assigned to|" +
        "allocated to|issued to|belonging to|allotted to)\\s+([A-Z][a-z]+(?: [A-Z][a-z]+)*)",
        Pattern.CASE_INSENSITIVE
    );

    // ── Pattern for serial number (SN, S/N, SERIAL) ──────────────────────────
    private static final Pattern SERIAL_NUMBER_PATTERN = Pattern.compile(
        "\\b(?:sn|s/n|serial|serial no|serial number)[:\\s]+([A-Z0-9\\-]+)\\b",
        Pattern.CASE_INSENSITIVE
    );

    // ── Pattern for QR public token (UUID-like or alphanumeric prefix) ────────
    private static final Pattern QR_TOKEN_PATTERN = Pattern.compile(
        "\\b([a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12})\\b",
        Pattern.CASE_INSENSITIVE
    );

    // ── Public API ────────────────────────────────────────────────────────────

    public static EntityMatch extractCategory(String query) {
        return extractFromMap(query, CATEGORY_ALIASES);
    }

    public static EntityMatch extractStatus(String query) {
        return extractFromMap(query, STATUS_ALIASES);
    }

    /**
     * Resolves a department name from free text.
     * Uses alias table lookup (longest alias first) so aliases always win.
     */
    public static String extractDepartment(String query) {
        if (query == null || query.isEmpty()) return null;

        String q = query.toLowerCase();

        // Build a sorted alias list (longest alias first for greedy match)
        List<AliasEntry> entries = new ArrayList<>();
        for (Map.Entry<String, List<String>> e : DEPARTMENT_ALIASES.entrySet()) {
            for (String alias : e.getValue()) {
                entries.add(new AliasEntry(alias, e.getKey()));
            }
        }
        entries.sort((a, b) -> Integer.compare(b.alias.length(), a.alias.length()));

        for (AliasEntry entry : entries) {
            Pattern p = Pattern.compile(
                "(?<![\\p{L}\\p{Nd}])" + Pattern.quote(entry.alias) + "(?![\\p{L}\\p{Nd}])",
                Pattern.CASE_INSENSITIVE
            );
            if (p.matcher(q).find()) {
                return entry.canonical;
            }
        }
        return null;
    }

    /**
     * Extract asset code (e.g. AST001).
     */
    public static String extractAssetCode(String query) {
        if (query == null) return null;
        Matcher m = Pattern.compile("\\b(ast\\d+)\\b", Pattern.CASE_INSENSITIVE).matcher(query);
        if (m.find()) return m.group(1).toUpperCase();
        return null;
    }

    /**
     * Extract employee code (e.g. EMP006).
     */
    public static String extractEmployeeCode(String query) {
        if (query == null) return null;
        Matcher m = Pattern.compile("\\b(emp\\d+)\\b", Pattern.CASE_INSENSITIVE).matcher(query);
        if (m.find()) return m.group(1).toUpperCase();
        return null;
    }

    /**
     * Extract an employee name from natural language.
     * Looks for names after trigger phrases like "assigned to Subham",
     * "details of Ramesh Kumar", "assets of Priya".
     *
     * Returns null if no name found.
     */
    public static String extractEmployeeName(String query) {
        if (query == null || query.trim().isEmpty()) return null;

        Matcher m = EMPLOYEE_NAME_PATTERN.matcher(query);
        if (m.find()) {
            return m.group(1).trim();
        }

        // Fallback: simple pattern after "to"/"of"/"for" followed by a capitalized word
        Matcher m2 = Pattern.compile(
            "\\b(?:to|of|for|by)\\s+([A-Z][a-z]+(?: [A-Z][a-z]+)*)",
            Pattern.CASE_INSENSITIVE
        ).matcher(query);
        if (m2.find()) {
            String candidate = m2.group(1).trim();
            // Avoid matching department/category/module keywords as names
            String lower = candidate.toLowerCase();
            if (!lower.equals("laptop") && !lower.equals("desktop") && !lower.equals("all")
                    && !lower.equals("it") && !lower.equals("stores")
                    && !lower.equals("maintenance") && !lower.equals("warranty")
                    && !lower.equals("category") && !lower.equals("vendor")
                    && !lower.equals("supplier") && !lower.equals("department")
                    && !lower.equals("assets") && !lower.equals("reports")
                    && !lower.equals("audit") && !lower.equals("qr")
                    && !lower.equals("finance") && !lower.equals("engineering")
                    && !lower.equals("operations") && !lower.equals("personnel")) {
                return candidate;
            }
        }
        return null;
    }

    /**
     * Extract vendor/supplier name from query.
     * Looks for mentions after "by vendor", "vendor named", "from supplier" etc.
     * Returns null if not found.
     */
    public static String extractVendorName(String query) {
        if (query == null || query.trim().isEmpty()) return null;
        Matcher m = Pattern.compile(
            "\\b(?:vendor|supplier|supplied by|from vendor|from supplier|by vendor)\\s+" +
            "([A-Za-z][A-Za-z0-9\\s&\\.]{1,30}?)(?:\\s*$|[,;\\.])",
            Pattern.CASE_INSENSITIVE
        ).matcher(query);
        if (m.find()) return m.group(1).trim();
        return null;
    }

    /**
     * Extract a serial number from query.
     * Pattern: SN/S.N./Serial: [value]
     * Returns null if not found.
     */
    public static String extractSerialNumber(String query) {
        if (query == null) return null;
        Matcher m = SERIAL_NUMBER_PATTERN.matcher(query);
        return m.find() ? m.group(1).toUpperCase() : null;
    }

    /**
     * Extract a QR public token (UUID format) from query.
     * Returns null if no UUID-like token found.
     */
    public static String extractQrToken(String query) {
        if (query == null) return null;
        Matcher m = QR_TOKEN_PATTERN.matcher(query);
        return m.find() ? m.group(1).toLowerCase() : null;
    }

    /**
     * Normalize a raw category string to its canonical DB name.
     */
    public static String normalizeCategory(String rawCategory) {
        EntityMatch match = extractCategory(rawCategory);
        return match != null ? match.canonical : rawCategory;
    }

    // ── Private helpers ───────────────────────────────────────────────────────

    private static EntityMatch extractFromMap(String query, Map<String, List<String>> map) {
        if (query == null || query.isEmpty()) return null;

        List<AliasEntry> entries = new ArrayList<>();
        for (Map.Entry<String, List<String>> entry : map.entrySet()) {
            for (String alias : entry.getValue()) {
                entries.add(new AliasEntry(alias, entry.getKey()));
            }
        }
        // Longest alias first — prevents "laptop" matching before "laptops ka"
        entries.sort((a, b) -> Integer.compare(b.alias.length(), a.alias.length()));

        for (AliasEntry entry : entries) {
            Pattern p = Pattern.compile(
                "\\b" + Pattern.quote(entry.alias) + "\\b",
                Pattern.CASE_INSENSITIVE
            );
            Matcher m = p.matcher(query);
            if (m.find()) {
                return new EntityMatch(m.group(), entry.canonical);
            }
        }
        return null;
    }

    private static class AliasEntry {
        String alias;
        String canonical;
        AliasEntry(String alias, String canonical) {
            this.alias = alias;
            this.canonical = canonical;
        }
    }
}
