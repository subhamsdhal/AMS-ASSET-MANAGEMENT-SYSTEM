package com.mycompany.asset_management_system_ams;

import jakarta.servlet.ServletException;
import jakarta.servlet.annotation.WebServlet;
import jakarta.servlet.http.HttpServlet;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import jakarta.servlet.http.HttpSession;
import java.io.IOException;

@WebServlet(name = "DeleteDepartmentServlet", urlPatterns = {"/DeleteDepartmentServlet"})
public class DeleteDepartmentServlet extends HttpServlet {

    // Deleting a department is a permanent, hard SQL DELETE and must only
    // happen on POST - this used to be doGet(), reachable via a plain
    // <a href> link on departments.jsp with only a client-side confirm()
    // dialog for protection. Same "state change via GET" pattern fixed
    // repeatedly elsewhere in this audit (DisableEmployeeServlet,
    // DeleteEmployeeServlet, UpdateCategoryStatusServlet, resolve_maintenance.jsp).
    @Override
    protected void doPost(HttpServletRequest request, HttpServletResponse response)
            throws ServletException, IOException {

        HttpSession session = request.getSession(false);
        if (session == null || session.getAttribute("username") == null || session.getAttribute("role") == null) {
            response.sendRedirect("login.jsp");
            return;
        }

        String role = String.valueOf(session.getAttribute("role"));
        if (!RoleAccessUtil.hasAccess(role, "DEPARTMENT_MANAGEMENT", "DELETE")) {
            response.sendRedirect("departments.jsp?access=denied");
            return;
        }

        String idStr = request.getParameter("id");
        if (idStr == null || idStr.trim().isEmpty()) {
            response.sendRedirect("departments.jsp?error=invalid");
            return;
        }

        int id = 0;
        try {
            id = Integer.parseInt(idStr);
        } catch (NumberFormatException e) {
            response.sendRedirect("departments.jsp?error=invalid");
            return;
        }

        Department d = DepartmentDAO.getDepartmentById(id);
        if (d == null) {
            response.sendRedirect("departments.jsp?error=invalid");
            return;
        }

        // Fault: used to only check assets/employees - see
        // DepartmentDAO.getDepartmentDeleteBlockReason() for the full
        // explanation of why that missed two silent-data-loss cases and one
        // confusing-server-error case.
        String blockReason = DepartmentDAO.getDepartmentDeleteBlockReason(id);
        if (!blockReason.isEmpty()) {
            response.sendRedirect("departments.jsp?error=deleteblocked&reason="
                    + java.net.URLEncoder.encode(blockReason, "UTF-8"));
            return;
        }

        boolean success = DepartmentDAO.deleteDepartment(id);

        if (success) {
            int userId = 0;
            if (session.getAttribute("user_id") != null) {
                userId = Integer.parseInt(String.valueOf(session.getAttribute("user_id")));
            }
            AuditDAO.log(userId, "DELETE", "departments", id, "Deleted department: " + d.getDepartmentName() + " (" + d.getDepartmentCode() + ")");
            
            try {
                NotificationEventService.EmailRouting routing = NotificationEventService.buildDepartmentRecipients("DELETED", id);
                // Fault: same class of finding already fixed on the Assets/
                // Employees modules - free-text fields landing straight in an
                // HTML email body with no escaping.
                String detailsTable = "<tr><th>Action:</th><td>Department Deleted</td></tr>"
                        + "<tr><th>Department Code:</th><td>" + HtmlEscapeUtil.escape(d.getDepartmentCode()) + "</td></tr>"
                        + "<tr><th>Department Name:</th><td>" + HtmlEscapeUtil.escape(d.getDepartmentName()) + "</td></tr>";
                String body = NotificationHelper.buildHtmlEmail("", "DEPARTMENT DELETED", detailsTable, "");
                NotificationHelper.sendNotification(
                        getServletContext(), "DEPT_ALERT", "DEPARTMENT_MANAGEMENT", id, 
                        routing.getToEmail(), routing.getCcEmail(), "", "IR-AMS | Department Deleted | " + d.getDepartmentCode(), body);
            } catch (Exception e) {
                e.printStackTrace();
            }

            response.sendRedirect("departments.jsp?msg=deleted");
        } else {
            response.sendRedirect("departments.jsp?error=server");
        }
    }
}
