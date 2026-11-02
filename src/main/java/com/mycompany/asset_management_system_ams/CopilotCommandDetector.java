package com.mycompany.asset_management_system_ams;

import java.util.regex.Matcher;
import java.util.regex.Pattern;
import java.util.UUID;
import java.util.Arrays;

public class CopilotCommandDetector {

    public static CopilotCommandPlan detectCommand(String rawQuery) {
        if (rawQuery == null || rawQuery.trim().isEmpty()) {
            return null;
        }

        // Normalize text slightly for easier matching
        String query = rawQuery.toLowerCase().trim();
        CopilotCommandPlan plan = new CopilotCommandPlan();
        plan.rawUserMessage = rawQuery;

        // Fault: every command pattern below matches on bare substrings like
        // query.contains("add") + query.contains("asset") - which also matches
        // pure analytical questions built from the exact same words, e.g.
        // "how many assets ADDed yesterday?" or "how many employees ADDed
        // this month?". Both got misrouted into CREATE_ASSET/CREATE_EMPLOYEE's
        // slot-filling flow ("To proceed, I still need: category, brandModel,
        // department, cost") instead of ever reaching CopilotIntentDetector's
        // ASSET_COUNT/EMPLOYEE_SEARCH handling below (in CopilotEngine, this
        // method runs BEFORE the query-intent pipeline, so a false match here
        // hijacks the question entirely - it never even gets a chance to be
        // classified correctly). Reproduced exactly from the reported
        // screenshots. A genuine imperative command ("add asset...", "create
        // employee...") is never phrased as a question about the past - so
        // bail out to the analytical pipeline whenever the query looks like
        // one, before any of the substring checks below get a chance to
        // misfire on it.
        if (looksLikeAnalyticalQuestion(query)) {
            return null;
        }

        // ----------------------------------------------------
        // EXPORT / REPORTS
        // ----------------------------------------------------
        if (query.equals("export this") || query.equals("export current result")) {
            plan.intent = CopilotIntentType.EXPORT_CURRENT_RESULT;
            return plan;
        }
        if (query.contains("generate") && query.contains("report") || query.contains("export") && query.contains("report")) {
            plan.intent = CopilotIntentType.EXPORT_REPORT;
            return plan;
        }

        // ----------------------------------------------------
        // ALLOCATION & RETURN
        // ----------------------------------------------------
        if (query.contains("allocate") || query.contains("assign") || query.contains("allocate karo")) {
            plan.intent = CopilotIntentType.ALLOCATE_ASSET;
            plan.targetModule = "ALLOCATION";
            plan.actionType = "CREATE";
            extractAssetAndEmployee(query, plan);
            checkRequired(plan, "assetCode", "employeeCode");
            setConfirmation(plan, false, "allocate asset " + plan.extractedFields.get("assetCode") + " to employee " + plan.extractedFields.get("employeeCode"));
            return plan;
        }

        if (query.contains("return") && (query.contains("asset") || query.contains("ast"))) {
            plan.intent = CopilotIntentType.RETURN_ASSET;
            plan.targetModule = "RETURN";
            plan.actionType = "CREATE";
            extractAssetCode(query, plan);
            checkRequired(plan, "assetCode");
            setConfirmation(plan, false, "return asset " + plan.extractedFields.get("assetCode"));
            return plan;
        }

        // ----------------------------------------------------
        // MAINTENANCE
        // ----------------------------------------------------
        if ((query.contains("create") || query.contains("add")) && query.contains("maintenance request")) {
            plan.intent = CopilotIntentType.CREATE_MAINTENANCE_REQUEST;
            plan.targetModule = "MAINTENANCE";
            plan.actionType = "CREATE";
            extractAssetCode(query, plan);
            extractIssue(query, plan);
            checkRequired(plan, "assetCode", "issue");
            setConfirmation(plan, false, "create maintenance request for " + plan.extractedFields.get("assetCode") + " with issue: " + plan.extractedFields.get("issue"));
            return plan;
        }

        if (query.contains("mark maintenance") && (query.contains("completed") || query.contains("complete"))) {
            plan.intent = CopilotIntentType.UPDATE_MAINTENANCE_STATUS;
            plan.targetModule = "MAINTENANCE";
            plan.actionType = "UPDATE";
            plan.extractedFields.put("status", "COMPLETED");
            extractIdOrAsset(query, plan);
            checkRequired(plan, "targetId");
            setConfirmation(plan, false, "mark maintenance " + plan.extractedFields.get("targetId") + " as COMPLETED");
            return plan;
        }

        // ----------------------------------------------------
        // ASSET REQUESTS
        // ----------------------------------------------------
        if (query.contains("approve asset request") || (query.contains("approve") && query.contains("request"))) {
            plan.intent = CopilotIntentType.APPROVE_ASSET_REQUEST;
            plan.targetModule = "REQUESTS";
            plan.actionType = "UPDATE";
            extractIdOrAsset(query, plan);
            checkRequired(plan, "targetId");
            setConfirmation(plan, false, "approve request " + plan.extractedFields.get("targetId"));
            return plan;
        }

        if (query.contains("reject asset request") || (query.contains("reject") && query.contains("request"))) {
            plan.intent = CopilotIntentType.REJECT_ASSET_REQUEST;
            plan.targetModule = "REQUESTS";
            plan.actionType = "UPDATE";
            extractIdOrAsset(query, plan);
            extractReason(query, plan);
            checkRequired(plan, "targetId", "reason");
            setConfirmation(plan, false, "reject request " + plan.extractedFields.get("targetId") + " with reason: " + plan.extractedFields.get("reason"));
            return plan;
        }

        // ----------------------------------------------------
        // EMPLOYEE ACTIONS
        // ----------------------------------------------------
        if (query.contains("delete employee") || query.matches(".*employee.*delete.*")) {
            plan.intent = CopilotIntentType.DELETE_EMPLOYEE;
            plan.targetModule = "EMPLOYEE";
            plan.actionType = "DELETE";
            extractEmployeeCode(query, plan);
            checkRequired(plan, "employeeCode");
            setConfirmation(plan, true, "delete employee " + plan.extractedFields.get("employeeCode"));
            return plan;
        }

        if (query.contains("disable employee") || query.matches(".*employee.*disable.*")) {
            plan.intent = CopilotIntentType.DISABLE_EMPLOYEE;
            plan.targetModule = "EMPLOYEE";
            plan.actionType = "DISABLE";
            extractEmployeeCode(query, plan);
            checkRequired(plan, "employeeCode");
            setConfirmation(plan, true, "disable employee " + plan.extractedFields.get("employeeCode"));
            return plan;
        }

        if ((query.contains("add") || query.contains("create") || query.contains("jodo")) && 
            (query.contains("employee") || query.contains("karmachari"))) {
            plan.intent = CopilotIntentType.CREATE_EMPLOYEE;
            plan.targetModule = "EMPLOYEE";
            plan.actionType = "CREATE";
            extractNameAndDept(rawQuery, query, plan);
            checkRequired(plan, "name", "department", "designation", "contact");
            setConfirmation(plan, false, "create employee: " + plan.extractedFields.get("name"));
            return plan;
        }

        if ((query.contains("edit") || query.contains("update")) && 
            (query.contains("employee") || query.matches(".*emp\\d+.*"))) {
            plan.intent = CopilotIntentType.UPDATE_EMPLOYEE;
            plan.targetModule = "EMPLOYEE";
            plan.actionType = "UPDATE";
            extractEmployeeCode(query, plan);
            extractUpdateField(query, plan);
            checkRequired(plan, "employeeCode", "updateField", "updateValue");
            setConfirmation(plan, false, "update " + plan.extractedFields.get("updateField") + " for employee " + plan.extractedFields.get("employeeCode"));
            return plan;
        }

        // ----------------------------------------------------
        // ASSET ACTIONS
        // ----------------------------------------------------
        if (query.contains("delete asset") || query.matches(".*asset.*delete.*") || query.matches(".*ast\\d+.*delete.*")) {
            plan.intent = CopilotIntentType.DELETE_ASSET;
            plan.targetModule = "ASSET";
            plan.actionType = "DELETE";
            extractAssetCode(query, plan);
            checkRequired(plan, "assetCode");
            setConfirmation(plan, true, "delete asset " + plan.extractedFields.get("assetCode"));
            return plan;
        }

        if ((query.contains("edit") || query.contains("update") || query.contains("change")) && 
            (query.contains("asset") || query.matches(".*ast\\d+.*"))) {
            plan.intent = CopilotIntentType.UPDATE_ASSET;
            plan.targetModule = "ASSET";
            plan.actionType = "UPDATE";
            extractAssetCode(query, plan);
            extractUpdateField(query, plan);
            checkRequired(plan, "assetCode", "updateField", "updateValue");
            setConfirmation(plan, false, "update " + plan.extractedFields.get("updateField") + " for asset " + plan.extractedFields.get("assetCode"));
            return plan;
        }

        if ((query.contains("add") || query.contains("create") || query.contains("add karo")) && 
            (query.contains("asset") || query.contains("laptop") || query.contains("printer"))) {
            plan.intent = CopilotIntentType.CREATE_ASSET;
            plan.targetModule = "ASSET";
            plan.actionType = "CREATE";
            extractAssetDetails(rawQuery, query, plan);
            checkRequired(plan, "category", "brandModel", "department", "cost");
            setConfirmation(plan, false, "create asset: " + plan.extractedFields.get("category") + " " + plan.extractedFields.get("brandModel"));
            return plan;
        }

        return null; // Not a command intent
    }

    // Question phrasing ("how many...", "...?") always means the user wants
    // information, never a write action - checked once, up front, rather than
    // patched into every individual contains("add")-style match below.
    private static final String[] QUESTION_LEAD_INS = {
        "how many", "how much", "count of", "number of", "total number",
        "what is", "what are", "which ", "list ", "show me", "show all",
        "give me the count", "who added", "who created",
        // Same "was something added/changed?" question, phrased without a
        // classic wh-word lead-in or a trailing "?" - paraphrases of the
        // same intent, not a different one, and must resolve the same way.
        "any ", "did anyone", "was there", "were there", "has anyone"
    };

    // Package-private (not private) so CopilotWriteIntentClassifier can reuse
    // the exact same "does this look like a question, not an instruction"
    // gate before spending an LLM call on write-intent classification - the
    // same reasoning that keeps this check running first in
    // detectCommand() above applies there too.
    static boolean looksLikeAnalyticalQuestion(String query) {
        if (query.indexOf('?') >= 0) {
            return true;
        }

        for (String leadIn : QUESTION_LEAD_INS) {
            if (query.startsWith(leadIn) || query.contains(" " + leadIn)) {
                return true;
            }
        }

        return false;
    }

    private static void extractAssetAndEmployee(String q, CopilotCommandPlan p) {
        Matcher mAst = Pattern.compile("(ast\\d{3,5})").matcher(q);
        if (mAst.find()) p.extractedFields.put("assetCode", mAst.group(1).toUpperCase());
        Matcher mEmp = Pattern.compile("(emp\\d{3,5})").matcher(q);
        if (mEmp.find()) p.extractedFields.put("employeeCode", mEmp.group(1).toUpperCase());
    }

    private static void extractAssetCode(String q, CopilotCommandPlan p) {
        Matcher mAst = Pattern.compile("(ast\\d{3,5})").matcher(q);
        if (mAst.find()) p.extractedFields.put("assetCode", mAst.group(1).toUpperCase());
    }

    private static void extractEmployeeCode(String q, CopilotCommandPlan p) {
        Matcher mEmp = Pattern.compile("(emp\\d{3,5})").matcher(q);
        if (mEmp.find()) p.extractedFields.put("employeeCode", mEmp.group(1).toUpperCase());
    }

    private static void extractIdOrAsset(String q, CopilotCommandPlan p) {
        Matcher m = Pattern.compile("(request\\s+|maintenance\\s+)?(ast\\d+|\\d+)").matcher(q);
        if (m.find()) {
            p.extractedFields.put("targetId", m.group(2).toUpperCase());
        }
    }

    private static void extractIssue(String q, CopilotCommandPlan p) {
        Matcher m = Pattern.compile("issue\\s+(.+)").matcher(q);
        if (m.find()) p.extractedFields.put("issue", m.group(1));
    }

    private static void extractReason(String q, CopilotCommandPlan p) {
        Matcher m = Pattern.compile("reason\\s+(.+)").matcher(q);
        if (m.find()) p.extractedFields.put("reason", m.group(1));
    }

    private static void extractNameAndDept(String raw, String q, CopilotCommandPlan p) {
        // Simple extraction heuristic
        Matcher mName = Pattern.compile("employee\\s+([A-Z][a-z]+\\s*[A-Z]?[a-z]*)").matcher(raw);
        if (mName.find()) p.extractedFields.put("name", mName.group(1));
        
        Matcher mDept = Pattern.compile("in\\s+([a-zA-Z\\s]+)\\s+department").matcher(q);
        if (mDept.find()) p.extractedFields.put("department", mDept.group(1));
        else if (q.contains("electrical")) p.extractedFields.put("department", "Electrical");
        
        if (q.contains("technician")) p.extractedFields.put("designation", "Technician");
    }

    private static void extractUpdateField(String q, CopilotCommandPlan p) {
        if (q.contains("mobile")) {
            p.extractedFields.put("updateField", "mobile");
            Matcher m = Pattern.compile("to\\s+(\\d{10})").matcher(q);
            if (m.find()) p.extractedFields.put("updateValue", m.group(1));
        } else if (q.contains("status")) {
            p.extractedFields.put("updateField", "status");
            Matcher m = Pattern.compile("to\\s+([a-z\\s]+)").matcher(q);
            if (m.find()) p.extractedFields.put("updateValue", m.group(1).trim().toUpperCase().replace(" ", "_"));
        } else if (q.contains("department")) {
            p.extractedFields.put("updateField", "department");
            Matcher m = Pattern.compile("to\\s+([a-z]+)").matcher(q);
            if (m.find()) p.extractedFields.put("updateValue", m.group(1));
        }
    }

    private static void extractAssetDetails(String raw, String q, CopilotCommandPlan p) {
        if (q.contains("laptop")) p.extractedFields.put("category", "Laptop");
        else if (q.contains("printer")) p.extractedFields.put("category", "Printer");

        Matcher mCost = Pattern.compile("cost\\s+(\\d+)").matcher(q);
        if (mCost.find()) p.extractedFields.put("cost", mCost.group(1));

        Matcher mDept = Pattern.compile("in\\s+([a-zA-Z\\s]+)\\s+(department|centre)").matcher(q);
        if (mDept.find()) p.extractedFields.put("department", mDept.group(1));

        // Attempt brand/model extraction
        Matcher mBrand = Pattern.compile("(laptop|printer)\\s+([A-Z][a-zA-Z0-9\\s]+)\\s+cost").matcher(raw);
        if (mBrand.find()) p.extractedFields.put("brandModel", mBrand.group(2).trim());
    }

    private static void checkRequired(CopilotCommandPlan p, String... fields) {
        for (String f : fields) {
            if (!p.extractedFields.containsKey(f) || p.extractedFields.get(f) == null) {
                p.missingRequiredFields.add(f);
            }
        }
    }

    private static void setConfirmation(CopilotCommandPlan p, boolean destructive, String msg) {
        p.requiresConfirmation = true;
        p.destructiveAction = destructive;
        p.previewMessage = msg;
        p.confirmationToken = UUID.randomUUID().toString();
        
        if (destructive) {
            String target = p.extractedFields.getOrDefault("employeeCode", p.extractedFields.getOrDefault("assetCode", "RECORD"));
            p.strongConfirmationText = "CONFIRM " + p.actionType.toUpperCase() + " " + target;
        }
    }
}
