package com.mycompany.asset_management_system_ams;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

import jakarta.servlet.http.HttpSession;

/**
 * CopilotToolCatalog — the bridge between the model and the existing DAO layer.
 *
 * The model NEVER writes SQL and never names a table. It picks a tool by name
 * from this catalog and supplies string parameters; this class maps those onto
 * a CopilotQueryPlan and calls the corresponding CopilotToolExecutor method —
 * the same PreparedStatement-backed, role-scoped code the keyword pipeline has
 * always used. Every security property of that layer is preserved unchanged.
 *
 * Two independent role layers, deliberately (same defence-in-depth shape as
 * RoleAccessUtil + each page's own gate):
 *
 *   1. forRole() filters the catalog BEFORE it is serialized into the request,
 *      so a lower-privileged user's model is never even told that a restricted
 *      tool exists — it cannot ask for what it cannot see.
 *   2. Each CopilotToolExecutor method re-reads the session role itself and
 *      scopes or refuses on its own. A bug in layer 1 is still caught by
 *      layer 2.
 *
 * READ-ONLY BY DESIGN. No write/mutation tool is exposed here. Create, approve,
 * reject, and delete continue to run through CopilotCommandDetector's strict
 * keyword path with its typed-confirmation gate — an LLM misreading "show" is
 * recoverable; an LLM misreading "delete" is not.
 */
public final class CopilotToolCatalog {

    // ── Role groups, mirroring the app's existing access boundaries ──────────
    private static final List<String> ALL =
            Arrays.asList("SUPER_ADMIN", "ADMIN", "ASSET_MANAGER", "DEPARTMENT_HEAD", "AUDITOR", "EMPLOYEE");
    private static final List<String> NON_EMPLOYEE =
            Arrays.asList("SUPER_ADMIN", "ADMIN", "ASSET_MANAGER", "DEPARTMENT_HEAD", "AUDITOR");
    private static final List<String> ASSET_OPS_AND_AUDIT =
            Arrays.asList("SUPER_ADMIN", "ADMIN", "ASSET_MANAGER", "AUDITOR");
    private static final List<String> AUDIT_ONLY =
            Arrays.asList("SUPER_ADMIN", "ADMIN", "AUDITOR");
    private static final List<String> ADMIN_ONLY =
            Arrays.asList("SUPER_ADMIN", "ADMIN");

    /** One catalog entry: what the model sees, plus who is allowed to see it. */
    private static final class Entry {
        final LlmToolSpec spec;
        final List<String> roles;

        Entry(LlmToolSpec spec, List<String> roles) {
            this.spec = spec;
            this.roles = roles;
        }
    }

    private static final Map<String, Entry> CATALOG = new LinkedHashMap<String, Entry>();

    private CopilotToolCatalog() {
    }

    static {
        // ── General / how IR-AMS works ──────────────────────────────────────
        add(ALL, new LlmToolSpec("search_project_knowledge",
                "Explains HOW a part of IR-AMS actually works, its business rules, and role permissions -"
                        + " for conceptual questions like 'how does asset request approval work', 'what "
                        + "happens when I mark an asset damaged', 'what can a department head do', or 'why "
                        + "would my request go to my department head first'. This is NOT for live data "
                        + "(counts, lists, who holds what) - use the other tools for that. Always prefer "
                        + "this tool over answering a how-it-works question from your own general "
                        + "knowledge of asset-management systems, since this system's real behavior has "
                        + "specific, non-obvious rules a generic answer would get wrong.")
                .param("query", "The user's question or topic, in plain language, e.g. "
                        + "'asset request approval workflow' or 'what does auditor role allow'"));

        // ── Assets ───────────────────────────────────────────────────────────
        add(ALL, new LlmToolSpec("search_assets",
                "Search the asset register. Filter by category, department, status, asset code, "
                        + "purchase date, or when the record was added to AMS. Use for questions like "
                        + "'show laptops in IT', 'list printers purchased after 2023', or 'how many "
                        + "assets were added this month' (use addedAfter/addedBefore for that last "
                        + "one - it is a DIFFERENT date from purchasedAfter/Before: an asset bought "
                        + "years ago can still be entered into AMS today).")
                .param("category", "Asset category, e.g. Laptop, Printer, Furniture")
                .param("department", "Department name, e.g. IT Centre")
                .param("status", "Asset status", "AVAILABLE", "ALLOCATED", "UNDER_MAINTENANCE", "DAMAGED", "DISPOSED")
                .param("assetCode", "Specific asset code, e.g. AST001")
                .param("purchasedAfter", "Only assets bought on or after this date, as YYYY-MM-DD "
                        + "(e.g. a request for 'purchased after 2023' means 2023-01-01)")
                .param("purchasedBefore", "Only assets bought before this date, as YYYY-MM-DD")
                .param("addedAfter", "Only assets whose AMS record was created on or after this date, "
                        + "as YYYY-MM-DD - use for 'added/registered this month/week/yesterday', NOT "
                        + "for purchase date")
                .param("addedBefore", "Only assets whose AMS record was created before this date, as YYYY-MM-DD"));

        add(ALL, new LlmToolSpec("get_asset_total_cost",
                "Total purchase cost of assets, optionally narrowed to one category or department. "
                        + "Use for 'what is the total cost of laptops'.")
                .param("category", "Asset category to total")
                .param("department", "Department to total"));

        add(ALL, new LlmToolSpec("get_available_assets",
                "Assets currently AVAILABLE (in stores, not allocated to anyone).")
                .param("category", "Optional category filter")
                .param("department", "Optional department filter"));

        add(ALL, new LlmToolSpec("get_allocated_assets",
                "Assets currently issued to an employee.")
                .param("category", "Optional category filter")
                .param("department", "Optional department filter"));

        add(ALL, new LlmToolSpec("get_asset_holder",
                "Who currently holds a specific asset. Requires the asset code.")
                .param("assetCode", "Asset code, e.g. AST001"));

        add(ALL, new LlmToolSpec("get_damaged_assets",
                "Assets recorded as damaged or in a non-serviceable condition.")
                .param("category", "Optional category filter"));

        add(ALL, new LlmToolSpec("get_asset_value_summary",
                "Aggregate asset value totals across the register."));

        add(NON_EMPLOYEE, new LlmToolSpec("get_disposed_assets",
                "Assets that have been disposed, retired, or written off.")
                .param("category", "Optional category filter"));

        add(NON_EMPLOYEE, new LlmToolSpec("get_asset_disposal_details",
                "The disposal WORKFLOW record for an asset: reason, proposed/approved/final method "
                        + "(scrap, auction, sale, donation, write-off, e-waste, return to vendor), "
                        + "proposed/approved/realised value, and status through its approval chain. "
                        + "Use for 'why was AST020 disposed', 'what method was used', 'how much did "
                        + "we recover from disposals' - distinct from get_disposed_assets, which only "
                        + "reports current status, not the reason/method/value detail.")
                .param("assetCode", "Optional specific asset code, e.g. AST020")
                .param("status", "Optional disposal workflow status", "PENDING", "APPROVED",
                        "COMPLETED", "REJECTED", "CANCELLED"));

        // ── Employees ────────────────────────────────────────────────────────
        add(ALL, new LlmToolSpec("get_employee_details",
                "Profile details for one employee. Give an employee code or a name.")
                .param("employeeCode", "Employee code, e.g. EMP006")
                .param("employeeName", "Full or partial employee name"));

        add(ALL, new LlmToolSpec("get_employee_allocations",
                "Assets currently assigned to a specific employee. "
                        + "Use for 'which assets does Subham have'.")
                .param("employeeCode", "Employee code, e.g. EMP006")
                .param("employeeName", "Full or partial employee name"));

        add(NON_EMPLOYEE, new LlmToolSpec("search_employees",
                "Search the employee register by name, code, department, or when the record was "
                        + "added to AMS.")
                .param("employeeName", "Full or partial name")
                .param("employeeCode", "Specific employee code, e.g. EMP006")
                .param("department", "Department name")
                .param("addedAfter", "Only employees whose AMS record was created on or after this "
                        + "date, as YYYY-MM-DD - this is when the RECORD was entered, not when they "
                        + "joined (use get_employees_by_joining_date for that)")
                .param("addedBefore", "Only employees whose AMS record was created before this date, as YYYY-MM-DD"));

        add(NON_EMPLOYEE, new LlmToolSpec("get_department_employees",
                "All employees in one department.")
                .param("department", "Department name, e.g. IT Centre"));

        add(NON_EMPLOYEE, new LlmToolSpec("get_employees_by_joining_date",
                "Employees by when they actually joined (a real date column, distinct from "
                        + "when their AMS record was created). Use for 'who joined last month', "
                        + "'new hires this quarter', 'employees who joined in IT since 2024'.")
                .param("joinedAfter", "Only employees who joined on or after this date, as "
                        + "YYYY-MM-DD (e.g. 'joined last month' means the 1st of last month)")
                .param("joinedBefore", "Only employees who joined on or before this date, as YYYY-MM-DD "
                        + "(e.g. 'joined last month' means the last day of last month)")
                .param("department", "Optional department filter, e.g. IT Centre"));

        // ── Allocation / returns ─────────────────────────────────────────────
        add(ALL, new LlmToolSpec("search_allocations",
                "Allocation and issue records — who was given what, and when.")
                .param("employeeCode", "Optional employee code")
                .param("department", "Optional department")
                .param("assetCode", "Optional asset code"));

        add(ALL, new LlmToolSpec("get_return_records",
                "Assets that have been returned by employees."));

        add(ALL, new LlmToolSpec("get_pending_returns",
                "Returns that are still awaiting processing."));

        // ── Asset requests ───────────────────────────────────────────────────
        add(ALL, new LlmToolSpec("get_pending_asset_requests",
                "Asset requests awaiting approval."));

        add(ALL, new LlmToolSpec("get_approved_requests",
                "Asset requests that have been approved."));

        add(ALL, new LlmToolSpec("get_rejected_requests",
                "Asset requests that have been rejected."));

        // ── Maintenance / warranty ───────────────────────────────────────────
        add(ALL, new LlmToolSpec("get_pending_maintenance",
                "Open or in-progress maintenance and service jobs.")
                .param("category", "Optional category filter"));

        add(ALL, new LlmToolSpec("get_maintenance_history",
                "Past maintenance records, optionally for one asset.")
                .param("assetCode", "Optional asset code, e.g. AST003"));

        add(ALL, new LlmToolSpec("get_warranty",
                "Warranty status. Use days for a forward window (e.g. days=30 for "
                        + "'expiring in the next 30 days'), or status=EXPIRED for lapsed warranties.")
                .param("days", "Number of days ahead to look, e.g. 30")
                .param("status", "Warranty state", "EXPIRING", "EXPIRED", "ACTIVE")
                .param("category", "Optional category filter"));

        add(NON_EMPLOYEE, new LlmToolSpec("get_warranty_renewal_history",
                "Past warranty RENEWAL actions for an asset: previous expiry, new expiry, how many "
                        + "months it was extended, and the renewal cost. Distinct from get_warranty, "
                        + "which only reports the CURRENT expiry date with no history of past renewals.")
                .param("assetCode", "Optional specific asset code, e.g. AST003"));

        add(NON_EMPLOYEE, new LlmToolSpec("get_asset_transfer_history",
                "Asset custody TRANSFER history between employees: who an asset moved from and to, "
                        + "when, and why. Distinct from get_asset_holder/search_allocations, which "
                        + "report who holds an asset NOW, not its change-of-custody history.")
                .param("assetCode", "Optional specific asset code, e.g. AST003")
                .param("employeeCode", "Optional employee code - matches either side of the transfer"));

        add(NON_EMPLOYEE, new LlmToolSpec("search_asset_documents",
                "Searches the TEXT CONTENT of uploaded asset documents (manuals, invoices, warranty "
                        + "papers) for a keyword or phrase, and returns matching snippets. Distinct from "
                        + "every other tool here, which answer from structured database columns - this is "
                        + "the one grounded in the actual prose of an uploaded file. Use for questions like "
                        + "'what does the manual for AST003 say about cleaning' or 'which invoice mentions "
                        + "extended warranty'. Only documents whose text was successfully extracted at "
                        + "upload time are searchable.")
                .param("query", "The keyword or phrase to search for in document text"));

        // ── Summaries ────────────────────────────────────────────────────────
        add(NON_EMPLOYEE, new LlmToolSpec("get_department_summary",
                "Asset counts and values grouped by department."));

        add(NON_EMPLOYEE, new LlmToolSpec("get_category_summary",
                "Asset counts and values grouped by category."));

        add(NON_EMPLOYEE, new LlmToolSpec("get_supplier_summary",
                "Assets grouped by supplier/vendor."));

        add(NON_EMPLOYEE, new LlmToolSpec("get_dashboard_summary",
                "High-level system overview: totals across assets, employees, and activity."));

        add(NON_EMPLOYEE, new LlmToolSpec("get_category_vendor_mapping",
                "Which suppliers are approved for which asset categories."));

        add(NON_EMPLOYEE, new LlmToolSpec("get_physical_verification_summary",
                "Physical verification outcomes: verified, mismatch, not found, damaged."));

        // ── QR ───────────────────────────────────────────────────────────────
        add(ASSET_OPS_AND_AUDIT, new LlmToolSpec("get_qr_status",
                "QR tagging coverage: which assets have QR tokens generated and tagged."));

        add(ASSET_OPS_AND_AUDIT, new LlmToolSpec("get_qr_scan_logs",
                "Recent QR scan activity, including invalid-token attempts."));

        add(ASSET_OPS_AND_AUDIT, new LlmToolSpec("get_maintenance_cost_outliers",
                "Finds assets whose TOTAL maintenance spend is disproportionately high compared to "
                        + "other assets in the same category - an analytical insight (comparing each asset "
                        + "to its category's average), not a simple filter. Use for questions like 'which "
                        + "assets cost the most to maintain', 'any unusually expensive assets to maintain', "
                        + "or 'flag maintenance cost outliers'.")
                .param("threshold", "How many times the category average counts as an outlier, e.g. 1.5 "
                        + "or 2 (default 1.5 if not stated)"));

        // ── Audit / admin ────────────────────────────────────────────────────
        add(AUDIT_ONLY, new LlmToolSpec("get_audit_logs",
                "System audit trail of administrative actions.")
                .param("days", "Look back this many days, e.g. 7"));

        add(ADMIN_ONLY, new LlmToolSpec("get_role_duty_summary",
                "Current role and duty assignments across staff."));

        add(ADMIN_ONLY, new LlmToolSpec("get_settings_summary",
                "System configuration summary."));

        add(ADMIN_ONLY, new LlmToolSpec("get_copilot_feedback_summary",
                "How the AMS Copilot itself is performing: thumbs-up/down counts, satisfaction rate, "
                        + "and the most recent thumbs-down answers so you can see what went wrong. Use for "
                        + "questions like 'how is the copilot doing' or 'show recent bad copilot answers'.")
                .param("days", "Look back this many days, e.g. 7 or 30 (default 30)"));
    }

    private static void add(List<String> roles, LlmToolSpec spec) {
        CATALOG.put(spec.name, new Entry(spec, roles));
    }

    // ─────────────────────────────────────────────────────────────────────────
    // ROLE FILTERING (security layer 1)
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * The tools this role may use. Anything not returned here is never shown to
     * the model, so it cannot be requested by name either.
     */
    public static List<LlmToolSpec> forRole(String role) {
        String normalized = role == null ? "" : role.trim().toUpperCase();
        List<LlmToolSpec> allowed = new ArrayList<LlmToolSpec>();

        for (Entry entry : CATALOG.values()) {
            if (entry.roles.contains(normalized)) {
                allowed.add(entry.spec);
            }
        }
        return allowed;
    }

    private static boolean isAllowed(String toolName, String role) {
        Entry entry = CATALOG.get(toolName);
        if (entry == null) {
            return false;
        }
        String normalized = role == null ? "" : role.trim().toUpperCase();
        return entry.roles.contains(normalized);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // DISPATCH
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * Runs one tool call and returns its result as compact JSON for the model.
     *
     * Re-checks the role even though forRole() already filtered the catalog: a
     * model can hallucinate a tool name it was never given, and this is what
     * makes that a clean refusal rather than an unauthorised read.
     */
    public static String execute(LlmToolCall call, String role, HttpSession session) {
        if (call == null || call.name.isEmpty()) {
            return "{\"error\":\"No tool name supplied.\"}";
        }

        if (!isAllowed(call.name, role)) {
            return "{\"error\":\"Tool '" + call.name
                    + "' is not available to your role, or does not exist.\"}";
        }

        try {
            CopilotQueryPlan plan = toPlan(call);
            Map<String, Object> result = invoke(call.name, plan, session);
            return CopilotJson.toJson(result);

        } catch (Exception e) {
            // Returned as data, not thrown: the model should see that this tool
            // failed and be able to try another route or say so honestly.
            return "{\"error\":\"Tool execution failed: " + CopilotJson.escape(String.valueOf(e.getMessage())) + "\"}";
        }
    }

    /**
     * Maps the model's string arguments onto the plan fields the DAOs expect.
     *
     * Fault found by inspection (not a live report): department and category
     * are matched against the DB with an EXACT (case-insensitive) equals -
     * see CopilotToolExecutor's "LOWER(d.department_name) = LOWER(?)" filters.
     * The model can reason about the request perfectly and still call
     * search_assets(department="IT") rather than the literal DB string
     * "IT Centre"; that reasoning was never wrong, but the query would come
     * back with zero rows and the model would report "no assets found" -
     * a wrong answer caused by a string mismatch, not a misunderstanding.
     * CopilotEntityResolver already solves exactly this for the keyword
     * fallback path (alias table: "it", "it dept", "information technology"
     * -> "IT Centre"); reused here so both paths canonicalize the same way.
     * Falls back to the model's raw value when no alias matches, rather than
     * dropping the filter - an unrecognised name should fail to match
     * (today's behaviour), not silently widen the query to every department.
     */
    // Package-private (not private) solely so CopilotContextUnderstandingTest
    // can assert on argument canonicalization directly, without a database.
    static CopilotQueryPlan toPlan(LlmToolCall call) {
        CopilotQueryPlan plan = new CopilotQueryPlan();
        plan.rawUserMessage = call.name;
        plan.needsDatabase = true;

        String rawCategory = call.arg("category");
        if (!rawCategory.isEmpty()) {
            plan.rawCategory = rawCategory;
            plan.normalizedCategory = CopilotEntityResolver.normalizeCategory(rawCategory);
        }

        String rawDepartment = call.arg("department");
        if (!rawDepartment.isEmpty()) {
            String canonical = CopilotEntityResolver.extractDepartment(rawDepartment);
            plan.departmentName = canonical != null ? canonical : rawDepartment.trim();
        }

        plan.assetCode = blankToNull(call.arg("assetCode"));
        plan.employeeCode = blankToNull(call.arg("employeeCode"));
        plan.employeeName = blankToNull(call.arg("employeeName"));
        plan.vendorName = blankToNull(call.arg("vendorName"));

        String status = call.arg("status");
        if (!status.isEmpty()) {
            plan.status = status.trim().toUpperCase().replace(' ', '_');
        }

        String days = call.arg("days");
        if (!days.isEmpty()) {
            try {
                // Models sometimes answer "30 days" rather than "30".
                plan.days = Integer.valueOf(days.replaceAll("[^0-9]", ""));
            } catch (Exception ignored) {
                plan.days = null;
            }
        }

        plan.purchasedAfter  = parseIsoDate(call.arg("purchasedAfter"));
        plan.purchasedBefore = parseIsoDate(call.arg("purchasedBefore"));

        plan.joinedAfter  = parseIsoDate(call.arg("joinedAfter"));
        plan.joinedBefore = parseIsoDate(call.arg("joinedBefore"));

        // Fault, found live: plan.startDate/endDate (created_at - "when was
        // this actually added to AMS") is fully wired at the SQL level in
        // both searchAssets() and searchEmployees(), but was never exposed
        // to the LLM tool path at all - no tool param existed to set it, on
        // any tool. A model asked "how many assets were added this month?"
        // correctly noticed it had no way to express that constraint and,
        // instead of just calling the tool anyway, got stuck narrating its
        // own confusion about the missing parameter as if that prose were
        // the answer (confirmed live - the model literally explained its
        // plan instead of executing it). addedAfter/addedBefore close that
        // gap the same way purchasedAfter/Before and joinedAfter/Before
        // already do for their own date questions.
        //
        // plan.endDate is deliberately set to the RAW inclusive end date
        // here, not shifted forward - both searchAssets() and
        // searchEmployees() already do their own +1 day at the
        // PreparedStatement-binding site to turn an inclusive end date into
        // an exclusive "< nextDay" bound. Shifting here too would silently
        // include one extra day's records on every addedBefore query.
        plan.startDate = parseIsoDate(call.arg("addedAfter"));
        plan.endDate   = parseIsoDate(call.arg("addedBefore"));

        String threshold = call.arg("threshold");
        if (!threshold.isEmpty()) {
            try {
                plan.costMultiplierThreshold = Double.valueOf(threshold.replaceAll("[^0-9.]", ""));
            } catch (Exception ignored) {
                plan.costMultiplierThreshold = null;
            }
        }

        plan.knowledgeQuery = blankToNull(call.arg("query"));

        return plan;
    }

    /**
     * Parses the ISO date the model was asked for. Never throws: a model
     * that answers "early 2023" instead of "2023-01-01" should lose that one
     * filter, not fail the whole tool call - the rest of the query still runs.
     */
    private static java.time.LocalDate parseIsoDate(String value) {
        if (value == null || value.trim().isEmpty()) {
            return null;
        }
        try {
            return java.time.LocalDate.parse(value.trim());
        } catch (Exception e) {
            return null;
        }
    }

    private static Map<String, Object> invoke(String name, CopilotQueryPlan plan, HttpSession session) {
        switch (name) {
            case "search_project_knowledge":   return CopilotToolExecutor.getProjectKnowledge(plan, session);
            case "search_assets":              return CopilotToolExecutor.searchAssets(plan, session);
            case "get_asset_total_cost":       return CopilotToolExecutor.getAssetTotalCost(plan, session);
            case "get_available_assets":       return CopilotToolExecutor.getAvailableAssets(plan, session);
            case "get_allocated_assets":       return CopilotToolExecutor.getAllocatedAssets(plan, session);
            case "get_asset_holder":           return CopilotToolExecutor.getAssetHolder(plan, session);
            case "get_damaged_assets":         return CopilotToolExecutor.getDamagedAssets(plan, session);
            case "get_asset_value_summary":    return CopilotToolExecutor.getAssetValueSummary(plan, session);
            case "get_disposed_assets":        return CopilotToolExecutor.getDisposedAssets(plan, session);
            case "get_asset_disposal_details": return CopilotToolExecutor.getAssetDisposalDetails(plan, session);

            case "get_employee_details":       return CopilotToolExecutor.getEmployeeDetails(plan, session);
            case "get_employee_allocations":   return CopilotToolExecutor.getEmployeeAllocations(plan, session);
            case "search_employees":           return CopilotToolExecutor.searchEmployees(plan, session);
            case "get_department_employees":   return CopilotToolExecutor.getDepartmentEmployees(plan, session);
            case "get_employees_by_joining_date":
                                               return CopilotToolExecutor.getEmployeesByJoiningDate(plan, session);

            case "search_allocations":         return CopilotToolExecutor.searchAllocations(plan, session);
            case "get_return_records":         return CopilotToolExecutor.getReturnRecords(plan, session);
            case "get_pending_returns":        return CopilotToolExecutor.getPendingReturns(plan, session);

            case "get_pending_asset_requests": return CopilotToolExecutor.getPendingAssetRequests(plan, session);
            case "get_approved_requests":      return CopilotToolExecutor.getApprovedRequests(plan, session);
            case "get_rejected_requests":      return CopilotToolExecutor.getRejectedRequests(plan, session);

            case "get_pending_maintenance":    return CopilotToolExecutor.getPendingMaintenance(plan, session);
            case "get_maintenance_history":    return CopilotToolExecutor.getMaintenanceHistory(plan, session);
            case "get_warranty":               return CopilotToolExecutor.getWarranty(plan, session);
            case "get_warranty_renewal_history": return CopilotToolExecutor.getWarrantyRenewalHistory(plan, session);
            case "get_asset_transfer_history":  return CopilotToolExecutor.getAssetTransferHistory(plan, session);
            case "search_asset_documents":      return CopilotToolExecutor.searchAssetDocuments(plan, session);

            case "get_department_summary":     return CopilotToolExecutor.getDepartmentSummary(plan, session);
            case "get_category_summary":       return CopilotToolExecutor.getCategorySummary(plan, session);
            case "get_supplier_summary":       return CopilotToolExecutor.getSupplierSummary(plan, session);
            case "get_dashboard_summary":      return CopilotToolExecutor.getDashboardSummary(plan, session);
            case "get_category_vendor_mapping":return CopilotToolExecutor.getCategoryVendorMapping(plan, session);
            case "get_physical_verification_summary":
                                               return CopilotToolExecutor.getPhysicalVerificationSummary(plan, session);

            case "get_qr_status":              return CopilotToolExecutor.getQrStatus(plan, session);
            case "get_qr_scan_logs":           return CopilotToolExecutor.getQrScanLogs(plan, session);
            case "get_maintenance_cost_outliers": return CopilotToolExecutor.getMaintenanceCostOutliers(plan, session);

            case "get_audit_logs":             return CopilotToolExecutor.getAuditLogs(plan, session);
            case "get_role_duty_summary":      return CopilotToolExecutor.getRoleDutySummary(plan, session);
            case "get_settings_summary":       return CopilotToolExecutor.getSettingsSummary(plan, session);
            case "get_copilot_feedback_summary": return CopilotToolExecutor.getCopilotFeedbackSummary(plan, session);

            default: {
                Map<String, Object> error = new LinkedHashMap<String, Object>();
                error.put("error", "Unknown tool: " + name);
                return error;
            }
        }
    }

    private static String blankToNull(String value) {
        return value == null || value.trim().isEmpty() ? null : value.trim();
    }
}
