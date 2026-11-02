package com.mycompany.asset_management_system_ams;

import java.io.IOException;
import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;

import jakarta.servlet.ServletException;
import jakarta.servlet.annotation.WebServlet;
import jakarta.servlet.http.HttpServlet;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import jakarta.servlet.http.HttpSession;

@WebServlet(name = "DisableEmployeeServlet", urlPatterns = {"/DisableEmployeeServlet"})
public class DisableEmployeeServlet extends HttpServlet {

    // Deactivating an employee is a state change and must only happen on
    // POST - this used to be doGet(), reachable via a plain <a href> link on
    // employees.jsp with only a client-side confirm() dialog for protection.
    // Same "state change via GET" pattern already fixed on
    // UpdateCategoryStatusServlet/resolve_maintenance.jsp earlier in this
    // audit - an <img> tag, browser link-prefetch, or a crawler could have
    // silently deactivated an employee for whichever admin/dept-head had the
    // link loaded while logged in.
    @Override
    protected void doPost(HttpServletRequest request, HttpServletResponse response)
            throws ServletException, IOException {

        try {
            HttpSession session = request.getSession(false);

            if (session == null
                    || session.getAttribute("username") == null
                    || session.getAttribute("role") == null) {
                response.sendRedirect("login.jsp");
                return;
            }

            String username = String.valueOf(session.getAttribute("username"));
            String role = String.valueOf(session.getAttribute("role"));

            int userId = getSessionInt(session, "user_id", 1);

            if (userId == 1) {
                userId = getSessionInt(session, "userId", 1);
            }

            if (!canManageEmployeeRecords(role)) {
                response.sendRedirect("employees.jsp?access=denied");
                return;
            }

            int employeeId = Integer.parseInt(request.getParameter("id"));
            EmployeeDAO dao = new EmployeeDAO();

            if ("DEPARTMENT_HEAD".equalsIgnoreCase(role)) {
                if (!dao.isEmployeeUnderDepartmentHead(employeeId, userId)) {
                    response.sendRedirect("employees.jsp?access=denied");
                    return;
                }
            }

            Employee employee = dao.getEmployeeById(employeeId);

            if (employee == null) {
                response.sendRedirect("employees.jsp?error=invalid");
                return;
            }

            String previousStatus = safe(employee.getStatus(), "N/A");

            if ("INACTIVE".equalsIgnoreCase(previousStatus)) {
                response.sendRedirect("employees.jsp?msg=alreadyinactive");
                return;
            }

            boolean disabled = dao.disableEmployee(employeeId);

            if (disabled) {

                AuditDAO.log(
                        userId,
                        "DISABLE",
                        "employees",
                        employeeId,
                        "Employee record deactivated by " + username
                        + " (" + formatRoleName(role) + ")"
                        + ". Employee: " + safe(employee.getEmployeeCode(), "N/A")
                        + " - " + safe(employee.getEmployeeName(), "")
                        + ". Previous Status: " + previousStatus
                        + ". New Status: INACTIVE"
                );

                sendEmployeeDeactivationNotice(
                        employeeId,
                        employee,
                        previousStatus,
                        username,
                        role,
                        NotificationHelper.getUserEmailByUsername(username)
                );

                response.sendRedirect("employees.jsp?msg=disabled");

            } else {
                response.sendRedirect("employees.jsp?error=disablefailed");
            }

        } catch (Exception e) {
            e.printStackTrace();
            response.sendRedirect("employees.jsp?error=server");
        }
    }

    private boolean canManageEmployeeRecords(String role) {
        return ("SUPER_ADMIN".equals(role) || "ADMIN".equals(role))
                || "DEPARTMENT_HEAD".equalsIgnoreCase(role);
    }

    private void sendEmployeeDeactivationNotice(
            int employeeId,
            Employee employee,
            String previousStatus,
            String disabledBy,
            String disablerRole,
            String disablerEmail
    ) {
        try {
            NotificationEventService.EmailRouting routing = NotificationEventService.buildEmployeeRecipients("DISABLED_DELETED", employeeId);
            String toEmail = routing.getToEmail();
            String ccEmail = routing.getCcEmail();

            String employeeCode = safe(employee.getEmployeeCode(), "N/A");

            String subject = "IR-AMS | Employee Record Deactivated | " + employeeCode;

            // Fault: same class of finding already fixed in DisposeAssetServlet -
            // free-text fields landing in an HTML email body unescaped.
            String detailsTable = "<tr><th>Status:</th><td>Deactivation Completed</td></tr>"
                    + "<tr><th>Priority:</th><td>High</td></tr>"
                    + "<tr><th>Module:</th><td>Employee Administration</td></tr>"
                    + "<tr><th>Reference ID:</th><td>" + HtmlEscapeUtil.escape(safe(employee.getEmployeeCode(), "N/A")) + " / Employee ID " + employeeId + "</td></tr>"
                    + "<tr><td colspan='2' style='background-color: #f1f5f9; text-align: center;'><b>STATUS CHANGE</b></td></tr>"
                    + "<tr><th>Field Updated:</th><td>Record Status</td></tr>"
                    + "<tr><th>Previous:</th><td>" + formatNormalText(previousStatus) + "</td></tr>"
                    + "<tr><th>Current:</th><td>Inactive</td></tr>"
                    + "<tr><td colspan='2' style='background-color: #f1f5f9; text-align: center;'><b>EMPLOYEE RECORD</b></td></tr>"
                    + "<tr><th>Employee Code:</th><td>" + HtmlEscapeUtil.escape(safe(employee.getEmployeeCode(), "N/A")) + "</td></tr>"
                    + "<tr><th>Name:</th><td>" + HtmlEscapeUtil.escape(safe(employee.getEmployeeName(), "")) + "</td></tr>"
                    + "<tr><th>Department:</th><td>" + HtmlEscapeUtil.escape(safe(employee.getDepartmentName(), "N/A")) + "</td></tr>"
                    + "<tr><th>Designation:</th><td>" + HtmlEscapeUtil.escape(safe(employee.getDesignation(), "N/A")) + "</td></tr>"
                    + "<tr><th>Email:</th><td>" + HtmlEscapeUtil.escape(safe(employee.getEmail(), "N/A")) + "</td></tr>"
                    + "<tr><th>Phone:</th><td>" + HtmlEscapeUtil.escape(safe(employee.getPhone(), "N/A")) + "</td></tr>"
                    + "<tr><td colspan='2' style='background-color: #f1f5f9; text-align: center;'><b>DEACTIVATED BY</b></td></tr>"
                    + "<tr><th>User:</th><td>" + HtmlEscapeUtil.escape(safe(disabledBy, "N/A")) + "</td></tr>"
                    + "<tr><th>Role:</th><td>" + formatRoleName(disablerRole) + "</td></tr>"
                    + "<tr><th>Account:</th><td>" + HtmlEscapeUtil.escape(safe(disablerEmail, "N/A")) + "</td></tr>";
            
            String actionNote = "Review linked user access, active asset allocations, pending requests, and department records associated with this employee.";

            String body = NotificationHelper.buildHtmlEmail("", "EMPLOYEE STATUS UPDATE", detailsTable, actionNote);

            NotificationHelper.sendNotification(
                    getServletContext(),
                    "EMPLOYEE_ADMIN_ALERT",
                    "EMPLOYEE_MANAGEMENT",
                    employeeId,
                    toEmail,
                    ccEmail,
                    "",
                    subject,
                    body
            );

        } catch (Exception e) {
            e.printStackTrace();
        }
    }

    private int getSessionInt(HttpSession session, String key, int fallback) {
        try {
            Object value = session.getAttribute(key);

            if (value == null) {
                return fallback;
            }

            return Integer.parseInt(String.valueOf(value));

        } catch (Exception e) {
            return fallback;
        }
    }

    private String safe(String value, String fallback) {
        if (value == null || value.trim().isEmpty()) {
            return fallback;
        }

        return value.trim();
    }

    private String formatRoleName(String roleName) {
        if (roleName == null || roleName.trim().isEmpty()) {
            return "N/A";
        }

        String text = roleName.trim().replace("_", " ").toLowerCase();
        String[] words = text.split(" ");
        StringBuilder formatted = new StringBuilder();

        for (String word : words) {
            if (word.trim().isEmpty()) {
                continue;
            }

            formatted.append(word.substring(0, 1).toUpperCase())
                    .append(word.substring(1))
                    .append(" ");
        }

        return formatted.toString().trim();
    }

    private String formatNormalText(String value) {
        if (value == null || value.trim().isEmpty()) {
            return "N/A";
        }

        String text = value.trim().replace("_", " ").toLowerCase();
        return text.substring(0, 1).toUpperCase() + text.substring(1);
    }

}