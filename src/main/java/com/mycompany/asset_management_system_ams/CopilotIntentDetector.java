package com.mycompany.asset_management_system_ams;

import java.util.logging.Level;
import java.util.logging.Logger;

/**
 * CopilotIntentDetector — Multi-signal, sentence-aware intent classifier.
 *
 * Architecture:
 *   1. Normalize the raw query via CopilotLanguageNormalizer
 *   2. Extract entities (category, dept, assetCode, employeeCode, status) via CopilotEntityResolver
 *   3. Extract time constraints via CopilotTimeResolver
 *   4. Score each intent using multiple keyword signals on the COMBINED text
 *      (raw + normalized) — avoids single-keyword false negatives
 *   5. Pick the highest-scoring intent; compute confidence = score/maxPossible
 *   6. Apply tiebreaker rules and entity-based fallbacks
 *   7. If confidence is too low, set clarificationNeeded = true
 *
 * IMPORTANT: This file MUST NOT generate SQL or call the DB.
 */
public class CopilotIntentDetector {
    private static final Logger LOGGER = Logger.getLogger(CopilotIntentDetector.class.getName());

    // ── Debug flag ─────────────────────────────────────────────────────────────
    private static final boolean DEBUG =
        "true".equalsIgnoreCase(System.getProperty("COPILOT_DEBUG", "false"));

    // ── Confidence threshold below which we ask for clarification ─────────────
    private static final double CLARIFICATION_THRESHOLD = 0.15;

    // ─────────────────────────────────────────────────────────────────────────
    // PUBLIC ENTRY POINT
    // ─────────────────────────────────────────────────────────────────────────

    public static CopilotQueryPlan detectIntent(String rawQuery) {
        CopilotQueryPlan plan = new CopilotQueryPlan();
        plan.rawUserMessage = rawQuery;
        plan.normalizedTextForNLU = CopilotLanguageNormalizer.normalize(rawQuery);

        // Combined text gives the entity resolver the best chance to find something
        // in either the raw (capitalised names) or the normalized (replaced phrases) text
        String combined = rawQuery + " " + plan.normalizedTextForNLU;
        String q = plan.normalizedTextForNLU.toLowerCase().trim();

        if (DEBUG) {
            System.out.println("[COPILOT-DEBUG] RAW       : " + rawQuery);
            System.out.println("[COPILOT-DEBUG] NORMALIZED: " + q);
        }

        // ── Step 1: Entity resolution ────────────────────────────────────────
        CopilotEntityResolver.EntityMatch catMatch = CopilotEntityResolver.extractCategory(combined);
        if (catMatch != null) {
            plan.rawCategory       = catMatch.raw;
            plan.normalizedCategory = catMatch.canonical;
        }

        CopilotEntityResolver.EntityMatch statusMatch = CopilotEntityResolver.extractStatus(combined);
        if (statusMatch != null) {
            plan.status = statusMatch.canonical;
        }

        plan.departmentName  = CopilotEntityResolver.extractDepartment(combined);
        plan.assetCode       = CopilotEntityResolver.extractAssetCode(combined);
        plan.employeeCode    = CopilotEntityResolver.extractEmployeeCode(combined);
        plan.employeeName    = CopilotEntityResolver.extractEmployeeName(rawQuery); // raw keeps capitalisation

        // ── Step 2: Time resolution ───────────────────────────────────────────
        CopilotTimeResolver.TimeMatch timeMatch = CopilotTimeResolver.extractTime(q);
        if (timeMatch != null) {
            plan.startDate    = timeMatch.startDate;
            plan.endDate      = timeMatch.endDate;
            plan.days         = timeMatch.days;
            plan.dateRangeRaw = timeMatch.dateRangeRaw;
        }

        // ── Step 3: High-priority single-signal shortcuts ─────────────────────
        // These have unambiguous trigger phrases that override scoring

        // EXPORT — always first
        if (anyOf(q, "export", "download", "make excel", "excel download", "generate excel")) {
            plan.intent      = CopilotIntentType.EXPORT_CURRENT_RESULT;
            plan.confidence  = 1.0;
            plan.sqlTemplateName = "EXPORT_CURRENT_RESULT";
            debugPlan(plan);
            return plan;
        }

        // HELP
        if (anyOf(q, "help", "how to", "steps to", "guide me", "what can you do", "capabilities")) {
            plan.intent      = CopilotIntentType.HELP_NAVIGATION;
            plan.confidence  = 1.0;
            debugPlan(plan);
            return plan;
        }

        // ── Step 4: Multi-signal scoring ──────────────────────────────────────
        // Each score() call returns the number of signals matched (0–N).
        // We pick the intent with the highest score.

        int scoreCost       = scoreCost(q);
        int scoreDeptSum    = scoreDeptSummary(q);
        int scoreCatSum     = scoreCategorySummary(q);
        int scoreSupplier   = scoreSupplier(q);
        int scoreHolder     = scoreHolder(q, plan);
        int scoreEmpDetails = scoreEmpDetails(q, plan);
        int scoreEmpAlloc   = scoreEmpAllocations(q, plan);
        int scoreAvail      = scoreAvailable(q, plan);
        int scoreAllocated  = scoreAllocated(q);
        int scoreDisposed   = scoreDisposed(q, plan);
        int scorePendReq    = scorePendingRequests(q);
        int scoreWarranty   = scoreWarranty(q);
        int scoreMaint      = scoreMaintenance(q, plan);
        int scoreDashboard  = scoreDashboard(q);
        int scoreCount      = scoreCount(q);
        int scoreList       = scoreList(q, plan);
        int scoreEmployee   = scoreEmployee(q, plan);
        int scoreDept       = scoreDepartment(q, plan);
        int scoreReturn     = scoreReturn(q);
        // Phase 2 scorers
        int scoreDamaged         = scoreDamaged(q, plan);
        int scoreApprovedReq     = scoreApprovedRequests(q);
        int scoreRejectedReq     = scoreRejectedRequests(q);
        int scoreReturnRecs      = scoreReturnRecords(q);
        int scorePendReturns     = scorePendingReturns(q);
        int scoreDeptEmp         = scoreDeptEmployees(q, plan);
        int scoreQrStat          = scoreQrStatus(q);
        int scoreQrLogs          = scoreQrScanLogs(q);
        int scoreAudit           = scoreAudit(q);
        int scoreRoleDuty        = scoreRoleDuty(q);
        int scoreSettings        = scoreSettings(q);
        int scorePhysVer         = scorePhysicalVerification(q);
        int scoreCatVendor       = scoreCategoryVendorMapping(q);
        int scoreValueSummary    = scoreAssetValueSummary(q);


        // Build an array of (intent, score) pairs and pick the winner
        IntentScore[] candidates = {
            new IntentScore(CopilotIntentType.ASSET_TOTAL_COST,             scoreCost),
            new IntentScore(CopilotIntentType.DEPT_SUMMARY,                 scoreDeptSum),
            new IntentScore(CopilotIntentType.CATEGORY_SUMMARY,             scoreCatSum),
            new IntentScore(CopilotIntentType.SUPPLIER_SUMMARY,             scoreSupplier),
            new IntentScore(CopilotIntentType.ASSET_HOLDER,                 scoreHolder),
            new IntentScore(CopilotIntentType.EMPLOYEE_DETAILS,             scoreEmpDetails),
            new IntentScore(CopilotIntentType.EMPLOYEE_ALLOCATIONS,         scoreEmpAlloc),
            new IntentScore(CopilotIntentType.AVAILABLE_ASSETS,             scoreAvail),
            new IntentScore(CopilotIntentType.ALLOCATED_ASSETS,             scoreAllocated),
            new IntentScore(CopilotIntentType.DISPOSED_ASSETS,              scoreDisposed),
            new IntentScore(CopilotIntentType.PENDING_ASSET_REQUESTS,       scorePendReq),
            new IntentScore(CopilotIntentType.DASHBOARD_SUMMARY,            scoreDashboard),
            new IntentScore(CopilotIntentType.ASSET_COUNT,                  scoreCount),
            new IntentScore(CopilotIntentType.ASSET_SEARCH,                 scoreList),
            new IntentScore(CopilotIntentType.EMPLOYEE_SEARCH,              scoreEmployee),
            new IntentScore(CopilotIntentType.DEPARTMENT_SEARCH,            scoreDept),
            new IntentScore(CopilotIntentType.RETURN_SEARCH,                scoreReturn),
            // Phase 2 intents
            new IntentScore(CopilotIntentType.DAMAGED_ASSETS,               scoreDamaged),
            new IntentScore(CopilotIntentType.APPROVED_ASSET_REQUESTS,      scoreApprovedReq),
            new IntentScore(CopilotIntentType.REJECTED_ASSET_REQUESTS,      scoreRejectedReq),
            new IntentScore(CopilotIntentType.RETURN_RECORDS,               scoreReturnRecs),
            new IntentScore(CopilotIntentType.PENDING_RETURNS,              scorePendReturns),
            new IntentScore(CopilotIntentType.DEPARTMENT_EMPLOYEES,         scoreDeptEmp),
            new IntentScore(CopilotIntentType.QR_STATUS,                    scoreQrStat),
            new IntentScore(CopilotIntentType.QR_SCAN_LOGS,                 scoreQrLogs),
            new IntentScore(CopilotIntentType.AUDIT_SEARCH,                 scoreAudit),
            new IntentScore(CopilotIntentType.ROLE_DUTY_SUMMARY,            scoreRoleDuty),
            new IntentScore(CopilotIntentType.SETTINGS_SUMMARY,             scoreSettings),
            new IntentScore(CopilotIntentType.PHYSICAL_VERIFICATION_SUMMARY, scorePhysVer),
            new IntentScore(CopilotIntentType.CATEGORY_VENDOR_MAPPING,      scoreCatVendor),
            new IntentScore(CopilotIntentType.ASSET_VALUE_SUMMARY,          scoreValueSummary),
        };

        // Warranty intent is handled separately because it branches on sub-type
        IntentScore bestNonWarranty = pickBest(candidates);

        // Warranty score
        if (scoreWarranty > 0) {
            CopilotIntentType warrantyType = resolveWarrantySubtype(q, timeMatch);
            if (bestNonWarranty.score < scoreWarranty) {
                plan.intent      = warrantyType;
                plan.confidence  = normalizeScore(scoreWarranty, 4);
                plan.needsDatabase = true;
                if (plan.days == null && plan.intent == CopilotIntentType.WARRANTY_EXPIRING_NEXT_N_DAYS) {
                    plan.days = 30; // sensible default
                }
                plan.sqlTemplateName = plan.intent.name();
                debugPlan(plan);
                return plan;
            }
        }

        // Maintenance sub-type
        if (scoreMaint > 0 && scoreMaint >= bestNonWarranty.score) {
            plan.intent     = resolveMaintSubtype(q, plan);
            plan.confidence = normalizeScore(scoreMaint, 3);
            plan.needsDatabase = true;
            plan.sqlTemplateName = plan.intent.name();
            debugPlan(plan);
            return plan;
        }

        // ── Step 5: Apply winner ───────────────────────────────────────────────
        if (bestNonWarranty.score > 0) {
            plan.intent     = bestNonWarranty.intent;
            plan.confidence = normalizeScore(bestNonWarranty.score, maxSignalsFor(bestNonWarranty.intent));
            plan.needsDatabase = true;
            plan.sqlTemplateName = plan.intent.name();
            debugPlan(plan);
            return plan;
        }

        // ── Step 6: Entity-based fallback ─────────────────────────────────────
        // Even if no clear intent, if entities are present we can do a general search
        if (plan.normalizedCategory != null || plan.departmentName != null
                || plan.status != null || plan.assetCode != null) {
            plan.intent      = CopilotIntentType.ASSET_SEARCH;
            plan.confidence  = 0.3;
            plan.needsDatabase = true;
            plan.sqlTemplateName = "ASSET_SEARCH_ENTITY_FALLBACK";
            debugPlan(plan);
            return plan;
        }

        if (plan.employeeCode != null || plan.employeeName != null) {
            plan.intent      = CopilotIntentType.EMPLOYEE_DETAILS;
            plan.confidence  = 0.3;
            plan.needsDatabase = true;
            plan.sqlTemplateName = "EMPLOYEE_DETAILS_ENTITY_FALLBACK";
            debugPlan(plan);
            return plan;
        }

        // ── Step 7: UNKNOWN with helpful clarification ────────────────────────
        plan.intent             = CopilotIntentType.UNKNOWN;
        plan.confidence         = 0.0;
        plan.needsDatabase      = false;
        plan.clarificationNeeded = true;
        plan.clarificationPrompt =
            "I can help with:\n" +
            "- **Asset cost** (e.g. \"total cost of laptops\")\n" +
            "- **Asset list** (e.g. \"show laptops in IT department\")\n" +
            "- **Employee details or allocations** (e.g. \"assets assigned to EMP006\")\n" +
            "- **Maintenance** (e.g. \"pending maintenance\", \"history of AST003\")\n" +
            "- **Warranty** (e.g. \"warranty expiring in 30 days\")\n" +
            "- **Pending requests / disposed assets / department summary**\n\n" +
            "Please rephrase your question.";
        debugPlan(plan);
        return plan;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // INTENT SCORERS — each returns number of signals matched (0–N)
    // ─────────────────────────────────────────────────────────────────────────

    /** ASSET_TOTAL_COST: cost / value / price / purchase signals */
    private static int scoreCost(String q) {
        int s = 0;
        if (anyOf(q, "total cost", "total purchase cost", "purchase cost")) s += 3;
        if (anyOf(q, "cost", "purchase", "spent", "expenditure", "expense")) s += 1;
        if (anyOf(q, "price", "value", "amount", "worth")) s += 1;
        if (anyOf(q, "how much", "kitna", "kharcha", "daam", "lagat")) s += 1;
        if (anyOf(q, "sum", "total", "aggregate")) s += 1;
        return s;
    }

    /** DEPT_SUMMARY: department-wise / group by department */
    private static int scoreDeptSummary(String q) {
        int s = 0;
        if (q.contains("department wise") || q.contains("dept wise") || q.contains("department-wise")) s += 3;
        if (q.contains("by department") || q.contains("per department")) s += 2;
        if (anyOf(q, "department summary", "dept summary")) s += 3;
        if (anyOf(q, "summary", "overview", "breakdown") && anyOf(q, "department", "dept")) s += 2;
        return s;
    }

    /** CATEGORY_SUMMARY: category-wise / group by category */
    private static int scoreCategorySummary(String q) {
        int s = 0;
        if (q.contains("category wise") || q.contains("category-wise")) s += 3;
        if (q.contains("by category") || q.contains("per category")) s += 2;
        if (anyOf(q, "category summary")) s += 3;
        if (anyOf(q, "summary", "overview", "breakdown") && anyOf(q, "category", "type")) s += 2;
        return s;
    }

    /** SUPPLIER_SUMMARY: vendor / supplier */
    private static int scoreSupplier(String q) {
        int s = 0;
        if (anyOf(q, "vendor summary", "supplier summary", "vendor list", "supplier list")) s += 3;
        if (anyOf(q, "vendor", "supplier", "vendors", "suppliers")) s += 1;
        if (anyOf(q, "summary", "list", "show")) s += 1;
        return s;
    }

    /** ASSET_HOLDER: who has / who holds / holding */
    private static int scoreHolder(String q, CopilotQueryPlan plan) {
        int s = 0;
        if (anyOf(q, "who has", "who holds", "who is holding", "who hold")) s += 3;
        if (anyOf(q, "holder", "custodian", "assigned employee")) s += 2;
        if (anyOf(q, "current holder", "asset holder")) s += 3;
        if (plan.assetCode != null) s += 2; // asset code strongly suggests holder query
        if (anyOf(q, "holding", "using", "using it")) s += 1;
        return s;
    }

    /** EMPLOYEE_DETAILS: employee profile / details of a specific employee */
    private static int scoreEmpDetails(String q, CopilotQueryPlan plan) {
        int s = 0;
        if (anyOf(q, "employee details", "employee profile", "employee info", "staff details")) s += 3;
        if (anyOf(q, "tell me about", "details of", "info of", "information of")) s += 1;
        if (plan.employeeCode != null) s += 2;
        if (anyOf(q, "designation", "contact", "phone", "email") && anyOf(q, "employee", "staff")) s += 2;
        return s;
    }

    /** EMPLOYEE_ALLOCATIONS: assets assigned to an employee */
    private static int scoreEmpAllocations(String q, CopilotQueryPlan plan) {
        int s = 0;
        if (anyOf(q, "assigned to", "allocated to", "assets of", "assets held by")) s += 3;
        if (anyOf(q, "which assets", "what assets") && anyOf(q, "assigned", "allocated")) s += 2;
        if (plan.employeeCode != null || plan.employeeName != null) s += 2;
        if (anyOf(q, "employee assets", "staff assets")) s += 2;
        // Do not fire if there's also an asset_code — that's a holder query
        if (plan.assetCode != null) s -= 2;
        return Math.max(s, 0);
    }

    /** AVAILABLE_ASSETS: available / free / not assigned */
    private static int scoreAvailable(String q, CopilotQueryPlan plan) {
        int s = 0;
        if (anyOf(q, "available assets", "free assets", "unassigned assets")) s += 3;
        if (anyOf(q, "available", "free", "not assigned", "unassigned")) s += 2;
        if (plan.status != null && "AVAILABLE".equals(plan.status)) s += 3;
        return s;
    }

    /** ALLOCATED_ASSETS: allocated / assigned (without specifying to whom) */
    private static int scoreAllocated(String q) {
        int s = 0;
        if (anyOf(q, "allocated assets", "assigned assets", "issued assets")) s += 3;
        if (q.contains("in use") || q.contains("currently allocated")) s += 2;
        // Only if NOT asking about a specific person
        return s;
    }

    /** DISPOSED_ASSETS: disposed / condemned / retired */
    private static int scoreDisposed(String q, CopilotQueryPlan plan) {
        int s = 0;
        if (anyOf(q, "disposed assets", "condemned assets", "retired assets", "scrapped assets")) s += 3;
        if (anyOf(q, "disposed", "condemned", "retired", "written off", "scrapped")) s += 2;
        if (plan.status != null && "DISPOSED".equals(plan.status)) s += 3;
        return s;
    }

    /** PENDING_ASSET_REQUESTS: pending request */
    private static int scorePendingRequests(String q) {
        int s = 0;
        if (anyOf(q, "pending asset request", "pending requests", "asset requests pending")) s += 3;
        if (anyOf(q, "pending request", "open request", "request pending")) s += 2;
        if (anyOf(q, "pending") && anyOf(q, "request")) s += 2;
        return s;
    }

    /** WARRANTY: any warranty mention */
    private static int scoreWarranty(String q) {
        int s = 0;
        if (anyOf(q, "warranty")) s += 2;
        if (anyOf(q, "expiring", "expiry", "expire")) s += 1;
        if (anyOf(q, "expired")) s += 1;
        if (anyOf(q, "days", "next", "within", "soon")) s += 1;
        return s;
    }

    /** MAINTENANCE: repair / maintenance history or pending */
    private static int scoreMaintenance(String q, CopilotQueryPlan plan) {
        int s = 0;
        if (anyOf(q, "maintenance", "repair", "service")) s += 2;
        if (anyOf(q, "history", "log", "past", "records")) s += 1;
        if (anyOf(q, "pending", "ongoing", "in progress")) s += 1;
        if (plan.assetCode != null) s += 1;
        return s;
    }

    /** DASHBOARD_SUMMARY */
    private static int scoreDashboard(String q) {
        int s = 0;
        if (anyOf(q, "dashboard", "summary", "overview", "snapshot")) s += 2;
        if (anyOf(q, "total assets", "how many assets", "all assets count")) s += 1;
        if (anyOf(q, "kpi", "statistics", "stats")) s += 2;
        return s;
    }

    /** ASSET_COUNT */
    private static int scoreCount(String q) {
        int s = 0;
        // Fault: "how many"/"count of" etc. used to score ASSET_COUNT
        // unconditionally, regardless of what the question was actually
        // counting - "how many EMPLOYEES added this month?" scored 2 here
        // purely from "how many", easily beating scoreEmployee()'s single
        // point for "employee", so it always won and answered with an
        // asset count instead. Withhold the generic "how many" bonus when
        // the question is clearly about a different entity (scoreEmployee()
        // below now carries its own matching "how many ... employee" bonus,
        // so EMPLOYEE_SEARCH can actually win those instead).
        boolean asksAboutOtherEntity = anyOf(q, "employee", "employees", "staff", "worker",
                "department", "departments", "vendor", "vendors", "supplier", "suppliers");
        if (anyOf(q, "how many", "count of", "number of", "total number")) {
            if (!asksAboutOtherEntity) {
                s += 2;
            }
        }
        if (anyOf(q, "count", "tally") && !asksAboutOtherEntity) s += 1;
        // Downgrade if cost signals dominate
        if (anyOf(q, "cost", "price", "value")) s -= 1;
        return Math.max(s, 0);
    }

    /** ASSET_SEARCH / LIST_ASSETS */
    private static int scoreList(String q, CopilotQueryPlan plan) {
        int s = 0;
        if (anyOf(q, "show", "list", "display", "give me", "tell me", "find")) s += 1;
        if (anyOf(q, "all", "assets")) s += 1;
        if (plan.normalizedCategory != null) s += 2;
        if (plan.departmentName != null) s += 1;
        if (anyOf(q, "in department", "in dept")) s += 1;
        return s;
    }

    /** EMPLOYEE_SEARCH (generic) */
    private static int scoreEmployee(String q, CopilotQueryPlan plan) {
        int s = 0;
        boolean mentionsEmployee = anyOf(q, "employee", "staff", "worker");
        if (mentionsEmployee) s += 1;
        // Matches the "how many"/"count of" bonus scoreCount() withholds
        // when the question is clearly about employees, not assets - so
        // "how many employees added this month?" actually resolves to
        // EMPLOYEE_SEARCH instead of losing by default to ASSET_COUNT.
        if (mentionsEmployee && anyOf(q, "how many", "count of", "number of", "total number", "count")) {
            s += 2;
        }
        if (plan.employeeCode != null) s += 1;
        if (plan.departmentName != null) s += 1;
        return s;
    }

    /** DEPARTMENT_SEARCH */
    private static int scoreDepartment(String q, CopilotQueryPlan plan) {
        int s = 0;
        boolean mentionsDept = anyOf(q, "department", "dept");
        if (mentionsDept) s += 1;
        if (anyOf(q, "list", "show")) s += 1;
        // Matches the "how many" bonus scoreCount() withholds for department
        // questions - see scoreCount()/scoreEmployee() for the full reasoning.
        if (mentionsDept && anyOf(q, "how many", "count of", "number of", "total number", "count")) {
            s += 2;
        }
        if (plan.departmentName != null) s += 1;
        return s;
    }

    /** RETURN_SEARCH / RETURN_RECORDS: show all return records */
    private static int scoreReturn(String q) {
        int s = 0;
        if (anyOf(q, "return", "returned", "return records", "handover")) s += 2;
        if (anyOf(q, "return history", "returned assets")) s += 2;
        // Downgrade if pending signals dominate
        if (q.contains("pending return") || q.contains("pending handover")) s -= 2;
        return Math.max(s, 0);
    }

    // ── Phase 2 Scorers ───────────────────────────────────────────────────────

    /** DAMAGED_ASSETS: faulty / broken / unserviceable */
    private static int scoreDamaged(String q, CopilotQueryPlan plan) {
        int s = 0;
        if (anyOf(q, "damaged assets", "damaged asset")) s += 3;
        if (anyOf(q, "damaged", "broken", "faulty", "defective", "unserviceable")) s += 2;
        if (plan.status != null && "DAMAGED".equals(plan.status)) s += 3;
        return s;
    }

    /** APPROVED_ASSET_REQUESTS */
    private static int scoreApprovedRequests(String q) {
        int s = 0;
        if (anyOf(q, "approved request", "approved asset request")) s += 3;
        if (q.contains("approved") && anyOf(q, "request", "demand")) s += 2;
        return s;
    }

    /** REJECTED_ASSET_REQUESTS */
    private static int scoreRejectedRequests(String q) {
        int s = 0;
        if (anyOf(q, "rejected request", "rejected asset request", "declined request")) s += 3;
        if (q.contains("rejected") && anyOf(q, "request", "demand")) s += 2;
        return s;
    }

    /** RETURN_RECORDS: all return records (distinct from pending returns) */
    private static int scoreReturnRecords(String q) {
        int s = 0;
        if (anyOf(q, "return records", "all returns", "return history")) s += 3;
        if (anyOf(q, "returned assets", "handover records")) s += 2;
        return s;
    }

    /** PENDING_RETURNS */
    private static int scorePendingReturns(String q) {
        int s = 0;
        if (anyOf(q, "pending return", "pending returns")) s += 3;
        if (anyOf(q, "not yet returned", "assets not returned", "pending handover")) s += 3;
        if (q.contains("pending") && q.contains("return")) s += 2;
        return s;
    }

    /** DEPARTMENT_EMPLOYEES: employees in a department */
    private static int scoreDeptEmployees(String q, CopilotQueryPlan plan) {
        int s = 0;
        if (anyOf(q, "employees in", "staff in", "workers in")) s += 3;
        if (anyOf(q, "who works in", "who is in")) s += 2;
        if (plan.departmentName != null && anyOf(q, "employee", "staff", "worker")) s += 2;
        return s;
    }

    /** QR_STATUS */
    private static int scoreQrStatus(String q) {
        int s = 0;
        if (anyOf(q, "qr status", "qr tagging status", "tagging status")) s += 3;
        if (anyOf(q, "qr code", "qr tag", "asset qr")) s += 2;
        if (anyOf(q, "qr") && anyOf(q, "status", "active", "tagged")) s += 2;
        return s;
    }

    /** QR_SCAN_LOGS */
    private static int scoreQrScanLogs(String q) {
        int s = 0;
        if (anyOf(q, "qr scan logs", "qr scan log")) s += 3;
        if (anyOf(q, "qr activity", "qr history", "qr sync")) s += 2;
        if (anyOf(q, "qr") && anyOf(q, "log", "scan", "activity", "sync")) s += 2;
        return s;
    }

    /** AUDIT_SEARCH */
    private static int scoreAudit(String q) {
        int s = 0;
        if (anyOf(q, "audit log", "audit trail", "audit history")) s += 3;
        if (anyOf(q, "who changed", "change history", "user activity")) s += 3;
        if (anyOf(q, "audit")) s += 1;
        if (anyOf(q, "activity log", "action log", "system log")) s += 2;
        return s;
    }

    /** ROLE_DUTY_SUMMARY */
    private static int scoreRoleDuty(String q) {
        int s = 0;
        if (anyOf(q, "role duty", "duty chart", "role assignment")) s += 3;
        if (anyOf(q, "who has admin", "who has auditor", "assigned roles")) s += 3;
        if (anyOf(q, "user roles", "role summary")) s += 2;
        return s;
    }

    /** SETTINGS_SUMMARY */
    private static int scoreSettings(String q) {
        int s = 0;
        if (anyOf(q, "settings summary", "system settings")) s += 3;
        if (anyOf(q, "ai mode", "email settings", "currency")) s += 2;
        if (anyOf(q, "configuration", "app config")) s += 2;
        return s;
    }

    /** PHYSICAL_VERIFICATION_SUMMARY */
    private static int scorePhysicalVerification(String q) {
        int s = 0;
        if (anyOf(q, "physical verification")) s += 3;
        if (anyOf(q, "pv status", "pv summary", "pv duty")) s += 3;
        if (anyOf(q, "verification status", "verification summary")) s += 2;
        if (anyOf(q, "physical check", "asset verification", "physical audit")) s += 2;
        return s;
    }

    /** CATEGORY_VENDOR_MAPPING */
    private static int scoreCategoryVendorMapping(String q) {
        int s = 0;
        if (anyOf(q, "category vendor", "category vendor mapping")) s += 3;
        if (anyOf(q, "which vendor supplies", "supplier for category", "vendor for category")) s += 3;
        if (q.contains("category") && anyOf(q, "vendor", "supplier")) s += 2;
        return s;
    }

    /** ASSET_VALUE_SUMMARY */
    private static int scoreAssetValueSummary(String q) {
        int s = 0;
        if (anyOf(q, "asset value summary", "value summary", "asset worth")) s += 3;
        if (anyOf(q, "total value") && anyOf(q, "department wise", "category wise")) s += 3;
        if (anyOf(q, "total value", "total asset value")) s += 2;
        if (anyOf(q, "value") && anyOf(q, "summary", "overview", "breakdown")) s += 1;
        return s;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // SUBTYPE RESOLVERS
    // ─────────────────────────────────────────────────────────────────────────

    private static CopilotIntentType resolveWarrantySubtype(String q, CopilotTimeResolver.TimeMatch timeMatch) {
        // Check "expired" as a word (NOT "expiring")
        boolean isExpired = false;
        int idx = q.indexOf("expired");
        if (idx >= 0) {
            boolean before = (idx == 0) || !Character.isLetterOrDigit(q.charAt(idx - 1));
            int end = idx + "expired".length();
            boolean after = (end >= q.length()) || !Character.isLetterOrDigit(q.charAt(end));
            isExpired = before && after;
        }

        if (isExpired || (timeMatch != null && "EXPIRED".equals(timeMatch.dateRangeRaw))) {
            return CopilotIntentType.WARRANTY_EXPIRED;
        }
        if (timeMatch != null && "THIS_MONTH".equals(timeMatch.dateRangeRaw)) {
            return CopilotIntentType.WARRANTY_THIS_MONTH;
        }
        // Default: expiring (future)
        return CopilotIntentType.WARRANTY_EXPIRING_NEXT_N_DAYS;
    }

    private static CopilotIntentType resolveMaintSubtype(String q, CopilotQueryPlan plan) {
        if (anyOf(q, "history", "log", "past", "records") || plan.assetCode != null) {
            return CopilotIntentType.MAINTENANCE_HISTORY;
        }
        return CopilotIntentType.MAINTENANCE_PENDING;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // UTILITIES
    // ─────────────────────────────────────────────────────────────────────────

    /** True if any of the given substrings is found in q */
    private static boolean anyOf(String q, String... tokens) {
        for (String t : tokens) {
            if (q.contains(t)) return true;
        }
        return false;
    }

    /** Pick the IntentScore with the highest score */
    private static IntentScore pickBest(IntentScore[] candidates) {
        IntentScore best = new IntentScore(CopilotIntentType.UNKNOWN, 0);
        for (IntentScore c : candidates) {
            if (c.score > best.score) best = c;
        }
        return best;
    }

    /** Normalize a raw score to [0.0, 1.0] */
    private static double normalizeScore(int score, int max) {
        if (max <= 0) return 0.0;
        return Math.min(1.0, (double) score / max);
    }

    /**
     * Rough maximum signal count for each intent (used to compute confidence).
     * Higher values → harder to reach 1.0, which is appropriate for intents
     * with more ambiguity.
     */
    private static int maxSignalsFor(CopilotIntentType intent) {
        switch (intent) {
            case ASSET_TOTAL_COST:               return 7;
            case DEPT_SUMMARY:                   return 5;
            case CATEGORY_SUMMARY:               return 5;
            case SUPPLIER_SUMMARY:               return 4;
            case ASSET_HOLDER:                   return 7;
            case EMPLOYEE_DETAILS:               return 5;
            case EMPLOYEE_ALLOCATIONS:           return 6;
            case AVAILABLE_ASSETS:               return 5;
            case ALLOCATED_ASSETS:               return 4;
            case DISPOSED_ASSETS:                return 5;
            case PENDING_ASSET_REQUESTS:         return 5;
            case DASHBOARD_SUMMARY:              return 4;
            case ASSET_COUNT:                    return 3;
            case ASSET_SEARCH:                   return 5;
            case EMPLOYEE_SEARCH:                return 3;
            case DEPARTMENT_SEARCH:              return 3;
            case RETURN_SEARCH:                  return 4;
            // Phase 2
            case DAMAGED_ASSETS:                 return 5;
            case APPROVED_ASSET_REQUESTS:        return 4;
            case REJECTED_ASSET_REQUESTS:        return 4;
            case RETURN_RECORDS:                 return 4;
            case PENDING_RETURNS:                return 5;
            case DEPARTMENT_EMPLOYEES:           return 5;
            case QR_STATUS:                      return 5;
            case QR_SCAN_LOGS:                   return 5;
            case AUDIT_SEARCH:                   return 5;
            case ROLE_DUTY_SUMMARY:              return 5;
            case SETTINGS_SUMMARY:               return 4;
            case PHYSICAL_VERIFICATION_SUMMARY:  return 5;
            case CATEGORY_VENDOR_MAPPING:        return 5;
            case ASSET_VALUE_SUMMARY:            return 5;
            default:                             return 3;
        }
    }

    private static void debugPlan(CopilotQueryPlan plan) {
        if (!DEBUG) return;
        System.out.println("[COPILOT-DEBUG] INTENT    : " + plan.intent + " (confidence=" + String.format("%.2f", plan.confidence) + ")");
        System.out.println("[COPILOT-DEBUG] ENTITIES  : category=" + plan.normalizedCategory
            + " dept=" + plan.departmentName
            + " assetCode=" + plan.assetCode
            + " empCode=" + plan.employeeCode
            + " empName=" + plan.employeeName
            + " status=" + plan.status
            + " days=" + plan.days);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // HELPER CLASS
    // ─────────────────────────────────────────────────────────────────────────

    private static class IntentScore {
        final CopilotIntentType intent;
        final int score;
        IntentScore(CopilotIntentType intent, int score) {
            this.intent = intent;
            this.score  = score;
        }
    }
}
