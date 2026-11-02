package com.mycompany.asset_management_system_ams;

import java.io.IOException;
import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.util.List;

import jakarta.servlet.ServletException;
import jakarta.servlet.annotation.WebServlet;
import jakarta.servlet.http.HttpServlet;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import jakarta.servlet.http.HttpSession;

/**
 * TransferEmployeeServlet - moves an employee to a new department and, for
 * each asset currently allocated to them, either leaves it allocated
 * (Retain - it travels with the employee) or closes it out through the
 * normal return flow (Return - it goes back to inventory). The employee's
 * employee_status/status are NOT changed by a transfer; they remain ACTIVE
 * and stay eligible for new allocations in their new department. The
 * transfer itself is recorded as an AuditDAO entry, not as a persistent
 * status value - see EmployeeDAO.updateEmployeeDepartment().
 */
@WebServlet(name = "TransferEmployeeServlet", urlPatterns = {"/TransferEmployeeServlet"})
public class TransferEmployeeServlet extends HttpServlet {

    @Override
    protected void doPost(HttpServletRequest request, HttpServletResponse response)
            throws ServletException, IOException {

        int employeeId = 0;

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

            employeeId = parseInt(request.getParameter("employeeId"), 0);

            if (employeeId <= 0) {
                response.sendRedirect("employees.jsp?error=invalid");
                return;
            }

            EmployeeDAO employeeDao = new EmployeeDAO();

            if ("DEPARTMENT_HEAD".equalsIgnoreCase(role)) {
                if (!employeeDao.isEmployeeUnderDepartmentHead(employeeId, userId)) {
                    response.sendRedirect("employees.jsp?access=denied");
                    return;
                }
            }

            Employee employee = employeeDao.getEmployeeById(employeeId);

            if (employee == null) {
                response.sendRedirect("employees.jsp?error=invalid");
                return;
            }

            if (!"ACTIVE".equalsIgnoreCase(employee.getStatus())) {
                response.sendRedirect("view_employee.jsp?id=" + employeeId + "&error=nottransferable");
                return;
            }

            int oldDepartmentId = employee.getDepartmentId();
            int newDepartmentId = parseInt(request.getParameter("newDepartmentId"), 0);

            if (newDepartmentId <= 0 || !isValidDepartment(newDepartmentId)) {
                response.sendRedirect("transfer_employee.jsp?id=" + employeeId + "&error=invaliddepartment");
                return;
            }

            if (newDepartmentId == oldDepartmentId) {
                response.sendRedirect("transfer_employee.jsp?id=" + employeeId + "&error=samedepartment");
                return;
            }

            String remarks = clean(request.getParameter("remarks"));
            if (remarks.isEmpty()) {
                remarks = "Employee transfer processed via IR-AMS";
            }

            String receivedBy = clean(request.getParameter("receivedBy"));

            AssetAllocationDAO allocationDao = new AssetAllocationDAO();
            List<AssetAllocation> allocations = allocationDao.getAllocationsByEmployeeId(employeeId);

            AssetReturnDAO returnDao = new AssetReturnDAO();

            int retainedCount = 0;
            int returnedCount = 0;
            java.util.List<Integer> returnedAssetIds = new java.util.ArrayList<>();

            // First pass: figure out how many returns were actually requested, so
            // we can validate receivedBy up front rather than partway through.
            int requestedReturnCount = 0;
            for (AssetAllocation allocation : allocations) {
                if (!"ALLOCATED".equalsIgnoreCase(allocation.getAllocationStatus())) {
                    continue;
                }
                String action = clean(request.getParameter("action_" + allocation.getAllocationId()));
                if ("return".equalsIgnoreCase(action)) {
                    requestedReturnCount++;
                }
            }

            if (requestedReturnCount > 0 && receivedBy.isEmpty()) {
                response.sendRedirect("transfer_employee.jsp?id=" + employeeId + "&error=receivedbyrequired");
                return;
            }

            String today = new java.sql.Date(System.currentTimeMillis()).toString();

            for (AssetAllocation allocation : allocations) {

                if (!"ALLOCATED".equalsIgnoreCase(allocation.getAllocationStatus())) {
                    continue;
                }

                String action = clean(request.getParameter("action_" + allocation.getAllocationId()));

                if (!"return".equalsIgnoreCase(action)) {
                    // Default is Retain - never force-return an asset the form
                    // didn't explicitly mark, so a missing/tampered field fails
                    // safe (asset stays with the employee) instead of fails open
                    // (asset gets silently returned).
                    retainedCount++;
                    // The allocation stays ALLOCATED, so clear any pending
                    // employee preference now that it's been reviewed/actioned -
                    // otherwise the same "employee requested" badge would keep
                    // showing up on every future transfer screen for this asset.
                    allocationDao.clearEmployeeTransferPreference(allocation.getAllocationId());
                    continue;
                }

                String condition = clean(request.getParameter("condition_" + allocation.getAllocationId()));
                if (condition.isEmpty()) {
                    condition = "GOOD";
                }

                int returnId = returnDao.addReturnAndReturnId(
                        allocation.getAllocationId(),
                        today,
                        condition,
                        receivedBy,
                        "Returned as part of employee transfer. " + remarks
                );

                if (returnId <= 0) {
                    // A requested return failed (already returned elsewhere, race
                    // condition, etc.) - abort the whole transfer rather than move
                    // the employee's department while leaving the admin thinking
                    // an asset was returned when it wasn't. Already-processed
                    // returns/retentions above are unaffected and this is safe to
                    // retry.
                    response.sendRedirect("transfer_employee.jsp?id=" + employeeId + "&error=returnfailed");
                    return;
                }

                returnedCount++;
                returnedAssetIds.add(allocation.getAssetId());

                AuditDAO.log(
                        userId,
                        "ADD",
                        "asset_returns",
                        returnId,
                        "Asset returned as part of employee transfer. Allocation ID: "
                        + allocation.getAllocationId()
                        + ", Employee: " + employee.getEmployeeCode()
                        + ", Processed by: " + username + " (" + formatRoleName(role) + ")."
                );
            }

            // Resolve the OLD department head's email before the department_id
            // changes underneath it - NotificationEventService.buildEmployeeRecipients
            // looks up the department head for whatever department the employee
            // is in AT THE TIME OF THE CALL.
            String oldDeptHeadEmail = employeeDao.getDepartmentHeadEmailByEmployeeId(employeeId);
            String oldDepartmentName = employee.getDepartmentName();

            boolean moved = employeeDao.updateEmployeeDepartment(employeeId, newDepartmentId);

            if (!moved) {
                response.sendRedirect("transfer_employee.jsp?id=" + employeeId + "&error=failed");
                return;
            }

            String newDepartmentName = getDepartmentName(newDepartmentId);

            for (Integer assetId : returnedAssetIds) {
                QrSnapshotService.syncAssetQuietly(assetId);
            }

            AuditDAO.log(
                    userId,
                    "TRANSFER",
                    "employees",
                    employeeId,
                    "Employee transferred by " + username + " (" + formatRoleName(role) + ")."
                    + " Employee: " + employee.getEmployeeCode() + " - " + employee.getEmployeeName()
                    + ". Department: " + safe(oldDepartmentName, "N/A") + " -> " + safe(newDepartmentName, "N/A")
                    + ". Assets retained: " + retainedCount + ", returned: " + returnedCount
                    + ". Remarks: " + remarks
            );

            sendTransferNotice(employee, oldDepartmentName, newDepartmentName, newDepartmentId,
                    oldDeptHeadEmail, retainedCount, returnedCount, remarks, username, role);

            response.sendRedirect("view_employee.jsp?id=" + employeeId + "&msg=transferred");

        } catch (Exception e) {
            e.printStackTrace();
            if (employeeId > 0) {
                response.sendRedirect("transfer_employee.jsp?id=" + employeeId + "&error=server");
            } else {
                response.sendRedirect("employees.jsp?error=server");
            }
        }
    }

    private void sendTransferNotice(
            Employee employee,
            String oldDepartmentName,
            String newDepartmentName,
            int newDepartmentId,
            String oldDeptHeadEmail,
            int retainedCount,
            int returnedCount,
            String remarks,
            String transferredBy,
            String transferrerRole
    ) {
        try {
            NotificationEventService.EmailRouting routing =
                    NotificationEventService.buildEmployeeRecipients("TRANSFERRED", employee.getEmployeeId());

            String toEmail = routing.getToEmail();
            String newDeptHeadEmail = getDepartmentHeadEmailByDepartmentId(newDepartmentId);
            String ccEmail = NotificationHelper.combineEmails(routing.getCcEmail(), newDeptHeadEmail);

            String subject = "IR-AMS | Employee Transferred | " + safe(employee.getEmployeeCode(), "N/A");

            // Fault: same class of finding already fixed in DisposeAssetServlet -
            // free-text fields landing in an HTML email body unescaped. `remarks`
            // is the highest-risk field here - a free-text box typed directly by
            // whoever processes the transfer.
            String detailsTable = "<tr><th>Employee:</th><td>" + HtmlEscapeUtil.escape(safe(employee.getEmployeeName(), "N/A"))
                    + " (" + HtmlEscapeUtil.escape(safe(employee.getEmployeeCode(), "N/A")) + ")</td></tr>"
                    + "<tr><th>From Department:</th><td>" + HtmlEscapeUtil.escape(safe(oldDepartmentName, "N/A")) + "</td></tr>"
                    + "<tr><th>To Department:</th><td>" + HtmlEscapeUtil.escape(safe(newDepartmentName, "N/A")) + "</td></tr>"
                    + "<tr><th>Assets Retained:</th><td>" + retainedCount + "</td></tr>"
                    + "<tr><th>Assets Returned:</th><td>" + returnedCount + "</td></tr>"
                    + "<tr><th>Remarks:</th><td>" + HtmlEscapeUtil.escape(safe(remarks, "N/A")) + "</td></tr>"
                    + "<tr><th>Transferred By:</th><td>" + HtmlEscapeUtil.escape(safe(transferredBy, "N/A"))
                    + " (" + formatRoleName(transferrerRole) + ")</td></tr>";

            String actionNote = "Confirm department-linked visibility, reporting, and retained asset custody "
                    + "records remain accurate for this employee in their new department.";

            String body = NotificationHelper.buildHtmlEmail(
                    HtmlEscapeUtil.escape(safe(employee.getEmployeeName(), "")), "EMPLOYEE TRANSFERRED", detailsTable, actionNote);

            NotificationHelper.sendNotification(
                    getServletContext(),
                    "EMPLOYEE_ADMIN_ALERT",
                    "EMPLOYEE_MANAGEMENT",
                    employee.getEmployeeId(),
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

    private String getDepartmentName(int departmentId) {
        String sql = "SELECT department_name FROM departments WHERE department_id = ?";

        try (Connection con = DBConnection.getConnection();
             PreparedStatement ps = con.prepareStatement(sql)) {

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

    private int getSessionInt(HttpSession session, String key, int fallback) {
        try {
            Object value = session.getAttribute(key);
            return value == null ? fallback : Integer.parseInt(String.valueOf(value));
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
        return value == null ? "" : value.trim();
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
