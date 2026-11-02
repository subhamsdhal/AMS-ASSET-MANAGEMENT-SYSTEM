package com.mycompany.asset_management_system_ams;

import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;

public final class QrSnapshotService {

    private QrSnapshotService() {
    }

    public static void syncAssetQuietly(int assetId) {
        try (Connection con = DBConnection.getConnection()) {
            syncAssetQuietly(con, assetId);
        } catch (Exception e) {
            System.err.println("QR Module DB Error: " + e.getMessage());
        }
    }

    public static void syncAssetQuietly(Connection con, int assetId) {
        try {
            if (con == null || assetId <= 0) {
                return;
            }

            ensureTables(con);

            SnapshotRow row = loadSnapshotRow(con, assetId);

            if (row == null || row.qrPublicToken.isEmpty()) {
                invalidateSnapshot(con, assetId, "");
                enqueue(con, assetId, "", "INVALIDATE", "PENDING", "");
                return;
            }

            String sql = "INSERT INTO public_asset_snapshot "
                    + "(asset_id, qr_public_token, asset_code, asset_name, category_name, asset_status, "
                    + "department_name, division_name, location_name, warranty_expiry, "
                    + "last_physical_verification_date, maintenance_indicator, token_active, last_synced_at) "
                    + "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 1, CURRENT_TIMESTAMP) "
                    + "ON DUPLICATE KEY UPDATE "
                    + "qr_public_token = VALUES(qr_public_token), "
                    + "asset_code = VALUES(asset_code), "
                    + "asset_name = VALUES(asset_name), "
                    + "category_name = VALUES(category_name), "
                    + "asset_status = VALUES(asset_status), "
                    + "department_name = VALUES(department_name), "
                    + "division_name = VALUES(division_name), "
                    + "location_name = VALUES(location_name), "
                    + "warranty_expiry = VALUES(warranty_expiry), "
                    + "last_physical_verification_date = VALUES(last_physical_verification_date), "
                    + "maintenance_indicator = VALUES(maintenance_indicator), "
                    + "token_active = 1, "
                    + "last_synced_at = CURRENT_TIMESTAMP";

            try (PreparedStatement ps = con.prepareStatement(sql)) {
                ps.setInt(1, row.assetId);
                ps.setString(2, row.qrPublicToken);
                ps.setString(3, row.assetCode);
                ps.setString(4, row.assetName);
                ps.setString(5, row.categoryName);
                ps.setString(6, row.assetStatus);
                ps.setString(7, row.departmentName);
                ps.setString(8, row.divisionName);
                ps.setString(9, row.locationName);
                ps.setDate(10, row.warrantyExpiry);
                ps.setDate(11, row.lastPhysicalVerificationDate);
                ps.setString(12, row.maintenanceIndicator);
                ps.executeUpdate();
            }

            enqueue(con, row.assetId, row.qrPublicToken, "UPSERT", "PENDING", "");

        } catch (Exception e) {
            try {
                enqueue(con, assetId, "", "UPSERT", "FAILED", e.getMessage());
            } catch (Exception ignored) {
            }

            System.err.println("QR Module DB Error: " + e.getMessage());
        }
    }

    public static void invalidateSnapshotQuietly(Connection con, int assetId, String oldToken) {
        try {
            if (con == null || assetId <= 0) {
                return;
            }

            ensureTables(con);
            invalidateSnapshot(con, assetId, oldToken);
            enqueue(con, assetId, safe(oldToken), "INVALIDATE", "PENDING", "");

        } catch (Exception e) {
            System.err.println("QR Module DB Error: " + e.getMessage());
        }
    }

    private static SnapshotRow loadSnapshotRow(Connection con, int assetId) throws Exception {
        String sql = "SELECT "
                + "a.asset_id, COALESCE(a.qr_public_token, '') AS qr_public_token, "
                + "COALESCE(a.asset_code, '') AS asset_code, COALESCE(a.asset_name, '') AS asset_name, "
                + "COALESCE(ac.category_name, 'Uncategorized') AS category_name, "
                + "COALESCE(a.asset_status, '') AS asset_status, "
                + "COALESCE(d.department_name, 'Unassigned') AS department_name, "
                + "COALESCE(rd.division_name, '') AS division_name, "
                + "COALESCE(rl.location_name, a.location, 'Not Mentioned') AS location_name, "
                + "a.warranty_expiry, a.last_physical_verification_date, "
                + "CASE "
                + "WHEN a.asset_status = 'UNDER_MAINTENANCE' THEN 'UNDER_MAINTENANCE' "
                + "WHEN EXISTS (SELECT 1 FROM maintenance_logs ml "
                + "WHERE ml.asset_id = a.asset_id AND ml.maintenance_status IN ('OPEN','IN_PROGRESS') LIMIT 1) "
                + "THEN 'MAINTENANCE_ACTIVE' "
                + "WHEN a.asset_status IN ('DAMAGED','LOST','DISPOSED') THEN a.asset_status "
                + "ELSE 'NORMAL' END AS maintenance_indicator "
                + "FROM assets a "
                + "LEFT JOIN asset_categories ac ON a.category_id = ac.category_id "
                + "LEFT JOIN departments d ON a.department_id = d.department_id "
                + "LEFT JOIN railway_divisions rd ON a.division_id = rd.division_id "
                + "LEFT JOIN railway_locations rl ON a.location_id = rl.location_id "
                + "WHERE a.asset_id = ? "
                + "LIMIT 1";

        try (PreparedStatement ps = con.prepareStatement(sql)) {
            ps.setInt(1, assetId);

            try (ResultSet rs = ps.executeQuery()) {
                if (rs.next()) {
                    SnapshotRow row = new SnapshotRow();
                    row.assetId = rs.getInt("asset_id");
                    row.qrPublicToken = safe(rs.getString("qr_public_token"));
                    row.assetCode = safe(rs.getString("asset_code"));
                    row.assetName = safe(rs.getString("asset_name"));
                    row.categoryName = safe(rs.getString("category_name"));
                    row.assetStatus = safe(rs.getString("asset_status"));
                    row.departmentName = safe(rs.getString("department_name"));
                    row.divisionName = safe(rs.getString("division_name"));
                    row.locationName = safe(rs.getString("location_name"));
                    row.warrantyExpiry = rs.getDate("warranty_expiry");
                    row.lastPhysicalVerificationDate = rs.getDate("last_physical_verification_date");
                    row.maintenanceIndicator = safe(rs.getString("maintenance_indicator"));
                    return row;
                }
            }
        }

        return null;
    }

    private static void invalidateSnapshot(Connection con, int assetId, String oldToken) throws Exception {
        String sql = "UPDATE public_asset_snapshot "
                + "SET token_active = 0, last_synced_at = CURRENT_TIMESTAMP "
                + "WHERE asset_id = ? OR qr_public_token = ?";

        try (PreparedStatement ps = con.prepareStatement(sql)) {
            ps.setInt(1, assetId);
            ps.setString(2, safe(oldToken));
            ps.executeUpdate();
        }
    }

    private static void enqueue(Connection con, int assetId, String token, String action, String status, String error) throws Exception {
        String sql = "INSERT INTO qr_sync_queue "
                + "(asset_id, qr_public_token, sync_action, sync_status, attempt_count, last_error) "
                + "VALUES (?, ?, ?, ?, 0, ?)";

        try (PreparedStatement ps = con.prepareStatement(sql)) {
            ps.setInt(1, assetId);
            ps.setString(2, safe(token));
            ps.setString(3, action);
            ps.setString(4, status);
            ps.setString(5, limit(error, 1000));
            ps.executeUpdate();
        }
    }

    private static void ensureTables(Connection con) throws Exception {
        String snapshotSql = "CREATE TABLE IF NOT EXISTS public_asset_snapshot ("
                + "snapshot_id BIGINT NOT NULL AUTO_INCREMENT, "
                + "asset_id INT NOT NULL, "
                + "qr_public_token VARCHAR(120) NOT NULL, "
                + "asset_code VARCHAR(80) NOT NULL, "
                + "asset_name VARCHAR(180) NOT NULL, "
                + "category_name VARCHAR(120) DEFAULT NULL, "
                + "asset_status VARCHAR(50) DEFAULT NULL, "
                + "department_name VARCHAR(120) DEFAULT NULL, "
                + "division_name VARCHAR(150) DEFAULT NULL, "
                + "location_name VARCHAR(180) DEFAULT NULL, "
                + "warranty_expiry DATE DEFAULT NULL, "
                + "last_physical_verification_date DATE DEFAULT NULL, "
                + "maintenance_indicator VARCHAR(80) DEFAULT NULL, "
                + "token_active TINYINT(1) NOT NULL DEFAULT 1, "
                + "last_synced_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP, "
                + "PRIMARY KEY (snapshot_id), "
                + "UNIQUE KEY uk_public_snapshot_token (qr_public_token), "
                + "UNIQUE KEY uk_public_snapshot_asset (asset_id), "
                + "KEY idx_public_snapshot_status (asset_status)"
                + ") ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci";

        String queueSql = "CREATE TABLE IF NOT EXISTS qr_sync_queue ("
                + "queue_id BIGINT NOT NULL AUTO_INCREMENT, "
                + "asset_id INT NOT NULL, "
                + "qr_public_token VARCHAR(120) DEFAULT NULL, "
                + "sync_action ENUM('UPSERT','INVALIDATE','DELETE') NOT NULL DEFAULT 'UPSERT', "
                + "sync_status ENUM('PENDING','PROCESSING','SYNCED','FAILED') NOT NULL DEFAULT 'PENDING', "
                + "attempt_count INT NOT NULL DEFAULT 0, "
                + "last_error TEXT, "
                + "created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP, "
                + "updated_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP, "
                + "PRIMARY KEY (queue_id), "
                + "KEY idx_qr_sync_status (sync_status), "
                + "KEY idx_qr_sync_asset (asset_id)"
                + ") ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci";

        try (PreparedStatement ps = con.prepareStatement(snapshotSql)) {
            ps.executeUpdate();
        }

        try (PreparedStatement ps = con.prepareStatement(queueSql)) {
            ps.executeUpdate();
        }
    }

    private static String safe(String value) {
        return value == null ? "" : value.trim();
    }

    private static String limit(String value, int maxLength) {
        String text = safe(value);

        if (text.length() <= maxLength) {
            return text;
        }

        return text.substring(0, maxLength);
    }

    private static class SnapshotRow {
        private int assetId;
        private String qrPublicToken;
        private String assetCode;
        private String assetName;
        private String categoryName;
        private String assetStatus;
        private String departmentName;
        private String divisionName;
        private String locationName;
        private java.sql.Date warrantyExpiry;
        private java.sql.Date lastPhysicalVerificationDate;
        private String maintenanceIndicator;
    }
}
