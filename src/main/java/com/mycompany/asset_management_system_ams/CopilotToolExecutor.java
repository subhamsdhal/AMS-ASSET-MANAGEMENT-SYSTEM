package com.mycompany.asset_management_system_ams;

import java.math.BigDecimal;
import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.logging.Level;
import java.util.logging.Logger;
import jakarta.servlet.http.HttpSession;

/**
 * CopilotToolExecutor — Safe DAO layer for AMS Copilot queries.
 *
 * RULES:
 *  - ALL SQL uses PreparedStatement with bound parameters.
 *  - No user text is ever concatenated into a SQL string.
 *  - No AI-generated SQL is executed here.
 *  - Each method returns Map<String, Object> so the formatter can work flexibly.
 *
 * New methods added in this upgrade:
 *   getAssetHolder(), getDisposedAssets(), getAvailableAssets(),
 *   getAllocatedAssets(), getPendingAssetRequests(), getDepartmentSummary(),
 *   getCategorySummary(), getSupplierSummary(), getEmployeeDetails(),
 *   getEmployeeAllocations(), getDashboardSummary()
 *
 * Existing methods preserved (with minor fixes):
 *   getAssetTotalCost() — now supports all-categories mode when no category given
 *   searchAssets(), getWarranty(), getPendingMaintenance(),
 *   searchEmployees(), searchAllocations(), getMaintenanceHistory()
 */
public class CopilotToolExecutor {
    private static final Logger LOGGER = Logger.getLogger(CopilotToolExecutor.class.getName());

    private static final boolean DEBUG =
        "true".equalsIgnoreCase(System.getProperty("COPILOT_DEBUG", "false"));

    // ─────────────────────────────────────────────────────────────────────────
    // COST
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * Total purchase cost — category specific or all assets if no category given.
     * Supports optional department filter.
     */
    public static Map<String, Object> getAssetTotalCost(CopilotQueryPlan plan, HttpSession session) {
        Map<String, Object> result = new HashMap<>();
        String category = plan.normalizedCategory;
        String dept     = plan.departmentName;
        String role     = sessionRole(session);
        String empCode  = sessionAttr(session, "empCode");

        if ("EMPLOYEE".equalsIgnoreCase(role) && isBlank(empCode)) {
            result.put("error", "🔒 **Access Denied**: Employees can only view their own records.");
            return result;
        }

        StringBuilder sql = new StringBuilder(
            "SELECT COUNT(*) AS total_assets, COALESCE(SUM(a.purchase_cost), 0) AS total_value " +
            "FROM assets a " +
            "LEFT JOIN asset_categories c ON a.category_id = c.category_id " +
            "LEFT JOIN departments d ON a.department_id = d.department_id " +
            "WHERE 1=1 "
        );

        if (!isBlank(category))  sql.append("AND LOWER(c.category_name) = LOWER(?) ");
        if (!isBlank(dept))      sql.append("AND LOWER(d.department_name) = LOWER(?) ");
        if ("EMPLOYEE".equalsIgnoreCase(role)) {
            sql.append("AND a.asset_id IN (SELECT asset_id FROM asset_allocation " +
                       "WHERE employee_id = (SELECT employee_id FROM employees WHERE employee_code = ?)) ");
        }

        try (Connection conn = DBConnection.getConnection();
             PreparedStatement ps = conn.prepareStatement(sql.toString())) {

            int idx = 1;
            if (!isBlank(category)) ps.setString(idx++, category);
            if (!isBlank(dept))     ps.setString(idx++, dept);
            if ("EMPLOYEE".equalsIgnoreCase(role)) ps.setString(idx++, empCode);

            try (ResultSet rs = ps.executeQuery()) {
                if (rs.next()) {
                    result.put("count", rs.getInt("total_assets"));
                    result.put("total", rs.getBigDecimal("total_value"));
                }
            }
        } catch (Exception e) {
            LOGGER.log(Level.SEVERE, "Error in getAssetTotalCost", e);
            result.put("error", "Sorry, there was an error retrieving the purchase cost.");
            return result;
        }

        result.put("category",    isBlank(category) ? "All" : category);
        result.put("rawCategory", plan.rawCategory);
        result.put("department",  dept);
        debugLog("getAssetTotalCost", result);
        return result;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // ASSET SEARCH / LIST
    // ─────────────────────────────────────────────────────────────────────────

    public static Map<String, Object> searchAssets(CopilotQueryPlan plan, HttpSession session) {
        Map<String, Object> result = new HashMap<>();
        String role    = sessionRole(session);
        String empCode = sessionAttr(session, "empCode");

        if ("EMPLOYEE".equalsIgnoreCase(role) && isBlank(empCode)) {
            result.put("error", "🔒 **Access Denied**: Employees can only view their own records.");
            return result;
        }

        StringBuilder sql = new StringBuilder(
            "SELECT a.asset_code, a.asset_name, c.category_name, d.department_name, " +
            "a.asset_status, a.purchase_cost, a.purchase_date " +
            "FROM assets a " +
            "LEFT JOIN asset_categories c ON a.category_id = c.category_id " +
            "LEFT JOIN departments d ON a.department_id = d.department_id " +
            "WHERE 1=1 "
        );

        if (plan.normalizedCategory != null) sql.append("AND LOWER(c.category_name) = LOWER(?) ");
        if (plan.departmentName     != null) sql.append("AND LOWER(d.department_name) = LOWER(?) ");
        if (plan.status             != null) sql.append("AND a.asset_status = ? ");
        if (plan.assetCode          != null) sql.append("AND a.asset_code = ? ");
        // Fault: plan.startDate/endDate were extracted by CopilotTimeResolver
        // (e.g. "yesterday", "this month") but never actually applied here -
        // "how many assets added yesterday?" silently answered with the
        // unfiltered total every time, ignoring the time constraint entirely.
        // created_at is when the row was actually added to AMS - the right
        // column for "added", as opposed to purchase_date (when it was
        // bought, which can predate its entry into the system by months).
        if (plan.startDate != null) sql.append("AND a.created_at >= ? ");
        if (plan.endDate   != null) sql.append("AND a.created_at < ? ");
        // A separate constraint from startDate/endDate above: "purchased
        // after 2023" is about assets.purchase_date (when it was bought),
        // not created_at (when the AMS row was added) - see CopilotQueryPlan.
        // Populated only by the LLM tool path (CopilotToolCatalog), which
        // asks the model directly for an ISO date rather than trying to
        // regex-parse "after 2023" / "since last year" itself.
        if (plan.purchasedAfter  != null) sql.append("AND a.purchase_date >= ? ");
        if (plan.purchasedBefore != null) sql.append("AND a.purchase_date < ? ");
        if ("EMPLOYEE".equalsIgnoreCase(role)) {
            sql.append("AND a.asset_id IN (SELECT asset_id FROM asset_allocation " +
                       "WHERE employee_id = (SELECT employee_id FROM employees WHERE employee_code = ?)) ");
        }
        sql.append("ORDER BY a.asset_code LIMIT 50");

        List<Map<String, String>> records = new ArrayList<>();
        try (Connection conn = DBConnection.getConnection();
             PreparedStatement ps = conn.prepareStatement(sql.toString())) {

            int idx = 1;
            if (plan.normalizedCategory != null) ps.setString(idx++, plan.normalizedCategory);
            if (plan.departmentName     != null) ps.setString(idx++, plan.departmentName);
            if (plan.status             != null) ps.setString(idx++, plan.status);
            if (plan.assetCode          != null) ps.setString(idx++, plan.assetCode);
            if (plan.startDate != null) ps.setTimestamp(idx++, java.sql.Timestamp.valueOf(plan.startDate.atStartOfDay()));
            if (plan.endDate   != null) ps.setTimestamp(idx++, java.sql.Timestamp.valueOf(plan.endDate.plusDays(1).atStartOfDay()));
            if (plan.purchasedAfter  != null) ps.setDate(idx++, java.sql.Date.valueOf(plan.purchasedAfter));
            if (plan.purchasedBefore != null) ps.setDate(idx++, java.sql.Date.valueOf(plan.purchasedBefore));
            if ("EMPLOYEE".equalsIgnoreCase(role)) ps.setString(idx++, empCode);

            try (ResultSet rs = ps.executeQuery()) {
                while (rs.next()) {
                    Map<String, String> row = new HashMap<>();
                    row.put("asset_code",      rs.getString("asset_code"));
                    row.put("asset_name",      rs.getString("asset_name"));
                    row.put("category_name",   rs.getString("category_name"));
                    row.put("department_name", rs.getString("department_name"));
                    row.put("status",          rs.getString("asset_status"));
                    row.put("purchase_cost",   rs.getString("purchase_cost"));
                    row.put("purchase_date",   rs.getString("purchase_date"));
                    records.add(row);
                }
            }
        } catch (Exception e) {
            LOGGER.log(Level.SEVERE, "Error in searchAssets", e);
            result.put("error", "Sorry, there was an error retrieving the assets.");
            return result;
        }

        result.put("records", records);
        debugLog("searchAssets", result);
        return result;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // AVAILABLE ASSETS
    // ─────────────────────────────────────────────────────────────────────────

    public static Map<String, Object> getAvailableAssets(CopilotQueryPlan plan, HttpSession session) {
        // Reuse searchAssets with status forced to AVAILABLE
        CopilotQueryPlan clone = clonePlan(plan);
        clone.status = "Available";
        return searchAssets(clone, session);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // ALLOCATED ASSETS
    // ─────────────────────────────────────────────────────────────────────────

    public static Map<String, Object> getAllocatedAssets(CopilotQueryPlan plan, HttpSession session) {
        CopilotQueryPlan clone = clonePlan(plan);
        clone.status = "Allocated";
        return searchAssets(clone, session);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // DISPOSED ASSETS
    // ─────────────────────────────────────────────────────────────────────────

    public static Map<String, Object> getDisposedAssets(CopilotQueryPlan plan, HttpSession session) {
        Map<String, Object> result = new HashMap<>();
        String role    = sessionRole(session);
        String empCode = sessionAttr(session, "empCode");

        if ("EMPLOYEE".equalsIgnoreCase(role)) {
            result.put("error", "🔒 **Access Denied**: Disposed asset records are not available for employee role.");
            return result;
        }

        String sql =
            "SELECT a.asset_code, a.asset_name, c.category_name, d.department_name, " +
            "a.asset_status, a.purchase_cost " +
            "FROM assets a " +
            "LEFT JOIN asset_categories c ON a.category_id = c.category_id " +
            "LEFT JOIN departments d ON a.department_id = d.department_id " +
            "WHERE a.asset_status IN ('Disposed', 'DISPOSED', 'Condemned', 'CONDEMNED') " +
            "ORDER BY a.asset_code LIMIT 100";

        List<Map<String, String>> records = new ArrayList<>();
        try (Connection conn = DBConnection.getConnection();
             PreparedStatement ps = conn.prepareStatement(sql);
             ResultSet rs = ps.executeQuery()) {

            while (rs.next()) {
                Map<String, String> row = new HashMap<>();
                row.put("asset_code",      rs.getString("asset_code"));
                row.put("asset_name",      rs.getString("asset_name"));
                row.put("category_name",   rs.getString("category_name"));
                row.put("department_name", rs.getString("department_name"));
                row.put("status",          rs.getString("asset_status"));
                row.put("purchase_cost",   rs.getString("purchase_cost"));
                records.add(row);
            }
        } catch (Exception e) {
            LOGGER.log(Level.SEVERE, "Error in getDisposedAssets", e);
            result.put("error", "Sorry, there was an error retrieving disposed assets.");
            return result;
        }

        result.put("records", records);
        debugLog("getDisposedAssets", result);
        return result;
    }

    /**
     * The actual disposal WORKFLOW record for an asset - reason, proposed vs
     * approved vs realised value, method (scrap/auction/sale/donation/etc.),
     * and status through PENDING/APPROVED/COMPLETED/REJECTED/CANCELLED.
     *
     * Added because there was previously no coverage at all for the
     * asset_disposal table: getDisposedAssets() (above) only reports
     * assets.asset_status = 'Disposed', which cannot answer "why was AST020
     * disposed", "what method was used", or "how much value did we recover"
     * - real questions with real data that had no tool to reach them.
     */
    public static Map<String, Object> getAssetDisposalDetails(CopilotQueryPlan plan, HttpSession session) {
        Map<String, Object> result = new HashMap<>();
        String role = sessionRole(session);

        if ("EMPLOYEE".equalsIgnoreCase(role)) {
            result.put("error", "🔒 **Access Denied**: Disposal records are not available for employee role.");
            return result;
        }

        StringBuilder sql = new StringBuilder(
            "SELECT a.asset_code, a.asset_name, ad.disposal_reason, ad.disposal_status, " +
            "ad.disposal_date, ad.proposed_method, ad.proposed_value, ad.approved_method, " +
            "ad.approved_value, ad.approved_date, ad.final_method, ad.realised_value, " +
            "ad.completed_at, ad.rejection_reason, ad.cancellation_reason, ad.remarks " +
            "FROM asset_disposal ad " +
            "JOIN assets a ON ad.asset_id = a.asset_id " +
            "WHERE 1=1 "
        );
        if (plan.assetCode != null) sql.append("AND a.asset_code = ? ");
        if (plan.status     != null) sql.append("AND ad.disposal_status = ? ");
        sql.append("ORDER BY ad.disposal_date DESC LIMIT 100");

        List<Map<String, String>> records = new ArrayList<>();
        try (Connection conn = DBConnection.getConnection();
             PreparedStatement ps = conn.prepareStatement(sql.toString())) {

            int idx = 1;
            if (plan.assetCode != null) ps.setString(idx++, plan.assetCode);
            if (plan.status     != null) ps.setString(idx++, plan.status);

            try (ResultSet rs = ps.executeQuery()) {
                while (rs.next()) {
                    Map<String, String> row = new HashMap<>();
                    row.put("asset_code",         rs.getString("asset_code"));
                    row.put("asset_name",         rs.getString("asset_name"));
                    row.put("disposal_reason",    rs.getString("disposal_reason"));
                    row.put("disposal_status",    rs.getString("disposal_status"));
                    row.put("disposal_date",      rs.getString("disposal_date"));
                    row.put("proposed_method",    rs.getString("proposed_method"));
                    row.put("proposed_value",     rs.getString("proposed_value"));
                    row.put("approved_method",    rs.getString("approved_method"));
                    row.put("approved_value",     rs.getString("approved_value"));
                    row.put("approved_date",      rs.getString("approved_date"));
                    row.put("final_method",       rs.getString("final_method"));
                    row.put("realised_value",     rs.getString("realised_value"));
                    row.put("completed_at",       rs.getString("completed_at"));
                    row.put("rejection_reason",   rs.getString("rejection_reason"));
                    row.put("cancellation_reason", rs.getString("cancellation_reason"));
                    row.put("remarks",            rs.getString("remarks"));
                    records.add(row);
                }
            }
        } catch (Exception e) {
            LOGGER.log(Level.SEVERE, "Error in getAssetDisposalDetails", e);
            result.put("error", "Sorry, error retrieving disposal details.");
            return result;
        }

        result.put("records", records);
        debugLog("getAssetDisposalDetails", result);
        return result;
    }

    /**
     * Asset-to-employee TRANSFER history (asset_transfers) - who an asset
     * moved from and to, when, and why. Distinct from allocation (who holds
     * it NOW) and from the employees.joining_date tool (an employee's own
     * transfer between DEPARTMENTS, unrelated) - this is specifically the
     * asset's custody-change history.
     *
     * This table is confirmed live on this database but was never captured
     * in schema.sql until it was added alongside the workflow that now
     * populates it (AssetTransferDAO.reviewTransfer(), migration 010) - see
     * that migration's own comment for how the gap was found. Before that,
     * this tool always returned zero rows, by design, not as a bug: nothing
     * had ever written to the table.
     */
    public static Map<String, Object> getAssetTransferHistory(CopilotQueryPlan plan, HttpSession session) {
        Map<String, Object> result = new HashMap<>();
        String role = sessionRole(session);

        if ("EMPLOYEE".equalsIgnoreCase(role)) {
            result.put("error", "🔒 **Access Denied**: Asset transfer history is not available for employee role.");
            return result;
        }

        StringBuilder sql = new StringBuilder(
            "SELECT a.asset_code, a.asset_name, fe.employee_name AS from_employee, " +
            "te.employee_name AS to_employee, t.transfer_date, t.transfer_reason " +
            "FROM asset_transfers t " +
            "JOIN assets a ON t.asset_id = a.asset_id " +
            "LEFT JOIN employees fe ON t.from_employee_id = fe.employee_id " +
            "LEFT JOIN employees te ON t.to_employee_id = te.employee_id " +
            "WHERE 1=1 "
        );
        if (plan.assetCode != null) sql.append("AND a.asset_code = ? ");
        if (plan.employeeCode != null) {
            sql.append("AND (fe.employee_code = ? OR te.employee_code = ?) ");
        }
        sql.append("ORDER BY t.transfer_date DESC LIMIT 100");

        List<Map<String, String>> records = new ArrayList<>();
        try (Connection conn = DBConnection.getConnection();
             PreparedStatement ps = conn.prepareStatement(sql.toString())) {

            int idx = 1;
            if (plan.assetCode != null) ps.setString(idx++, plan.assetCode);
            if (plan.employeeCode != null) {
                ps.setString(idx++, plan.employeeCode);
                ps.setString(idx++, plan.employeeCode);
            }

            try (ResultSet rs = ps.executeQuery()) {
                while (rs.next()) {
                    Map<String, String> row = new HashMap<>();
                    row.put("asset_code",      rs.getString("asset_code"));
                    row.put("asset_name",      rs.getString("asset_name"));
                    row.put("from_employee",   rs.getString("from_employee"));
                    row.put("to_employee",     rs.getString("to_employee"));
                    row.put("transfer_date",   rs.getString("transfer_date"));
                    row.put("transfer_reason", rs.getString("transfer_reason"));
                    records.add(row);
                }
            }
        } catch (Exception e) {
            LOGGER.log(Level.SEVERE, "Error in getAssetTransferHistory", e);
            result.put("error", "Sorry, error retrieving asset transfer history.");
            return result;
        }

        result.put("records", records);
        debugLog("getAssetTransferHistory", result);
        return result;
    }

    /**
     * Document-grounded answers: keyword search over the TEXT CONTENT of
     * uploaded asset documents (manuals, invoices, warranty papers -
     * asset_document_text_index.extracted_text, populated at upload time by
     * UploadAssetDocumentServlet/AddAssetServlet via
     * AssetDocumentDAO.indexDocumentText()). Distinct from every other tool
     * in this class, which all answer from structured database columns -
     * this is the one path that lets the Copilot ground an answer in the
     * actual prose of an uploaded file, e.g. "what does the manual for
     * AST003 say about cleaning" or "which invoice mentions extended
     * warranty".
     *
     * AssetDocumentDAO.searchDocumentText() already existed - built,
     * snippet-formatting and all, with a comment reading "for copilot
     * matching" - but was never actually registered as a tool anywhere in
     * this catalog. Wiring it in here is the entire fix; the search logic
     * itself (a LIKE query with a highlighted snippet extracted around the
     * first match) is untouched.
     */
    public static Map<String, Object> searchAssetDocuments(CopilotQueryPlan plan, HttpSession session) {
        Map<String, Object> result = new HashMap<>();
        String role = sessionRole(session);

        if ("EMPLOYEE".equalsIgnoreCase(role)) {
            result.put("error", "🔒 **Access Denied**: Document search is not available for employee role.");
            return result;
        }

        String keyword = plan.knowledgeQuery;
        if (keyword == null || keyword.trim().isEmpty()) {
            result.put("error", "Please specify what to search for, e.g. \"search the documents for extended warranty\".");
            return result;
        }

        try {
            List<String> snippets = new AssetDocumentDAO().searchDocumentText(keyword);
            result.put("records", snippets);
            if (snippets.isEmpty()) {
                result.put("note", "No uploaded document text matched \"" + keyword
                        + "\". Only documents whose text was successfully extracted at upload time are searchable.");
            }
        } catch (Exception e) {
            LOGGER.log(Level.SEVERE, "Error in searchAssetDocuments", e);
            result.put("error", "Sorry, error searching asset documents.");
            return result;
        }

        debugLog("searchAssetDocuments", result);
        return result;
    }

    /**
     * Warranty RENEWAL history (warranty_renewals) - when a warranty was
     * extended, from what expiry to what new expiry, by how many months, and
     * at what cost. Distinct from getWarranty() (above), which reports the
     * asset's CURRENT warranty_expiry only and has no visibility into past
     * renewal actions or their cost.
     */
    public static Map<String, Object> getWarrantyRenewalHistory(CopilotQueryPlan plan, HttpSession session) {
        Map<String, Object> result = new HashMap<>();
        String role = sessionRole(session);

        if ("EMPLOYEE".equalsIgnoreCase(role)) {
            result.put("error", "🔒 **Access Denied**: Warranty renewal history is not available for employee role.");
            return result;
        }

        StringBuilder sql = new StringBuilder(
            "SELECT a.asset_code, a.asset_name, wr.previous_expiry, wr.new_expiry, " +
            "wr.extension_months, wr.renewal_cost, wr.notes, wr.created_at " +
            "FROM warranty_renewals wr " +
            "JOIN assets a ON wr.asset_id = a.asset_id " +
            "WHERE 1=1 "
        );
        if (plan.assetCode != null) sql.append("AND a.asset_code = ? ");
        sql.append("ORDER BY wr.created_at DESC LIMIT 100");

        List<Map<String, String>> records = new ArrayList<>();
        try (Connection conn = DBConnection.getConnection();
             PreparedStatement ps = conn.prepareStatement(sql.toString())) {

            int idx = 1;
            if (plan.assetCode != null) ps.setString(idx++, plan.assetCode);

            try (ResultSet rs = ps.executeQuery()) {
                while (rs.next()) {
                    Map<String, String> row = new HashMap<>();
                    row.put("asset_code",       rs.getString("asset_code"));
                    row.put("asset_name",       rs.getString("asset_name"));
                    row.put("previous_expiry",  rs.getString("previous_expiry"));
                    row.put("new_expiry",       rs.getString("new_expiry"));
                    row.put("extension_months", rs.getString("extension_months"));
                    row.put("renewal_cost",     rs.getString("renewal_cost"));
                    row.put("notes",            rs.getString("notes"));
                    row.put("renewed_at",       rs.getString("created_at"));
                    records.add(row);
                }
            }
        } catch (Exception e) {
            LOGGER.log(Level.SEVERE, "Error in getWarrantyRenewalHistory", e);
            result.put("error", "Sorry, error retrieving warranty renewal history.");
            return result;
        }

        result.put("records", records);
        debugLog("getWarrantyRenewalHistory", result);
        return result;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // ASSET HOLDER
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * Who currently holds a given asset.
     * Requires plan.assetCode to be set. If not set, falls back to listing
     * all current allocations for a category or department.
     */
    public static Map<String, Object> getAssetHolder(CopilotQueryPlan plan, HttpSession session) {
        Map<String, Object> result = new HashMap<>();
        String role = sessionRole(session);

        if (isBlank(plan.assetCode)) {
            // No asset code — fall back to allocation search
            return searchAllocations(plan, session);
        }

        String sql =
            "SELECT a.asset_code, a.asset_name, c.category_name, " +
            "e.employee_code, e.employee_name AS full_name, e.designation, d.department_name, " +
            "aa.allocation_date " +
            "FROM asset_allocation aa " +
            "JOIN assets a   ON aa.asset_id   = a.asset_id " +
            "JOIN employees e ON aa.employee_id = e.employee_id " +
            "LEFT JOIN asset_categories c ON a.category_id = c.category_id " +
            "LEFT JOIN departments d ON e.department_id = d.department_id " +
            "WHERE aa.allocation_status = 'ALLOCATED' " +
            "AND a.asset_code = ? " +
            "ORDER BY aa.allocation_date DESC LIMIT 1";

        List<Map<String, String>> records = new ArrayList<>();
        try (Connection conn = DBConnection.getConnection();
             PreparedStatement ps = conn.prepareStatement(sql)) {

            ps.setString(1, plan.assetCode);
            try (ResultSet rs = ps.executeQuery()) {
                if (rs.next()) {
                    Map<String, String> row = new HashMap<>();
                    row.put("asset_code",      rs.getString("asset_code"));
                    row.put("asset_name",      rs.getString("asset_name"));
                    row.put("category_name",   rs.getString("category_name"));
                    row.put("employee_code",   rs.getString("employee_code"));
                    row.put("full_name",       rs.getString("full_name"));
                    row.put("designation",     rs.getString("designation"));
                    row.put("department_name", rs.getString("department_name"));
                    row.put("allocation_date", rs.getString("allocation_date"));
                    records.add(row);
                }
            }
        } catch (Exception e) {
            LOGGER.log(Level.SEVERE, "Error in getAssetHolder", e);
            result.put("error", "Sorry, there was an error finding the asset holder.");
            return result;
        }

        result.put("records",   records);
        result.put("assetCode", plan.assetCode);
        debugLog("getAssetHolder", result);
        return result;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // PENDING ASSET REQUESTS
    // ─────────────────────────────────────────────────────────────────────────

    public static Map<String, Object> getPendingAssetRequests(CopilotQueryPlan plan, HttpSession session) {
        Map<String, Object> result = new HashMap<>();
        String role    = sessionRole(session);
        String empCode = sessionAttr(session, "empCode");

        // Fault: asset_requests has no justification column - the real
        // column is request_reason. Same class of bug found repeatedly this
        // pass (employees.full_name, audit_logs.log_id,
        // maintenance_requests.resolution_notes). Aliased rather than
        // renamed downstream.
        StringBuilder sql = new StringBuilder(
            "SELECT ar.request_id, e.employee_code, e.employee_name AS full_name, d.department_name, " +
            "c.category_name, ar.request_reason AS justification, ar.request_date, ar.request_status " +
            "FROM asset_requests ar " +
            "JOIN employees e ON ar.employee_id = e.employee_id " +
            "LEFT JOIN departments d ON e.department_id = d.department_id " +
            "LEFT JOIN asset_categories c ON ar.category_id = c.category_id " +
            // Includes PENDING_DEPT_HEAD alongside PENDING - both are "pending"
            // in the general sense this read-only tool answers for; a request
            // sitting at Department Head review hasn't reached the Asset
            // Manager stage yet but is still an open, unresolved request.
            // Matches the same two-value IN pattern already used for
            // maintenance_requests just below.
            "WHERE ar.request_status IN ('PENDING', 'PENDING_DEPT_HEAD') "
        );

        if ("EMPLOYEE".equalsIgnoreCase(role) && !isBlank(empCode)) {
            sql.append("AND e.employee_code = ? ");
        }
        sql.append("ORDER BY ar.request_date DESC LIMIT 50");

        List<Map<String, String>> records = new ArrayList<>();
        try (Connection conn = DBConnection.getConnection();
             PreparedStatement ps = conn.prepareStatement(sql.toString())) {

            if ("EMPLOYEE".equalsIgnoreCase(role) && !isBlank(empCode)) {
                ps.setString(1, empCode);
            }

            try (ResultSet rs = ps.executeQuery()) {
                while (rs.next()) {
                    Map<String, String> row = new HashMap<>();
                    row.put("request_id",      rs.getString("request_id"));
                    row.put("employee_code",   rs.getString("employee_code"));
                    row.put("full_name",       rs.getString("full_name"));
                    row.put("department_name", rs.getString("department_name"));
                    row.put("category_name",   rs.getString("category_name"));
                    row.put("justification",   rs.getString("justification"));
                    row.put("request_date",    rs.getString("request_date"));
                    row.put("request_status",  rs.getString("request_status"));
                    records.add(row);
                }
            }
        } catch (Exception e) {
            LOGGER.log(Level.SEVERE, "Error in getPendingAssetRequests", e);
            result.put("error", "Sorry, there was an error retrieving pending asset requests.");
            return result;
        }

        result.put("records", records);
        debugLog("getPendingAssetRequests", result);
        return result;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // EMPLOYEE DETAILS
    // ─────────────────────────────────────────────────────────────────────────

    public static Map<String, Object> getEmployeeDetails(CopilotQueryPlan plan, HttpSession session) {
        Map<String, Object> result = new HashMap<>();
        String role = sessionRole(session);

        if ("EMPLOYEE".equalsIgnoreCase(role)) {
            result.put("error", "🔒 **Access Denied**: Employees cannot view other employees' details.");
            return result;
        }

        boolean hasCode = !isBlank(plan.employeeCode);
        boolean hasName = !isBlank(plan.employeeName);

        if (!hasCode && !hasName) {
            result.put("error", "Please specify an employee code (e.g. EMP006) or employee name.");
            return result;
        }

        StringBuilder sql = new StringBuilder(
            "SELECT e.employee_code, e.employee_name AS full_name, e.designation, e.email, e.phone, " +
            "d.department_name, e.status " +
            "FROM employees e " +
            "LEFT JOIN departments d ON e.department_id = d.department_id " +
            "WHERE 1=1 "
        );

        if (hasCode) sql.append("AND e.employee_code = ? ");
        if (hasName) sql.append("AND LOWER(e.employee_name) LIKE LOWER(?) ");
        sql.append("ORDER BY e.employee_code LIMIT 10");

        List<Map<String, String>> records = new ArrayList<>();
        try (Connection conn = DBConnection.getConnection();
             PreparedStatement ps = conn.prepareStatement(sql.toString())) {

            int idx = 1;
            if (hasCode) ps.setString(idx++, plan.employeeCode);
            if (hasName) ps.setString(idx++, "%" + plan.employeeName + "%");

            try (ResultSet rs = ps.executeQuery()) {
                while (rs.next()) {
                    Map<String, String> row = new HashMap<>();
                    row.put("employee_code",   rs.getString("employee_code"));
                    row.put("full_name",       rs.getString("full_name"));
                    row.put("designation",     rs.getString("designation"));
                    row.put("email",           rs.getString("email"));
                    row.put("phone",           rs.getString("phone"));
                    row.put("department_name", rs.getString("department_name"));
                    row.put("status",          rs.getString("status"));
                    records.add(row);
                }
            }
        } catch (Exception e) {
            LOGGER.log(Level.SEVERE, "Error in getEmployeeDetails", e);
            result.put("error", "Sorry, there was an error retrieving employee details.");
            return result;
        }

        result.put("records", records);
        debugLog("getEmployeeDetails", result);
        return result;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // EMPLOYEE ALLOCATIONS
    // ─────────────────────────────────────────────────────────────────────────

    public static Map<String, Object> getEmployeeAllocations(CopilotQueryPlan plan, HttpSession session) {
        Map<String, Object> result = new HashMap<>();
        String role    = sessionRole(session);
        String empCode = sessionAttr(session, "empCode");

        boolean hasCode = !isBlank(plan.employeeCode);
        boolean hasName = !isBlank(plan.employeeName);

        if (!hasCode && !hasName && !("EMPLOYEE".equalsIgnoreCase(role))) {
            result.put("error", "Please specify an employee code (e.g. EMP006) or employee name to see their allocations.");
            return result;
        }

        StringBuilder sql = new StringBuilder(
            "SELECT a.asset_code, a.asset_name, c.category_name, " +
            "e.employee_code, e.employee_name AS full_name, d.department_name, aa.allocation_date " +
            "FROM asset_allocation aa " +
            "JOIN assets a ON aa.asset_id = a.asset_id " +
            "JOIN employees e ON aa.employee_id = e.employee_id " +
            "LEFT JOIN asset_categories c ON a.category_id = c.category_id " +
            "LEFT JOIN departments d ON e.department_id = d.department_id " +
            "WHERE aa.allocation_status = 'ALLOCATED' "
        );

        if (hasCode) sql.append("AND e.employee_code = ? ");
        if (hasName) sql.append("AND LOWER(e.employee_name) LIKE LOWER(?) ");
        if ("EMPLOYEE".equalsIgnoreCase(role) && !isBlank(empCode) && !hasCode && !hasName) {
            sql.append("AND e.employee_code = ? ");
        }
        sql.append("ORDER BY aa.allocation_date DESC LIMIT 50");

        List<Map<String, String>> records = new ArrayList<>();
        try (Connection conn = DBConnection.getConnection();
             PreparedStatement ps = conn.prepareStatement(sql.toString())) {

            int idx = 1;
            if (hasCode) ps.setString(idx++, plan.employeeCode);
            if (hasName) ps.setString(idx++, "%" + plan.employeeName + "%");
            if ("EMPLOYEE".equalsIgnoreCase(role) && !isBlank(empCode) && !hasCode && !hasName) {
                ps.setString(idx++, empCode);
            }

            try (ResultSet rs = ps.executeQuery()) {
                while (rs.next()) {
                    Map<String, String> row = new HashMap<>();
                    row.put("asset_code",      rs.getString("asset_code"));
                    row.put("asset_name",      rs.getString("asset_name"));
                    row.put("category_name",   rs.getString("category_name"));
                    row.put("employee_code",   rs.getString("employee_code"));
                    row.put("full_name",       rs.getString("full_name"));
                    row.put("department_name", rs.getString("department_name"));
                    row.put("allocation_date", rs.getString("allocation_date"));
                    records.add(row);
                }
            }
        } catch (Exception e) {
            LOGGER.log(Level.SEVERE, "Error in getEmployeeAllocations", e);
            result.put("error", "Sorry, there was an error retrieving employee allocations.");
            return result;
        }

        result.put("records", records);
        debugLog("getEmployeeAllocations", result);
        return result;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // DEPARTMENT SUMMARY
    // ─────────────────────────────────────────────────────────────────────────

    public static Map<String, Object> getDepartmentSummary(CopilotQueryPlan plan, HttpSession session) {
        Map<String, Object> result = new HashMap<>();
        String role = sessionRole(session);

        if ("EMPLOYEE".equalsIgnoreCase(role)) {
            result.put("error", "🔒 **Access Denied**: Department summary is not available for employee role.");
            return result;
        }

        String sql =
            "SELECT d.department_name, " +
            "COUNT(a.asset_id) AS asset_count, " +
            "COALESCE(SUM(a.purchase_cost), 0) AS total_cost, " +
            "COALESCE(AVG(a.purchase_cost), 0) AS avg_cost " +
            "FROM departments d " +
            "LEFT JOIN assets a ON a.department_id = d.department_id " +
            "GROUP BY d.department_id, d.department_name " +
            "ORDER BY total_cost DESC";

        List<Map<String, Object>> records = new ArrayList<>();
        try (Connection conn = DBConnection.getConnection();
             PreparedStatement ps = conn.prepareStatement(sql);
             ResultSet rs = ps.executeQuery()) {

            while (rs.next()) {
                Map<String, Object> row = new HashMap<>();
                row.put("department_name", rs.getString("department_name"));
                row.put("asset_count",     rs.getInt("asset_count"));
                row.put("total_cost",      rs.getBigDecimal("total_cost"));
                row.put("avg_cost",        rs.getBigDecimal("avg_cost"));
                records.add(row);
            }
        } catch (Exception e) {
            LOGGER.log(Level.SEVERE, "Error in getDepartmentSummary", e);
            result.put("error", "Sorry, there was an error retrieving department summary.");
            return result;
        }

        result.put("records", records);
        debugLog("getDepartmentSummary", result);
        return result;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // CATEGORY SUMMARY
    // ─────────────────────────────────────────────────────────────────────────

    public static Map<String, Object> getCategorySummary(CopilotQueryPlan plan, HttpSession session) {
        Map<String, Object> result = new HashMap<>();
        String role = sessionRole(session);

        if ("EMPLOYEE".equalsIgnoreCase(role)) {
            result.put("error", "🔒 **Access Denied**: Category summary is not available for employee role.");
            return result;
        }

        String sql =
            "SELECT c.category_name, " +
            "COUNT(a.asset_id) AS asset_count, " +
            "COALESCE(SUM(a.purchase_cost), 0) AS total_cost, " +
            "COALESCE(AVG(a.purchase_cost), 0) AS avg_cost " +
            "FROM asset_categories c " +
            "LEFT JOIN assets a ON a.category_id = c.category_id " +
            "GROUP BY c.category_id, c.category_name " +
            "ORDER BY total_cost DESC";

        List<Map<String, Object>> records = new ArrayList<>();
        try (Connection conn = DBConnection.getConnection();
             PreparedStatement ps = conn.prepareStatement(sql);
             ResultSet rs = ps.executeQuery()) {

            while (rs.next()) {
                Map<String, Object> row = new HashMap<>();
                row.put("category_name", rs.getString("category_name"));
                row.put("asset_count",   rs.getInt("asset_count"));
                row.put("total_cost",    rs.getBigDecimal("total_cost"));
                row.put("avg_cost",      rs.getBigDecimal("avg_cost"));
                records.add(row);
            }
        } catch (Exception e) {
            LOGGER.log(Level.SEVERE, "Error in getCategorySummary", e);
            result.put("error", "Sorry, there was an error retrieving category summary.");
            return result;
        }

        result.put("records", records);
        debugLog("getCategorySummary", result);
        return result;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // SUPPLIER SUMMARY
    // ─────────────────────────────────────────────────────────────────────────

    public static Map<String, Object> getSupplierSummary(CopilotQueryPlan plan, HttpSession session) {
        Map<String, Object> result = new HashMap<>();
        String role = sessionRole(session);

        if ("EMPLOYEE".equalsIgnoreCase(role)) {
            result.put("error", "🔒 **Access Denied**: Supplier summary is not available for employee role.");
            return result;
        }

        // Try vendors table; gracefully fail if column names differ
        String sql =
            "SELECT v.vendor_name, COUNT(a.asset_id) AS asset_count, " +
            "COALESCE(SUM(a.purchase_cost), 0) AS total_cost " +
            "FROM vendors v " +
            "LEFT JOIN assets a ON a.vendor_id = v.vendor_id " +
            "GROUP BY v.vendor_id, v.vendor_name " +
            "ORDER BY total_cost DESC LIMIT 50";

        List<Map<String, Object>> records = new ArrayList<>();
        try (Connection conn = DBConnection.getConnection();
             PreparedStatement ps = conn.prepareStatement(sql);
             ResultSet rs = ps.executeQuery()) {

            while (rs.next()) {
                Map<String, Object> row = new HashMap<>();
                row.put("vendor_name",  rs.getString("vendor_name"));
                row.put("asset_count",  rs.getInt("asset_count"));
                row.put("total_cost",   rs.getBigDecimal("total_cost"));
                records.add(row);
            }
        } catch (Exception e) {
            LOGGER.log(Level.SEVERE, "Error in getSupplierSummary", e);
            result.put("error", "Sorry, there was an error retrieving supplier summary.");
            return result;
        }

        result.put("records", records);
        debugLog("getSupplierSummary", result);
        return result;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // DASHBOARD SUMMARY
    // ─────────────────────────────────────────────────────────────────────────

    public static Map<String, Object> getDashboardSummary(CopilotQueryPlan plan, HttpSession session) {
        Map<String, Object> result = new HashMap<>();
        String role    = sessionRole(session);
        String empCode = sessionAttr(session, "empCode");

        String sql;
        if ("EMPLOYEE".equalsIgnoreCase(role) && !isBlank(empCode)) {
            sql =
                "SELECT " +
                "COUNT(*) AS total, " +
                "SUM(CASE WHEN a.asset_status = 'Available' THEN 1 ELSE 0 END) AS available, " +
                "SUM(CASE WHEN a.asset_status = 'Allocated' THEN 1 ELSE 0 END) AS allocated, " +
                "SUM(CASE WHEN a.asset_status = 'Under Maintenance' THEN 1 ELSE 0 END) AS under_maintenance, " +
                "COALESCE(SUM(a.purchase_cost), 0) AS total_cost " +
                "FROM assets a " +
                "WHERE a.asset_id IN (SELECT asset_id FROM asset_allocation " +
                "WHERE employee_id = (SELECT employee_id FROM employees WHERE employee_code = ?))";
        } else {
            sql =
                "SELECT " +
                "COUNT(*) AS total, " +
                "SUM(CASE WHEN a.asset_status = 'Available' THEN 1 ELSE 0 END) AS available, " +
                "SUM(CASE WHEN a.asset_status = 'Allocated' THEN 1 ELSE 0 END) AS allocated, " +
                "SUM(CASE WHEN a.asset_status = 'Under Maintenance' THEN 1 ELSE 0 END) AS under_maintenance, " +
                "COALESCE(SUM(a.purchase_cost), 0) AS total_cost " +
                "FROM assets a";
        }

        try (Connection conn = DBConnection.getConnection();
             PreparedStatement ps = conn.prepareStatement(sql)) {

            if ("EMPLOYEE".equalsIgnoreCase(role) && !isBlank(empCode)) {
                ps.setString(1, empCode);
            }

            try (ResultSet rs = ps.executeQuery()) {
                if (rs.next()) {
                    result.put("total",             rs.getInt("total"));
                    result.put("available",         rs.getInt("available"));
                    result.put("allocated",         rs.getInt("allocated"));
                    result.put("under_maintenance", rs.getInt("under_maintenance"));
                    result.put("total_cost",        rs.getBigDecimal("total_cost"));
                }
            }
        } catch (Exception e) {
            LOGGER.log(Level.SEVERE, "Error in getDashboardSummary", e);
            result.put("error", "Sorry, there was an error retrieving the dashboard summary.");
            return result;
        }

        debugLog("getDashboardSummary", result);
        return result;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // WARRANTY
    // ─────────────────────────────────────────────────────────────────────────

    public static Map<String, Object> getWarranty(CopilotQueryPlan plan, HttpSession session) {
        Map<String, Object> result = new HashMap<>();
        String role    = sessionRole(session);
        String empCode = sessionAttr(session, "empCode");

        int nDays = plan.days != null ? plan.days : 30;

        // Fault, found live via the LLM agent loop: this used to branch only
        // on plan.intent. That field is set by the keyword pipeline
        // (CopilotIntentDetector), but CopilotToolCatalog.toPlan() - the LLM
        // tool path - never touches plan.intent at all; it puts the model's
        // "status" argument (EXPIRING/EXPIRED/ACTIVE) into plan.status
        // instead. Every get_warranty call made by the agent loop therefore
        // fell through to the "expiring" branch below regardless of the
        // status actually requested, AND skipped binding that branch's own
        // "?" placeholder (also gated on plan.intent) - so it failed on
        // every single call with "No value specified for parameter 1"
        // (confirmed live: asking "which laptops are out of warranty"
        // routed here with status=EXPIRED and errored every time). Checking
        // plan.status too makes this work from both callers.
        boolean isExpired = plan.intent == CopilotIntentType.WARRANTY_EXPIRED
                || "EXPIRED".equalsIgnoreCase(plan.status);
        boolean isThisMonth = plan.intent == CopilotIntentType.WARRANTY_THIS_MONTH
                || "THIS_MONTH".equalsIgnoreCase(plan.status);

        String condition;
        boolean bindDays;
        if (isExpired) {
            // Already expired — past dates only
            condition = "a.warranty_expiry IS NOT NULL AND a.warranty_expiry < CURDATE()";
            bindDays = false;
        } else if (isThisMonth) {
            condition = "a.warranty_expiry IS NOT NULL " +
                        "AND MONTH(a.warranty_expiry) = MONTH(CURDATE()) " +
                        "AND YEAR(a.warranty_expiry) = YEAR(CURDATE()) " +
                        "AND a.warranty_expiry >= CURDATE()";
            bindDays = false;
        } else {
            // Expiring within N days (future only, including the LLM's
            // "EXPIRING"/"ACTIVE" status arguments — both mean "still within
            // the window", the only distinction the model has no dedicated
            // SQL shape for). Critical: >= CURDATE() ensures we never return
            // already-expired rows here.
            condition = "a.warranty_expiry IS NOT NULL " +
                        "AND a.warranty_expiry >= CURDATE() " +
                        "AND a.warranty_expiry <= DATE_ADD(CURDATE(), INTERVAL ? DAY)";
            bindDays = true;
        }

        String orderDir = isExpired ? "DESC" : "ASC";

        String sql =
            "SELECT a.asset_code, a.asset_name, c.category_name, d.department_name, " +
            "a.warranty_expiry, DATEDIFF(a.warranty_expiry, CURDATE()) AS days_remaining " +
            "FROM assets a " +
            "LEFT JOIN asset_categories c ON a.category_id = c.category_id " +
            "LEFT JOIN departments d ON a.department_id = d.department_id " +
            "WHERE " + condition + " ";

        if ("EMPLOYEE".equalsIgnoreCase(role) && !isBlank(empCode)) {
            sql += "AND a.asset_id IN (SELECT asset_id FROM asset_allocation " +
                   "WHERE employee_id = (SELECT employee_id FROM employees WHERE employee_code = ?)) ";
        }
        sql += "ORDER BY a.warranty_expiry " + orderDir + " LIMIT 50";

        List<Map<String, Object>> records = new ArrayList<>();
        try (Connection conn = DBConnection.getConnection();
             PreparedStatement ps = conn.prepareStatement(sql)) {

            int idx = 1;
            if (bindDays) {
                ps.setInt(idx++, nDays);
            }
            if ("EMPLOYEE".equalsIgnoreCase(role) && !isBlank(empCode)) {
                ps.setString(idx++, empCode);
            }

            try (ResultSet rs = ps.executeQuery()) {
                while (rs.next()) {
                    Map<String, Object> row = new HashMap<>();
                    row.put("asset_code",      rs.getString("asset_code"));
                    row.put("asset_name",      rs.getString("asset_name"));
                    row.put("category_name",   rs.getString("category_name"));
                    row.put("department_name", rs.getString("department_name"));
                    row.put("warranty_expiry", rs.getString("warranty_expiry"));
                    row.put("days_remaining",  rs.getInt("days_remaining"));
                    records.add(row);
                }
            }
        } catch (Exception e) {
            LOGGER.log(Level.SEVERE, "Error in getWarranty", e);
            result.put("error", "Sorry, error retrieving warranty details.");
            return result;
        }

        result.put("records", records);
        result.put("days",    nDays);
        debugLog("getWarranty", result);
        return result;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MAINTENANCE
    // ─────────────────────────────────────────────────────────────────────────

    public static Map<String, Object> getPendingMaintenance(CopilotQueryPlan plan, HttpSession session) {
        Map<String, Object> result = new HashMap<>();
        String role    = sessionRole(session);
        String empCode = sessionAttr(session, "empCode");

        StringBuilder sql = new StringBuilder(
            "SELECT a.asset_code, a.asset_name, c.category_name, d.department_name, " +
            "m.issue_description, m.request_status, m.request_date " +
            "FROM maintenance_requests m " +
            "JOIN assets a ON m.asset_id = a.asset_id " +
            "LEFT JOIN asset_categories c ON a.category_id = c.category_id " +
            "LEFT JOIN departments d ON a.department_id = d.department_id " +
            "WHERE m.request_status IN ('PENDING', 'IN_PROGRESS') "
        );

        if ("EMPLOYEE".equalsIgnoreCase(role) && !isBlank(empCode)) {
            sql.append("AND a.asset_id IN (SELECT asset_id FROM asset_allocation " +
                       "WHERE employee_id = (SELECT employee_id FROM employees WHERE employee_code = ?)) ");
        }
        sql.append("ORDER BY m.request_date DESC LIMIT 50");

        List<Map<String, String>> records = new ArrayList<>();
        try (Connection conn = DBConnection.getConnection();
             PreparedStatement ps = conn.prepareStatement(sql.toString())) {

            if ("EMPLOYEE".equalsIgnoreCase(role) && !isBlank(empCode)) {
                ps.setString(1, empCode);
            }

            try (ResultSet rs = ps.executeQuery()) {
                while (rs.next()) {
                    Map<String, String> row = new HashMap<>();
                    row.put("asset_code",        rs.getString("asset_code"));
                    row.put("asset_name",        rs.getString("asset_name"));
                    row.put("category_name",     rs.getString("category_name"));
                    row.put("department_name",   rs.getString("department_name"));
                    row.put("issue_description", rs.getString("issue_description"));
                    row.put("request_status",    rs.getString("request_status"));
                    row.put("request_date",      rs.getString("request_date"));
                    records.add(row);
                }
            }
        } catch (Exception e) {
            LOGGER.log(Level.SEVERE, "Error in getPendingMaintenance", e);
            result.put("error", "Sorry, error retrieving maintenance details.");
            return result;
        }

        result.put("records", records);
        debugLog("getPendingMaintenance", result);
        return result;
    }

    public static Map<String, Object> getMaintenanceHistory(CopilotQueryPlan plan, HttpSession session) {
        Map<String, Object> result = new HashMap<>();
        String role    = sessionRole(session);
        String empCode = sessionAttr(session, "empCode");

        if (isBlank(plan.assetCode)) {
            result.put("error", "Please specify the asset code (e.g. AST003) for the maintenance history.");
            return result;
        }

        // Fault: maintenance_requests has no resolution_notes column - the
        // real column is remarks. Same class of bug as employees.full_name
        // and audit_logs.log_id found earlier this pass. Confirmed live:
        // every maintenance-history tool call threw "Unknown column
        // 'm.resolution_notes'". Aliased rather than renamed downstream.
        StringBuilder sql = new StringBuilder(
            "SELECT a.asset_code, a.asset_name, " +
            "m.request_date, m.issue_description, m.request_status, m.remarks AS resolution_notes " +
            "FROM maintenance_requests m " +
            "JOIN assets a ON m.asset_id = a.asset_id " +
            "WHERE a.asset_code = ? "
        );

        if ("EMPLOYEE".equalsIgnoreCase(role) && !isBlank(empCode)) {
            sql.append("AND a.asset_id IN (SELECT asset_id FROM asset_allocation " +
                       "WHERE employee_id = (SELECT employee_id FROM employees WHERE employee_code = ?)) ");
        }
        sql.append("ORDER BY m.request_date DESC LIMIT 50");

        List<Map<String, String>> records = new ArrayList<>();
        try (Connection conn = DBConnection.getConnection();
             PreparedStatement ps = conn.prepareStatement(sql.toString())) {

            ps.setString(1, plan.assetCode);
            if ("EMPLOYEE".equalsIgnoreCase(role) && !isBlank(empCode)) {
                ps.setString(2, empCode);
            }

            try (ResultSet rs = ps.executeQuery()) {
                while (rs.next()) {
                    Map<String, String> row = new HashMap<>();
                    row.put("asset_code",        rs.getString("asset_code"));
                    row.put("asset_name",        rs.getString("asset_name"));
                    row.put("request_date",      rs.getString("request_date"));
                    row.put("issue_description", rs.getString("issue_description"));
                    row.put("request_status",    rs.getString("request_status"));
                    row.put("resolution_notes",  rs.getString("resolution_notes"));
                    records.add(row);
                }
            }
        } catch (Exception e) {
            LOGGER.log(Level.SEVERE, "Error in getMaintenanceHistory", e);
            result.put("error", "Sorry, error retrieving maintenance history.");
            return result;
        }

        result.put("records", records);
        debugLog("getMaintenanceHistory", result);
        return result;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // EMPLOYEE SEARCH (generic)
    // ─────────────────────────────────────────────────────────────────────────

    public static Map<String, Object> searchEmployees(CopilotQueryPlan plan, HttpSession session) {
        Map<String, Object> result = new HashMap<>();
        String role = sessionRole(session);

        if ("EMPLOYEE".equalsIgnoreCase(role)) {
            result.put("error", "🔒 **Access Denied**: Employees cannot search other employees.");
            return result;
        }

        StringBuilder sql = new StringBuilder(
            "SELECT e.employee_code, e.employee_name AS full_name, e.designation, d.department_name " +
            "FROM employees e " +
            "LEFT JOIN departments d ON e.department_id = d.department_id " +
            "WHERE 1=1 "
        );

        if (plan.departmentName != null) sql.append("AND LOWER(d.department_name) = LOWER(?) ");
        if (plan.employeeCode   != null) sql.append("AND e.employee_code = ? ");
        if (plan.employeeName   != null) sql.append("AND LOWER(e.employee_name) LIKE LOWER(?) ");
        // Same fix as searchAssets() - see that method's comment. created_at
        // is when the employee record was actually added to AMS.
        if (plan.startDate != null) sql.append("AND e.created_at >= ? ");
        if (plan.endDate   != null) sql.append("AND e.created_at < ? ");
        sql.append("ORDER BY e.employee_code LIMIT 50");

        List<Map<String, String>> records = new ArrayList<>();
        try (Connection conn = DBConnection.getConnection();
             PreparedStatement ps = conn.prepareStatement(sql.toString())) {

            int idx = 1;
            if (plan.departmentName != null) ps.setString(idx++, plan.departmentName);
            if (plan.employeeCode   != null) ps.setString(idx++, plan.employeeCode);
            if (plan.employeeName   != null) ps.setString(idx++, "%" + plan.employeeName + "%");
            if (plan.startDate != null) ps.setTimestamp(idx++, java.sql.Timestamp.valueOf(plan.startDate.atStartOfDay()));
            if (plan.endDate   != null) ps.setTimestamp(idx++, java.sql.Timestamp.valueOf(plan.endDate.plusDays(1).atStartOfDay()));

            try (ResultSet rs = ps.executeQuery()) {
                while (rs.next()) {
                    Map<String, String> row = new HashMap<>();
                    row.put("employee_code",   rs.getString("employee_code"));
                    row.put("full_name",       rs.getString("full_name"));
                    row.put("designation",     rs.getString("designation"));
                    row.put("department_name", rs.getString("department_name"));
                    records.add(row);
                }
            }
        } catch (Exception e) {
            LOGGER.log(Level.SEVERE, "Error in searchEmployees", e);
            result.put("error", "Sorry, error searching employees.");
            return result;
        }

        result.put("records", records);
        debugLog("searchEmployees", result);
        return result;
    }

    /**
     * Employees by WHEN THEY JOINED (employees.joining_date), optionally
     * scoped to a department. Added because there was previously no tool at
     * all for this - "how many employees joined last month?" had no way to
     * be answered with real data and could only get an honest "I don't have
     * a tool for that" (confirmed live). joining_date is a real, existing
     * column that was simply never exposed to the Copilot.
     */
    public static Map<String, Object> getEmployeesByJoiningDate(CopilotQueryPlan plan, HttpSession session) {
        Map<String, Object> result = new HashMap<>();
        String role = sessionRole(session);

        if ("EMPLOYEE".equalsIgnoreCase(role)) {
            result.put("error", "🔒 **Access Denied**: Employees cannot search other employees.");
            return result;
        }

        StringBuilder sql = new StringBuilder(
            "SELECT e.employee_code, e.employee_name AS full_name, e.designation, " +
            "d.department_name, e.joining_date " +
            "FROM employees e " +
            "LEFT JOIN departments d ON e.department_id = d.department_id " +
            "WHERE e.is_deleted = 0 AND e.joining_date IS NOT NULL "
        );

        if (plan.departmentName != null) sql.append("AND LOWER(d.department_name) = LOWER(?) ");
        if (plan.joinedAfter    != null) sql.append("AND e.joining_date >= ? ");
        if (plan.joinedBefore   != null) sql.append("AND e.joining_date <= ? ");
        sql.append("ORDER BY e.joining_date DESC LIMIT 100");

        List<Map<String, String>> records = new ArrayList<>();
        try (Connection conn = DBConnection.getConnection();
             PreparedStatement ps = conn.prepareStatement(sql.toString())) {

            int idx = 1;
            if (plan.departmentName != null) ps.setString(idx++, plan.departmentName);
            if (plan.joinedAfter    != null) ps.setDate(idx++, java.sql.Date.valueOf(plan.joinedAfter));
            if (plan.joinedBefore   != null) ps.setDate(idx++, java.sql.Date.valueOf(plan.joinedBefore));

            try (ResultSet rs = ps.executeQuery()) {
                while (rs.next()) {
                    Map<String, String> row = new HashMap<>();
                    row.put("employee_code",   rs.getString("employee_code"));
                    row.put("full_name",       rs.getString("full_name"));
                    row.put("designation",     rs.getString("designation"));
                    row.put("department_name", rs.getString("department_name"));
                    row.put("joining_date",    rs.getString("joining_date"));
                    records.add(row);
                }
            }
        } catch (Exception e) {
            LOGGER.log(Level.SEVERE, "Error in getEmployeesByJoiningDate", e);
            result.put("error", "Sorry, error retrieving employees by joining date.");
            return result;
        }

        result.put("records", records);
        debugLog("getEmployeesByJoiningDate", result);
        return result;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // ALLOCATION SEARCH
    // ─────────────────────────────────────────────────────────────────────────

    public static Map<String, Object> searchAllocations(CopilotQueryPlan plan, HttpSession session) {
        Map<String, Object> result = new HashMap<>();
        String role    = sessionRole(session);
        String empCode = sessionAttr(session, "empCode");

        StringBuilder sql = new StringBuilder(
            "SELECT aa.allocation_id, a.asset_code, a.asset_name, c.category_name, " +
            "e.employee_code, e.employee_name AS full_name, d.department_name, aa.allocation_date " +
            "FROM asset_allocation aa " +
            "JOIN assets a ON aa.asset_id = a.asset_id " +
            "JOIN employees e ON aa.employee_id = e.employee_id " +
            "LEFT JOIN departments d ON e.department_id = d.department_id " +
            "LEFT JOIN asset_categories c ON a.category_id = c.category_id " +
            "WHERE aa.allocation_status = 'ALLOCATED' "
        );

        if (plan.normalizedCategory != null) sql.append("AND LOWER(c.category_name) = LOWER(?) ");
        if (plan.departmentName     != null) sql.append("AND LOWER(d.department_name) = LOWER(?) ");
        if (plan.assetCode          != null) sql.append("AND a.asset_code = ? ");
        if (plan.employeeCode       != null) sql.append("AND e.employee_code = ? ");
        if (plan.employeeName       != null) sql.append("AND LOWER(e.employee_name) LIKE LOWER(?) ");
        if ("EMPLOYEE".equalsIgnoreCase(role) && !isBlank(empCode)) {
            sql.append("AND e.employee_code = ? ");
        }
        sql.append("ORDER BY aa.allocation_date DESC LIMIT 50");

        List<Map<String, String>> records = new ArrayList<>();
        try (Connection conn = DBConnection.getConnection();
             PreparedStatement ps = conn.prepareStatement(sql.toString())) {

            int idx = 1;
            if (plan.normalizedCategory != null) ps.setString(idx++, plan.normalizedCategory);
            if (plan.departmentName     != null) ps.setString(idx++, plan.departmentName);
            if (plan.assetCode          != null) ps.setString(idx++, plan.assetCode);
            if (plan.employeeCode       != null) ps.setString(idx++, plan.employeeCode);
            if (plan.employeeName       != null) ps.setString(idx++, "%" + plan.employeeName + "%");
            if ("EMPLOYEE".equalsIgnoreCase(role) && !isBlank(empCode)) ps.setString(idx++, empCode);

            try (ResultSet rs = ps.executeQuery()) {
                while (rs.next()) {
                    Map<String, String> row = new HashMap<>();
                    row.put("asset_code",      rs.getString("asset_code"));
                    row.put("asset_name",      rs.getString("asset_name"));
                    row.put("category_name",   rs.getString("category_name"));
                    row.put("employee_code",   rs.getString("employee_code"));
                    row.put("full_name",       rs.getString("full_name"));
                    row.put("department_name", rs.getString("department_name"));
                    row.put("allocation_date", rs.getString("allocation_date"));
                    records.add(row);
                }
            }
        } catch (Exception e) {
            LOGGER.log(Level.SEVERE, "Error in searchAllocations", e);
            result.put("error", "Sorry, error retrieving allocations.");
            return result;
        }

        result.put("records", records);
        debugLog("searchAllocations", result);
        return result;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // PHASE 2 DAO METHODS
    // ─────────────────────────────────────────────────────────────────────────

    // ── DAMAGED ASSETS ───────────────────────────────────────────────────────

    public static Map<String, Object> getDamagedAssets(CopilotQueryPlan plan, HttpSession session) {
        Map<String, Object> result = new HashMap<>();
        StringBuilder sql = new StringBuilder(
            "SELECT a.asset_code, a.asset_name, c.category_name, d.department_name, " +
            "a.asset_status " +
            "FROM assets a " +
            "LEFT JOIN asset_categories c ON a.category_id = c.category_id " +
            "LEFT JOIN departments d ON a.department_id = d.department_id " +
            "WHERE a.asset_status IN ('Damaged', 'Unserviceable', 'DAMAGED', 'UNSERVICEABLE') "
        );
        if (plan.normalizedCategory != null) sql.append("AND LOWER(c.category_name) = LOWER(?) ");
        if (plan.departmentName     != null) sql.append("AND LOWER(d.department_name) = LOWER(?) ");
        sql.append("ORDER BY a.asset_code LIMIT 100");

        List<Map<String, String>> records = new ArrayList<>();
        try (Connection conn = DBConnection.getConnection();
             PreparedStatement ps = conn.prepareStatement(sql.toString())) {
            int idx = 1;
            if (plan.normalizedCategory != null) ps.setString(idx++, plan.normalizedCategory);
            if (plan.departmentName     != null) ps.setString(idx++, plan.departmentName);
            try (ResultSet rs = ps.executeQuery()) {
                while (rs.next()) {
                    Map<String, String> row = new HashMap<>();
                    row.put("asset_code",      rs.getString("asset_code"));
                    row.put("asset_name",      rs.getString("asset_name"));
                    row.put("category_name",   rs.getString("category_name"));
                    row.put("department_name", rs.getString("department_name"));
                    row.put("asset_status",    rs.getString("asset_status"));
                    records.add(row);
                }
            }
        } catch (Exception e) {
            LOGGER.log(Level.SEVERE, "Error in getDamagedAssets", e);
            result.put("error", "Sorry, error retrieving damaged assets.");
            return result;
        }
        result.put("records", records);
        debugLog("getDamagedAssets", result);
        return result;
    }

    // ── APPROVED ASSET REQUESTS ───────────────────────────────────────────────

    public static Map<String, Object> getApprovedRequests(CopilotQueryPlan plan, HttpSession session) {
        Map<String, Object> result = new HashMap<>();
        String role    = sessionRole(session);
        String empCode = sessionAttr(session, "empCode");

        StringBuilder sql = new StringBuilder(
            "SELECT ar.request_id, e.employee_code, e.employee_name AS full_name, d.department_name, " +
            "c.category_name, ar.request_date, ar.request_status " +
            "FROM asset_requests ar " +
            "JOIN employees e ON ar.employee_id = e.employee_id " +
            "LEFT JOIN departments d ON e.department_id = d.department_id " +
            "LEFT JOIN asset_categories c ON ar.category_id = c.category_id " +
            "WHERE ar.request_status = 'APPROVED' "
        );
        if ("EMPLOYEE".equalsIgnoreCase(role) && !isBlank(empCode)) {
            sql.append("AND e.employee_code = ? ");
        }
        sql.append("ORDER BY ar.request_date DESC LIMIT 50");

        List<Map<String, String>> records = new ArrayList<>();
        try (Connection conn = DBConnection.getConnection();
             PreparedStatement ps = conn.prepareStatement(sql.toString())) {
            if ("EMPLOYEE".equalsIgnoreCase(role) && !isBlank(empCode)) {
                ps.setString(1, empCode);
            }
            try (ResultSet rs = ps.executeQuery()) {
                while (rs.next()) {
                    Map<String, String> row = new HashMap<>();
                    row.put("request_id",      rs.getString("request_id"));
                    row.put("employee_code",   rs.getString("employee_code"));
                    row.put("full_name",       rs.getString("full_name"));
                    row.put("department_name", rs.getString("department_name"));
                    row.put("category_name",   rs.getString("category_name"));
                    row.put("request_date",    rs.getString("request_date"));
                    row.put("request_status",  rs.getString("request_status"));
                    records.add(row);
                }
            }
        } catch (Exception e) {
            LOGGER.log(Level.SEVERE, "Error in getApprovedRequests", e);
            result.put("error", "Sorry, error retrieving approved requests.");
            return result;
        }
        result.put("records", records);
        debugLog("getApprovedRequests", result);
        return result;
    }

    // ── REJECTED ASSET REQUESTS ───────────────────────────────────────────────

    public static Map<String, Object> getRejectedRequests(CopilotQueryPlan plan, HttpSession session) {
        Map<String, Object> result = new HashMap<>();
        String role    = sessionRole(session);
        String empCode = sessionAttr(session, "empCode");

        StringBuilder sql = new StringBuilder(
            "SELECT ar.request_id, e.employee_code, e.employee_name AS full_name, d.department_name, " +
            "c.category_name, ar.request_date, ar.request_status " +
            "FROM asset_requests ar " +
            "JOIN employees e ON ar.employee_id = e.employee_id " +
            "LEFT JOIN departments d ON e.department_id = d.department_id " +
            "LEFT JOIN asset_categories c ON ar.category_id = c.category_id " +
            "WHERE ar.request_status IN ('REJECTED', 'DECLINED') "
        );
        if ("EMPLOYEE".equalsIgnoreCase(role) && !isBlank(empCode)) {
            sql.append("AND e.employee_code = ? ");
        }
        sql.append("ORDER BY ar.request_date DESC LIMIT 50");

        List<Map<String, String>> records = new ArrayList<>();
        try (Connection conn = DBConnection.getConnection();
             PreparedStatement ps = conn.prepareStatement(sql.toString())) {
            if ("EMPLOYEE".equalsIgnoreCase(role) && !isBlank(empCode)) {
                ps.setString(1, empCode);
            }
            try (ResultSet rs = ps.executeQuery()) {
                while (rs.next()) {
                    Map<String, String> row = new HashMap<>();
                    row.put("request_id",      rs.getString("request_id"));
                    row.put("employee_code",   rs.getString("employee_code"));
                    row.put("full_name",       rs.getString("full_name"));
                    row.put("department_name", rs.getString("department_name"));
                    row.put("category_name",   rs.getString("category_name"));
                    row.put("request_date",    rs.getString("request_date"));
                    row.put("request_status",  rs.getString("request_status"));
                    records.add(row);
                }
            }
        } catch (Exception e) {
            LOGGER.log(Level.SEVERE, "Error in getRejectedRequests", e);
            result.put("error", "Sorry, error retrieving rejected requests.");
            return result;
        }
        result.put("records", records);
        debugLog("getRejectedRequests", result);
        return result;
    }

    // ── RETURN RECORDS ────────────────────────────────────────────────────────

    public static Map<String, Object> getReturnRecords(CopilotQueryPlan plan, HttpSession session) {
        Map<String, Object> result = new HashMap<>();
        String role    = sessionRole(session);
        String empCode = sessionAttr(session, "empCode");

        StringBuilder sql = new StringBuilder(
            "SELECT ar.return_id, a.asset_code, a.asset_name, " +
            "COALESCE(e.employee_code, '') AS employee_code, " +
            "COALESCE(e.employee_name, '') AS full_name, " +
            "COALESCE(d.department_name, '') AS department_name, " +
            "ar.return_date, ar.return_condition " +
            "FROM asset_returns ar " +
            "LEFT JOIN assets a ON ar.asset_id = a.asset_id " +
            "LEFT JOIN employees e ON ar.employee_id = e.employee_id " +
            "LEFT JOIN departments d ON e.department_id = d.department_id " +
            "WHERE 1=1 "
        );
        if ("EMPLOYEE".equalsIgnoreCase(role) && !isBlank(empCode)) {
            sql.append("AND e.employee_code = ? ");
        }
        if (plan.assetCode != null) sql.append("AND a.asset_code = ? ");
        sql.append("ORDER BY ar.return_date DESC LIMIT 50");

        List<Map<String, String>> records = new ArrayList<>();
        try (Connection conn = DBConnection.getConnection();
             PreparedStatement ps = conn.prepareStatement(sql.toString())) {
            int idx = 1;
            if ("EMPLOYEE".equalsIgnoreCase(role) && !isBlank(empCode)) ps.setString(idx++, empCode);
            if (plan.assetCode != null) ps.setString(idx++, plan.assetCode);
            try (ResultSet rs = ps.executeQuery()) {
                while (rs.next()) {
                    Map<String, String> row = new HashMap<>();
                    row.put("return_id",       rs.getString("return_id"));
                    row.put("asset_code",      rs.getString("asset_code"));
                    row.put("asset_name",      rs.getString("asset_name"));
                    row.put("employee_code",   rs.getString("employee_code"));
                    row.put("full_name",       rs.getString("full_name"));
                    row.put("department_name", rs.getString("department_name"));
                    row.put("return_date",     rs.getString("return_date"));
                    row.put("return_condition",rs.getString("return_condition"));
                    records.add(row);
                }
            }
        } catch (Exception e) {
            LOGGER.log(Level.SEVERE, "Error in getReturnRecords", e);
            result.put("error", "Sorry, error retrieving return records.");
            return result;
        }
        result.put("records", records);
        debugLog("getReturnRecords", result);
        return result;
    }

    // ── PENDING RETURNS ───────────────────────────────────────────────────────
    // NOTE: asset_returns does not have a status column — "pending" means
    // assets that are allocated but have no matching return record yet.

    public static Map<String, Object> getPendingReturns(CopilotQueryPlan plan, HttpSession session) {
        Map<String, Object> result = new HashMap<>();
        String role    = sessionRole(session);
        String empCode = sessionAttr(session, "empCode");

        StringBuilder sql = new StringBuilder(
            "SELECT aa.allocation_id, a.asset_code, a.asset_name, c.category_name, " +
            "e.employee_code, e.employee_name AS full_name, d.department_name, aa.allocation_date " +
            "FROM asset_allocation aa " +
            "JOIN assets a ON aa.asset_id = a.asset_id " +
            "JOIN employees e ON aa.employee_id = e.employee_id " +
            "LEFT JOIN departments d ON e.department_id = d.department_id " +
            "LEFT JOIN asset_categories c ON a.category_id = c.category_id " +
            "WHERE aa.allocation_status = 'ALLOCATED' " +
            "AND NOT EXISTS (SELECT 1 FROM asset_returns r WHERE r.allocation_id = aa.allocation_id) "
        );
        if ("EMPLOYEE".equalsIgnoreCase(role) && !isBlank(empCode)) {
            sql.append("AND e.employee_code = ? ");
        }
        if (plan.departmentName != null) sql.append("AND LOWER(d.department_name) = LOWER(?) ");
        sql.append("ORDER BY aa.allocation_date ASC LIMIT 50");

        List<Map<String, String>> records = new ArrayList<>();
        try (Connection conn = DBConnection.getConnection();
             PreparedStatement ps = conn.prepareStatement(sql.toString())) {
            int idx = 1;
            if ("EMPLOYEE".equalsIgnoreCase(role) && !isBlank(empCode)) ps.setString(idx++, empCode);
            if (plan.departmentName != null) ps.setString(idx++, plan.departmentName);
            try (ResultSet rs = ps.executeQuery()) {
                while (rs.next()) {
                    Map<String, String> row = new HashMap<>();
                    row.put("asset_code",      rs.getString("asset_code"));
                    row.put("asset_name",      rs.getString("asset_name"));
                    row.put("category_name",   rs.getString("category_name"));
                    row.put("employee_code",   rs.getString("employee_code"));
                    row.put("full_name",       rs.getString("full_name"));
                    row.put("department_name", rs.getString("department_name"));
                    row.put("allocation_date", rs.getString("allocation_date"));
                    records.add(row);
                }
            }
        } catch (Exception e) {
            LOGGER.log(Level.SEVERE, "Error in getPendingReturns", e);
            result.put("error", "Sorry, error retrieving pending returns.");
            return result;
        }
        result.put("records", records);
        debugLog("getPendingReturns", result);
        return result;
    }

    // ── DEPARTMENT EMPLOYEES ──────────────────────────────────────────────────

    public static Map<String, Object> getDepartmentEmployees(CopilotQueryPlan plan, HttpSession session) {
        Map<String, Object> result = new HashMap<>();
        if (isBlank(plan.departmentName)) {
            result.put("error", "Please specify a department (e.g. IT Centre, Stores, Finance).");
            return result;
        }
        String sql =
            "SELECT e.employee_code, e.employee_name AS full_name, e.designation, e.email, e.status " +
            "FROM employees e " +
            "JOIN departments d ON e.department_id = d.department_id " +
            "WHERE LOWER(d.department_name) = LOWER(?) " +
            "ORDER BY e.employee_name LIMIT 100";

        List<Map<String, String>> records = new ArrayList<>();
        try (Connection conn = DBConnection.getConnection();
             PreparedStatement ps = conn.prepareStatement(sql)) {
            ps.setString(1, plan.departmentName);
            try (ResultSet rs = ps.executeQuery()) {
                while (rs.next()) {
                    Map<String, String> row = new HashMap<>();
                    row.put("employee_code", rs.getString("employee_code"));
                    row.put("full_name",     rs.getString("full_name"));
                    row.put("designation",   rs.getString("designation"));
                    row.put("email",         rs.getString("email"));
                    row.put("status",        rs.getString("status"));
                    records.add(row);
                }
            }
        } catch (Exception e) {
            LOGGER.log(Level.SEVERE, "Error in getDepartmentEmployees", e);
            result.put("error", "Sorry, error retrieving department employees.");
            return result;
        }
        result.put("records", records);
        result.put("department", plan.departmentName);
        debugLog("getDepartmentEmployees", result);
        return result;
    }

    // ── QR STATUS ─────────────────────────────────────────────────────────────

    public static Map<String, Object> getQrStatus(CopilotQueryPlan plan, HttpSession session) {
        Map<String, Object> result = new HashMap<>();
        StringBuilder sql = new StringBuilder(
            "SELECT a.asset_code, a.asset_name, c.category_name, d.department_name, " +
            "CASE WHEN pas.token_active = 1 THEN 'QR Active' ELSE 'No QR / Inactive' END AS qr_status, " +
            "pas.last_synced_at " +
            "FROM assets a " +
            "LEFT JOIN asset_categories c ON a.category_id = c.category_id " +
            "LEFT JOIN departments d ON a.department_id = d.department_id " +
            "LEFT JOIN public_asset_snapshot pas ON a.asset_id = pas.asset_id " +
            "WHERE 1=1 "
        );
        if (plan.normalizedCategory != null) sql.append("AND LOWER(c.category_name) = LOWER(?) ");
        if (plan.departmentName     != null) sql.append("AND LOWER(d.department_name) = LOWER(?) ");
        sql.append("ORDER BY a.asset_code LIMIT 100");

        List<Map<String, String>> records = new ArrayList<>();
        try (Connection conn = DBConnection.getConnection();
             PreparedStatement ps = conn.prepareStatement(sql.toString())) {
            int idx = 1;
            if (plan.normalizedCategory != null) ps.setString(idx++, plan.normalizedCategory);
            if (plan.departmentName     != null) ps.setString(idx++, plan.departmentName);
            try (ResultSet rs = ps.executeQuery()) {
                while (rs.next()) {
                    Map<String, String> row = new HashMap<>();
                    row.put("asset_code",      rs.getString("asset_code"));
                    row.put("asset_name",      rs.getString("asset_name"));
                    row.put("category_name",   rs.getString("category_name"));
                    row.put("department_name", rs.getString("department_name"));
                    row.put("qr_status",       rs.getString("qr_status"));
                    row.put("last_synced_at",  rs.getString("last_synced_at"));
                    records.add(row);
                }
            }
        } catch (Exception e) {
            LOGGER.log(Level.SEVERE, "Error in getQrStatus", e);
            result.put("error", "Sorry, error retrieving QR status. The QR module tables may not be fully initialized.");
            return result;
        }
        result.put("records", records);
        debugLog("getQrStatus", result);
        return result;
    }

    // ── QR SCAN LOGS ─────────────────────────────────────────────────────────

    public static Map<String, Object> getQrScanLogs(CopilotQueryPlan plan, HttpSession session) {
        Map<String, Object> result = new HashMap<>();
        String role = sessionRole(session);
        if (!isAdminOrAuditor(role)) {
            result.put("error", "🔒 **Access Denied**: Only ADMIN, SUPER_ADMIN, and AUDITOR roles can view QR scan logs.");
            return result;
        }

        String sql =
            "SELECT q.asset_id, a.asset_code, q.qr_public_token, q.operation_type, " +
            "q.status AS sync_status, q.attempted_at, q.error_message " +
            "FROM qr_sync_queue q " +
            "LEFT JOIN assets a ON q.asset_id = a.asset_id " +
            "ORDER BY q.attempted_at DESC LIMIT 50";

        List<Map<String, String>> records = new ArrayList<>();
        try (Connection conn = DBConnection.getConnection();
             PreparedStatement ps = conn.prepareStatement(sql);
             ResultSet rs = ps.executeQuery()) {
            while (rs.next()) {
                Map<String, String> row = new HashMap<>();
                row.put("asset_code",    rs.getString("asset_code"));
                row.put("token",         rs.getString("qr_public_token"));
                row.put("operation",     rs.getString("operation_type"));
                row.put("sync_status",   rs.getString("sync_status"));
                row.put("attempted_at",  rs.getString("attempted_at"));
                row.put("error_message", rs.getString("error_message"));
                records.add(row);
            }
        } catch (Exception e) {
            LOGGER.log(Level.SEVERE, "Error in getQrScanLogs", e);
            result.put("error", "Sorry, error retrieving QR scan logs. The qr_sync_queue table may not be initialized.");
            return result;
        }
        result.put("records", records);
        debugLog("getQrScanLogs", result);
        return result;
    }

    // ── AUDIT LOGS ────────────────────────────────────────────────────────────
    // ADMIN / SUPER_ADMIN / AUDITOR only

    public static Map<String, Object> getAuditLogs(CopilotQueryPlan plan, HttpSession session) {
        Map<String, Object> result = new HashMap<>();
        String role = sessionRole(session);
        if (!isAdminOrAuditor(role)) {
            result.put("error", "🔒 **Access Denied**: Only ADMIN, SUPER_ADMIN, and AUDITOR roles can view audit logs.");
            return result;
        }

        // Fault: audit_logs' real primary key is audit_id, not log_id - same
        // class of bug as the employees.full_name issue found earlier this
        // pass. Confirmed live: every audit-log tool call was throwing
        // "Unknown column 'al.log_id'". Aliased rather than renamed
        // downstream, same reasoning as that fix.
        StringBuilder sql = new StringBuilder(
            "SELECT al.audit_id AS log_id, al.username, al.user_role, al.module_name, " +
            "al.action_type, al.record_id, al.action_details, al.created_at " +
            "FROM audit_logs al " +
            "WHERE 1=1 "
        );
        if (plan.startDate != null) sql.append("AND DATE(al.created_at) >= ? ");
        if (plan.endDate   != null) sql.append("AND DATE(al.created_at) <= ? ");
        sql.append("ORDER BY al.created_at DESC LIMIT 100");

        List<Map<String, String>> records = new ArrayList<>();
        try (Connection conn = DBConnection.getConnection();
             PreparedStatement ps = conn.prepareStatement(sql.toString())) {
            int idx = 1;
            if (plan.startDate != null) ps.setString(idx++, plan.startDate.toString());
            if (plan.endDate   != null) ps.setString(idx++, plan.endDate.toString());
            try (ResultSet rs = ps.executeQuery()) {
                while (rs.next()) {
                    Map<String, String> row = new HashMap<>();
                    row.put("log_id",         rs.getString("log_id"));
                    row.put("username",        rs.getString("username"));
                    row.put("user_role",       rs.getString("user_role"));
                    row.put("module_name",     rs.getString("module_name"));
                    row.put("action_type",     rs.getString("action_type"));
                    row.put("record_id",       rs.getString("record_id"));
                    row.put("action_details",  rs.getString("action_details"));
                    row.put("created_at",      rs.getString("created_at"));
                    records.add(row);
                }
            }
        } catch (Exception e) {
            LOGGER.log(Level.SEVERE, "Error in getAuditLogs", e);
            result.put("error", "Sorry, error retrieving audit logs.");
            return result;
        }
        result.put("records", records);
        debugLog("getAuditLogs", result);
        return result;
    }

    // ── ROLE DUTY SUMMARY ─────────────────────────────────────────────────────
    // ADMIN / SUPER_ADMIN only

    public static Map<String, Object> getRoleDutySummary(CopilotQueryPlan plan, HttpSession session) {
        Map<String, Object> result = new HashMap<>();
        String role = sessionRole(session);
        if (!isAdmin(role)) {
            result.put("error", "🔒 **Access Denied**: Only ADMIN and SUPER_ADMIN roles can view role/duty summary.");
            return result;
        }

        // Fault: employee_role_assignments has neither role_name nor
        // assigned_date - the real columns are role_code and effective_from.
        // Same class of bug found repeatedly this pass. Aliased rather than
        // renamed downstream.
        String sql =
            "SELECT e.employee_code, e.employee_name AS full_name, d.department_name, " +
            "era.role_code AS role_name, era.effective_from AS assigned_date " +
            "FROM employee_role_assignments era " +
            "JOIN employees e ON era.employee_id = e.employee_id " +
            "LEFT JOIN departments d ON e.department_id = d.department_id " +
            "ORDER BY era.role_code, e.employee_code LIMIT 100";

        List<Map<String, String>> records = new ArrayList<>();
        try (Connection conn = DBConnection.getConnection();
             PreparedStatement ps = conn.prepareStatement(sql);
             ResultSet rs = ps.executeQuery()) {
            while (rs.next()) {
                Map<String, String> row = new HashMap<>();
                row.put("employee_code",   rs.getString("employee_code"));
                row.put("full_name",       rs.getString("full_name"));
                row.put("department_name", rs.getString("department_name"));
                row.put("role_name",       rs.getString("role_name"));
                row.put("assigned_date",   rs.getString("assigned_date"));
                records.add(row);
            }
        } catch (Exception e) {
            LOGGER.log(Level.SEVERE, "Error in getRoleDutySummary", e);
            result.put("error", "Sorry, error retrieving role/duty summary.");
            return result;
        }
        result.put("records", records);
        debugLog("getRoleDutySummary", result);
        return result;
    }

    // ── PHYSICAL VERIFICATION SUMMARY ────────────────────────────────────────

    public static Map<String, Object> getPhysicalVerificationSummary(CopilotQueryPlan plan, HttpSession session) {
        Map<String, Object> result = new HashMap<>();
        // First check if the table exists — it may not be initialized on all DBs
        boolean tableExists = false;
        try (Connection conn = DBConnection.getConnection();
             PreparedStatement ps = conn.prepareStatement(
                 "SELECT COUNT(*) FROM information_schema.tables " +
                 "WHERE table_schema = DATABASE() AND table_name = 'asset_physical_verification'");
             ResultSet rs = ps.executeQuery()) {
            if (rs.next()) tableExists = rs.getInt(1) > 0;
        } catch (Exception ignored) {}

        if (!tableExists) {
            result.put("error",
                "Physical Verification data is not available in the current database setup. " +
                "The `asset_physical_verification` table does not exist. " +
                "Please set up the Physical Verification module first.");
            return result;
        }

        // Table exists — query summary
        String sql =
            "SELECT apv.verified_status, COUNT(*) AS count " +
            "FROM asset_physical_verification apv " +
            "GROUP BY apv.verified_status " +
            "ORDER BY count DESC";

        List<Map<String, String>> records = new ArrayList<>();
        try (Connection conn = DBConnection.getConnection();
             PreparedStatement ps = conn.prepareStatement(sql);
             ResultSet rs = ps.executeQuery()) {
            while (rs.next()) {
                Map<String, String> row = new HashMap<>();
                row.put("verified_status", rs.getString("verified_status"));
                row.put("count",           rs.getString("count"));
                records.add(row);
            }
        } catch (Exception e) {
            LOGGER.log(Level.SEVERE, "Error in getPhysicalVerificationSummary", e);
            result.put("error", "Sorry, error retrieving physical verification summary.");
            return result;
        }
        result.put("records", records);
        debugLog("getPhysicalVerificationSummary", result);
        return result;
    }

    // ── CATEGORY VENDOR MAPPING ───────────────────────────────────────────────

    public static Map<String, Object> getCategoryVendorMapping(CopilotQueryPlan plan, HttpSession session) {
        Map<String, Object> result = new HashMap<>();
        // Check if category_vendor_mapping table exists
        boolean tableExists = false;
        try (Connection conn = DBConnection.getConnection();
             PreparedStatement ps = conn.prepareStatement(
                 "SELECT COUNT(*) FROM information_schema.tables " +
                 "WHERE table_schema = DATABASE() AND table_name = 'category_vendor_mapping'");
             ResultSet rs = ps.executeQuery()) {
            if (rs.next()) tableExists = rs.getInt(1) > 0;
        } catch (Exception ignored) {}

        String sql;
        List<Map<String, String>> records = new ArrayList<>();

        if (tableExists) {
            sql = "SELECT c.category_name, v.vendor_name, cvm.is_preferred " +
                  "FROM category_vendor_mapping cvm " +
                  "JOIN asset_categories c ON cvm.category_id = c.category_id " +
                  "JOIN vendors v ON cvm.vendor_id = v.vendor_id " +
                  "ORDER BY c.category_name, cvm.is_preferred DESC LIMIT 100";
        } else {
            // Fallback: derive from actual assets table
            sql = "SELECT c.category_name, v.vendor_name, COUNT(a.asset_id) AS asset_count " +
                  "FROM assets a " +
                  "JOIN asset_categories c ON a.category_id = c.category_id " +
                  "LEFT JOIN vendors v ON a.vendor_id = v.vendor_id " +
                  "WHERE v.vendor_name IS NOT NULL " +
                  "GROUP BY c.category_name, v.vendor_name " +
                  "ORDER BY c.category_name, asset_count DESC LIMIT 100";
        }

        try (Connection conn = DBConnection.getConnection();
             PreparedStatement ps = conn.prepareStatement(sql);
             ResultSet rs = ps.executeQuery()) {
            while (rs.next()) {
                Map<String, String> row = new HashMap<>();
                row.put("category_name", rs.getString("category_name"));
                row.put("vendor_name",   rs.getString("vendor_name"));
                if (tableExists) {
                    row.put("is_preferred", rs.getString("is_preferred"));
                } else {
                    row.put("asset_count", rs.getString("asset_count"));
                }
                records.add(row);
            }
        } catch (Exception e) {
            LOGGER.log(Level.SEVERE, "Error in getCategoryVendorMapping", e);
            result.put("error", "Sorry, error retrieving category-vendor mapping.");
            return result;
        }
        result.put("records", records);
        result.put("source", tableExists ? "category_vendor_mapping" : "assets_derived");
        debugLog("getCategoryVendorMapping", result);
        return result;
    }

    // ── ASSET VALUE SUMMARY ───────────────────────────────────────────────────

    public static Map<String, Object> getAssetValueSummary(CopilotQueryPlan plan, HttpSession session) {
        Map<String, Object> result = new HashMap<>();
        // Group by category AND department together for rich summary
        String sql =
            "SELECT c.category_name, d.department_name, " +
            "COUNT(a.asset_id) AS asset_count, " +
            "COALESCE(SUM(a.purchase_cost), 0) AS total_value, " +
            "COALESCE(AVG(a.purchase_cost), 0) AS avg_value " +
            "FROM assets a " +
            "LEFT JOIN asset_categories c ON a.category_id = c.category_id " +
            "LEFT JOIN departments d ON a.department_id = d.department_id " +
            "GROUP BY c.category_name, d.department_name " +
            "ORDER BY total_value DESC LIMIT 100";

        List<Map<String, String>> records = new ArrayList<>();
        try (Connection conn = DBConnection.getConnection();
             PreparedStatement ps = conn.prepareStatement(sql);
             ResultSet rs = ps.executeQuery()) {
            while (rs.next()) {
                Map<String, String> row = new HashMap<>();
                row.put("category_name",   rs.getString("category_name"));
                row.put("department_name", rs.getString("department_name"));
                row.put("asset_count",     rs.getString("asset_count"));
                row.put("total_value",     rs.getString("total_value"));
                row.put("avg_value",       rs.getString("avg_value"));
                records.add(row);
            }
        } catch (Exception e) {
            LOGGER.log(Level.SEVERE, "Error in getAssetValueSummary", e);
            result.put("error", "Sorry, error retrieving asset value summary.");
            return result;
        }
        result.put("records", records);
        debugLog("getAssetValueSummary", result);
        return result;
    }

    // ── SETTINGS SUMMARY (ADMIN / SUPER_ADMIN only) ───────────────────────────
    // NEVER shows: API keys, passwords, tokens, SMTP credentials.

    public static Map<String, Object> getSettingsSummary(CopilotQueryPlan plan, HttpSession session) {
        Map<String, Object> result = new HashMap<>();
        String role = sessionRole(session);
        if (!isAdmin(role)) {
            result.put("error", "🔒 **Access Denied**: Only ADMIN and SUPER_ADMIN roles can view system settings.");
            return result;
        }

        // Check if system_settings table exists
        boolean tableExists = false;
        try (Connection conn = DBConnection.getConnection();
             PreparedStatement ps = conn.prepareStatement(
                 "SELECT COUNT(*) FROM information_schema.tables " +
                 "WHERE table_schema = DATABASE() AND table_name = 'system_settings'");
             ResultSet rs = ps.executeQuery()) {
            if (rs.next()) tableExists = rs.getInt(1) > 0;
        } catch (Exception ignored) {}

        if (!tableExists) {
            result.put("error", "System settings table not found in the current database.");
            return result;
        }

        // SAFE settings keys only — never expose secret keys
        String sql =
            "SELECT setting_key, setting_value " +
            "FROM system_settings " +
            "WHERE setting_key NOT IN (" +
            " 'gemini_api_key', 'openai_api_key', 'smtp_password', 'smtp_username', " +
            " 'ngrok_token', 'cloudflare_token', 'qr_secret', 'jwt_secret', " +
            " 'api_key', 'secret_key', 'access_token', 'refresh_token'" +
            ") ORDER BY setting_key";

        List<Map<String, String>> records = new ArrayList<>();
        try (Connection conn = DBConnection.getConnection();
             PreparedStatement ps = conn.prepareStatement(sql);
             ResultSet rs = ps.executeQuery()) {
            while (rs.next()) {
                Map<String, String> row = new HashMap<>();
                row.put("setting_key",   rs.getString("setting_key"));
                row.put("setting_value", rs.getString("setting_value"));
                records.add(row);
            }
        } catch (Exception e) {
            LOGGER.log(Level.SEVERE, "Error in getSettingsSummary", e);
            result.put("error", "Sorry, error retrieving system settings.");
            return result;
        }
        result.put("records", records);
        result.put("note", "API keys, passwords, and tokens are never shown for security.");
        debugLog("getSettingsSummary", result);
        return result;
    }

    // ── COPILOT FEEDBACK SUMMARY (ADMIN / SUPER_ADMIN only) ───────────────────
    // Closes the loop on CopilotFeedbackDAO/CopilotFeedbackServlet's
    // thumbs-up/down capture: without this, every recorded rating sat in
    // copilot_answer_feedback with nothing ever reading it back. Restricted
    // the same as getRoleDutySummary/getSettingsSummary - this is
    // operational data about the Copilot itself, not AMS asset data.

    public static Map<String, Object> getCopilotFeedbackSummary(CopilotQueryPlan plan, HttpSession session) {
        Map<String, Object> result = new HashMap<>();
        String role = sessionRole(session);
        if (!isAdmin(role)) {
            result.put("error", "🔒 **Access Denied**: Only ADMIN and SUPER_ADMIN roles can view Copilot feedback.");
            return result;
        }

        int days = (plan.days != null && plan.days > 0) ? plan.days : 30;

        int upCount = 0;
        int downCount = 0;
        List<Map<String, String>> recentDown = new ArrayList<>();

        try (Connection conn = DBConnection.getConnection()) {
            try (PreparedStatement ps = conn.prepareStatement(
                    "SELECT rating, COUNT(*) AS cnt FROM copilot_answer_feedback " +
                    "WHERE created_at >= DATE_SUB(NOW(), INTERVAL ? DAY) GROUP BY rating")) {
                ps.setInt(1, days);
                try (ResultSet rs = ps.executeQuery()) {
                    while (rs.next()) {
                        if ("UP".equals(rs.getString("rating"))) upCount = rs.getInt("cnt");
                        else if ("DOWN".equals(rs.getString("rating"))) downCount = rs.getInt("cnt");
                    }
                }
            }

            // The actionable part: WHAT went wrong, not just how often -
            // an admin cannot fix a bad answer pattern from a bare count alone.
            try (PreparedStatement ps = conn.prepareStatement(
                    "SELECT question, answer, created_at FROM copilot_answer_feedback " +
                    "WHERE rating = 'DOWN' AND created_at >= DATE_SUB(NOW(), INTERVAL ? DAY) " +
                    "ORDER BY feedback_id DESC LIMIT 10")) {
                ps.setInt(1, days);
                try (ResultSet rs = ps.executeQuery()) {
                    while (rs.next()) {
                        Map<String, String> row = new HashMap<>();
                        row.put("question", rs.getString("question"));
                        row.put("answer", truncate(rs.getString("answer"), 300));
                        row.put("created_at", rs.getString("created_at"));
                        recentDown.add(row);
                    }
                }
            }
        } catch (Exception e) {
            LOGGER.log(Level.SEVERE, "Error in getCopilotFeedbackSummary", e);
            result.put("error", "Sorry, error retrieving Copilot feedback.");
            return result;
        }

        int total = upCount + downCount;
        String satisfactionRate = total == 0 ? "n/a"
                : String.format("%.1f%%", (upCount * 100.0) / total);

        result.put("period_days", days);
        result.put("up_count", upCount);
        result.put("down_count", downCount);
        result.put("total_rated", total);
        result.put("satisfaction_rate", satisfactionRate);
        result.put("recent_downvoted", recentDown);
        debugLog("getCopilotFeedbackSummary", result);
        return result;
    }

    /** Guards a field embedded in a JSON-ish tool result from bloating the model's context on one long answer. */
    private static String truncate(String value, int maxChars) {
        if (value == null) return "";
        return value.length() <= maxChars ? value : value.substring(0, maxChars) + "...";
    }

    // ── PROJECT KNOWLEDGE (how IR-AMS works, not a data lookup) ─────────────────
    // Available to every role - explaining how the system works is not
    // sensitive the way live records are, and every role needs to be able to
    // ask "how does this work" about their own corner of the app.

    public static Map<String, Object> getProjectKnowledge(CopilotQueryPlan plan, HttpSession session) {
        Map<String, Object> result = new HashMap<>();
        String query = plan.knowledgeQuery;
        if (query == null || query.trim().isEmpty()) {
            result.put("error", "No topic given to look up.");
            return result;
        }

        List<CopilotKnowledgeBase.Topic> matches = CopilotKnowledgeBase.search(query);
        if (matches.isEmpty()) {
            result.put("found", false);
            result.put("note", "No IR-AMS documentation matched '" + query + "'. Say plainly that this "
                    + "isn't something you have documented, rather than guessing at how it might work.");
            return result;
        }

        List<Map<String, String>> topics = new ArrayList<>();
        for (CopilotKnowledgeBase.Topic topic : matches) {
            Map<String, String> row = new HashMap<>();
            row.put("title", topic.title);
            row.put("content", topic.content);
            topics.add(row);
        }
        result.put("found", true);
        result.put("topics", topics);
        debugLog("getProjectKnowledge", result);
        return result;
    }

    // ── MAINTENANCE COST OUTLIERS (insight, not a lookup) ──────────────────────
    // Every other tool in this class answers "what/how many/who" from a direct
    // filter. This one REASONS over the data: an asset's total maintenance
    // spend only means something next to its category's average - the same
    // comparison a human analyst would make before flagging it, not a value
    // any single WHERE clause can express. Same role group as get_qr_scan_logs
    // (ASSET_OPS_AND_AUDIT in the catalog) - operational insight for the roles
    // that actually act on maintenance spend, plus audit visibility.

    public static Map<String, Object> getMaintenanceCostOutliers(CopilotQueryPlan plan, HttpSession session) {
        Map<String, Object> result = new HashMap<>();
        String role = sessionRole(session);
        if (!isAssetOpsOrAudit(role)) {
            result.put("error", "🔒 **Access Denied**: This insight is available to Asset Manager, Admin, "
                    + "Super Admin, and Auditor roles.");
            return result;
        }

        // "Outlier" needs a threshold to mean anything - default 1.5x a
        // category's average total-maintenance-spend-per-asset, overridable
        // via plan.days being reused as a tenths-of-a-multiplier (e.g. 20 ->
        // 2.0x) would overload an unrelated field's meaning, so this reads
        // its own plan field instead: costMultiplierThreshold, populated the
        // same way other numeric tool args are (see CopilotToolCatalog.toPlan()
        // - a "threshold" param parsed defensively, never throwing on a
        // non-numeric model answer).
        double multiplier = (plan.costMultiplierThreshold != null && plan.costMultiplierThreshold > 1.0)
                ? plan.costMultiplierThreshold : 1.5;

        List<Map<String, String>> outliers;
        try {
            outliers = queryMaintenanceCostOutliers(multiplier);
        } catch (Exception e) {
            LOGGER.log(Level.SEVERE, "Error in getMaintenanceCostOutliers", e);
            result.put("error", "Sorry, error computing maintenance cost outliers.");
            return result;
        }

        result.put("threshold_multiplier", multiplier);
        result.put("outliers", outliers);
        if (outliers.isEmpty()) {
            result.put("note", "No asset's total maintenance cost exceeds " + multiplier
                    + "x its category's average - nothing stands out as disproportionately expensive to maintain.");
        }
        debugLog("getMaintenanceCostOutliers", result);
        return result;
    }

    /**
     * The actual outlier query, split out from getMaintenanceCostOutliers()
     * so CopilotDigestScheduler can surface the same insight PROACTIVELY in
     * the daily digest, not only when a user with the right role happens to
     * ask - a scheduled job has no HttpSession/role to gate on in the first
     * place, and re-deriving this query a second time would let the two
     * silently drift apart. Throws on failure (unlike the tool wrapper,
     * which turns that into a chat-friendly error) so each caller decides
     * how to present a query failure to its own audience.
     *
     * Repeats the per-asset SUM(cost) subquery twice (once as the row set
     * itself, once again to compute each category's average over that same
     * row set) rather than a CTE - this codebase's other ~35 tool queries
     * are all plain SELECT/JOIN with no CTEs, and at this data volume
     * (assets, not transactions) the duplicate aggregation costs nothing
     * worth optimising away at the expense of a MySQL-8-only WITH clause
     * this project has never otherwise relied on.
     */
    static List<Map<String, String>> queryMaintenanceCostOutliers(double multiplier) throws Exception {
        String sql =
            "SELECT ac.asset_code, ac.asset_name, ac.category_name, ac.total_cost, avgc.avg_cost, " +
            "(ac.total_cost / avgc.avg_cost) AS cost_ratio " +
            "FROM ( " +
            "    SELECT a.asset_id, a.asset_code, a.asset_name, a.category_id, cat.category_name, " +
            "           COALESCE(SUM(ml.cost), 0) AS total_cost " +
            "    FROM assets a " +
            "    JOIN asset_categories cat ON a.category_id = cat.category_id " +
            "    LEFT JOIN maintenance_logs ml ON ml.asset_id = a.asset_id " +
            "    GROUP BY a.asset_id, a.asset_code, a.asset_name, a.category_id, cat.category_name " +
            ") ac " +
            "JOIN ( " +
            "    SELECT x.category_id, AVG(x.total_cost) AS avg_cost " +
            "    FROM ( " +
            "        SELECT a.asset_id, a.category_id, COALESCE(SUM(ml.cost), 0) AS total_cost " +
            "        FROM assets a " +
            "        LEFT JOIN maintenance_logs ml ON ml.asset_id = a.asset_id " +
            "        GROUP BY a.asset_id, a.category_id " +
            "    ) x " +
            "    GROUP BY x.category_id " +
            ") avgc ON ac.category_id = avgc.category_id " +
            "WHERE avgc.avg_cost > 0 AND ac.total_cost > avgc.avg_cost * ? " +
            "ORDER BY cost_ratio DESC " +
            "LIMIT 20";

        List<Map<String, String>> outliers = new ArrayList<>();
        try (Connection conn = DBConnection.getConnection();
             PreparedStatement ps = conn.prepareStatement(sql)) {
            ps.setDouble(1, multiplier);
            try (ResultSet rs = ps.executeQuery()) {
                while (rs.next()) {
                    Map<String, String> row = new HashMap<>();
                    row.put("asset_code", rs.getString("asset_code"));
                    row.put("asset_name", rs.getString("asset_name"));
                    row.put("category_name", rs.getString("category_name"));
                    row.put("total_maintenance_cost", rs.getString("total_cost"));
                    row.put("category_average_cost", rs.getString("avg_cost"));
                    row.put("times_above_average", String.format("%.1fx", rs.getDouble("cost_ratio")));
                    outliers.add(row);
                }
            }
        }
        return outliers;
    }

    private static boolean isAssetOpsOrAudit(String role) {
        return "ASSET_MANAGER".equalsIgnoreCase(role)
            || "ADMIN".equalsIgnoreCase(role)
            || "SUPER_ADMIN".equalsIgnoreCase(role)
            || "AUDITOR".equalsIgnoreCase(role);
    }

    // ── Access control helpers ────────────────────────────────────────────────

    private static boolean isAdmin(String role) {
        return "ADMIN".equalsIgnoreCase(role) || "SUPER_ADMIN".equalsIgnoreCase(role);
    }

    private static boolean isAdminOrAuditor(String role) {
        return "ADMIN".equalsIgnoreCase(role)
            || "SUPER_ADMIN".equalsIgnoreCase(role)
            || "AUDITOR".equalsIgnoreCase(role);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // PRIVATE UTILITIES
    // ─────────────────────────────────────────────────────────────────────────


    private static String sessionAttr(HttpSession session, String key) {
        if (session == null) return null;
        try {
            Object v = session.getAttribute(key);
            return v == null ? null : String.valueOf(v);
        } catch (IllegalStateException alreadyInvalidated) {
            // Same fault as CopilotReasoningPlanner/CopilotSessionMemory: a
            // dead session throws here instead of returning null.
            return null;
        }
    }

    /**
     * Role lookup used ONLY for the row-scoping check every method in this
     * file does ("EMPLOYEE".equalsIgnoreCase(role) -> restrict to the
     * caller's own records). Deliberately NOT sessionAttr(session, "role"):
     * that returns null when the role can't be read (no session, or a
     * session invalidated mid-request), and every one of the ~24 scoping
     * checks below treats null as "not an employee" - i.e. UNRESTRICTED.
     * A dead session would then silently fail OPEN, handing an employee
     * caller org-wide data instead of just their own, which is a real
     * security regression (found while hardening this file's session-
     * invalidation handling), not a hypothetical one.
     *
     * Fails CLOSED instead: an unreadable role resolves to "EMPLOYEE", the
     * most restrictive real role checked here, so an indeterminate session
     * scopes down to (at most) the caller's own rows or a denial - the same
     * shape of outcome CopilotToolCatalog's own role gate already prefers
     * (default-deny for anything it can't positively verify).
     */
    private static String sessionRole(HttpSession session) {
        String role = sessionAttr(session, "role");
        return role == null ? "EMPLOYEE" : role;
    }

    private static boolean isBlank(String s) {
        return s == null || s.trim().isEmpty();
    }

    /** Shallow clone of plan for intent-override methods */
    private static CopilotQueryPlan clonePlan(CopilotQueryPlan src) {
        CopilotQueryPlan c = new CopilotQueryPlan();
        c.rawUserMessage       = src.rawUserMessage;
        c.normalizedTextForNLU = src.normalizedTextForNLU;
        c.intent               = src.intent;
        c.normalizedCategory   = src.normalizedCategory;
        c.rawCategory          = src.rawCategory;
        c.departmentName       = src.departmentName;
        c.assetCode            = src.assetCode;
        c.employeeCode         = src.employeeCode;
        c.employeeName         = src.employeeName;
        c.status               = src.status;
        c.days                 = src.days;
        c.startDate            = src.startDate;
        c.endDate              = src.endDate;
        c.dateRangeRaw         = src.dateRangeRaw;
        c.needsDatabase        = src.needsDatabase;
        return c;
    }

    @SuppressWarnings("unchecked")
    private static void debugLog(String method, Map<String, Object> result) {
        if (!DEBUG) return;
        int rows = 0;
        if (result.containsKey("records")) {
            Object r = result.get("records");
            if (r instanceof List) rows = ((List<?>) r).size();
        }
        System.out.println("[COPILOT-DEBUG] DAO: " + method + "() → " + rows + " rows");
    }
}
