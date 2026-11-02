package com.mycompany.asset_management_system_ams;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

import jakarta.servlet.http.HttpSession;

import org.junit.jupiter.api.Test;
import org.mockito.MockedStatic;
import org.mockito.Mockito;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.anyInt;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.mockStatic;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;

/**
 * CopilotChatMemoryPersistenceTest — the two-tier contract added on top of
 * CopilotChatMemory's original session-only behaviour (already covered by
 * CopilotContextUnderstandingTest, unaffected by this addition since every
 * test there passes userId=0 to opt out of the DB tier entirely):
 *
 *   - a fresh/empty session rehydrates from CopilotChatHistoryDAO when a
 *     real userId is given, and copies that history INTO the session so a
 *     second call within the same session does not hit the DB again
 *   - record() writes to both tiers - the session list (if a session is
 *     present) and CopilotChatHistoryDAO (if a real userId is given)
 *   - userId <= 0 means "skip the DB tier entirely", preserving the exact
 *     original session-only behaviour for any caller that has no
 *     authenticated user to key persistence on
 */
public class CopilotChatMemoryPersistenceTest {

    private static HttpSession fakeSession() {
        HttpSession session = Mockito.mock(HttpSession.class);
        Map<String, Object> attrs = new HashMap<String, Object>();
        Mockito.when(session.getAttribute(Mockito.anyString()))
                .thenAnswer(inv -> attrs.get(inv.getArgument(0, String.class)));
        Mockito.doAnswer(inv -> {
            attrs.put(inv.getArgument(0, String.class), inv.getArgument(1));
            return null;
        }).when(session).setAttribute(Mockito.anyString(), Mockito.any());
        return session;
    }

    @Test
    public void testEmptySessionRehydratesFromDbWhenUserIdGiven() {
        HttpSession session = fakeSession();
        List<CopilotChatMemory.Turn> fromDb = new ArrayList<CopilotChatMemory.Turn>();
        fromDb.add(new CopilotChatMemory.Turn("how many laptops?", "42 laptops."));
        fromDb.add(new CopilotChatMemory.Turn("what about desktops?", "17 desktops."));

        try (MockedStatic<CopilotChatHistoryDAO> dao = mockStatic(CopilotChatHistoryDAO.class)) {
            dao.when(() -> CopilotChatHistoryDAO.recent(42, 8)).thenReturn(fromDb);

            List<LlmMessage> messages = CopilotChatMemory.recent(session, 42, 6);

            assertEquals(4, messages.size(), "2 turns -> 4 messages (user+assistant each).");
            assertEquals("how many laptops?", messages.get(0).text);
            assertEquals("42 laptops.", messages.get(1).text);
            assertEquals("what about desktops?", messages.get(2).text);
        }
    }

    @Test
    public void testDbIsOnlyConsultedOnceThenSessionTakesOver() {
        HttpSession session = fakeSession();
        List<CopilotChatMemory.Turn> fromDb = new ArrayList<CopilotChatMemory.Turn>();
        fromDb.add(new CopilotChatMemory.Turn("q1", "a1"));

        try (MockedStatic<CopilotChatHistoryDAO> dao = mockStatic(CopilotChatHistoryDAO.class)) {
            dao.when(() -> CopilotChatHistoryDAO.recent(42, 8)).thenReturn(fromDb);

            CopilotChatMemory.recent(session, 42, 6); // 1st call: session empty, hits DB, repopulates session
            CopilotChatMemory.recent(session, 42, 6); // 2nd call: session now has history already

            dao.verify(() -> CopilotChatHistoryDAO.recent(42, 8), times(1));
        }
    }

    @Test
    public void testZeroUserIdSkipsDbTierEntirely() {
        HttpSession session = fakeSession(); // empty session, no history

        try (MockedStatic<CopilotChatHistoryDAO> dao = mockStatic(CopilotChatHistoryDAO.class)) {
            List<LlmMessage> messages = CopilotChatMemory.recent(session, 0, 6);

            assertTrue(messages.isEmpty());
            dao.verifyNoInteractions();
        }
    }

    @Test
    public void testRecordWritesToBothSessionAndDbTier() {
        HttpSession session = fakeSession();

        try (MockedStatic<CopilotChatHistoryDAO> dao = mockStatic(CopilotChatHistoryDAO.class)) {
            CopilotChatMemory.record(session, 42, "how many laptops?", "42 laptops.");

            dao.verify(() -> CopilotChatHistoryDAO.append(42, "how many laptops?", "42 laptops."));

            // The session tier must also have it, independent of the DB call -
            // a second recent() in the SAME session must not need the DB at all.
            List<LlmMessage> messages = CopilotChatMemory.recent(session, 0, 6);
            assertEquals(2, messages.size());
        }
    }

    @Test
    public void testRecordSkipsDbTierWhenUserIdIsZero() {
        HttpSession session = fakeSession();

        try (MockedStatic<CopilotChatHistoryDAO> dao = mockStatic(CopilotChatHistoryDAO.class)) {
            CopilotChatMemory.record(session, 0, "q", "a");

            dao.verify(() -> CopilotChatHistoryDAO.append(anyInt(), anyString(), anyString()), times(0));
        }
    }

    @Test
    public void testRecordWithNullSessionStillPersistsToDb() {
        try (MockedStatic<CopilotChatHistoryDAO> dao = mockStatic(CopilotChatHistoryDAO.class)) {
            // No session at all (e.g. a caller with no HttpSession available) -
            // must not throw, and the DB tier must still get the turn.
            CopilotChatMemory.record(null, 42, "q", "a");

            dao.verify(() -> CopilotChatHistoryDAO.append(42, "q", "a"));
        }
    }
}
