package com.mycompany.asset_management_system_ams;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * CopilotProjectModuleRegistry
 *
 * Central lookup table describing every IR-AMS module:
 *   - moduleName
 *   - related DB tables
 *   - trigger phrases (used by intent detector fallback)
 *   - supported read intents
 *   - DAO tool method names
 *   - required role(s) for sensitive operations (null = any authenticated role)
 *   - capability text shown when user asks "what can you do in [module]?"
 *
 * Never generates SQL. Never calls the DB. Read-only metadata only.
 */
public class CopilotProjectModuleRegistry {

    // ── Module descriptor ─────────────────────────────────────────────────────

    public static class ModuleDescriptor {
        public final String moduleName;
        public final List<String> relatedTables;
        public final List<String> triggerPhrases;
        public final List<CopilotIntentType> supportedReadIntents;
        public final List<String> toolMethodNames;
        /** null = any authenticated role. Non-null = restricted to listed roles. */
        public final List<String> requiredRoles;
        public final String capabilityText;

        private ModuleDescriptor(Builder b) {
            this.moduleName           = b.moduleName;
            this.relatedTables        = Collections.unmodifiableList(b.relatedTables);
            this.triggerPhrases       = Collections.unmodifiableList(b.triggerPhrases);
            this.supportedReadIntents = Collections.unmodifiableList(b.supportedReadIntents);
            this.toolMethodNames      = Collections.unmodifiableList(b.toolMethodNames);
            this.requiredRoles        = b.requiredRoles == null ? null
                                        : Collections.unmodifiableList(b.requiredRoles);
            this.capabilityText       = b.capabilityText;
        }

        public boolean isRoleAllowed(String role) {
            if (requiredRoles == null) return true;
            if (role == null) return false;
            for (String r : requiredRoles) {
                if (r.equalsIgnoreCase(role)) return true;
            }
            return false;
        }

        private static class Builder {
            String moduleName;
            List<String> relatedTables    = Collections.emptyList();
            List<String> triggerPhrases   = Collections.emptyList();
            List<CopilotIntentType> supportedReadIntents = Collections.emptyList();
            List<String> toolMethodNames  = Collections.emptyList();
            List<String> requiredRoles    = null;
            String capabilityText         = "";

            Builder name(String n)       { this.moduleName = n; return this; }
            Builder tables(String... t)  { this.relatedTables = Arrays.asList(t); return this; }
            Builder phrases(String... p) { this.triggerPhrases = Arrays.asList(p); return this; }
            Builder intents(CopilotIntentType... i) { this.supportedReadIntents = Arrays.asList(i); return this; }
            Builder tools(String... m)   { this.toolMethodNames = Arrays.asList(m); return this; }
            Builder roles(String... r)   { this.requiredRoles = Arrays.asList(r); return this; }
            Builder capability(String c) { this.capabilityText = c; return this; }
            ModuleDescriptor build()     { return new ModuleDescriptor(this); }
        }
    }

    // ── Registry map: moduleName → descriptor ─────────────────────────────────

    // LinkedHashMap (not HashMap): registration order below (Dashboard,
    // Assets, Employees, ... Role & Duty Assignment) is a sensible reading
    // order, and getModulesForRole() relies on it to hand the LLM agent loop
    // a stable, coherent module list rather than hash-bucket order that
    // could reshuffle between JVM runs.
    private static final Map<String, ModuleDescriptor> REGISTRY = new LinkedHashMap<>();

    static {
        register(new ModuleDescriptor.Builder()
            .name("Dashboard")
            .tables("assets", "asset_allocation", "maintenance_logs", "asset_requests")
            .phrases("dashboard", "overview", "summary", "snapshot", "kpi", "statistics",
                     "total assets", "how many assets")
            .intents(CopilotIntentType.DASHBOARD_SUMMARY)
            .tools("getDashboardSummary")
            .capability("I can show **Dashboard KPIs**: total assets, available count, allocated count, " +
                        "assets under maintenance, total purchase value, and pending request count.")
            .build());

        register(new ModuleDescriptor.Builder()
            .name("Assets")
            .tables("assets", "asset_categories", "vendors", "departments",
                    "railway_divisions", "railway_locations")
            .phrases("asset", "assets", "asset list", "asset code", "asset search",
                     "show assets", "find assets", "asset count", "asset cost",
                     "purchase cost", "warranty", "available", "allocated", "disposed", "damaged",
                     "holder", "who holds", "who has")
            .intents(CopilotIntentType.ASSET_SEARCH, CopilotIntentType.ASSET_TOTAL_COST,
                     CopilotIntentType.ASSET_COUNT,  CopilotIntentType.ASSET_HOLDER,
                     CopilotIntentType.AVAILABLE_ASSETS, CopilotIntentType.ALLOCATED_ASSETS,
                     CopilotIntentType.DISPOSED_ASSETS,  CopilotIntentType.DAMAGED_ASSETS,
                     CopilotIntentType.ASSET_BY_STATUS,  CopilotIntentType.ASSET_VALUE_SUMMARY,
                     CopilotIntentType.WARRANTY_EXPIRING_NEXT_N_DAYS,
                     CopilotIntentType.WARRANTY_EXPIRED,
                     CopilotIntentType.WARRANTY_THIS_MONTH)
            .tools("searchAssets", "getAssetTotalCost", "getAssetHolder",
                   "getAvailableAssets", "getAllocatedAssets", "getDisposedAssets",
                   "getDamagedAssets", "countAssets", "getWarranty", "getAssetValueSummary")
            .capability("I can answer: **asset list** (by category/department/status/code), " +
                        "**asset cost** (total purchase cost), **asset count**, " +
                        "**who holds a specific asset**, **available/allocated/disposed/damaged assets**, " +
                        "**warranty expiring** in next N days, **warranty renewal history** (past " +
                        "renewals, extension length, cost), **asset value summaries** by department/" +
                        "category, **disposal workflow details** (reason, method, value recovered, " +
                        "approval status), and **asset transfer history** (custody changes between " +
                        "employees).\n\n" +
                        "Examples:\n" +
                        "- `show laptops in IT department`\n" +
                        "- `total cost of all desktops`\n" +
                        "- `who is holding AST001?`\n" +
                        "- `warranty expiring in next 30 days`\n" +
                        "- `show all disposed assets`\n" +
                        "- `why was AST020 disposed and what did we recover?`\n" +
                        "- `has AST003's warranty ever been renewed?`")
            .build());

        register(new ModuleDescriptor.Builder()
            .name("Employees")
            .tables("employees", "users", "departments", "employee_role_assignments",
                    "asset_allocation")
            .phrases("employee", "employees", "staff", "worker", "employee details",
                     "employee profile", "employee search", "who works in")
            .intents(CopilotIntentType.EMPLOYEE_DETAILS, CopilotIntentType.EMPLOYEE_SEARCH,
                     CopilotIntentType.EMPLOYEE_ALLOCATIONS, CopilotIntentType.DEPARTMENT_EMPLOYEES)
            .tools("getEmployeeDetails", "searchEmployees", "getEmployeeAllocations",
                   "getDepartmentEmployees")
            .capability("I can answer: **employee details** (by code or name), " +
                        "**employee search** by department, **assets assigned to an employee**, " +
                        "and **employees in a department**.\n\n" +
                        "Examples:\n" +
                        "- `employee details of EMP006`\n" +
                        "- `which assets are assigned to Subham?`\n" +
                        "- `employees in IT department`")
            .build());

        register(new ModuleDescriptor.Builder()
            .name("Departments")
            .tables("departments")
            .phrases("department", "departments", "dept", "department summary", "department wise")
            .intents(CopilotIntentType.DEPT_SUMMARY, CopilotIntentType.DEPARTMENT_SEARCH,
                     CopilotIntentType.DEPARTMENT_EMPLOYEES)
            .tools("getDepartmentSummary", "getDepartmentEmployees")
            .capability("I can show: **department-wise asset summary** (count + total value) " +
                        "and **employees in a department**.\n\n" +
                        "Examples:\n" +
                        "- `total value of assets department wise`\n" +
                        "- `employees in Stores department`")
            .build());

        register(new ModuleDescriptor.Builder()
            .name("Categories")
            .tables("asset_categories")
            .phrases("category", "categories", "category wise", "category summary", "asset type")
            .intents(CopilotIntentType.CATEGORY_SUMMARY)
            .tools("getCategorySummary")
            .capability("I can show: **category-wise asset summary** (count + total cost).\n\n" +
                        "Example: `show category wise asset summary`")
            .build());

        register(new ModuleDescriptor.Builder()
            .name("Suppliers")
            .tables("vendors")
            .phrases("vendor", "vendors", "supplier", "suppliers", "vendor list",
                     "vendor summary", "supplier summary")
            .intents(CopilotIntentType.SUPPLIER_SUMMARY)
            .tools("getSupplierSummary")
            .capability("I can show: **vendor/supplier summary** (count of assets per supplier).\n\n" +
                        "Example: `show vendor summary`")
            .build());

        register(new ModuleDescriptor.Builder()
            .name("Category Supplier Mapping")
            .tables("category_vendor_mapping", "asset_categories", "vendors")
            .phrases("category vendor mapping", "which vendor supplies", "category supplier",
                     "vendor for category", "supplier for category")
            .intents(CopilotIntentType.CATEGORY_VENDOR_MAPPING)
            .tools("getCategoryVendorMapping")
            .capability("I can show: **category-to-vendor mappings** (which suppliers provide which asset types).\n\n" +
                        "Example: `show category vendor mapping`")
            .build());

        register(new ModuleDescriptor.Builder()
            .name("Asset Requests")
            .tables("asset_requests", "employees", "asset_categories", "departments")
            .phrases("asset request", "asset requests", "pending request", "approved request",
                     "rejected request", "demand", "new request", "request status")
            .intents(CopilotIntentType.PENDING_ASSET_REQUESTS,
                     CopilotIntentType.APPROVED_ASSET_REQUESTS,
                     CopilotIntentType.REJECTED_ASSET_REQUESTS)
            .tools("getPendingAssetRequests", "getApprovedRequests", "getRejectedRequests")
            .capability("I can show: **pending asset requests**, **approved requests**, and **rejected requests**.\n\n" +
                        "Examples:\n" +
                        "- `show pending asset requests`\n" +
                        "- `show approved asset requests`\n" +
                        "- `show rejected requests`")
            .build());

        register(new ModuleDescriptor.Builder()
            .name("Allocation")
            .tables("asset_allocation", "assets", "employees", "departments",
                    "asset_categories")
            .phrases("allocation", "allocated", "assigned", "custody", "currently holding",
                     "employee allocations", "who holds", "who has")
            .intents(CopilotIntentType.ALLOCATION_SEARCH, CopilotIntentType.EMPLOYEE_ALLOCATIONS,
                     CopilotIntentType.ASSET_HOLDER, CopilotIntentType.ALLOCATED_ASSETS)
            .tools("searchAllocations", "getEmployeeAllocations", "getAssetHolder",
                   "getAllocatedAssets")
            .capability("I can answer: **current allocations**, **employee asset holdings**, " +
                        "and **who holds a specific asset**.\n\n" +
                        "Examples:\n" +
                        "- `which assets are assigned to Subham?`\n" +
                        "- `who is holding AST001?`\n" +
                        "- `show allocated assets in IT department`")
            .build());

        register(new ModuleDescriptor.Builder()
            .name("Returns")
            .tables("asset_returns", "assets", "employees", "departments",
                    "asset_allocation")
            .phrases("return", "returns", "return records", "return history", "handover",
                     "pending return", "returned assets")
            .intents(CopilotIntentType.RETURN_SEARCH, CopilotIntentType.PENDING_RETURNS)
            .tools("getReturnRecords", "getPendingReturns")
            .capability("I can show: **return records** and **pending returns** (items not yet returned).\n\n" +
                        "Examples:\n" +
                        "- `show return records`\n" +
                        "- `show pending returns`")
            .build());

        register(new ModuleDescriptor.Builder()
            .name("Maintenance")
            .tables("maintenance_logs", "assets", "employees")
            .phrases("maintenance", "repair", "service", "under maintenance", "pending maintenance",
                     "maintenance history", "repair history", "service log")
            .intents(CopilotIntentType.MAINTENANCE_PENDING, CopilotIntentType.MAINTENANCE_HISTORY)
            .tools("getPendingMaintenance", "getMaintenanceHistory")
            .capability("I can answer: **pending/ongoing maintenance** (assets under repair), " +
                        "and **maintenance history** of a specific asset.\n\n" +
                        "Examples:\n" +
                        "- `show pending maintenance`\n" +
                        "- `maintenance history of AST003`\n" +
                        "- `how many assets are under maintenance?`")
            .build());

        register(new ModuleDescriptor.Builder()
            .name("Physical Verification")
            .tables("asset_physical_verification", "verification_rounds",
                    "physical_verification_duties", "assets", "employees")
            .phrases("physical verification", "pv", "pv status", "pv duty", "verification",
                     "physical check", "asset verification", "verification status")
            .intents(CopilotIntentType.PHYSICAL_VERIFICATION_SUMMARY)
            .tools("getPhysicalVerificationSummary")
            .capability("I can show: **physical verification summary** — verification rounds, " +
                        "asset verification status (verified/not verified/discrepancy), and duty assignments.\n\n" +
                        "Example: `show physical verification summary`")
            .build());

        register(new ModuleDescriptor.Builder()
            .name("Reports & Analytics")
            .tables("assets", "asset_allocation", "maintenance_logs", "asset_returns",
                    "asset_requests", "employees", "departments", "asset_categories",
                    "vendors")
            .phrases("report", "reports", "analytics", "summary", "department wise",
                     "category wise", "value summary", "total value", "asset value",
                     "department summary", "category summary")
            .intents(CopilotIntentType.DEPT_SUMMARY, CopilotIntentType.CATEGORY_SUMMARY,
                     CopilotIntentType.ASSET_VALUE_SUMMARY, CopilotIntentType.SUPPLIER_SUMMARY,
                     CopilotIntentType.DASHBOARD_SUMMARY)
            .tools("getDepartmentSummary", "getCategorySummary", "getAssetValueSummary",
                   "getSupplierSummary", "getDashboardSummary")
            .capability("I can generate: **department-wise asset summary**, " +
                        "**category-wise summary**, **vendor/supplier summary**, " +
                        "**asset value breakdown**, and **overall dashboard KPIs**.\n\n" +
                        "Examples:\n" +
                        "- `total value of assets department wise`\n" +
                        "- `show category wise asset summary`\n" +
                        "- `show vendor summary`")
            .build());

        register(new ModuleDescriptor.Builder()
            .name("Audit")
            .tables("audit_logs", "users")
            .phrases("audit", "audit log", "audit logs", "who changed", "change history",
                     "activity log", "user activity", "action log")
            .intents(CopilotIntentType.AUDIT_SEARCH)
            .tools("getAuditLogs")
            .roles("ADMIN", "SUPER_ADMIN", "AUDITOR")
            .capability("I can search: **audit logs** — who performed what action, " +
                        "on which record, and when.\n\n" +
                        "Examples:\n" +
                        "- `show audit logs`\n" +
                        "- `show audit logs for today`")
            .build());

        register(new ModuleDescriptor.Builder()
            .name("QR Control Center")
            .tables("public_asset_snapshot", "qr_sync_queue", "public_qr_base_urls")
            .phrases("qr", "qr code", "qr tag", "qr status", "tagging status",
                     "qr scan", "scan log", "qr scan logs", "qr tagging", "qr control")
            .intents(CopilotIntentType.QR_STATUS, CopilotIntentType.QR_SCAN_LOGS)
            .tools("getQrStatus", "getQrScanLogs")
            .capability("I can show: **QR tagging status** (which assets have active QR codes) " +
                        "and **QR sync/scan logs** (recent QR activity).\n\n" +
                        "Examples:\n" +
                        "- `show QR tagging status`\n" +
                        "- `show QR scan logs`")
            .build());

        register(new ModuleDescriptor.Builder()
            .name("Settings")
            .tables("system_settings")
            .phrases("settings", "system settings", "configuration", "config",
                     "ai mode", "email settings", "currency settings")
            .intents(CopilotIntentType.SETTINGS_SUMMARY)
            .tools("getSettingsSummary")
            .roles("ADMIN", "SUPER_ADMIN")
            .capability("I can show: **system settings summary** — AI mode status, provider, " +
                        "currency, QR provider, and notification settings. " +
                        "(Sensitive keys are never shown.)\n\n" +
                        "Example: `show system settings`")
            .build());

        register(new ModuleDescriptor.Builder()
            .name("Role & Duty Assignment")
            .tables("employee_role_assignments", "employees", "users")
            .phrases("role duty", "role assignment", "duty", "duty assignment", "duty chart",
                     "role summary", "who has admin", "who has role", "assigned role")
            .intents(CopilotIntentType.ROLE_DUTY_SUMMARY)
            .tools("getRoleDutySummary")
            .roles("ADMIN", "SUPER_ADMIN")
            .capability("I can show: **role and duty assignments** — which employees have " +
                        "which system roles (ADMIN, AUDITOR, ASSET_MANAGER, etc.).\n\n" +
                        "Example: `show role duty summary`")
            .build());
    }

    // ── Internal registry helpers ─────────────────────────────────────────────

    private static void register(ModuleDescriptor d) {
        REGISTRY.put(d.moduleName.toLowerCase(), d);
    }

    // ── Public API ────────────────────────────────────────────────────────────

    /**
     * Find the module for a given intent type.
     * Returns null if no module owns that intent.
     */
    public static ModuleDescriptor findModuleForIntent(CopilotIntentType intent) {
        if (intent == null) return null;
        for (ModuleDescriptor d : REGISTRY.values()) {
            if (d.supportedReadIntents.contains(intent)) return d;
        }
        return null;
    }

    /**
     * Find the module by trigger phrase match in normalized user text.
     */
    public static ModuleDescriptor findModuleByPhrase(String normalizedText) {
        if (normalizedText == null) return null;
        String q = normalizedText.toLowerCase();
        ModuleDescriptor best = null;
        int bestLen = 0;
        for (ModuleDescriptor d : REGISTRY.values()) {
            for (String phrase : d.triggerPhrases) {
                if (q.contains(phrase) && phrase.length() > bestLen) {
                    best = d;
                    bestLen = phrase.length();
                }
            }
        }
        return best;
    }

    /**
     * Get capability text for a named module.
     * Returns null if module not found.
     */
    public static String getCapabilityText(String moduleName) {
        if (moduleName == null) return null;
        ModuleDescriptor d = REGISTRY.get(moduleName.toLowerCase());
        return d != null ? d.capabilityText : null;
    }

    /**
     * Check whether the given role is allowed to use the given tool.
     * Returns true if the tool belongs to an unrestricted module or the role matches.
     */
    public static boolean isToolAllowed(CopilotIntentType intent, String role) {
        ModuleDescriptor d = findModuleForIntent(intent);
        if (d == null) return true; // unknown module = allow (tool executor will handle details)
        return d.isRoleAllowed(role);
    }

    /**
     * Every module visible to a given role, in registration order.
     *
     * Added so the LLM agent loop (CopilotAgentLoop) can give the model a
     * comprehensive, accurate map of every IR-AMS module and what it can
     * help with - not just this keyword-driven registry's original use (the
     * keyword-fallback pipeline's "help [module]" command). Without this,
     * the agent loop only knows the raw tool list, which does not by itself
     * explain what each module IS or which questions naturally belong to
     * it; a user asking "what can the QR Control Center do?" deserves a
     * real, curated answer, not the model guessing from a function name.
     */
    public static List<ModuleDescriptor> getModulesForRole(String role) {
        List<ModuleDescriptor> visible = new ArrayList<>();
        for (ModuleDescriptor d : REGISTRY.values()) {
            if (d.isRoleAllowed(role)) {
                visible.add(d);
            }
        }
        return visible;
    }

    /**
     * Returns a map of all module names → their capability texts.
     * Useful for building the "what can you do?" help response.
     */
    public static Map<String, String> getAllCapabilities() {
        Map<String, String> caps = new HashMap<>();
        for (ModuleDescriptor d : REGISTRY.values()) {
            caps.put(d.moduleName, d.capabilityText);
        }
        return caps;
    }
}
