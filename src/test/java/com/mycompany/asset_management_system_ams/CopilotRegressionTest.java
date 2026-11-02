package com.mycompany.asset_management_system_ams;

/**
 * CopilotRegressionTest — Standalone NLU regression test suite.
 *
 * Tests ONLY the language normalization + intent detection + entity resolution
 * pipeline (no database required). Run with:
 *
 *   mvn test
 *   or: javac + java CopilotRegressionTest (after compile)
 *
 * Each test calls CopilotIntentDetector.detectIntent() and validates the
 * resulting CopilotQueryPlan against expected intent + entities.
 *
 * Coverage:
 *   TC-01 to TC-30  — Phase 1 core + robustness scenarios (30 tests)
 *   TC-31 to TC-45  — Phase 2 extended intent scenarios  (15 tests)
 *   Total           : 45 scenarios
 *
 * Note on MODULE_CAPABILITY: This enum does NOT exist in CopilotIntentType.
 * Module-specific help ("what can you do in maintenance?") resolves to
 * HELP_NAVIGATION; the module keyword is stored in plan.targetModule.
 *
 * IMPORTANT: This file is in src/test/java — NOT in src/main/java.
 * Do not move it to the production source tree.
 */
public class CopilotRegressionTest {

    // ── Test case counter ──────────────────────────────────────────────────
    private static int passed = 0;
    private static int failed = 0;

    // ─────────────────────────────────────────────────────────────────────────
    // MAIN
    // ─────────────────────────────────────────────────────────────────────────

    public static void main(String[] args) {
        System.out.println("==========================================================");
        System.out.println(" AMS Copilot — NLU Regression Test Suite");
        System.out.println("==========================================================\n");

        // Enable debug output for test run
        System.setProperty("COPILOT_DEBUG", "true");

        runAllTests();

        System.out.println("\n==========================================================");
        System.out.println(" RESULTS: " + passed + " passed, " + failed + " failed");
        System.out.println("==========================================================");

        if (failed > 0) System.exit(1);
    }

    private static void runAllTests() {

        // ── Test 1 ────────────────────────────────────────────────────────────
        test("TC-01: Total purchase cost — direct English",
            "Can you tell me the total purchase cost of all laptops?",
            CopilotIntentType.ASSET_TOTAL_COST,
            ExpectedEntities.of().category("Laptop")
        );

        // ── Test 2 ────────────────────────────────────────────────────────────
        test("TC-02: Voice error — purchased calls of laptops",
            "Hello, can you tell me all the purchased calls of the laptops?",
            CopilotIntentType.ASSET_TOTAL_COST,
            ExpectedEntities.of().category("Laptop")
        );

        // ── Test 3 ────────────────────────────────────────────────────────────
        test("TC-03: Hinglish — saare laptops ka cost kitna hai",
            "mujhe batao saare laptops ka cost kitna hai",
            CopilotIntentType.ASSET_TOTAL_COST,
            ExpectedEntities.of().category("Laptop")
        );

        // ── Test 4 ────────────────────────────────────────────────────────────
        test("TC-04: Asset list with category + department",
            "show laptops in IT department",
            CopilotIntentType.ASSET_SEARCH,
            ExpectedEntities.of().category("Laptop").department("IT Centre")
        );

        // ── Test 5 ────────────────────────────────────────────────────────────
        test("TC-05: Warranty expiring future — next 30 days",
            "warranty expiring in next 30 days",
            CopilotIntentType.WARRANTY_EXPIRING_NEXT_N_DAYS,
            ExpectedEntities.of().days(30)
        );

        // ── Test 6 ────────────────────────────────────────────────────────────
        test("TC-06: Warranty already expired",
            "expired warranty assets",
            CopilotIntentType.WARRANTY_EXPIRED,
            ExpectedEntities.of()
        );

        // ── Test 7 ────────────────────────────────────────────────────────────
        test("TC-07: Maintenance history with asset code",
            "maintenance history of AST003",
            CopilotIntentType.MAINTENANCE_HISTORY,
            ExpectedEntities.of().assetCode("AST003")
        );

        // ── Test 8 ────────────────────────────────────────────────────────────
        test("TC-08: Export last result",
            "export this",
            CopilotIntentType.EXPORT_CURRENT_RESULT,
            ExpectedEntities.of()
        );

        // ── Test 9 ────────────────────────────────────────────────────────────
        test("TC-09: Who is holding asset (ASSET_HOLDER)",
            "who is holding laptop AST001?",
            CopilotIntentType.ASSET_HOLDER,
            ExpectedEntities.of().assetCode("AST001")
        );

        // ── Test 10 ───────────────────────────────────────────────────────────
        test("TC-10: Pending asset requests",
            "show pending asset requests",
            CopilotIntentType.PENDING_ASSET_REQUESTS,
            ExpectedEntities.of()
        );

        // ── Test 11 ───────────────────────────────────────────────────────────
        test("TC-11: Available assets in Stores",
            "which assets are available in stores?",
            CopilotIntentType.AVAILABLE_ASSETS,
            ExpectedEntities.of().department("Stores")
        );

        // ── Test 12 ───────────────────────────────────────────────────────────
        test("TC-12: Disposed assets",
            "show all disposed assets",
            CopilotIntentType.DISPOSED_ASSETS,
            ExpectedEntities.of()
        );

        // ── Test 13 ───────────────────────────────────────────────────────────
        test("TC-13: Department-wise value summary",
            "total value of assets department wise",
            CopilotIntentType.DEPT_SUMMARY,
            ExpectedEntities.of()
        );

        // ── Test 14 ───────────────────────────────────────────────────────────
        test("TC-14: Employee allocations by name",
            "which assets are assigned to Subham?",
            CopilotIntentType.EMPLOYEE_ALLOCATIONS,
            ExpectedEntities.of().employeeName("Subham")
        );

        // ── Test 15 ───────────────────────────────────────────────────────────
        test("TC-15: Employee details by code",
            "tell me employee details of EMP006",
            CopilotIntentType.EMPLOYEE_DETAILS,
            ExpectedEntities.of().employeeCode("EMP006")
        );

        // ── Additional robustness tests ───────────────────────────────────────

        test("TC-16: Voice error — purchased cost",
            "tell me the purchased cost of all desktops",
            CopilotIntentType.ASSET_TOTAL_COST,
            ExpectedEntities.of().category("Desktop")
        );

        test("TC-17: Total cost all assets (no category)",
            "what is the total asset cost?",
            CopilotIntentType.ASSET_TOTAL_COST,
            ExpectedEntities.of()
        );

        test("TC-18: Hinglish — portfolio cost",
            "portfolio value of all assets",
            CopilotIntentType.ASSET_TOTAL_COST,
            ExpectedEntities.of()
        );

        test("TC-19: Warranty — this month",
            "show assets whose warranty expires this month",
            CopilotIntentType.WARRANTY_THIS_MONTH,
            ExpectedEntities.of()
        );

        test("TC-20: Maintenance — pending (no history keyword)",
            "how many assets are under maintenance?",
            CopilotIntentType.MAINTENANCE_PENDING,
            ExpectedEntities.of()
        );

        test("TC-21: Category summary",
            "asset summary by category",
            CopilotIntentType.CATEGORY_SUMMARY,
            ExpectedEntities.of()
        );

        test("TC-22: Normalization — lap top → laptop",
            "show me all lap tops",
            CopilotIntentType.ASSET_SEARCH,
            ExpectedEntities.of().category("Laptop")
        );

        test("TC-23: Odia — mote kuha sabu laptops ra cost",
            "mote kuha sabu laptops ra cost kete",
            CopilotIntentType.ASSET_TOTAL_COST,
            ExpectedEntities.of().category("Laptop")
        );

        test("TC-24: Typo — maintainance history AST005",
            "maintainance history of AST005",
            CopilotIntentType.MAINTENANCE_HISTORY,
            ExpectedEntities.of().assetCode("AST005")
        );

        test("TC-25: Typo — warrenty expiring",
            "warrenty expiring in next 15 days",
            CopilotIntentType.WARRANTY_EXPIRING_NEXT_N_DAYS,
            ExpectedEntities.of().days(15)
        );

        test("TC-26: Download = export",
            "download this report",
            CopilotIntentType.EXPORT_CURRENT_RESULT,
            ExpectedEntities.of()
        );

        test("TC-27: Stores department — available assets",
            "which assets are free in store?",
            CopilotIntentType.AVAILABLE_ASSETS,
            ExpectedEntities.of().department("Stores")
        );

        test("TC-28: Audit department assets",
            "show assets in audit department",
            CopilotIntentType.ASSET_SEARCH,
            ExpectedEntities.of().department("Audit")
        );

        test("TC-29: General admin department",
            "assets in general admin",
            CopilotIntentType.ASSET_SEARCH,
            ExpectedEntities.of().department("General Administration")
        );

        test("TC-30: Allocated assets",
            "show all allocated assets",
            CopilotIntentType.ALLOCATED_ASSETS,
            ExpectedEntities.of()
        );

        // ── Phase 2 — Extended Asset Tests ───────────────────────────────────

        // ── Test 31 ───────────────────────────────────────────────────────────
        test("TC-31: Damaged assets — plain English",
            "show damaged assets",
            CopilotIntentType.DAMAGED_ASSETS,
            ExpectedEntities.of()
        );

        // ── Test 32 ───────────────────────────────────────────────────────────
        test("TC-32: Damaged assets — broken keyword",
            "show all broken assets",
            CopilotIntentType.DAMAGED_ASSETS,
            ExpectedEntities.of()
        );

        // ── Test 33 ───────────────────────────────────────────────────────────
        test("TC-33: Approved asset requests",
            "show approved asset requests",
            CopilotIntentType.APPROVED_ASSET_REQUESTS,
            ExpectedEntities.of()
        );

        // ── Test 34 ───────────────────────────────────────────────────────────
        test("TC-34: Rejected asset requests",
            "show rejected requests",
            CopilotIntentType.REJECTED_ASSET_REQUESTS,
            ExpectedEntities.of()
        );

        // ── Test 35 ───────────────────────────────────────────────────────────
        test("TC-35: Return records — all",
            "show all return records",
            CopilotIntentType.RETURN_RECORDS,
            ExpectedEntities.of()
        );

        // ── Test 36 ───────────────────────────────────────────────────────────
        test("TC-36: Pending returns",
            "show pending returns",
            CopilotIntentType.PENDING_RETURNS,
            ExpectedEntities.of()
        );

        // ── Test 37 ───────────────────────────────────────────────────────────
        test("TC-37: Pending returns — alternate phrasing",
            "which assets have not been returned?",
            CopilotIntentType.PENDING_RETURNS,
            ExpectedEntities.of()
        );

        // ── Test 38 ───────────────────────────────────────────────────────────
        // Note: "MODULE_CAPABILITY" is not a separate enum value.
        // DEPARTMENT_EMPLOYEES covers "employees in <dept>" queries.
        // The department extractor resolves "IT department" → "IT Centre".
        test("TC-38: Department employees — IT",
            "employees in IT department",
            CopilotIntentType.DEPARTMENT_EMPLOYEES,
            ExpectedEntities.of().department("IT Centre")
        );

        // ── Test 39 ───────────────────────────────────────────────────────────
        test("TC-39: QR tagging status",
            "show QR tagging status",
            CopilotIntentType.QR_STATUS,
            ExpectedEntities.of()
        );

        // ── Test 40 ───────────────────────────────────────────────────────────
        test("TC-40: QR scan logs",
            "show QR scan logs",
            CopilotIntentType.QR_SCAN_LOGS,
            ExpectedEntities.of()
        );

        // ── Test 41 ───────────────────────────────────────────────────────────
        test("TC-41: Audit logs",
            "show audit logs",
            CopilotIntentType.AUDIT_SEARCH,
            ExpectedEntities.of()
        );

        // ── Test 42 ───────────────────────────────────────────────────────────
        test("TC-42: Role duty summary",
            "show role duty summary",
            CopilotIntentType.ROLE_DUTY_SUMMARY,
            ExpectedEntities.of()
        );

        // ── Test 43 ───────────────────────────────────────────────────────────
        test("TC-43: Physical verification summary",
            "show physical verification summary",
            CopilotIntentType.PHYSICAL_VERIFICATION_SUMMARY,
            ExpectedEntities.of()
        );

        // ── Test 44 ───────────────────────────────────────────────────────────
        test("TC-44: Category vendor mapping",
            "show category vendor mapping",
            CopilotIntentType.CATEGORY_VENDOR_MAPPING,
            ExpectedEntities.of()
        );

        // ── Test 45 ───────────────────────────────────────────────────────────
        // "what can you do in maintenance?" and follow-up "what about stores?"
        // both route to HELP_NAVIGATION (the canonical enum for help/capability
        // queries). MODULE_CAPABILITY does NOT exist as a separate enum value.
        // CopilotReasoningPlanner detects the module keyword ("maintenance" /
        // "stores") and stores it in plan.targetModule for module-specific help.
        test("TC-45: Help — maintenance module capability",
            "what can you do in maintenance?",
            CopilotIntentType.HELP_NAVIGATION,
            ExpectedEntities.of()
        );

        // TC-45b is a documentation note only:
        // "what about stores?" is a follow-up that re-routes via
        // CopilotReasoningPlanner session memory, inheriting the previous
        // HELP_NAVIGATION intent with targetModule changed to "Stores".
        // It is not testable in isolation without a live session context.

        // EXPORT_CURRENT_RESULT is already covered by TC-08 and TC-26.
    }

    // ─────────────────────────────────────────────────────────────────────────
    // TEST RUNNER
    // ─────────────────────────────────────────────────────────────────────────

    private static void test(String testName, String input,
                              CopilotIntentType expectedIntent,
                              ExpectedEntities expected) {
        System.out.println("\n── " + testName);
        System.out.println("   Input: \"" + input + "\"");

        // Normalize
        String normalized = CopilotLanguageNormalizer.normalize(input);
        System.out.println("   Normalized: \"" + normalized + "\"");

        // Detect
        CopilotQueryPlan plan = CopilotIntentDetector.detectIntent(input);

        boolean ok = true;
        StringBuilder issues = new StringBuilder();

        // Check intent
        if (plan.intent != expectedIntent) {
            issues.append("\n   ❌ Intent: expected=").append(expectedIntent)
                  .append(", got=").append(plan.intent)
                  .append(" (confidence=").append(String.format("%.2f", plan.confidence)).append(")");
            ok = false;
        } else {
            System.out.println("   ✅ Intent: " + plan.intent + " (confidence=" +
                String.format("%.2f", plan.confidence) + ")");
        }

        // Check category
        if (expected.category != null) {
            if (!expected.category.equals(plan.normalizedCategory)) {
                issues.append("\n   ❌ Category: expected=").append(expected.category)
                      .append(", got=").append(plan.normalizedCategory);
                ok = false;
            } else {
                System.out.println("   ✅ Category: " + plan.normalizedCategory);
            }
        }

        // Check department
        if (expected.department != null) {
            if (!expected.department.equals(plan.departmentName)) {
                issues.append("\n   ❌ Department: expected=").append(expected.department)
                      .append(", got=").append(plan.departmentName);
                ok = false;
            } else {
                System.out.println("   ✅ Department: " + plan.departmentName);
            }
        }

        // Check asset code
        if (expected.assetCode != null) {
            if (!expected.assetCode.equals(plan.assetCode)) {
                issues.append("\n   ❌ AssetCode: expected=").append(expected.assetCode)
                      .append(", got=").append(plan.assetCode);
                ok = false;
            } else {
                System.out.println("   ✅ AssetCode: " + plan.assetCode);
            }
        }

        // Check employee code
        if (expected.employeeCode != null) {
            if (!expected.employeeCode.equals(plan.employeeCode)) {
                issues.append("\n   ❌ EmployeeCode: expected=").append(expected.employeeCode)
                      .append(", got=").append(plan.employeeCode);
                ok = false;
            } else {
                System.out.println("   ✅ EmployeeCode: " + plan.employeeCode);
            }
        }

        // Check employee name
        if (expected.employeeName != null) {
            boolean nameMatch = plan.employeeName != null &&
                plan.employeeName.toLowerCase().contains(expected.employeeName.toLowerCase());
            if (!nameMatch) {
                issues.append("\n   ❌ EmployeeName: expected to contain '").append(expected.employeeName)
                      .append("', got=").append(plan.employeeName);
                ok = false;
            } else {
                System.out.println("   ✅ EmployeeName: " + plan.employeeName);
            }
        }

        // Check days
        if (expected.days != null) {
            if (!expected.days.equals(plan.days)) {
                issues.append("\n   ❌ Days: expected=").append(expected.days)
                      .append(", got=").append(plan.days);
                ok = false;
            } else {
                System.out.println("   ✅ Days: " + plan.days);
            }
        }

        if (ok) {
            System.out.println("   PASS ✅");
            passed++;
        } else {
            System.out.println("   FAIL ❌" + issues);
            failed++;
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // HELPER — builder for expected entities
    // ─────────────────────────────────────────────────────────────────────────

    private static class ExpectedEntities {
        String category;
        String department;
        String assetCode;
        String employeeCode;
        String employeeName;
        Integer days;

        static ExpectedEntities of() { return new ExpectedEntities(); }

        ExpectedEntities category(String c)     { this.category     = c; return this; }
        ExpectedEntities department(String d)   { this.department   = d; return this; }
        ExpectedEntities assetCode(String a)    { this.assetCode    = a; return this; }
        ExpectedEntities employeeCode(String e) { this.employeeCode = e; return this; }
        ExpectedEntities employeeName(String e) { this.employeeName = e; return this; }
        ExpectedEntities days(int n)            { this.days         = n; return this; }
    }
}
