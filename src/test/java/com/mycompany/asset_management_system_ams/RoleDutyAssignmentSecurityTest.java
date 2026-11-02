package com.mycompany.asset_management_system_ams;

import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.MockedStatic;
import org.mockito.Mockito;

import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import jakarta.servlet.http.HttpSession;

import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;

import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.*;

public class RoleDutyAssignmentSecurityTest {

    private MockedStatic<DBConnection> mockedDBConnection;

    @BeforeEach
    public void setUp() {
        mockedDBConnection = mockStatic(DBConnection.class);
    }

    @AfterEach
    public void tearDown() {
        mockedDBConnection.close();
    }

    @Test
    public void testRoleAssignmentServlet_DenySuperAdmin() throws Exception {
        HttpServletRequest request = mock(HttpServletRequest.class);
        HttpServletResponse response = mock(HttpServletResponse.class);
        HttpSession session = mock(HttpSession.class);

        when(request.getSession(false)).thenReturn(session);
        when(session.getAttribute("username")).thenReturn("super_admin");
        when(session.getAttribute("role")).thenReturn("SUPER_ADMIN");

        RoleAssignmentServlet servlet = new RoleAssignmentServlet();
        servlet.doPost(request, response);

        verify(response).sendError(HttpServletResponse.SC_FORBIDDEN, "Unauthorized access.");
    }

    @Test
    public void testRoleAssignmentServlet_IDOR_DenyDepartmentHeadOutsideDept() throws Exception {
        HttpServletRequest request = mock(HttpServletRequest.class);
        HttpServletResponse response = mock(HttpServletResponse.class);
        HttpSession session = mock(HttpSession.class);

        when(request.getSession(false)).thenReturn(session);
        when(session.getAttribute("username")).thenReturn("dept_head");
        when(session.getAttribute("role")).thenReturn("DEPARTMENT_HEAD");
        when(session.getAttribute("user_id")).thenReturn(101);

        when(request.getParameter("action")).thenReturn("assign");
        when(request.getParameter("employee_id")).thenReturn("50");
        when(request.getParameter("role_code")).thenReturn("EMPLOYEE");

        Connection con = mock(Connection.class);
        PreparedStatement ps = mock(PreparedStatement.class);
        ResultSet rs = mock(ResultSet.class);

        mockedDBConnection.when(DBConnection::getConnection).thenReturn(con);

        when(con.prepareStatement(anyString())).thenReturn(ps);
        when(ps.executeQuery()).thenReturn(rs);
        // EmployeeDAO.isEmployeeUnderDepartmentHead logic simulation
        when(rs.next()).thenReturn(true);
        when(rs.getInt(1)).thenReturn(0); // 0 means employee not under department head

        RoleAssignmentServlet servlet = new RoleAssignmentServlet();
        servlet.doPost(request, response);

        verify(response).sendError(HttpServletResponse.SC_FORBIDDEN, "You can only assign roles to employees within your department.");
    }

    @Test
    public void testUpdateUserRoleServlet_DenyModifyingSuperAdminAccount() throws Exception {
        HttpServletRequest request = mock(HttpServletRequest.class);
        HttpServletResponse response = mock(HttpServletResponse.class);
        HttpSession session = mock(HttpSession.class);

        when(request.getSession(false)).thenReturn(session);
        when(session.getAttribute("username")).thenReturn("admin");
        when(session.getAttribute("role")).thenReturn("ADMIN");
        when(session.getAttribute("user_id")).thenReturn(1);

        // Target a different account (user_id=2) than the acting admin's own
        // (user_id=1, from the session above) - this test is specifically
        // about the servlet blocking an ADMIN from modifying a *different*
        // account whose current_role is super_admin, not about the
        // self-modification guard (that scenario is covered separately by
        // testUpdateUserRoleServlet_DenySelfModification below). The target
        // account is also deliberately named something other than the
        // literal "super_admin" username, since the safeguard this test
        // exercises must key off current_role, not username - see
        // UpdateUserRoleServlet's own fix comment for why.
        when(request.getParameter("userId")).thenReturn("2");
        // A real, valid role literal - not a placeholder - since
        // UpdateUserRoleServlet now validates newRole against the actual
        // current_role enum before this test's real target (the target
        // ACCOUNT'S protection, not the requested role) is ever reached.
        when(request.getParameter("newRole")).thenReturn("employee");

        Connection con = mock(Connection.class);
        PreparedStatement ps = mock(PreparedStatement.class);
        ResultSet rs = mock(ResultSet.class);

        mockedDBConnection.when(DBConnection::getConnection).thenReturn(con);

        when(con.prepareStatement(anyString())).thenReturn(ps);
        when(ps.executeQuery()).thenReturn(rs);
        when(rs.next()).thenReturn(true);
        when(rs.getString("username")).thenReturn("real_super_admin_account");
        when(rs.getString("current_role")).thenReturn("super_admin");
        
        when(con.prepareStatement("SELECT role_name FROM roles WHERE role_id = ?")).thenReturn(ps);
        when(rs.getString("role_name")).thenReturn("admin");

        UpdateUserRoleServlet servlet = new UpdateUserRoleServlet();
        servlet.doPost(request, response);

        verify(response).sendRedirect("manage_roles.jsp?error=cannot_modify_super_admin");
    }

    // Regression test for the self-modification guard added to
    // UpdateUserRoleServlet: an ADMIN POSTing with their own user_id as the
    // target userId must be rejected before any database work happens, not
    // silently allowed to change their own role/status. Uses a mocked
    // Connection that fails the test if it's ever asked for a
    // PreparedStatement, confirming the guard fires before the servlet's
    // first DB query, not just before the final UPDATE.
    @Test
    public void testUpdateUserRoleServlet_DenySelfModification() throws Exception {
        HttpServletRequest request = mock(HttpServletRequest.class);
        HttpServletResponse response = mock(HttpServletResponse.class);
        HttpSession session = mock(HttpSession.class);

        when(request.getSession(false)).thenReturn(session);
        when(session.getAttribute("username")).thenReturn("admin");
        when(session.getAttribute("role")).thenReturn("ADMIN");
        when(session.getAttribute("user_id")).thenReturn(1);

        // Target userId matches the acting admin's own session user_id.
        when(request.getParameter("userId")).thenReturn("1");
        when(request.getParameter("newRole")).thenReturn("employee");

        UpdateUserRoleServlet servlet = new UpdateUserRoleServlet();
        servlet.doPost(request, response);

        verify(response).sendRedirect("manage_roles.jsp?error=self");
        // The guard must short-circuit before DBConnection.getConnection() is
        // ever called - no DB round trip should happen for a rejected
        // self-modification attempt.
        mockedDBConnection.verifyNoInteractions();
    }

    @Test
    public void testUpdateUserRoleServlet_DenyAssigningSuperAdminRole() throws Exception {
        HttpServletRequest request = mock(HttpServletRequest.class);
        HttpServletResponse response = mock(HttpServletResponse.class);
        HttpSession session = mock(HttpSession.class);

        when(request.getSession(false)).thenReturn(session);
        when(session.getAttribute("username")).thenReturn("admin");
        when(session.getAttribute("role")).thenReturn("ADMIN");
        when(session.getAttribute("user_id")).thenReturn(1);

        when(request.getParameter("userId")).thenReturn("2");
        when(request.getParameter("newRole")).thenReturn("super_admin"); 

        Connection con = mock(Connection.class);
        PreparedStatement ps = mock(PreparedStatement.class);
        ResultSet rs = mock(ResultSet.class);

        mockedDBConnection.when(DBConnection::getConnection).thenReturn(con);

        when(con.prepareStatement(anyString())).thenReturn(ps);
        when(ps.executeQuery()).thenReturn(rs);
        when(rs.next()).thenReturn(true);
        when(rs.getString("username")).thenReturn("normal_user");
        when(rs.getString("current_role")).thenReturn("employee");
        
        when(con.prepareStatement("SELECT role_name FROM roles WHERE role_id = ?")).thenReturn(ps);
        ResultSet rsUser = mock(ResultSet.class);
        when(rsUser.next()).thenReturn(true);
        when(rsUser.getString("username")).thenReturn("normal_user");
        
        UpdateUserRoleServlet servlet = new UpdateUserRoleServlet();
        servlet.doPost(request, response);

        verify(response).sendRedirect("manage_roles.jsp?error=cannot_assign_super_admin");
    }
}
