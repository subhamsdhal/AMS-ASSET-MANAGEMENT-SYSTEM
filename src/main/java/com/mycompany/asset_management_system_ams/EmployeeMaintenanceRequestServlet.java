package com.mycompany.asset_management_system_ams;

import java.io.IOException;
import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.util.Arrays;
import java.util.List;

import jakarta.servlet.ServletException;
import jakarta.servlet.annotation.WebServlet;
import jakarta.servlet.http.HttpServlet;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import jakarta.servlet.http.HttpSession;

@WebServlet(name = "EmployeeMaintenanceRequestServlet", urlPatterns = {"/EmployeeMaintenanceRequestServlet"})
public class EmployeeMaintenanceRequestServlet extends HttpServlet {

    private static final List<String> VALID_PRIORITIES = Arrays.asList("LOW", "MEDIUM", "HIGH", "CRITICAL");

    @Override
    protected void doPost(HttpServletRequest request, HttpServletResponse response)
            throws ServletException, IOException {
        
        request.setCharacterEncoding("UTF-8");
        
        HttpSession session = request.getSession(false);
        if (session == null || session.getAttribute("username") == null || session.getAttribute("role") == null) {
            response.sendRedirect("login.jsp");
            return;
        }

        String role = (String) session.getAttribute("role");
        if (!"EMPLOYEE".equalsIgnoreCase(role)) {
            response.sendRedirect("dashboard.jsp?access=denied");
            return;
        }

        int employeeId = getSessionInt(session, "employee_id", 0);
        if (employeeId <= 0) {
            String username = (String) session.getAttribute("username");
            employeeId = getEmployeeIdByUsername(username);
            
            if (employeeId <= 0) {
                response.sendRedirect("employee_maintenance_request.jsp?error=invalid_employee");
                return;
            }
        }

        String assetIdStr = request.getParameter("assetId");
        String issueDescription = request.getParameter("issueDescription");
        String priority = request.getParameter("priority");

        int assetId = 0;
        try {
            assetId = Integer.parseInt(assetIdStr);
        } catch (NumberFormatException e) {
            response.sendRedirect("employee_maintenance_request.jsp?error=invalid_asset");
            return;
        }

        if (issueDescription == null || issueDescription.trim().isEmpty()) {
            response.sendRedirect("employee_maintenance_request.jsp?error=empty_desc");
            return;
        }

        String normalizedPriority = priority == null ? "" : priority.trim().toUpperCase();
        if (!VALID_PRIORITIES.contains(normalizedPriority)) {
            normalizedPriority = "MEDIUM";
        }

        MaintenanceRequestDAO dao = new MaintenanceRequestDAO();

        // Security check: ensure asset belongs to employee
        if (!dao.isAssetCurrentlyAllottedToEmployee(assetId, employeeId)) {
            response.sendRedirect("employee_maintenance_request.jsp?error=not_allotted");
            return;
        }

        boolean success = dao.createMaintenanceRequest(assetId, employeeId, issueDescription, normalizedPriority);

        if (success) {
            int userId = getSessionInt(session, "user_id", employeeId);
            AuditDAO.log(
                    userId,
                    "ADD",
                    "maintenance_requests",
                    assetId,
                    "Maintenance request submitted by employee. Asset ID: " + assetId
                    + ", Priority: " + normalizedPriority
                    + ", Employee ID: " + employeeId
            );
            response.sendRedirect("employee_maintenance_request.jsp?msg=request_submitted");
        } else {
            response.sendRedirect("employee_maintenance_request.jsp?error=submission_failed");
        }
    }

    private int getSessionInt(HttpSession session, String key, int fallback) {
        try {
            Object value = session.getAttribute(key);
            if (value == null) return fallback;
            return Integer.parseInt(String.valueOf(value));
        } catch (Exception e) {
            return fallback;
        }
    }
    
    private int getEmployeeIdByUsername(String username) {
        int empId = 0;
        if (username == null || username.trim().isEmpty()) return empId;
        
        // Match user's employee_id or fallback to LOWER(username) = LOWER(employee_code)
        String sql = "SELECT e.employee_id FROM employees e "
                   + "LEFT JOIN users u ON u.employee_id = e.employee_id "
                   + "WHERE u.username = ? OR LOWER(e.employee_code) = LOWER(?) LIMIT 1";
                   
        try (Connection con = DBConnection.getConnection();
             PreparedStatement ps = con.prepareStatement(sql)) {
             
            ps.setString(1, username);
            ps.setString(2, username);
            
            try (ResultSet rs = ps.executeQuery()) {
                if (rs.next()) {
                    empId = rs.getInt(1);
                }
            }
        } catch (Exception e) {
            e.printStackTrace();
        }
        return empId;
    }
}
