package com.mycompany.asset_management_system_ams;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

import jakarta.servlet.http.HttpSession;

import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Test;
import org.mockito.MockedStatic;
import org.mockito.Mockito;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertTrue;

/**
 * CopilotContextUnderstandingTest — locks the "understand meaning, not
 * keywords" behaviour of the Copilot's LLM reasoning path (CopilotAgentLoop)
 * and its fallback-path equivalent (CopilotSessionMemory).
 *
 * WHY THESE TESTS AND NOT OTHERS: the model's own semantic reasoning (does it
 * *actually* explain recursion well to a beginner?) cannot be asserted
 * deterministically without a live LLM call, which is slow, costs money, and
 * is exactly the kind of external dependency a unit suite should not have.
 * What CAN be locked deterministically - and is exactly what was silently
 * broken before this change - is the ARCHITECTURE around the model:
 *
 *   - does the model actually receive the prior conversation turns it needs
 *     to resolve "it", "the second one", "what about last month"?
 *   - does the system prompt actually instruct meaning-first interpretation,
 *     constraint preservation, and asking rather than guessing?
 *   - does a different wording of the same request reach the model verbatim,
 *     rather than being pre-filtered or rewritten by a keyword layer?
 *   - does provider failover carry that same context forward?
 *   - does the tool round trip (plan -> execute -> reason) actually feed real
 *     data back, and does a model that never stops asking for tools get cut
 *     off instead of hanging the request?
 *   - for the keyword-fallback path only (used when no LLM is configured):
 *     does its structured follow-up mechanism correctly resolve "what about
 *     the IT department?" the way the LLM path resolves it by reading context?
 *
 * FakeLlmClient stands in for a real provider so every test here runs
 * offline, with no API key and no network call - the same reason
 * LlmClientFactory.createChain() is mocked rather than really invoked.
 */
public class CopilotContextUnderstandingTest {

    private static final String ROLE = "SUPER_ADMIN";

    /**
     * A couple of tests below feed CopilotAgentLoop a fake "rate limited"
     * error response (e.g. FakeLlmClient "BROKEN"/"DOWN") to exercise
     * failover - which, since LlmProviderCooldown was added, now really does
     * record a cooldown against that provider NAME in shared static state.
     * Since Surefire commonly reuses one JVM across test classes, a stray
     * provider name reused elsewhere (any future test, in this file or
     * another) could otherwise be silently skipped by a leftover cooldown
     * from a completely unrelated test. Reset after every test here so
     * nothing this file does can ever leak into another test's run.
     */
    @AfterEach
    public void resetProviderCooldownState() {
        LlmProviderCooldown.clear();
    }

    // ─────────────────────────────────────────────────────────────────────
    // Test doubles
    // ─────────────────────────────────────────────────────────────────────

    /**
     * Records every LlmRequest it is asked to answer and replies from a
     * scripted queue (repeating the last entry once exhausted) - lets a test
     * see exactly what CopilotAgentLoop sent the model, with no network call
     * or real provider key required.
     */
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

        LlmRequest lastRequest() {
            return received.get(received.size() - 1);
        }
    }

    /** Mockito mock of HttpSession backed by a real Map, so state persists across calls. */
    private static HttpSession fakeSession() {
        HttpSession session = Mockito.mock(HttpSession.class);
        Map<String, Object> attrs = new HashMap<String, Object>();
        Mockito.when(session.getAttribute(Mockito.anyString()))
                .thenAnswer(inv -> attrs.get(inv.getArgument(0, String.class)));
        Mockito.doAnswer(inv -> {
            attrs.put(inv.getArgument(0, String.class), inv.getArgument(1));
            return null;
        }).when(session).setAttribute(Mockito.anyString(), Mockito.any());
        Mockito.doAnswer(inv -> {
            attrs.remove(inv.getArgument(0, String.class));
            return null;
        }).when(session).removeAttribute(Mockito.anyString());
        return session;
    }

    private static String textOf(LlmMessage m) {
        return m.text;
    }

    // ─────────────────────────────────────────────────────────────────────
    // 1. Conversation context / reference resolution plumbing
    // ─────────────────────────────────────────────────────────────────────

    @Test
    public void testPriorTurnsAreReplayedSoReferencesCanResolve() {
        // The exact "What is React?" -> "How does it handle state?" pattern,
        // applied to this domain: "how many laptops are there?" -> "what
        // about desktops?" must not need the word "desktop" repeated with
        // "count" for the model to know what is being asked.
        HttpSession session = fakeSession();
        CopilotChatMemory.record(session, 0, "how many laptops are there?",
                "There are 42 laptops recorded in IR-AMS.");

        FakeLlmClient client = new FakeLlmClient("FAKE", LlmResponse.text("There are 17 desktops."));

        try (MockedStatic<LlmClientFactory> factory = Mockito.mockStatic(LlmClientFactory.class)) {
            factory.when(LlmClientFactory::createChain).thenReturn(List.<LlmClient>of(client));

            String answer = CopilotAgentLoop.answer("what about desktops?", 0, "Subham", ROLE, session);
            assertEquals("There are 17 desktops.", answer);
        }

        List<LlmMessage> sent = client.lastRequest().messages;
        assertTrue(sent.size() >= 3,
                "Expected the prior question, the prior answer, and the new question - got " + sent.size());
        assertEquals("how many laptops are there?", textOf(sent.get(0)),
                "The earlier question must be replayed so 'what about desktops?' has something to attach to");
        assertEquals("There are 42 laptops recorded in IR-AMS.", textOf(sent.get(1)));
        assertEquals("what about desktops?", textOf(sent.get(sent.size() - 1)));
    }

    @Test
    public void testNewTurnIsRecordedForTheNextFollowUp() {
        HttpSession session = fakeSession();
        FakeLlmClient client = new FakeLlmClient("FAKE", LlmResponse.text("42 laptops."));

        try (MockedStatic<LlmClientFactory> factory = Mockito.mockStatic(LlmClientFactory.class)) {
            factory.when(LlmClientFactory::createChain).thenReturn(List.<LlmClient>of(client));
            CopilotAgentLoop.answer("how many laptops are there?", 0, "Subham", ROLE, session);
        }

        List<LlmMessage> recent = CopilotChatMemory.recent(session, 0, 6);
        assertEquals(2, recent.size(), "Question + answer should now be in history for the NEXT follow-up");
        assertEquals("how many laptops are there?", textOf(recent.get(0)));
        assertEquals("42 laptops.", textOf(recent.get(1)));
    }

    // ─────────────────────────────────────────────────────────────────────
    // 2. System prompt instructs meaning-first, context-aware, constraint-
    //    preserving, clarification-seeking behaviour (regression lock)
    // ─────────────────────────────────────────────────────────────────────

    @Test
    public void testSystemPromptTellsTheModelToReadMeaningNotKeywords() {
        String prompt = captureSystemPrompt();
        assertTrue(prompt.contains("MEANING, not from which words"),
                "System prompt should explicitly steer away from keyword matching. Actual:\n" + prompt);
        assertTrue(prompt.toLowerCase().contains("how many assets were added yesterday"),
                "The exact false-positive class from the original bug report should be named as an example");
    }

    @Test
    public void testSystemPromptTellsTheModelToUseConversationContext() {
        String prompt = captureSystemPrompt();
        assertTrue(prompt.contains("pronouns") && prompt.contains("previous"),
                "System prompt should instruct pronoun/reference resolution via prior turns. Actual:\n" + prompt);
    }

    @Test
    public void testSystemPromptTellsTheModelToPreserveConstraintsAndAskWhenAmbiguous() {
        // Stale, found while working on a related fix: this asserted on a
        // "REQUIREMENTS AND CONSTRAINTS" heading from an earlier version of
        // the prompt. buildSystemPrompt() was since rewritten into the
        // four-stage PLAN/ACT/OBSERVE/SELF-CORRECT framework, which still
        // covers the same substance (stage 4 explicitly checks "does it
        // honor every constraint the user stated") under different wording -
        // so this test was silently failing (not silently passing on
        // weaker behaviour), which is the safer direction to fail in but
        // still means the guard was providing zero coverage. Matched to the
        // current wording instead of a defunct section title.
        String prompt = captureSystemPrompt();
        assertTrue(prompt.contains("honor every constraint the user stated"),
                "System prompt should have explicit instruction to honour stated constraints. Actual:\n" + prompt);
        assertTrue(prompt.contains("clarifying question"),
                "System prompt should tell the model to ask rather than guess when genuinely ambiguous");
    }

    @Test
    public void testSystemPromptForbidsNarratingAToolCallInsteadOfMakingIt() {
        // Fault, found live: asked "how many assets were added this month?",
        // the model found no tool parameter for "added" (a real, separate
        // gap - see the addedAfter/addedBefore fix) and, instead of calling
        // search_assets anyway or saying plainly it could not filter that
        // way, sent back a description of its own reasoning ("This function
        // call will return... we need to use the purchasedAfter and
        // purchasedBefore parameters...") as if that prose were the answer.
        // The missing parameter is now fixed, but the model narrating a plan
        // instead of acting on it is a separate failure mode worth guarding
        // against directly, independent of any one missing parameter.
        String prompt = captureSystemPrompt();
        assertTrue(prompt.contains("Never describe what a tool call WOULD do"),
                "System prompt should explicitly forbid narrating a plan instead of executing it. "
                        + "Actual:\n" + prompt);
    }

    @Test
    public void testSystemPromptIncludesAPreReplySelfCheck() {
        // Same drift as testSystemPromptTellsTheModelToPreserveConstraintsAndAskWhenAmbiguous
        // above - "BEFORE YOU REPLY" was an older heading; the self-check is
        // now stage 4 ("SELF-CORRECT, then answer... check the draft against
        // the question one more time... If any check fails, revise before
        // sending").
        String prompt = captureSystemPrompt();
        assertTrue(prompt.contains("check the draft against the question"),
                "System prompt should ask the model to check its own draft against the question before "
                        + "sending it. Actual:\n" + prompt);
    }

    @Test
    public void testSystemPromptIncludesEveryModuleTheRoleCanSee() {
        // Fault: the agent loop previously only knew its raw tool list, with
        // no curated explanation of what each IR-AMS module actually IS or
        // which questions belong to it - "what can the QR Control Center
        // do?" had nothing grounded to answer from. The module reference
        // block (from CopilotProjectModuleRegistry, previously used only by
        // the keyword-fallback pipeline) fixes that.
        String prompt = captureSystemPrompt();
        assertTrue(prompt.contains("SCOPE"),
                "System prompt should have an explicit SCOPE section establishing broad AMS coverage");
        assertTrue(prompt.contains("QR Control Center"),
                "The module reference block should list every module the role can see. Actual:\n" + prompt);
        assertTrue(prompt.contains("Physical Verification"),
                "The module reference block should list every module the role can see. Actual:\n" + prompt);
    }

    @Test
    public void testModuleRegistryHidesRoleRestrictedModulesFromLowerRoles() {
        // Same role-filtering guarantee CopilotToolCatalog.forRole() already
        // gives at the tool level, now also applied to the module reference
        // the system prompt is built from - an EMPLOYEE must never be told
        // "you can use the Audit module" even as background knowledge.
        List<CopilotProjectModuleRegistry.ModuleDescriptor> employeeModules =
                CopilotProjectModuleRegistry.getModulesForRole("EMPLOYEE");
        List<String> names = new ArrayList<String>();
        for (CopilotProjectModuleRegistry.ModuleDescriptor m : employeeModules) {
            names.add(m.moduleName);
        }
        assertTrue(!names.contains("Audit"), "EMPLOYEE must not see the Audit module in its reference");
        assertTrue(!names.contains("Settings"), "EMPLOYEE must not see the Settings module in its reference");
        assertTrue(!names.contains("Role & Duty Assignment"),
                "EMPLOYEE must not see the Role & Duty Assignment module in its reference");
        assertTrue(names.contains("Assets"), "EMPLOYEE should still see ordinary modules like Assets");
    }

    private static String captureSystemPrompt() {
        FakeLlmClient client = new FakeLlmClient("FAKE", LlmResponse.text("ok"));
        try (MockedStatic<LlmClientFactory> factory = Mockito.mockStatic(LlmClientFactory.class)) {
            factory.when(LlmClientFactory::createChain).thenReturn(List.<LlmClient>of(client));
            CopilotAgentLoop.answer("anything", 0, "Subham", ROLE, fakeSession());
        }
        return client.lastRequest().systemPrompt;
    }

    // ─────────────────────────────────────────────────────────────────────
    // 3. Paraphrases of the same request reach the model unmodified
    // ─────────────────────────────────────────────────────────────────────

    @Test
    public void testDifferentPhrasingsOfTheSameRequestReachTheModelVerbatim() {
        // "Can you make this easier to understand?" / "ELI5 this." / "Explain
        // this in simple words." are the same intent worded differently -
        // none of them should be rewritten, truncated, or matched against a
        // fixed phrase list before the model ever sees them.
        for (String phrasing : new String[]{
                "Can you make this easier to understand?",
                "ELI5 this.",
                "Explain this in simple words.",
                "Can you dumb this down?"
        }) {
            FakeLlmClient client = new FakeLlmClient("FAKE", LlmResponse.text("(explained)"));
            try (MockedStatic<LlmClientFactory> factory = Mockito.mockStatic(LlmClientFactory.class)) {
                factory.when(LlmClientFactory::createChain).thenReturn(List.<LlmClient>of(client));
                CopilotAgentLoop.answer(phrasing, 0, "Subham", ROLE, fakeSession());
            }
            List<LlmMessage> sent = client.lastRequest().messages;
            assertEquals(phrasing, textOf(sent.get(sent.size() - 1)),
                    "The user's exact wording must reach the model, not a keyword-normalized version of it");
        }
    }

    // ─────────────────────────────────────────────────────────────────────
    // 4. Provider failover keeps the conversation intact
    // ─────────────────────────────────────────────────────────────────────

    @Test
    public void testFailoverToSecondProviderCarriesTheFullConversationForward() {
        HttpSession session = fakeSession();
        CopilotChatMemory.record(session, 0, "how many laptops are there?", "42 laptops.");

        FakeLlmClient broken = new FakeLlmClient("BROKEN", LlmResponse.error("rate limited"));
        FakeLlmClient backup = new FakeLlmClient("BACKUP", LlmResponse.text("17 desktops."));

        try (MockedStatic<LlmClientFactory> factory = Mockito.mockStatic(LlmClientFactory.class)) {
            factory.when(LlmClientFactory::createChain).thenReturn(List.<LlmClient>of(broken, backup));

            String answer = CopilotAgentLoop.answer("what about desktops?", 0, "Subham", ROLE, session);
            assertEquals("17 desktops.", answer);
        }

        List<LlmMessage> sentToBackup = backup.lastRequest().messages;
        assertEquals("how many laptops are there?", textOf(sentToBackup.get(0)),
                "The provider that took over must not lose the conversation the first provider already had");
        assertEquals("what about desktops?", textOf(sentToBackup.get(sentToBackup.size() - 1)));
    }

    @Test
    public void testProviderAlreadyKnownToBeRateLimitedIsSkippedWithoutBeingCalledAtAll() {
        // Deliberately gives "primary" a SUCCESS script - if it were actually
        // called, the test would still pass on the answer alone, which would
        // hide the real bug this guards against. Asserting primary.received
        // is empty is what actually proves the skip happened, not a retry.
        FakeLlmClient primary = new FakeLlmClient("PRIMARY", LlmResponse.text("should never be reached"));
        FakeLlmClient secondary = new FakeLlmClient("SECONDARY", LlmResponse.text("42 laptops."));

        Map<String, String> headers = new HashMap<String, String>();
        headers.put("retry-after", "30");
        LlmProviderCooldown.recordRateLimited("PRIMARY", headers);

        try (MockedStatic<LlmClientFactory> factory = Mockito.mockStatic(LlmClientFactory.class)) {
            factory.when(LlmClientFactory::createChain).thenReturn(List.<LlmClient>of(primary, secondary));

            String answer = CopilotAgentLoop.answer("how many laptops are there?", 0, "Subham", ROLE, fakeSession());
            assertEquals("42 laptops.", answer);
        }

        assertTrue(primary.received.isEmpty(),
                "A provider already known to be rate-limited must be skipped entirely, not called and failed again.");
        assertEquals(1, secondary.received.size());
    }

    @Test
    public void testTheLastRemainingProviderIsStillTriedEvenWhileCoolingDown() {
        // A cooldown must never make the Copilot give up on a question it
        // could otherwise answer - if every configured provider happens to
        // be marked as rate-limited, the last one is tried anyway rather
        // than the request failing on a stale guess about its availability.
        FakeLlmClient onlyOption = new FakeLlmClient("ONLY", LlmResponse.text("42 laptops."));

        Map<String, String> headers = new HashMap<String, String>();
        headers.put("retry-after", "30");
        LlmProviderCooldown.recordRateLimited("ONLY", headers);

        try (MockedStatic<LlmClientFactory> factory = Mockito.mockStatic(LlmClientFactory.class)) {
            factory.when(LlmClientFactory::createChain).thenReturn(List.<LlmClient>of(onlyOption));

            String answer = CopilotAgentLoop.answer("how many laptops are there?", 0, "Subham", ROLE, fakeSession());
            assertEquals("42 laptops.", answer);
        }

        assertEquals(1, onlyOption.received.size(),
                "The only configured provider must still be tried, cooldown or not.");
    }

    // ─────────────────────────────────────────────────────────────────────
    // 5. Tool round trip: plan -> execute -> reason -> answer
    // ─────────────────────────────────────────────────────────────────────

    @Test
    public void testToolResultIsFedBackAndModelAnswersFromIt() {
        Map<String, String> args = new LinkedHashMap<String, String>();
        args.put("category", "Laptop");
        LlmToolCall call = new LlmToolCall("call_1", "search_assets", args);

        FakeLlmClient client = new FakeLlmClient("FAKE",
                LlmResponse.tools("", List.of(call)),
                LlmResponse.text("Here are the laptops."));

        try (MockedStatic<LlmClientFactory> factory = Mockito.mockStatic(LlmClientFactory.class)) {
            factory.when(LlmClientFactory::createChain).thenReturn(List.<LlmClient>of(client));
            String answer = CopilotAgentLoop.answer("show me the laptops", 0, "Subham", ROLE, fakeSession());
            assertEquals("Here are the laptops.", answer);
        }

        // The second call to the model must include the tool call it made and
        // the (really CopilotToolCatalog-executed) result, not just the raw
        // question again.
        List<LlmMessage> secondRequest = client.received.get(1).messages;
        boolean sawToolResult = secondRequest.stream()
                .anyMatch(m -> m.role == LlmMessage.Role.TOOL_RESULT && "search_assets".equals(m.toolName));
        assertTrue(sawToolResult, "The executed tool's result must be replayed back to the model");
    }

    // ─────────────────────────────────────────────────────────────────────
    // 6. The tool-round cap stops a runaway loop instead of hanging
    // ─────────────────────────────────────────────────────────────────────

    @Test
    public void testIterationCapStopsAModelThatNeverStopsCallingTools() {
        Map<String, String> args = new LinkedHashMap<String, String>();
        args.put("category", "Laptop");
        LlmToolCall call = new LlmToolCall("call_x", "search_assets", args);

        // Every single response asks for another tool call - it never finalizes.
        FakeLlmClient stubborn = new FakeLlmClient("STUBBORN",
                LlmResponse.tools("", List.of(call)),
                LlmResponse.tools("", List.of(call)),
                LlmResponse.tools("", List.of(call)),
                LlmResponse.tools("", List.of(call)),
                LlmResponse.tools("", List.of(call)),
                LlmResponse.tools("", List.of(call)));

        try (MockedStatic<LlmClientFactory> factory = Mockito.mockStatic(LlmClientFactory.class)) {
            factory.when(LlmClientFactory::createChain).thenReturn(List.<LlmClient>of(stubborn));
            String answer = CopilotAgentLoop.answer("show me the laptops", 0, "Subham", ROLE, fakeSession());

            // Must not hang or loop forever - and must not return null either.
            // null used to mean "silently fall back to the keyword pipeline",
            // which for a model this confused produced wrong, fragment-matched
            // answers with no indication anything had gone wrong. A model that
            // still demands tool calls even on the forced final attempt (tools
            // turned off) is exhibiting the same "can't get a usable answer"
            // failure as a real provider outage, so it gets the same honest
            // message instead.
            assertEquals(CopilotAgentLoop.PROVIDER_UNAVAILABLE_MESSAGE, answer,
                    "A model that never stops calling tools, even with tools disabled on the "
                            + "forced final attempt, must end in the same honest unavailability "
                            + "message as a real provider outage - not hang, and not silently "
                            + "fall back to the keyword pipeline");
        }
    }

    // ─────────────────────────────────────────────────────────────────────
    // 7. Fallback-path reference resolution: CopilotSessionMemory
    //
    // What CopilotAgentLoop gets for free by replaying real conversation
    // text, the keyword-fallback path (used only when no LLM is configured)
    // gets from this structured "inherit last entities, let anything new
    // override" mechanism - the no-LLM equivalent of resolving "what about
    // the IT department?".
    // ─────────────────────────────────────────────────────────────────────

    @Test
    public void testFallbackFollowUpInheritsPriorEntitiesAndOverridesWithNewOnes() {
        HttpSession session = fakeSession();

        CopilotQueryPlan last = new CopilotQueryPlan();
        last.rawUserMessage = "employees in stores department";
        last.intent = CopilotIntentType.DEPARTMENT_EMPLOYEES;
        last.departmentName = "Stores";
        CopilotSessionMemory.save(session, last, Map.of("records", List.of()), "Stores employees");

        CopilotQueryPlan next = new CopilotQueryPlan();
        next.rawUserMessage = "what about the IT department?";
        next.intent = CopilotIntentType.UNKNOWN; // nothing scored - context must supply it

        assertTrue(CopilotSessionMemory.isFollowUp(session, next));

        // Simulate the entity resolver having picked up "IT" before the merge.
        next.departmentName = "IT Centre";
        CopilotQueryPlan merged = CopilotSessionMemory.buildFollowUpPlan(session, next);

        assertEquals(CopilotIntentType.DEPARTMENT_EMPLOYEES, merged.intent,
                "Follow-up must inherit the intent that had no keyword in the new message");
        assertEquals("IT Centre", merged.departmentName,
                "The NEW department mentioned in the follow-up must win over the inherited one");
    }

    // ─────────────────────────────────────────────────────────────────────
    // 8. Analytical-question guard: paraphrases must not hijack into a
    //    write-command's slot-filling flow
    // ─────────────────────────────────────────────────────────────────────

    // ─────────────────────────────────────────────────────────────────────
    // 8. Tool-argument canonicalization: correct arguments, not just correct
    //    tool choice - a model that reasons correctly can still supply a
    //    department name that doesn't match the DB's exact string.
    // ─────────────────────────────────────────────────────────────────────

    @Test
    public void testDepartmentArgumentIsCanonicalizedEvenWhenTheModelUsesAnAlias() {
        // The model correctly identified "IT" as the department to filter on -
        // it just didn't spell it the way the DB does. That must still work,
        // the same way CopilotEntityResolver already makes it work for the
        // keyword fallback path.
        for (String modelSaid : new String[]{"IT", "IT department", "information technology", "IT Centre"}) {
            Map<String, String> args = new LinkedHashMap<String, String>();
            args.put("department", modelSaid);
            CopilotQueryPlan plan = CopilotToolCatalog.toPlan(
                    new LlmToolCall("call_d", "search_assets", args));
            assertEquals("IT Centre", plan.departmentName,
                    "'" + modelSaid + "' should resolve to the DB's canonical department name");
        }
    }

    @Test
    public void testUnrecognisedDepartmentFallsBackToTheRawValueRatherThanDroppingTheFilter() {
        // An unrecognised name should fail to match at the DB (today's safe
        // behaviour), not silently widen the query to every department.
        Map<String, String> args = new LinkedHashMap<String, String>();
        args.put("department", "Not A Real Department");
        CopilotQueryPlan plan = CopilotToolCatalog.toPlan(
                new LlmToolCall("call_d2", "search_assets", args));
        assertEquals("Not A Real Department", plan.departmentName);
    }

    @Test
    public void testCategoryArgumentIsCanonicalized() {
        Map<String, String> args = new LinkedHashMap<String, String>();
        args.put("category", "laptops");
        CopilotQueryPlan plan = CopilotToolCatalog.toPlan(
                new LlmToolCall("call_c", "search_assets", args));
        assertEquals("Laptop", plan.normalizedCategory);
    }

    @Test
    public void testPurchaseDateConstraintReachesThePlanAsAStructuredDate() {
        // "purchased after 2023" is a real, statable constraint
        // (Requirement Preservation) - the model is asked for a clean ISO
        // date rather than us trying to regex-parse "after 2023" ourselves.
        Map<String, String> args = new LinkedHashMap<String, String>();
        args.put("purchasedAfter", "2023-01-01");
        CopilotQueryPlan plan = CopilotToolCatalog.toPlan(
                new LlmToolCall("call_p", "search_assets", args));
        assertEquals(java.time.LocalDate.of(2023, 1, 1), plan.purchasedAfter);
    }

    @Test
    public void testJoiningDateConstraintReachesThePlanAsAStructuredDateDistinctFromPurchaseDate() {
        // The employees.joining_date tool added because there was previously
        // no way to answer "who joined last month" with real data at all
        // (confirmed live). joinedAfter/Before must be its own plan fields,
        // not reused from purchasedAfter/Before (assets) or startDate/endDate
        // (record-created-at) - those are different questions about
        // different columns, same reasoning as the asset purchase-date fix.
        Map<String, String> args = new LinkedHashMap<String, String>();
        args.put("joinedAfter", "2024-01-01");
        args.put("joinedBefore", "2024-01-31");
        CopilotQueryPlan plan = CopilotToolCatalog.toPlan(
                new LlmToolCall("call_j", "get_employees_by_joining_date", args));

        assertEquals(java.time.LocalDate.of(2024, 1, 1), plan.joinedAfter);
        assertEquals(java.time.LocalDate.of(2024, 1, 31), plan.joinedBefore);
        assertNull(plan.purchasedAfter, "A joining-date constraint must not leak into the asset purchase-date fields");
        assertNull(plan.startDate, "A joining-date constraint must not leak into the record-created-at fields");
    }

    @Test
    public void testAddedDateConstraintReachesThePlanWithoutDoubleShiftingTheEndDate() {
        // Fault, found live: plan.startDate/endDate (created_at - "when was
        // this actually added to AMS") was fully wired at the SQL level in
        // both searchAssets() and searchEmployees(), but had no tool
        // parameter exposing it to the LLM at all - a model asked "how many
        // assets were added this month?" correctly noticed it had nothing to
        // express that with and got stuck narrating its own confusion
        // instead of answering. addedAfter/addedBefore close that gap.
        //
        // The end date must NOT be shifted here: both executor methods
        // already do their own +1 day at the PreparedStatement-binding site
        // to turn an inclusive end date into an exclusive "< nextDay" bound.
        // Shifting in toPlan() too would silently include one extra day on
        // every addedBefore query.
        Map<String, String> args = new LinkedHashMap<String, String>();
        args.put("addedAfter", "2026-07-01");
        args.put("addedBefore", "2026-07-31");
        CopilotQueryPlan plan = CopilotToolCatalog.toPlan(
                new LlmToolCall("call_a", "search_assets", args));

        assertEquals(java.time.LocalDate.of(2026, 7, 1), plan.startDate);
        assertEquals(java.time.LocalDate.of(2026, 7, 31), plan.endDate,
                "endDate must be the raw inclusive date the model gave, not shifted forward here - "
                        + "the executor's own PreparedStatement binding does that shift");
        assertNull(plan.purchasedAfter, "An added-date constraint must not leak into the purchase-date fields");
    }

    @Test
    public void testUnparseableDateIsDroppedNotFatal() {
        // A model that answers "early 2023" instead of an ISO date should
        // lose that one filter, not fail the whole tool call.
        Map<String, String> args = new LinkedHashMap<String, String>();
        args.put("purchasedAfter", "early 2023");
        args.put("category", "Laptop");
        CopilotQueryPlan plan = CopilotToolCatalog.toPlan(
                new LlmToolCall("call_p2", "search_assets", args));
        assertNull(plan.purchasedAfter);
        assertEquals("Laptop", plan.normalizedCategory, "Other arguments must still parse normally");
    }

    // ─────────────────────────────────────────────────────────────────────
    // 9. Analytical-question guard: paraphrases must not hijack into a
    //    write-command's slot-filling flow
    // ─────────────────────────────────────────────────────────────────────

    @Test
    public void testCommonEnglishWordsDoNotFalsePositiveAsDepartmentAbbreviations() {
        // Found live: "me" was registered as an alias for the "Mechanical"
        // department, and extractDepartment() word-boundary-matches every
        // alias regardless of how common the word is in ordinary English.
        // "Show me the old ones." (no department mentioned at all) resolved
        // department -> "Mechanical" purely because it contains "me" - the
        // exact same class of bug as CopilotCommandDetector matching "add"
        // inside "added", just one level deeper in the pipeline.
        for (String query : new String[]{
                "Show me the old ones.",
                "Can you tell me the total cost?",
                "Please give me a summary.",
                "Notify me about warranty expiry."
        }) {
            assertNull(CopilotEntityResolver.extractDepartment(query),
                    "'" + query + "' does not mention any department - 'me' must not resolve to Mechanical");
        }
        // The department must still resolve when actually meant.
        assertEquals("Mechanical", CopilotEntityResolver.extractDepartment("assets in mechanical department"));
    }

    @Test
    public void testPastTenseQuestionsAboutSeveralEntitiesNeverRouteToACreateCommand() {
        String[] paraphrasesOfTheSameAnalyticalQuestion = {
                "how many assets added yesterday?",
                "how many employees added this month?",
                "any maintenance done yesterday?",
                "any allocation done this month?",
                "were there any assets added last week",
                "did anyone add an employee today",
                "has anyone added a new asset this week"
        };
        for (String query : paraphrasesOfTheSameAnalyticalQuestion) {
            CopilotCommandPlan plan = CopilotCommandDetector.detectCommand(query);
            assertNull(plan, "'" + query + "' is a question about the past, not an instruction - "
                    + "must not be routed into a create/add command's slot-filling flow");
        }
    }

    // ─────────────────────────────────────────────────────────────────────
    // 10. Session-invalidation robustness (found via live testing)
    //
    // A session that dies mid-request (timeout, redeploy, logout in another
    // tab, or simply outliving a slow multi-provider LLM fallback chain)
    // makes EVERY method on it throw IllegalStateException, not return null.
    // Live reproduction: all 3 configured LLM providers rate-limited back to
    // back (a real ~30s round trip), CopilotAgentLoop correctly fell back to
    // the keyword pipeline, and CopilotReasoningPlanner's unguarded
    // session.getAttribute("role") then threw, turning a normal "use the
    // fallback" path into "I could not complete this AMS lookup due to an
    // internal server issue" for a perfectly good question.
    // ─────────────────────────────────────────────────────────────────────

    /** An HttpSession mock that throws IllegalStateException on every method, like a dead Tomcat session does. */
    private static HttpSession invalidatedSession() {
        HttpSession session = Mockito.mock(HttpSession.class);
        Mockito.when(session.getAttribute(Mockito.anyString()))
                .thenThrow(new IllegalStateException("getAttribute: Session already invalidated"));
        Mockito.doThrow(new IllegalStateException("setAttribute: Session already invalidated"))
                .when(session).setAttribute(Mockito.anyString(), Mockito.any());
        Mockito.doThrow(new IllegalStateException("removeAttribute: Session already invalidated"))
                .when(session).removeAttribute(Mockito.anyString());
        return session;
    }

    @Test
    public void testReasoningPlannerSurvivesAnInvalidatedSession() {
        CopilotQueryPlan raw = new CopilotQueryPlan();
        raw.rawUserMessage = "how many laptops are there?";
        raw.normalizedTextForNLU = "how many laptops are there";
        raw.intent = CopilotIntentType.ASSET_COUNT;
        raw.confidence = 0.8;

        CopilotQueryPlan result = CopilotReasoningPlanner.plan(raw, invalidatedSession());

        assertTrue(result != null, "A dead session must degrade to 'no session context', not throw");
        assertEquals(CopilotIntentType.ASSET_COUNT, result.intent,
                "The plan itself should be unaffected by a session that can't be read");
    }

    @Test
    public void testSessionMemorySaveAndReadSurviveAnInvalidatedSession() {
        HttpSession dead = invalidatedSession();
        CopilotQueryPlan plan = new CopilotQueryPlan();
        plan.rawUserMessage = "show laptops";
        plan.intent = CopilotIntentType.ASSET_SEARCH;

        // None of these may throw - a dead session should behave like no
        // session was ever saved to, the same graceful-degrade CopilotEngine
        // already relies on for session == null.
        CopilotSessionMemory.save(dead, plan, Map.of("records", List.of()), "title");
        assertNull(CopilotSessionMemory.loadLastPlan(dead));
        assertNull(CopilotSessionMemory.getLastIntent(dead));
        assertTrue(!CopilotSessionMemory.isLastResultExportable(dead));
        assertEquals(0, CopilotSessionMemory.getLastRowCount(dead));
        CopilotSessionMemory.clear(dead);
    }

    @Test
    public void testChatMemorySurvivesAnInvalidatedSession() {
        HttpSession dead = invalidatedSession();

        // Must not throw, and must come back with "no history" rather than
        // half-written state.
        CopilotChatMemory.record(dead, 0, "question", "answer");
        List<LlmMessage> recent = CopilotChatMemory.recent(dead, 0, 6);
        assertTrue(recent.isEmpty(), "A dead session has no readable history, not a half-saved turn");
        CopilotChatMemory.clear(dead);
    }

    @Test
    public void testUnreadableRoleFailsClosedNotOpen() {
        // The security-relevant half of this fix: CopilotToolExecutor's row-
        // scoping ("EMPLOYEE".equalsIgnoreCase(role) -> restrict to the
        // caller's own records) previously read role via a helper that
        // returned null for BOTH session == null and a dead session, and
        // every scoping check treated null as "not an employee" - i.e.
        // UNRESTRICTED. An indeterminate session must restrict (or deny),
        // never silently widen, what a caller can read.
        CopilotQueryPlan plan = new CopilotQueryPlan();
        plan.intent = CopilotIntentType.ASSET_SEARCH;

        Map<String, Object> result = CopilotToolExecutor.searchAssets(plan, invalidatedSession());

        assertTrue(result.containsKey("error"),
                "An unreadable role must fail closed (denied), not fail open (unrestricted org-wide data). "
                        + "Actual result: " + result);
    }

    @Test
    public void testFullFallbackPipelineAnswersInsteadOfCrashingOnADeadSession() {
        // The exact live failure, end to end: the agent loop already gave up
        // (chain exhausted -> returns null, simulated here by an empty
        // chain), and the keyword-fallback pipeline behind it must still
        // produce a real answer instead of CopilotEngine's generic
        // "internal server issue" catch-all.
        try (MockedStatic<LlmClientFactory> factory = Mockito.mockStatic(LlmClientFactory.class)) {
            factory.when(LlmClientFactory::createChain).thenReturn(List.<LlmClient>of());

            CopilotEngine.CopilotResponse response = CopilotEngine.answer(
                    "how many laptops are there?", 1, "Subham", ROLE, invalidatedSession());

            assertTrue(response != null && response.answer != null && !response.answer.isEmpty());
            assertTrue(!"ERROR".equals(response.mode),
                    "A dead session should not turn a normal fallback answer into a hard error. Got: "
                            + response.mode + " / " + response.answer);
        }
    }

    @Test
    public void testAiUnavailableFallsBackToLabeledKeywordAnswerNotSilentWrongOne() {
        // Every provider genuinely FAILS (not "nothing configured" - that's
        // the test above) -> CopilotAgentLoop returns PROVIDER_UNAVAILABLE_MESSAGE,
        // a distinct signal from null. CopilotEngine must not show that bare
        // message when the keyword pipeline can actually answer a simple,
        // single-intent question like this one; it must show the keyword
        // pipeline's real answer, clearly labeled as a lower-fidelity
        // fallback - not silently, and not replaced by a dead end either.
        FakeLlmClient down = new FakeLlmClient("DOWN", LlmResponse.error("rate limited"));

        try (MockedStatic<LlmClientFactory> factory = Mockito.mockStatic(LlmClientFactory.class)) {
            factory.when(LlmClientFactory::createChain).thenReturn(List.<LlmClient>of(down));

            CopilotEngine.CopilotResponse response = CopilotEngine.answer(
                    "how many laptops are there?", 1, "Subham", ROLE, fakeSession());

            assertTrue(response != null && response.answer != null && !response.answer.isEmpty());
            assertTrue(response.answer.startsWith("⚠️"),
                    "A real keyword-pipeline answer shown only because the AI is down must be "
                            + "clearly labeled as a lower-fidelity fallback, not indistinguishable "
                            + "from a full AI response. Got: " + response.answer);
            assertTrue(!response.answer.equals(CopilotAgentLoop.PROVIDER_UNAVAILABLE_MESSAGE),
                    "When the keyword pipeline CAN answer, it must not be replaced by the bare "
                            + "unavailability message - that message is reserved for when neither "
                            + "path can help.");
        }
    }

    // ─────────────────────────────────────────────────────────────────────
    // 8. Null tool-call arguments must be treated as absent, not the
    //    literal string "null"
    // ─────────────────────────────────────────────────────────────────────

    @Test
    public void testOpenAiCompatibleClientTreatsJsonNullArgumentAsAbsentNotTheStringNull() {
        // Fault, found live: every LlmToolSpec param is optional (this
        // catalog has no "required" concept), and a model that decides not
        // to use one commonly emits a literal JSON null for it instead of
        // omitting the key. org.json represents that as the JSONObject.NULL
        // singleton, and the old code did String.valueOf(JSONObject.NULL) ->
        // the four-character text "null", which CopilotToolCatalog.toPlan()
        // then treated as a real (nonsense) category filter instead of "no
        // filter". Confirmed live via NVIDIA's OpenAI-compatible endpoint.
        OpenAiCompatibleClient client =
                new OpenAiCompatibleClient("fake-key", "fake-model", "https://example.test/v1", "TEST");
        String body = "{\"choices\":[{\"message\":{\"content\":\"\",\"tool_calls\":[{\"id\":\"call_1\","
                + "\"type\":\"function\",\"function\":{\"name\":\"search_assets\","
                + "\"arguments\":\"{\\\"category\\\":\\\"Laptop\\\",\\\"department\\\":null}\"}}]}}]}";

        LlmResponse response = client.parseResponse(body);

        assertTrue(response.hasToolCalls());
        LlmToolCall call = response.toolCalls.get(0);
        assertEquals("Laptop", call.arg("category"));
        assertEquals("", call.arg("department"),
                "A JSON null argument must be treated as absent (empty), not stringified into "
                        + "the literal text \"null\"");
    }

    @Test
    public void testGeminiClientTreatsJsonNullArgumentAsAbsentNotTheStringNull() {
        // Same fault as the OpenAI-compatible path above, found on Gemini's
        // own args object during the same investigation.
        GeminiClient client = new GeminiClient("fake-key", "fake-model");
        String body = "{\"candidates\":[{\"content\":{\"parts\":[{\"functionCall\":{"
                + "\"name\":\"search_assets\",\"args\":{\"category\":\"Laptop\",\"department\":null}}}]}}]}";

        LlmResponse response = client.parseResponse(body);

        assertTrue(response.hasToolCalls());
        LlmToolCall call = response.toolCalls.get(0);
        assertEquals("Laptop", call.arg("category"));
        assertEquals("", call.arg("department"),
                "A JSON null argument must be treated as absent (empty), not stringified into "
                        + "the literal text \"null\"");
    }

    // ─────────────────────────────────────────────────────────────────────
    // 9. Cross-provider failover must not hand Gemini a functionCall it
    //    cannot validate (missing thought_signature)
    // ─────────────────────────────────────────────────────────────────────

    @Test
    public void testGeminiClientDowngradesUnsignedToolCallHistoryToPlainTextInsteadOfNativeFunctionCall() {
        // Fault, found live: a mid-conversation provider failover (Groq made
        // a tool call, then errored on the NEXT round, and Gemini took over)
        // replayed that tool call into Gemini's history as a native
        // functionCall part. Gemini 3 requires every functionCall part to
        // carry a thoughtSignature IT ISSUED - one from a different provider
        // does not exist and cannot be forged, so Gemini hard-400'd:
        // "Function call is missing a thought_signature...". A call with no
        // thoughtSignature (thoughtSignature == null, exactly what every
        // non-Gemini LlmToolCall has) must be downgraded to plain text
        // instead of a native functionCall/functionResponse pair.
        LlmToolCall unsignedCall = new LlmToolCall(
                "call_1", "get_available_assets", new LinkedHashMap<String, String>());

        LlmRequest request = new LlmRequest()
                .add(LlmMessage.user("How many available assets are there?"))
                .add(LlmMessage.toolCall(List.of(unsignedCall)))
                .add(LlmMessage.toolResult("call_1", "get_available_assets", "{\"count\":8}"));

        GeminiClient client = new GeminiClient("fake-key", "fake-model");
        String json = client.buildPayload(request).toString();

        assertTrue(!json.contains("\"functionCall\""),
                "A tool call with no Gemini thought signature must not be rendered as a native "
                        + "functionCall - Gemini cannot validate a signature it never issued");
        assertTrue(!json.contains("\"functionResponse\""),
                "The result for an unsigned tool call must not be rendered as a native "
                        + "functionResponse either - it has no valid functionCall to pair with");
        assertTrue(json.contains("get_available_assets"),
                "The tool name should still reach Gemini as plain-text context, just not as a "
                        + "native structure it must validate");
    }

    @Test
    public void testGeminiClientTellsTheModelNotToRepeatAnUnsignedToolCall() {
        // Fault, found live: the structural downgrade above stopped the 400
        // crash, but Gemini then treated the downgraded text as unverified
        // background rather than a completed lookup, and re-explored with
        // five extra tool calls (including re-calling the SAME tool) before
        // landing on the right answer anyway. The system prompt must gain an
        // explicit directive - only when there IS an unsigned call in
        // history, since this is a real per-request cost - telling the model
        // the data is real and not to repeat the lookup.
        LlmToolCall unsignedCall = new LlmToolCall(
                "call_1", "get_available_assets", new LinkedHashMap<String, String>());
        LlmRequest request = new LlmRequest()
                .system("base system prompt")
                .add(LlmMessage.user("How many available assets are there?"))
                .add(LlmMessage.toolCall(List.of(unsignedCall)))
                .add(LlmMessage.toolResult("call_1", "get_available_assets", "{\"count\":8}"));

        GeminiClient client = new GeminiClient("fake-key", "fake-model");
        String json = client.buildPayload(request).toString();

        assertTrue(json.contains("Do not call the same tool again")
                        || json.contains("do not re-call it"),
                "The request must explicitly tell the model not to repeat an already-answered "
                        + "unsigned tool call. Actual:\n" + json);

        // And the no-history case must be unaffected - no wasted tokens on
        // a directive that has nothing to apply to.
        LlmRequest freshRequest = new LlmRequest()
                .system("base system prompt")
                .add(LlmMessage.user("How many available assets are there?"));
        String freshJson = client.buildPayload(freshRequest).toString();
        assertTrue(!freshJson.contains("Do not call the same tool again"),
                "A fresh question with no cross-provider tool history should not carry the "
                        + "unsigned-call directive at all");
    }

    @Test
    public void testGeminiClientStillEchoesItsOwnSignedToolCallNatively() {
        // The other half of the same fix: a call GEMINI ITSELF made (a real
        // thoughtSignature) must still round-trip as a native functionCall,
        // with the signature echoed back byte-for-byte - that behavior
        // (fixed in an earlier pass) must not regress.
        LlmToolCall signedCall = new LlmToolCall(
                "call_2", "get_available_assets", new LinkedHashMap<String, String>(), "sig-abc123");

        LlmRequest request = new LlmRequest()
                .add(LlmMessage.user("How many available assets are there?"))
                .add(LlmMessage.toolCall(List.of(signedCall)))
                .add(LlmMessage.toolResult("call_2", "get_available_assets", "{\"count\":8}"));

        GeminiClient client = new GeminiClient("fake-key", "fake-model");
        String json = client.buildPayload(request).toString();

        assertTrue(json.contains("\"functionCall\""),
                "A call Gemini itself signed must still be echoed as a native functionCall");
        assertTrue(json.contains("sig-abc123"),
                "The thought signature must be echoed back byte-for-byte");
        assertTrue(json.contains("\"functionResponse\""),
                "The matching result for a signed call must still be a native functionResponse");
    }
}
