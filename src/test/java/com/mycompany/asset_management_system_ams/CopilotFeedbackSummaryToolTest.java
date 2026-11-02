package com.mycompany.asset_management_system_ams;

import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.util.List;
import java.util.Map;

import jakarta.servlet.http.HttpSession;

import org.junit.jupiter.api.Test;
import org.mockito.MockedStatic;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.mockStatic;
import static org.mockito.Mockito.when;

/**
 * CopilotFeedbackSummaryToolTest — the get_copilot_feedback_summary tool
 * that closes the loop on CopilotFeedbackDAO's thumbs-up/down capture
 * (previously written but never read back anywhere). Locks in the same
 * two-layer role gate every other admin-only tool here follows
 * (getRoleDutySummary/getSettingsSummary) and the UP/DOWN aggregation math,
 * with mocked JDBC - separately verified live against a real deployment
 * while building this feature (real feedback rows inserted, asked through
 * the actual chat UI, confirmed counts and the downvoted example matched,
 * then cleaned up).
 */
public class CopilotFeedbackSummaryToolTest {

    private static HttpSession sessionWithRole(String role) {
        HttpSession session = mock(HttpSession.class);
        when(session.getAttribute("role")).thenReturn(role);
        return session;
    }

    @Test
    public void testNonAdminIsDenied() {
        CopilotQueryPlan plan = new CopilotQueryPlan();
        Map<String, Object> result = CopilotToolExecutor.getCopilotFeedbackSummary(plan, sessionWithRole("ASSET_MANAGER"));
        assertTrue(result.containsKey("error"));
        assertTrue(((String) result.get("error")).contains("Access Denied"));
    }

    @Test
    public void testAuditorIsDenied() {
        // Feedback data is about the Copilot's own operation, not an
        // auditable AMS record - deliberately narrower than getAuditLogs'
        // ADMIN+AUDITOR gate, matching getRoleDutySummary/getSettingsSummary
        // (ADMIN-only) instead.
        CopilotQueryPlan plan = new CopilotQueryPlan();
        Map<String, Object> result = CopilotToolExecutor.getCopilotFeedbackSummary(plan, sessionWithRole("AUDITOR"));
        assertTrue(result.containsKey("error"));
    }

    @Test
    public void testAdminSeesCountsAndSatisfactionRate() throws Exception {
        Connection con = mock(Connection.class);
        PreparedStatement countsPs = mock(PreparedStatement.class);
        PreparedStatement recentPs = mock(PreparedStatement.class);
        ResultSet countsRs = mock(ResultSet.class);
        ResultSet recentRs = mock(ResultSet.class);

        when(con.prepareStatement(org.mockito.ArgumentMatchers.contains("GROUP BY rating"))).thenReturn(countsPs);
        when(con.prepareStatement(org.mockito.ArgumentMatchers.contains("ORDER BY feedback_id DESC"))).thenReturn(recentPs);

        when(countsPs.executeQuery()).thenReturn(countsRs);
        when(countsRs.next()).thenReturn(true, true, false);
        when(countsRs.getString("rating")).thenReturn("UP", "DOWN");
        when(countsRs.getInt("cnt")).thenReturn(7, 3);

        when(recentPs.executeQuery()).thenReturn(recentRs);
        when(recentRs.next()).thenReturn(true, false);
        when(recentRs.getString("question")).thenReturn("how many laptops are there?");
        when(recentRs.getString("answer")).thenReturn("There is 1 laptop.");
        when(recentRs.getString("created_at")).thenReturn("2026-08-22 10:00:00");

        try (MockedStatic<DBConnection> db = mockStatic(DBConnection.class)) {
            db.when(DBConnection::getConnection).thenReturn(con);

            CopilotQueryPlan plan = new CopilotQueryPlan();
            Map<String, Object> result = CopilotToolExecutor.getCopilotFeedbackSummary(plan, sessionWithRole("ADMIN"));

            assertFalse(result.containsKey("error"));
            assertEquals(7, result.get("up_count"));
            assertEquals(3, result.get("down_count"));
            assertEquals(10, result.get("total_rated"));
            assertEquals("70.0%", result.get("satisfaction_rate"));

            @SuppressWarnings("unchecked")
            List<Map<String, String>> recentDown = (List<Map<String, String>>) result.get("recent_downvoted");
            assertEquals(1, recentDown.size());
            assertEquals("how many laptops are there?", recentDown.get(0).get("question"));
        }
    }

    @Test
    public void testZeroRatingsReportsNotApplicableRateWithoutDividingByZero() throws Exception {
        Connection con = mock(Connection.class);
        PreparedStatement ps = mock(PreparedStatement.class);
        ResultSet rs = mock(ResultSet.class);
        when(con.prepareStatement(anyString())).thenReturn(ps);
        when(ps.executeQuery()).thenReturn(rs);
        when(rs.next()).thenReturn(false); // no rows in either query

        try (MockedStatic<DBConnection> db = mockStatic(DBConnection.class)) {
            db.when(DBConnection::getConnection).thenReturn(con);

            CopilotQueryPlan plan = new CopilotQueryPlan();
            Map<String, Object> result = CopilotToolExecutor.getCopilotFeedbackSummary(plan, sessionWithRole("SUPER_ADMIN"));

            assertEquals(0, result.get("up_count"));
            assertEquals(0, result.get("down_count"));
            assertEquals("n/a", result.get("satisfaction_rate"));
        }
    }

    @Test
    public void testDefaultLookbackIs30DaysWhenPlanDaysNotSet() throws Exception {
        Connection con = mock(Connection.class);
        PreparedStatement ps = mock(PreparedStatement.class);
        ResultSet rs = mock(ResultSet.class);
        when(con.prepareStatement(anyString())).thenReturn(ps);
        when(ps.executeQuery()).thenReturn(rs);
        when(rs.next()).thenReturn(false);

        try (MockedStatic<DBConnection> db = mockStatic(DBConnection.class)) {
            db.when(DBConnection::getConnection).thenReturn(con);

            CopilotQueryPlan plan = new CopilotQueryPlan(); // plan.days left null
            Map<String, Object> result = CopilotToolExecutor.getCopilotFeedbackSummary(plan, sessionWithRole("ADMIN"));

            assertEquals(30, result.get("period_days"));
        }
    }
}
