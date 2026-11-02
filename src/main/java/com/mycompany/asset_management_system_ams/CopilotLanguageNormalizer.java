package com.mycompany.asset_management_system_ams;

import java.util.LinkedHashMap;
import java.util.Map;
import java.util.regex.Pattern;

/**
 * CopilotLanguageNormalizer
 *
 * Converts raw user text (with Hinglish, Odia, voice-recognition errors,
 * typos, plurals) into clean normalized English that the intent detector
 * and entity resolver can work with reliably.
 *
 * Rules are applied longest-match first (LinkedHashMap preserves insertion
 * order; we iterate all entries so multi-word phrases are placed before
 * single-word ones).
 */
public class CopilotLanguageNormalizer {

    private static final Map<String, String> PHRASE_MAPPINGS = new LinkedHashMap<>();

    static {
        // ── Voice / speech-recognition errors (domain-specific) ──────────────
        PHRASE_MAPPINGS.put("purchased calls",   "purchase cost");
        PHRASE_MAPPINGS.put("purchase calls",    "purchase cost");
        PHRASE_MAPPINGS.put("purchased cost",    "purchase cost");
        PHRASE_MAPPINGS.put("all purchased cost","all purchase cost");
        PHRASE_MAPPINGS.put("purchase price",    "purchase cost");
        PHRASE_MAPPINGS.put("total price",       "total cost");
        PHRASE_MAPPINGS.put("asset coast",       "asset cost");
        PHRASE_MAPPINGS.put("assets coast",      "assets cost");
        PHRASE_MAPPINGS.put("asset calls",       "asset cost");
        PHRASE_MAPPINGS.put("asset value",       "asset cost");
        PHRASE_MAPPINGS.put("portfolio value",   "total cost");
        PHRASE_MAPPINGS.put("portfolio cost",    "total cost");

        // ── Device / equipment names ─────────────────────────────────────────
        PHRASE_MAPPINGS.put("lap top",           "laptop");
        PHRASE_MAPPINGS.put("lap tops",          "laptops");
        PHRASE_MAPPINGS.put("note book",         "notebook");
        PHRASE_MAPPINGS.put("note books",        "notebooks");
        PHRASE_MAPPINGS.put("desk top",          "desktop");
        PHRASE_MAPPINGS.put("desk tops",         "desktops");
        PHRASE_MAPPINGS.put("printer scanner",   "printer");
        PHRASE_MAPPINGS.put("scanner printer",   "printer");

        // ── Spelling / typo corrections ──────────────────────────────────────
        PHRASE_MAPPINGS.put("maintainance",      "maintenance");
        PHRASE_MAPPINGS.put("maintainence",      "maintenance");
        PHRASE_MAPPINGS.put("maintenence",       "maintenance");
        PHRASE_MAPPINGS.put("warrenty",          "warranty");
        PHRASE_MAPPINGS.put("waranty",           "warranty");
        PHRASE_MAPPINGS.put("warenty",           "warranty");
        PHRASE_MAPPINGS.put("catagory",          "category");
        PHRASE_MAPPINGS.put("catgory",           "category");
        PHRASE_MAPPINGS.put("categry",           "category");
        PHRASE_MAPPINGS.put("vender",            "vendor");
        PHRASE_MAPPINGS.put("depart ment",       "department");
        PHRASE_MAPPINGS.put("alloted",           "allocated");
        PHRASE_MAPPINGS.put("allotment",         "allocation");
        PHRASE_MAPPINGS.put("allot",             "allocate");
        PHRASE_MAPPINGS.put("written records",   "return records");
        PHRASE_MAPPINGS.put("employ details",    "employee details");
        PHRASE_MAPPINGS.put("employees detail",  "employee details");

        // ── Employee / holder synonyms ────────────────────────────────────────
        PHRASE_MAPPINGS.put("current holder",    "assigned employee");
        PHRASE_MAPPINGS.put("asset holder",      "assigned employee");
        PHRASE_MAPPINGS.put("custodian",         "assigned employee");
        PHRASE_MAPPINGS.put("who holds",         "who has");
        PHRASE_MAPPINGS.put("who is holding",    "who has");
        PHRASE_MAPPINGS.put("who has been assigned", "assigned to");
        PHRASE_MAPPINGS.put("allotted to",       "assigned to");
        PHRASE_MAPPINGS.put("issued to",         "assigned to");

        // ── Status synonyms ───────────────────────────────────────────────────
        PHRASE_MAPPINGS.put("not assigned",      "available");
        PHRASE_MAPPINGS.put("unassigned",        "available");
        PHRASE_MAPPINGS.put("in stock",          "available");
        PHRASE_MAPPINGS.put("free assets",       "available assets");
        PHRASE_MAPPINGS.put("condemned",         "disposed");
        PHRASE_MAPPINGS.put("retired",           "disposed");
        PHRASE_MAPPINGS.put("scrapped",          "disposed");
        PHRASE_MAPPINGS.put("written off",       "disposed");
        PHRASE_MAPPINGS.put("unserviceable",     "damaged");
        PHRASE_MAPPINGS.put("broken",            "damaged");
        PHRASE_MAPPINGS.put("in use",            "allocated");

        // ── Maintenance synonyms ──────────────────────────────────────────────
        PHRASE_MAPPINGS.put("under repair",      "under maintenance");
        PHRASE_MAPPINGS.put("being repaired",    "under maintenance");
        PHRASE_MAPPINGS.put("service history",   "maintenance history");
        PHRASE_MAPPINGS.put("repair history",    "maintenance history");
        PHRASE_MAPPINGS.put("service log",       "maintenance history");

        // ── Numbers (Hindi / Odia spoken) ─────────────────────────────────────
        PHRASE_MAPPINGS.put("tees",              "30");
        PHRASE_MAPPINGS.put("pandrah",           "15");
        PHRASE_MAPPINGS.put("saat",              "7");
        PHRASE_MAPPINGS.put("तीस",               "30");
        PHRASE_MAPPINGS.put("पंद्रह",             "15");
        PHRASE_MAPPINGS.put("सात",               "7");
        PHRASE_MAPPINGS.put("३०",                "30");
        PHRASE_MAPPINGS.put("୩୦",                "30");
        PHRASE_MAPPINGS.put("୧୫",                "15");
        PHRASE_MAPPINGS.put("୭",                 "7");

        // ── Hinglish / Hindi ─────────────────────────────────────────────────
        PHRASE_MAPPINGS.put("mujhe batao",       "tell me");
        PHRASE_MAPPINGS.put("मुझे बताओ",          "tell me");
        PHRASE_MAPPINGS.put("mujhe dikhao",      "show me");
        PHRASE_MAPPINGS.put("batao",             "show");
        PHRASE_MAPPINGS.put("बताओ",              "show");
        PHRASE_MAPPINGS.put("dikhao",            "show");
        PHRASE_MAPPINGS.put("दिखाओ",             "show");
        PHRASE_MAPPINGS.put("dekhna hai",        "show");
        PHRASE_MAPPINGS.put("dekhao",            "show");
        PHRASE_MAPPINGS.put("kaunse",            "which");
        PHRASE_MAPPINGS.put("kahan hai",         "where");
        PHRASE_MAPPINGS.put("kahan hain",        "where");

        PHRASE_MAPPINGS.put("saare",             "all");
        PHRASE_MAPPINGS.put("sare",              "all");
        PHRASE_MAPPINGS.put("sabhi",             "all");
        PHRASE_MAPPINGS.put("sab",               "all");
        PHRASE_MAPPINGS.put("सारे",              "all");
        PHRASE_MAPPINGS.put("सभी",               "all");
        PHRASE_MAPPINGS.put("सब",                "all");

        PHRASE_MAPPINGS.put("cost kitna hai",    "total cost");
        PHRASE_MAPPINGS.put("kitna cost",        "total cost");
        PHRASE_MAPPINGS.put("kitna hai",         "how much");
        PHRASE_MAPPINGS.put("price kitna hai",   "total cost");
        PHRASE_MAPPINGS.put("kharcha kitna hai", "total cost");
        PHRASE_MAPPINGS.put("kitna kharcha",     "total cost");
        PHRASE_MAPPINGS.put("kitna daam",        "total cost");
        PHRASE_MAPPINGS.put("daam kitna",        "total cost");
        PHRASE_MAPPINGS.put("daam kitna hai",    "total cost");
        PHRASE_MAPPINGS.put("total daam",        "total cost");
        PHRASE_MAPPINGS.put("कुल लागत",          "total cost");
        PHRASE_MAPPINGS.put("कुल कीमत",          "total cost");
        PHRASE_MAPPINGS.put("कुल खर्च",          "total cost");
        PHRASE_MAPPINGS.put("कितना खर्च",        "how much cost");
        PHRASE_MAPPINGS.put("दाम कितना",         "how much cost");
        PHRASE_MAPPINGS.put("लागत",              "cost");
        PHRASE_MAPPINGS.put("खर्च",              "cost");
        PHRASE_MAPPINGS.put("कीमत",              "price");
        PHRASE_MAPPINGS.put("दाम",               "price");
        PHRASE_MAPPINGS.put("लैपटॉप्स",          "laptops");
        PHRASE_MAPPINGS.put("लैपटॉप",            "laptop");

        PHRASE_MAPPINGS.put("kaunse assets",     "which assets");
        PHRASE_MAPPINGS.put("dept",              "department");

        PHRASE_MAPPINGS.put("warranty kab expire hoga", "warranty expiry");
        PHRASE_MAPPINGS.put("वारंटी कब खत्म होगा",     "warranty expiry");
        PHRASE_MAPPINGS.put("agle",              "next");
        PHRASE_MAPPINGS.put("अगले",              "next");
        PHRASE_MAPPINGS.put("din",               "days");
        PHRASE_MAPPINGS.put("दिन",               "days");
        PHRASE_MAPPINGS.put("ke andar",          "within");
        PHRASE_MAPPINGS.put("के अंदर",           "within");
        PHRASE_MAPPINGS.put("में",               "in");
        PHRASE_MAPPINGS.put("expired ho gaya",   "expired");
        PHRASE_MAPPINGS.put("वारंटी खत्म",       "warranty expired");
        PHRASE_MAPPINGS.put("वारंटी एक्सपायर",   "warranty expiry");
        PHRASE_MAPPINGS.put("लंबित मेंटेनेंस",   "pending maintenance");

        // ── Odia / Roman Odia ────────────────────────────────────────────────
        PHRASE_MAPPINGS.put("ମୋତେ କୁହ",          "tell me");
        PHRASE_MAPPINGS.put("mote kuha",         "tell me");
        PHRASE_MAPPINGS.put("kuha",              "tell me");
        PHRASE_MAPPINGS.put("କୁହ",               "tell me");
        PHRASE_MAPPINGS.put("ଦେଖାଅ",             "show");
        PHRASE_MAPPINGS.put("ସବୁ",               "all");
        PHRASE_MAPPINGS.put("sabu",              "all");
        PHRASE_MAPPINGS.put("ଲାପଟପ୍",            "laptop");
        PHRASE_MAPPINGS.put("ମୂଲ୍ୟ",             "cost");
        PHRASE_MAPPINGS.put("ଦାମ",               "price");
        PHRASE_MAPPINGS.put("ଖର୍ଚ୍ଚ",            "cost");
        PHRASE_MAPPINGS.put("kete kharcha",      "how much cost");
        PHRASE_MAPPINGS.put("kete daam",         "how much cost");
        PHRASE_MAPPINGS.put("ମୋଟ ମୂଲ୍ୟ",         "total cost");
        PHRASE_MAPPINGS.put("ମୋଟ ଖର୍ଚ୍ଚ",        "total cost");
        PHRASE_MAPPINGS.put("kete cost",         "total cost");
        PHRASE_MAPPINGS.put("laptop ra cost kete","laptop total cost");
        PHRASE_MAPPINGS.put("agami",             "next");
        PHRASE_MAPPINGS.put("ଆଗାମୀ",             "next");
        PHRASE_MAPPINGS.put("dina",              "days");
        PHRASE_MAPPINGS.put("ଦିନ",               "days");
        PHRASE_MAPPINGS.put("warranty kebe expire haba", "warranty expiry");
        PHRASE_MAPPINGS.put("ୱାରେଣ୍ଟି",          "warranty");
        PHRASE_MAPPINGS.put("ମେଣ୍ଟେନାନ୍ସ",       "maintenance");
        PHRASE_MAPPINGS.put("pending maintenance dekhao", "show pending maintenance");

        // Phase 2: QR-related phrases
        PHRASE_MAPPINGS.put("qr code status",       "qr status");
        PHRASE_MAPPINGS.put("qr tagging status",    "qr status");
        PHRASE_MAPPINGS.put("qr tagging",           "qr status");
        PHRASE_MAPPINGS.put("qr tag status",        "qr status");
        PHRASE_MAPPINGS.put("tagging status",       "qr status");
        PHRASE_MAPPINGS.put("asset qr",             "qr status");
        PHRASE_MAPPINGS.put("qr scan logs",         "qr scan logs");
        PHRASE_MAPPINGS.put("qr scan log",          "qr scan logs");
        PHRASE_MAPPINGS.put("qr scan activity",     "qr scan logs");
        PHRASE_MAPPINGS.put("qr activity",          "qr scan logs");
        PHRASE_MAPPINGS.put("qr history",           "qr scan logs");
        PHRASE_MAPPINGS.put("qr sync",              "qr scan logs");

        // Phase 2: Audit-related phrases
        PHRASE_MAPPINGS.put("audit logs",           "audit log");
        PHRASE_MAPPINGS.put("audit trail",          "audit log");
        PHRASE_MAPPINGS.put("audit history",        "audit log");
        PHRASE_MAPPINGS.put("who changed",          "audit log");
        PHRASE_MAPPINGS.put("who made changes",     "audit log");
        PHRASE_MAPPINGS.put("user activity",        "audit log");
        PHRASE_MAPPINGS.put("activity log",         "audit log");
        PHRASE_MAPPINGS.put("action log",           "audit log");
        PHRASE_MAPPINGS.put("change history",       "audit log");
        PHRASE_MAPPINGS.put("system log",           "audit log");

        // Phase 2: Role/Duty-related phrases
        PHRASE_MAPPINGS.put("role duty summary",    "role duty");
        PHRASE_MAPPINGS.put("role duties",          "role duty");
        PHRASE_MAPPINGS.put("duty chart",           "role duty");
        PHRASE_MAPPINGS.put("duty assignment",      "role duty");
        PHRASE_MAPPINGS.put("role assignment",      "role duty");
        PHRASE_MAPPINGS.put("who has admin",        "role duty");
        PHRASE_MAPPINGS.put("who has auditor",      "role duty");
        PHRASE_MAPPINGS.put("assigned roles",       "role duty");
        PHRASE_MAPPINGS.put("user roles",           "role duty");

        // Phase 2: Physical Verification phrases
        PHRASE_MAPPINGS.put("physical verification summary", "physical verification");
        PHRASE_MAPPINGS.put("pv status",            "physical verification");
        PHRASE_MAPPINGS.put("pv summary",           "physical verification");
        PHRASE_MAPPINGS.put("pv duty",              "physical verification");
        PHRASE_MAPPINGS.put("physical check",       "physical verification");
        PHRASE_MAPPINGS.put("asset verification",   "physical verification");
        PHRASE_MAPPINGS.put("verification status",  "physical verification");
        PHRASE_MAPPINGS.put("verification summary", "physical verification");
        PHRASE_MAPPINGS.put("physical audit",       "physical verification");

        // Phase 2: Damaged/Unserviceable
        PHRASE_MAPPINGS.put("faulty assets",        "damaged assets");
        PHRASE_MAPPINGS.put("faulty asset",         "damaged asset");
        PHRASE_MAPPINGS.put("unserviceable assets", "damaged assets");
        PHRASE_MAPPINGS.put("unserviceable asset",  "damaged asset");
        PHRASE_MAPPINGS.put("defective assets",     "damaged assets");
        PHRASE_MAPPINGS.put("broken assets",        "damaged assets");

        // Phase 2: Return-related phrases
        PHRASE_MAPPINGS.put("return records",       "return records");
        PHRASE_MAPPINGS.put("return history",       "return records");
        PHRASE_MAPPINGS.put("all returns",          "return records");
        PHRASE_MAPPINGS.put("returned assets",      "return records");
        PHRASE_MAPPINGS.put("handover records",     "return records");
        PHRASE_MAPPINGS.put("pending returns",      "pending return");
        PHRASE_MAPPINGS.put("pending handover",     "pending return");
        PHRASE_MAPPINGS.put("not yet returned",     "pending return");
        PHRASE_MAPPINGS.put("assets not returned",  "pending return");

        // Phase 2: Asset Requests
        PHRASE_MAPPINGS.put("approved requests",    "approved request");
        PHRASE_MAPPINGS.put("rejected requests",    "rejected request");
        PHRASE_MAPPINGS.put("declined requests",    "rejected request");
        PHRASE_MAPPINGS.put("asset demands",        "asset request");
        PHRASE_MAPPINGS.put("new demands",          "asset request");

        // Phase 2: Category-vendor mapping
        PHRASE_MAPPINGS.put("category vendor mapping",   "category vendor");
        PHRASE_MAPPINGS.put("category supplier mapping", "category vendor");
        PHRASE_MAPPINGS.put("which vendor supplies",     "category vendor");
        PHRASE_MAPPINGS.put("supplier for category",     "category vendor");
        PHRASE_MAPPINGS.put("vendor for category",       "category vendor");

        // Phase 2: Settings-related phrases
        PHRASE_MAPPINGS.put("system settings",     "settings summary");
        PHRASE_MAPPINGS.put("ai mode",             "settings summary");
        PHRASE_MAPPINGS.put("email settings",      "settings summary");
        PHRASE_MAPPINGS.put("currency settings",   "settings summary");
        PHRASE_MAPPINGS.put("app config",          "settings summary");
        PHRASE_MAPPINGS.put("configuration summary", "settings summary");

        // Phase 2: Department employees
        PHRASE_MAPPINGS.put("employees in department",   "employees in");
        PHRASE_MAPPINGS.put("staff in department",       "employees in");
        PHRASE_MAPPINGS.put("workers in department",     "employees in");
        PHRASE_MAPPINGS.put("who works in",              "employees in");
        PHRASE_MAPPINGS.put("who is in",                 "employees in");
    }

    /**
     * Normalize rawQuery, preserving original but returning a clean version
     * suitable for NLU processing.
     *
     * @param rawQuery the original user text
     * @return lowercased, phrase-replaced, particle-stripped, whitespace-normalized text
     */
    public static String normalize(String rawQuery) {
        if (rawQuery == null) return null;

        String normalized = rawQuery.toLowerCase().trim();

        // Apply phrase mappings (longest-phrase first is ensured by iteration order)
        for (Map.Entry<String, String> entry : PHRASE_MAPPINGS.entrySet()) {
            // Use word-boundary regex that works for both ASCII and Unicode scripts
            String regex = "(?<![\\p{L}\\p{Nd}])" + Pattern.quote(entry.getKey()) + "(?![\\p{L}\\p{Nd}])";
            normalized = normalized.replaceAll(regex, entry.getValue());
        }

        // Strip Hindi/Odia grammatical particles that don't add NLU meaning
        normalized = normalized.replace(" ka ",  " ");
        normalized = normalized.replace(" ki ",  " ");
        normalized = normalized.replace(" ke ",  " ");
        normalized = normalized.replace(" ra ",  " ");
        normalized = normalized.replace(" ର ",   " ");   // Odia 'ra'
        normalized = normalized.replace(" no ",  " ");   // Odia 'no' (possessive)
        normalized = normalized.replace(" r ",   " ");   // informal Odia short

        // Collapse multiple spaces
        normalized = normalized.replaceAll("\\s+", " ").trim();

        return normalized;
    }
}
