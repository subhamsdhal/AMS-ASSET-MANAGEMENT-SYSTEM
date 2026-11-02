package com.mycompany.asset_management_system_ams;

import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.Statement;
import java.util.ArrayList;
import java.util.List;

public class MaintenanceLogDAO {

    public List<MaintenanceLog> getAllMaintenanceLogs() {

        List<MaintenanceLog> maintenanceList = new ArrayList<>();

        try (Connection con = DBConnection.getConnection()) {

            boolean hasDescription = columnExists(con, "maintenance_logs", "description");
            boolean hasIssueReported = columnExists(con, "maintenance_logs", "issue_reported");
            boolean hasWorkDone = columnExists(con, "maintenance_logs", "work_done");
            boolean hasPerformedBy = columnExists(con, "maintenance_logs", "performed_by");

            String descriptionExpression;

            if (hasDescription) {
                descriptionExpression = "COALESCE(ml.description, '')";
            } else if (hasIssueReported) {
                descriptionExpression = "COALESCE(ml.issue_reported, '')";
            } else if (hasWorkDone) {
                descriptionExpression = "COALESCE(ml.work_done, '')";
            } else {
                descriptionExpression = "''";
            }

            String performedByExpression = hasPerformedBy
                    ? "COALESCE(ml.performed_by, '')"
                    : "''";

            String sql = "SELECT ml.maintenance_id, "
                    + "ml.asset_id, "
                    + "a.asset_code, a.asset_name, a.asset_status, "
                    + "COALESCE(ac.category_name, 'Uncategorized') AS category_name, "
                    + "ml.maintenance_date, "
                    + "ml.maintenance_type, "
                    + descriptionExpression + " AS description, "
                    + "COALESCE(ml.cost, 0) AS cost, "
                    + performedByExpression + " AS performed_by "
                    + "FROM maintenance_logs ml "
                    + "LEFT JOIN assets a ON ml.asset_id = a.asset_id "
                    + "LEFT JOIN asset_categories ac ON a.category_id = ac.category_id "
                    + "ORDER BY ml.maintenance_id DESC";

            try (
                    PreparedStatement ps = con.prepareStatement(sql);
                    ResultSet rs = ps.executeQuery()
            ) {

                while (rs.next()) {

                    MaintenanceLog log = new MaintenanceLog();

                    log.setMaintenanceId(rs.getInt("maintenance_id"));
                    log.setAssetId(rs.getInt("asset_id"));
                    log.setAssetCode(rs.getString("asset_code"));
                    log.setAssetName(rs.getString("asset_name"));
                    log.setAssetStatus(rs.getString("asset_status"));
                    log.setCategoryName(rs.getString("category_name"));
                    log.setMaintenanceDate(rs.getString("maintenance_date"));
                    log.setMaintenanceType(rs.getString("maintenance_type"));
                    log.setDescription(rs.getString("description"));
                    log.setCost(rs.getDouble("cost"));
                    log.setPerformedBy(rs.getString("performed_by"));

                    maintenanceList.add(log);
                }
            }

        } catch (Exception e) {
            System.err.println("[MaintenanceLogDAO] getAllMaintenanceLogs failed: " + e.getMessage());
            e.printStackTrace();
        }

        return maintenanceList;
    }

    public boolean addMaintenanceLog(int assetId, String maintenanceDate,
            String maintenanceType, String description,
            double cost, String performedBy, String assetStatusAfterMaintenance) {

        return addMaintenanceLogAndReturnId(
                assetId,
                maintenanceDate,
                maintenanceType,
                description,
                cost,
                performedBy,
                assetStatusAfterMaintenance
        ) > 0;
    }

    public int addMaintenanceLogAndReturnId(int assetId, String maintenanceDate,
            String maintenanceType, String description,
            double cost, String performedBy, String assetStatusAfterMaintenance) {

        int maintenanceId = 0;

        Connection con = null;
        PreparedStatement checkAssetPs = null;
        PreparedStatement insertPs = null;
        PreparedStatement updateAssetPs = null;
        ResultSet assetRs = null;
        ResultSet generatedKeys = null;

        try {
            con = DBConnection.getConnection();
            con.setAutoCommit(false);

            String currentAssetStatus = "";

            String checkAssetSql = "SELECT asset_status "
                    + "FROM assets "
                    + "WHERE asset_id = ? "
                    + "FOR UPDATE";

            checkAssetPs = con.prepareStatement(checkAssetSql);
            checkAssetPs.setInt(1, assetId);
            assetRs = checkAssetPs.executeQuery();

            if (assetRs.next()) {
                currentAssetStatus = assetRs.getString("asset_status");
            } else {
                con.rollback();
                return 0;
            }

            if ("DISPOSED".equalsIgnoreCase(currentAssetStatus)) {
                con.rollback();
                return 0;
            }

            String cleanMaintenanceType = normalizeMaintenanceType(maintenanceType);
            String cleanAssetStatus = normalizeAssetStatus(assetStatusAfterMaintenance);

            if (cleanMaintenanceType.isEmpty()) {
                con.rollback();
                return 0;
            }

            boolean hasMaintenanceStatus = columnExists(con, "maintenance_logs", "maintenance_status");
            boolean hasNextDueDate = columnExists(con, "maintenance_logs", "next_due_date");
            boolean hasIssueReported = columnExists(con, "maintenance_logs", "issue_reported");
            boolean hasWorkDone = columnExists(con, "maintenance_logs", "work_done");
            boolean hasDescription = columnExists(con, "maintenance_logs", "description");
            boolean hasCost = columnExists(con, "maintenance_logs", "cost");
            boolean hasPerformedBy = columnExists(con, "maintenance_logs", "performed_by");
            boolean hasRemarks = columnExists(con, "maintenance_logs", "remarks");
            boolean hasCreatedAt = columnExists(con, "maintenance_logs", "created_at");
            boolean hasUpdatedAt = columnExists(con, "maintenance_logs", "updated_at");

            List<String> columns = new ArrayList<>();
            List<Object> values = new ArrayList<>();

            columns.add("asset_id");
            values.add(assetId);

            columns.add("maintenance_date");
            values.add(clean(maintenanceDate));

            columns.add("maintenance_type");
            values.add(cleanMaintenanceType);

            if (hasMaintenanceStatus) {
                columns.add("maintenance_status");

                if ("AVAILABLE".equalsIgnoreCase(cleanAssetStatus)) {
                    values.add("COMPLETED");
                } else {
                    values.add("IN_PROGRESS");
                }
            }

            if (hasNextDueDate) {
                columns.add("next_due_date");
                values.add(null);
            }

            if (hasIssueReported) {
                columns.add("issue_reported");
                values.add(clean(description));
            }

            if (hasWorkDone) {
                columns.add("work_done");

                if ("AVAILABLE".equalsIgnoreCase(cleanAssetStatus)) {
                    values.add(clean(description));
                } else {
                    values.add("");
                }
            }

            if (hasDescription) {
                columns.add("description");
                values.add(clean(description));
            }

            if (hasCost) {
                columns.add("cost");
                values.add(cost);
            }

            if (hasPerformedBy) {
                columns.add("performed_by");
                values.add(clean(performedBy));
            }

            if (hasRemarks) {
                columns.add("remarks");

                if ("AVAILABLE".equalsIgnoreCase(cleanAssetStatus)) {
                    values.add("Maintenance logged and asset marked available.");
                } else {
                    values.add("Maintenance logged and asset kept under maintenance.");
                }
            }

            if (hasCreatedAt) {
                columns.add("created_at");
                values.add("CURRENT_TIMESTAMP_SPECIAL");
            }

            if (hasUpdatedAt) {
                columns.add("updated_at");
                values.add("CURRENT_TIMESTAMP_SPECIAL");
            }

            StringBuilder insertSql = new StringBuilder();
            insertSql.append("INSERT INTO maintenance_logs (");

            for (int i = 0; i < columns.size(); i++) {
                if (i > 0) {
                    insertSql.append(", ");
                }

                insertSql.append(columns.get(i));
            }

            insertSql.append(") VALUES (");

            for (int i = 0; i < values.size(); i++) {
                if (i > 0) {
                    insertSql.append(", ");
                }

                Object value = values.get(i);

                if ("CURRENT_TIMESTAMP_SPECIAL".equals(value)) {
                    insertSql.append("CURRENT_TIMESTAMP");
                } else {
                    insertSql.append("?");
                }
            }

            insertSql.append(")");

            insertPs = con.prepareStatement(insertSql.toString(), Statement.RETURN_GENERATED_KEYS);

            int parameterIndex = 1;

            for (Object value : values) {

                if ("CURRENT_TIMESTAMP_SPECIAL".equals(value)) {
                    continue;
                }

                if (value == null) {
                    insertPs.setObject(parameterIndex, null);
                } else if (value instanceof Integer) {
                    insertPs.setInt(parameterIndex, (Integer) value);
                } else if (value instanceof Double) {
                    insertPs.setDouble(parameterIndex, (Double) value);
                } else {
                    insertPs.setString(parameterIndex, String.valueOf(value));
                }

                parameterIndex++;
            }

            int rows = insertPs.executeUpdate();

            if (rows <= 0) {
                con.rollback();
                return 0;
            }

            generatedKeys = insertPs.getGeneratedKeys();

            if (generatedKeys.next()) {
                maintenanceId = generatedKeys.getInt(1);
            }

            if (maintenanceId <= 0) {
                con.rollback();
                return 0;
            }

            String resolvedAssetStatus = resolveAssetStatusAfterMaintenance(con, assetId, cleanAssetStatus);

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
                return 0;
            }

            con.commit();

        } catch (Exception e) {
            System.err.println("[MaintenanceLogDAO] addMaintenanceLogAndReturnId failed: " + e.getMessage());

            try {
                if (con != null) {
                    con.rollback();
                }
            } catch (Exception ex) {
                ex.printStackTrace();
            }

            maintenanceId = 0;
            e.printStackTrace();

        } finally {
            closeResultSet(generatedKeys);
            closeResultSet(assetRs);

            closeStatement(updateAssetPs);
            closeStatement(insertPs);
            closeStatement(checkAssetPs);

            try {
                if (con != null) {
                    con.setAutoCommit(true);
                }
            } catch (Exception e) {
                System.err.println("[MaintenanceLogDAO] addMaintenanceLogAndReturnId failed: " + e.getMessage());
                e.printStackTrace();
            }

            closeConnection(con);
        }

        return maintenanceId;
    }

    public String[] getMaintenanceNotificationDetails(int maintenanceId) {

        String[] details = null;

        try (Connection con = DBConnection.getConnection()) {

            boolean hasDescription = columnExists(con, "maintenance_logs", "description");
            boolean hasIssueReported = columnExists(con, "maintenance_logs", "issue_reported");
            boolean hasWorkDone = columnExists(con, "maintenance_logs", "work_done");
            boolean hasPerformedBy = columnExists(con, "maintenance_logs", "performed_by");

            String descriptionExpression;

            if (hasDescription) {
                descriptionExpression = "COALESCE(ml.description, '')";
            } else if (hasIssueReported) {
                descriptionExpression = "COALESCE(ml.issue_reported, '')";
            } else if (hasWorkDone) {
                descriptionExpression = "COALESCE(ml.work_done, '')";
            } else {
                descriptionExpression = "''";
            }

            String performedByExpression = hasPerformedBy
                    ? "COALESCE(ml.performed_by, '')"
                    : "''";

            String sql = "SELECT ml.maintenance_id, "
                    + "a.asset_code, a.asset_name, a.serial_number, a.location, a.asset_status, "
                    + "COALESCE(ac.category_name, 'Uncategorized') AS category_name, "
                    + "ml.maintenance_date, ml.maintenance_type, "
                    + descriptionExpression + " AS description, "
                    + "COALESCE(ml.cost, 0) AS cost, "
                    + performedByExpression + " AS performed_by, "
                    + "e.email AS employee_email, "
                    + "e.employee_name AS employee_name, "
                    + "e.employee_code, "
                    + "d.department_name "
                    + "FROM maintenance_logs ml "
                    + "LEFT JOIN assets a ON ml.asset_id = a.asset_id "
                    + "LEFT JOIN asset_categories ac ON a.category_id = ac.category_id "
                    + "LEFT JOIN asset_allocation aa ON aa.asset_id = a.asset_id "
                    + "AND aa.allocation_status = 'ALLOCATED' "
                    + "LEFT JOIN employees e ON aa.employee_id = e.employee_id "
                    + "LEFT JOIN departments d ON e.department_id = d.department_id "
                    + "WHERE ml.maintenance_id = ? "
                    + "ORDER BY aa.allocation_id DESC "
                    + "LIMIT 1";

            try (PreparedStatement ps = con.prepareStatement(sql)) {

                ps.setInt(1, maintenanceId);

                try (ResultSet rs = ps.executeQuery()) {

                    if (rs.next()) {
                        details = new String[16];

                        details[0] = rs.getString("asset_code");
                        details[1] = rs.getString("asset_name");
                        details[2] = rs.getString("category_name");
                        details[3] = rs.getString("serial_number");
                        details[4] = rs.getString("location");
                        details[5] = rs.getString("asset_status");
                        details[6] = rs.getString("maintenance_date");
                        details[7] = rs.getString("maintenance_type");
                        details[8] = rs.getString("description");
                        details[9] = String.valueOf(rs.getDouble("cost"));
                        details[10] = rs.getString("performed_by");
                        details[11] = String.valueOf(rs.getInt("maintenance_id"));
                        details[12] = rs.getString("employee_email");
                        details[13] = rs.getString("employee_name");
                        details[14] = rs.getString("employee_code");
                        details[15] = rs.getString("department_name");
                    }
                }
            }

        } catch (Exception e) {
            System.err.println("[MaintenanceLogDAO] addMaintenanceLogAndReturnId failed: " + e.getMessage());
            e.printStackTrace();
        }

        return details;
    }

    public MaintenanceLog getMaintenanceById(int maintenanceId) {

        MaintenanceLog log = null;

        try (Connection con = DBConnection.getConnection()) {

            boolean hasDescription = columnExists(con, "maintenance_logs", "description");
            boolean hasIssueReported = columnExists(con, "maintenance_logs", "issue_reported");
            boolean hasWorkDone = columnExists(con, "maintenance_logs", "work_done");
            boolean hasPerformedBy = columnExists(con, "maintenance_logs", "performed_by");

            String descriptionExpression;

            if (hasDescription) {
                descriptionExpression = "COALESCE(ml.description, '')";
            } else if (hasIssueReported) {
                descriptionExpression = "COALESCE(ml.issue_reported, '')";
            } else if (hasWorkDone) {
                descriptionExpression = "COALESCE(ml.work_done, '')";
            } else {
                descriptionExpression = "''";
            }

            String performedByExpression = hasPerformedBy
                    ? "COALESCE(ml.performed_by, '')"
                    : "''";

            String sql = "SELECT ml.maintenance_id, "
                    + "ml.asset_id, "
                    + "a.asset_code, a.asset_name, a.asset_status, "
                    + "COALESCE(ac.category_name, 'Uncategorized') AS category_name, "
                    + "ml.maintenance_date, "
                    + "ml.maintenance_type, "
                    + descriptionExpression + " AS description, "
                    + "COALESCE(ml.cost, 0) AS cost, "
                    + performedByExpression + " AS performed_by "
                    + "FROM maintenance_logs ml "
                    + "LEFT JOIN assets a ON ml.asset_id = a.asset_id "
                    + "LEFT JOIN asset_categories ac ON a.category_id = ac.category_id "
                    + "WHERE ml.maintenance_id = ?";

            try (PreparedStatement ps = con.prepareStatement(sql)) {

                ps.setInt(1, maintenanceId);

                try (ResultSet rs = ps.executeQuery()) {

                    if (rs.next()) {

                        log = new MaintenanceLog();

                        log.setMaintenanceId(rs.getInt("maintenance_id"));
                        log.setAssetId(rs.getInt("asset_id"));
                        log.setAssetCode(rs.getString("asset_code"));
                        log.setAssetName(rs.getString("asset_name"));
                        log.setAssetStatus(rs.getString("asset_status"));
                        log.setCategoryName(rs.getString("category_name"));
                        log.setMaintenanceDate(rs.getString("maintenance_date"));
                        log.setMaintenanceType(rs.getString("maintenance_type"));
                        log.setDescription(rs.getString("description"));
                        log.setCost(rs.getDouble("cost"));
                        log.setPerformedBy(rs.getString("performed_by"));
                    }
                }
            }

        } catch (Exception e) {
            System.err.println("[MaintenanceLogDAO] getMaintenanceById failed: " + e.getMessage());
            e.printStackTrace();
        }

        return log;
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
            System.err.println("[MaintenanceLogDAO] getMaintenanceById failed: " + e.getMessage());
            e.printStackTrace();
        }

        return false;
    }

    private String normalizeMaintenanceType(String maintenanceType) {

        if (maintenanceType == null || maintenanceType.trim().isEmpty()) {
            return "";
        }

        String type = maintenanceType.trim().toUpperCase();

        if ("PREVENTIVE".equals(type)) {
            return "PREVENTIVE";
        }

        if ("CORRECTIVE".equals(type)) {
            return "CORRECTIVE";
        }

        if ("REPAIR".equals(type)) {
            return "REPAIR";
        }

        if ("INSPECTION".equals(type)) {
            return "INSPECTION";
        }

        return "";
    }

    private String normalizeAssetStatus(String assetStatusAfterMaintenance) {

        if (assetStatusAfterMaintenance == null || assetStatusAfterMaintenance.trim().isEmpty()) {
            return "UNDER_MAINTENANCE";
        }

        String status = assetStatusAfterMaintenance.trim().toUpperCase();

        if ("AVAILABLE".equals(status)) {
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
            System.err.println("[MaintenanceLogDAO] getMaintenanceById failed: " + e.getMessage());
            e.printStackTrace();
        }
    }

    private void closeStatement(PreparedStatement ps) {
        try {
            if (ps != null) {
                ps.close();
            }
        } catch (Exception e) {
            System.err.println("[MaintenanceLogDAO] getMaintenanceById failed: " + e.getMessage());
            e.printStackTrace();
        }
    }

    private void closeConnection(Connection con) {
        try {
            if (con != null) {
                con.close();
            }
        } catch (Exception e) {
            System.err.println("[MaintenanceLogDAO] getMaintenanceById failed: " + e.getMessage());
            e.printStackTrace();
        }
    }
}
