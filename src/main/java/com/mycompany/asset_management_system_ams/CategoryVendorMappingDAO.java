package com.mycompany.asset_management_system_ams;

import java.util.logging.Logger;
import java.util.logging.Level;


import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.util.ArrayList;
import java.util.List;

public class CategoryVendorMappingDAO {
    private static final Logger LOGGER = Logger.getLogger(CategoryVendorMappingDAO.class.getName());


    public List<CategoryVendorMapping> getAllMappings() {
        List<CategoryVendorMapping> mappingList = new ArrayList<>();

        String sql = "SELECT m.mapping_id, m.category_id, c.category_name, "
                + "m.vendor_id, v.vendor_name, m.status, m.created_at, "
                + "COALESCE(a.asset_count, 0) AS linked_asset_count "
                + "FROM category_vendor_mapping m "
                + "JOIN asset_categories c ON m.category_id = c.category_id "
                + "JOIN vendors v ON m.vendor_id = v.vendor_id "
                + "LEFT JOIN (SELECT category_id, vendor_id, COUNT(*) AS asset_count FROM assets GROUP BY category_id, vendor_id) a "
                + "ON a.category_id = m.category_id AND a.vendor_id = m.vendor_id "
                + "ORDER BY c.category_name ASC, v.vendor_name ASC";

        try (Connection con = DBConnection.getConnection();
             PreparedStatement ps = con.prepareStatement(sql);
             ResultSet rs = ps.executeQuery()) {

            while (rs.next()) {
                mappingList.add(mapMapping(rs));
            }
        } catch (Exception e) {
            System.err.println("[CategoryVendorMappingDAO] getAllMappings failed: " + e.getMessage());
            LOGGER.log(Level.SEVERE, "Exception occurred", e);
        }

        return mappingList;
    }

    public boolean addOrReactivateMapping(int categoryId, int vendorId) {
        boolean saved = false;

        String sql = "INSERT INTO category_vendor_mapping "
                + "(category_id, vendor_id, status) "
                + "VALUES (?, ?, 'ACTIVE') "
                + "ON DUPLICATE KEY UPDATE status = 'ACTIVE', updated_at = CURRENT_TIMESTAMP";

        try (Connection con = DBConnection.getConnection();
             PreparedStatement ps = con.prepareStatement(sql)) {

            ps.setInt(1, categoryId);
            ps.setInt(2, vendorId);

            saved = ps.executeUpdate() > 0;
        } catch (Exception e) {
            System.err.println("[CategoryVendorMappingDAO] addOrReactivateMapping failed: " + e.getMessage());
            LOGGER.log(Level.SEVERE, "Exception occurred", e);
        }

        return saved;
    }

    public boolean updateMappingStatus(int mappingId, String status) {
        boolean updated = false;

        String normalizedStatus = normalizeStatus(status);

        String sql = "UPDATE category_vendor_mapping SET status = ?, updated_at = CURRENT_TIMESTAMP WHERE mapping_id = ?";

        try (Connection con = DBConnection.getConnection();
             PreparedStatement ps = con.prepareStatement(sql)) {

            ps.setString(1, normalizedStatus);
            ps.setInt(2, mappingId);

            updated = ps.executeUpdate() > 0;
        } catch (Exception e) {
            System.err.println("[CategoryVendorMappingDAO] updateMappingStatus failed: " + e.getMessage());
            LOGGER.log(Level.SEVERE, "Exception occurred", e);
        }

        return updated;
    }

    public CategoryVendorMapping getMappingById(int mappingId) {
        CategoryVendorMapping mapping = null;

        String sql = "SELECT m.mapping_id, m.category_id, c.category_name, "
                + "m.vendor_id, v.vendor_name, m.status, m.created_at, "
                + "COALESCE(a.asset_count, 0) AS linked_asset_count "
                + "FROM category_vendor_mapping m "
                + "JOIN asset_categories c ON m.category_id = c.category_id "
                + "JOIN vendors v ON m.vendor_id = v.vendor_id "
                + "LEFT JOIN (SELECT category_id, vendor_id, COUNT(*) AS asset_count FROM assets GROUP BY category_id, vendor_id) a "
                + "ON a.category_id = m.category_id AND a.vendor_id = m.vendor_id "
                + "WHERE m.mapping_id = ?";

        try (Connection con = DBConnection.getConnection();
             PreparedStatement ps = con.prepareStatement(sql)) {

            ps.setInt(1, mappingId);

            try (ResultSet rs = ps.executeQuery()) {
                if (rs.next()) {
                    mapping = mapMapping(rs);
                }
            }
        } catch (Exception e) {
            System.err.println("[CategoryVendorMappingDAO] getMappingById failed: " + e.getMessage());
            LOGGER.log(Level.SEVERE, "Exception occurred", e);
        }

        return mapping;
    }

    public int getActiveMappingCount() {
        return getMappingCountByStatus("ACTIVE");
    }

    public int getInactiveMappingCount() {
        return getMappingCountByStatus("INACTIVE");
    }

    public boolean isActiveSupplierMappedToCategory(int categoryId, int vendorId) {
        boolean mapped = false;

        String sql = "SELECT COUNT(*) AS total FROM category_vendor_mapping "
                + "WHERE category_id = ? AND vendor_id = ? AND status = 'ACTIVE'";

        try (Connection con = DBConnection.getConnection();
             PreparedStatement ps = con.prepareStatement(sql)) {

            ps.setInt(1, categoryId);
            ps.setInt(2, vendorId);

            try (ResultSet rs = ps.executeQuery()) {
                if (rs.next()) {
                    mapped = rs.getInt("total") > 0;
                }
            }
        } catch (Exception e) {
            System.err.println("[CategoryVendorMappingDAO] isActiveSupplierMappedToCategory failed: " + e.getMessage());
            LOGGER.log(Level.SEVERE, "Exception occurred", e);
        }

        return mapped;
    }

    public String getMappingStatus(int categoryId, int vendorId) {
        String status = null;
        String sql = "SELECT status FROM category_vendor_mapping WHERE category_id = ? AND vendor_id = ?";
        try (Connection con = DBConnection.getConnection();
             PreparedStatement ps = con.prepareStatement(sql)) {
            ps.setInt(1, categoryId);
            ps.setInt(2, vendorId);
            try (ResultSet rs = ps.executeQuery()) {
                if (rs.next()) {
                    status = rs.getString("status");
                }
            }
        } catch (Exception e) {
            System.err.println("[CategoryVendorMappingDAO] getMappingStatus failed: " + e.getMessage());
            LOGGER.log(Level.SEVERE, "Exception occurred", e);
        }
        return status;
    }

    private int getMappingCountByStatus(String status) {
        int count = 0;

        String sql = "SELECT COUNT(*) AS total FROM category_vendor_mapping WHERE status = ?";

        try (Connection con = DBConnection.getConnection();
             PreparedStatement ps = con.prepareStatement(sql)) {

            ps.setString(1, status);

            try (ResultSet rs = ps.executeQuery()) {
                if (rs.next()) {
                    count = rs.getInt("total");
                }
            }
        } catch (Exception e) {
            System.err.println("[CategoryVendorMappingDAO] isActiveSupplierMappedToCategory failed: " + e.getMessage());
            LOGGER.log(Level.SEVERE, "Exception occurred", e);
        }

        return count;
    }

    private CategoryVendorMapping mapMapping(ResultSet rs) throws Exception {
        CategoryVendorMapping mapping = new CategoryVendorMapping();
        mapping.setMappingId(rs.getInt("mapping_id"));
        mapping.setCategoryId(rs.getInt("category_id"));
        mapping.setCategoryName(rs.getString("category_name"));
        mapping.setVendorId(rs.getInt("vendor_id"));
        mapping.setVendorName(rs.getString("vendor_name"));
        mapping.setStatus(rs.getString("status"));
        mapping.setCreatedAt(rs.getString("created_at"));
        mapping.setLinkedAssetCount(rs.getInt("linked_asset_count"));
        return mapping;
    }

    private String normalizeStatus(String value) {
        if (value == null) {
            return "ACTIVE";
        }
        String cleaned = value.trim().toUpperCase();
        if ("ENABLE".equals(cleaned) || "ENABLED".equals(cleaned) || "ACTIVE".equals(cleaned)) {
            return "ACTIVE";
        }
        return "INACTIVE";
    }
}
