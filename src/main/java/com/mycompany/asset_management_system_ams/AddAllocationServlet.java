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

@WebServlet(name = "AddAllocationServlet", urlPatterns = {"/AddAllocationServlet"})
public class AddAllocationServlet extends HttpServlet {

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

            // Fault (Low, fixed): defaulted a missing session user_id to 1, silently
            // mis-attributing blocked/failed attempts to whichever account happens to
            // be user_id 1 - same bug class already fixed in the QR module (see
            // GenerateAssetQrServlet etc). AuditDAO.log() correctly resolves an id <= 0
            // to a NULL/"unknown actor" row instead.
            int auditUserId = userId > 0 ? userId : 0;

            if (!("SUPER_ADMIN".equals(role) || "ADMIN".equals(role)) && !"ASSET_MANAGER".equalsIgnoreCase(role)) {
                AuditDAO.log(
                        auditUserId,
                        "ADD_BLOCKED",
                        "asset_allocation",
                        0,
                        "Unauthorized allocation attempt by " + username
                        + " (" + formatRole(role) + ")."
                );

                response.sendRedirect("allocation.jsp?access=denied");
                return;
            }

            String[] assetIds = request.getParameterValues("assetIds");

            if (assetIds == null || assetIds.length == 0) {
                AuditDAO.log(
                        auditUserId,
                        "ADD_BLOCKED",
                        "asset_allocation",
                        0,
                        "Allocation blocked. No asset selected. Attempted by "
                        + username + " (" + formatRole(role) + ")."
                );

                response.sendRedirect("add_allocation.jsp?error=noasset");
                return;
            }

            int employeeId = parseInt(request.getParameter("employeeId"), 0);

            String allocationDate = safe(request.getParameter("allocationDate"), "");
            String returnDate = "";
            String allocationStatus = "ALLOCATED";
            String remarks = safe(request.getParameter("remarks"), "Issued for official railway work");

            if (employeeId <= 0) {
                AuditDAO.log(
                        auditUserId,
                        "ADD_BLOCKED",
                        "asset_allocation",
                        0,
                        "Allocation blocked. Invalid employee selected. Attempted by "
                        + username + " (" + formatRole(role) + ")."
                );

                response.sendRedirect("add_allocation.jsp?error=failed");
                return;
            }

            if (!DateValidationUtil.isPastOrToday(allocationDate)) {
                AuditDAO.log(
                        auditUserId,
                        "ADD_BLOCKED",
                        "asset_allocation",
                        0,
                        "Allocation blocked. Invalid or future allocation date: "
                        + allocationDate
                        + ". Employee ID: " + employeeId
                        + ". Attempted by " + username + " (" + formatRole(role) + ")."
                );

                response.sendRedirect("add_allocation.jsp?error=invaliddate");
                return;
            }

            AssetAllocationDAO dao = new AssetAllocationDAO();

            int successCount = 0;
            int failedCount = 0;
            int firstAllocationId = 0;

            List<String[]> successfulAllocationDetails = new ArrayList<>();

            for (String assetIdText : assetIds) {

                int assetId = parseInt(assetIdText, 0);

                if (assetId <= 0) {
                    failedCount++;

                    AuditDAO.log(
                            auditUserId,
                            "ADD_BLOCKED",
                            "asset_allocation",
                            0,
                            "Allocation blocked for invalid asset selection. Raw value: "
                            + safe(assetIdText, "N/A")
                            + ". Employee ID: " + employeeId
                            + ". Attempted by " + username + " (" + formatRole(role) + ")."
                    );

                    continue;
                }

                int allocationId = dao.addAllocationAndReturnId(
                        assetId,
                        employeeId,
                        allocationDate,
                        returnDate,
                        allocationStatus,
                        remarks,
                        userId
                );

                if (allocationId > 0) {
                    successCount++;
                    QrSnapshotService.syncAssetQuietly(assetId);

                    if (firstAllocationId == 0) {
                        firstAllocationId = allocationId;
                    }

                    String[] details = dao.getAllocationNotificationDetails(allocationId);

                    if (details != null) {
                        successfulAllocationDetails.add(details);
                    }

                    AuditDAO.log(
                            auditUserId,
                            "ADD",
                            "asset_allocation",
                            allocationId,
                            "Asset allocation created successfully. Allocation ID: "
                            + allocationId
                            + ", Asset ID: " + assetId
                            + ", Employee ID: " + employeeId
                            + ", Allocation Date: " + allocationDate
                            + ", Status: " + allocationStatus
                            + ", Created by: " + username
                            + " (" + formatRole(role) + ")."
                    );

                } else {
                    failedCount++;

                    AuditDAO.log(
                            auditUserId,
                            "ADD_BLOCKED",
                            "asset_allocation",
                            0,
                            "Asset allocation blocked by backend validation. "
                            + "Possible reason: asset already allocated/unavailable, employee inactive, or employee soft-deleted. "
                            + "Asset ID: " + assetId
                            + ", Employee ID: " + employeeId
                            + ", Attempted by: " + username
                            + " (" + formatRole(role) + ")."
                    );
                }
            }

            if (successCount > 0) {
                sendAllocationEmail(
                        request,
                        successfulAllocationDetails,
                        firstAllocationId,
                        username,
                        role,
                        allocationDate,
                        returnDate,
                        allocationStatus,
                        remarks
                );
            }

            if (successCount > 0 && failedCount == 0) {
                response.sendRedirect("allocation.jsp?msg=added");

            } else if (successCount > 0) {
                response.sendRedirect("allocation.jsp?msg=partial");

            } else {
                response.sendRedirect("add_allocation.jsp?error=blocked");
            }

        } catch (Exception e) {
            e.printStackTrace();
            response.sendRedirect("add_allocation.jsp?error=server");
        }
    }

    private void sendAllocationEmail(
            HttpServletRequest request,
            List<String[]> allocationDetailsList,
            int referenceAllocationId,
            String username,
            String role,
            String allocationDate,
            String returnDate,
            String allocationStatus,
            String remarks
    ) {
        try {
            if (allocationDetailsList == null || allocationDetailsList.isEmpty()) {
                return;
            }

            String[] first = allocationDetailsList.get(0);

            String employeeEmail = getArrayValue(first, 0, "");
            String employeeName = getArrayValue(first, 1, "Employee");
            String employeeCode = getArrayValue(first, 2, "N/A");
            String departmentName = getArrayValue(first, 3, "N/A");
            
            // To pass employeeId to buildAllocationRecipients, we can fetch it or pass it.
            // But AddAllocationServlet has employeeId in doPost.
            // The details array has employee_id? Wait, details index 0 is email, 1 name, 2 code, 3 dept.
            // Let's pass employeeId from doPost. Oh wait, I can extract employeeId from request.getParameter("employeeId")?
            // Yes, request is passed to sendAllocationEmail.
            int employeeId = 0;
            try {
                employeeId = Integer.parseInt(request.getParameter("employeeId"));
            } catch (Exception e) {}

            NotificationEventService.EmailRouting routing = NotificationEventService.buildAllocationRecipients("ALLOCATED", employeeId);
            employeeEmail = routing.getToEmail();
            String ccEmail = routing.getCcEmail();

            String subject = "IR-AMS | Asset Allocation Recorded | Allocation #" + referenceAllocationId;

            StringBuilder assetListHtml = new StringBuilder();
            assetListHtml.append("<tr><th colspan=\"2\" style=\"background-color: #e2e8f0; text-align: center;\">Allocated Assets</th></tr>");

            for (String[] details : allocationDetailsList) {
                String allocationId = getArrayValue(details, 12, "N/A");
                String assetCode = getArrayValue(details, 4, "N/A");
                String assetName = getArrayValue(details, 5, "N/A");
                String serialNumber = getArrayValue(details, 6, "N/A");
                String location = getArrayValue(details, 7, "N/A");

                assetListHtml.append("<tr><th>Asset:</th><td>").append(assetName).append(" (").append(assetCode).append(")</td></tr>")
                             .append("<tr><th>Serial Number:</th><td>").append(serialNumber).append("</td></tr>")
                             .append("<tr><th>Location:</th><td>").append(location).append("</td></tr>")
                             .append("<tr><td colspan=\"2\" style=\"border-bottom: 2px solid #cbd5e0;\"></td></tr>");
            }

            String detailsTable = "<tr><th>Employee:</th><td>" + employeeName + " (" + employeeCode + ")</td></tr>"
                    + "<tr><th>Department:</th><td>" + departmentName + "</td></tr>"
                    + "<tr><th>Allocation Date:</th><td>" + safe(allocationDate, "N/A") + "</td></tr>"
                    + "<tr><th>Expected Return:</th><td>" + safe(returnDate, "Not specified") + "</td></tr>"
                    + "<tr><th>Status:</th><td>" + safe(allocationStatus, "ALLOCATED") + "</td></tr>"
                    // Fault (Medium, fixed): remarks is free text embedded unescaped in this
                    // HTML email - same recurring class as audit/10-maintenance.md Finding 1.
                    + "<tr><th>Remarks:</th><td>" + HtmlEscapeUtil.escape(safe(remarks, "N/A")) + "</td></tr>"
                    + assetListHtml.toString();

            String actionNote = getAllocationStatusMessage(allocationStatus);

            String body = NotificationHelper.buildHtmlEmail(employeeName, "Asset Allocation Recorded", detailsTable, actionNote);

            NotificationHelper.sendAllocationAlert(
                    request.getServletContext(),
                    referenceAllocationId,
                    employeeEmail,
                    ccEmail,
                    "",
                    subject,
                    body
            );

        } catch (Exception e) {
            e.printStackTrace();
        }
    }

    private String getAllocationStatusMessage(String allocationStatus) {
        if ("ALLOCATED".equalsIgnoreCase(allocationStatus)) {
            return "The above asset has been allocated for official use. Please handle it responsibly and complete return verification through IR-AMS when the asset is returned.";
        }
        return "Please log in to IR-AMS for further details regarding this allocation.";
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
