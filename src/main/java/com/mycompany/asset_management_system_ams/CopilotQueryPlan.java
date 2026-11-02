package com.mycompany.asset_management_system_ams;

import java.time.LocalDate;

/**
 * CopilotQueryPlan -- Structured representation of a parsed user request.
 *
 * Fields are populated sequentially by:
 *   CopilotLanguageNormalizer -> CopilotIntentDetector -> CopilotEntityResolver
 *   -> CopilotTimeResolver -> CopilotReasoningPlanner
 *
 * This plan is then consumed by CopilotToolExecutor and CopilotResponseFormatter.
 */
public class CopilotQueryPlan {

    // Raw + normalized text
    /** The exact text the user sent (never modified) */
    public String rawUserMessage;

    /** Normalized version used for NLU processing */
    public String normalizedTextForNLU;

    /** Optional hint detected during normalization (e.g. "HINDI", "ODIA", "EN") */
    public String detectedLanguageHint;

    // Intent
    public CopilotIntentType intent = CopilotIntentType.UNKNOWN;

    /**
     * Confidence score from 0.0 (no signals) to 1.0 (maximum signals match).
     * Used to decide whether to ask a clarification question.
     */
    public double confidence = 0.0;

    /**
     * Human-readable name of the SQL template / DAO method chosen.
     * Used only for server-side debug logging.
     */
    public String sqlTemplateName;

    /**
     * The IR-AMS module this query targets (e.g. "Assets", "Maintenance").
     * Set by CopilotProjectModuleRegistry via CopilotReasoningPlanner.
     */
    public String targetModule;

    // Entities
    /** Raw text that was matched to a category (e.g. "laptops") */
    public String rawCategory;

    /** Canonical DB category name (e.g. "Laptop") */
    public String normalizedCategory;

    /** Canonical DB department name (e.g. "IT Centre") */
    public String departmentName;

    /** Asset code extracted (e.g. "AST001") */
    public String assetCode;

    /** Employee code extracted (e.g. "EMP006") */
    public String employeeCode;

    /**
     * Employee name extracted from natural language
     * (e.g. "Subham" from "assets assigned to Subham").
     * May be a partial name -- DAO will use LIKE search.
     */
    public String employeeName;

    /** Normalized status string (e.g. "AVAILABLE", "DISPOSED") */
    public String status;

    /**
     * Vendor/supplier name extracted from query
     * (e.g. "HP" from "assets supplied by HP").
     */
    public String vendorName;

    // Time / Date
    /** Filters on when the RECORD was added to AMS (created_at) - "added yesterday", "this month". */
    public LocalDate startDate;
    public LocalDate endDate;
    public Integer   days;
    /** Raw label for the time range, e.g. "THIS_MONTH", "EXPIRED", "NEXT_30_DAYS" */
    public String    dateRangeRaw;

    /**
     * get_maintenance_cost_outliers' own threshold - how many times a
     * category's average total-maintenance-spend-per-asset an asset must
     * exceed to be flagged. A distinct field rather than overloading `days`
     * or another numeric field with a second meaning.
     */
    public Double costMultiplierThreshold;

    /** search_project_knowledge's free-text query - what the user wants explained about how IR-AMS works. */
    public String knowledgeQuery;

    /**
     * Filters on when the ASSET was actually bought (assets.purchase_date) -
     * a different question from startDate/endDate above. "Purchased after
     * 2023" and "added yesterday" are not the same constraint: an asset
     * bought in 2019 can be entered into AMS today. Set by the LLM tool path
     * (CopilotToolCatalog) from a model-supplied ISO date; the keyword
     * fallback path does not currently populate these.
     */
    public LocalDate purchasedAfter;
    public LocalDate purchasedBefore;

    /**
     * Filters on when an EMPLOYEE actually joined (employees.joining_date) -
     * same distinction as purchasedAfter/Before above, just for people
     * instead of assets: "joined last month" is a real, different question
     * from "record added to AMS last month" (an employee who joined in 2019
     * could have their AMS record entered today). Set by the LLM tool path
     * from a model-supplied ISO date; the keyword fallback path does not
     * populate these.
     */
    public LocalDate joinedAfter;
    public LocalDate joinedBefore;

    // Processing flags
    /** Whether this plan requires a live DB call */
    public boolean needsDatabase = false;

    /** Whether the intent is too ambiguous and a clarification is needed */
    public boolean clarificationNeeded = false;

    /** The clarification question to show the user (if clarificationNeeded) */
    public String clarificationPrompt;

    // Response style (set by CopilotResultAnalyzer after DAO returns)
    /** e.g. "TABLE", "DETAIL", "SUMMARY", "COUNT_ONLY", "EMPTY" */
    public String responseStyle;

    // Follow-up / session memory fields
    /** True if this plan was built by inheriting the previous query context */
    public boolean isFollowUp = false;

    /** Human-readable description of what context was inherited */
    public String followUpContext;
}
