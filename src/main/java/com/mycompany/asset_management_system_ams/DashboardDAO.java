package com.mycompany.asset_management_system_ams;

import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.util.List;
import java.util.logging.Level;
import java.util.logging.Logger;

public class DashboardDAO {

    private static final Logger LOGGER = Logger.getLogger(DashboardDAO.class.getName());

    private boolean queryError;

    public boolean hasQueryError() {
        return queryError;
    }

    public int getCount(String tableName, List<Integer> deptIds) {
        int count = 0;
        String sql;

        if ("employees".equalsIgnoreCase(tableName)) {
            sql = "SELECT COUNT(*) FROM employees";
        } else if ("assets".equalsIgnoreCase(tableName)
                || "asset_requests".equalsIgnoreCase(tableName)
                || "maintenance_logs".equalsIgnoreCase(tableName)
                || "asset_allocation".equalsIgnoreCase(tableName)
                || "asset_returns".equalsIgnoreCase(tableName)
                || "asset_categories".equalsIgnoreCase(tableName)
                || "vendors".equalsIgnoreCase(tableName)
                || "audit_logs".equalsIgnoreCase(tableName)) {
            sql = "SELECT COUNT(*) FROM " + tableName;
        } else {
            return 0;
        }
        
        if (deptIds != null && !deptIds.isEmpty() && ("assets".equalsIgnoreCase(tableName) || "asset_requests".equalsIgnoreCase(tableName) || "asset_allocation".equalsIgnoreCase(tableName) || "asset_returns".equalsIgnoreCase(tableName))) {
            StringBuilder placeholders = new StringBuilder();
            for (int i = 0; i < deptIds.size(); i++) {
                placeholders.append("?");
                if (i < deptIds.size() - 1) placeholders.append(",");
            }
            if ("assets".equalsIgnoreCase(tableName)) {
                sql += " WHERE department_id IN (" + placeholders + ")";
            } else if ("asset_requests".equalsIgnoreCase(tableName) || "asset_allocation".equalsIgnoreCase(tableName)) {
                sql += " WHERE employee_id IN (SELECT employee_id FROM employees WHERE department_id IN (" + placeholders + "))";
            } else if ("asset_returns".equalsIgnoreCase(tableName)) {
                sql += " WHERE employee_id IN (SELECT employee_id FROM employees WHERE department_id IN (" + placeholders + "))";
            }
        } else if (deptIds != null && deptIds.isEmpty() && ("assets".equalsIgnoreCase(tableName) || "asset_requests".equalsIgnoreCase(tableName) || "asset_allocation".equalsIgnoreCase(tableName) || "asset_returns".equalsIgnoreCase(tableName))) {
            if ("assets".equalsIgnoreCase(tableName)) {
                sql += " WHERE department_id = -1";
            } else {
                sql += " WHERE employee_id = -1";
            }
        }

        try (Connection con = DBConnection.getConnection()) {
            if (con == null) {
                queryError = true;
                LOGGER.warning("Dashboard count query skipped because the database connection is unavailable.");
                return 0;
            }

            try (PreparedStatement ps = con.prepareStatement(sql)) {
                int paramIndex = 1;
                if (deptIds != null && !deptIds.isEmpty() && ("assets".equalsIgnoreCase(tableName) || "asset_requests".equalsIgnoreCase(tableName) || "asset_allocation".equalsIgnoreCase(tableName) || "asset_returns".equalsIgnoreCase(tableName))) {
                    for (Integer id : deptIds) {
                        ps.setInt(paramIndex++, id);
                    }
                }
                try (ResultSet rs = ps.executeQuery()) {

                if (rs.next()) {
                    count = rs.getInt(1);
                }
                } // close ResultSet
            } // close PreparedStatement
        } catch (Exception e) {
            queryError = true;
            LOGGER.log(Level.WARNING, "Unable to load dashboard count for table: " + tableName, e);
        }

        return count;
    }

    public int getAssetStatusCount(String status, List<Integer> deptIds) {
        int count = 0;

        String sql = "SELECT COUNT(*) FROM assets WHERE UPPER(asset_status) = UPPER(?)";
        if ("UNDER_MAINTENANCE".equalsIgnoreCase(status)) {
            sql = "SELECT COUNT(*) FROM assets WHERE UPPER(asset_status) IN ('UNDER_MAINTENANCE', 'MAINTENANCE')";
        }
        
        if (deptIds != null && !deptIds.isEmpty()) {
            StringBuilder placeholders = new StringBuilder();
            for (int i = 0; i < deptIds.size(); i++) {
                placeholders.append("?");
                if (i < deptIds.size() - 1) placeholders.append(",");
            }
            sql += " AND department_id IN (" + placeholders + ")";
        } else if (deptIds != null && deptIds.isEmpty()) {
            sql += " AND department_id = -1";
        }

        try (Connection con = DBConnection.getConnection()) {
            if (con == null) {
                queryError = true;
                LOGGER.warning("Dashboard status query skipped because the database connection is unavailable.");
                return 0;
            }

            try (PreparedStatement ps = con.prepareStatement(sql)) {

                int paramIndex = 1;
                if (!"UNDER_MAINTENANCE".equalsIgnoreCase(status)) {
                    ps.setString(paramIndex++, status);
                }
                
                if (deptIds != null && !deptIds.isEmpty()) {
                    for (Integer id : deptIds) {
                        ps.setInt(paramIndex++, id);
                    }
                }

                try (ResultSet rs = ps.executeQuery()) {
                    if (rs.next()) {
                        count = rs.getInt(1);
                    }
                }
            }
        } catch (Exception e) {
            queryError = true;
            LOGGER.log(Level.WARNING, "Unable to load dashboard asset status count for: " + status, e);
        }

        return count;
    }

    public double getTotalAssetValue(List<Integer> deptIds) {
        double totalValue = 0.0;

        String sql = "SELECT COALESCE(SUM(purchase_cost), 0) FROM assets";
        if (deptIds != null && !deptIds.isEmpty()) {
            StringBuilder placeholders = new StringBuilder();
            for (int i = 0; i < deptIds.size(); i++) {
                placeholders.append("?");
                if (i < deptIds.size() - 1) placeholders.append(",");
            }
            sql += " WHERE department_id IN (" + placeholders + ")";
        } else if (deptIds != null && deptIds.isEmpty()) {
            sql += " WHERE department_id = -1";
        }

        try (Connection con = DBConnection.getConnection()) {
            if (con == null) {
                queryError = true;
                LOGGER.warning("Dashboard asset value query skipped because the database connection is unavailable.");
                return 0.0;
            }

            try (PreparedStatement ps = con.prepareStatement(sql)) {
                if (deptIds != null && !deptIds.isEmpty()) {
                    int paramIndex = 1;
                    for (Integer id : deptIds) {
                        ps.setInt(paramIndex++, id);
                    }
                }
                try (ResultSet rs = ps.executeQuery()) {

                if (rs.next()) {
                    totalValue = rs.getDouble(1);
                }
                } // close ResultSet
            } // close PreparedStatement
        } catch (Exception e) {
            queryError = true;
            LOGGER.log(Level.WARNING, "Unable to load dashboard asset value.", e);
        }

        return totalValue;
    }
}
