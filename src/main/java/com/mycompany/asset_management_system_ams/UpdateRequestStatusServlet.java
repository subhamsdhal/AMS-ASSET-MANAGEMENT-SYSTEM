package com.mycompany.asset_management_system_ams;

import java.io.IOException;
import jakarta.servlet.ServletException;
import jakarta.servlet.annotation.WebServlet;
import jakarta.servlet.http.HttpServlet;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import jakarta.servlet.http.HttpSession;

@WebServlet(name = "UpdateRequestStatusServlet", urlPatterns = {"/UpdateRequestStatusServlet"})
public class UpdateRequestStatusServlet extends HttpServlet {

    @Override
    protected void doPost(HttpServletRequest request, HttpServletResponse response)
            throws ServletException, IOException {

        int requestId = 0;

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

            // Default of 0 (not 1) on a missing session attribute - defaulting to 1
            // would silently mis-attribute this Approve/Reject/Fulfill audit-log
            // entry to whichever real account happens to be user_id 1 (typically
            // the first admin) instead of showing "unknown actor". Matches the
            // safer default already used by the sibling AddAssetRequestServlet.
            int userId = getSessionInt(session, "user_id", 0);

            if (userId <= 0) {
                userId = getSessionInt(session, "userId", 0);
            }

            if (!("SUPER_ADMIN".equals(role) || "ADMIN".equals(role)) && !"ASSET_MANAGER".equalsIgnoreCase(role)) {
                response.sendRedirect("asset_requests.jsp?access=denied");
                return;
            }

            requestId = parseInt(request.getParameter("requestId"), 0);
            String requestStatus = normalizeStatus(request.getParameter("requestStatus"));
            String remarks = clean(request.getParameter("remarks"));
            // Only meaningful when requestStatus is FULFILLED - see
            // AssetRequestDAO.updateRequestStatus()'s javadoc. 0 ("no
            // allocation selected") is a legal value when the employee has no
            // active allocation to pick from.
            int fulfilledAllocationId = parseInt(request.getParameter("fulfilledAllocationId"), 0);

            if (requestId <= 0 || requestStatus.isEmpty()) {
                response.sendRedirect("asset_requests.jsp?error=failed");
                return;
            }

            AssetRequestDAO dao = new AssetRequestDAO();
            boolean updated = dao.updateRequestStatus(requestId, requestStatus, username, remarks, fulfilledAllocationId);

            if (updated) {
                String action = "UPDATED";
                if ("APPROVED".equals(requestStatus)) action = "APPROVED";
                if ("REJECTED".equals(requestStatus)) action = "REJECTED";
                if ("FULFILLED".equals(requestStatus)) action = "FULFILLED";

                AuditDAO.log(
                        userId,
                        action.toUpperCase(),
                        "asset_requests",
                        requestId,
                        "Asset request " + requestStatus + " by " + username
                        + (fulfilledAllocationId > 0 ? ", fulfilled via Allocation #" + fulfilledAllocationId : "")
                );

                String[] details = dao.getRequestNotificationDetails(requestId);

                String employeeEmail = "";
                String employeeName = "Employee";
                String employeeCode = "N/A";
                String categoryName = "Requested Asset Category";
                String requestDate = "N/A";
                String departmentName = "N/A";

                if (details != null) {
                    employeeEmail = getArrayValue(details, 0, "");
                    employeeName = getArrayValue(details, 1, "Employee");
                    employeeCode = getArrayValue(details, 2, "N/A");
                    categoryName = getArrayValue(details, 3, "Requested Asset Category");
                    requestDate = getArrayValue(details, 4, "N/A");
                    departmentName = getArrayValue(details, 9, "N/A");
                }

                int employeeId = 0;
                if (details != null) {
                    try {
                        // We need employee_id for buildAssetRequestRecipients
                        employeeId = dao.getEmployeeIdByRequestId(requestId); 
                    } catch (Exception e) {}
                }

                NotificationEventService.EmailRouting routing = NotificationEventService.buildAssetRequestRecipients(action, employeeId);
                String toEmail = routing.getToEmail();
                String ccEmail = routing.getCcEmail();

                String subject = "Asset Request " + requestStatus + " - Request #" + requestId;

                String detailsTable = "<tr><th>Request ID:</th><td>" + requestId + "</td></tr>"
                        + "<tr><th>Employee:</th><td>" + employeeName + " (" + employeeCode + ")</td></tr>"
                        + "<tr><th>Department:</th><td>" + departmentName + "</td></tr>"
                        + "<tr><th>Requested Category:</th><td>" + categoryName + "</td></tr>"
                        + "<tr><th>Request Date:</th><td>" + requestDate + "</td></tr>"
                        + "<tr><th>Current Status:</th><td>" + requestStatus + "</td></tr>"
                        // Fault (Medium, fixed): remarks (an approver's own free-text note) was
                        // embedded unescaped - same recurring class as
                        // audit/10-maintenance.md Finding 1.
                        + "<tr><th>Remarks:</th><td>" + HtmlEscapeUtil.escape(remarks) + "</td></tr>";
                
                String actionNote = getStatusActionMessage(requestStatus, role, username) + "<br><br>" 
                        + getNextStepMessage(requestStatus) + "<br><br>Please log in to IR-AMS for further review or action.";

                String body = NotificationHelper.buildHtmlEmail(employeeName, "Asset Request Status Updated", detailsTable, actionNote);

                NotificationHelper.sendAssetRequestAlert(
                        getServletContext(),
                        requestId,
                        toEmail,
                        ccEmail,
                        "",
                        subject,
                        body
                );

                if ("APPROVED".equals(requestStatus)) {
                    response.sendRedirect("asset_requests.jsp?msg=approved");
                } else if ("REJECTED".equals(requestStatus)) {
                    response.sendRedirect("asset_requests.jsp?msg=rejected");
                } else if ("FULFILLED".equals(requestStatus)) {
                    response.sendRedirect("asset_requests.jsp?msg=fulfilled");
                } else {
                    response.sendRedirect("asset_requests.jsp?msg=updated");
                }

            } else {
                response.sendRedirect("asset_requests.jsp?error=updatefailed");
            }

        } catch (Exception e) {
            e.printStackTrace();
            response.sendRedirect("asset_requests.jsp?error=server");
        }
    }

    private String getStatusActionMessage(String requestStatus, String role, String username) {
        String roleText = formatRole(role);
        if ("APPROVED".equalsIgnoreCase(requestStatus)) {
            return "This request has been approved by " + roleText + " " + username + ".";
        }
        if ("REJECTED".equalsIgnoreCase(requestStatus)) {
            return "This request has been rejected by " + roleText + " " + username + ".";
        }
        if ("FULFILLED".equalsIgnoreCase(requestStatus)) {
            return "This request has been fulfilled by " + roleText + " " + username + ".";
        }
        return "This request has been updated by " + roleText + " " + username + ".";
    }

    private String getNextStepMessage(String requestStatus) {
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

    private int parseInt(String value, int defaultValue) {
        try {
            return Integer.parseInt(clean(value));
        } catch (Exception e) {
            return defaultValue;
        }
    }

    private int getSessionInt(HttpSession session, String key, int defaultValue) {
        try {
            Object obj = session.getAttribute(key);
            if (obj != null) {
                return Integer.parseInt(String.valueOf(obj));
            }
        } catch (Exception e) {
        }
        return defaultValue;
    }

    private String clean(String value) {
        if (value == null) {
            return "";
        }
        return value.trim();
    }

    private String safe(String value, String defaultIfEmpty) {
        String cleanValue = clean(value);
        return cleanValue.isEmpty() ? defaultIfEmpty : cleanValue;
    }

    private String getArrayValue(String[] array, int index, String defaultValue) {
        if (array != null && index >= 0 && index < array.length) {
            return safe(array[index], defaultValue);
        }
        return defaultValue;
    }

    private String formatRole(String role) {
        if (role == null) return "User";
        String cleanRole = role.trim().toUpperCase();
        if ("SUPER_ADMIN".equals(cleanRole) || "ADMIN".equals(cleanRole)) return "Super Admin";
        if ("ASSET_MANAGER".equals(cleanRole)) return "Asset Manager";
        if ("DEPARTMENT_HEAD".equals(cleanRole)) return "Department Head";
        if ("AUDITOR".equals(cleanRole)) return "Auditor";
        if ("EMPLOYEE".equals(cleanRole)) return "Employee";
        return "User";
    }

    // Fault (Low-Medium, fixed): any unrecognized requestStatus value (a UI bug,
    // a tampered request, or a stale/replayed form) used to silently fall back to
    // "PENDING" here. AssetRequestDAO.updateRequestStatus()'s transition guard
    // only applies a requiredCurrentStatus precondition for APPROVED/REJECTED/
    // FULFILLED targets - a PENDING target has none, so that fallback could reset
    // an already-APPROVED/REJECTED/FULFILLED request back to PENDING with no
    // transition-legality check at all. The real UI (asset_requests.jsp) never
    // submits "PENDING" - only APPROVED/REJECTED/FULFILLED - so rejecting anything
    // else outright (empty string -> the existing requestStatus.isEmpty() check
    // above redirects to ?error=failed) closes the gap without removing any real
    // functionality. See audit/06-asset-requests.md Finding 2.
    private String normalizeStatus(String status) {
        String cleanStatus = clean(status).toUpperCase();
        if ("APPROVED".equals(cleanStatus)
                || "REJECTED".equals(cleanStatus)
                || "FULFILLED".equals(cleanStatus)) {
            return cleanStatus;
        }
        return "";
    }
}
