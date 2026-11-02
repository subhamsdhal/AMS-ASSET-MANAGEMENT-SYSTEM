package com.mycompany.asset_management_system_ams;

import java.sql.Connection;
import java.sql.Statement;

public class UpdateSchema {
    public static void main(String[] args) {
        try (Connection con = DBConnection.getConnection();
             Statement stmt = con.createStatement()) {
            String sql = "ALTER TABLE employees ADD COLUMN profile_image_path VARCHAR(255) NULL";
            stmt.executeUpdate(sql);
            System.out.println("Column added successfully.");
        } catch (Exception e) {
            e.printStackTrace();
        }
    }
}
