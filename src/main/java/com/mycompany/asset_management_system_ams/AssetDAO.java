package com.mycompany.asset_management_system_ams;

import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.Types;
import java.time.LocalDate;
import java.util.ArrayList;
import java.util.List;

public class AssetDAO {

    public List<Asset> getAllAssets() {
        return getAllAssets(null);
    }

    public List<Asset> getAllAssets(List<Integer> departmentIds) {
        List<Asset> assetList = new ArrayList<>();

        String sql = "SELECT a.asset_id, a.asset_code, a.asset_name, "
                + "COALESCE(c.category_name, 'Uncategorized') AS category_name, "
                + "COALESCE(v.vendor_name, 'No Supplier') AS vendor_name, "
                + "a.serial_number, COALESCE(a.qr_code, a.qr_public_token) AS qr_code, "
                + "a.asset_image_path, "
                + "COALESCE(l.location_name, a.location, 'Rail Sadan') AS location, "
                + "a.purchase_date, a.purchase_cost, a.warranty_expiry, a.asset_status, a.depreciation_rate "
                + "FROM assets a "
                + "LEFT JOIN asset_categories c ON a.category_id = c.category_id "
                + "LEFT JOIN vendors v ON a.vendor_id = v.vendor_id "
                + "LEFT JOIN railway_locations l ON a.location_id = l.location_id ";
                
        if (departmentIds != null && !departmentIds.isEmpty()) {
            StringBuilder sb = new StringBuilder("(");
            for (int i = 0; i < departmentIds.size(); i++) {
                sb.append("?");
                if (i < departmentIds.size() - 1) sb.append(",");
            }
            sb.append(")");
            sql += "WHERE a.department_id IN " + sb.toString() + " ";
        }
        
        sql += "ORDER BY a.asset_id ASC";

        try (Connection con = DBConnection.getConnection();
             PreparedStatement ps = con.prepareStatement(sql)) {
             
            if (departmentIds != null && !departmentIds.isEmpty()) {
                for (int i = 0; i < departmentIds.size(); i++) {
                    ps.setInt(i + 1, departmentIds.get(i));
                }
            }

            try (ResultSet rs = ps.executeQuery()) {
                while (rs.next()) {
                    assetList.add(buildAsset(rs));
                }
            }
        } catch (Exception e) {
            System.err.println("[AssetDAO] getAllAssets failed: " + e.getMessage());
            e.printStackTrace();
        }

        return assetList;
    }

    public Asset getAssetByQrCode(String qrCode) {
        Asset asset = null;

        String sql = "SELECT a.asset_id, a.asset_code, a.asset_name, "
                + "COALESCE(c.category_name, 'Uncategorized') AS category_name, "
                + "COALESCE(v.vendor_name, 'No Supplier') AS vendor_name, "
                + "a.serial_number, COALESCE(a.qr_code, a.qr_public_token) AS qr_code, "
                + "a.asset_image_path, "
                + "COALESCE(l.location_name, a.location, 'Rail Sadan') AS location, "
                + "a.purchase_date, a.purchase_cost, a.warranty_expiry, a.asset_status, a.depreciation_rate "
                + "FROM assets a "
                + "LEFT JOIN asset_categories c ON a.category_id = c.category_id "
                + "LEFT JOIN vendors v ON a.vendor_id = v.vendor_id "
                + "LEFT JOIN railway_locations l ON a.location_id = l.location_id "
                + "WHERE a.qr_code = ? OR a.qr_public_token = ?";

        try (Connection con = DBConnection.getConnection();
             PreparedStatement ps = con.prepareStatement(sql)) {

            ps.setString(1, clean(qrCode));
            ps.setString(2, clean(qrCode));

            try (ResultSet rs = ps.executeQuery()) {
                if (rs.next()) {
                    asset = buildAsset(rs);
                }
            }
        } catch (Exception e) {
            System.err.println("[AssetDAO] getAssetByQrCode failed: " + e.getMessage());
            e.printStackTrace();
        }

        return asset;
    }

    public boolean addAsset(String assetCode, String assetName, int categoryId, int vendorId,
            String serialNumber, String qrCode, String location,
            String purchaseDate, double purchaseCost,
            String warrantyExpiry, double depreciationRate,
            String assetStatus, int departmentId, int divisionId, int locationId) {

        return addAsset(assetCode, assetName, categoryId, vendorId, serialNumber, qrCode, location,
                purchaseDate, purchaseCost, warrantyExpiry, depreciationRate, assetStatus, "", departmentId, divisionId, locationId);
    }

    public boolean addAsset(String assetCode, String assetName, int categoryId, int vendorId,
            String serialNumber, String qrCode, String location,
            String purchaseDate, double purchaseCost,
            String warrantyExpiry, double depreciationRate,
            String assetStatus, String assetImagePath,
            int departmentId, int divisionId, int locationId) {

        if (!isActiveSupplierMappedToCategory(categoryId, vendorId)) {
            return false;
        }

        String sql = "INSERT INTO assets "
                + "(asset_code, asset_name, category_id, vendor_id, serial_number, qr_code, qr_public_token, "
                + "asset_image_path, location, purchase_date, purchase_cost, warranty_expiry, depreciation_rate, asset_status, "
                + "condition_status, service_status, department_id, division_id, location_id) "
                + "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'GOOD', 'SERVICEABLE', ?, ?, ?)";

        try (Connection con = DBConnection.getConnection()) {

            // Fault (security): this used to derive the new asset's
            // qr_public_token from buildQrPublicToken(assetCode, qrCode) - a
            // predictable "IRAMS-<assetCode>" value, guessable by anyone who
            // knows the app's sequential asset-code pattern (AST001, AST002,
            // ...). qr_public_token is the ONLY gate on public_asset_view.jsp,
            // a genuinely unauthenticated page - GenerateAssetQrServlet
            // already knows this and issues a real SecureRandom token
            // whenever an admin explicitly (re)generates a QR, but every
            // asset sat with a guessable token from the moment it was
            // created until someone happened to click "Generate QR" for it -
            // confirmed live in the database (AST021, AST022,
            // ECoR-LAP-0007 all still carried their predictable
            // creation-time token). Fixed by generating a real random token
            // - matching GenerateAssetQrServlet's own format exactly - right
            // here at creation, so no asset ever has a guessable public
            // token, not even for the brief window before anyone thinks to
            // regenerate it.
            String publicToken = generateUniqueQrPublicToken(con);

            try (PreparedStatement ps = con.prepareStatement(sql)) {

                ps.setString(1, clean(assetCode));
                ps.setString(2, clean(assetName));
                ps.setInt(3, categoryId);
                ps.setInt(4, vendorId);
                ps.setString(5, clean(serialNumber));
                ps.setString(6, clean(qrCode));
                ps.setString(7, publicToken);
                ps.setString(8, emptyToNull(assetImagePath));
                ps.setString(9, clean(location));
                ps.setString(10, emptyToNull(purchaseDate));
                ps.setDouble(11, purchaseCost);
                ps.setString(12, emptyToNull(warrantyExpiry));
                ps.setDouble(13, depreciationRate);
                ps.setString(14, normalizeAssetStatus(assetStatus));

                if (departmentId > 0) ps.setInt(15, departmentId); else ps.setNull(15, Types.INTEGER);
                if (divisionId > 0) ps.setInt(16, divisionId); else ps.setNull(16, Types.INTEGER);
                if (locationId > 0) ps.setInt(17, locationId); else ps.setNull(17, Types.INTEGER);

                return ps.executeUpdate() > 0;
            }
        } catch (Exception e) {
            System.err.println("[AssetDAO] addAsset failed: " + e.getMessage());
            e.printStackTrace();
        }

        return false;
    }

    public Asset getAssetById(int assetId) {
        Asset asset = null;

        String sql = "SELECT a.asset_id, a.asset_code, a.asset_name, "
                + "COALESCE(c.category_name, 'Uncategorized') AS category_name, "
                + "COALESCE(v.vendor_name, 'No Supplier') AS vendor_name, "
                + "a.serial_number, COALESCE(a.qr_code, a.qr_public_token) AS qr_code, "
                + "a.asset_image_path, "
                + "COALESCE(l.location_name, a.location, 'Rail Sadan') AS location, "
                + "a.purchase_date, a.purchase_cost, a.warranty_expiry, a.asset_status, a.depreciation_rate "
                + "FROM assets a "
                + "LEFT JOIN asset_categories c ON a.category_id = c.category_id "
                + "LEFT JOIN vendors v ON a.vendor_id = v.vendor_id "
                + "LEFT JOIN railway_locations l ON a.location_id = l.location_id "
                + "WHERE a.asset_id = ?";

        try (Connection con = DBConnection.getConnection();
             PreparedStatement ps = con.prepareStatement(sql)) {

            ps.setInt(1, assetId);
            try (ResultSet rs = ps.executeQuery()) {
                if (rs.next()) {
                    asset = buildAsset(rs);
                }
            }
        } catch (Exception e) {
            System.err.println("[AssetDAO] getAssetById failed: " + e.getMessage());
            e.printStackTrace();
        }

        return asset;
    }

    public boolean updateAsset(int assetId, String assetCode, String assetName,
            int categoryId, int vendorId, String serialNumber,
            String qrCode, String location, String purchaseDate,
            double purchaseCost, String warrantyExpiry,
            double depreciationRate, String assetStatus,
            int departmentId, int divisionId, int locationId) {

        return updateAsset(assetId, assetCode, assetName, categoryId, vendorId, serialNumber,
                qrCode, location, purchaseDate, purchaseCost, warrantyExpiry, depreciationRate,
                assetStatus, "", departmentId, divisionId, locationId);
    }

    public boolean updateAsset(int assetId, String assetCode, String assetName,
            int categoryId, int vendorId, String serialNumber,
            String qrCode, String location, String purchaseDate,
            double purchaseCost, String warrantyExpiry,
            double depreciationRate, String assetStatus, String assetImagePath,
            int departmentId, int divisionId, int locationId) {

        if (!isActiveSupplierMappedToCategory(categoryId, vendorId)) {
            return false;
        }

        String sql = "UPDATE assets SET asset_code = ?, asset_name = ?, category_id = ?, vendor_id = ?, "
                + "serial_number = ?, qr_code = ?, asset_image_path = COALESCE(NULLIF(?, ''), asset_image_path), "
                + "location = ?, purchase_date = ?, purchase_cost = ?, "
                + "warranty_expiry = ?, depreciation_rate = ?, asset_status = ?, "
                + "department_id = ?, division_id = ?, location_id = ? "
                + "WHERE asset_id = ?";

        try (Connection con = DBConnection.getConnection();
             PreparedStatement ps = con.prepareStatement(sql)) {

            ps.setString(1, clean(assetCode));
            ps.setString(2, clean(assetName));
            ps.setInt(3, categoryId);
            ps.setInt(4, vendorId);
            ps.setString(5, clean(serialNumber));
            ps.setString(6, clean(qrCode));
            ps.setString(7, clean(assetImagePath));
            ps.setString(8, clean(location));
            ps.setString(9, emptyToNull(purchaseDate));
            ps.setDouble(10, purchaseCost);
            ps.setString(11, emptyToNull(warrantyExpiry));
            ps.setDouble(12, depreciationRate);
            ps.setString(13, normalizeAssetStatus(assetStatus));
            
            if (departmentId > 0) ps.setInt(14, departmentId); else ps.setNull(14, Types.INTEGER);
            if (divisionId > 0) ps.setInt(15, divisionId); else ps.setNull(15, Types.INTEGER);
            if (locationId > 0) ps.setInt(16, locationId); else ps.setNull(16, Types.INTEGER);
            
            ps.setInt(17, assetId);

            return ps.executeUpdate() > 0;
        } catch (Exception e) {
            System.err.println("[AssetDAO] updateAsset failed: " + e.getMessage());
            e.printStackTrace();
        }

        return false;
    }

    /**
     * Maker stage of the disposal approval workflow. Records the proposal in
     * asset_disposal as PENDING and does NOT touch assets.asset_status - the
     * asset stays exactly as it was (AVAILABLE/UNDER_MAINTENANCE/etc.) until
     * a second party actually reviews the proposal via reviewDisposal(). This
     * closes the Future Scope gap flagged in the project report: the schema
     * already modelled a full maker-checker chain (disposal_status enum) but
     * the old disposeAsset() inserted straight to 'COMPLETED' and flipped the
     * asset in the same single-actor step - no second-party authorization for
     * an inherently high-consequence, financially significant action.
     *
     * uk_disposal_asset_id is UNIQUE on asset_id alone, so an asset can only
     * ever have one disposal row, ever - a real constraint this method has to
     * work within rather than fight. If the asset's existing row (if any) is
     * REJECTED, this UPDATEs it back to PENDING with the new submission's
     * details instead of trying a second INSERT, which is how a maker
     * resubmits after a rejection.
     */
    public boolean submitDisposal(
            int assetId,
            String disposalDate,
            String disposalReason,
            double disposalValue,
            int requestedBy,
            String remarks) {

        Connection con = null;

        try {
            con = DBConnection.getConnection();
            con.setAutoCommit(false);

            String currentStatus = getAssetStatusForUpdate(con, assetId);

            if (currentStatus.isEmpty()
                    || "DISPOSED".equalsIgnoreCase(currentStatus)
                    || hasActiveAllocation(con, assetId)) {
                con.rollback();
                return false;
            }

            String existingStatus = null;
            try (PreparedStatement ps = con.prepareStatement(
                    "SELECT disposal_status FROM asset_disposal WHERE asset_id = ? FOR UPDATE")) {
                ps.setInt(1, assetId);
                try (ResultSet rs = ps.executeQuery()) {
                    if (rs.next()) {
                        existingStatus = rs.getString(1);
                    }
                }
            }

            // A PENDING or already-COMPLETED row blocks a new submission outright;
            // no row, or a REJECTED row, are the only two states a submission may
            // proceed from.
            if ("PENDING".equalsIgnoreCase(existingStatus) || "COMPLETED".equalsIgnoreCase(existingStatus)
                    || "APPROVED".equalsIgnoreCase(existingStatus)) {
                con.rollback();
                return false;
            }

            String requestedByDate = LocalDate.now().toString();
            boolean ok;

            if (existingStatus == null) {
                String insertSql = "INSERT INTO asset_disposal "
                        + "(asset_id, disposal_date, disposal_reason, disposal_value, requested_by, requested_date, "
                        + "approved_by, approved_date, disposal_status, remarks) "
                        + "VALUES (?, ?, ?, ?, ?, ?, NULL, NULL, 'PENDING', ?)";
                try (PreparedStatement ps = con.prepareStatement(insertSql)) {
                    ps.setInt(1, assetId);
                    ps.setString(2, emptyToNull(disposalDate));
                    ps.setString(3, normalizeDisposalReason(disposalReason, remarks));
                    ps.setDouble(4, Math.max(disposalValue, 0.0));
                    if (requestedBy <= 0) {
                        ps.setNull(5, Types.INTEGER);
                    } else {
                        ps.setInt(5, requestedBy);
                    }
                    ps.setString(6, requestedByDate);
                    ps.setString(7, limitText(remarks, 255));
                    ok = ps.executeUpdate() > 0;
                }
            } else {
                // Resubmission after a REJECTED review - reuse the row (the unique
                // constraint on asset_id leaves no other option), clearing the
                // previous reviewer's decision so it reads as a fresh proposal.
                String updateSql = "UPDATE asset_disposal SET disposal_date = ?, disposal_reason = ?, "
                        + "disposal_value = ?, requested_by = ?, requested_date = ?, "
                        + "approved_by = NULL, approved_date = NULL, disposal_status = 'PENDING', remarks = ? "
                        + "WHERE asset_id = ? AND disposal_status = 'REJECTED'";
                try (PreparedStatement ps = con.prepareStatement(updateSql)) {
                    ps.setString(1, emptyToNull(disposalDate));
                    ps.setString(2, normalizeDisposalReason(disposalReason, remarks));
                    ps.setDouble(3, Math.max(disposalValue, 0.0));
                    if (requestedBy <= 0) {
                        ps.setNull(4, Types.INTEGER);
                    } else {
                        ps.setInt(4, requestedBy);
                    }
                    ps.setString(5, requestedByDate);
                    ps.setString(6, limitText(remarks, 255));
                    ps.setInt(7, assetId);
                    ok = ps.executeUpdate() > 0;
                }
            }

            if (!ok) {
                con.rollback();
                return false;
            }

            con.commit();
            return true;
        } catch (Exception e) {
            System.err.println("[AssetDAO] submitDisposal failed: " + e.getMessage());
            try {
                if (con != null) {
                    con.rollback();
                }
            } catch (Exception ignored) {
            }
            e.printStackTrace();
        } finally {
            try {
                if (con != null) {
                    con.setAutoCommit(true);
                    con.close();
                }
            } catch (Exception e) {
                System.err.println("[AssetDAO] submitDisposal failed: " + e.getMessage());
                e.printStackTrace();
            }
        }

        return false;
    }

    /**
     * Checker stage: a second party (SUPER_ADMIN/ADMIN, never the maker's
     * ASSET_MANAGER-only role - see ReviewAssetDisposalServlet) approves or
     * rejects a PENDING disposal proposal. Approving is the only path that
     * ever flips assets.asset_status to DISPOSED - this is deliberately the
     * single choke point for that state change, matching how the disposal
     * was already effectively final-and-irreversible under the old
     * single-actor flow, just now gated behind a real second signature.
     *
     * requiredCurrentStatus='PENDING' in the WHERE clause is the same
     * idempotency/concurrency guard pattern used throughout this codebase
     * (AssetRequestDAO.updateRequestStatus, forwardOrRejectByDeptHead,
     * ReviewPhysicalVerificationServlet): a stale or replayed review action
     * becomes a safe no-op instead of double-processing.
     *
     * @param action "APPROVE" or "REJECT"
     */
    public boolean reviewDisposal(int disposalId, String action, int reviewerUserId, String remarks) {
        boolean approve = "APPROVE".equalsIgnoreCase(clean(action));
        Connection con = null;

        try {
            con = DBConnection.getConnection();
            con.setAutoCommit(false);

            int assetId = 0;
            String disposalDate = null;
            try (PreparedStatement ps = con.prepareStatement(
                    "SELECT asset_id, disposal_date FROM asset_disposal WHERE disposal_id = ? AND disposal_status = 'PENDING' FOR UPDATE")) {
                ps.setInt(1, disposalId);
                try (ResultSet rs = ps.executeQuery()) {
                    if (rs.next()) {
                        assetId = rs.getInt(1);
                        disposalDate = rs.getString(2);
                    }
                }
            }

            if (assetId <= 0) {
                con.rollback();
                return false;
            }

            // Write-off entry: the asset's own DepreciationUtil-computed book
            // value as of disposal_date (not "today" - approval can happen
            // days after the maker submitted the proposal, and the write-off
            // figure should reflect what the asset was worth when it was
            // actually taken out of service, not when the paperwork cleared).
            // Never touched on reject - calculated_book_value stays NULL.
            Double calculatedBookValue = null;
            if (approve) {
                try (PreparedStatement ps = con.prepareStatement(
                        "SELECT purchase_cost, depreciation_rate, purchase_date FROM assets WHERE asset_id = ?")) {
                    ps.setInt(1, assetId);
                    try (ResultSet rs = ps.executeQuery()) {
                        if (rs.next()) {
                            double purchaseCost = rs.getDouble("purchase_cost");
                            double depreciationRate = rs.getDouble("depreciation_rate");
                            String purchaseDateIso = rs.getString("purchase_date");
                            LocalDate asOf = disposalDate != null ? LocalDate.parse(disposalDate) : LocalDate.now();
                            calculatedBookValue = DepreciationUtil.computeBookValue(
                                    purchaseCost, depreciationRate, purchaseDateIso, asOf);
                        }
                    }
                }
            }

            String newStatus = approve ? "COMPLETED" : "REJECTED";
            String updateDisposalSql = "UPDATE asset_disposal SET disposal_status = ?, approved_by = ?, "
                    + "approved_date = ?, remarks = ?, calculated_book_value = ? WHERE disposal_id = ? AND disposal_status = 'PENDING'";

            try (PreparedStatement ps = con.prepareStatement(updateDisposalSql)) {
                ps.setString(1, newStatus);
                if (reviewerUserId <= 0) {
                    ps.setNull(2, Types.INTEGER);
                } else {
                    ps.setInt(2, reviewerUserId);
                }
                ps.setString(3, LocalDate.now().toString());
                ps.setString(4, limitText(remarks, 255));
                if (calculatedBookValue == null) {
                    ps.setNull(5, Types.DECIMAL);
                } else {
                    ps.setDouble(5, calculatedBookValue);
                }
                ps.setInt(6, disposalId);

                if (ps.executeUpdate() <= 0) {
                    con.rollback();
                    return false;
                }
            }

            if (approve) {
                String updateAssetSql = "UPDATE assets SET asset_status = 'DISPOSED', condition_status = 'DAMAGED', "
                        + "service_status = 'SCRAP_RECOMMENDED' WHERE asset_id = ? AND asset_status <> 'DISPOSED'";
                try (PreparedStatement ps = con.prepareStatement(updateAssetSql)) {
                    ps.setInt(1, assetId);
                    if (ps.executeUpdate() <= 0) {
                        con.rollback();
                        return false;
                    }
                }
            }

            con.commit();
            return true;
        } catch (Exception e) {
            System.err.println("[AssetDAO] reviewDisposal failed: " + e.getMessage());
            try {
                if (con != null) {
                    con.rollback();
                }
            } catch (Exception ignored) {
            }
            e.printStackTrace();
        } finally {
            try {
                if (con != null) {
                    con.setAutoCommit(true);
                    con.close();
                }
            } catch (Exception e) {
                System.err.println("[AssetDAO] reviewDisposal failed: " + e.getMessage());
                e.printStackTrace();
            }
        }

        return false;
    }

    /** Disposal proposals currently awaiting a checker's review, newest first. */
    public List<java.util.Map<String, String>> getPendingDisposals() {
        List<java.util.Map<String, String>> out = new ArrayList<>();
        String sql = "SELECT ad.disposal_id, ad.asset_id, a.asset_code, a.asset_name, "
                + "DATE_FORMAT(ad.disposal_date, '%d %b %Y') AS disposal_date, "
                + "ad.disposal_reason, ad.disposal_value, ad.remarks, "
                + "COALESCE(u.username, 'System') AS requested_by_name, "
                + "DATE_FORMAT(ad.requested_date, '%d %b %Y') AS requested_date "
                + "FROM asset_disposal ad "
                + "JOIN assets a ON ad.asset_id = a.asset_id "
                + "LEFT JOIN users u ON ad.requested_by = u.user_id "
                + "WHERE ad.disposal_status = 'PENDING' "
                + "ORDER BY ad.requested_date DESC, ad.disposal_id DESC";

        try (Connection con = DBConnection.getConnection();
             PreparedStatement ps = con.prepareStatement(sql);
             ResultSet rs = ps.executeQuery()) {

            while (rs.next()) {
                java.util.Map<String, String> row = new java.util.HashMap<>();
                row.put("disposal_id", String.valueOf(rs.getInt("disposal_id")));
                row.put("asset_id", String.valueOf(rs.getInt("asset_id")));
                row.put("asset_code", rs.getString("asset_code"));
                row.put("asset_name", rs.getString("asset_name"));
                row.put("disposal_date", rs.getString("disposal_date"));
                row.put("disposal_reason", rs.getString("disposal_reason"));
                row.put("disposal_value", String.valueOf(rs.getDouble("disposal_value")));
                row.put("remarks", rs.getString("remarks"));
                row.put("requested_by_name", rs.getString("requested_by_name"));
                row.put("requested_date", rs.getString("requested_date"));
                out.add(row);
            }
        } catch (Exception e) {
            System.err.println("[AssetDAO] getPendingDisposals failed: " + e.getMessage());
            e.printStackTrace();
        }

        return out;
    }

    /** Every disposal record (all statuses), newest first - backs asset_disposals.jsp. */
    public List<java.util.Map<String, String>> getAllDisposals() {
        List<java.util.Map<String, String>> out = new ArrayList<>();
        String sql = "SELECT ad.disposal_id, ad.asset_id, a.asset_code, a.asset_name, "
                + "DATE_FORMAT(ad.disposal_date, '%d %b %Y') AS disposal_date, "
                + "ad.disposal_reason, ad.disposal_value, ad.disposal_status, ad.remarks, "
                + "COALESCE(ru.username, '') AS requested_by_name, "
                + "COALESCE(au.username, '') AS approved_by_name "
                + "FROM asset_disposal ad "
                + "JOIN assets a ON ad.asset_id = a.asset_id "
                + "LEFT JOIN users ru ON ad.requested_by = ru.user_id "
                + "LEFT JOIN users au ON ad.approved_by = au.user_id "
                + "ORDER BY ad.disposal_id DESC";

        try (Connection con = DBConnection.getConnection();
             PreparedStatement ps = con.prepareStatement(sql);
             ResultSet rs = ps.executeQuery()) {

            while (rs.next()) {
                java.util.Map<String, String> row = new java.util.HashMap<>();
                row.put("disposal_id", String.valueOf(rs.getInt("disposal_id")));
                row.put("asset_id", String.valueOf(rs.getInt("asset_id")));
                row.put("asset_code", rs.getString("asset_code"));
                row.put("asset_name", rs.getString("asset_name"));
                row.put("disposal_date", rs.getString("disposal_date"));
                row.put("disposal_reason", rs.getString("disposal_reason"));
                row.put("disposal_value", String.valueOf(rs.getDouble("disposal_value")));
                row.put("disposal_status", rs.getString("disposal_status"));
                row.put("remarks", rs.getString("remarks"));
                row.put("requested_by_name", rs.getString("requested_by_name"));
                row.put("approved_by_name", rs.getString("approved_by_name"));
                out.add(row);
            }
        } catch (Exception e) {
            System.err.println("[AssetDAO] getAllDisposals failed: " + e.getMessage());
            e.printStackTrace();
        }

        return out;
    }

    /**
     * Every non-disposed asset with its current DepreciationUtil-computed
     * book value and accumulated depreciation - backs depreciation_report.jsp.
     * Disposed assets are excluded: their final, permanent figure already
     * lives on asset_disposal.calculated_book_value (set once, at approval,
     * and never recalculated afterward - an asset's book value should not
     * keep "moving" once it has actually left service).
     */
    public List<java.util.Map<String, String>> getDepreciationReport() {
        List<java.util.Map<String, String>> out = new ArrayList<>();
        String sql = "SELECT a.asset_id, a.asset_code, a.asset_name, "
                + "COALESCE(c.category_name, 'Uncategorized') AS category_name, "
                + "a.purchase_cost, a.depreciation_rate, a.purchase_date, "
                + "DATE_FORMAT(a.purchase_date, '%d %b %Y') AS purchase_date_display, "
                + "a.asset_status "
                + "FROM assets a "
                + "LEFT JOIN asset_categories c ON a.category_id = c.category_id "
                + "WHERE a.asset_status <> 'DISPOSED' "
                + "ORDER BY a.asset_code ASC";

        try (Connection con = DBConnection.getConnection();
             PreparedStatement ps = con.prepareStatement(sql);
             ResultSet rs = ps.executeQuery()) {

            while (rs.next()) {
                double purchaseCost = rs.getDouble("purchase_cost");
                double depreciationRate = rs.getDouble("depreciation_rate");
                String purchaseDateIso = rs.getString("purchase_date");

                double bookValue = DepreciationUtil.computeBookValue(purchaseCost, depreciationRate, purchaseDateIso, null);
                double accumulatedDepreciation = DepreciationUtil.computeAccumulatedDepreciation(
                        purchaseCost, depreciationRate, purchaseDateIso, null);

                java.util.Map<String, String> row = new java.util.HashMap<>();
                row.put("asset_id", String.valueOf(rs.getInt("asset_id")));
                row.put("asset_code", rs.getString("asset_code"));
                row.put("asset_name", rs.getString("asset_name"));
                row.put("category_name", rs.getString("category_name"));
                row.put("purchase_cost", String.valueOf(purchaseCost));
                row.put("depreciation_rate", String.valueOf(depreciationRate));
                row.put("purchase_date", rs.getString("purchase_date_display"));
                row.put("asset_status", rs.getString("asset_status"));
                row.put("book_value", String.valueOf(bookValue));
                row.put("accumulated_depreciation", String.valueOf(accumulatedDepreciation));
                out.add(row);
            }
        } catch (Exception e) {
            System.err.println("[AssetDAO] getDepreciationReport failed: " + e.getMessage());
            e.printStackTrace();
        }

        return out;
    }

    public int getAssetIdByDisposalId(int disposalId) {
        String sql = "SELECT asset_id FROM asset_disposal WHERE disposal_id = ?";
        try (Connection con = DBConnection.getConnection();
             PreparedStatement ps = con.prepareStatement(sql)) {
            ps.setInt(1, disposalId);
            try (ResultSet rs = ps.executeQuery()) {
                if (rs.next()) {
                    return rs.getInt(1);
                }
            }
        } catch (Exception e) {
            System.err.println("[AssetDAO] getAssetIdByDisposalId failed: " + e.getMessage());
            e.printStackTrace();
        }
        return 0;
    }

    /** True only for a status that should block a *new* disposal submission (PENDING/COMPLETED). */
    public boolean hasBlockingDisposal(int assetId) {
        String sql = "SELECT COUNT(*) FROM asset_disposal WHERE asset_id = ? AND disposal_status IN ('PENDING', 'COMPLETED', 'APPROVED')";
        try (Connection con = DBConnection.getConnection();
             PreparedStatement ps = con.prepareStatement(sql)) {
            ps.setInt(1, assetId);
            try (ResultSet rs = ps.executeQuery()) {
                return rs.next() && rs.getInt(1) > 0;
            }
        } catch (Exception e) {
            System.err.println("[AssetDAO] hasBlockingDisposal failed: " + e.getMessage());
            e.printStackTrace();
        }
        return false;
    }

    public boolean hasActiveAllocation(int assetId) {
        try (Connection con = DBConnection.getConnection()) {
            return hasActiveAllocation(con, assetId);
        } catch (Exception e) {
            System.err.println("[AssetDAO] hasActiveAllocation failed: " + e.getMessage());
            e.printStackTrace();
        }

        return true;
    }

    public boolean hasExistingDisposal(int assetId) {
        try (Connection con = DBConnection.getConnection()) {
            return hasExistingDisposal(con, assetId);
        } catch (Exception e) {
            System.err.println("[AssetDAO] hasExistingDisposal failed: " + e.getMessage());
            e.printStackTrace();
        }

        return true;
    }

    public String[] getDisposalNotificationDetails(int assetId) {
        String[] details = null;

        String sql = "SELECT a.asset_id, a.asset_code, a.asset_name, "
                + "COALESCE(c.category_name, 'Uncategorized') AS category_name, "
                + "COALESCE(v.vendor_name, 'No Supplier') AS vendor_name, "
                + "a.serial_number, COALESCE(l.location_name, a.location, 'Rail Sadan') AS location, "
                + "a.purchase_date, a.purchase_cost, a.warranty_expiry, a.asset_status, "
                + "e.email AS employee_email, e.employee_name AS employee_name, e.employee_code, d.department_name "
                + "FROM assets a "
                + "LEFT JOIN asset_categories c ON a.category_id = c.category_id "
                + "LEFT JOIN vendors v ON a.vendor_id = v.vendor_id "
                + "LEFT JOIN railway_locations l ON a.location_id = l.location_id "
                + "LEFT JOIN asset_allocation aa ON aa.asset_id = a.asset_id AND aa.allocation_status = 'ALLOCATED' "
                + "LEFT JOIN employees e ON aa.employee_id = e.employee_id "
                + "LEFT JOIN departments d ON e.department_id = d.department_id "
                + "WHERE a.asset_id = ? "
                + "ORDER BY aa.allocation_id DESC LIMIT 1";

        try (Connection con = DBConnection.getConnection();
             PreparedStatement ps = con.prepareStatement(sql)) {

            ps.setInt(1, assetId);
            try (ResultSet rs = ps.executeQuery()) {
                if (rs.next()) {
                    details = new String[15];
                    details[0] = String.valueOf(rs.getInt("asset_id"));
                    details[1] = rs.getString("asset_code");
                    details[2] = rs.getString("asset_name");
                    details[3] = rs.getString("category_name");
                    details[4] = rs.getString("vendor_name");
                    details[5] = rs.getString("serial_number");
                    details[6] = rs.getString("location");
                    details[7] = rs.getString("purchase_date");
                    details[8] = String.valueOf(rs.getDouble("purchase_cost"));
                    details[9] = rs.getString("warranty_expiry");
                    details[10] = rs.getString("asset_status");
                    details[11] = rs.getString("employee_email");
                    details[12] = rs.getString("employee_name");
                    details[13] = rs.getString("employee_code");
                    details[14] = rs.getString("department_name");
                }
            }
        } catch (Exception e) {
            // Fault: copy-pasted from hasExistingDisposal()'s own catch block -
            // logged the wrong method name on failure here, misleading anyone
            // debugging via server logs into looking at the wrong code path.
            System.err.println("[AssetDAO] getDisposalNotificationDetails failed: " + e.getMessage());
            e.printStackTrace();
        }

        return details;
    }

    public boolean isActiveSupplierMappedToCategory(int categoryId, int vendorId) {
        if (categoryId <= 0 || vendorId <= 0) {
            return false;
        }

        String sql = "SELECT COUNT(*) AS total FROM category_vendor_mapping "
                + "WHERE category_id = ? AND vendor_id = ? AND status = 'ACTIVE'";

        try (Connection con = DBConnection.getConnection();
             PreparedStatement ps = con.prepareStatement(sql)) {

            ps.setInt(1, categoryId);
            ps.setInt(2, vendorId);
            try (ResultSet rs = ps.executeQuery()) {
                return rs.next() && rs.getInt("total") > 0;
            }
        } catch (Exception e) {
            System.err.println("[AssetDAO] isActiveSupplierMappedToCategory failed: " + e.getMessage());
            e.printStackTrace();
        }

        return false;
    }

    public boolean isDuplicateAssetCodeOrSerial(String assetCode, String serialNumber, int excludeAssetId) {
        if (clean(assetCode).isEmpty() && clean(serialNumber).isEmpty()) {
            return false;
        }

        String sql = "SELECT COUNT(*) FROM assets WHERE (asset_code = ? OR serial_number = ?) AND asset_id != ?";
        try (Connection con = DBConnection.getConnection();
             PreparedStatement ps = con.prepareStatement(sql)) {
             
            ps.setString(1, clean(assetCode));
            ps.setString(2, clean(serialNumber));
            ps.setInt(3, excludeAssetId);
            
            try (ResultSet rs = ps.executeQuery()) {
                if (rs.next()) {
                    return rs.getInt(1) > 0;
                }
            }
        } catch (Exception e) {
            System.err.println("[AssetDAO] isDuplicateAssetCodeOrSerial failed: " + e.getMessage());
            e.printStackTrace();
        }
        return false;
    }

    public boolean isAssetCodeExists(String assetCode, int excludeAssetId) {
        if (assetCode == null || assetCode.trim().isEmpty()) {
            return false;
        }

        String sql = "SELECT COUNT(*) FROM assets WHERE asset_code = ?";
        if (excludeAssetId > 0) {
            sql += " AND asset_id != ?";
        }

        try (Connection con = DBConnection.getConnection();
             PreparedStatement ps = con.prepareStatement(sql)) {
             
            ps.setString(1, assetCode.trim());
            if (excludeAssetId > 0) {
                ps.setInt(2, excludeAssetId);
            }
            
            try (ResultSet rs = ps.executeQuery()) {
                if (rs.next()) {
                    return rs.getInt(1) > 0;
                }
            }
        } catch (Exception e) {
            System.err.println("[AssetDAO] isAssetCodeExists failed: " + e.getMessage());
            e.printStackTrace();
        }
        return false;
    }

    public String getNextSystemAssetCode() {
        String sql = "SELECT asset_code FROM assets WHERE asset_code LIKE 'AST%'";
        int max = 0;
        try (Connection con = DBConnection.getConnection();
             PreparedStatement ps = con.prepareStatement(sql);
             ResultSet rs = ps.executeQuery()) {
             
            while (rs.next()) {
                String code = rs.getString(1);
                if (code != null && code.matches("^AST\\d+$")) {
                    try {
                        int num = Integer.parseInt(code.substring(3));
                        if (num > max) {
                            max = num;
                        }
                    } catch (NumberFormatException e) {
                        // ignore invalid numbers
                    }
                }
            }
        } catch (Exception e) {
            System.err.println("[AssetDAO] getNextSystemAssetCode failed: " + e.getMessage());
            e.printStackTrace();
        }
        
        return String.format("AST%03d", max + 1);
    }

    private Asset buildAsset(ResultSet rs) throws Exception {
        Asset asset = new Asset();
        asset.setAssetId(rs.getInt("asset_id"));
        asset.setAssetCode(rs.getString("asset_code"));
        asset.setAssetName(rs.getString("asset_name"));
        asset.setCategoryName(rs.getString("category_name"));
        asset.setVendorName(rs.getString("vendor_name"));
        asset.setSerialNumber(rs.getString("serial_number"));
        asset.setQrCode(rs.getString("qr_code"));
        asset.setAssetImagePath(rs.getString("asset_image_path"));
        asset.setLocation(rs.getString("location"));
        asset.setPurchaseDate(rs.getString("purchase_date"));
        asset.setPurchaseCost(rs.getDouble("purchase_cost"));
        asset.setWarrantyExpiry(rs.getString("warranty_expiry"));
        asset.setAssetStatus(rs.getString("asset_status"));
        asset.setDepreciationRate(rs.getDouble("depreciation_rate"));
        return asset;
    }

    // Same format as GenerateAssetQrServlet's own token generator - kept
    // identical deliberately so a token minted here at creation time is
    // indistinguishable from one minted by an explicit "Generate QR" later;
    // nothing about a fresh asset's token should hint that it hasn't been
    // through that flow yet.
    private static final java.security.SecureRandom QR_TOKEN_RANDOM = new java.security.SecureRandom();
    private static final String QR_TOKEN_CHARS = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";

    private String generateUniqueQrPublicToken(Connection con) throws Exception {
        String token;

        do {
            StringBuilder sb = new StringBuilder("ECORQR");
            for (int i = 0; i < 18; i++) {
                sb.append(QR_TOKEN_CHARS.charAt(QR_TOKEN_RANDOM.nextInt(QR_TOKEN_CHARS.length())));
            }
            token = sb.toString();
        } while (qrPublicTokenExists(con, token));

        return token;
    }

    private boolean qrPublicTokenExists(Connection con, String token) throws Exception {
        String sql = "SELECT COUNT(*) FROM assets WHERE qr_public_token = ?";

        try (PreparedStatement ps = con.prepareStatement(sql)) {
            ps.setString(1, token);

            try (ResultSet rs = ps.executeQuery()) {
                return rs.next() && rs.getInt(1) > 0;
            }
        }
    }

    private String normalizeAssetStatus(String assetStatus) {
        String value = clean(assetStatus).toUpperCase();
        if ("ALLOCATED".equals(value) || "UNDER_MAINTENANCE".equals(value)
                || "DISPOSED".equals(value) || "DAMAGED".equals(value) || "LOST".equals(value)) {
            return value;
        }
        return "AVAILABLE";
    }

    private String getAssetStatusForUpdate(Connection con, int assetId) throws Exception {
        String sql = "SELECT asset_status FROM assets WHERE asset_id = ? FOR UPDATE";

        try (PreparedStatement ps = con.prepareStatement(sql)) {
            ps.setInt(1, assetId);

            try (ResultSet rs = ps.executeQuery()) {
                if (rs.next()) {
                    return clean(rs.getString("asset_status"));
                }
            }
        }

        return "";
    }

    private boolean hasActiveAllocation(Connection con, int assetId) throws Exception {
        String sql = "SELECT COUNT(*) FROM asset_allocation "
                + "WHERE asset_id = ? AND allocation_status = 'ALLOCATED'";

        try (PreparedStatement ps = con.prepareStatement(sql)) {
            ps.setInt(1, assetId);

            try (ResultSet rs = ps.executeQuery()) {
                return rs.next() && rs.getInt(1) > 0;
            }
        }
    }

    private boolean hasExistingDisposal(Connection con, int assetId) throws Exception {
        String sql = "SELECT COUNT(*) FROM asset_disposal WHERE asset_id = ?";

        try (PreparedStatement ps = con.prepareStatement(sql)) {
            ps.setInt(1, assetId);

            try (ResultSet rs = ps.executeQuery()) {
                return rs.next() && rs.getInt(1) > 0;
            }
        }
    }

    private String normalizeDisposalReason(String reason, String remarks) {
        String value = (clean(reason) + " " + clean(remarks)).toUpperCase();

        if (value.contains("LOST")) {
            return "LOST";
        }

        if (value.contains("OBSOLETE") || value.contains("REPLACED") || value.contains("UPGRADE")) {
            return "OBSOLETE";
        }

        if (value.contains("BEYOND") || value.contains("ECONOMIC") || value.contains("REPAIR")) {
            return "BEYOND_ECONOMIC_REPAIR";
        }

        if (value.contains("DAMAGE")) {
            return "DAMAGED";
        }

        if (value.contains("END") || value.contains("LIFE")) {
            return "END_OF_LIFE";
        }

        return "OTHER";
    }

    private String limitText(String value, int maxLength) {
        String text = clean(value);

        if (text.length() <= maxLength) {
            return text;
        }

        return text.substring(0, maxLength);
    }

    private String emptyToNull(String value) {
        String text = clean(value);
        return text.isEmpty() ? null : text;
    }

    private String clean(String value) {
        return value == null ? "" : value.trim();
    }
}
