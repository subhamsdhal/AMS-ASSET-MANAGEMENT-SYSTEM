package com.mycompany.asset_management_system_ams;

import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.util.ArrayList;
import java.util.List;
import java.util.logging.Level;
import java.util.logging.Logger;

public class RecentActivityDAO {

    private static final Logger LOGGER = Logger.getLogger(RecentActivityDAO.class.getName());

    private boolean queryError;

    public boolean hasQueryError() {
        return queryError;
    }

    public List<RecentActivity> getRecentActivities() {

        List<RecentActivity> list = new ArrayList<>();

        String sql = "SELECT "
                + "audit_id, "
                + "action_type AS action, "
                + "module_name AS table_name, "
                + "action_details AS remarks, "
                + "DATE_FORMAT(created_at, '%d %b %Y, %h:%i %p') AS action_time, "
                + "COALESCE(ip_address, '') AS ip_address "
                + "FROM audit_logs "
                + "ORDER BY created_at DESC, audit_id DESC "
                + "LIMIT 5";

        try (Connection con = DBConnection.getConnection()) {
            if (con == null) {
                queryError = true;
                LOGGER.warning("Recent activity query skipped because the database connection is unavailable.");
                return list;
            }

            try (PreparedStatement ps = con.prepareStatement(sql);
                 ResultSet rs = ps.executeQuery()) {

                while (rs.next()) {

                    RecentActivity activity = new RecentActivity(
                            rs.getInt("audit_id"),
                            rs.getString("action"),
                            rs.getString("table_name"),
                            rs.getString("remarks"),
                            rs.getString("action_time"),
                            rs.getString("ip_address")
                    );

                    list.add(activity);
                }
            }
        } catch (Exception e) {
            queryError = true;
            LOGGER.log(Level.WARNING, "Unable to load recent dashboard activity.", e);
        }

        return list;
    }
}
