package com.mycompany.asset_management_system_ams;

import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

import jakarta.servlet.http.HttpSession;

import org.junit.jupiter.api.Test;
import org.mockito.MockedStatic;
import org.mockito.Mockito;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.mockStatic;
import static org.mockito.Mockito.when;

/**
 * CopilotWriteIntentClassifierTest — locks in the contract that lets natural
 * language reach the Copilot's five non-destructive write actions without
 * ever changing how they are authorized or executed:
 *
 *   - the analytical-question gate is checked BEFORE any LLM call
 *   - only the tools a role's own checkPermission() already allows are ever
 *     offered to the model (never a wider set the confirmation step would
 *     just reject anyway)
 *   - a confident "no tool call" answer is trusted, not retried on another
 *     provider
 *   - the built plan always requires confirmation and is never marked
 *     destructive (all five actions are reversible/redoable)
 *   - an unambiguous name resolves to a code; an ambiguous or absent one
 *     becomes a missing-field prompt instead of a guess
 */
public class CopilotWriteIntentClassifierTest {

    private static final class FakeLlmClient implements LlmClient {
        private final String name;
        private final List<LlmResponse> script;
        private final List<LlmRequest> received = new ArrayList<LlmRequest>();
        private int index = 0;

        FakeLlmClient(String name, LlmResponse... script) {
            this.name = name;
            this.script = List.of(script);
        }

        @Override
        public String providerName() {
            return name;
        }

        @Override
        public String modelName() {
            return "fake-model";
        }

        @Override
        public boolean isConfigured() {
            return true;
        }

        @Override
        public LlmResponse chat(LlmRequest request) {
            received.add(request);
            LlmResponse next = index < script.size() ? script.get(index) : script.get(script.size() - 1);
            index++;
            return next;
        }

        int callCount() {
            return received.size();
        }

        LlmRequest lastRequest() {
            return received.get(received.size() - 1);
        }
    }

    private static LlmToolCall toolCall(String name, Map<String, String> args) {
        return new LlmToolCall("call_1", name, args);
    }

    private static Map<String, String> args(String... kv) {
        Map<String, String> map = new LinkedHashMap<String, String>();
        for (int i = 0; i < kv.length; i += 2) {
            map.put(kv[i], kv[i + 1]);
        }
        return map;
    }

    // ─────────────────────────────────────────────────────────────────────
    // Analytical-question gate
    // ─────────────────────────────────────────────────────────────────────

    @Test
    public void testAnalyticalQuestionNeverReachesTheModel() {
        // If the gate did not short-circuit first, this client would hand
        // back a (bogus) allocate call for a plain data question - proving
        // the gate works by showing that does NOT happen.
        FakeLlmClient client = new FakeLlmClient("FAKE",
                LlmResponse.tools("", List.of(toolCall("allocate_asset", args("asset", "AST010", "employee", "EMP004")))));

        try (MockedStatic<LlmClientFactory> factory = mockStatic(LlmClientFactory.class)) {
            factory.when(LlmClientFactory::createChain).thenReturn(List.<LlmClient>of(client));

            CopilotCommandPlan plan = CopilotWriteIntentClassifier.classify(
                    "how many assets are currently allocated?", "ASSET_MANAGER", fakeSession());

            assertNull(plan, "A question must never be classified as a write action.");
            assertEquals(0, client.callCount(), "The model must never even be called for a question.");
        }
    }

    // ─────────────────────────────────────────────────────────────────────
    // Role-based tool filtering
    // ─────────────────────────────────────────────────────────────────────

    @Test
    public void testAuditorGetsNoToolsAndNeverCallsTheModel() {
        FakeLlmClient client = new FakeLlmClient("FAKE",
                LlmResponse.tools("", List.of(toolCall("allocate_asset", args("asset", "AST010", "employee", "EMP004")))));

        try (MockedStatic<LlmClientFactory> factory = mockStatic(LlmClientFactory.class)) {
            factory.when(LlmClientFactory::createChain).thenReturn(List.<LlmClient>of(client));

            CopilotCommandPlan plan = CopilotWriteIntentClassifier.classify(
                    "allocate AST010 to EMP004", "AUDITOR", fakeSession());

            assertNull(plan, "AUDITOR has no write permissions at all.");
            assertEquals(0, client.callCount(), "No tools means no reason to ever call the model.");
        }
    }

    @Test
    public void testEmployeeIsOnlyOfferedCreateMaintenanceRequest() {
        FakeLlmClient client = new FakeLlmClient("FAKE", LlmResponse.text(""));

        try (MockedStatic<LlmClientFactory> factory = mockStatic(LlmClientFactory.class)) {
            factory.when(LlmClientFactory::createChain).thenReturn(List.<LlmClient>of(client));

            CopilotWriteIntentClassifier.classify(
                    "raise a maintenance request for AST010, screen flickering", "EMPLOYEE", fakeSession());

            assertEquals(1, client.callCount());
            List<String> offeredToolNames = new ArrayList<String>();
            for (LlmToolSpec spec : client.lastRequest().tools) {
                offeredToolNames.add(spec.name);
            }
            assertEquals(List.of("create_maintenance_request"), offeredToolNames,
                    "EMPLOYEE must only ever be offered the one write action checkPermission() grants it.");
        }
    }

    @Test
    public void testAssetManagerIsOfferedAllFiveActions() {
        FakeLlmClient client = new FakeLlmClient("FAKE", LlmResponse.text(""));

        try (MockedStatic<LlmClientFactory> factory = mockStatic(LlmClientFactory.class)) {
            factory.when(LlmClientFactory::createChain).thenReturn(List.<LlmClient>of(client));

            CopilotWriteIntentClassifier.classify("do something", "ASSET_MANAGER", fakeSession());

            assertEquals(5, client.lastRequest().tools.size(),
                    "ASSET_MANAGER's checkPermission() grants all five non-EMPLOYEE/DEPARTMENT intents.");
        }
    }

    // ─────────────────────────────────────────────────────────────────────
    // Provider failover semantics
    // ─────────────────────────────────────────────────────────────────────

    @Test
    public void testConfidentNoToolCallIsNotRetriedOnAnotherProvider() {
        FakeLlmClient first = new FakeLlmClient("FIRST", LlmResponse.text("(no action)"));
        FakeLlmClient second = new FakeLlmClient("SECOND",
                LlmResponse.tools("", List.of(toolCall("allocate_asset", args("asset", "AST010", "employee", "EMP004")))));

        try (MockedStatic<LlmClientFactory> factory = mockStatic(LlmClientFactory.class)) {
            factory.when(LlmClientFactory::createChain).thenReturn(List.<LlmClient>of(first, second));

            CopilotCommandPlan plan = CopilotWriteIntentClassifier.classify(
                    "allocate AST010 to EMP004", "ASSET_MANAGER", fakeSession());

            assertNull(plan, "A confident 'no' from the first provider must be trusted.");
            assertEquals(1, first.callCount());
            assertEquals(0, second.callCount(),
                    "A second provider must not be tried after a confident non-error answer.");
        }
    }

    @Test
    public void testProviderErrorFailsOverToNextProvider() {
        FakeLlmClient broken = new FakeLlmClient("BROKEN", LlmResponse.error("rate limited"));
        FakeLlmClient backup = new FakeLlmClient("BACKUP",
                LlmResponse.tools("", List.of(toolCall("return_asset", args("asset", "AST010")))));

        try (MockedStatic<LlmClientFactory> factory = mockStatic(LlmClientFactory.class)) {
            factory.when(LlmClientFactory::createChain).thenReturn(List.<LlmClient>of(broken, backup));

            CopilotCommandPlan plan = CopilotWriteIntentClassifier.classify(
                    "return AST010", "ASSET_MANAGER", fakeSession());

            assertEquals(CopilotIntentType.RETURN_ASSET, plan.intent);
            assertEquals(1, broken.callCount());
            assertEquals(1, backup.callCount());
        }
    }

    // ─────────────────────────────────────────────────────────────────────
    // Plan building — codes given directly
    // ─────────────────────────────────────────────────────────────────────

    @Test
    public void testAllocateAssetPlanBuiltFromExplicitCodes() {
        FakeLlmClient client = new FakeLlmClient("FAKE",
                LlmResponse.tools("", List.of(toolCall("allocate_asset", args("asset", "ast010", "employee", "emp004")))));

        try (MockedStatic<LlmClientFactory> factory = mockStatic(LlmClientFactory.class)) {
            factory.when(LlmClientFactory::createChain).thenReturn(List.<LlmClient>of(client));

            CopilotCommandPlan plan = CopilotWriteIntentClassifier.classify(
                    "can you hand AST010 over to EMP004", "ASSET_MANAGER", fakeSession());

            assertEquals(CopilotIntentType.ALLOCATE_ASSET, plan.intent);
            assertEquals("ALLOCATION", plan.targetModule);
            assertEquals("AST010", plan.extractedFields.get("assetCode"));
            assertEquals("EMP004", plan.extractedFields.get("employeeCode"));
            assertTrue(plan.missingRequiredFields.isEmpty());
            assertTrue(plan.requiresConfirmation);
            assertFalse(plan.destructiveAction, "None of the five classified actions are destructive.");
        }
    }

    @Test
    public void testRejectAssetRequestPlanBuiltWithReason() {
        FakeLlmClient client = new FakeLlmClient("FAKE",
                LlmResponse.tools("", List.of(toolCall("reject_asset_request",
                        args("requestId", "42", "reason", "no budget left")))));

        try (MockedStatic<LlmClientFactory> factory = mockStatic(LlmClientFactory.class)) {
            factory.when(LlmClientFactory::createChain).thenReturn(List.<LlmClient>of(client));

            CopilotCommandPlan plan = CopilotWriteIntentClassifier.classify(
                    "reject request 42, no budget left", "ADMIN", fakeSession());

            assertEquals(CopilotIntentType.REJECT_ASSET_REQUEST, plan.intent);
            assertEquals("42", plan.extractedFields.get("targetId"));
            assertEquals("no budget left", plan.extractedFields.get("reason"));
            assertTrue(plan.missingRequiredFields.isEmpty());
        }
    }

    @Test
    public void testUnrecognisedToolNameIsTreatedAsNoAction() {
        FakeLlmClient client = new FakeLlmClient("FAKE",
                LlmResponse.tools("", List.of(toolCall("delete_everything", args()))));

        try (MockedStatic<LlmClientFactory> factory = mockStatic(LlmClientFactory.class)) {
            factory.when(LlmClientFactory::createChain).thenReturn(List.<LlmClient>of(client));

            CopilotCommandPlan plan = CopilotWriteIntentClassifier.classify(
                    "do something", "SUPER_ADMIN", fakeSession());

            assertNull(plan, "A tool name never offered must never produce a plan.");
        }
    }

    // ─────────────────────────────────────────────────────────────────────
    // Plan building — name resolution (requires a DB lookup)
    // ─────────────────────────────────────────────────────────────────────

    @Test
    public void testEmployeeNameResolvesWhenExactlyOneActiveMatch() throws Exception {
        FakeLlmClient client = new FakeLlmClient("FAKE",
                LlmResponse.tools("", List.of(toolCall("allocate_asset", args("asset", "AST010", "employee", "Priya")))));

        Connection con = mock(Connection.class);
        PreparedStatement ps = mock(PreparedStatement.class);
        ResultSet rs = mock(ResultSet.class);
        when(con.prepareStatement(anyString())).thenReturn(ps);
        when(ps.executeQuery()).thenReturn(rs);
        // Exactly one row - an unambiguous match.
        when(rs.next()).thenReturn(true, false);
        when(rs.getString(1)).thenReturn("EMP004");

        try (MockedStatic<LlmClientFactory> factory = mockStatic(LlmClientFactory.class);
             MockedStatic<DBConnection> db = mockStatic(DBConnection.class)) {
            factory.when(LlmClientFactory::createChain).thenReturn(List.<LlmClient>of(client));
            db.when(DBConnection::getConnection).thenReturn(con);

            CopilotCommandPlan plan = CopilotWriteIntentClassifier.classify(
                    "give AST010 to Priya", "ASSET_MANAGER", fakeSession());

            assertEquals("EMP004", plan.extractedFields.get("employeeCode"),
                    "An unambiguous single name match must resolve to its code.");
            assertTrue(plan.missingRequiredFields.isEmpty());
        }
    }

    @Test
    public void testAmbiguousEmployeeNameBecomesAMissingFieldNotAGuess() throws Exception {
        FakeLlmClient client = new FakeLlmClient("FAKE",
                LlmResponse.tools("", List.of(toolCall("allocate_asset", args("asset", "AST010", "employee", "Priya")))));

        Connection con = mock(Connection.class);
        PreparedStatement ps = mock(PreparedStatement.class);
        ResultSet rs = mock(ResultSet.class);
        when(con.prepareStatement(anyString())).thenReturn(ps);
        when(ps.executeQuery()).thenReturn(rs);
        // Two rows - ambiguous, must not guess either one.
        when(rs.next()).thenReturn(true, true, false);
        when(rs.getString(1)).thenReturn("EMP004", "EMP009");

        try (MockedStatic<LlmClientFactory> factory = mockStatic(LlmClientFactory.class);
             MockedStatic<DBConnection> db = mockStatic(DBConnection.class)) {
            factory.when(LlmClientFactory::createChain).thenReturn(List.<LlmClient>of(client));
            db.when(DBConnection::getConnection).thenReturn(con);

            CopilotCommandPlan plan = CopilotWriteIntentClassifier.classify(
                    "give AST010 to Priya", "ASSET_MANAGER", fakeSession());

            assertNull(plan.extractedFields.get("employeeCode"));
            assertTrue(plan.missingRequiredFields.contains("employeeCode"),
                    "An ambiguous name must prompt for clarification, never pick one of the matches.");
        }
    }

    // ─────────────────────────────────────────────────────────────────────

    private static HttpSession fakeSession() {
        return Mockito.mock(HttpSession.class);
    }
}
