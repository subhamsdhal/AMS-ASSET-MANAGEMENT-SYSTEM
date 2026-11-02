package com.mycompany.asset_management_system_ams;

import java.io.IOException;
import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.time.LocalDate;
import java.util.ArrayList;
import java.util.List;

import jakarta.servlet.ServletException;
import jakarta.servlet.annotation.WebServlet;
import jakarta.servlet.http.HttpServlet;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import jakarta.servlet.http.HttpSession;

@WebServlet(name = "UpdateMaintenanceServlet", urlPatterns = {"/UpdateMaintenanceServlet"})
public class UpdateMaintenanceServlet extends HttpServlet {

    @Override
    protected void doPost(HttpServletRequest request, HttpServletResponse response)
            throws ServletException, IOException {

        int maintenanceId = 0;

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

            if (!("SUPER_ADMIN".equals(role) || "ADMIN".equals(role)) && !"ASSET_MANAGER".equalsIgnoreCase(role)) {
                response.sendRedirect("maintenance.jsp?access=denied");
                return;
            }

            maintenanceId = parseInt(request.getParameter("maintenanceId"), 0);
            int assetId = parseInt(request.getParameter("assetId"), 0);
            int vendorId = parseInt(request.getParameter("vendorId"), 0);
            int performedByEmployeeId = parseInt(request.getParameter("performedByEmployeeId"), 0);

            String maintenanceDate = clean(request.getParameter("maintenanceDate"));
            String maintenanceType = normalizeMaintenanceType(request.getParameter("maintenanceType"));
            String maintenanceStatus = normalizeMaintenanceStatus(request.getParameter("maintenanceStatus"));
            String nextDueDate = clean(request.getParameter("nextDueDate"));
            String issueReported = clean(request.getParameter("issueReported"));
            String workDone = clean(request.getParameter("workDone"));
            String description = clean(request.getParameter("description"));
            String performedBy = clean(request.getParameter("performedBy"));
            String remarks = clean(request.getParameter("remarks"));
            String assetStatusAfterMaintenance = normalizeAssetStatus(request.getParameter("assetStatusAfterMaintenance"));

            double cost = parseDouble(request.getParameter("cost"), -1);

            if (maintenanceId <= 0 || assetId <= 0
                    || maintenanceDate.isEmpty()
                    || maintenanceType.isEmpty()
                    || performedBy.isEmpty()
                    || cost < 0) {
                response.sendRedirect("edit_maintenance.jsp?id=" + maintenanceId + "&error=failed");
                return;
            }

            LocalDate maintenanceLocalDate;

            try {
                maintenanceLocalDate = LocalDate.parse(maintenanceDate);
            } catch (Exception e) {
                response.sendRedirect("edit_maintenance.jsp?id=" + maintenanceId + "&error=invaliddate");
                return;
            }

            if (maintenanceLocalDate.isAfter(LocalDate.now())) {
                response.sendRedirect("edit_maintenance.jsp?id=" + maintenanceId + "&error=invaliddate");
                return;
            }

            if (!nextDueDate.isEmpty()) {
                try {
                    LocalDate nextDueLocalDate = LocalDate.parse(nextDueDate);

                    if (nextDueLocalDate.isBefore(maintenanceLocalDate)) {
                        response.sendRedirect("edit_maintenance.jsp?id=" + maintenanceId + "&error=invaliddate");
                        return;
                    }
                } catch (Exception e) {
                    response.sendRedirect("edit_maintenance.jsp?id=" + maintenanceId + "&error=invaliddate");
                    return;
                }
            }

            String oldStatus = "";
            try (Connection con = DBConnection.getConnection();
                 PreparedStatement ps = con.prepareStatement("SELECT maintenance_status FROM maintenance_logs WHERE maintenance_id = ?")) {
                ps.setInt(1, maintenanceId);
                try (ResultSet rs = ps.executeQuery()) {
                    if (rs.next()) {
                        oldStatus = rs.getString("maintenance_status");
                    }
                }
            } catch (Exception ignored) {}

            boolean updated = updateMaintenanceRecord(
                    maintenanceId,
                    assetId,
                    vendorId,
                    performedByEmployeeId,
                    maintenanceDate,
                    maintenanceType,
                    maintenanceStatus,
                    nextDueDate,
                    issueReported,
                    workDone,
                    description,
                    performedBy,
                    remarks,
                    cost,
                    assetStatusAfterMaintenance,
                    userId
            );

            if (updated) {
                QrSnapshotService.syncAssetQuietly(assetId);

                AuditDAO.log(
                        userId,
                        "UPDATE",
                        "maintenance_logs",
                        maintenanceId,
                        "Maintenance record updated. Maintenance ID: " + maintenanceId
                        + ", Asset ID: " + assetId
                        + ", Updated by: " + username
                );

                if (("COMPLETED".equalsIgnoreCase(maintenanceStatus) || "RESOLVED".equalsIgnoreCase(maintenanceStatus)) 
                        && !maintenanceStatus.equalsIgnoreCase(oldStatus)) {
                    try {
                        String detailsTable = "<tr><th>Maintenance ID:</th><td>" + maintenanceId + "</td></tr>"
                                + "<tr><th>Asset ID:</th><td>" + assetId + "</td></tr>"
                                + "<tr><th>Status:</th><td>" + maintenanceStatus + "</td></tr>"
                                // Fault (Medium, fixed): workDone is free text, embedded unescaped -
                                // same class as AddMaintenanceServlet's description/performedBy fix.
                                // See audit/10-maintenance.md Finding 1.
                                + "<tr><th>Work Done:</th><td>" + HtmlEscapeUtil.escape(workDone) + "</td></tr>";
                                
                        String body = NotificationHelper.buildHtmlEmail(
                                "Asset Manager",
                                "Maintenance Resolved",
                                detailsTable,
                                "The maintenance request has been successfully completed and resolved."
                        );
                        
                        NotificationEventService.EmailRouting routing = NotificationEventService.buildMaintenanceRecipients("COMPLETED", assetId);
                        String toEmail = routing.getToEmail();
                        String ccEmail = routing.getCcEmail();
                        
                        NotificationHelper.sendMaintenanceAlert(
                                getServletContext(),
                                maintenanceId,
                                toEmail,
                                ccEmail,
                                "",
                                "IR-AMS Maintenance Resolved",
                                body
                        );
                    } catch (Exception notifyEx) {
                        notifyEx.printStackTrace();
                    }
                }

                response.sendRedirect("maintenance.jsp?msg=updated");
            } else {
                AuditDAO.log(
                        userId,
                        "UPDATE_FAILED",
                        "maintenance_logs",
                        maintenanceId,
                        "Maintenance update failed. Maintenance ID: " + maintenanceId
                        + ", Asset ID: " + assetId
                        + ", Updated by: " + username
                );
                response.sendRedirect("edit_maintenance.jsp?id=" + maintenanceId + "&error=failed");
            }

        } catch (Exception e) {
            e.printStackTrace();

            if (maintenanceId > 0) {
                response.sendRedirect("edit_maintenance.jsp?id=" + maintenanceId + "&error=server");
            } else {
                response.sendRedirect("maintenance.jsp?error=server");
            }
        }
    }

    private boolean updateMaintenanceRecord(
            int maintenanceId,
            int assetId,
            int vendorId,
            int performedByEmployeeId,
            String maintenanceDate,
            String maintenanceType,
            String maintenanceStatus,
            String nextDueDate,
            String issueReported,
            String workDone,
            String description,
            String performedBy,
            String remarks,
            double cost,
            String assetStatusAfterMaintenance,
            int approvedBy
    ) {

        boolean updated = false;

        Connection con = null;
        PreparedStatement checkMaintenancePs = null;
        PreparedStatement checkAssetPs = null;
        PreparedStatement updateMaintenancePs = null;
        PreparedStatement updateAssetPs = null;
        ResultSet maintenanceRs = null;
        ResultSet assetRs = null;

        try {
            con = DBConnection.getConnection();
            con.setAutoCommit(false);

            String checkMaintenanceSql = "SELECT maintenance_id "
                    + "FROM maintenance_logs "
                    + "WHERE maintenance_id = ? "
                    + "FOR UPDATE";

            checkMaintenancePs = con.prepareStatement(checkMaintenanceSql);
            checkMaintenancePs.setInt(1, maintenanceId);
            maintenanceRs = checkMaintenancePs.executeQuery();

            if (!maintenanceRs.next()) {
                con.rollback();
                return false;
            }

            String checkAssetSql = "SELECT asset_status "
                    + "FROM assets "
                    + "WHERE asset_id = ? "
                    + "FOR UPDATE";

            checkAssetPs = con.prepareStatement(checkAssetSql);
            checkAssetPs.setInt(1, assetId);
            assetRs = checkAssetPs.executeQuery();

            if (!assetRs.next()) {
                con.rollback();
                return false;
            }

            String currentAssetStatus = assetRs.getString("asset_status");

            if ("DISPOSED".equalsIgnoreCase(currentAssetStatus)) {
                con.rollback();
                return false;
            }

            boolean hasMaintenanceStatus = columnExists(con, "maintenance_logs", "maintenance_status");
            boolean hasNextDueDate = columnExists(con, "maintenance_logs", "next_due_date");
            boolean hasIssueReported = columnExists(con, "maintenance_logs", "issue_reported");
            boolean hasWorkDone = columnExists(con, "maintenance_logs", "work_done");
            boolean hasDescription = columnExists(con, "maintenance_logs", "description");
            boolean hasPerformedBy = columnExists(con, "maintenance_logs", "performed_by");
            boolean hasVendorId = columnExists(con, "maintenance_logs", "vendor_id");
            boolean hasPerformedByEmployeeId = columnExists(con, "maintenance_logs", "performed_by_employee_id");
            boolean hasRemarks = columnExists(con, "maintenance_logs", "remarks");
            boolean hasApprovedBy = columnExists(con, "maintenance_logs", "approved_by");
            boolean hasUpdatedAt = columnExists(con, "maintenance_logs", "updated_at");

            List<Object> values = new ArrayList<>();
            StringBuilder sql = new StringBuilder();

            sql.append("UPDATE maintenance_logs SET ");
            sql.append("asset_id = ?, maintenance_date = ?, maintenance_type = ?, cost = ?");

            values.add(assetId);
            values.add(maintenanceDate);
            values.add(maintenanceType);
            values.add(cost);

            if (hasMaintenanceStatus) {
                sql.append(", maintenance_status = ?");
                values.add(maintenanceStatus);
            }

            if (hasNextDueDate) {
                sql.append(", next_due_date = ?");
                values.add(nextDueDate.isEmpty() ? null : nextDueDate);
            }

            if (hasIssueReported) {
                sql.append(", issue_reported = ?");
                values.add(issueReported);
            }

            if (hasWorkDone) {
                sql.append(", work_done = ?");
                values.add(workDone);
            }

            if (hasDescription) {
                sql.append(", description = ?");
                values.add(description.isEmpty() ? issueReported : description);
            }

            if (hasPerformedBy) {
                sql.append(", performed_by = ?");
                values.add(performedBy);
            }

            if (hasVendorId) {
                sql.append(", vendor_id = ?");
                values.add(vendorId <= 0 ? null : vendorId);
            }

            if (hasPerformedByEmployeeId) {
                sql.append(", performed_by_employee_id = ?");
                values.add(performedByEmployeeId <= 0 ? null : performedByEmployeeId);
            }

            if (hasRemarks) {
                sql.append(", remarks = ?");
                values.add(remarks);
            }

            if (hasApprovedBy) {
                sql.append(", approved_by = ?");
                values.add(approvedBy);
            }

            if (hasUpdatedAt) {
                sql.append(", updated_at = CURRENT_TIMESTAMP");
            }

            sql.append(" WHERE maintenance_id = ?");
            values.add(maintenanceId);

            updateMaintenancePs = con.prepareStatement(sql.toString());

            for (int i = 0; i < values.size(); i++) {
                Object value = values.get(i);

                if (value == null) {
                    updateMaintenancePs.setObject(i + 1, null);
                } else if (value instanceof Integer) {
                    updateMaintenancePs.setInt(i + 1, (Integer) value);
                } else if (value instanceof Double) {
                    updateMaintenancePs.setDouble(i + 1, (Double) value);
                } else {
                    updateMaintenancePs.setString(i + 1, String.valueOf(value));
                }
            }

            int maintenanceRows = updateMaintenancePs.executeUpdate();

            if (maintenanceRows <= 0) {
                con.rollback();
                return false;
            }

            String resolvedAssetStatus = resolveAssetStatusAfterMaintenance(con, assetId, assetStatusAfterMaintenance);

            String updateAssetSql = "UPDATE assets "
                    + "SET asset_status = ?, condition_status = ?, service_status = ? "
                    + "WHERE asset_id = ? "
                    + "AND asset_status <> 'DISPOSED'";

            updateAssetPs = con.prepareStatement(updateAssetSql);
            updateAssetPs.setString(1, resolvedAssetStatus);
            updateAssetPs.setString(2, conditionStatusForAssetStatus(resolvedAssetStatus));
            updateAssetPs.setString(3, serviceStatusForAssetStatus(resolvedAssetStatus));
            updateAssetPs.setInt(4, assetId);

            int assetRows = updateAssetPs.executeUpdate();

            if (assetRows <= 0) {
                con.rollback();
                return false;
            }

            con.commit();
            updated = true;

        } catch (Exception e) {
            e.printStackTrace();

            try {
                if (con != null) {
                    con.rollback();
                }
            } catch (Exception ex) {
                ex.printStackTrace();
            }

            updated = false;

        } finally {
            closeResultSet(assetRs);
            closeResultSet(maintenanceRs);

            closeStatement(updateAssetPs);
            closeStatement(updateMaintenancePs);
            closeStatement(checkAssetPs);
            closeStatement(checkMaintenancePs);

            try {
                if (con != null) {
                    con.setAutoCommit(true);
                }
            } catch (Exception e) {
                e.printStackTrace();
            }

            closeConnection(con);
        }

        return updated;
    }

    private boolean columnExists(Connection con, String tableName, String columnName) {

        String sql = "SELECT COUNT(*) FROM information_schema.columns "
                + "WHERE table_schema = DATABASE() "
                + "AND table_name = ? "
                + "AND column_name = ?";

        try (PreparedStatement ps = con.prepareStatement(sql)) {
            ps.setString(1, tableName);
            ps.setString(2, columnName);

            try (ResultSet rs = ps.executeQuery()) {
                return rs.next() && rs.getInt(1) > 0;
            }

        } catch (Exception e) {
            e.printStackTrace();
        }

        return false;
    }

    private String normalizeMaintenanceType(String maintenanceType) {
        String value = clean(maintenanceType).toUpperCase();

        if ("PREVENTIVE".equals(value)) {
            return "PREVENTIVE";
        }

        if ("CORRECTIVE".equals(value)) {
            return "CORRECTIVE";
        }

        if ("REPAIR".equals(value)) {
            return "REPAIR";
        }

        if ("INSPECTION".equals(value)) {
            return "INSPECTION";
        }

        return "";
    }

    private String normalizeMaintenanceStatus(String status) {
        String value = clean(status).toUpperCase();

        if ("OPEN".equals(value)) {
            return "OPEN";
        }

        if ("IN_PROGRESS".equals(value)) {
            return "IN_PROGRESS";
        }

        if ("COMPLETED".equals(value)) {
            return "COMPLETED";
        }

        if ("CANCELLED".equals(value)) {
            return "CANCELLED";
        }

        return "IN_PROGRESS";
    }

    private String normalizeAssetStatus(String status) {
        String value = clean(status).toUpperCase();

        if ("AVAILABLE".equals(value)) {
            return "AVAILABLE";
        }

        return "UNDER_MAINTENANCE";
    }

    private String resolveAssetStatusAfterMaintenance(Connection con, int assetId, String requestedStatus) throws Exception {
        String cleanStatus = normalizeAssetStatus(requestedStatus);

        if (!"AVAILABLE".equals(cleanStatus)) {
            return "UNDER_MAINTENANCE";
        }

        String sql = "SELECT COUNT(*) "
                + "FROM asset_allocation "
                + "WHERE asset_id = ? "
                + "AND allocation_status = 'ALLOCATED'";

        try (PreparedStatement ps = con.prepareStatement(sql)) {
            ps.setInt(1, assetId);

            try (ResultSet rs = ps.executeQuery()) {
                if (rs.next() && rs.getInt(1) > 0) {
                    return "ALLOCATED";
                }
            }
        }

        return "AVAILABLE";
    }

    private String conditionStatusForAssetStatus(String assetStatus) {
        if ("UNDER_MAINTENANCE".equalsIgnoreCase(assetStatus)) {
            return "NEEDS_REPAIR";
        }

        return "GOOD";
    }

    private String serviceStatusForAssetStatus(String assetStatus) {
        if ("UNDER_MAINTENANCE".equalsIgnoreCase(assetStatus)) {
            return "UNDER_REPAIR";
        }

        return "SERVICEABLE";
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

    private double parseDouble(String value, double fallback) {
        try {
            if (value == null || value.trim().isEmpty()) {
                return fallback;
            }

            return Double.parseDouble(value.trim());

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

    private void closeResultSet(ResultSet rs) {
        try {
            if (rs != null) {
                rs.close();
            }
        } catch (Exception e) {
            e.printStackTrace();
        }
    }

    private void closeStatement(PreparedStatement ps) {
        try {
            if (ps != null) {
                ps.close();
            }
        } catch (Exception e) {
            e.printStackTrace();
        }
    }

    private void closeConnection(Connection con) {
        try {
            if (con != null) {
                con.close();
            }
        } catch (Exception e) {
            e.printStackTrace();
        }
    }
}
