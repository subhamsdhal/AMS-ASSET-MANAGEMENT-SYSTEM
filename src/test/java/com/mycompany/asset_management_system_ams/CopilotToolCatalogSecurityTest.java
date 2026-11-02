package com.mycompany.asset_management_system_ams;

import java.util.HashMap;
import java.util.List;
import java.util.Map;

import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

/**
 * Locks the access boundary of the AI Copilot's tool catalog.
 *
 * This matters more than a normal unit test: the catalog is what an LLM is
 * allowed to reach into the database with. A regression that widens it would
 * not throw, would not fail a build, and would not be visible in the UI — it
 * would just quietly let a lower-privileged role read data through the Copilot
 * that the equivalent IR-AMS screen denies them.
 *
 * Both layers are asserted:
 *   1. forRole()  — a restricted tool is never even shown to the model
 *   2. execute()  — a restricted tool is refused even if the model names it
 *                   anyway (a hallucinated or replayed tool name)
 */
public class CopilotToolCatalogSecurityTest {

    private static boolean hasTool(List<LlmToolSpec> tools, String name) {
        for (LlmToolSpec spec : tools) {
            if (spec.name.equals(name)) {
                return true;
            }
        }
        return false;
    }

    @Test
    public void testEmployeeCannotSeePrivilegedTools() {
        List<LlmToolSpec> tools = CopilotToolCatalog.forRole("EMPLOYEE");

        // An employee gets a working Copilot...
        assertTrue(hasTool(tools, "get_employee_allocations"),
                "EMPLOYEE should still be able to look up their own allocated assets");
        assertTrue(hasTool(tools, "get_warranty"),
                "EMPLOYEE should still be able to ask about warranty");

        // ...but nothing that exposes the organisation as a whole.
        assertFalse(hasTool(tools, "get_audit_logs"),
                "EMPLOYEE must never reach the audit trail");
        assertFalse(hasTool(tools, "get_settings_summary"),
                "EMPLOYEE must never reach system settings");
        assertFalse(hasTool(tools, "get_role_duty_summary"),
                "EMPLOYEE must never reach role/duty assignments");
        assertFalse(hasTool(tools, "get_department_summary"),
                "EMPLOYEE must not reach org-wide department summaries");
        assertFalse(hasTool(tools, "get_disposed_assets"),
                "EMPLOYEE must not reach disposal records");
        assertFalse(hasTool(tools, "search_employees"),
                "EMPLOYEE must not be able to search the employee register");

        // Same NON_EMPLOYEE boundary applies to the three tools added for
        // asset_disposal, asset_transfers, and warranty_renewals - these are
        // operational/managerial records, same class as disposal records
        // and department summaries above, not personal employee data.
        assertFalse(hasTool(tools, "get_asset_disposal_details"),
                "EMPLOYEE must not reach disposal workflow details");
        assertFalse(hasTool(tools, "get_asset_transfer_history"),
                "EMPLOYEE must not reach asset transfer history");
        assertFalse(hasTool(tools, "get_warranty_renewal_history"),
                "EMPLOYEE must not reach warranty renewal history");
    }

    @Test
    public void testAuditorSeesAuditButNotAdminOnlyTools() {
        List<LlmToolSpec> tools = CopilotToolCatalog.forRole("AUDITOR");

        assertTrue(hasTool(tools, "get_audit_logs"),
                "AUDITOR is the role the audit trail exists for");
        assertTrue(hasTool(tools, "get_qr_scan_logs"),
                "AUDITOR has QR scan-log visibility elsewhere in the app");

        // Read-only compliance access stops short of system administration -
        // same boundary access_matrix.jsp documents for this role.
        assertFalse(hasTool(tools, "get_settings_summary"),
                "AUDITOR must not reach system settings");
        assertFalse(hasTool(tools, "get_role_duty_summary"),
                "AUDITOR must not reach role/duty assignments");
    }

    @Test
    public void testDepartmentHeadCannotReachAuditOrQrTools() {
        List<LlmToolSpec> tools = CopilotToolCatalog.forRole("DEPARTMENT_HEAD");

        assertTrue(hasTool(tools, "get_department_summary"),
                "DEPARTMENT_HEAD should reach department summaries");

        assertFalse(hasTool(tools, "get_audit_logs"),
                "DEPARTMENT_HEAD has no audit-log access anywhere in the app");
        assertFalse(hasTool(tools, "get_qr_status"),
                "DEPARTMENT_HEAD has no QR control access anywhere in the app");
    }

    @Test
    public void testAdminSeesEverythingIncludingAdminOnlyTools() {
        List<LlmToolSpec> tools = CopilotToolCatalog.forRole("SUPER_ADMIN");

        assertTrue(hasTool(tools, "get_audit_logs"));
        assertTrue(hasTool(tools, "get_settings_summary"));
        assertTrue(hasTool(tools, "get_role_duty_summary"));
        assertTrue(hasTool(tools, "search_assets"));
        assertTrue(hasTool(tools, "get_asset_disposal_details"));
        assertTrue(hasTool(tools, "get_asset_transfer_history"));
        assertTrue(hasTool(tools, "get_warranty_renewal_history"));
    }

    @Test
    public void testUnknownOrMissingRoleGetsNoTools() {
        // Default-deny: an unrecognised role value must not fall through to a
        // permissive default. Same invariant RoleAccessUtil enforces for pages.
        assertTrue(CopilotToolCatalog.forRole(null).isEmpty(),
                "A null role must receive no tools");
        assertTrue(CopilotToolCatalog.forRole("").isEmpty(),
                "A blank role must receive no tools");
        assertTrue(CopilotToolCatalog.forRole("GUEST").isEmpty(),
                "An unrecognised role must receive no tools");
    }

    @Test
    public void testCatalogIsReadOnly() {
        // The Copilot's LLM path must expose no mutation. Write actions stay on
        // CopilotCommandDetector's keyword path with its confirmation gate.
        List<LlmToolSpec> tools = CopilotToolCatalog.forRole("SUPER_ADMIN");
        for (LlmToolSpec spec : tools) {
            String name = spec.name;
            assertFalse(name.startsWith("create_") || name.startsWith("add_")
                            || name.startsWith("update_") || name.startsWith("delete_")
                            || name.startsWith("approve_") || name.startsWith("reject_")
                            || name.startsWith("set_") || name.startsWith("remove_"),
                    "Catalog must stay read-only, but found a mutating tool: " + name);
        }
    }

    @Test
    public void testExecuteRefusesToolOutsideRoleEvenWhenNamedDirectly() {
        // Layer 2: forRole() never showed EMPLOYEE this tool, but a model can
        // still emit a name it was not given. That must be refused, not run.
        LlmToolCall hallucinated =
                new LlmToolCall("call_1", "get_audit_logs", new HashMap<String, String>());

        String result = CopilotToolCatalog.execute(hallucinated, "EMPLOYEE", null);

        assertTrue(result.contains("error"),
                "A tool outside the caller's role must return an error, not data");
        assertTrue(result.contains("not available to your role"),
                "Refusal should say why. Actual: " + result);
    }

    @Test
    public void testExecuteRefusesCompletelyUnknownToolName() {
        Map<String, String> args = new HashMap<String, String>();
        args.put("category", "Laptop");
        LlmToolCall invented = new LlmToolCall("call_2", "drop_all_assets", args);

        String result = CopilotToolCatalog.execute(invented, "SUPER_ADMIN", null);

        assertTrue(result.contains("error"),
                "An unknown tool name must be refused even for SUPER_ADMIN. Actual: " + result);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Provider chain
    // ─────────────────────────────────────────────────────────────────────────

    @Test
    public void testUnconfiguredProvidersNeverEnterTheChain() {
        // With no keys saved (the state in a unit-test environment, where
        // SettingsDAO cannot reach a database), the chain must be empty rather
        // than containing half-built clients. An unconfigured provider in the
        // chain would add a guaranteed-failing network round trip to every
        // question before the fallback could run.
        for (LlmClient client : LlmClientFactory.createChain()) {
            assertTrue(client.isConfigured(),
                    "Chain contained an unconfigured provider: " + client.providerName());
        }
    }

    @Test
    public void testChainContainsNoDuplicateProviders() {
        // The primary is added first and then skipped in the fallback sweep;
        // a regression there would make the same failing provider be retried
        // twice before moving on.
        List<LlmClient> chain = LlmClientFactory.createChain();
        for (int i = 0; i < chain.size(); i++) {
            for (int j = i + 1; j < chain.size(); j++) {
                assertFalse(chain.get(i).providerName().equals(chain.get(j).providerName()),
                        "Provider appears twice in the chain: " + chain.get(i).providerName());
            }
        }
    }

    @Test
    public void testCreateReturnsTheHeadOfTheChain() {
        List<LlmClient> chain = LlmClientFactory.createChain();
        LlmClient primary = LlmClientFactory.create();

        if (chain.isEmpty()) {
            assertTrue(primary == null, "create() must be null when the chain is empty");
        } else {
            assertTrue(primary != null && primary.providerName().equals(chain.get(0).providerName()),
                    "create() must return the first client in the chain");
        }
    }

    @Test
    public void testLocalOpenAiCompatibleEndpointNeedsNoKey() {
        // Ollama / LM Studio run locally with no auth. Requiring a key there
        // would make the most genuinely free option unusable.
        LlmClient local = new OpenAiCompatibleClient(
                "", "llama3", "http://localhost:11434/v1", "Local");
        assertTrue(local.isConfigured(),
                "A localhost endpoint should be usable without an API key");

        LlmClient remote = new OpenAiCompatibleClient(
                "", "gpt-4o-mini", "https://api.openai.com/v1", "OPENAI");
        assertFalse(remote.isConfigured(),
                "A remote endpoint must still require an API key");
    }
}
