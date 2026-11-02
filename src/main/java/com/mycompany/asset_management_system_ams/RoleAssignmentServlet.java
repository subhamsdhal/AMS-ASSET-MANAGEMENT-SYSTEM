package com.mycompany.asset_management_system_ams;

import java.io.IOException;
import jakarta.servlet.ServletException;
import jakarta.servlet.annotation.WebServlet;
import jakarta.servlet.http.HttpServlet;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import jakarta.servlet.http.HttpSession;

@WebServlet(name = "RoleAssignmentServlet", urlPatterns = {"/RoleAssignmentServlet"})
public class RoleAssignmentServlet extends HttpServlet {

    @Override
    protected void doPost(HttpServletRequest request, HttpServletResponse response)
            throws ServletException, IOException {

        HttpSession session = request.getSession(false);
        if (session == null || session.getAttribute("username") == null || session.getAttribute("role") == null) {
            response.sendRedirect("login.jsp");
            return;
        }

        String userRole = (String) session.getAttribute("role");
        if (!("DEPARTMENT_HEAD".equals(userRole) || "ADMIN".equals(userRole))) {
            response.sendError(HttpServletResponse.SC_FORBIDDEN, "Unauthorized access.");
            return;
        }

        // Was a raw (Integer) cast with no fallback - every other servlet in this
        // app uses this same defensive getSessionInt() pattern specifically
        // because an unguarded cast throws an uncaught NPE/ClassCastException
        // (a raw 500 error page, potentially leaking a stack trace) instead of a
        // clean redirect if "user_id" is ever missing from an otherwise-valid
        // session.
        int performedByUserId = getSessionInt(session, "user_id", 0);
        if (performedByUserId <= 0) {
            performedByUserId = getSessionInt(session, "userId", 0);
        }
        if (performedByUserId <= 0) {
            response.sendRedirect("login.jsp");
            return;
        }

        String action = request.getParameter("action");

        try {
            if ("ASSIGN".equalsIgnoreCase(action)) {
                int employeeId = Integer.parseInt(request.getParameter("employee_id"));
                String roleCode = request.getParameter("role_code");
                if (roleCode != null) {
                    roleCode = roleCode.trim().toUpperCase(java.util.Locale.ENGLISH);
                }
                String designationTitle = null;
                String remarks = "Assigned from Role & Duty Assignment module";
                
                if ("SUPER_ADMIN".equals(roleCode)) {
                    throw new Exception("SUPER_ADMIN role cannot be assigned dynamically.");
                }
                
                if ("DEPARTMENT_HEAD".equals(userRole)) {
                    EmployeeDAO empDao = new EmployeeDAO();
                    if (!empDao.isEmployeeUnderDepartmentHead(employeeId, performedByUserId)) {
                        response.sendError(HttpServletResponse.SC_FORBIDDEN, "You can only assign roles to employees within your department.");
                        return;
                    }
                }

                if ("EMPLOYEE".equals(roleCode)) {
                    java.util.List<java.util.Map<String, String>> oldRolesList = RoleAssignmentDAO.getActiveRolesByEmployeeId(employeeId);
                    String oldRoles = oldRolesList.stream().map(m -> m.get("role_code")).collect(java.util.stream.Collectors.joining(","));
                    if (oldRoles.isEmpty()) oldRoles = "Unknown";
                    
                    boolean success = RoleAssignmentDAO.deactivateAllRolesForEmployee(employeeId, performedByUserId);
                    if (success) {
                        AuditDAO.log(performedByUserId, "ROLE_DUTY_ASSIGNMENT", "employee_role_assignments", employeeId, "Reset EMP" + String.format("%03d", employeeId) + " from " + oldRoles + " to EMPLOYEE");
                        response.sendRedirect("role_assignment.jsp?msg=deactivated");
                    } else {
                        response.sendRedirect("role_assignment.jsp?error=reset_failed");
                    }
                    return;
                }
                
                String deptStr = request.getParameter("department_id");
                Integer departmentId = null;
                if (deptStr != null && !deptStr.trim().isEmpty()) {
                    departmentId = Integer.parseInt(deptStr);
                }

                if ("DEPARTMENT_HEAD".equals(roleCode) && departmentId == null) {
                    throw new Exception("Department is mandatory for DEPARTMENT_HEAD role.");
                }

                boolean success = RoleAssignmentDAO.assignRoleToEmployee(employeeId, roleCode, departmentId, designationTitle, performedByUserId, remarks);

                if (success) {
                    String auditMsg = "Assigned role " + roleCode + " to employee " + employeeId + " with designation " + designationTitle;
                    if (departmentId != null) auditMsg += " for department " + departmentId;
                    AuditDAO.log(performedByUserId, "ROLE_DUTY_ASSIGNMENT", "employee_role_assignments", employeeId, auditMsg);
                    
                    response.sendRedirect("role_assignment.jsp?msg=assigned");
                } else {
                    response.sendRedirect("role_assignment.jsp?error=assign_failed");
                }
                
            } else if ("DEACTIVATE".equalsIgnoreCase(action)) {
                int assignmentId = Integer.parseInt(request.getParameter("assignment_id"));
                String targetRole = request.getParameter("target_role");
                if (targetRole != null) {
                    targetRole = targetRole.trim().toUpperCase(java.util.Locale.ENGLISH);
                }
                
                if ("SUPER_ADMIN".equals(targetRole)) {
                    throw new Exception("SUPER_ADMIN role cannot be deactivated dynamically.");
                }
                
                if (RoleAssignmentDAO.isAssignmentForProtected(assignmentId)) {
                    throw new Exception("The protected background accounts cannot be modified.");
                }
                
                if ("DEPARTMENT_HEAD".equals(userRole)) {
                    EmployeeDAO empDao = new EmployeeDAO();
                    int targetEmployeeId = -1;
                    try (java.sql.Connection con = DBConnection.getConnection();
                         java.sql.PreparedStatement ps = con.prepareStatement("SELECT employee_id FROM employee_role_assignments WHERE assignment_id = ?")) {
                        ps.setInt(1, assignmentId);
                        try (java.sql.ResultSet rs = ps.executeQuery()) {
                            if (rs.next()) {
                                targetEmployeeId = rs.getInt("employee_id");
                            }
                        }
                    }
                    if (targetEmployeeId == -1 || !empDao.isEmployeeUnderDepartmentHead(targetEmployeeId, performedByUserId)) {
                        response.sendError(HttpServletResponse.SC_FORBIDDEN, "You can only deactivate roles for employees within your department.");
                        return;
                    }
                }
                
                boolean success = RoleAssignmentDAO.deactivateAssignment(assignmentId, performedByUserId);
                
                if (success) {
                    AuditDAO.log(performedByUserId, "ROLE_DUTY_ASSIGNMENT", "employee_role_assignments", assignmentId, "Deactivated role assignment " + assignmentId);
                    response.sendRedirect("role_assignment.jsp?msg=deactivated");
                } else {
                    response.sendRedirect("role_assignment.jsp?error=deact_failed");
                }
            } else {
                response.sendRedirect("role_assignment.jsp?error=invalid_action");
            }
        } catch (Exception e) {
            e.printStackTrace();
            response.sendRedirect("role_assignment.jsp?error=" + java.net.URLEncoder.encode(e.getMessage(), "UTF-8"));
        }
    }

    private int getSessionInt(HttpSession session, String key, int fallback) {
        try {
            Object value = session.getAttribute(key);
            return value == null ? fallback : Integer.parseInt(String.valueOf(value));
        } catch (Exception e) {
            return fallback;
        }
    }
}
