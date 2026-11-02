package com.mycompany.asset_management_system_ams;

import org.junit.jupiter.api.Test;
import org.mockito.MockedStatic;
import org.mockito.Mockito;

import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import jakarta.servlet.http.HttpSession;
import jakarta.servlet.ServletConfig;
import jakarta.servlet.ServletContext;
import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;

import static org.mockito.ArgumentMatchers.argThat;
import static org.mockito.Mockito.*;

public class LoginServletIntegrationTest {
    
    @Test
    public void testLoginServletWithEmp001() throws Exception {
        HttpServletRequest request = mock(HttpServletRequest.class);
        HttpServletResponse response = mock(HttpServletResponse.class);
        HttpSession session = mock(HttpSession.class);
        Connection con = mock(Connection.class);
        PreparedStatement ps = mock(PreparedStatement.class);
        ResultSet rs = mock(ResultSet.class);

        // Simulate incoming POST request with emp001 and password emp001123
        when(request.getParameter("username")).thenReturn("emp001");
        when(request.getParameter("password")).thenReturn("emp001123");
        when(request.getSession()).thenReturn(session);
        // LoginServlet now hardens against session fixation by calling
        // getSession(false) (to invalidate any pre-auth session) and then
        // getSession(true) to start a fresh one, instead of the deprecated
        // no-arg getSession() - see CHANGELOG-fixes.md (Login-5, session
        // fixation). No pre-existing session in this scenario, so (false)
        // returns null like a real fresh request would; (true) returns the
        // same mock the assertions below check against.
        when(request.getSession(false)).thenReturn(null);
        when(request.getSession(true)).thenReturn(session);

        // LoginServlet now also runs a brute-force lockout check
        // (ensureLoginSecurityAttemptTable + isAccountLocked) before the auth
        // query below - it reuses the same mocked Connection, so it needs its
        // own PreparedStatement/ResultSet pair matched by SQL text, rather
        // than sharing rs.next()'s stubbed sequence with the auth query (that
        // sharing is what broke this test after the lockout fix landed - see
        // CHANGELOG-fixes.md, Login-6).
        PreparedStatement lockoutTablePs = mock(PreparedStatement.class);
        PreparedStatement lockoutCheckPs = mock(PreparedStatement.class);
        ResultSet lockoutRs = mock(ResultSet.class);
        when(lockoutRs.next()).thenReturn(true);
        when(lockoutRs.getInt("attempt_count")).thenReturn(0); // well under the lockout threshold
        when(lockoutCheckPs.executeQuery()).thenReturn(lockoutRs);

        when(con.prepareStatement(argThat(sql -> sql != null && sql.contains("CREATE TABLE IF NOT EXISTS login_security_attempts"))))
                .thenReturn(lockoutTablePs);
        when(con.prepareStatement(argThat(sql -> sql != null && sql.contains("SELECT COUNT(*) AS attempt_count"))))
                .thenReturn(lockoutCheckPs);

        // Mock JDBC behavior for the SQL query:
        // "SELECT user_id, username, password_crypt, current_role, employee_id, status FROM users ..."
        when(con.prepareStatement(argThat(sql -> sql != null && sql.contains("SELECT user_id, username, password_crypt"))))
                .thenReturn(ps);
        when(ps.executeQuery()).thenReturn(rs);
        when(rs.next()).thenReturn(true, false);
        when(rs.getString("password_crypt")).thenReturn("$2a$10$gZIgTvuUoZZ3cJJ6hKLgE.ivXBTt86weQZ4PUYDip/inQyTfvlrWi");
        when(rs.getString("current_role")).thenReturn("employee");
        when(rs.getString("username")).thenReturn("emp001");
        when(rs.getInt("user_id")).thenReturn(101);
        when(rs.getObject("employee_id")).thenReturn(1);

        // Mock static DBConnection
        try (MockedStatic<DBConnection> mockedDb = mockStatic(DBConnection.class)) {
            mockedDb.when(DBConnection::getConnection).thenReturn(con);
            
            ServletConfig config = mock(ServletConfig.class);
            ServletContext context = mock(ServletContext.class);
            when(config.getServletContext()).thenReturn(context);
            
            // Execute the servlet POST request
            LoginServlet servlet = new LoginServlet();
            servlet.init(config);
            servlet.doPost(request, response);
            
            // ASSERTIONS: Verify session attributes were correctly assigned
            verify(session).setAttribute("user_id", 101);
            verify(session).setAttribute("username", "emp001");
            verify(session).setAttribute("role", "EMPLOYEE");
            verify(session).setAttribute("employee_id", 1);
            
            // ASSERTION: Verify successful redirect to the correct landing page (200 OK / 302 Redirect)
            verify(response).sendRedirect("employee_dashboard.jsp");
        }
    }
    
    @Test
    public void testLoginServletWithAdmin() throws Exception {
        HttpServletRequest request = mock(HttpServletRequest.class);
        HttpServletResponse response = mock(HttpServletResponse.class);
        HttpSession session = mock(HttpSession.class);
        Connection con = mock(Connection.class);
        PreparedStatement ps = mock(PreparedStatement.class);
        ResultSet rs = mock(ResultSet.class);

        // Simulate incoming POST request with admin and password admin123
        when(request.getParameter("username")).thenReturn("admin");
        when(request.getParameter("password")).thenReturn("admin123");
        when(request.getSession()).thenReturn(session);
        // LoginServlet now hardens against session fixation by calling
        // getSession(false) (to invalidate any pre-auth session) and then
        // getSession(true) to start a fresh one, instead of the deprecated
        // no-arg getSession() - see CHANGELOG-fixes.md (Login-5, session
        // fixation). No pre-existing session in this scenario, so (false)
        // returns null like a real fresh request would; (true) returns the
        // same mock the assertions below check against.
        when(request.getSession(false)).thenReturn(null);
        when(request.getSession(true)).thenReturn(session);

        PreparedStatement lockoutTablePs = mock(PreparedStatement.class);
        PreparedStatement lockoutCheckPs = mock(PreparedStatement.class);
        ResultSet lockoutRs = mock(ResultSet.class);
        when(lockoutRs.next()).thenReturn(true);
        when(lockoutRs.getInt("attempt_count")).thenReturn(0); // well under the lockout threshold
        when(lockoutCheckPs.executeQuery()).thenReturn(lockoutRs);

        when(con.prepareStatement(argThat(sql -> sql != null && sql.contains("CREATE TABLE IF NOT EXISTS login_security_attempts"))))
                .thenReturn(lockoutTablePs);
        when(con.prepareStatement(argThat(sql -> sql != null && sql.contains("SELECT COUNT(*) AS attempt_count"))))
                .thenReturn(lockoutCheckPs);
        when(con.prepareStatement(argThat(sql -> sql != null && sql.contains("SELECT user_id, username, password_crypt"))))
                .thenReturn(ps);
        when(ps.executeQuery()).thenReturn(rs);
        when(rs.next()).thenReturn(true, false);
        when(rs.getString("password_crypt")).thenReturn("$2a$10$YBhBKYSBIasdlcAT/05Tbell5xUpAyo8d0epxWIejJ17IwC7h3CJK");
        when(rs.getString("current_role")).thenReturn("admin");
        when(rs.getString("username")).thenReturn("admin");
        when(rs.getInt("user_id")).thenReturn(1);
        when(rs.getObject("employee_id")).thenReturn(1);

        try (MockedStatic<DBConnection> mockedDb = mockStatic(DBConnection.class)) {
            mockedDb.when(DBConnection::getConnection).thenReturn(con);
            
            ServletConfig config = mock(ServletConfig.class);
            ServletContext context = mock(ServletContext.class);
            when(config.getServletContext()).thenReturn(context);
            
            LoginServlet servlet = new LoginServlet();
            servlet.init(config);
            servlet.doPost(request, response);
            
            // ASSERTIONS: Verify session attributes were correctly assigned for ADMIN
            verify(session).setAttribute("user_id", 1);
            verify(session).setAttribute("username", "admin");
            verify(session).setAttribute("role", "ADMIN");
            
            // ASSERTION: Verify successful redirect for admin
            verify(response).sendRedirect("dashboard.jsp");
        }
    }
}
