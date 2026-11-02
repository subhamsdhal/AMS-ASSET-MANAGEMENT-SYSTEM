package com.mycompany.asset_management_system_ams;

import jakarta.servlet.ServletException;
import jakarta.servlet.annotation.WebServlet;
import jakarta.servlet.http.HttpServlet;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import jakarta.servlet.http.HttpSession;
import java.io.IOException;

@WebServlet(name = "DeleteEmployeeDocumentServlet", urlPatterns = {"/DeleteEmployeeDocumentServlet"})
public class DeleteEmployeeDocumentServlet extends HttpServlet {

    @Override
    protected void doPost(HttpServletRequest request, HttpServletResponse response)
            throws ServletException, IOException {

        try {
            HttpSession session = request.getSession(false);

            if (session == null || session.getAttribute("username") == null || session.getAttribute("role") == null) {
                response.sendRedirect("login.jsp");
                return;
            }

            String username = String.valueOf(session.getAttribute("username"));
            String role = String.valueOf(session.getAttribute("role"));
            int userId = getSessionInt(session, "user_id", 1);
            if (userId == 1) {
                userId = getSessionInt(session, "userId", 1);
            }

            int documentId = parseInt(request.getParameter("id"), 0);
            int employeeId = parseInt(request.getParameter("employeeId"), 0);

            boolean isDepartmentHead = "DEPARTMENT_HEAD".equalsIgnoreCase(role);
            boolean isSuperAdminOrAdmin = "SUPER_ADMIN".equals(role) || "ADMIN".equals(role);

            if (!isSuperAdminOrAdmin && !isDepartmentHead) {
                if (employeeId > 0) {
                    response.sendRedirect("view_employee.jsp?id=" + employeeId + "&error=delete_denied");
                } else {
                    response.sendRedirect("employees.jsp?error=delete_denied");
                }
                return;
            }

            if (isDepartmentHead && employeeId > 0) {
                EmployeeDAO empDao = new EmployeeDAO();
                if (!empDao.isEmployeeUnderDepartmentHead(employeeId, userId)) {
                    response.sendRedirect("employees.jsp?access=denied");
                    return;
                }
            }

            if (documentId <= 0 || employeeId <= 0) {
                if (employeeId > 0) {
                    response.sendRedirect("view_employee.jsp?id=" + employeeId + "&error=invalid_document");
                } else {
                    response.sendRedirect("employees.jsp?error=invalid_document");
                }
                return;
            }

            EmployeeDocumentDAO dao = new EmployeeDocumentDAO();
            boolean success = dao.deactivateEmployeeDocument(documentId);

            if (success) {
                AuditDAO.log(
                        userId,
                        "EMP_DOC_DELETE",
                        "employee_documents",
                        documentId,
                        "Employee document soft deleted. Employee ID: " + employeeId + ", Document ID: " + documentId + ", Deleted by: " + username
                );
                response.sendRedirect("view_employee.jsp?id=" + employeeId + "&msg=document_deleted");
            } else {
                response.sendRedirect("view_employee.jsp?id=" + employeeId + "&error=delete_failed");
            }

        } catch (Exception e) {
            e.printStackTrace();
            response.sendRedirect("employees.jsp?error=server");
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

    private int parseInt(String value, int fallback) {
        try {
            return Integer.parseInt(value == null ? "" : value.trim());
        } catch (Exception e) {
            return fallback;
        }
    }
}
