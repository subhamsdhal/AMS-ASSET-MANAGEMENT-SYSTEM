package com.mycompany.asset_management_system_ams;

import java.lang.reflect.Method;
import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;

import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

/**
 * RoleIdResolverTest — locks in the role_id sync fix (audit/01-auth-session.md's
 * P0 schema-drift finding, followed to its real root cause: UpdateUserRoleServlet
 * and EmergencyAdminResetServlet updated current_role but never role_id,
 * confirmed live to leave role_id stale/wrong for most real user rows).
 *
 * resolveRoleId() is package-private, called via reflection here only because
 * this test intentionally exercises it exactly as its two real callers do -
 * not because there's anything sensitive about it.
 */
public class RoleIdResolverTest {

    private static Integer invoke(Connection con, String currentRole) throws Exception {
        Method m = RoleIdResolver.class.getDeclaredMethod("resolveRoleId", Connection.class, String.class);
        m.setAccessible(true);
        return (Integer) m.invoke(null, con, currentRole);
    }

    @Test
    public void testResolvesAPlainEnumValueToItsUppercaseRoleName() throws Exception {
        Connection con = mock(Connection.class);
        PreparedStatement ps = mock(PreparedStatement.class);
        ResultSet rs = mock(ResultSet.class);

        when(con.prepareStatement("SELECT role_id FROM roles WHERE role_name = ?")).thenReturn(ps);
        when(ps.executeQuery()).thenReturn(rs);
        when(rs.next()).thenReturn(true);
        when(rs.getInt("role_id")).thenReturn(6);

        Integer result = invoke(con, "admin");

        assertEquals(6, result);
        // Must have queried the UPPERCASE spelling roles.role_name actually
        // stores, not the lowercase enum literal verbatim.
        org.mockito.Mockito.verify(ps).setString(1, "ADMIN");
    }

    @Test
    public void testDeptHeadResolvesToDepartmentHeadNotALiteralUppercase() throws Exception {
        // The one real naming mismatch found live: users.current_role stores
        // "dept_head", but roles.role_name stores "DEPARTMENT_HEAD" - a
        // genuinely different string, not just a case difference. A naive
        // currentRole.toUpperCase() would look up "DEPT_HEAD" and silently
        // fail to resolve every department head's role_id - confirmed this
        // is exactly what was happening against the real database.
        Connection con = mock(Connection.class);
        PreparedStatement ps = mock(PreparedStatement.class);
        ResultSet rs = mock(ResultSet.class);

        when(con.prepareStatement("SELECT role_id FROM roles WHERE role_name = ?")).thenReturn(ps);
        when(ps.executeQuery()).thenReturn(rs);
        when(rs.next()).thenReturn(true);
        when(rs.getInt("role_id")).thenReturn(3);

        Integer result = invoke(con, "dept_head");

        assertEquals(3, result);
        org.mockito.Mockito.verify(ps).setString(1, "DEPARTMENT_HEAD");
    }

    @Test
    public void testCaseAndWhitespaceInsensitiveOnTheInputValue() throws Exception {
        Connection con = mock(Connection.class);
        PreparedStatement ps = mock(PreparedStatement.class);
        ResultSet rs = mock(ResultSet.class);

        when(con.prepareStatement("SELECT role_id FROM roles WHERE role_name = ?")).thenReturn(ps);
        when(ps.executeQuery()).thenReturn(rs);
        when(rs.next()).thenReturn(true);
        when(rs.getInt("role_id")).thenReturn(2);

        Integer result = invoke(con, "  Asset_Manager  ");

        assertEquals(2, result);
        org.mockito.Mockito.verify(ps).setString(1, "ASSET_MANAGER");
    }

    @Test
    public void testReturnsNullRatherThanThrowingWhenNoRoleMatches() throws Exception {
        Connection con = mock(Connection.class);
        PreparedStatement ps = mock(PreparedStatement.class);
        ResultSet rs = mock(ResultSet.class);

        when(con.prepareStatement("SELECT role_id FROM roles WHERE role_name = ?")).thenReturn(ps);
        when(ps.executeQuery()).thenReturn(rs);
        when(rs.next()).thenReturn(false);

        assertNull(invoke(con, "employee"));
    }

    @Test
    public void testReturnsNullRatherThanThrowingOnDbFailure() throws Exception {
        Connection con = mock(Connection.class);
        when(con.prepareStatement(eq("SELECT role_id FROM roles WHERE role_name = ?")))
                .thenThrow(new java.sql.SQLException("connection lost"));

        assertNull(invoke(con, "admin"), "A DB failure must degrade to null, never throw out of the resolver.");
    }

    @Test
    public void testReturnsNullForBlankOrNullInputWithoutTouchingTheDb() throws Exception {
        Connection con = mock(Connection.class);

        assertNull(invoke(con, null));
        assertNull(invoke(con, ""));
        assertNull(invoke(con, "   "));

        org.mockito.Mockito.verifyNoInteractions(con);
    }
}
