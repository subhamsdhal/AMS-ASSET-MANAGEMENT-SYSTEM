package com.mycompany.asset_management_system_ams;

/**
 * CopilotIntentType — Canonical enum for all AMS Copilot intents.
 *
 * IMPORTANT: Do not rename existing values — they are referenced by name in
 * session attributes, CopilotEngine, CopilotToolExecutor, and formatters.
 * New intents added at bottom of each logical group.
 */
public enum CopilotIntentType {

    // Asset Queries
    ASSET_SEARCH,           // List/filter assets by category, dept, status, code
    ASSET_TOTAL_COST,       // Sum of purchase_cost (all or filtered by category/dept)
    ASSET_COUNT,            // Count of assets matching filters
    ASSET_HOLDER,           // Who currently holds a specific asset
    AVAILABLE_ASSETS,       // Assets with status = Available
    ALLOCATED_ASSETS,       // Assets with status = Allocated
    DISPOSED_ASSETS,        // Assets with status = Disposed / Condemned

    // Employee Queries
    EMPLOYEE_SEARCH,        // Search employees by code/name/dept
    EMPLOYEE_DETAILS,       // Full profile of a specific employee
    EMPLOYEE_ALLOCATIONS,   // All assets assigned to a given employee

    // Department / Category / Supplier Summaries
    DEPARTMENT_SEARCH,      // Search/filter by department
    DEPT_SUMMARY,           // Group-by department: count + total cost
    CATEGORY_SUMMARY,       // Group-by category: count + total cost
    SUPPLIER_SUMMARY,       // Vendor/supplier summary

    // Allocation / Return
    ALLOCATION_SEARCH,      // Current active allocations
    RETURN_SEARCH,          // Return records (legacy alias)
    PENDING_ASSET_REQUESTS, // Asset requests with status = PENDING

    // Maintenance
    MAINTENANCE_PENDING,    // Assets currently under maintenance / pending
    MAINTENANCE_HISTORY,    // Maintenance log for a specific asset

    // Warranty
    WARRANTY_EXPIRING_NEXT_N_DAYS,  // Warranty expiring in next N days (future only)
    WARRANTY_EXPIRED,               // Already-expired warranties
    WARRANTY_THIS_MONTH,            // Expiring in current calendar month

    // Dashboard / Overview
    DASHBOARD_SUMMARY,      // High-level KPI counts

    // Export / Navigation
    EXPORT_CURRENT_RESULT,  // Export last query result to Excel
    EXPORT_REPORT,          // Named report export
    HELP_NAVIGATION,        // "help" / "how do I..." / "what can you do?"

    // Write Commands (handled by CopilotCommandDetector)
    CREATE_EMPLOYEE,
    UPDATE_EMPLOYEE,
    DISABLE_EMPLOYEE,
    DELETE_EMPLOYEE,
    CREATE_ASSET,
    UPDATE_ASSET,
    DELETE_ASSET,
    ALLOCATE_ASSET,
    RETURN_ASSET,
    CREATE_MAINTENANCE_REQUEST,
    UPDATE_MAINTENANCE_STATUS,
    APPROVE_ASSET_REQUEST,
    REJECT_ASSET_REQUEST,
    CREATE_DEPARTMENT,
    UPDATE_DEPARTMENT,
    CREATE_CATEGORY,
    UPDATE_CATEGORY,
    CREATE_SUPPLIER,
    UPDATE_SUPPLIER,
    VIEW_RECORD,

    // Phase 2: Extended Asset Queries
    DAMAGED_ASSETS,              // Assets with status = Damaged / Unserviceable
    ASSET_BY_STATUS,             // Generic status filter
    ASSET_VALUE_SUMMARY,         // SUM+AVG grouped by category and/or department

    // Phase 2: Asset Requests
    APPROVED_ASSET_REQUESTS,     // asset_requests WHERE status = APPROVED
    REJECTED_ASSET_REQUESTS,     // asset_requests WHERE status = REJECTED

    // Phase 2: Returns
    RETURN_RECORDS,              // All return records (with optional filters)
    PENDING_RETURNS,             // Returns not yet completed

    // Phase 2: Employee / Department
    DEPARTMENT_EMPLOYEES,        // Employees belonging to a given department

    // Phase 2: QR
    QR_STATUS,                   // QR tagging status of assets
    QR_SCAN_LOGS,                // QR sync/scan queue logs

    // Phase 2: Audit
    AUDIT_SEARCH,                // audit_logs (ADMIN / SUPER_ADMIN / AUDITOR only)

    // Phase 2: Role / Settings
    ROLE_DUTY_SUMMARY,           // employee_role_assignments summary
    SETTINGS_SUMMARY,            // System settings safe summary

    // Phase 2: Physical Verification
    PHYSICAL_VERIFICATION_SUMMARY, // asset_physical_verification summary

    // Phase 2: Category-Vendor Mapping
    CATEGORY_VENDOR_MAPPING,     // category_vendor_mapping join with vendor names

    // Fallback
    UNKNOWN
}
