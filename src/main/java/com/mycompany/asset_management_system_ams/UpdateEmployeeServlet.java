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

@WebServlet(name = "UpdateEmployeeServlet", urlPatterns = {"/UpdateEmployeeServlet"})
public class UpdateEmployeeServlet extends HttpServlet {

    @Override
    protected void doPost(HttpServletRequest request, HttpServletResponse response)
            throws ServletException, IOException {

        try {
            request.setCharacterEncoding("UTF-8");

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

            int employeeId = parseInt(request.getParameter("employeeId"), 0);

            if ("DEPARTMENT_HEAD".equalsIgnoreCase(role)) {
                EmployeeDAO dao = new EmployeeDAO();
                if (!dao.isEmployeeUnderDepartmentHead(employeeId, userId)) {
                    response.sendRedirect("employees.jsp?access=denied");
                    return;
                }
            }

            String employeeCode = clean(request.getParameter("employeeCode"));
            String employeeName = clean(request.getParameter("employeeName"));
            String email = clean(request.getParameter("email"));
            String phone = PhoneValidationUtil.validatePhone(request.getParameter("phone"));

            int departmentId = parseInt(request.getParameter("departmentId"), 0);

            String designation = clean(request.getParameter("designation"));
            String joiningDate = clean(request.getParameter("joiningDate"));

            if (employeeId <= 0
                    || employeeCode.isEmpty()
                    || employeeName.isEmpty()
                    || email.isEmpty()
                    || departmentId <= 0
                    || designation.isEmpty()
                    || joiningDate.isEmpty()) {
                response.sendRedirect("edit_employee.jsp?id=" + employeeId + "&error=failed");
                return;
            }

            if (phone == null) {
                response.sendRedirect("edit_employee.jsp?id=" + employeeId + "&error=invalidphone");
                return;
            }

            if (!isValidDepartment(departmentId)) {
                response.sendRedirect("edit_employee.jsp?id=" + employeeId + "&error=invaliddepartment");
                return;
            }

            if (!DateValidationUtil.isPastOrToday(joiningDate)) {
                response.sendRedirect("edit_employee.jsp?id=" + employeeId + "&error=invaliddate");
                return;
            }
            String status = clean(request.getParameter("status")).toUpperCase();

            try (Connection con = DBConnection.getConnection()) {

                EmployeeSnapshot oldEmployee = getEmployeeSnapshot(con, employeeId);

                if (oldEmployee == null) {
                    response.sendRedirect("employees.jsp?error=invalid");
                    return;
                }

                String newDepartmentName = getDepartmentName(con, departmentId);

                EmployeeSnapshot newEmployee = new EmployeeSnapshot();

                newEmployee.employeeId = employeeId;
                newEmployee.employeeCode = employeeCode;
                newEmployee.employeeName = employeeName;
                newEmployee.email = email;
                newEmployee.phone = phone;
                newEmployee.departmentId = departmentId;
                newEmployee.departmentName = newDepartmentName;
                newEmployee.designation = designation;
                newEmployee.joiningDate = joiningDate;
                newEmployee.status = status;

                ChangeSummary changeSummary = buildEmployeeChangeSummary(oldEmployee, newEmployee);
                boolean hasActualChange = changeSummary != null && changeSummary.changeCount > 0;

                EmployeeDAO dao = new EmployeeDAO();

                boolean updated = dao.updateEmployee(
                        employeeId,
                        employeeCode,
                        employeeName,
                        email,
                        phone,
                        departmentId,
                        designation,
                        joiningDate,
                        status
                );

                if (updated) {
                    String auditMessage;
                    if (hasActualChange) {
                        auditMessage = "Employee record updated by " + username
                                + " (" + formatRoleName(role) + ")"
                                + ". Employee: " + employeeCode + " - " + employeeName
                                + ". Updated information: " + changeSummary.auditText.toString().replace("\n", " | ");
                    } else {
                        auditMessage = "Employee update submitted by " + username
                                + " (" + formatRoleName(role) + ")"
                                + ". Employee: " + employeeCode + " - " + employeeName
                                + ". No effective employee record change detected.";
                    }

                    AuditDAO.log(
                            userId,
                            hasActualChange ? "UPDATE" : "NO_CHANGE",
                            "employees",
                            employeeId,
                            auditMessage
                    );

                    if (hasActualChange) {
                        sendEmployeeRecordNotice(
                                oldEmployee,
                                newEmployee,
                                changeSummary,
                                username,
                                role,
                                NotificationHelper.getUserEmailByUsername(username)
                        );
                    }

                    response.sendRedirect("employees.jsp?msg=updated");

                } else {
                    response.sendRedirect("edit_employee.jsp?id=" + employeeId + "&error=failed");
                }
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

    private boolean isValidDepartment(int departmentId) {
        String sql = "SELECT COUNT(*) FROM departments WHERE department_id = ? AND status = 'ACTIVE'";

        try (Connection con = DBConnection.getConnection();
             PreparedStatement ps = con.prepareStatement(sql)) {

            ps.setInt(1, departmentId);

            try (ResultSet rs = ps.executeQuery()) {
                return rs.next() && rs.getInt(1) > 0;
            }
        } catch (Exception e) {
            e.printStackTrace();
        }

        return false;
    }

    private void sendEmployeeRecordNotice(
            EmployeeSnapshot oldEmployee,
            EmployeeSnapshot newEmployee,
            ChangeSummary changeSummary,
            String updatedBy,
            String updaterRole,
            String updaterEmail
    ) {
        try {
            String action = "UPDATED";
            if (!oldEmployee.status.equals(newEmployee.status)) {
                action = "STATUS_CHANGED";
            }
            NotificationEventService.EmailRouting routing = NotificationEventService.buildEmployeeRecipients(action, newEmployee.employeeId);
            String toEmail = routing.getToEmail();
            String ccEmail = routing.getCcEmail();

            String subject = getEmployeeRecordSubject(oldEmployee, newEmployee);

            // Fault: same class of finding already fixed in DisposeAssetServlet -
            // free-text fields landing in an HTML email body unescaped.
            // changeSummary.htmlText is already safe (built via appendChange(),
            // which now escapes each value itself).
            String detailsTable = "<tr><th>Status:</th><td>Update Completed</td></tr>"
                    + "<tr><th>Priority:</th><td>" + getNoticePriority(oldEmployee, newEmployee) + "</td></tr>"
                    + "<tr><th>Module:</th><td>Employee Administration</td></tr>"
                    + "<tr><th>Reference ID:</th><td>" + HtmlEscapeUtil.escape(safe(newEmployee.employeeCode, "N/A")) + " / Employee ID " + newEmployee.employeeId + "</td></tr>"
                    + "<tr><td colspan='2' style='background-color: #f1f5f9; text-align: center;'><b>UPDATE SUMMARY</b></td></tr>"
                    + "<tr><td colspan='2'>" + changeSummary.htmlText + "</td></tr>"
                    + "<tr><td colspan='2' style='background-color: #f1f5f9; text-align: center;'><b>EMPLOYEE RECORD</b></td></tr>"
                    + "<tr><th>Employee Code:</th><td>" + HtmlEscapeUtil.escape(safe(newEmployee.employeeCode, "N/A")) + "</td></tr>"
                    + "<tr><th>Name:</th><td>" + HtmlEscapeUtil.escape(safe(newEmployee.employeeName, "")) + "</td></tr>"
                    + "<tr><th>Department:</th><td>" + HtmlEscapeUtil.escape(safe(newEmployee.departmentName, "N/A")) + "</td></tr>"
                    + "<tr><th>Designation:</th><td>" + HtmlEscapeUtil.escape(safe(newEmployee.designation, "N/A")) + "</td></tr>"
                    + "<tr><th>Record Status:</th><td>" + formatNormalText(newEmployee.status) + "</td></tr>"
                    + "<tr><td colspan='2' style='background-color: #f1f5f9; text-align: center;'><b>UPDATED BY</b></td></tr>"
                    + "<tr><th>User:</th><td>" + HtmlEscapeUtil.escape(safe(updatedBy, "N/A")) + "</td></tr>"
                    + "<tr><th>Role:</th><td>" + formatRoleName(updaterRole) + "</td></tr>"
                    + "<tr><th>Account:</th><td>" + HtmlEscapeUtil.escape(safe(updaterEmail, "N/A")) + "</td></tr>";
            
            String actionNote = getActionRequiredText(oldEmployee, newEmployee);

            String body = NotificationHelper.buildHtmlEmail("", "EMPLOYEE RECORD UPDATE", detailsTable, actionNote);

            NotificationHelper.sendNotification(
                    getServletContext(),
                    "EMPLOYEE_ADMIN_ALERT",
                    "EMPLOYEE_MANAGEMENT",
                    newEmployee.employeeId,
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

    private String buildCcRouting(
            String updaterRole,
            String departmentHeadEmail,
            String superAdminEmail,
            String toEmail
    ) {
        if ("SUPER_ADMIN".equals(updaterRole) || "ADMIN".equals(updaterRole)) {
            return combineUniqueEmails(
                    departmentHeadEmail,
                    superAdminEmail,
                    toEmail
            );
        }

        if ("DEPARTMENT_HEAD".equalsIgnoreCase(updaterRole)) {
            return combineUniqueEmails(
                    superAdminEmail,
                    "",
                    toEmail
            );
        }

        return combineUniqueEmails(
                superAdminEmail,
                "",
                toEmail
        );
    }

    private String getEmployeeRecordSubject(EmployeeSnapshot oldEmployee, EmployeeSnapshot newEmployee) {

        if (!same(oldEmployee.status, newEmployee.status)
                && "INACTIVE".equalsIgnoreCase(newEmployee.status)) {
            return "IR-AMS | Employee Record Deactivated | " + safe(newEmployee.employeeCode, "N/A");
        }

        if (!same(oldEmployee.status, newEmployee.status)
                && "ACTIVE".equalsIgnoreCase(newEmployee.status)) {
            return "IR-AMS | Employee Record Reactivated | " + safe(newEmployee.employeeCode, "N/A");
        }

        if (oldEmployee.departmentId != newEmployee.departmentId) {
            return "IR-AMS | Department Assignment Updated | " + safe(newEmployee.employeeCode, "N/A");
        }

        if (!same(oldEmployee.designation, newEmployee.designation)) {
            return "IR-AMS | Designation Updated | " + safe(newEmployee.employeeCode, "N/A");
        }

        return "IR-AMS | Employee Record Updated | " + safe(newEmployee.employeeCode, "N/A");
    }

    private String getNoticePriority(EmployeeSnapshot oldEmployee, EmployeeSnapshot newEmployee) {

        if (!same(oldEmployee.status, newEmployee.status)) {
            return "High";
        }

        if (oldEmployee.departmentId != newEmployee.departmentId) {
            return "High";
        }

        if (!same(oldEmployee.designation, newEmployee.designation)) {
            return "Medium";
        }

        return "Normal";
    }

    private String getActionRequiredText(EmployeeSnapshot oldEmployee, EmployeeSnapshot newEmployee) {

        if (!same(oldEmployee.status, newEmployee.status)
                && "INACTIVE".equalsIgnoreCase(newEmployee.status)) {
            return "Review linked user access and asset allocation records, if applicable.";
        }

        if (!same(oldEmployee.status, newEmployee.status)
                && "ACTIVE".equalsIgnoreCase(newEmployee.status)) {
            return "Confirm that the employee record is active as per the current duty assignment.";
        }

        if (oldEmployee.departmentId != newEmployee.departmentId) {
            return "Confirm that department-linked visibility, reporting, and asset allocation records remain accurate.";
        }

        if (!same(oldEmployee.designation, newEmployee.designation)) {
            return "Confirm that the updated designation matches the employee’s current operational responsibility.";
        }

        return "Review the updated field. If the change is incorrect, report it to the Department Head or System Administrator.";
    }

    private ChangeSummary buildEmployeeChangeSummary(EmployeeSnapshot oldEmployee, EmployeeSnapshot newEmployee) {

        ChangeSummary summary = new ChangeSummary();

        appendChange(summary, "Employee Code", oldEmployee.employeeCode, newEmployee.employeeCode);
        appendChange(summary, "Name", oldEmployee.employeeName, newEmployee.employeeName);
        appendChange(summary, "Email", oldEmployee.email, newEmployee.email);
        appendChange(summary, "Phone", oldEmployee.phone, newEmployee.phone);

        if (oldEmployee.departmentId != newEmployee.departmentId) {
            appendChange(summary, "Department", oldEmployee.departmentName, newEmployee.departmentName);
        }

        appendChange(summary, "Designation", oldEmployee.designation, newEmployee.designation);
        appendChange(summary, "Joining Date", oldEmployee.joiningDate, newEmployee.joiningDate);

        if (!same(oldEmployee.status, newEmployee.status)) {
            appendChange(summary, "Record Status", formatNormalText(oldEmployee.status), formatNormalText(newEmployee.status));
        }

        finalizeChangeSummary(summary);

        return summary;
    }

    private void appendChange(ChangeSummary summary, String fieldName, String oldValue, String newValue) {

        if (same(oldValue, newValue)) {
            return;
        }

        summary.changeCount++;

        if (summary.changeCount == 1) {
            summary.firstFieldName = fieldName;
            summary.firstOldValue = safe(oldValue, "N/A");
            summary.firstNewValue = safe(newValue, "N/A");
        }

        summary.auditText.append(fieldName)
                .append(": ")
                .append(safe(oldValue, "N/A"))
                .append(" → ")
                .append(safe(newValue, "N/A"))
                .append("\n");

        // Fault: fieldName is always one of this method's own fixed literal
        // labels ("Employee Code", "Name", ...), but oldValue/newValue are
        // form-submitted (or DB-sourced) free text landing straight in an HTML
        // email body with no escaping - same class of finding already fixed in
        // DisposeAssetServlet. HtmlEscapeUtil.escape() is a no-op on
        // already-plain text.
        summary.htmlTextBuilder.append("<b>").append(fieldName).append("</b>: ")
                .append(HtmlEscapeUtil.escape(safe(oldValue, "N/A")))
                .append(" &rarr; ")
                .append(HtmlEscapeUtil.escape(safe(newValue, "N/A")))
                .append("<br>");
    }

    private void finalizeChangeSummary(ChangeSummary summary) {

        if (summary.changeCount == 0) {
            summary.htmlText = "";
            return;
        }

        summary.htmlText = "<b>Fields Updated: " + summary.changeCount + "</b><br>" + summary.htmlTextBuilder.toString();
    }

    private EmployeeSnapshot getEmployeeSnapshot(Connection con, int employeeId) {
        String sql = "SELECT e.employee_id, e.employee_code, e.employee_name, "
                + "e.email, e.phone, e.department_id, d.department_name, "
                + "e.designation, e.joining_date, e.employee_status AS status "
                + "FROM employees e "
                + "LEFT JOIN departments d ON e.department_id = d.department_id "
                + "WHERE e.employee_id = ?";

        try (PreparedStatement ps = con.prepareStatement(sql)) {
            ps.setInt(1, employeeId);
            try (ResultSet rs = ps.executeQuery()) {
                if (rs.next()) {
                    EmployeeSnapshot employee = new EmployeeSnapshot();

                    employee.employeeId = rs.getInt("employee_id");
                    employee.employeeCode = rs.getString("employee_code");
                    employee.employeeName = rs.getString("employee_name");
                    
                    employee.email = rs.getString("email");
                    employee.phone = rs.getString("phone");
                    employee.departmentId = rs.getInt("department_id");
                    employee.departmentName = rs.getString("department_name");
                    employee.designation = rs.getString("designation");
                    employee.joiningDate = rs.getString("joining_date");
                    employee.status = rs.getString("status");

                    return employee;
                }
            }
        } catch (Exception e) {
            e.printStackTrace();
        }

        return null;
    }

    private String getDepartmentName(Connection con, int departmentId) {
        String sql = "SELECT department_name FROM departments WHERE department_id = ?";
        try (PreparedStatement ps = con.prepareStatement(sql)) {
            ps.setInt(1, departmentId);
            try (ResultSet rs = ps.executeQuery()) {
                if (rs.next()) {
                    return rs.getString("department_name");
                }
            }
        } catch (Exception e) {
            e.printStackTrace();
        }

        return "N/A";
    }

    private String getDepartmentHeadEmailByDepartmentId(int departmentId) {
        String sql = "SELECT u.email "
                + "FROM departments d "
                + "JOIN users u ON d.department_head_user_id = u.user_id "
                + "JOIN roles r ON u.role_id = r.role_id "
                + "WHERE d.department_id = ? "
                + "AND r.role_name = 'DEPARTMENT_HEAD' "
                + "AND u.status = 'ACTIVE' "
                + "LIMIT 1";

        try (Connection con = DBConnection.getConnection();
             PreparedStatement ps = con.prepareStatement(sql)) {
            ps.setInt(1, departmentId);

            try (ResultSet rs = ps.executeQuery()) {
                if (rs.next()) {
                    String email = rs.getString("email");

                    if (email != null && !email.trim().isEmpty()) {
                        return email.trim();
                    }
                }
            }
        } catch (Exception e) {
            e.printStackTrace();
        }

        return NotificationRecipientResolver.getPrimaryEmailByRole("DEPARTMENT_HEAD");
    }

    private String combineUniqueEmails(String firstEmail, String secondEmail, String excludeEmail) {

        StringBuilder emails = new StringBuilder();

        appendEmail(emails, firstEmail, excludeEmail);
        appendEmail(emails, secondEmail, excludeEmail);

        return emails.toString();
    }

    private void appendEmail(StringBuilder emails, String email, String excludeEmail) {

        if (email == null || email.trim().isEmpty()) {
            return;
        }

        String cleanEmail = email.trim();

        if (excludeEmail != null && cleanEmail.equalsIgnoreCase(excludeEmail.trim())) {
            return;
        }

        String existing = emails.toString().toLowerCase();

        if (existing.contains(cleanEmail.toLowerCase())) {
            return;
        }

        if (emails.length() > 0) {
            emails.append(",");
        }

        emails.append(cleanEmail);
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

    private int parseInt(String value, int fallback) {
        try {
            return Integer.parseInt(clean(value));
        } catch (Exception e) {
            return fallback;
        }
    }

    private String clean(String value) {
        if (value == null) {
            return "";
        }

        return value.trim();
    }

    private String safe(String value, String fallback) {
        if (value == null || value.trim().isEmpty()) {
            return fallback;
        }

        return value.trim();
    }

    private boolean same(String first, String second) {
        return safe(first, "").equalsIgnoreCase(safe(second, ""));
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

    private String padRight(String value, int length) {
        String text = safe(value, "");

        if (text.length() >= length) {
            return text;
        }

        StringBuilder padded = new StringBuilder(text);

        while (padded.length() < length) {
            padded.append(" ");
        }

        return padded.toString();
    }

    private static class EmployeeSnapshot {

        int employeeId;
        String employeeCode;
        String employeeName;
        
        String email;
        String phone;
        int departmentId;
        String departmentName;
        String designation;
        String joiningDate;
        String status;
    }

    private static class ChangeSummary {

        int changeCount = 0;
        String firstFieldName = "";
        String firstOldValue = "";
        String firstNewValue = "";
        String htmlText = "";
        StringBuilder auditText = new StringBuilder();
        StringBuilder htmlTextBuilder = new StringBuilder();
    }
}
