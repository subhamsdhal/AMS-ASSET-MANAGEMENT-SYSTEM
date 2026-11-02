package com.mycompany.asset_management_system_ams;

import java.io.IOException;

import jakarta.servlet.ServletException;
import jakarta.servlet.annotation.WebServlet;
import jakarta.servlet.http.HttpServlet;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import jakarta.servlet.http.HttpSession;

@WebServlet(name = "AddMaintenanceServlet", urlPatterns = {"/AddMaintenanceServlet"})
public class AddMaintenanceServlet extends HttpServlet {

    @Override
    protected void doPost(HttpServletRequest request, HttpServletResponse response)
            throws ServletException, IOException {

        HttpSession session = request.getSession(false);

        try {
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

            if (!isMaintenanceManager(role)) {
                AuditDAO.log(
                        userId,
                        "ADD_BLOCKED",
                        "maintenance_logs",
                        0,
                        "Unauthorized maintenance add attempt by: " + username
                );

                response.sendRedirect("maintenance.jsp?access=denied");
                return;
            }

            int assetId = parseInt(request.getParameter("assetId"), 0);

            String maintenanceDate = safe(request.getParameter("maintenanceDate"), "");
            String maintenanceType = normalizeMaintenanceType(request.getParameter("maintenanceType"));
            String description = safe(request.getParameter("description"), "");
            String performedBy = safe(request.getParameter("performedBy"), "");
            String assetStatusAfterMaintenance = normalizeAssetStatusAfterMaintenance(
                    request.getParameter("assetStatusAfterMaintenance")
            );

            double cost = parseDouble(request.getParameter("cost"), -1);

            if (assetId <= 0) {
                AuditDAO.log(
                        userId,
                        "ADD_BLOCKED",
                        "maintenance_logs",
                        0,
                        "Maintenance add blocked. Invalid asset selected. Created by: " + username
                );

                response.sendRedirect("add_maintenance.jsp?error=failed");
                return;
            }

            if (maintenanceDate.isEmpty() || !DateValidationUtil.isPastOrToday(maintenanceDate)) {
                AuditDAO.log(
                        userId,
                        "ADD_BLOCKED",
                        "maintenance_logs",
                        0,
                        "Maintenance add blocked due to invalid/future maintenance date. Asset ID: "
                        + assetId + ", Date: " + maintenanceDate + ", Created by: " + username
                );

                response.sendRedirect("add_maintenance.jsp?error=invaliddate");
                return;
            }

            if (maintenanceType.isEmpty()) {
                AuditDAO.log(
                        userId,
                        "ADD_BLOCKED",
                        "maintenance_logs",
                        0,
                        "Maintenance add blocked due to invalid maintenance type. Asset ID: "
                        + assetId + ", Created by: " + username
                );

                response.sendRedirect("add_maintenance.jsp?error=failed");
                return;
            }

            if (cost < 0) {
                AuditDAO.log(
                        userId,
                        "ADD_BLOCKED",
                        "maintenance_logs",
                        0,
                        "Maintenance add blocked due to negative/invalid cost. Asset ID: "
                        + assetId + ", Cost: " + request.getParameter("cost")
                        + ", Created by: " + username
                );

                response.sendRedirect("add_maintenance.jsp?error=invalidcost");
                return;
            }

            if (description.isEmpty() || performedBy.isEmpty()) {
                AuditDAO.log(
                        userId,
                        "ADD_BLOCKED",
                        "maintenance_logs",
                        0,
                        "Maintenance add blocked due to missing description/performed by. Asset ID: "
                        + assetId + ", Created by: " + username
                );

                response.sendRedirect("add_maintenance.jsp?error=failed");
                return;
            }

            MaintenanceLogDAO dao = new MaintenanceLogDAO();

            int maintenanceId = dao.addMaintenanceLogAndReturnId(
                    assetId,
                    maintenanceDate,
                    maintenanceType,
                    description,
                    cost,
                    performedBy,
                    assetStatusAfterMaintenance
            );

            if (maintenanceId > 0) {

                QrSnapshotService.syncAssetQuietly(assetId);

                AuditDAO.log(
                        userId,
                        "ADD",
                        "maintenance_logs",
                        maintenanceId,
                        "Maintenance log added. Maintenance ID: " + maintenanceId
                        + ", Asset ID: " + assetId
                        + ", Type: " + maintenanceType
                        + ", Service Outcome: " + formatServiceOutcome(assetStatusAfterMaintenance)
                        + ", Created by: " + username
                );

                sendMaintenanceEmail(
                        request,
                        dao,
                        maintenanceId,
                        assetId,
                        username,
                        role,
                        assetStatusAfterMaintenance
                );

                response.sendRedirect("maintenance.jsp?msg=added");

            } else {
                AuditDAO.log(
                        userId,
                        "ADD_BLOCKED",
                        "maintenance_logs",
                        0,
                        "Maintenance add failed from DAO. Asset may be disposed/invalid. Asset ID: "
                        + assetId + ", Created by: " + username
                );

                response.sendRedirect("add_maintenance.jsp?error=blocked");
            }

        } catch (Exception e) {
            e.printStackTrace();

            try {
                int fallbackUserId = 1;

                if (session != null) {
                    fallbackUserId = getSessionInt(session, "user_id", 1);
                }

                AuditDAO.log(
                        fallbackUserId,
                        "ADD_BLOCKED",
                        "maintenance_logs",
                        0,
                        "Maintenance add server error: " + e.getMessage()
                );
            } catch (Exception ignored) {
            }

            response.sendRedirect("add_maintenance.jsp?error=server");
        }
    }

    private void sendMaintenanceEmail(
            HttpServletRequest request,
            MaintenanceLogDAO dao,
            int maintenanceId,
            int assetId,
            String username,
            String role,
            String assetStatusAfterMaintenance
    ) {
        try {
            String[] details = dao.getMaintenanceNotificationDetails(maintenanceId);

            if (details == null) {
                return;
            }

            String assetCode = getArrayValue(details, 0, "N/A");
            String assetName = getArrayValue(details, 1, "N/A");
            String categoryName = getArrayValue(details, 2, "N/A");
            String serialNumber = getArrayValue(details, 3, "N/A");
            String location = getArrayValue(details, 4, "N/A");
            String currentAssetStatus = getArrayValue(details, 5, "N/A");
            String maintenanceDate = getArrayValue(details, 6, "N/A");
            String maintenanceType = getArrayValue(details, 7, "N/A");
            String description = getArrayValue(details, 8, "N/A");
            String cost = getArrayValue(details, 9, "0.0");
            String performedBy = getArrayValue(details, 10, "N/A");
            
            String employeeEmail = getArrayValue(details, 12, "");
            String employeeName = getArrayValue(details, 13, "Not currently allocated");
            String employeeCode = getArrayValue(details, 14, "N/A");
            String departmentName = getArrayValue(details, 15, "N/A");

            String action = "NEW";
            if (Double.parseDouble(cost) >= 5000) action = "HIGH_COST"; // Example logic for high cost

            NotificationEventService.EmailRouting routing = NotificationEventService.buildMaintenanceRecipients(action, assetId);
            String recipientEmail = routing.getToEmail();
            String ccEmail = routing.getCcEmail();

            String displayMaintenanceType = formatDisplayText(maintenanceType);
            String displayServiceOutcome = formatServiceOutcome(assetStatusAfterMaintenance);
            String displayCurrentAssetStatus = formatDisplayText(currentAssetStatus);
            String displayCost = formatCost(cost);

            String typeInstruction = getMaintenanceTypeMessage(
                    maintenanceType,
                    assetStatusAfterMaintenance
            );

            String outcomeInstruction = getServiceOutcomeInstruction(
                    assetStatusAfterMaintenance
            );

            String subject = "IR-AMS | Asset Maintenance Recorded | Maintenance #" + maintenanceId;

            String detailsTable = "<tr><th>Maintenance ID:</th><td>" + maintenanceId + "</td></tr>"
                    + "<tr><th>Asset:</th><td>" + assetName + " (" + assetCode + ")</td></tr>"
                    + "<tr><th>Category:</th><td>" + categoryName + "</td></tr>"
                    + "<tr><th>Serial Number:</th><td>" + serialNumber + "</td></tr>"
                    + "<tr><th>Location:</th><td>" + location + "</td></tr>"
                    + "<tr><th>Allocated To:</th><td>" + employeeName + " (" + employeeCode + ")</td></tr>"
                    + "<tr><th>Department:</th><td>" + departmentName + "</td></tr>"
                    + "<tr><th>Maintenance Date:</th><td>" + maintenanceDate + "</td></tr>"
                    + "<tr><th>Maintenance Type:</th><td>" + displayMaintenanceType + "</td></tr>"
                    // Fault (Medium, fixed): description/performedBy are free text and were
                    // embedded unescaped in this HTML email body - the same vulnerability
                    // class already fixed elsewhere in this codebase (e.g. DeleteEmployeeServlet)
                    // via HtmlEscapeUtil, just not swept into this module. See
                    // audit/10-maintenance.md Finding 1.
                    + "<tr><th>Description:</th><td>" + HtmlEscapeUtil.escape(description) + "</td></tr>"
                    + "<tr><th>Cost:</th><td>Rs. " + displayCost + "</td></tr>"
                    + "<tr><th>Performed By:</th><td>" + HtmlEscapeUtil.escape(performedBy) + "</td></tr>"
                    + "<tr><th>Service Outcome:</th><td>" + displayServiceOutcome + "</td></tr>"
                    + "<tr><th>Current Asset Status:</th><td>" + displayCurrentAssetStatus + "</td></tr>";
            
            String actionNote = typeInstruction + "<br><br>" + outcomeInstruction;

            String body = NotificationHelper.buildHtmlEmail("", "Asset Maintenance Recorded", detailsTable, actionNote);

            NotificationHelper.sendMaintenanceAlert(
                    request.getServletContext(),
                    maintenanceId,
                    recipientEmail,
                    ccEmail,
                    "",
                    subject,
                    body
            );

        } catch (Exception e) {
            e.printStackTrace();
        }
    }

    private boolean isMaintenanceManager(String role) {
        return "SUPER_ADMIN".equalsIgnoreCase(safe(role, ""))
                || "ADMIN".equalsIgnoreCase(safe(role, ""))
                || "ASSET_MANAGER".equalsIgnoreCase(safe(role, ""));
    }

    private String normalizeMaintenanceType(String maintenanceType) {

        String cleanType = safe(maintenanceType, "").toUpperCase();

        if ("PREVENTIVE".equals(cleanType)) {
            return "PREVENTIVE";
        }

        if ("CORRECTIVE".equals(cleanType)) {
            return "CORRECTIVE";
        }

        if ("REPAIR".equals(cleanType)) {
            return "REPAIR";
        }

        if ("INSPECTION".equals(cleanType)) {
            return "INSPECTION";
        }

        return "";
    }

    private String normalizeAssetStatusAfterMaintenance(String status) {

        String cleanStatus = safe(status, "UNDER_MAINTENANCE").toUpperCase();

        if ("AVAILABLE".equals(cleanStatus)) {
            return "AVAILABLE";
        }

        if ("UNDER_MAINTENANCE".equals(cleanStatus)) {
            return "UNDER_MAINTENANCE";
        }

        return "UNDER_MAINTENANCE";
    }

    private String formatServiceOutcome(String status) {

        String cleanStatus = safe(status, "UNDER_MAINTENANCE").toUpperCase();

        if ("AVAILABLE".equals(cleanStatus)) {
            return "Mark as Available";
        }

        if ("UNDER_MAINTENANCE".equals(cleanStatus)) {
            return "Keep Under Maintenance";
        }

        return formatDisplayText(cleanStatus);
    }

    private String getServiceOutcomeInstruction(String assetStatusAfterMaintenance) {

        String cleanStatus = safe(assetStatusAfterMaintenance, "UNDER_MAINTENANCE").toUpperCase();

        if ("AVAILABLE".equals(cleanStatus)) {
            return "The asset has been marked available after service verification. Asset Manager may review and reassign it as per operational requirement.";
        }

        if ("UNDER_MAINTENANCE".equals(cleanStatus)) {
            return "The asset will remain under maintenance. It should not be allocated until service completion and verification.";
        }

        return "Please review the updated asset status in IR-AMS before taking any allocation decision.";
    }

    private String getMaintenanceTypeMessage(
            String maintenanceType,
            String assetStatusAfterMaintenance
    ) {
        String cleanType = safe(maintenanceType, "").toUpperCase();
        String cleanStatus = safe(assetStatusAfterMaintenance, "UNDER_MAINTENANCE").toUpperCase();

        if ("PREVENTIVE".equals(cleanType)) {
            if ("AVAILABLE".equals(cleanStatus)) {
                return "Preventive maintenance has been recorded for asset health check and operational readiness.";
            }

            return "Preventive maintenance found an issue. Asset has been kept under maintenance for further inspection.";
        }

        if ("CORRECTIVE".equals(cleanType)) {
            if ("AVAILABLE".equals(cleanStatus)) {
                return "Corrective maintenance has been completed and the asset has been marked available.";
            }

            return "Corrective maintenance has been recorded. Asset requires further service or verification.";
        }

        if ("REPAIR".equals(cleanType)) {
            if ("AVAILABLE".equals(cleanStatus)) {
                return "Repair work has been completed and verified. The asset is ready for further operational use.";
            }

            return "Repair work has been recorded. The asset remains under maintenance until service completion.";
        }

        if ("INSPECTION".equals(cleanType)) {
            if ("AVAILABLE".equals(cleanStatus)) {
                return "Inspection has been completed and verified. The asset is ready for further operational use.";
            }

            return "Inspection has been recorded. Asset remains under maintenance for further action.";
        }

        return "Please log in to IR-AMS for further details regarding this maintenance record.";
    }

    private String formatDisplayText(String value) {

        String cleanValue = safe(value, "N/A");

        if ("N/A".equalsIgnoreCase(cleanValue)) {
            return "N/A";
        }

        cleanValue = cleanValue.replace("_", " ").toLowerCase();

        String[] words = cleanValue.split(" ");
        StringBuilder result = new StringBuilder();

        for (String word : words) {
            if (word == null || word.trim().isEmpty()) {
                continue;
            }

            if (result.length() > 0) {
                result.append(" ");
            }

            result.append(word.substring(0, 1).toUpperCase())
                    .append(word.substring(1));
        }

        return result.toString();
    }

    private String formatCost(String cost) {

        try {
            double amount = Double.parseDouble(safe(cost, "0"));
            return String.format("%.2f", amount);
        } catch (Exception e) {
            return safe(cost, "0.00");
        }
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
            return Integer.parseInt(safe(value, String.valueOf(fallback)));
        } catch (Exception e) {
            return fallback;
        }
    }

    private double parseDouble(String value, double fallback) {
        try {
            return Double.parseDouble(safe(value, String.valueOf(fallback)));
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
