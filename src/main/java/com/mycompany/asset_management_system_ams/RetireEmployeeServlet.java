package com.mycompany.asset_management_system_ams;

import java.io.IOException;
import java.util.ArrayList;
import java.util.List;

import jakarta.servlet.ServletException;
import jakarta.servlet.annotation.WebServlet;
import jakarta.servlet.http.HttpServlet;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import jakarta.servlet.http.HttpSession;

/**
 * RetireEmployeeServlet - marks an employee RETIRED. Unlike a transfer, no
 * asset may be retained: a retiring employee is leaving, so every currently
 * ALLOCATED asset must be returned as part of this same action. If any asset
 * is missing its return details the whole retirement is rejected - there is
 * no partial-retirement state where the employee is RETIRED but still shows
 * custody of railway property.
 */
@WebServlet(name = "RetireEmployeeServlet", urlPatterns = {"/RetireEmployeeServlet"})
public class RetireEmployeeServlet extends HttpServlet {

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
                response.sendRedirect("view_employee.jsp?id=" + employeeId + "&error=notretirable");
                return;
            }

            String remarks = clean(request.getParameter("remarks"));
            if (remarks.isEmpty()) {
                remarks = "Employee retirement processed via IR-AMS";
            }

            String receivedBy = clean(request.getParameter("receivedBy"));

            AssetAllocationDAO allocationDao = new AssetAllocationDAO();
            List<AssetAllocation> allocations = allocationDao.getAllocationsByEmployeeId(employeeId);

            List<AssetAllocation> activeAllocations = new ArrayList<>();
            for (AssetAllocation allocation : allocations) {
                if ("ALLOCATED".equalsIgnoreCase(allocation.getAllocationStatus())) {
                    activeAllocations.add(allocation);
                }
            }

            if (!activeAllocations.isEmpty() && receivedBy.isEmpty()) {
                response.sendRedirect("retire_employee.jsp?id=" + employeeId + "&error=receivedbyrequired");
                return;
            }

            // Every currently-allocated asset must have a condition submitted -
            // no silent skipping. If the form is missing one (tampered request,
            // JS disabled, stale page), reject the whole retirement rather than
            // retire the employee while an asset is still shown as allocated to
            // them.
            for (AssetAllocation allocation : activeAllocations) {
                String condition = clean(request.getParameter("condition_" + allocation.getAllocationId()));
                if (condition.isEmpty()) {
                    response.sendRedirect("retire_employee.jsp?id=" + employeeId + "&error=allassetsrequired");
                    return;
                }
            }

            AssetReturnDAO returnDao = new AssetReturnDAO();
            String today = new java.sql.Date(System.currentTimeMillis()).toString();

            List<Integer> returnedAssetIds = new ArrayList<>();

            for (AssetAllocation allocation : activeAllocations) {

                String condition = clean(request.getParameter("condition_" + allocation.getAllocationId()));

                int returnId = returnDao.addReturnAndReturnId(
                        allocation.getAllocationId(),
                        today,
                        condition,
                        receivedBy,
                        "Returned as part of employee retirement. " + remarks
                );

                if (returnId <= 0) {
                    // Same reasoning as TransferEmployeeServlet: abort rather than
                    // retire the employee with an asset return that didn't
                    // actually go through. Safe to retry.
                    response.sendRedirect("retire_employee.jsp?id=" + employeeId + "&error=returnfailed");
                    return;
                }

                returnedAssetIds.add(allocation.getAssetId());

                AuditDAO.log(
                        userId,
                        "ADD",
                        "asset_returns",
                        returnId,
                        "Asset returned as part of employee retirement. Allocation ID: "
                        + allocation.getAllocationId()
                        + ", Employee: " + employee.getEmployeeCode()
                        + ", Processed by: " + username + " (" + formatRoleName(role) + ")."
                );
            }

            boolean retired = employeeDao.retireEmployee(employeeId);

            if (!retired) {
                response.sendRedirect("retire_employee.jsp?id=" + employeeId + "&error=failed");
                return;
            }

            for (Integer assetId : returnedAssetIds) {
                QrSnapshotService.syncAssetQuietly(assetId);
            }

            AuditDAO.log(
                    userId,
                    "RETIRE",
                    "employees",
                    employeeId,
                    "Employee retired by " + username + " (" + formatRoleName(role) + ")."
                    + " Employee: " + employee.getEmployeeCode() + " - " + employee.getEmployeeName()
                    + ". Assets returned: " + returnedAssetIds.size()
                    + ". Remarks: " + remarks
            );

            sendRetirementNotice(employee, returnedAssetIds.size(), remarks, username, role);

            response.sendRedirect("view_employee.jsp?id=" + employeeId + "&msg=retired");

        } catch (Exception e) {
            e.printStackTrace();
            if (employeeId > 0) {
                response.sendRedirect("retire_employee.jsp?id=" + employeeId + "&error=server");
            } else {
                response.sendRedirect("employees.jsp?error=server");
            }
        }
    }

    private void sendRetirementNotice(
            Employee employee,
            int returnedCount,
            String remarks,
            String retiredBy,
            String retirerRole
    ) {
        try {
            NotificationEventService.EmailRouting routing =
                    NotificationEventService.buildEmployeeRecipients("RETIRED", employee.getEmployeeId());

            String toEmail = routing.getToEmail();
            String ccEmail = routing.getCcEmail();

            String subject = "IR-AMS | Employee Retired | " + safe(employee.getEmployeeCode(), "N/A");

            // Fault: same class of finding already fixed in DisposeAssetServlet -
            // free-text fields landing in an HTML email body unescaped. `remarks`
            // is the highest-risk field here - a free-text box typed directly by
            // whoever processes the retirement.
            String detailsTable = "<tr><th>Employee:</th><td>" + HtmlEscapeUtil.escape(safe(employee.getEmployeeName(), "N/A"))
                    + " (" + HtmlEscapeUtil.escape(safe(employee.getEmployeeCode(), "N/A")) + ")</td></tr>"
                    + "<tr><th>Department:</th><td>" + HtmlEscapeUtil.escape(safe(employee.getDepartmentName(), "N/A")) + "</td></tr>"
                    + "<tr><th>Assets Returned:</th><td>" + returnedCount + "</td></tr>"
                    + "<tr><th>Remarks:</th><td>" + HtmlEscapeUtil.escape(safe(remarks, "N/A")) + "</td></tr>"
                    + "<tr><th>Retired By:</th><td>" + HtmlEscapeUtil.escape(safe(retiredBy, "N/A"))
                    + " (" + formatRoleName(retirerRole) + ")</td></tr>";

            String actionNote = "Review linked user login access for this employee - retirement does not "
                    + "automatically disable their IR-AMS account.";

            String body = NotificationHelper.buildHtmlEmail(
                    HtmlEscapeUtil.escape(safe(employee.getEmployeeName(), "")), "EMPLOYEE RETIRED", detailsTable, actionNote);

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
