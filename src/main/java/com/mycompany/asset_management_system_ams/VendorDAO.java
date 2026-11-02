package com.mycompany.asset_management_system_ams;

import java.util.logging.Logger;
import java.util.logging.Level;


import java.math.BigDecimal;
import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.Statement;
import java.sql.Types;
import java.util.ArrayList;
import java.util.List;

public class VendorDAO {
    private static final Logger LOGGER = Logger.getLogger(VendorDAO.class.getName());


    public List<Vendor> getAllVendors() {
        List<Vendor> vendorList = new ArrayList<>();

        String sql = "SELECT v.vendor_id, v.vendor_name, v.contact_person, "
                + "v.email, v.phone, v.address, v.created_at, v.vendor_status, "
                + "COUNT(a.asset_id) AS asset_count, "
                + "COALESCE(SUM(a.purchase_cost), 0) AS total_purchase_value "
                + "FROM vendors v "
                + "LEFT JOIN assets a ON v.vendor_id = a.vendor_id "
                + "GROUP BY v.vendor_id, v.vendor_name, v.contact_person, "
                + "v.email, v.phone, v.address, v.created_at, v.vendor_status "
                + "ORDER BY v.vendor_id ASC";

        try (Connection con = DBConnection.getConnection();
             PreparedStatement ps = con.prepareStatement(sql);
             ResultSet rs = ps.executeQuery()) {

            while (rs.next()) {
                vendorList.add(mapVendor(rs));
            }
        } catch (Exception e) {
            System.err.println("[VendorDAO] getAllVendors failed: " + e.getMessage());
            LOGGER.log(Level.SEVERE, "Exception occurred", e);
        }

        return vendorList;
    }

    public List<Vendor> getActiveVendors() {
        List<Vendor> vendorList = new ArrayList<>();

        String sql = "SELECT v.vendor_id, v.vendor_name, v.contact_person, "
                + "v.email, v.phone, v.address, v.created_at, v.vendor_status, "
                + "0 AS asset_count, 0 AS total_purchase_value "
                + "FROM vendors v "
                + "WHERE v.vendor_status = 'ACTIVE' "
                + "ORDER BY v.vendor_name ASC";

        try (Connection con = DBConnection.getConnection();
             PreparedStatement ps = con.prepareStatement(sql);
             ResultSet rs = ps.executeQuery()) {

            while (rs.next()) {
                vendorList.add(mapVendor(rs));
            }
        } catch (Exception e) {
            System.err.println("[VendorDAO] getActiveVendors failed: " + e.getMessage());
            LOGGER.log(Level.SEVERE, "Exception occurred", e);
        }

        return vendorList;
    }

    public int addVendorAndReturnId(String vendorName, String contactPerson,
            String email, String phone, String address) {

        int vendorId = 0;

        String sql = "INSERT INTO vendors "
                + "(vendor_name, contact_person, email, phone, address, gst_number, vendor_status) "
                + "VALUES (?, ?, ?, ?, ?, NULL, 'ACTIVE')";

        try (Connection con = DBConnection.getConnection();
             PreparedStatement ps = con.prepareStatement(sql, Statement.RETURN_GENERATED_KEYS)) {

            ps.setString(1, clean(vendorName));
            setNullableString(ps, 2, contactPerson);
            setNullableString(ps, 3, email);
            setNullableString(ps, 4, phone);
            setNullableString(ps, 5, address);

            int rows = ps.executeUpdate();

            if (rows > 0) {
                try (ResultSet keys = ps.getGeneratedKeys()) {
                    if (keys.next()) {
                        vendorId = keys.getInt(1);
                    }
                }
            }
        } catch (Exception e) {
            System.err.println("[VendorDAO] addVendorAndReturnId failed: " + e.getMessage());
            LOGGER.log(Level.SEVERE, "Exception occurred", e);
        }

        return vendorId;
    }

    public boolean addVendor(String vendorName, String contactPerson,
            String email, String phone, String address) {
        return addVendorAndReturnId(vendorName, contactPerson, email, phone, address) > 0;
    }

    public Vendor getVendorById(int vendorId) {
        Vendor vendor = null;

        String sql = "SELECT v.vendor_id, v.vendor_name, v.contact_person, "
                + "v.email, v.phone, v.address, v.created_at, v.vendor_status, "
                + "COUNT(a.asset_id) AS asset_count, "
                + "COALESCE(SUM(a.purchase_cost), 0) AS total_purchase_value "
                + "FROM vendors v "
                + "LEFT JOIN assets a ON v.vendor_id = a.vendor_id "
                + "WHERE v.vendor_id = ? "
                + "GROUP BY v.vendor_id, v.vendor_name, v.contact_person, "
                + "v.email, v.phone, v.address, v.created_at, v.vendor_status";

        try (Connection con = DBConnection.getConnection();
             PreparedStatement ps = con.prepareStatement(sql)) {

            ps.setInt(1, vendorId);

            try (ResultSet rs = ps.executeQuery()) {
                if (rs.next()) {
                    vendor = mapVendor(rs);
                }
            }
        } catch (Exception e) {
            System.err.println("[VendorDAO] getVendorById failed: " + e.getMessage());
            LOGGER.log(Level.SEVERE, "Exception occurred", e);
        }

        return vendor;
    }

    public boolean updateVendor(int vendorId, String vendorName,
            String contactPerson, String email, String phone, String address) {

        boolean updated = false;

        String sql = "UPDATE vendors SET "
                + "vendor_name = ?, "
                + "contact_person = ?, "
                + "email = ?, "
                + "phone = ?, "
                + "address = ?, "
                + "vendor_status = 'ACTIVE', "
                + "updated_at = CURRENT_TIMESTAMP "
                + "WHERE vendor_id = ?";

        try (Connection con = DBConnection.getConnection();
             PreparedStatement ps = con.prepareStatement(sql)) {

            ps.setString(1, clean(vendorName));
            setNullableString(ps, 2, contactPerson);
            setNullableString(ps, 3, email);
            setNullableString(ps, 4, phone);
            setNullableString(ps, 5, address);
            ps.setInt(6, vendorId);

            updated = ps.executeUpdate() > 0;
        } catch (Exception e) {
            System.err.println("[VendorDAO] updateVendor failed: " + e.getMessage());
            LOGGER.log(Level.SEVERE, "Exception occurred", e);
        }

        return updated;
    }

    public int getAssetCountByVendorId(int vendorId) {
        int count = 0;

        String sql = "SELECT COUNT(*) AS total_assets FROM assets WHERE vendor_id = ?";

        try (Connection con = DBConnection.getConnection();
             PreparedStatement ps = con.prepareStatement(sql)) {

            ps.setInt(1, vendorId);

            try (ResultSet rs = ps.executeQuery()) {
                if (rs.next()) {
                    count = rs.getInt("total_assets");
                }
            }
        } catch (Exception e) {
            System.err.println("[VendorDAO] getAssetCountByVendorId failed: " + e.getMessage());
            LOGGER.log(Level.SEVERE, "Exception occurred", e);
        }

        return count;
    }

    public int getMappingCountByVendorId(int vendorId) {
        int count = 0;

        String sql = "SELECT COUNT(*) AS total_mappings FROM category_vendor_mapping WHERE vendor_id = ?";

        try (Connection con = DBConnection.getConnection();
             PreparedStatement ps = con.prepareStatement(sql)) {

            ps.setInt(1, vendorId);

            try (ResultSet rs = ps.executeQuery()) {
                if (rs.next()) {
                    count = rs.getInt("total_mappings");
                }
            }
        } catch (Exception e) {
            System.err.println("[VendorDAO] getMappingCountByVendorId failed: " + e.getMessage());
            LOGGER.log(Level.SEVERE, "Exception occurred", e);
        }

        return count;
    }

    public boolean deleteVendor(int vendorId) {
        // Official-safe behavior: do not hard-delete supplier history.
        // It only marks supplier and its category mappings inactive.
        boolean updated = false;

        String vendorSql = "UPDATE vendors SET vendor_status = 'INACTIVE', updated_at = CURRENT_TIMESTAMP WHERE vendor_id = ?";
        String mappingSql = "UPDATE category_vendor_mapping SET status = 'INACTIVE', updated_at = CURRENT_TIMESTAMP WHERE vendor_id = ?";

        try (Connection con = DBConnection.getConnection()) {
            con.setAutoCommit(false);

            try (PreparedStatement ps = con.prepareStatement(vendorSql)) {
                ps.setInt(1, vendorId);
                updated = ps.executeUpdate() > 0;
            }

            try (PreparedStatement ps = con.prepareStatement(mappingSql)) {
                ps.setInt(1, vendorId);
                ps.executeUpdate();
            }

            con.commit();
        } catch (Exception e) {
            System.err.println("[VendorDAO] deleteVendor failed: " + e.getMessage());
            LOGGER.log(Level.SEVERE, "Exception occurred", e);
        }

        return updated;
    }

    /**
     * Reverses {@link #deleteVendor}: sets vendor_status back to ACTIVE so
     * the supplier is selectable again everywhere getActiveVendors() is used
     * (the Category Supplier Mapping "Select Supplier" dropdown, in
     * particular). Deliberately does NOT touch category_vendor_mapping rows
     * the way deleteVendor()'s cascade does - reactivating a supplier should
     * not silently re-approve it for every category it happened to be mapped
     * to before it was disabled; an admin re-approves those explicitly, one
     * at a time, from the Category Supplier Mapping page, same as any other
     * new mapping.
     */
    public boolean reactivateVendor(int vendorId) {
        String sql = "UPDATE vendors SET vendor_status = 'ACTIVE', updated_at = CURRENT_TIMESTAMP WHERE vendor_id = ?";

        try (Connection con = DBConnection.getConnection();
             PreparedStatement ps = con.prepareStatement(sql)) {
            ps.setInt(1, vendorId);
            return ps.executeUpdate() > 0;
        } catch (Exception e) {
            System.err.println("[VendorDAO] reactivateVendor failed: " + e.getMessage());
            LOGGER.log(Level.SEVERE, "Exception occurred", e);
            return false;
        }
    }

    private Vendor mapVendor(ResultSet rs) throws Exception {
        Vendor vendor = new Vendor();
        vendor.setVendorId(rs.getInt("vendor_id"));
        vendor.setVendorName(rs.getString("vendor_name"));
        vendor.setContactPerson(rs.getString("contact_person"));
        vendor.setEmail(rs.getString("email"));
        vendor.setPhone(rs.getString("phone"));
        vendor.setAddress(rs.getString("address"));
        vendor.setCreatedAt(rs.getString("created_at"));
        BigDecimal total = rs.getBigDecimal("total_purchase_value");
        vendor.setAssetCount(rs.getInt("asset_count"));
        vendor.setTotalPurchaseValue(total == null ? BigDecimal.ZERO : total);
        // Fault, found live: vendor_status was already in every SELECT this
        // method serves but was never read here - see Vendor.java's status
        // field note for the user-visible symptom this caused.
        String vendorStatus = rs.getString("vendor_status");
        vendor.setStatus(vendorStatus == null || vendorStatus.trim().isEmpty() ? "ACTIVE" : vendorStatus);
        return vendor;
    }

    private void setNullableString(PreparedStatement ps, int index, String value) throws Exception {
        String cleaned = clean(value);
        if (cleaned.isEmpty()) {
            ps.setNull(index, Types.VARCHAR);
        } else {
            ps.setString(index, cleaned);
        }
    }

    private String clean(String value) {
        return value == null ? "" : value.trim();
    }
}
