package com.mycompany.asset_management_system_ams;

import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.mockito.MockedStatic;

import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.util.Arrays;
import java.util.List;

import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.*;

public class AssetDAOTest {

    @Test
    public void testDeptHeadScopingForGetAllAssets() throws Exception {
        Connection con = mock(Connection.class);
        PreparedStatement ps = mock(PreparedStatement.class);
        ResultSet rs = mock(ResultSet.class);

        when(con.prepareStatement(anyString())).thenReturn(ps);
        when(ps.executeQuery()).thenReturn(rs);
        when(rs.next()).thenReturn(false); // No assets returned for simplicity

        try (MockedStatic<DBConnection> mockedDb = mockStatic(DBConnection.class)) {
            mockedDb.when(DBConnection::getConnection).thenReturn(con);

            AssetDAO dao = new AssetDAO();
            List<Integer> deptIds = Arrays.asList(5); // Simulate dept_head of department 5
            
            dao.getAllAssets(deptIds);
            
            // Capture the SQL query
            ArgumentCaptor<String> sqlCaptor = ArgumentCaptor.forClass(String.class);
            verify(con).prepareStatement(sqlCaptor.capture());
            String executedSql = sqlCaptor.getValue();
            
            // Verify SQL has the scoping filter
            assertTrue(executedSql.contains("WHERE a.department_id IN (?)"));
            
            // Verify the correct department ID was bound to the PreparedStatement
            verify(ps).setInt(1, 5);
        }
    }

    @Test
    public void testGlobalScopingForGetAllAssets() throws Exception {
        Connection con = mock(Connection.class);
        PreparedStatement ps = mock(PreparedStatement.class);
        ResultSet rs = mock(ResultSet.class);

        when(con.prepareStatement(anyString())).thenReturn(ps);
        when(ps.executeQuery()).thenReturn(rs);
        when(rs.next()).thenReturn(false); // No assets returned for simplicity

        try (MockedStatic<DBConnection> mockedDb = mockStatic(DBConnection.class)) {
            mockedDb.when(DBConnection::getConnection).thenReturn(con);

            AssetDAO dao = new AssetDAO();
            
            // Null deptIds simulates a super_admin or auditor
            dao.getAllAssets(null);
            
            ArgumentCaptor<String> sqlCaptor = ArgumentCaptor.forClass(String.class);
            verify(con).prepareStatement(sqlCaptor.capture());
            String executedSql = sqlCaptor.getValue();
            
            // Verify SQL does NOT have the department_id filter
            assertTrue(!executedSql.contains("department_id IN"));
            
            // No parameters should be bound
            verify(ps, never()).setInt(anyInt(), anyInt());
        }
    }
}
