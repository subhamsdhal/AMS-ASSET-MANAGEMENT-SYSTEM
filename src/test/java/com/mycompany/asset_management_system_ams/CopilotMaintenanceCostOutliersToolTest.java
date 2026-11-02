package com.mycompany.asset_management_system_ams;

import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.util.List;
import java.util.Map;

import jakarta.servlet.http.HttpSession;

import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.mockito.MockedStatic;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.mockStatic;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * CopilotMaintenanceCostOutliersToolTest — get_maintenance_cost_outliers, the
 * Copilot's one genuinely analytical (not lookup) tool: it compares each
 * asset's total maintenance spend against its own category's average,
 * something no single WHERE clause expresses. The query itself was verified
 * once directly against real live data while building this (2 real outliers
 * found, both at exactly 2.0x their category average - confirmed by hand);
 * these tests lock in the role gate and the threshold/default-handling logic
 * with mocked JDBC.
 */
public class CopilotMaintenanceCostOutliersToolTest {

    private static HttpSession sessionWithRole(String role) {
        HttpSession session = mock(HttpSession.class);
        when(session.getAttribute("role")).thenReturn(role);
        return session;
    }

    @Test
    public void testEmployeeIsDenied() {
        CopilotQueryPlan plan = new CopilotQueryPlan();
        Map<String, Object> result = CopilotToolExecutor.getMaintenanceCostOutliers(plan, sessionWithRole("EMPLOYEE"));
        assertTrue(result.containsKey("error"));
    }

    @Test
    public void testDepartmentHeadIsDenied() {
        // Deliberately narrower than every other data-lookup tool (most are
        // ALL-role) - this is an operational spend insight, matching the
        // ASSET_OPS_AND_AUDIT group get_qr_scan_logs already uses.
        CopilotQueryPlan plan = new CopilotQueryPlan();
        Map<String, Object> result = CopilotToolExecutor.getMaintenanceCostOutliers(plan, sessionWithRole("DEPARTMENT_HEAD"));
        assertTrue(result.containsKey("error"));
    }

    @Test
    public void testAssetManagerAuditorAdminSuperAdminAreAllowed() throws Exception {
        for (String role : new String[]{"ASSET_MANAGER", "AUDITOR", "ADMIN", "SUPER_ADMIN"}) {
            Connection con = mock(Connection.class);
            PreparedStatement ps = mock(PreparedStatement.class);
            ResultSet rs = mock(ResultSet.class);
            when(con.prepareStatement(anyString())).thenReturn(ps);
            when(ps.executeQuery()).thenReturn(rs);
            when(rs.next()).thenReturn(false);

            try (MockedStatic<DBConnection> db = mockStatic(DBConnection.class)) {
                db.when(DBConnection::getConnection).thenReturn(con);
                CopilotQueryPlan plan = new CopilotQueryPlan();
                Map<String, Object> result = CopilotToolExecutor.getMaintenanceCostOutliers(plan, sessionWithRole(role));
                assertFalse(result.containsKey("error"), role + " should be allowed to use this tool.");
            }
        }
    }

    @Test
    public void testDefaultThresholdIs1Point5WhenPlanFieldNotSet() throws Exception {
        Connection con = mock(Connection.class);
        PreparedStatement ps = mock(PreparedStatement.class);
        ResultSet rs = mock(ResultSet.class);
        when(con.prepareStatement(anyString())).thenReturn(ps);
        when(ps.executeQuery()).thenReturn(rs);
        when(rs.next()).thenReturn(false);

        try (MockedStatic<DBConnection> db = mockStatic(DBConnection.class)) {
            db.when(DBConnection::getConnection).thenReturn(con);

            CopilotQueryPlan plan = new CopilotQueryPlan(); // costMultiplierThreshold left null
            Map<String, Object> result = CopilotToolExecutor.getMaintenanceCostOutliers(plan, sessionWithRole("ADMIN"));

            assertEquals(1.5, (Double) result.get("threshold_multiplier"), 0.0001);
            verify(ps).setDouble(1, 1.5);
        }
    }

    @Test
    public void testExplicitThresholdIsUsedWhenSet() throws Exception {
        Connection con = mock(Connection.class);
        PreparedStatement ps = mock(PreparedStatement.class);
        ResultSet rs = mock(ResultSet.class);
        when(con.prepareStatement(anyString())).thenReturn(ps);
        when(ps.executeQuery()).thenReturn(rs);
        when(rs.next()).thenReturn(false);

        try (MockedStatic<DBConnection> db = mockStatic(DBConnection.class)) {
            db.when(DBConnection::getConnection).thenReturn(con);

            CopilotQueryPlan plan = new CopilotQueryPlan();
            plan.costMultiplierThreshold = 3.0;
            CopilotToolExecutor.getMaintenanceCostOutliers(plan, sessionWithRole("ADMIN"));

            verify(ps).setDouble(1, 3.0);
        }
    }

    @Test
    public void testOutOfRangeThresholdFallsBackToDefault() throws Exception {
        // <= 1.0 would flag "at or below average" as an outlier, which is
        // not what this tool means by the word - guarded the same way other
        // tools here fall back to a sane default on a nonsensical model answer.
        Connection con = mock(Connection.class);
        PreparedStatement ps = mock(PreparedStatement.class);
        ResultSet rs = mock(ResultSet.class);
        when(con.prepareStatement(anyString())).thenReturn(ps);
        when(ps.executeQuery()).thenReturn(rs);
        when(rs.next()).thenReturn(false);

        try (MockedStatic<DBConnection> db = mockStatic(DBConnection.class)) {
            db.when(DBConnection::getConnection).thenReturn(con);

            CopilotQueryPlan plan = new CopilotQueryPlan();
            plan.costMultiplierThreshold = 0.5;
            CopilotToolExecutor.getMaintenanceCostOutliers(plan, sessionWithRole("ADMIN"));

            verify(ps).setDouble(1, 1.5);
        }
    }

    @Test
    public void testMapsRowsAndComputesRatioLabel() throws Exception {
        Connection con = mock(Connection.class);
        PreparedStatement ps = mock(PreparedStatement.class);
        ResultSet rs = mock(ResultSet.class);
        when(con.prepareStatement(anyString())).thenReturn(ps);
        when(ps.executeQuery()).thenReturn(rs);
        when(rs.next()).thenReturn(true, false);
        when(rs.getString("asset_code")).thenReturn("AST006");
        when(rs.getString("asset_name")).thenReturn("Canon Multifunction Printer");
        when(rs.getString("category_name")).thenReturn("Printer & Scanner");
        when(rs.getString("total_cost")).thenReturn("6500.00");
        when(rs.getString("avg_cost")).thenReturn("3250.000000");
        when(rs.getDouble("cost_ratio")).thenReturn(2.0);

        try (MockedStatic<DBConnection> db = mockStatic(DBConnection.class)) {
            db.when(DBConnection::getConnection).thenReturn(con);

            CopilotQueryPlan plan = new CopilotQueryPlan();
            Map<String, Object> result = CopilotToolExecutor.getMaintenanceCostOutliers(plan, sessionWithRole("ADMIN"));

            @SuppressWarnings("unchecked")
            List<Map<String, String>> outliers = (List<Map<String, String>>) result.get("outliers");
            assertEquals(1, outliers.size());
            assertEquals("AST006", outliers.get(0).get("asset_code"));
            assertEquals("2.0x", outliers.get(0).get("times_above_average"));
        }
    }

    @Test
    public void testEmptyResultIncludesAReassuringNote() throws Exception {
        Connection con = mock(Connection.class);
        PreparedStatement ps = mock(PreparedStatement.class);
        ResultSet rs = mock(ResultSet.class);
        when(con.prepareStatement(anyString())).thenReturn(ps);
        when(ps.executeQuery()).thenReturn(rs);
        when(rs.next()).thenReturn(false);

        try (MockedStatic<DBConnection> db = mockStatic(DBConnection.class)) {
            db.when(DBConnection::getConnection).thenReturn(con);

            CopilotQueryPlan plan = new CopilotQueryPlan();
            Map<String, Object> result = CopilotToolExecutor.getMaintenanceCostOutliers(plan, sessionWithRole("ADMIN"));

            assertTrue(((List<?>) result.get("outliers")).isEmpty());
            assertTrue(result.containsKey("note"));
        }
    }
}
