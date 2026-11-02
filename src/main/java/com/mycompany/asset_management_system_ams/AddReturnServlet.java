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

@WebServlet(name = "AddReturnServlet", urlPatterns = {"/AddReturnServlet"})
public class AddReturnServlet extends HttpServlet {

    @Override
    protected void doPost(HttpServletRequest request, HttpServletResponse response)
            throws ServletException, IOException {

        int allocationId = 0;

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

            if (!("SUPER_ADMIN".equals(role) || "ADMIN".equals(role)) && !"ASSET_MANAGER".equalsIgnoreCase(role)
                    && !"EMPLOYEE".equalsIgnoreCase(role)) {

                AuditDAO.log(
                        auditUserId,
                        "ADD_BLOCKED",
                        "asset_returns",
                        0,
                        "Unauthorized return attempt by " + username
                        + " (" + formatRole(role) + ")."
                );

                response.sendRedirect("returns.jsp?access=denied");
                return;
            }

            allocationId = parseInt(request.getParameter("allocationId"), 0);

            if (allocationId <= 0) {
                AuditDAO.log(
                        auditUserId,
                        "ADD_BLOCKED",
                        "asset_returns",
                        0,
                        "Return blocked. Invalid allocation selected. Attempted by: "
                        + username
                        + " (" + formatRole(role) + ")."
                );

                response.sendRedirect("add_return.jsp?error=failed");
                return;
            }

            String returnDate = safe(request.getParameter("returnDate"), "");
            String returnCondition = normalizeReturnCondition(request.getParameter("returnCondition"));
            String receivedBy = safe(request.getParameter("receivedBy"), "");
            String remarks = safe(request.getParameter("remarks"), "");

            if (!DateValidationUtil.isPastOrToday(returnDate)) {
                AuditDAO.log(
                        auditUserId,
                        "ADD_BLOCKED",
                        "asset_returns",
                        0,
                        "Return blocked. Invalid or future return date: "
                        + returnDate
                        + ". Allocation ID: " + allocationId
                        + ". Attempted by: " + username
                        + " (" + formatRole(role) + ")."
                );

                response.sendRedirect("add_return.jsp?allocationId=" + allocationId + "&error=invaliddate");
                return;
            }

            // Was calling getAllocationsByEmployeeId(0) and looping to find the one
            // matching allocationId - employeeId=0 means AssetAllocationDAO builds no
            // WHERE clause at all, so this fetched every allocation row that has ever
            // existed in the system on every single return submission, just to read one
            // record. AssetAllocationDAO.getAllocationById(allocationId) already exists
            // and does the same lookup as a single indexed-PK query.
            AssetAllocationDAO allocationDao = new AssetAllocationDAO();
            AssetAllocation targetAllocation = allocationDao.getAllocationById(allocationId);
            String allocationDate = targetAllocation == null ? null : targetAllocation.getAllocationDate();

            if (allocationDate != null && !DateValidationUtil.isDateNotBefore(returnDate, allocationDate)) {
                AuditDAO.log(
                        auditUserId,
                        "ADD_BLOCKED",
                        "asset_returns",
                        0,
                        "Return blocked. Return date (" + returnDate + ") is before allocation date (" + allocationDate + ")."
                        + ". Allocation ID: " + allocationId
                        + ". Attempted by: " + username
                        + " (" + formatRole(role) + ")."
                );

                response.sendRedirect("add_return.jsp?allocationId=" + allocationId + "&error=invaliddate");
                return;
            }

            if (receivedBy.trim().isEmpty() || remarks.trim().isEmpty()) {
                AuditDAO.log(
                        auditUserId,
                        "ADD_BLOCKED",
                        "asset_returns",
                        0,
                        "Return blocked. Receiving authority or remarks missing. Allocation ID: "
                        + allocationId
                        + ". Attempted by: " + username
                        + " (" + formatRole(role) + ")."
                );

                response.sendRedirect("add_return.jsp?allocationId=" + allocationId + "&error=failed");
                return;
            }

            AssetReturnDAO dao = new AssetReturnDAO();

            int returnId = dao.addReturnAndReturnId(
                    allocationId,
                    returnDate,
                    returnCondition,
                    receivedBy,
                    remarks
            );

            if (returnId > 0) {

                QrSnapshotService.syncAssetQuietly(getAssetIdByAllocationId(allocationId));

                AuditDAO.log(
                        auditUserId,
                        "ADD",
                        "asset_returns",
                        returnId,
                        "Asset return recorded successfully. Return ID: "
                        + returnId
                        + ", Allocation ID: " + allocationId
                        + ", Return Date: " + returnDate
                        + ", Return Condition: " + returnCondition
                        + ", Received By: " + receivedBy
                        + ", Created by: " + username
                        + " (" + formatRole(role) + ")."
                );

                sendReturnEmail(
                        request,
                        dao,
                        returnId,
                        allocationId,
                        username,
                        role,
                        returnDate,
                        returnCondition,
                        receivedBy,
                        remarks
                );

                response.sendRedirect("returns.jsp?msg=added");

            } else {
                AuditDAO.log(
                        auditUserId,
                        "ADD_BLOCKED",
                        "asset_returns",
                        0,
                        "Return blocked by backend validation. Possible reason: allocation already returned, invalid allocation, or duplicate return. "
                        + "Allocation ID: " + allocationId
                        + ". Attempted by: " + username
                        + " (" + formatRole(role) + ")."
                );

                response.sendRedirect("add_return.jsp?allocationId=" + allocationId + "&error=blocked");
            }

        } catch (Exception e) {
            e.printStackTrace();

            if (allocationId > 0) {
                response.sendRedirect("add_return.jsp?allocationId=" + allocationId + "&error=server");
            } else {
                response.sendRedirect("add_return.jsp?error=server");
            }
        }
    }

    private int getAssetIdByAllocationId(int allocationId) {
        String sql = "SELECT asset_id FROM asset_allocation WHERE allocation_id = ? LIMIT 1";

        try (Connection con = DBConnection.getConnection();
             PreparedStatement ps = con.prepareStatement(sql)) {

            ps.setInt(1, allocationId);

            try (ResultSet rs = ps.executeQuery()) {
                if (rs.next()) {
                    return rs.getInt("asset_id");
                }
            }

        } catch (Exception e) {
            e.printStackTrace();
        }

        return 0;
    }

    private void sendReturnEmail(
            HttpServletRequest request,
            AssetReturnDAO dao,
            int returnId,
            int allocationId,
            String username,
            String role,
            String returnDate,
            String returnCondition,
            String receivedBy,
            String remarks
    ) {
        try {
            String[] details = dao.getReturnNotificationDetails(returnId);

            if (details == null) {
                return;
            }

            String employeeEmail = getArrayValue(details, 0, "");
            String employeeName = getArrayValue(details, 1, "Employee");
            String employeeCode = getArrayValue(details, 2, "N/A");
            String departmentName = getArrayValue(details, 3, "N/A");
            String assetCode = getArrayValue(details, 4, "N/A");
            String assetName = getArrayValue(details, 5, "N/A");
            String serialNumber = getArrayValue(details, 6, "N/A");
            String location = getArrayValue(details, 7, "N/A");

            // Extract employee_id from DB using dao
            int employeeId = 0;
            try {
                employeeId = dao.getEmployeeIdByReturnId(returnId);
            } catch (Exception e) {}

            String action = "SUBMIT"; 
            if ("DAMAGED".equalsIgnoreCase(returnCondition)) action = "DAMAGED";
            
            NotificationEventService.EmailRouting routing = NotificationEventService.buildReturnRecipients(action, employeeId);
            String toEmail = routing.getToEmail();
            String ccEmail = routing.getCcEmail();

            String subject = "IR-AMS | Asset Return Recorded | Return #" + returnId;

            String detailsTable = "<tr><th>Return ID:</th><td>" + returnId + "</td></tr>"
                    + "<tr><th>Allocation ID:</th><td>" + allocationId + "</td></tr>"
                    + "<tr><th>Employee:</th><td>" + employeeName + " (" + employeeCode + ")</td></tr>"
                    + "<tr><th>Department:</th><td>" + departmentName + "</td></tr>"
                    + "<tr><th>Asset:</th><td>" + assetName + " (" + assetCode + ")</td></tr>"
                    + "<tr><th>Serial Number:</th><td>" + serialNumber + "</td></tr>"
                    + "<tr><th>Location:</th><td>" + location + "</td></tr>"
                    + "<tr><th>Return Date:</th><td>" + safe(returnDate, "N/A") + "</td></tr>"
                    + "<tr><th>Return Condition:</th><td>" + returnCondition + "</td></tr>"
                    // Fault (Medium, fixed): receivedBy/remarks are free text embedded
                    // unescaped - same recurring class as audit/10-maintenance.md Finding 1.
                    + "<tr><th>Received By:</th><td>" + HtmlEscapeUtil.escape(safe(receivedBy, "N/A")) + "</td></tr>"
                    + "<tr><th>Remarks:</th><td>" + HtmlEscapeUtil.escape(safe(remarks, "N/A")) + "</td></tr>";
            
            String actionNote = getConditionMessage(returnCondition);

            String body = NotificationHelper.buildHtmlEmail(employeeName, "Asset Return Verification", detailsTable, actionNote);

            NotificationHelper.sendReturnAlert(
                    request.getServletContext(),
                    returnId,
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

    private String getConditionMessage(String returnCondition) {

        if ("GOOD".equalsIgnoreCase(returnCondition)) {
            return "The returned asset has been marked in good condition and may be made available for future allocation.";
        }

        if ("DAMAGED".equalsIgnoreCase(returnCondition)) {
            return "The returned asset has been marked as damaged and routed for asset manager review.";
        }

        if ("NEEDS_REPAIR".equalsIgnoreCase(returnCondition)) {
            return "The returned asset has been marked for repair and routed to maintenance status.";
        }

        return "Please log in to IR-AMS for further details regarding this return.";
    }

    private String normalizeReturnCondition(String returnCondition) {

        if (returnCondition == null || returnCondition.trim().isEmpty()) {
            return "GOOD";
        }

        String condition = returnCondition.trim().toUpperCase().replace(" ", "_");

        if ("REPAIR_REQUIRED".equals(condition)) {
            return "NEEDS_REPAIR";
        }

        if ("DAMAGED".equals(condition)) {
            return "DAMAGED";
        }

        if ("NEEDS_REPAIR".equals(condition)) {
            return "NEEDS_REPAIR";
        }

        return "GOOD";
    }

    private String formatRole(String role) {

        if (role == null || role.trim().isEmpty()) {
            return "System User";
        }

        return role.replace("_", " ");
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
