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

public class EmployeeModuleSecurityTest {

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
    public void testUpdateEmployeeServletIDOR_DenyAccessToOtherDepartmentEmployee() throws Exception {
        HttpServletRequest request = mock(HttpServletRequest.class);
        HttpServletResponse response = mock(HttpServletResponse.class);
        HttpSession session = mock(HttpSession.class);

        when(request.getSession(false)).thenReturn(session);
        when(session.getAttribute("username")).thenReturn("dept_head_1");
        when(session.getAttribute("role")).thenReturn("DEPARTMENT_HEAD");
        when(session.getAttribute("user_id")).thenReturn(101); // Dept head user ID

        // Trying to update employee 50 (which belongs to a different department)
        when(request.getParameter("employeeId")).thenReturn("50");

        Connection con = mock(Connection.class);
        PreparedStatement ps = mock(PreparedStatement.class);
        ResultSet rs = mock(ResultSet.class);

        mockedDBConnection.when(DBConnection::getConnection).thenReturn(con);

        // Mock EmployeeDAO.isEmployeeUnderDepartmentHead query
        when(con.prepareStatement(anyString())).thenReturn(ps);
        when(ps.executeQuery()).thenReturn(rs);
        when(rs.next()).thenReturn(true);
        when(rs.getInt(1)).thenReturn(0); // 0 means employee is NOT under this department head

        UpdateEmployeeServlet servlet = new UpdateEmployeeServlet();
        servlet.doPost(request, response);

        // Verify that access was denied and redirected
        verify(response).sendRedirect("employees.jsp?access=denied");
    }

    @Test
    public void testDisableEmployeeServletIDOR_DenyAccessToOtherDepartmentEmployee() throws Exception {
        HttpServletRequest request = mock(HttpServletRequest.class);
        HttpServletResponse response = mock(HttpServletResponse.class);
        HttpSession session = mock(HttpSession.class);

        when(request.getSession(false)).thenReturn(session);
        when(session.getAttribute("username")).thenReturn("dept_head_1");
        when(session.getAttribute("role")).thenReturn("DEPARTMENT_HEAD");
        when(session.getAttribute("user_id")).thenReturn(101);

        // Trying to disable employee 50
        when(request.getParameter("id")).thenReturn("50");

        Connection con = mock(Connection.class);
        PreparedStatement ps = mock(PreparedStatement.class);
        ResultSet rs = mock(ResultSet.class);

        mockedDBConnection.when(DBConnection::getConnection).thenReturn(con);

        // Mock EmployeeDAO.isEmployeeUnderDepartmentHead query
        when(con.prepareStatement(anyString())).thenReturn(ps);
        when(ps.executeQuery()).thenReturn(rs);
        when(rs.next()).thenReturn(true);
        when(rs.getInt(1)).thenReturn(0);

        DisableEmployeeServlet servlet = new DisableEmployeeServlet();
        servlet.doPost(request, response);

        verify(response).sendRedirect("employees.jsp?access=denied");
    }

    @Test
    public void testAddEmployeeServletIDOR_DenyAddingToOtherDepartment() throws Exception {
        HttpServletRequest request = mock(HttpServletRequest.class);
        HttpServletResponse response = mock(HttpServletResponse.class);
        HttpSession session = mock(HttpSession.class);

        when(request.getSession(false)).thenReturn(session);
        when(session.getAttribute("username")).thenReturn("dept_head_1");
        when(session.getAttribute("role")).thenReturn("DEPARTMENT_HEAD");
        when(session.getAttribute("user_id")).thenReturn(101);

        // Trying to add to department 5 (not managed by this dept head)
        when(request.getParameter("departmentId")).thenReturn("5");
        when(request.getParameter("employeeCode")).thenReturn("EMP999");
        when(request.getParameter("employeeName")).thenReturn("Test User");
        when(request.getParameter("email")).thenReturn("test@test.com");
        when(request.getParameter("phone")).thenReturn("1234567890");

        Connection con = mock(Connection.class);
        PreparedStatement ps = mock(PreparedStatement.class);
        ResultSet rs = mock(ResultSet.class);

        mockedDBConnection.when(DBConnection::getConnection).thenReturn(con);

        // Mock DepartmentDAO.isDepartmentUnderDepartmentHead query
        when(con.prepareStatement(anyString())).thenReturn(ps);
        when(ps.executeQuery()).thenReturn(rs);
        when(rs.next()).thenReturn(false); // Department NOT under this dept head

        AddEmployeeServlet servlet = new AddEmployeeServlet();
        servlet.doPost(request, response);

        verify(response).sendRedirect("employees.jsp?access=denied");
    }
}
