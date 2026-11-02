package com.mycompany.asset_management_system_ams;

import java.io.IOException;
import java.util.Arrays;
import java.util.List;

import jakarta.servlet.ServletException;
import jakarta.servlet.annotation.WebServlet;
import jakarta.servlet.http.HttpServlet;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import jakarta.servlet.http.HttpSession;

@WebServlet(name = "UpdateMaintenanceRequestStatusServlet", urlPatterns = {"/UpdateMaintenanceRequestStatusServlet"})
public class UpdateMaintenanceRequestStatusServlet extends HttpServlet {

    // maintenance_requests.request_status is a plain VARCHAR(30), not a DB
    // ENUM - nothing at the database level stops garbage from being written.
    // maintenance.jsp's own action-button logic only recognizes these four
    // exact values (PENDING -> show Approve/Reject, APPROVED/IN_PROGRESS ->
    // show Complete, anything else -> "No Actions" with no way to act on it
    // again). Before this fix, requestStatus was written to the DB completely
    // unvalidated - any typo'd or tampered value would permanently strand a
    // request with no further action buttons ever appearing in the UI again.
    private static final List<String> VALID_STATUSES =
            Arrays.asList("PENDING", "APPROVED", "REJECTED", "COMPLETED", "IN_PROGRESS");

    @Override
    protected void doPost(HttpServletRequest request, HttpServletResponse response)
            throws ServletException, IOException {

        request.setCharacterEncoding("UTF-8");

        HttpSession session = request.getSession(false);
        if (session == null || session.getAttribute("username") == null || session.getAttribute("role") == null) {
            response.sendRedirect("login.jsp");
            return;
        }

        String username = String.valueOf(session.getAttribute("username"));
        String role = (String) session.getAttribute("role");
        if (!("SUPER_ADMIN".equals(role) || "ADMIN".equals(role)) && !"ASSET_MANAGER".equalsIgnoreCase(role)) {
            response.sendRedirect("dashboard.jsp?access=denied");
            return;
        }

        int userId = getSessionInt(session, "user_id", 1);
        if (userId == 1) {
            userId = getSessionInt(session, "userId", 1);
        }

        String requestIdStr = request.getParameter("requestId");
        String requestStatus = clean(request.getParameter("requestStatus")).toUpperCase();
        String remarks = request.getParameter("remarks");

        // Only meaningful when requestStatus is COMPLETED - see
        // MaintenanceRequestDAO.updateMaintenanceRequestStatus()'s javadoc.
        // 0 (not present, or "none available") is a legal value: a request
        // can still be completed with nothing to link to.
        int resolvedMaintenanceId = 0;
        try {
            resolvedMaintenanceId = Integer.parseInt(clean(request.getParameter("resolvedMaintenanceId")));
        } catch (NumberFormatException ignored) {
        }

        int requestId = 0;
        try {
            requestId = Integer.parseInt(requestIdStr);
        } catch (NumberFormatException e) {
            response.sendRedirect("maintenance.jsp?error=invalid_request");
            return;
        }

        if (requestStatus.isEmpty()) {
            response.sendRedirect("maintenance.jsp?error=empty_status");
            return;
        }

        if (!VALID_STATUSES.contains(requestStatus)) {
            response.sendRedirect("maintenance.jsp?error=invalid_status");
            return;
        }

        MaintenanceRequestDAO dao = new MaintenanceRequestDAO();
        boolean success = dao.updateMaintenanceRequestStatus(requestId, requestStatus, remarks, resolvedMaintenanceId);

        if (success) {
            AuditDAO.log(
                    userId,
                    "UPDATE",
                    "maintenance_requests",
                    requestId,
                    "Maintenance request status changed to " + requestStatus
                    + ". Request ID: " + requestId
                    + (resolvedMaintenanceId > 0 ? ", Resolved by Maintenance Log #" + resolvedMaintenanceId : "")
                    + ", Updated by: " + username + " (" + formatRoleName(role) + ")."
            );

            response.sendRedirect("maintenance.jsp?msg=status_updated");
        } else {
            response.sendRedirect("maintenance.jsp?error=update_failed");
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

    private String formatRoleName(String roleName) {
        if (roleName == null || roleName.trim().isEmpty()) {
            return "N/A";
        }
        return roleName.replace("_", " ");
    }
}
