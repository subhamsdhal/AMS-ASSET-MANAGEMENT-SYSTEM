package com.mycompany.asset_management_system_ams;

import jakarta.servlet.ServletException;
import jakarta.servlet.annotation.WebServlet;
import jakarta.servlet.http.HttpServlet;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import jakarta.servlet.http.HttpSession;
import java.io.IOException;

@WebServlet(name = "AddDepartmentServlet", urlPatterns = {"/AddDepartmentServlet"})
public class AddDepartmentServlet extends HttpServlet {

    @Override
    protected void doPost(HttpServletRequest request, HttpServletResponse response)
            throws ServletException, IOException {

        HttpSession session = request.getSession(false);
        if (session == null || session.getAttribute("username") == null || session.getAttribute("role") == null) {
            response.sendRedirect("login.jsp");
            return;
        }

        String role = String.valueOf(session.getAttribute("role"));
        if (!RoleAccessUtil.hasAccess(role, "DEPARTMENT_MANAGEMENT", "CREATE")) {
            response.sendRedirect("departments.jsp?access=denied");
            return;
        }

        String code = request.getParameter("department_code");
        String name = request.getParameter("department_name");
        String description = request.getParameter("description");
        String headStr = request.getParameter("department_head_user_id");
        String status = request.getParameter("status");

        if (code == null || code.trim().isEmpty() || name == null || name.trim().isEmpty()) {
            response.sendRedirect("add_department.jsp?error=invalid");
            return;
        }

        code = code.trim();
        name = name.trim();

        if (DepartmentDAO.isDepartmentCodeExists(code, 0)) {
            response.sendRedirect("add_department.jsp?error=duplicatecode");
            return;
        }

        if (DepartmentDAO.isDepartmentNameExists(name, 0)) {
            response.sendRedirect("add_department.jsp?error=duplicatename");
            return;
        }

        Department d = new Department();
        d.setDepartmentCode(code);
        d.setDepartmentName(name);
        d.setDescription(description != null ? description.trim() : "");
        d.setStatus(status != null && status.equalsIgnoreCase("INACTIVE") ? "INACTIVE" : "ACTIVE");
        
        try {
            if (headStr != null && !headStr.trim().isEmpty()) {
                d.setDepartmentHeadUserId(Integer.parseInt(headStr));
            }
        } catch (NumberFormatException e) {
            // ignore, keep 0
        }

        boolean success = DepartmentDAO.addDepartment(d);

        if (success) {
            int userId = 0;
            if (session.getAttribute("user_id") != null) {
                userId = Integer.parseInt(String.valueOf(session.getAttribute("user_id")));
            }
            AuditDAO.log(userId, "CREATE", "departments", (Integer) null, "Created new department: " + name + " (" + code + ")");
            
            try {
                NotificationEventService.EmailRouting routing = NotificationEventService.buildDepartmentRecipients("ADDED", 0);
                // Fault: same class of finding already fixed on the Assets/
                // Employees modules - form-submitted free text landing straight
                // in an HTML email body with no escaping.
                String detailsTable = "<tr><th>Action:</th><td>New Department Created</td></tr>"
                        + "<tr><th>Department Code:</th><td>" + HtmlEscapeUtil.escape(code) + "</td></tr>"
                        + "<tr><th>Department Name:</th><td>" + HtmlEscapeUtil.escape(name) + "</td></tr>";
                String body = NotificationHelper.buildHtmlEmail("", "DEPARTMENT ADDED", detailsTable, "");
                NotificationHelper.sendNotification(
                        getServletContext(), "DEPT_ALERT", "DEPARTMENT_MANAGEMENT", 0, 
                        routing.getToEmail(), routing.getCcEmail(), "", "IR-AMS | Department Added | " + code, body);
            } catch (Exception e) {
                e.printStackTrace();
            }
            
            response.sendRedirect("departments.jsp?msg=added");
        } else {
            response.sendRedirect("add_department.jsp?error=server");
        }
    }
}
