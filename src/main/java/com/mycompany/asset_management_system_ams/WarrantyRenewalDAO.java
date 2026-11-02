package com.mycompany.asset_management_system_ams;

import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.Types;
import java.util.ArrayList;
import java.util.List;
import java.util.logging.Level;
import java.util.logging.Logger;

/**
 * WarrantyRenewalDAO - reads and writes the warranty_renewals table.
 *
 * ensureTable() self-heals the table on first use (same pattern already
 * established in QrUrlUtil.ensureSystemSettingsTable()), so this feature
 * works immediately on any existing deployment without requiring a manual
 * migration step first - important for a "live world deployment" this app
 * has been hardened for throughout this session. schema.sql is also updated
 * with the same definition for documentation/fresh-install purposes.
 */
public class WarrantyRenewalDAO {

    private static final Logger LOGGER = Logger.getLogger(WarrantyRenewalDAO.class.getName());
    private static volatile boolean tableEnsured = false;

    private static void ensureTable(Connection con) {
        if (tableEnsured) {
            return;
        }
        String sql = "CREATE TABLE IF NOT EXISTS warranty_renewals ("
                + "renewal_id INT AUTO_INCREMENT PRIMARY KEY, "
                + "asset_id INT NOT NULL, "
                + "previous_expiry DATE DEFAULT NULL, "
                + "new_expiry DATE NOT NULL, "
                + "extension_months INT DEFAULT NULL, "
                + "renewal_cost DECIMAL(12,2) DEFAULT 0.00, "
                + "notes TEXT, "
                + "renewed_by INT DEFAULT NULL, "
                + "created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP, "
                + "KEY idx_warranty_renewals_asset (asset_id)"
                + ") ENGINE=InnoDB DEFAULT CHARSET=utf8mb4";
        try (PreparedStatement ps = con.prepareStatement(sql)) {
            ps.executeUpdate();
            tableEnsured = true;
        } catch (Exception e) {
            LOGGER.log(Level.WARNING, "Unable to ensure warranty_renewals table exists", e);
        }
    }

    /**
     * Records a renewal and updates the asset's live warranty_expiry to the
     * new date, in one transaction - the renewal log and the asset's current
     * warranty status (already used everywhere else in the app, e.g.
     * warranty_report.jsp / WarrantyAlertScheduler) must never disagree.
     */
    public boolean recordRenewal(int assetId, String previousExpiry, String newExpiry,
            Integer extensionMonths, double renewalCost, String notes, int renewedBy) {

        Connection con = null;
        try {
            con = DBConnection.getConnection();
            if (con == null) {
                return false;
            }
            ensureTable(con);

            con.setAutoCommit(false);

            String insertSql = "INSERT INTO warranty_renewals "
                    + "(asset_id, previous_expiry, new_expiry, extension_months, renewal_cost, notes, renewed_by) "
                    + "VALUES (?, ?, ?, ?, ?, ?, ?)";
            try (PreparedStatement ps = con.prepareStatement(insertSql)) {
                ps.setInt(1, assetId);
                if (previousExpiry == null || previousExpiry.trim().isEmpty()) {
                    ps.setNull(2, Types.DATE);
                } else {
                    ps.setString(2, previousExpiry);
                }
                ps.setString(3, newExpiry);
                if (extensionMonths == null) {
                    ps.setNull(4, Types.INTEGER);
                } else {
                    ps.setInt(4, extensionMonths);
                }
                ps.setDouble(5, renewalCost);
                ps.setString(6, notes == null ? "" : notes.trim());
                if (renewedBy > 0) {
                    ps.setInt(7, renewedBy);
                } else {
                    ps.setNull(7, Types.INTEGER);
                }
                ps.executeUpdate();
            }

            String updateSql = "UPDATE assets SET warranty_expiry = ? WHERE asset_id = ?";
            try (PreparedStatement ps = con.prepareStatement(updateSql)) {
                ps.setString(1, newExpiry);
                ps.setInt(2, assetId);
                int updated = ps.executeUpdate();
                if (updated == 0) {
                    con.rollback();
                    return false;
                }
            }

            con.commit();
            return true;

        } catch (Exception e) {
            LOGGER.log(Level.SEVERE, "recordRenewal failed for asset " + assetId, e);
            try {
                if (con != null) {
                    con.rollback();
                }
            } catch (Exception rollbackEx) {
                LOGGER.log(Level.WARNING, "Rollback failed", rollbackEx);
            }
            return false;
        } finally {
            try {
                if (con != null) {
                    con.setAutoCommit(true);
                    con.close();
                }
            } catch (Exception closeEx) {
                LOGGER.log(Level.WARNING, "Unable to close connection", closeEx);
            }
        }
    }

    public List<WarrantyRenewal> getHistoryForAsset(int assetId) {
        List<WarrantyRenewal> list = new ArrayList<>();

        String sql = "SELECT wr.renewal_id, wr.asset_id, wr.previous_expiry, wr.new_expiry, "
                + "wr.extension_months, wr.renewal_cost, wr.notes, wr.created_at, "
                + "COALESCE(u.username, 'System') AS renewed_by_username "
                + "FROM warranty_renewals wr "
                + "LEFT JOIN users u ON wr.renewed_by = u.user_id "
                + "WHERE wr.asset_id = ? "
                + "ORDER BY wr.created_at DESC, wr.renewal_id DESC";

        try (Connection con = DBConnection.getConnection()) {
            if (con == null) {
                return list;
            }
            ensureTable(con);

            try (PreparedStatement ps = con.prepareStatement(sql)) {
                ps.setInt(1, assetId);
                try (ResultSet rs = ps.executeQuery()) {
                    while (rs.next()) {
                        WarrantyRenewal renewal = new WarrantyRenewal();
                        renewal.setRenewalId(rs.getInt("renewal_id"));
                        renewal.setAssetId(rs.getInt("asset_id"));
                        renewal.setPreviousExpiry(rs.getString("previous_expiry"));
                        renewal.setNewExpiry(rs.getString("new_expiry"));
                        int extMonths = rs.getInt("extension_months");
                        renewal.setExtensionMonths(rs.wasNull() ? null : extMonths);
                        renewal.setRenewalCost(rs.getDouble("renewal_cost"));
                        renewal.setNotes(rs.getString("notes"));
                        renewal.setRenewedByUsername(rs.getString("renewed_by_username"));
                        renewal.setCreatedAt(rs.getString("created_at"));
                        list.add(renewal);
                    }
                }
            }
        } catch (Exception e) {
            LOGGER.log(Level.WARNING, "getHistoryForAsset failed for asset " + assetId, e);
        }

        return list;
    }

    /** Total renewal count across all assets, for the DB-Status/dashboard-style summary if ever needed. */
    public int getRenewalCountForAsset(int assetId) {
        String sql = "SELECT COUNT(*) FROM warranty_renewals WHERE asset_id = ?";
        try (Connection con = DBConnection.getConnection()) {
            if (con == null) {
                return 0;
            }
            ensureTable(con);
            try (PreparedStatement ps = con.prepareStatement(sql)) {
                ps.setInt(1, assetId);
                try (ResultSet rs = ps.executeQuery()) {
                    return rs.next() ? rs.getInt(1) : 0;
                }
            }
        } catch (Exception e) {
            LOGGER.log(Level.WARNING, "getRenewalCountForAsset failed for asset " + assetId, e);
            return 0;
        }
    }
}
