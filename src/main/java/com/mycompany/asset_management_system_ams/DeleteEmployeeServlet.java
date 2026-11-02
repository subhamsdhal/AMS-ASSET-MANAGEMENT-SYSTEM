package com.mycompany.asset_management_system_ams;

import java.io.IOException;

import jakarta.servlet.ServletException;
import jakarta.servlet.annotation.WebServlet;
import jakarta.servlet.http.HttpServlet;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import jakarta.servlet.http.HttpSession;

@WebServlet(name = "DeleteEmployeeServlet", urlPatterns = {"/DeleteEmployeeServlet"})
public class DeleteEmployeeServlet extends HttpServlet {

    // Deleting an employee is a state change and must only happen on POST -
    // this used to be doGet(), reachable via a plain <a href> link on
    // employees.jsp with only a client-side confirm() dialog for protection.
    // Same "state change via GET" pattern fixed on DisableEmployeeServlet
    // above and UpdateCategoryStatusServlet/resolve_maintenance.jsp earlier
    // in this audit - more consequential here since this is an actual
    // (soft-)delete, not just a deactivation.
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

            int userId = getSessionInt(session, "user_id", 0);

            if (userId == 0) {
                userId = getSessionInt(session, "userId", 0);
            }

            int auditUserId = userId > 0 ? userId : 1;

            int employeeId = Integer.parseInt(request.getParameter("id"));

            EmployeeDAO dao = new EmployeeDAO();
            Employee employee = dao.getEmployeeById(employeeId);

            if (employee == null) {
                AuditDAO.log(
                        auditUserId,
                        "DELETE_BLOCKED",
                        "employees",
                        employeeId,
                        "Employee delete blocked. Employee record not found. Attempted by "
                        + username + " (" + formatRoleName(role) + ")."
                );

                response.sendRedirect("employees.jsp?error=deleteinvalid");
                return;
            }

            boolean isSuperAdmin = ("SUPER_ADMIN".equals(role) || "ADMIN".equals(role));
            boolean isDepartmentHead = "DEPARTMENT_HEAD".equalsIgnoreCase(role);

            if (!isSuperAdmin && !isDepartmentHead) {
                AuditDAO.log(
                        auditUserId,
                        "DELETE_BLOCKED",
                        "employees",
                        employeeId,
                        "Unauthorized employee delete attempt by "
                        + username + " (" + formatRoleName(role) + "). Employee: "
                        + buildEmployeeShortName(employee)
                );

                response.sendRedirect("employees.jsp?error=deleteunauthorized");
                return;
            }

            if (isDepartmentHead && !dao.isEmployeeUnderDepartmentHead(employeeId, userId)) {
                AuditDAO.log(
                        auditUserId,
                        "DELETE_BLOCKED",
                        "employees",
                        employeeId,
                        "Department Head delete blocked. Employee does not belong to this Department Head's department. "
                        + "Attempted by " + username + " (" + formatRoleName(role) + "). Employee: "
                        + buildEmployeeShortName(employee)
                );

                response.sendRedirect("employees.jsp?error=deletewrongdept");
                return;
            }

            String blockReason = dao.getEmployeeDeleteBlockReason(employeeId);

            if (blockReason != null && !blockReason.trim().isEmpty()) {
                AuditDAO.log(
                        auditUserId,
                        "DELETE_BLOCKED",
                        "employees",
                        employeeId,
                        "Employee delete blocked by system. Employee: "
                        + buildEmployeeShortName(employee)
                        + ". Reason: " + blockReason
                        + " Attempted by " + username + " (" + formatRoleName(role) + ")."
                );

                response.sendRedirect("employees.jsp?error=deleteblocked");
                return;
            }

            String employeeSummary = buildEmployeeSnapshot(employee);

            String deleteReason = "Removed from employee directory after deactivation. "
                    + "Historical references, asset records, return records and audit logs retained.";

            NotificationEventService.EmailRouting routing = NotificationEventService.buildEmployeeRecipients("DISABLED_DELETED", employeeId);
            String toEmail = routing.getToEmail();
            String ccEmail = routing.getCcEmail();

            boolean deleted = dao.deleteEmployeePermanently(employeeId, auditUserId, deleteReason);

            if (deleted) {
                AuditDAO.log(
                        auditUserId,
                        "DELETE",
                        "employees",
                        employeeId,
                        "Employee removed from active employee directory by "
                        + username + " (" + formatRoleName(role) + "). "
                        + "Employee master record retained as soft-deleted for historical integrity. "
                        + "Deleted employee snapshot: "
                        + employeeSummary
                );

                sendEmployeeDeleteNotification(
                        employeeId,
                        employee,
                        username,
                        role,
                        NotificationHelper.getUserEmailByUsername(username),
                        toEmail,
                        ccEmail
                    );

                response.sendRedirect("employees.jsp?msg=deleted");

            } else {
                AuditDAO.log(
                        auditUserId,
                        "DELETE_BLOCKED",
                        "employees",
                        employeeId,
                        "Employee delete failed by system. Employee: "
                        + employeeSummary
                        + ". Attempted by " + username + " (" + formatRoleName(role) + ")."
                );

                response.sendRedirect("employees.jsp?error=deletefailed");
            }

        } catch (Exception e) {
            e.printStackTrace();
            response.sendRedirect("employees.jsp?error=server");
        }
    }

    private void sendEmployeeDeleteNotification(
            int employeeId,
            Employee employee,
            String deletedBy,
            String deleterRole,
            String deleterEmail,
            String toEmail,
            String ccEmail
    ) {
        try {
            if (toEmail == null || toEmail.trim().isEmpty()) {
                return;
            }

            String subject = "IR-AMS | Employee Removed from Directory | "
                    + safe(employee.getEmployeeCode(), "N/A");

            // Fault: same class of finding already fixed in DisposeAssetServlet -
            // free-text fields landing in an HTML email body unescaped.
            String detailsTable = "<tr><th>Status:</th><td>Employee Removed from Active Directory</td></tr>"
                    + "<tr><th>Priority:</th><td>High</td></tr>"
                    + "<tr><th>Module:</th><td>Employee Administration</td></tr>"
                    + "<tr><th>Reference ID:</th><td>" + HtmlEscapeUtil.escape(safe(employee.getEmployeeCode(), "N/A")) + " / Employee ID " + employeeId + "</td></tr>"
                    + "<tr><td colspan='2' style='background-color: #f1f5f9; text-align: center;'><b>EMPLOYEE SNAPSHOT</b></td></tr>"
                    + "<tr><th>Employee Code:</th><td>" + HtmlEscapeUtil.escape(safe(employee.getEmployeeCode(), "N/A")) + "</td></tr>"
                    + "<tr><th>Name:</th><td>" + HtmlEscapeUtil.escape(safe(employee.getEmployeeName(), "")) + "</td></tr>"
                    + "<tr><th>Department:</th><td>" + HtmlEscapeUtil.escape(safe(employee.getDepartmentName(), "N/A")) + "</td></tr>"
                    + "<tr><th>Designation:</th><td>" + HtmlEscapeUtil.escape(safe(employee.getDesignation(), "N/A")) + "</td></tr>"
                    + "<tr><th>Email:</th><td>" + HtmlEscapeUtil.escape(safe(employee.getEmail(), "N/A")) + "</td></tr>"
                    + "<tr><th>Phone:</th><td>" + HtmlEscapeUtil.escape(safe(employee.getPhone(), "N/A")) + "</td></tr>"
                    + "<tr><th>Joining Date:</th><td>" + safe(employee.getJoiningDate(), "N/A") + "</td></tr>"
                    + "<tr><th>Previous Status:</th><td>" + safe(employee.getStatus(), "N/A") + "</td></tr>"
                    + "<tr><td colspan='2' style='background-color: #f1f5f9; text-align: center;'><b>ACTION BY</b></td></tr>"
                    + "<tr><th>User:</th><td>" + HtmlEscapeUtil.escape(safe(deletedBy, "N/A")) + "</td></tr>"
                    + "<tr><th>Role:</th><td>" + formatRoleName(deleterRole) + "</td></tr>"
                    + "<tr><th>Account:</th><td>" + HtmlEscapeUtil.escape(safe(deleterEmail, "N/A")) + "</td></tr>"
                    + "<tr><td colspan='2' style='background-color: #f1f5f9; text-align: center;'><b>AUDIT NOTE</b></td></tr>"
                    // Fault: overclaimed "no longer visible in the active employee
                    // directory" - employees.jsp's own list defaults to showing every
                    // status (its own filter dropdown defaults to "All Status", not
                    // "Active Only"), so a deleted/deactivated employee stays visible
                    // there by default, just tagged Inactive - only genuinely true for
                    // allocation eligibility (AssetAllocationDAO.isActiveEmployee()
                    // requires employee_status = 'ACTIVE'). Reworded to match reality.
                    + "<tr><td colspan='2'>The employee's status has been set to Inactive and they are no longer eligible for new asset allocations. They still appear in the employee directory (filterable by status) with their historical allocation, return and audit records retained.</td></tr>";
            
            String actionNote = "";

            String body = NotificationHelper.buildHtmlEmail("", "EMPLOYEE DIRECTORY UPDATE", detailsTable, actionNote);

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

    private String buildEmployeeShortName(Employee employee) {
        return safe(employee.getEmployeeCode(), "N/A")
                + " - "
                + safe(employee.getEmployeeName(), "");
    }

    private String buildEmployeeSnapshot(Employee employee) {
        return safe(employee.getEmployeeCode(), "N/A")
                + " - "
                + safe(employee.getEmployeeName(), "")
                + " | Department: "
                + safe(employee.getDepartmentName(), "N/A")
                + " | Designation: "
                + safe(employee.getDesignation(), "N/A")
                + " | Email: "
                + safe(employee.getEmail(), "N/A")
                + " | Phone: "
                + safe(employee.getPhone(), "N/A")
                + " | Joining Date: "
                + safe(employee.getJoiningDate(), "N/A")
                + " | Status: "
                + safe(employee.getStatus(), "N/A");
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
}