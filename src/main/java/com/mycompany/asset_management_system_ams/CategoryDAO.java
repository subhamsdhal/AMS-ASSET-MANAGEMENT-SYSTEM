package com.mycompany.asset_management_system_ams;

import java.util.logging.Logger;
import java.util.logging.Level;


import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.Statement;
import java.util.ArrayList;
import java.util.List;

public class CategoryDAO {
    private static final Logger LOGGER = Logger.getLogger(CategoryDAO.class.getName());


    public List<Category> getAllCategories() {
        List<Category> categoryList = new ArrayList<>();

        String sql = "SELECT c.category_id, c.category_name, c.description, "
                + "c.created_at, "
                + "CASE WHEN c.status = 'ACTIVE' THEN 'YES' ELSE 'NO' END AS is_active, "
                + "(SELECT COUNT(*) FROM assets a WHERE a.category_id = c.category_id) AS asset_count, "
                + "(SELECT COUNT(*) FROM asset_requests ar WHERE ar.category_id = c.category_id) AS request_count "
                + "FROM asset_categories c "
                + "ORDER BY c.category_id ASC";

        try (Connection con = DBConnection.getConnection();
             PreparedStatement ps = con.prepareStatement(sql);
             ResultSet rs = ps.executeQuery()) {

            while (rs.next()) {
                Category category = mapCategory(rs);
                categoryList.add(category);
            }
        } catch (Exception e) {
            System.err.println("[CategoryDAO] getAllCategories failed: " + e.getMessage());
            LOGGER.log(Level.SEVERE, "Exception occurred", e);
        }

        return categoryList;
    }

    public List<Category> getActiveCategories() {
        List<Category> categoryList = new ArrayList<>();

        String sql = "SELECT category_id, category_name, description, created_at, "
                + "CASE WHEN status = 'ACTIVE' THEN 'YES' ELSE 'NO' END AS is_active, "
                + "0 AS asset_count, 0 AS request_count "
                + "FROM asset_categories "
                + "WHERE status = 'ACTIVE' "
                + "ORDER BY category_name ASC";

        try (Connection con = DBConnection.getConnection();
             PreparedStatement ps = con.prepareStatement(sql);
             ResultSet rs = ps.executeQuery()) {

            while (rs.next()) {
                categoryList.add(mapCategory(rs));
            }
        } catch (Exception e) {
            System.err.println("[CategoryDAO] getActiveCategories failed: " + e.getMessage());
            LOGGER.log(Level.SEVERE, "Exception occurred", e);
        }

        return categoryList;
    }

    public Category getCategoryById(int categoryId) {
        Category category = null;

        String sql = "SELECT c.category_id, c.category_name, c.description, "
                + "c.created_at, "
                + "CASE WHEN c.status = 'ACTIVE' THEN 'YES' ELSE 'NO' END AS is_active, "
                + "(SELECT COUNT(*) FROM assets a WHERE a.category_id = c.category_id) AS asset_count, "
                + "(SELECT COUNT(*) FROM asset_requests ar WHERE ar.category_id = c.category_id) AS request_count "
                + "FROM asset_categories c "
                + "WHERE c.category_id = ?";

        try (Connection con = DBConnection.getConnection();
             PreparedStatement ps = con.prepareStatement(sql)) {

            ps.setInt(1, categoryId);

            try (ResultSet rs = ps.executeQuery()) {
                if (rs.next()) {
                    category = mapCategory(rs);
                }
            }
        } catch (Exception e) {
            System.err.println("[CategoryDAO] getCategoryById failed: " + e.getMessage());
            LOGGER.log(Level.SEVERE, "Exception occurred", e);
        }

        return category;
    }

    public int addCategoryAndReturnId(String categoryName, String description) {
        int categoryId = 0;

        String sql = "INSERT INTO asset_categories "
                + "(category_name, description, useful_life_years, default_depreciation_rate, status, is_active) "
                + "VALUES (?, ?, 5, 0.00, 'ACTIVE', 'YES')";

        try (Connection con = DBConnection.getConnection();
             PreparedStatement ps = con.prepareStatement(sql, Statement.RETURN_GENERATED_KEYS)) {

            ps.setString(1, clean(categoryName));
            ps.setString(2, clean(description));

            int rows = ps.executeUpdate();

            if (rows > 0) {
                try (ResultSet keys = ps.getGeneratedKeys()) {
                    if (keys.next()) {
                        categoryId = keys.getInt(1);
                    }
                }
            }
        } catch (Exception e) {
            System.err.println("[CategoryDAO] addCategoryAndReturnId failed: " + e.getMessage());
            LOGGER.log(Level.SEVERE, "Exception occurred", e);
        }

        return categoryId;
    }

    public boolean addCategory(String categoryName, String description) {
        return addCategoryAndReturnId(categoryName, description) > 0;
    }

    public boolean updateCategory(int categoryId, String categoryName, String description, String isActive) {
        boolean updated = false;

        String normalizedActive = normalizeYesNo(isActive);
        String status = "YES".equals(normalizedActive) ? "ACTIVE" : "INACTIVE";

        String sql = "UPDATE asset_categories SET "
                + "category_name = ?, "
                + "description = ?, "
                + "status = ?, "
                + "is_active = ?, "
                + "updated_at = CURRENT_TIMESTAMP "
                + "WHERE category_id = ?";

        try (Connection con = DBConnection.getConnection();
             PreparedStatement ps = con.prepareStatement(sql)) {

            ps.setString(1, clean(categoryName));
            ps.setString(2, clean(description));
            ps.setString(3, status);
            ps.setString(4, normalizedActive);
            ps.setInt(5, categoryId);

            updated = ps.executeUpdate() > 0;
        } catch (Exception e) {
            System.err.println("[CategoryDAO] updateCategory failed: " + e.getMessage());
            LOGGER.log(Level.SEVERE, "Exception occurred", e);
        }

        return updated;
    }

    public boolean updateCategoryStatus(int categoryId, String isActive) {
        boolean updated = false;

        String normalizedActive = normalizeYesNo(isActive);
        String status = "YES".equals(normalizedActive) ? "ACTIVE" : "INACTIVE";

        String sql = "UPDATE asset_categories SET "
                + "status = ?, "
                + "is_active = ?, "
                + "updated_at = CURRENT_TIMESTAMP "
                + "WHERE category_id = ?";

        try (Connection con = DBConnection.getConnection();
             PreparedStatement ps = con.prepareStatement(sql)) {

            ps.setString(1, status);
            ps.setString(2, normalizedActive);
            ps.setInt(3, categoryId);

            updated = ps.executeUpdate() > 0;
        } catch (Exception e) {
            System.err.println("[CategoryDAO] updateCategoryStatus failed: " + e.getMessage());
            LOGGER.log(Level.SEVERE, "Exception occurred", e);
        }

        return updated;
    }

    public int getAssetCountByCategoryId(int categoryId) {
        int count = 0;

        String sql = "SELECT COUNT(*) AS total_assets FROM assets WHERE category_id = ?";

        try (Connection con = DBConnection.getConnection();
             PreparedStatement ps = con.prepareStatement(sql)) {

            ps.setInt(1, categoryId);

            try (ResultSet rs = ps.executeQuery()) {
                if (rs.next()) {
                    count = rs.getInt("total_assets");
                }
            }
        } catch (Exception e) {
            System.err.println("[CategoryDAO] getAssetCountByCategoryId failed: " + e.getMessage());
            LOGGER.log(Level.SEVERE, "Exception occurred", e);
        }

        return count;
    }

    private Category mapCategory(ResultSet rs) throws Exception {
        Category category = new Category();
        category.setCategoryId(rs.getInt("category_id"));
        category.setCategoryName(rs.getString("category_name"));
        category.setDescription(rs.getString("description"));
        category.setCreatedAt(rs.getString("created_at"));
        category.setIsActive(rs.getString("is_active"));
        category.setAssetCount(rs.getInt("asset_count"));
        category.setRequestCount(rs.getInt("request_count"));
        return category;
    }

    private String normalizeYesNo(String value) {
        if (value == null) {
            return "YES";
        }
        String cleaned = value.trim().toUpperCase();
        if ("ACTIVE".equals(cleaned) || "YES".equals(cleaned) || "1".equals(cleaned) || "TRUE".equals(cleaned)) {
            return "YES";
        }
        return "NO";
    }

    private String clean(String value) {
        return value == null ? "" : value.trim();
    }
}
