package com.mycompany.asset_management_system_ams;

import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.util.List;

import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.mockito.MockedStatic;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.mockStatic;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * CopilotChatHistoryDAOTest — the mocked-JDBC counterpart to the live-DB
 * smoke test run manually against a real local MySQL while building this
 * feature (insert/order/limit/trim all confirmed there). These tests lock
 * the same contract into CI, where no real database is assumed to be
 * reachable: correct chronological ordering out of a DESC-ordered query,
 * and - most importantly - that a DB failure degrades to "no history"
 * rather than breaking the caller, since CopilotChatMemory depends on that
 * to keep answering within a session even if the durability tier is down.
 */
public class CopilotChatHistoryDAOTest {

    @Test
    public void testRecentReturnsOldestFirstFromADescOrderedQuery() throws Exception {
        Connection con = mock(Connection.class);
        PreparedStatement ps = mock(PreparedStatement.class);
        ResultSet rs = mock(ResultSet.class);

        when(con.prepareStatement(anyString())).thenReturn(ps);
        when(ps.executeQuery()).thenReturn(rs);
        // The DAO's SQL orders history_id DESC (newest first) so LIMIT keeps
        // the most recent N - recent() must reverse that back to
        // chronological order before returning.
        when(rs.next()).thenReturn(true, true, true, false);
        when(rs.getString("question")).thenReturn("and printers?", "what about desktops?", "how many laptops?");
        when(rs.getString("answer")).thenReturn("5 printers.", "17 desktops.", "42 laptops.");

        try (MockedStatic<DBConnection> db = mockStatic(DBConnection.class)) {
            db.when(DBConnection::getConnection).thenReturn(con);

            List<CopilotChatMemory.Turn> turns = CopilotChatHistoryDAO.recent(1, 10);

            assertEquals(3, turns.size());
            assertEquals("how many laptops?", turns.get(0).question, "Oldest turn must come first after reversal.");
            assertEquals("and printers?", turns.get(2).question, "Newest turn must come last.");
        }
    }

    @Test
    public void testRecentDegradesToEmptyListOnDbFailure() throws Exception {
        try (MockedStatic<DBConnection> db = mockStatic(DBConnection.class)) {
            db.when(DBConnection::getConnection).thenThrow(new RuntimeException("connection pool exhausted"));

            List<CopilotChatMemory.Turn> turns = CopilotChatHistoryDAO.recent(1, 10);

            assertTrue(turns.isEmpty(), "A DB failure must degrade to no history, never throw out of the DAO.");
        }
    }

    @Test
    public void testRecentRejectsNonPositiveInputsWithoutTouchingTheDb() {
        try (MockedStatic<DBConnection> db = mockStatic(DBConnection.class)) {
            assertTrue(CopilotChatHistoryDAO.recent(0, 10).isEmpty());
            assertTrue(CopilotChatHistoryDAO.recent(-5, 10).isEmpty());
            assertTrue(CopilotChatHistoryDAO.recent(1, 0).isEmpty());
            db.verifyNoInteractions();
        }
    }

    @Test
    public void testAppendInsertsThenTrims() throws Exception {
        Connection con = mock(Connection.class);
        PreparedStatement ps = mock(PreparedStatement.class);

        when(con.prepareStatement(anyString())).thenReturn(ps);

        try (MockedStatic<DBConnection> db = mockStatic(DBConnection.class)) {
            db.when(DBConnection::getConnection).thenReturn(con);

            CopilotChatHistoryDAO.append(1, "how many laptops?", "42 laptops.");

            ArgumentCaptor<String> sqlCaptor = ArgumentCaptor.forClass(String.class);
            verify(con, org.mockito.Mockito.atLeastOnce()).prepareStatement(sqlCaptor.capture());
            boolean sawInsert = false;
            boolean sawTrim = false;
            for (String sql : sqlCaptor.getAllValues()) {
                String normalized = sql.toUpperCase(java.util.Locale.ENGLISH);
                if (normalized.contains("INSERT INTO COPILOT_CHAT_HISTORY")) sawInsert = true;
                if (normalized.contains("DELETE FROM COPILOT_CHAT_HISTORY")) sawTrim = true;
            }
            assertTrue(sawInsert, "append() must insert the new turn.");
            assertTrue(sawTrim, "append() must also trim old rows back down to the retention cap.");
        }
    }

    @Test
    public void testAppendNeverThrowsOnDbFailure() {
        try (MockedStatic<DBConnection> db = mockStatic(DBConnection.class)) {
            db.when(DBConnection::getConnection).thenThrow(new RuntimeException("down"));
            // Must not throw - a follow-up question in the current session
            // must still work even if durable persistence is broken.
            CopilotChatHistoryDAO.append(1, "q", "a");
        }
    }

    @Test
    public void testAppendIgnoresInvalidInputsWithoutTouchingTheDb() {
        try (MockedStatic<DBConnection> db = mockStatic(DBConnection.class)) {
            CopilotChatHistoryDAO.append(0, "q", "a");
            CopilotChatHistoryDAO.append(1, null, "a");
            CopilotChatHistoryDAO.append(1, "q", null);
            db.verifyNoInteractions();
        }
    }

    // ─────────────────────────────────────────────────────────────────────
    // listForUser() / deleteAllForUser() — back the new chat history page
    // ─────────────────────────────────────────────────────────────────────

    @Test
    public void testListForUserReturnsMostRecentFirstUnlikeRecent() throws Exception {
        Connection con = mock(Connection.class);
        PreparedStatement ps = mock(PreparedStatement.class);
        ResultSet rs = mock(ResultSet.class);

        when(con.prepareStatement(anyString())).thenReturn(ps);
        when(ps.executeQuery()).thenReturn(rs);
        // Unlike recent() (which reverses to chronological order for
        // replay), a browsable history view wants newest-first exactly as
        // the DESC-ordered query already returns it - no reversal.
        when(rs.next()).thenReturn(true, true, false);
        when(rs.getInt("history_id")).thenReturn(2, 1);
        when(rs.getString("question")).thenReturn("and printers?", "how many laptops?");
        when(rs.getString("answer")).thenReturn("5 printers.", "42 laptops.");
        when(rs.getTimestamp("created_at")).thenReturn(
                new java.sql.Timestamp(2000), new java.sql.Timestamp(1000));

        try (MockedStatic<DBConnection> db = mockStatic(DBConnection.class)) {
            db.when(DBConnection::getConnection).thenReturn(con);

            List<CopilotChatHistoryDAO.HistoryEntry> entries = CopilotChatHistoryDAO.listForUser(1, 50);

            assertEquals(2, entries.size());
            assertEquals("and printers?", entries.get(0).question, "Newest turn must come first, not reversed.");
            assertEquals("how many laptops?", entries.get(1).question);
        }
    }

    @Test
    public void testListForUserDegradesToEmptyListOnDbFailure() {
        try (MockedStatic<DBConnection> db = mockStatic(DBConnection.class)) {
            db.when(DBConnection::getConnection).thenThrow(new RuntimeException("connection pool exhausted"));

            List<CopilotChatHistoryDAO.HistoryEntry> entries = CopilotChatHistoryDAO.listForUser(1, 50);

            assertTrue(entries.isEmpty(), "A DB failure must degrade to an empty list, never throw.");
        }
    }

    @Test
    public void testListForUserRejectsNonPositiveInputsWithoutTouchingTheDb() {
        try (MockedStatic<DBConnection> db = mockStatic(DBConnection.class)) {
            assertTrue(CopilotChatHistoryDAO.listForUser(0, 50).isEmpty());
            assertTrue(CopilotChatHistoryDAO.listForUser(-1, 50).isEmpty());
            assertTrue(CopilotChatHistoryDAO.listForUser(1, 0).isEmpty());
            db.verifyNoInteractions();
        }
    }

    @Test
    public void testDeleteAllForUserScopesToTheGivenUserOnly() throws Exception {
        Connection con = mock(Connection.class);
        PreparedStatement ps = mock(PreparedStatement.class);
        when(con.prepareStatement(anyString())).thenReturn(ps);

        try (MockedStatic<DBConnection> db = mockStatic(DBConnection.class)) {
            db.when(DBConnection::getConnection).thenReturn(con);

            boolean result = CopilotChatHistoryDAO.deleteAllForUser(7);

            assertTrue(result);
            ArgumentCaptor<String> sqlCaptor = ArgumentCaptor.forClass(String.class);
            verify(con).prepareStatement(sqlCaptor.capture());
            String sql = sqlCaptor.getValue().toUpperCase(java.util.Locale.ENGLISH);
            assertTrue(sql.contains("DELETE FROM COPILOT_CHAT_HISTORY"), "Must delete from the history table.");
            assertTrue(sql.contains("WHERE USER_ID = ?"),
                    "Must scope the delete to one user - never a global wipe of every user's history.");
            verify(ps).setInt(1, 7);
        }
    }

    @Test
    public void testDeleteAllForUserReturnsFalseOnDbFailureRatherThanThrowing() {
        try (MockedStatic<DBConnection> db = mockStatic(DBConnection.class)) {
            db.when(DBConnection::getConnection).thenThrow(new RuntimeException("down"));

            boolean result = CopilotChatHistoryDAO.deleteAllForUser(7);

            assertEquals(false, result);
        }
    }

    @Test
    public void testDeleteAllForUserRejectsNonPositiveUserIdWithoutTouchingTheDb() {
        try (MockedStatic<DBConnection> db = mockStatic(DBConnection.class)) {
            assertEquals(false, CopilotChatHistoryDAO.deleteAllForUser(0));
            assertEquals(false, CopilotChatHistoryDAO.deleteAllForUser(-3));
            db.verifyNoInteractions();
        }
    }
}
