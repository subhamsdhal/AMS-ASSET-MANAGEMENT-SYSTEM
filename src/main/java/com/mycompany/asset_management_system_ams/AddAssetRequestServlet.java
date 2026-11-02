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

@WebServlet(name = "AddAssetRequestServlet", urlPatterns = {"/AddAssetRequestServlet"})
public class AddAssetRequestServlet extends HttpServlet {

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

            if (userId <= 0) {
                userId = getSessionInt(session, "userId", 0);
            }

            if (!("SUPER_ADMIN".equals(role) || "ADMIN".equals(role)) && !"ASSET_MANAGER".equals(role)
                    && !"DEPARTMENT_HEAD".equals(role)
                    && !"EMPLOYEE".equals(role)) {
                response.sendRedirect("asset_requests.jsp?access=denied");
                return;
            }

            int employeeId = parseInt(request.getParameter("employeeId"), 0);
            int categoryId = parseInt(request.getParameter("categoryId"), 0);

            if ("EMPLOYEE".equals(role)) {
                int linkedEmployeeId = getLinkedEmployeeId(userId);

                if (linkedEmployeeId <= 0) {
                    response.sendRedirect("employee_requests.jsp?new=1&error=access");
                    return;
                }

                employeeId = linkedEmployeeId;
            }

            String requestDate = safe(request.getParameter("requestDate"), "");
            String requestStatus = "PENDING";
            String approvedBy = "";
            String remarks = safe(request.getParameter("remarks"), "");

            if (employeeId <= 0 || categoryId <= 0) {
                if ("EMPLOYEE".equals(role)) {
                    response.sendRedirect("employee_requests.jsp?new=1&error=invalidselection");
                } else {
                    response.sendRedirect("add_request.jsp?error=invalidselection");
                }
                return;
            }

            if (requestDate.isEmpty() || !DateValidationUtil.isPastOrToday(requestDate)) {
                if ("EMPLOYEE".equals(role)) {
                    response.sendRedirect("employee_requests.jsp?new=1&error=invaliddate");
                } else {
                    response.sendRedirect("add_request.jsp?error=invaliddate");
                }
                return;
            }

            if (remarks.isEmpty()) {
                if ("EMPLOYEE".equals(role)) {
                    response.sendRedirect("employee_requests.jsp?new=1&error=failed");
                } else {
                    response.sendRedirect("add_request.jsp?error=failed");
                }
                return;
            }

            AssetRequestDAO dao = new AssetRequestDAO();

            // Only an employee's own self-service request is eligible to
            // start at the Department Head review stage. A request an ops
            // role (Admin/Asset Manager/Department Head/Super Admin) raises
            // on someone else's behalf skips straight to the Asset Manager
            // exactly as it always has - see addAssetRequestAndReturnId()'s
            // javadoc for the reasoning.
            boolean routeThroughDeptHead = "EMPLOYEE".equals(role);

            int requestId = dao.addAssetRequestAndReturnId(
                    employeeId,
                    categoryId,
                    requestDate,
                    requestStatus,
                    approvedBy,
                    remarks,
                    routeThroughDeptHead
            );

            if (requestId > 0) {

                AuditDAO.log(
                        userId,
                        "ADD",
                        "asset_requests",
                        requestId,
                        "New asset request created for employee ID: " + employeeId + " by " + username
                );

                String[] details = dao.getRequestNotificationDetails(requestId);

                String employeeEmail = "";
                String employeeName = "Employee";
                String employeeCode = "N/A";
                String categoryName = "Requested Asset Category";
                String departmentName = "N/A";
                // Reflects what was actually persisted (PENDING_DEPT_HEAD or
                // PENDING), not the pre-routing local variable above -
                // addAssetRequestAndReturnId() may have upgraded it.
                String persistedStatus = requestStatus;

                if (details != null) {
                    employeeEmail = getArrayValue(details, 0, "");
                    employeeName = getArrayValue(details, 1, "Employee");
                    employeeCode = getArrayValue(details, 2, "N/A");
                    categoryName = getArrayValue(details, 3, "Requested Asset Category");
                    departmentName = getArrayValue(details, 9, "N/A");
                    persistedStatus = getArrayValue(details, 5, requestStatus);
                }

                String notifyAction = "PENDING_DEPT_HEAD".equals(persistedStatus) ? "NEW_DEPT_HEAD" : "NEW";
                NotificationEventService.EmailRouting routing = NotificationEventService.buildAssetRequestRecipients(notifyAction, employeeId);
                String toEmail = routing.getToEmail();
                String ccEmail = routing.getCcEmail();

                String statusMessage = getNextStepMessage(persistedStatus);
                String roleMessage = getRoleBasedActionMessage(role, username);

                String subject = "Asset Request Submitted - Request #" + requestId;

                String detailsTable = "<tr><th>Request ID:</th><td>" + requestId + "</td></tr>"
                        + "<tr><th>Employee:</th><td>" + employeeName + " (" + employeeCode + ")</td></tr>"
                        + "<tr><th>Department:</th><td>" + departmentName + "</td></tr>"
                        + "<tr><th>Requested Category:</th><td>" + categoryName + "</td></tr>"
                        + "<tr><th>Request Date:</th><td>" + safe(requestDate, "N/A") + "</td></tr>"
                        + "<tr><th>Current Status:</th><td>" + persistedStatus + "</td></tr>"
                        // Fault (Medium, fixed): remarks is free text embedded unescaped -
                        // same recurring class as audit/10-maintenance.md Finding 1.
                        + "<tr><th>Remarks:</th><td>" + HtmlEscapeUtil.escape(safe(remarks, "N/A")) + "</td></tr>";
                
                String actionNote = roleMessage + "<br><br>" + statusMessage + "<br><br>Please log in to IR-AMS for further review or action.";

                String body = NotificationHelper.buildHtmlEmail("Asset Manager", "Asset Request Submitted", detailsTable, actionNote);

                NotificationHelper.sendAssetRequestAlert(
                        getServletContext(),
                        requestId,
                        toEmail,
                        ccEmail,
                        "",
                        subject,
                        body
                );

                if ("EMPLOYEE".equals(role)) {
                    response.sendRedirect("employee_requests.jsp?success=1");
                } else {
                    response.sendRedirect("asset_requests.jsp?msg=added");
                }

            } else {
                if ("EMPLOYEE".equals(role)) {
                    response.sendRedirect("employee_requests.jsp?new=1&error=failed");
                } else {
                    response.sendRedirect("add_request.jsp?error=failed");
                }
            }

        } catch (Exception e) {
            e.printStackTrace();
            HttpSession session = request.getSession(false);
            if (session != null && "EMPLOYEE".equals(session.getAttribute("role"))) {
                response.sendRedirect("employee_requests.jsp?new=1&error=server");
            } else {
                response.sendRedirect("add_request.jsp?error=server");
            }
        }
    }

    private String getRoleBasedActionMessage(String role, String username) {

        if ("SUPER_ADMIN".equals(role) || "ADMIN".equals(role)) {
            return "This request has been recorded by the Super Admin on behalf of the employee.";
        }

        if ("ASSET_MANAGER".equals(role)) {
            return "This request has been recorded by the Asset Manager for asset requirement processing.";
        }

        if ("DEPARTMENT_HEAD".equals(role)) {
            return "This request has been initiated by the Department Head for departmental asset requirement.";
        }

        if ("EMPLOYEE".equals(role)) {
            return "This request has been submitted by the employee and forwarded for review.";
        }

        return "This request has been recorded in IR-AMS by " + username + ".";
    }

    private String getNextStepMessage(String requestStatus) {

        if ("PENDING_DEPT_HEAD".equalsIgnoreCase(requestStatus)) {
            return "Your request is currently awaiting review by your Department Head. You will receive another email once it is forwarded or rejected.";
        }

        if ("PENDING".equalsIgnoreCase(requestStatus)) {
            return "Your request is currently pending for review. You will receive another email when it is approved, rejected or fulfilled.";
        }

        if ("APPROVED".equalsIgnoreCase(requestStatus)) {
            return "Your request has been approved and will now proceed for asset allocation or fulfilment.";
        }

        if ("REJECTED".equalsIgnoreCase(requestStatus)) {
            return "Your request has been rejected. Please contact the Asset Manager or Department Head for further clarification.";
        }

        if ("FULFILLED".equalsIgnoreCase(requestStatus)) {
            return "Your request has been fulfilled. Please check the allocated asset details in IR-AMS.";
        }

        return "Please log in to IR-AMS for further updates regarding this request.";
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

    private int getLinkedEmployeeId(int userId) {
        if (userId <= 0) {
            return 0;
        }

        String sql = "SELECT employee_id FROM users WHERE user_id = ? AND employee_id IS NOT NULL";

        try (Connection con = DBConnection.getConnection();
             PreparedStatement ps = con.prepareStatement(sql)) {
            ps.setInt(1, userId);

            try (ResultSet rs = ps.executeQuery()) {
                if (rs.next()) {
                    return rs.getInt("employee_id");
                }
            }
        } catch (Exception e) {
            e.printStackTrace();
        }

        return 0;
    }

    private int parseInt(String value, int fallback) {
        try {
            if (value == null || value.trim().isEmpty()) {
                return fallback;
            }

            return Integer.parseInt(value.trim());
        } catch (Exception e) {
            return fallback;
        }
    }

    private String getArrayValue(String[] array, int index, String fallback) {
        if (array == null || index < 0 || index >= array.length) {
            return fallback;
        }

        return safe(array[index], fallback);
    }

    private String safe(String value, String fallback) {
        if (value == null || value.trim().isEmpty()) {
            return fallback;
        }

        return value.trim();
    }
}
