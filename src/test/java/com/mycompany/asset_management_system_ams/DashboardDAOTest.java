package com.mycompany.asset_management_system_ams;

import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.mockito.MockedStatic;

import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.util.Arrays;
import java.util.List;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.*;

public class DashboardDAOTest {

    @Test
    public void testDeptHeadScopingForGetCount() throws Exception {
        Connection con = mock(Connection.class);
        PreparedStatement ps = mock(PreparedStatement.class);
        ResultSet rs = mock(ResultSet.class);

        when(con.prepareStatement(anyString())).thenReturn(ps);
        when(ps.executeQuery()).thenReturn(rs);
        when(rs.next()).thenReturn(true, false);
        when(rs.getInt(1)).thenReturn(42);

        try (MockedStatic<DBConnection> mockedDb = mockStatic(DBConnection.class)) {
            mockedDb.when(DBConnection::getConnection).thenReturn(con);

            DashboardDAO dao = new DashboardDAO();
            List<Integer> deptIds = Arrays.asList(5); // Simulate dept_head of department 5
            
            int count = dao.getCount("assets", deptIds);
            
            // Verify the result matches our mocked DB response
            assertEquals(42, count);
            
            // Capture the SQL query
            ArgumentCaptor<String> sqlCaptor = ArgumentCaptor.forClass(String.class);
            verify(con).prepareStatement(sqlCaptor.capture());
            String executedSql = sqlCaptor.getValue();
            
            // Verify SQL has the scoping filter
            assertTrue(executedSql.contains("department_id IN (?)"));
            
            // Verify the correct department ID was bound to the PreparedStatement
            verify(ps).setInt(1, 5);
        }
    }

    @Test
    public void testGlobalScopingForGetCount() throws Exception {
        Connection con = mock(Connection.class);
        PreparedStatement ps = mock(PreparedStatement.class);
        ResultSet rs = mock(ResultSet.class);

        when(con.prepareStatement(anyString())).thenReturn(ps);
        when(ps.executeQuery()).thenReturn(rs);
        when(rs.next()).thenReturn(true, false);
        when(rs.getInt(1)).thenReturn(100);

        try (MockedStatic<DBConnection> mockedDb = mockStatic(DBConnection.class)) {
            mockedDb.when(DBConnection::getConnection).thenReturn(con);

            DashboardDAO dao = new DashboardDAO();
            
            // Null deptIds simulates a super_admin or auditor
            int count = dao.getCount("assets", null);
            
            assertEquals(100, count);
            
            ArgumentCaptor<String> sqlCaptor = ArgumentCaptor.forClass(String.class);
            verify(con).prepareStatement(sqlCaptor.capture());
            String executedSql = sqlCaptor.getValue();
            
            // Verify SQL does NOT have the department_id filter
            assertTrue(!executedSql.contains("department_id IN"));
            assertTrue(!executedSql.contains("WHERE department_id")); // For assets, there shouldn't be a WHERE for null deptIds
            
            // No parameters should be bound
            verify(ps, never()).setInt(anyInt(), anyInt());
        }
    }

    @Test
    public void testDeptHeadScopingForGetAssetStatusCount() throws Exception {
        Connection con = mock(Connection.class);
        PreparedStatement ps = mock(PreparedStatement.class);
        ResultSet rs = mock(ResultSet.class);

        when(con.prepareStatement(anyString())).thenReturn(ps);
        when(ps.executeQuery()).thenReturn(rs);
        when(rs.next()).thenReturn(true, false);
        when(rs.getInt(1)).thenReturn(15);

        try (MockedStatic<DBConnection> mockedDb = mockStatic(DBConnection.class)) {
            mockedDb.when(DBConnection::getConnection).thenReturn(con);

            DashboardDAO dao = new DashboardDAO();
            List<Integer> deptIds = Arrays.asList(3, 4); // Simulate dept_head of departments 3 and 4
            
            int count = dao.getAssetStatusCount("ALLOCATED", deptIds);
            
            assertEquals(15, count);
            
            ArgumentCaptor<String> sqlCaptor = ArgumentCaptor.forClass(String.class);
            verify(con).prepareStatement(sqlCaptor.capture());
            String executedSql = sqlCaptor.getValue();
            
            assertTrue(executedSql.contains("department_id IN (?,?)"));
            
            // Parameter 1 is the status ('ALLOCATED')
            verify(ps).setString(1, "ALLOCATED");
            // Parameters 2 and 3 are the department IDs
            verify(ps).setInt(2, 3);
            verify(ps).setInt(3, 4);
        }
    }

    @Test
    public void testDeptHeadScopingForTotalAssetValue() throws Exception {
        Connection con = mock(Connection.class);
        PreparedStatement ps = mock(PreparedStatement.class);
        ResultSet rs = mock(ResultSet.class);

        when(con.prepareStatement(anyString())).thenReturn(ps);
        when(ps.executeQuery()).thenReturn(rs);
        when(rs.next()).thenReturn(true, false);
        when(rs.getDouble(1)).thenReturn(50000.50);

        try (MockedStatic<DBConnection> mockedDb = mockStatic(DBConnection.class)) {
            mockedDb.when(DBConnection::getConnection).thenReturn(con);

            DashboardDAO dao = new DashboardDAO();
            List<Integer> deptIds = Arrays.asList(2); // Simulate dept_head of department 2
            
            double value = dao.getTotalAssetValue(deptIds);
            
            assertEquals(50000.50, value);
            
            ArgumentCaptor<String> sqlCaptor = ArgumentCaptor.forClass(String.class);
            verify(con).prepareStatement(sqlCaptor.capture());
            String executedSql = sqlCaptor.getValue();
            
            assertTrue(executedSql.contains("WHERE department_id IN (?)"));
            
            verify(ps).setInt(1, 2);
        }
    }
}
