package com.mycompany.asset_management_system_ams;

import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;

import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import jakarta.servlet.http.HttpSession;

import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.MockedStatic;
import org.mockito.Mockito;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.*;

public class AdminHandoffTest {

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
    public void testAdminHandoffWithNoFallback() throws Exception {
        HttpServletRequest request = mock(HttpServletRequest.class);
        HttpServletResponse response = mock(HttpServletResponse.class);
        HttpSession session = mock(HttpSession.class);

        when(request.getSession(false)).thenReturn(session);
        when(session.getAttribute("username")).thenReturn("admin");
        when(session.getAttribute("role")).thenReturn("ADMIN");
        when(session.getAttribute("user_id")).thenReturn(1);

        when(request.getParameter("userId")).thenReturn("101");
        when(request.getParameter("newRole")).thenReturn("admin");
        when(request.getParameter("outgoingAdminRole")).thenReturn(""); // No fallback
        when(request.getParameter("status")).thenReturn("ACTIVE");

        Connection con = mock(Connection.class);
        PreparedStatement psTarget = mock(PreparedStatement.class);
        ResultSet rsTarget = mock(ResultSet.class);

        PreparedStatement psAdmin = mock(PreparedStatement.class);
        ResultSet rsAdmin = mock(ResultSet.class);

        PreparedStatement psUpdateAdmins = mock(PreparedStatement.class);
        PreparedStatement psLogAdmins = mock(PreparedStatement.class);
        PreparedStatement psUpdateTarget = mock(PreparedStatement.class);
        PreparedStatement psLogTarget = mock(PreparedStatement.class);

        mockedDBConnection.when(DBConnection::getConnection).thenReturn(con);

        // 1. Target user lookup
        when(con.prepareStatement("SELECT username, current_role FROM users WHERE user_id = ?")).thenReturn(psTarget);
        when(psTarget.executeQuery()).thenReturn(rsTarget);
        when(rsTarget.next()).thenReturn(true);
        when(rsTarget.getString("username")).thenReturn("emp001");
        when(rsTarget.getString("current_role")).thenReturn("employee");

        // 2. Find current admin(s)
        when(con.prepareStatement("SELECT user_id FROM users WHERE current_role = 'admin'")).thenReturn(psAdmin);
        when(psAdmin.executeQuery()).thenReturn(rsAdmin);
        when(rsAdmin.next()).thenReturn(true, false);
        when(rsAdmin.getInt("user_id")).thenReturn(1);

        // 3. Demote admins
        when(con.prepareStatement("UPDATE users SET current_role = ?, role_id = ? WHERE current_role = 'admin'")).thenReturn(psUpdateAdmins);
        when(con.prepareStatement("INSERT INTO role_assignment_log (assigned_to, assigned_by, old_role, new_role) VALUES (?, ?, ?, ?)")).thenReturn(psLogAdmins, psLogTarget);

        // 4. Update Target
        when(con.prepareStatement("UPDATE users SET current_role = ?, status = ?, role_id = ? WHERE user_id = ?")).thenReturn(psUpdateTarget);

        // RoleIdResolver.resolveRoleId() now runs once per current_role
        // write (fallback demotion + target update) - a real, generic role
        // lookup that isn't the focus of this test, so it's stubbed to
        // always resolve rather than differentiated per role name.
        PreparedStatement psRoleLookup = mock(PreparedStatement.class);
        ResultSet rsRoleLookup = mock(ResultSet.class);
        when(con.prepareStatement("SELECT role_id FROM roles WHERE role_name = ?")).thenReturn(psRoleLookup);
        when(psRoleLookup.executeQuery()).thenReturn(rsRoleLookup);
        when(rsRoleLookup.next()).thenReturn(true);
        when(rsRoleLookup.getInt("role_id")).thenReturn(1);

        UpdateUserRoleServlet servlet = new UpdateUserRoleServlet();
        servlet.doPost(request, response);

        // Verify fallback to employee
        verify(psUpdateAdmins).setString(1, "employee");
        verify(psLogAdmins).setString(4, "employee");
        // Regression lock for the role_id sync fix: both the demoted
        // ex-admin(s) and the newly-promoted target must have role_id set
        // alongside current_role in the SAME statement, not left stale -
        // see RoleIdResolver's class doc for why this matters.
        verify(psUpdateAdmins).setInt(2, 1);
        verify(psUpdateTarget).setInt(3, 1);
        verify(con).commit();
    }

    @Test
    public void testAdminHandoffWithAssetManagerFallback() throws Exception {
        HttpServletRequest request = mock(HttpServletRequest.class);
        HttpServletResponse response = mock(HttpServletResponse.class);
        HttpSession session = mock(HttpSession.class);

        when(request.getSession(false)).thenReturn(session);
        when(session.getAttribute("username")).thenReturn("admin");
        when(session.getAttribute("role")).thenReturn("ADMIN");
        when(session.getAttribute("user_id")).thenReturn(1);

        when(request.getParameter("userId")).thenReturn("101");
        when(request.getParameter("newRole")).thenReturn("admin");
        when(request.getParameter("outgoingAdminRole")).thenReturn("asset_manager"); // Fallback!
        when(request.getParameter("status")).thenReturn("ACTIVE");

        Connection con = mock(Connection.class);
        PreparedStatement psTarget = mock(PreparedStatement.class);
        ResultSet rsTarget = mock(ResultSet.class);
        PreparedStatement psAdmin = mock(PreparedStatement.class);
        ResultSet rsAdmin = mock(ResultSet.class);
        PreparedStatement psUpdateAdmins = mock(PreparedStatement.class);
        PreparedStatement psLogAdmins = mock(PreparedStatement.class);
        PreparedStatement psUpdateTarget = mock(PreparedStatement.class);
        PreparedStatement psLogTarget = mock(PreparedStatement.class);

        mockedDBConnection.when(DBConnection::getConnection).thenReturn(con);

        when(con.prepareStatement("SELECT username, current_role FROM users WHERE user_id = ?")).thenReturn(psTarget);
        when(psTarget.executeQuery()).thenReturn(rsTarget);
        when(rsTarget.next()).thenReturn(true);
        when(rsTarget.getString("username")).thenReturn("emp001");
        when(rsTarget.getString("current_role")).thenReturn("employee");

        when(con.prepareStatement("SELECT user_id FROM users WHERE current_role = 'admin'")).thenReturn(psAdmin);
        when(psAdmin.executeQuery()).thenReturn(rsAdmin);
        when(rsAdmin.next()).thenReturn(true, false);
        when(rsAdmin.getInt("user_id")).thenReturn(1);

        when(con.prepareStatement("UPDATE users SET current_role = ?, role_id = ? WHERE current_role = 'admin'")).thenReturn(psUpdateAdmins);
        when(con.prepareStatement("INSERT INTO role_assignment_log (assigned_to, assigned_by, old_role, new_role) VALUES (?, ?, ?, ?)")).thenReturn(psLogAdmins, psLogTarget);
        when(con.prepareStatement("UPDATE users SET current_role = ?, status = ?, role_id = ? WHERE user_id = ?")).thenReturn(psUpdateTarget);

        // RoleIdResolver.resolveRoleId() now runs once per current_role
        // write (fallback demotion + target update) - stubbed to always
        // resolve, same reasoning as the other test in this file.
        PreparedStatement psRoleLookup = mock(PreparedStatement.class);
        ResultSet rsRoleLookup = mock(ResultSet.class);
        when(con.prepareStatement("SELECT role_id FROM roles WHERE role_name = ?")).thenReturn(psRoleLookup);
        when(psRoleLookup.executeQuery()).thenReturn(rsRoleLookup);
        when(rsRoleLookup.next()).thenReturn(true);
        when(rsRoleLookup.getInt("role_id")).thenReturn(1);

        UpdateUserRoleServlet servlet = new UpdateUserRoleServlet();
        servlet.doPost(request, response);

        // Verify fallback to asset_manager
        verify(psUpdateAdmins).setString(1, "asset_manager");
        verify(psLogAdmins).setString(4, "asset_manager");
        verify(con).commit();
    }

    @Test
    public void testAdminHandoffWithAdminFallbackRejected() throws Exception {
        HttpServletRequest request = mock(HttpServletRequest.class);
        HttpServletResponse response = mock(HttpServletResponse.class);
        HttpSession session = mock(HttpSession.class);

        when(request.getSession(false)).thenReturn(session);
        when(session.getAttribute("username")).thenReturn("admin");
        when(session.getAttribute("role")).thenReturn("ADMIN");
        when(session.getAttribute("user_id")).thenReturn(1);

        when(request.getParameter("userId")).thenReturn("101");
        when(request.getParameter("newRole")).thenReturn("admin");
        when(request.getParameter("outgoingAdminRole")).thenReturn("admin"); // INVALID Fallback!
        when(request.getParameter("status")).thenReturn("ACTIVE");

        UpdateUserRoleServlet servlet = new UpdateUserRoleServlet();
        servlet.doPost(request, response);

        // Verify it rejects the request without even opening a connection
        verify(response).sendRedirect("manage_roles.jsp?error=invalid_fallback");
        mockedDBConnection.verifyNoInteractions();
    }
}
