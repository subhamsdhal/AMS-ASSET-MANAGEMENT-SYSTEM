package com.mycompany.asset_management_system_ams;

import java.math.BigDecimal;
import java.text.NumberFormat;
import java.util.List;
import java.util.Locale;
import java.util.Map;

/**
 * CopilotResponseFormatter — Converts DAO results into human-readable Markdown.
 *
 * Rules:
 *  - Always give a direct answer first ("The total cost is ₹X")
 *  - Then show table / detail list
 *  - If no data: say what was searched, say no records found — never say "I cannot"
 *  - Never invent facts not in data
 */
public class CopilotResponseFormatter {

    private static final NumberFormat INR_FORMAT = NumberFormat.getNumberInstance(new Locale("en", "IN"));

    // ─────────────────────────────────────────────────────────────────────────
    // DISPATCH
    // ─────────────────────────────────────────────────────────────────────────

    public static String formatResponse(CopilotQueryPlan plan, Map<String, Object> data) {
        if (data == null) {
            return "I checked the live AMS database but received no response. Please try again.";
        }
        if (data.containsKey("error")) {
            return (String) data.get("error");
        }

        switch (plan.intent) {
            case ASSET_TOTAL_COST:          return formatTotalCost(plan, data);
            case ASSET_SEARCH:              return formatAssetSearch(plan, data);
            case ASSET_COUNT:               return formatAssetCount(plan, data);
            case AVAILABLE_ASSETS:          return formatAvailableAssets(plan, data);
            case ALLOCATED_ASSETS:          return formatAllocatedAssets(plan, data);
            case DISPOSED_ASSETS:           return formatDisposedAssets(data);
            case ASSET_HOLDER:              return formatAssetHolder(plan, data);
            case EMPLOYEE_DETAILS:          return formatEmployeeDetails(plan, data);
            case EMPLOYEE_ALLOCATIONS:      return formatEmployeeAllocations(plan, data);
            case EMPLOYEE_SEARCH:           return formatEmployeeSearch(plan, data);
            case ALLOCATION_SEARCH:         return formatAllocationSearch(plan, data);
            case RETURN_SEARCH:             return formatAllocationSearch(plan, data);
            case PENDING_ASSET_REQUESTS:    return formatPendingRequests(data);
            case MAINTENANCE_PENDING:       return formatPendingMaintenance(data);
            case MAINTENANCE_HISTORY:       return formatMaintenanceHistory(plan, data);
            case WARRANTY_EXPIRING_NEXT_N_DAYS:
            case WARRANTY_EXPIRED:
            case WARRANTY_THIS_MONTH:       return formatWarranty(plan, data);
            case DEPT_SUMMARY:              return formatDeptSummary(data);
            case CATEGORY_SUMMARY:          return formatCategorySummary(data);
            case SUPPLIER_SUMMARY:          return formatSupplierSummary(data);
            case DASHBOARD_SUMMARY:         return formatDashboardSummary(data);
            default:
                return "I checked the live AMS database. " +
                       "Please rephrase your question or type **help** for examples.";
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // TOTAL COST
    // ─────────────────────────────────────────────────────────────────────────

    private static String formatTotalCost(CopilotQueryPlan plan, Map<String, Object> data) {
        int count = toInt(data.get("count"));
        BigDecimal total = toBD(data.get("total"));
        String category = str(data.get("category"));
        String dept     = str(data.get("department"));

        String scope = "All".equals(category)
            ? "all asset categories"
            : (category + " assets");
        if (dept != null) scope += " in " + dept;

        if (count == 0) {
            return "I checked the live AMS database but found **no matching records** for " + scope + ".";
        }

        String totalFmt = "₹" + INR_FORMAT.format(Math.round(total.doubleValue()));
        StringBuilder sb = new StringBuilder();
        sb.append("The **total purchase cost** of ").append(scope).append(" is ")
          .append("**").append(totalFmt).append("**")
          .append(" across **").append(count).append("** asset record(s).\n\n");
        sb.append("| Category | Count | Total Purchase Cost |\n");
        sb.append("|---|---|---|\n");
        sb.append("| ").append(category).append(" | ").append(count)
          .append(" | ").append(totalFmt).append(" |\n");
        return sb.toString().trim();
    }

    // ─────────────────────────────────────────────────────────────────────────
    // ASSET SEARCH / LIST
    // ─────────────────────────────────────────────────────────────────────────

    @SuppressWarnings("unchecked")
    private static String formatAssetSearch(CopilotQueryPlan plan, Map<String, Object> data) {
        List<Map<String, String>> records = (List<Map<String, String>>) data.get("records");
        if (records == null || records.isEmpty()) {
            StringBuilder sb = new StringBuilder("I checked the live AMS database but found **no matching records**");
            if (plan.normalizedCategory != null) sb.append(" for category **").append(plan.normalizedCategory).append("**");
            if (plan.departmentName != null) sb.append(" in department **").append(plan.departmentName).append("**");
            if (plan.status != null) sb.append(" with status **").append(plan.status).append("**");
            sb.append(".");
            return sb.toString();
        }

        StringBuilder sb = new StringBuilder("I found **").append(records.size()).append("** matching asset(s)");
        if (plan.normalizedCategory != null) sb.append(" in category **").append(plan.normalizedCategory).append("**");
        if (plan.departmentName != null) sb.append(" — Department: **").append(plan.departmentName).append("**");
        sb.append(":\n\n");
        sb.append("| Asset Code | Asset Name | Category | Department | Status |\n");
        sb.append("|---|---|---|---|---|\n");
        for (Map<String, String> r : records) {
            sb.append("| ").append(nvl(r.get("asset_code")))
              .append(" | ").append(nvl(r.get("asset_name")))
              .append(" | ").append(nvl(r.get("category_name")))
              .append(" | ").append(nvl(r.get("department_name")))
              .append(" | ").append(nvl(r.get("status")))
              .append(" |\n");
        }
        return sb.toString().trim();
    }

    // ─────────────────────────────────────────────────────────────────────────
    // ASSET COUNT
    // ─────────────────────────────────────────────────────────────────────────

    @SuppressWarnings("unchecked")
    private static String formatAssetCount(CopilotQueryPlan plan, Map<String, Object> data) {
        List<Map<String, String>> records = (List<Map<String, String>>) data.get("records");
        int count = records != null ? records.size() : 0;
        StringBuilder sb = new StringBuilder("The live AMS database has **").append(count).append("** asset(s)");
        if (plan.normalizedCategory != null) sb.append(" in category **").append(plan.normalizedCategory).append("**");
        if (plan.departmentName != null) sb.append(" in department **").append(plan.departmentName).append("**");
        sb.append(".");
        return sb.toString();
    }

    // ─────────────────────────────────────────────────────────────────────────
    // AVAILABLE ASSETS
    // ─────────────────────────────────────────────────────────────────────────

    @SuppressWarnings("unchecked")
    private static String formatAvailableAssets(CopilotQueryPlan plan, Map<String, Object> data) {
        List<Map<String, String>> records = (List<Map<String, String>>) data.get("records");
        if (records == null || records.isEmpty()) {
            String dept = plan.departmentName != null ? " in **" + plan.departmentName + "**" : "";
            return "I checked the live AMS database. No **available** assets found" + dept + ".";
        }
        StringBuilder sb = new StringBuilder("Found **").append(records.size()).append("** available asset(s)");
        if (plan.departmentName != null) sb.append(" in **").append(plan.departmentName).append("**");
        sb.append(":\n\n");
        sb.append("| Asset Code | Asset Name | Category | Department |\n");
        sb.append("|---|---|---|---|\n");
        for (Map<String, String> r : records) {
            sb.append("| ").append(nvl(r.get("asset_code")))
              .append(" | ").append(nvl(r.get("asset_name")))
              .append(" | ").append(nvl(r.get("category_name")))
              .append(" | ").append(nvl(r.get("department_name")))
              .append(" |\n");
        }
        return sb.toString().trim();
    }

    // ─────────────────────────────────────────────────────────────────────────
    // ALLOCATED ASSETS
    // ─────────────────────────────────────────────────────────────────────────

    @SuppressWarnings("unchecked")
    private static String formatAllocatedAssets(CopilotQueryPlan plan, Map<String, Object> data) {
        List<Map<String, String>> records = (List<Map<String, String>>) data.get("records");
        if (records == null || records.isEmpty()) {
            return "I checked the live AMS database. No **allocated** assets found.";
        }
        StringBuilder sb = new StringBuilder("Found **").append(records.size()).append("** allocated asset(s):\n\n");
        sb.append("| Asset Code | Asset Name | Category | Department | Status |\n");
        sb.append("|---|---|---|---|---|\n");
        for (Map<String, String> r : records) {
            sb.append("| ").append(nvl(r.get("asset_code")))
              .append(" | ").append(nvl(r.get("asset_name")))
              .append(" | ").append(nvl(r.get("category_name")))
              .append(" | ").append(nvl(r.get("department_name")))
              .append(" | ").append(nvl(r.get("status")))
              .append(" |\n");
        }
        return sb.toString().trim();
    }

    // ─────────────────────────────────────────────────────────────────────────
    // DISPOSED ASSETS
    // ─────────────────────────────────────────────────────────────────────────

    @SuppressWarnings("unchecked")
    private static String formatDisposedAssets(Map<String, Object> data) {
        List<Map<String, String>> records = (List<Map<String, String>>) data.get("records");
        if (records == null || records.isEmpty()) {
            return "I checked the live AMS database. No disposed/condemned assets were found.";
        }
        StringBuilder sb = new StringBuilder("Found **").append(records.size()).append("** disposed asset(s):\n\n");
        sb.append("| Asset Code | Asset Name | Category | Department | Status |\n");
        sb.append("|---|---|---|---|---|\n");
        for (Map<String, String> r : records) {
            sb.append("| ").append(nvl(r.get("asset_code")))
              .append(" | ").append(nvl(r.get("asset_name")))
              .append(" | ").append(nvl(r.get("category_name")))
              .append(" | ").append(nvl(r.get("department_name")))
              .append(" | ").append(nvl(r.get("status")))
              .append(" |\n");
        }
        return sb.toString().trim();
    }

    // ─────────────────────────────────────────────────────────────────────────
    // ASSET HOLDER
    // ─────────────────────────────────────────────────────────────────────────

    @SuppressWarnings("unchecked")
    private static String formatAssetHolder(CopilotQueryPlan plan, Map<String, Object> data) {
        List<Map<String, String>> records = (List<Map<String, String>>) data.get("records");
        String assetCode = str(data.get("assetCode"));
        if (assetCode == null) assetCode = plan.assetCode;

        if (records == null || records.isEmpty()) {
            return "Asset **" + nvl(assetCode) + "** is currently **not allocated** to any employee " +
                   "(or may not exist in the live AMS database).";
        }

        Map<String, String> r = records.get(0);
        return "Asset **" + nvl(r.get("asset_code")) + "** (" + nvl(r.get("asset_name")) + ") " +
               "is currently held by:\n\n" +
               "- **Employee:** " + nvl(r.get("employee_code")) + " — " + nvl(r.get("full_name")) + "\n" +
               "- **Designation:** " + nvl(r.get("designation")) + "\n" +
               "- **Department:** " + nvl(r.get("department_name")) + "\n" +
               "- **Allocated Since:** " + nvl(r.get("allocation_date"));
    }

    // ─────────────────────────────────────────────────────────────────────────
    // EMPLOYEE DETAILS
    // ─────────────────────────────────────────────────────────────────────────

    @SuppressWarnings("unchecked")
    private static String formatEmployeeDetails(CopilotQueryPlan plan, Map<String, Object> data) {
        List<Map<String, String>> records = (List<Map<String, String>>) data.get("records");
        if (records == null || records.isEmpty()) {
            String who = plan.employeeCode != null ? plan.employeeCode : plan.employeeName;
            return "I checked the live AMS database. No employee found matching **" + nvl(who) + "**.";
        }

        StringBuilder sb = new StringBuilder("Found **").append(records.size()).append("** employee record(s):\n\n");
        for (Map<String, String> r : records) {
            sb.append("**").append(nvl(r.get("employee_code"))).append("** — ")
              .append(nvl(r.get("full_name"))).append("\n");
            sb.append("- Designation: ").append(nvl(r.get("designation"))).append("\n");
            sb.append("- Department: ").append(nvl(r.get("department_name"))).append("\n");
            sb.append("- Email: ").append(nvl(r.get("email"))).append("\n");
            sb.append("- Phone: ").append(nvl(r.get("phone"))).append("\n");
            sb.append("- Status: ").append(nvl(r.get("status"))).append("\n\n");
        }
        return sb.toString().trim();
    }

    // ─────────────────────────────────────────────────────────────────────────
    // EMPLOYEE ALLOCATIONS
    // ─────────────────────────────────────────────────────────────────────────

    @SuppressWarnings("unchecked")
    private static String formatEmployeeAllocations(CopilotQueryPlan plan, Map<String, Object> data) {
        List<Map<String, String>> records = (List<Map<String, String>>) data.get("records");
        String who = plan.employeeCode != null ? plan.employeeCode
                   : (plan.employeeName != null ? plan.employeeName : "the employee");

        if (records == null || records.isEmpty()) {
            return "I checked the live AMS database. No currently allocated assets found for **" + who + "**.";
        }

        String holderName = records.get(0).get("full_name");
        String holderCode = records.get(0).get("employee_code");

        StringBuilder sb = new StringBuilder();
        sb.append("**").append(holderCode).append("** — ").append(nvl(holderName))
          .append(" has **").append(records.size()).append("** currently allocated asset(s):\n\n");
        sb.append("| Asset Code | Asset Name | Category | Allocated Since |\n");
        sb.append("|---|---|---|---|\n");
        for (Map<String, String> r : records) {
            sb.append("| ").append(nvl(r.get("asset_code")))
              .append(" | ").append(nvl(r.get("asset_name")))
              .append(" | ").append(nvl(r.get("category_name")))
              .append(" | ").append(nvl(r.get("allocation_date")))
              .append(" |\n");
        }
        return sb.toString().trim();
    }

    // ─────────────────────────────────────────────────────────────────────────
    // EMPLOYEE SEARCH (generic)
    // ─────────────────────────────────────────────────────────────────────────

    @SuppressWarnings("unchecked")
    private static String formatEmployeeSearch(CopilotQueryPlan plan, Map<String, Object> data) {
        List<Map<String, String>> records = (List<Map<String, String>>) data.get("records");
        if (records == null || records.isEmpty()) {
            StringBuilder sb = new StringBuilder("I checked the live AMS database. No employees found");
            if (plan.departmentName != null) sb.append(" in department **").append(plan.departmentName).append("**");
            sb.append(".");
            return sb.toString();
        }

        StringBuilder sb = new StringBuilder("Found **").append(records.size()).append("** employee(s):\n\n");
        sb.append("| Emp Code | Name | Designation | Department |\n");
        sb.append("|---|---|---|---|\n");
        for (Map<String, String> r : records) {
            sb.append("| ").append(nvl(r.get("employee_code")))
              .append(" | ").append(nvl(r.get("full_name")))
              .append(" | ").append(nvl(r.get("designation")))
              .append(" | ").append(nvl(r.get("department_name")))
              .append(" |\n");
        }
        return sb.toString().trim();
    }

    // ─────────────────────────────────────────────────────────────────────────
    // ALLOCATION SEARCH
    // ─────────────────────────────────────────────────────────────────────────

    @SuppressWarnings("unchecked")
    private static String formatAllocationSearch(CopilotQueryPlan plan, Map<String, Object> data) {
        List<Map<String, String>> records = (List<Map<String, String>>) data.get("records");
        if (records == null || records.isEmpty()) {
            return "I checked the live AMS database. No matching allocation records found.";
        }

        StringBuilder sb = new StringBuilder("Found **").append(records.size()).append("** allocation(s):\n\n");
        sb.append("| Asset Code | Asset Name | Category | Employee | Department |\n");
        sb.append("|---|---|---|---|---|\n");
        for (Map<String, String> r : records) {
            sb.append("| ").append(nvl(r.get("asset_code")))
              .append(" | ").append(nvl(r.get("asset_name")))
              .append(" | ").append(nvl(r.get("category_name")))
              .append(" | ").append(nvl(r.get("employee_code"))).append(" - ").append(nvl(r.get("full_name")))
              .append(" | ").append(nvl(r.get("department_name")))
              .append(" |\n");
        }
        return sb.toString().trim();
    }

    // ─────────────────────────────────────────────────────────────────────────
    // PENDING ASSET REQUESTS
    // ─────────────────────────────────────────────────────────────────────────

    @SuppressWarnings("unchecked")
    private static String formatPendingRequests(Map<String, Object> data) {
        List<Map<String, String>> records = (List<Map<String, String>>) data.get("records");
        if (records == null || records.isEmpty()) {
            return "I checked the live AMS database. There are **no pending asset requests** at this time.";
        }

        StringBuilder sb = new StringBuilder("There are **").append(records.size()).append("** pending asset request(s):\n\n");
        sb.append("| Req ID | Employee | Department | Category | Date Requested |\n");
        sb.append("|---|---|---|---|---|\n");
        for (Map<String, String> r : records) {
            sb.append("| ").append(nvl(r.get("request_id")))
              .append(" | ").append(nvl(r.get("employee_code"))).append(" - ").append(nvl(r.get("full_name")))
              .append(" | ").append(nvl(r.get("department_name")))
              .append(" | ").append(nvl(r.get("category_name")))
              .append(" | ").append(nvl(r.get("request_date")))
              .append(" |\n");
        }
        return sb.toString().trim();
    }

    // ─────────────────────────────────────────────────────────────────────────
    // PENDING MAINTENANCE
    // ─────────────────────────────────────────────────────────────────────────

    @SuppressWarnings("unchecked")
    private static String formatPendingMaintenance(Map<String, Object> data) {
        List<Map<String, String>> records = (List<Map<String, String>>) data.get("records");
        if (records == null || records.isEmpty()) {
            return "I checked the live AMS database. No assets are currently pending/under maintenance.";
        }

        StringBuilder sb = new StringBuilder("**").append(records.size()).append("** asset(s) under maintenance / pending repair:\n\n");
        sb.append("| Asset Code | Asset Name | Category | Department | Status | Date |\n");
        sb.append("|---|---|---|---|---|---|\n");
        for (Map<String, String> r : records) {
            sb.append("| ").append(nvl(r.get("asset_code")))
              .append(" | ").append(nvl(r.get("asset_name")))
              .append(" | ").append(nvl(r.get("category_name")))
              .append(" | ").append(nvl(r.get("department_name")))
              .append(" | ").append(nvl(r.get("request_status")))
              .append(" | ").append(nvl(r.get("request_date")))
              .append(" |\n");
        }
        return sb.toString().trim();
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MAINTENANCE HISTORY
    // ─────────────────────────────────────────────────────────────────────────

    @SuppressWarnings("unchecked")
    private static String formatMaintenanceHistory(CopilotQueryPlan plan, Map<String, Object> data) {
        List<Map<String, String>> records = (List<Map<String, String>>) data.get("records");
        if (records == null || records.isEmpty()) {
            return "I checked the live AMS database. No maintenance history found for asset **" + plan.assetCode + "**.";
        }

        String assetName = records.get(0).get("asset_name");
        StringBuilder sb = new StringBuilder("Maintenance history for **")
            .append(plan.assetCode).append("**")
            .append(assetName != null ? " — " + assetName : "")
            .append(" (").append(records.size()).append(" record(s)):\n\n");
        sb.append("| Date | Status | Issue | Resolution |\n");
        sb.append("|---|---|---|---|\n");
        for (Map<String, String> r : records) {
            sb.append("| ").append(nvl(r.get("request_date")))
              .append(" | ").append(nvl(r.get("request_status")))
              .append(" | ").append(truncate(nvl(r.get("issue_description")), 40))
              .append(" | ").append(truncate(nvl(r.get("resolution_notes")), 40))
              .append(" |\n");
        }
        return sb.toString().trim();
    }

    // ─────────────────────────────────────────────────────────────────────────
    // WARRANTY
    // ─────────────────────────────────────────────────────────────────────────

    @SuppressWarnings("unchecked")
    private static String formatWarranty(CopilotQueryPlan plan, Map<String, Object> data) {
        List<Map<String, Object>> records = (List<Map<String, Object>>) data.get("records");
        int days = toInt(data.get("days"));

        if (records == null || records.isEmpty()) {
            if (plan.intent == CopilotIntentType.WARRANTY_EXPIRED) {
                return "I checked the live AMS database. There are **no expired** asset warranties.";
            } else if (plan.intent == CopilotIntentType.WARRANTY_THIS_MONTH) {
                return "I checked the live AMS database. No asset warranties are expiring **this month**.";
            } else {
                return "I checked the live AMS database. No asset warranties are expiring in the **next " + days + " days**.";
            }
        }

        StringBuilder sb = new StringBuilder();
        if (plan.intent == CopilotIntentType.WARRANTY_EXPIRED) {
            sb.append("Found **").append(records.size()).append("** asset(s) with **expired** warranties:\n\n");
        } else if (plan.intent == CopilotIntentType.WARRANTY_THIS_MONTH) {
            sb.append("Found **").append(records.size()).append("** asset(s) with warranties expiring **this month**:\n\n");
        } else {
            sb.append("Found **").append(records.size()).append("** asset(s) with warranties expiring in the **next ")
              .append(days).append(" days** (future only):\n\n");
        }

        sb.append("| Asset Code | Asset Name | Category | Department | Expiry Date | Days Remaining |\n");
        sb.append("|---|---|---|---|---|---|\n");
        for (Map<String, Object> r : records) {
            sb.append("| ").append(nvl((String) r.get("asset_code")))
              .append(" | ").append(nvl((String) r.get("asset_name")))
              .append(" | ").append(nvl((String) r.get("category_name")))
              .append(" | ").append(nvl((String) r.get("department_name")))
              .append(" | ").append(nvl((String) r.get("warranty_expiry")))
              .append(" | ").append(r.get("days_remaining"))
              .append(" |\n");
        }
        return sb.toString().trim();
    }

    // ─────────────────────────────────────────────────────────────────────────
    // DEPARTMENT SUMMARY
    // ─────────────────────────────────────────────────────────────────────────

    @SuppressWarnings("unchecked")
    private static String formatDeptSummary(Map<String, Object> data) {
        List<Map<String, Object>> records = (List<Map<String, Object>>) data.get("records");
        if (records == null || records.isEmpty()) {
            return "I checked the live AMS database. No department summary data available.";
        }

        // Grand total
        BigDecimal grandTotal = BigDecimal.ZERO;
        int grandCount = 0;
        for (Map<String, Object> r : records) {
            grandTotal = grandTotal.add(toBD(r.get("total_cost")));
            grandCount += toInt(r.get("asset_count"));
        }

        StringBuilder sb = new StringBuilder("**Asset Value — Department-wise Summary** (")
            .append(records.size()).append(" departments, ").append(grandCount).append(" total assets):\n\n");
        sb.append("| Department | Assets | Total Cost | Avg Cost |\n");
        sb.append("|---|---|---|---|\n");
        for (Map<String, Object> r : records) {
            sb.append("| ").append(nvl((String) r.get("department_name")))
              .append(" | ").append(toInt(r.get("asset_count")))
              .append(" | ₹").append(INR_FORMAT.format(Math.round(toBD(r.get("total_cost")).doubleValue())))
              .append(" | ₹").append(INR_FORMAT.format(Math.round(toBD(r.get("avg_cost")).doubleValue())))
              .append(" |\n");
        }
        sb.append("\n**Grand Total: ₹").append(INR_FORMAT.format(Math.round(grandTotal.doubleValue())))
          .append("** across ").append(grandCount).append(" assets.");
        return sb.toString().trim();
    }

    // ─────────────────────────────────────────────────────────────────────────
    // CATEGORY SUMMARY
    // ─────────────────────────────────────────────────────────────────────────

    @SuppressWarnings("unchecked")
    private static String formatCategorySummary(Map<String, Object> data) {
        List<Map<String, Object>> records = (List<Map<String, Object>>) data.get("records");
        if (records == null || records.isEmpty()) {
            return "I checked the live AMS database. No category summary data available.";
        }

        BigDecimal grandTotal = BigDecimal.ZERO;
        int grandCount = 0;
        for (Map<String, Object> r : records) {
            grandTotal = grandTotal.add(toBD(r.get("total_cost")));
            grandCount += toInt(r.get("asset_count"));
        }

        StringBuilder sb = new StringBuilder("**Asset Value — Category-wise Summary** (")
            .append(records.size()).append(" categories, ").append(grandCount).append(" total assets):\n\n");
        sb.append("| Category | Assets | Total Cost | Avg Cost |\n");
        sb.append("|---|---|---|---|\n");
        for (Map<String, Object> r : records) {
            sb.append("| ").append(nvl((String) r.get("category_name")))
              .append(" | ").append(toInt(r.get("asset_count")))
              .append(" | ₹").append(INR_FORMAT.format(Math.round(toBD(r.get("total_cost")).doubleValue())))
              .append(" | ₹").append(INR_FORMAT.format(Math.round(toBD(r.get("avg_cost")).doubleValue())))
              .append(" |\n");
        }
        sb.append("\n**Grand Total: ₹").append(INR_FORMAT.format(Math.round(grandTotal.doubleValue())))
          .append("** across ").append(grandCount).append(" assets.");
        return sb.toString().trim();
    }

    // ─────────────────────────────────────────────────────────────────────────
    // SUPPLIER SUMMARY
    // ─────────────────────────────────────────────────────────────────────────

    @SuppressWarnings("unchecked")
    private static String formatSupplierSummary(Map<String, Object> data) {
        List<Map<String, Object>> records = (List<Map<String, Object>>) data.get("records");
        if (records == null || records.isEmpty()) {
            return "I checked the live AMS database. No vendor/supplier data available.";
        }

        StringBuilder sb = new StringBuilder("**Vendor / Supplier Summary** (")
            .append(records.size()).append(" vendor(s)):\n\n");
        sb.append("| Vendor Name | Assets Supplied | Total Value |\n");
        sb.append("|---|---|---|\n");
        for (Map<String, Object> r : records) {
            sb.append("| ").append(nvl((String) r.get("vendor_name")))
              .append(" | ").append(toInt(r.get("asset_count")))
              .append(" | ₹").append(INR_FORMAT.format(Math.round(toBD(r.get("total_cost")).doubleValue())))
              .append(" |\n");
        }
        return sb.toString().trim();
    }

    // ─────────────────────────────────────────────────────────────────────────
    // DASHBOARD SUMMARY
    // ─────────────────────────────────────────────────────────────────────────

    private static String formatDashboardSummary(Map<String, Object> data) {
        int total            = toInt(data.get("total"));
        int available        = toInt(data.get("available"));
        int allocated        = toInt(data.get("allocated"));
        int underMaintenance = toInt(data.get("under_maintenance"));
        BigDecimal totalCost = toBD(data.get("total_cost"));

        return "**AMS Dashboard Summary:**\n\n" +
               "| Metric | Value |\n" +
               "|---|---|\n" +
               "| Total Assets | " + total + " |\n" +
               "| Available | " + available + " |\n" +
               "| Allocated | " + allocated + " |\n" +
               "| Under Maintenance | " + underMaintenance + " |\n" +
               "| Total Portfolio Value | ₹" + INR_FORMAT.format(Math.round(totalCost.doubleValue())) + " |";
    }

    // ─────────────────────────────────────────────────────────────────────────
    // UTILITIES
    // ─────────────────────────────────────────────────────────────────────────

    private static String nvl(String s) { return s != null ? s : "—"; }

    private static String str(Object o) { return o != null ? String.valueOf(o) : null; }

    private static int toInt(Object o) {
        if (o == null) return 0;
        if (o instanceof Number) return ((Number) o).intValue();
        try { return Integer.parseInt(String.valueOf(o)); } catch (Exception e) { return 0; }
    }

    private static BigDecimal toBD(Object o) {
        if (o == null) return BigDecimal.ZERO;
        if (o instanceof BigDecimal) return (BigDecimal) o;
        try { return new BigDecimal(String.valueOf(o)); } catch (Exception e) { return BigDecimal.ZERO; }
    }

    private static String truncate(String s, int max) {
        if (s == null) return "—";
        return s.length() <= max ? s : s.substring(0, max - 1) + "…";
    }
}
