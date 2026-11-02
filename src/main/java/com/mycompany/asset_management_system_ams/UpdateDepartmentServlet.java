package com.mycompany.asset_management_system_ams;

import jakarta.servlet.ServletException;
import jakarta.servlet.annotation.WebServlet;
import jakarta.servlet.http.HttpServlet;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import jakarta.servlet.http.HttpSession;
import java.io.IOException;

@WebServlet(name = "UpdateDepartmentServlet", urlPatterns = {"/UpdateDepartmentServlet"})
public class UpdateDepartmentServlet extends HttpServlet {

    @Override
    protected void doPost(HttpServletRequest request, HttpServletResponse response)
            throws ServletException, IOException {

        HttpSession session = request.getSession(false);
        if (session == null || session.getAttribute("username") == null || session.getAttribute("role") == null) {
            response.sendRedirect("login.jsp");
            return;
        }

        String role = String.valueOf(session.getAttribute("role"));
        if (!RoleAccessUtil.hasAccess(role, "DEPARTMENT_MANAGEMENT", "EDIT")) {
            response.sendRedirect("departments.jsp?access=denied");
            return;
        }

        String idStr = request.getParameter("department_id");
        String code = request.getParameter("department_code");
        String name = request.getParameter("department_name");
        String description = request.getParameter("description");
        String headStr = request.getParameter("department_head_user_id");
        String status = request.getParameter("status");

        if (idStr == null || idStr.trim().isEmpty() || code == null || code.trim().isEmpty() || name == null || name.trim().isEmpty()) {
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

        code = code.trim();
        name = name.trim();

        if (DepartmentDAO.isDepartmentCodeExists(code, id)) {
            response.sendRedirect("edit_department.jsp?id=" + id + "&error=duplicatecode");
            return;
        }

        if (DepartmentDAO.isDepartmentNameExists(name, id)) {
            response.sendRedirect("edit_department.jsp?id=" + id + "&error=duplicatename");
            return;
        }

        Department d = new Department();
        d.setDepartmentId(id);
        d.setDepartmentCode(code);
        d.setDepartmentName(name);
        d.setDescription(description != null ? description.trim() : "");
        d.setStatus(status != null && status.equalsIgnoreCase("INACTIVE") ? "INACTIVE" : "ACTIVE");
        
        try {
            if (headStr != null && !headStr.trim().isEmpty()) {
                d.setDepartmentHeadUserId(Integer.parseInt(headStr));
            }
        } catch (NumberFormatException e) {
            // ignore
        }

        Department oldD = DepartmentDAO.getDepartmentById(id);
        boolean headChanged = false;
        if (oldD != null) {
            headChanged = oldD.getDepartmentHeadUserId() != d.getDepartmentHeadUserId();
        }

        boolean success = DepartmentDAO.updateDepartment(d);

        if (success) {
            int userId = 0;
            if (session.getAttribute("user_id") != null) {
                userId = Integer.parseInt(String.valueOf(session.getAttribute("user_id")));
            }
            AuditDAO.log(userId, "UPDATE", "departments", id, "Updated department: " + name + " (" + code + ")");
            
            try {
                String action = headChanged ? "HEAD_CHANGED" : "UPDATED";
                NotificationEventService.EmailRouting routing = NotificationEventService.buildDepartmentRecipients(action, id);
                // Fault: same class of finding already fixed on the Assets/
                // Employees modules - form-submitted free text landing straight
                // in an HTML email body with no escaping.
                String detailsTable = "<tr><th>Action:</th><td>Department Updated</td></tr>"
                        + "<tr><th>Department Code:</th><td>" + HtmlEscapeUtil.escape(code) + "</td></tr>"
                        + "<tr><th>Department Name:</th><td>" + HtmlEscapeUtil.escape(name) + "</td></tr>";
                if (headChanged) {
                    detailsTable += "<tr><th>Status:</th><td>Department Head Changed</td></tr>";
                }
                String body = NotificationHelper.buildHtmlEmail("", "DEPARTMENT UPDATED", detailsTable, "");
                NotificationHelper.sendNotification(
                        getServletContext(), "DEPT_ALERT", "DEPARTMENT_MANAGEMENT", id, 
                        routing.getToEmail(), routing.getCcEmail(), "", "IR-AMS | Department Updated | " + code, body);
            } catch (Exception e) {
                e.printStackTrace();
            }

            response.sendRedirect("departments.jsp?msg=updated");
        } else {
            response.sendRedirect("edit_department.jsp?id=" + id + "&error=server");
        }
    }
}
