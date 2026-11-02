package com.mycompany.asset_management_system_ams;

import java.io.IOException;
import java.util.List;

import jakarta.servlet.ServletException;
import jakarta.servlet.annotation.WebServlet;
import jakarta.servlet.http.HttpServlet;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import jakarta.servlet.http.HttpSession;

/**
 * SubmitEmployeeTransferPreferenceServlet - lets an EMPLOYEE state, per
 * currently-allocated asset, whether they'd like to keep it or return it if
 * they get transferred. This is only ever a request/preference: it never
 * changes allocation_status or asset_status, and never touches the
 * employee's department. An Admin/Super Admin/Department Head still has to
 * review it (it shows up pre-filled, but overridable, on
 * transfer_employee.jsp) and actually run TransferEmployeeServlet to make
 * anything happen.
 *
 * employeeId is read only from the session ("employee_id"), never from a
 * request parameter, so this can't be used to submit a preference on behalf
 * of a different employee. AssetAllocationDAO.submitEmployeeTransferPreference()
 * also re-checks employee_id ownership itself as defense in depth.
 */
@WebServlet(name = "SubmitEmployeeTransferPreferenceServlet", urlPatterns = {"/SubmitEmployeeTransferPreferenceServlet"})
public class SubmitEmployeeTransferPreferenceServlet extends HttpServlet {

    @Override
    protected void doPost(HttpServletRequest request, HttpServletResponse response)
            throws ServletException, IOException {

        try {
            request.setCharacterEncoding("UTF-8");

            HttpSession session = request.getSession(false);

            if (session == null
                    || session.getAttribute("username") == null
                    || session.getAttribute("role") == null
                    || session.getAttribute("employee_id") == null) {
                response.sendRedirect("login.jsp");
                return;
            }

            String username = String.valueOf(session.getAttribute("username"));
            String role = String.valueOf(session.getAttribute("role"));

            if (!"EMPLOYEE".equalsIgnoreCase(role)) {
                response.sendRedirect("employee_transfer_preference.jsp?error=denied");
                return;
            }

            int userId = getSessionInt(session, "user_id", 0);
            if (userId == 0) {
                userId = getSessionInt(session, "userId", 0);
            }

            int employeeId = getSessionInt(session, "employee_id", 0);

            if (employeeId <= 0) {
                response.sendRedirect("employee_transfer_preference.jsp?error=invalid");
                return;
            }

            String note = clean(request.getParameter("note"));

            AssetAllocationDAO allocationDao = new AssetAllocationDAO();
            List<AssetAllocation> allocations = allocationDao.getAllocationsByEmployeeId(employeeId);

            int submittedCount = 0;

            for (AssetAllocation allocation : allocations) {

                if (!"ALLOCATED".equalsIgnoreCase(allocation.getAllocationStatus())) {
                    continue;
                }

                String preference = clean(request.getParameter("preference_" + allocation.getAllocationId()));

                if (preference.isEmpty()) {
                    continue;
                }

                boolean saved = allocationDao.submitEmployeeTransferPreference(
                        allocation.getAllocationId(), employeeId, preference, note);

                if (saved) {
                    submittedCount++;
                }
            }

            if (submittedCount == 0) {
                response.sendRedirect("employee_transfer_preference.jsp?error=nopreference");
                return;
            }

            AuditDAO.log(
                    userId,
                    "TRANSFER_PREFERENCE_SUBMITTED",
                    "asset_allocation",
                    employeeId,
                    "Employee " + username + " submitted transfer/return asset preference(s) for "
                    + submittedCount + " allocation(s). Note: " + (note.isEmpty() ? "(none)" : note)
            );

            sendPreferenceNotice(employeeId, username, submittedCount, note);

            response.sendRedirect("employee_transfer_preference.jsp?msg=submitted");

        } catch (Exception e) {
            e.printStackTrace();
            response.sendRedirect("employee_transfer_preference.jsp?error=server");
        }
    }

    private void sendPreferenceNotice(int employeeId, String employeeUsername, int submittedCount, String note) {
        try {
            EmployeeDAO employeeDao = new EmployeeDAO();
            Employee employee = employeeDao.getEmployeeById(employeeId);

            if (employee == null) {
                return;
            }

            String deptHeadEmail = employeeDao.getDepartmentHeadEmailByEmployeeId(employeeId);
            String superAdminEmail = NotificationRecipientResolver.getPrimaryEmailByRole("SUPER_ADMIN");
            String toEmail = deptHeadEmail;
            String ccEmail = NotificationHelper.combineEmails(superAdminEmail, "");

            String subject = "IR-AMS | Employee Transfer Preference Submitted | " + safe(employee.getEmployeeCode(), "N/A");

            String detailsTable = "<tr><th>Employee:</th><td>" + safe(employee.getEmployeeName(), "N/A")
                    + " (" + safe(employee.getEmployeeCode(), "N/A") + ")</td></tr>"
                    + "<tr><th>Department:</th><td>" + safe(employee.getDepartmentName(), "N/A") + "</td></tr>"
                    + "<tr><th>Assets with Preference:</th><td>" + submittedCount + "</td></tr>"
                    // Fault (Medium, fixed): note is the employee's own free-text input,
                    // submitted through self-service - embedded unescaped. Same recurring
                    // class as audit/10-maintenance.md Finding 1.
                    + "<tr><th>Employee Note:</th><td>" + HtmlEscapeUtil.escape(safe(note, "N/A")) + "</td></tr>";

            String actionNote = "Review this employee's stated keep/return preference on the Transfer screen "
                    + "before finalizing their transfer. The preference is a suggestion only and can be overridden.";

            String body = NotificationHelper.buildHtmlEmail(
                    safe(employee.getEmployeeName(), ""), "TRANSFER PREFERENCE SUBMITTED", detailsTable, actionNote);

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
            return value == null ? fallback : Integer.parseInt(String.valueOf(value));
        } catch (Exception e) {
            return fallback;
        }
    }

    private String clean(String value) {
        return value == null ? "" : value.trim();
    }

    private String safe(String value, String fallback) {
        if (value == null || value.trim().isEmpty()) {
            return fallback;
        }
        return value.trim();
    }
}
