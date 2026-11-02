package com.mycompany.asset_management_system_ams;

import java.io.IOException;
import java.io.PrintWriter;
import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.util.ArrayList;
import java.util.List;
import jakarta.servlet.ServletException;
import jakarta.servlet.annotation.WebServlet;
import jakarta.servlet.http.HttpServlet;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import jakarta.servlet.http.HttpSession;

@WebServlet(name = "AssetSearchServlet", urlPatterns = {"/AssetSearchServlet"})
public class AssetSearchServlet extends HttpServlet {

    @Override
    protected void doGet(HttpServletRequest request, HttpServletResponse response)
            throws ServletException, IOException {

        response.setContentType("application/json");
        response.setCharacterEncoding("UTF-8");

        HttpSession session = request.getSession(false);
        if (session == null || session.getAttribute("username") == null) {
            response.setStatus(HttpServletResponse.SC_UNAUTHORIZED);
            response.getWriter().write("{\"error\": \"Unauthorized\"}");
            return;
        }

        String query = request.getParameter("q");
        if (query == null) {
            query = "";
        }
        query = query.trim();

        // Optional: physical_verification_duties' own picker (my_physical_verification_
        // duties.jsp) passes the duty currently selected so an asset already reported
        // under it doesn't show up again for a fresh batch - re-selecting it there would
        // silently overwrite the earlier report (AddPhysicalVerificationServlet matches
        // and updates by round+duty+asset) with no warning shown anywhere. Genuinely
        // correcting an existing report still goes through that page's own explicit
        // "Edit" button on the report itself, not through this picker. Every other
        // caller of this servlet omits the parameter, so this is a no-op for them.
        int excludeDutyId = 0;
        try {
            String excludeDutyIdParam = request.getParameter("excludeDutyId");
            if (excludeDutyIdParam != null && !excludeDutyIdParam.trim().isEmpty()) {
                excludeDutyId = Integer.parseInt(excludeDutyIdParam.trim());
            }
        } catch (NumberFormatException e) {
            excludeDutyId = 0;
        }

        int page = 1;
        try {
            String pageParam = request.getParameter("page");
            if (pageParam != null && !pageParam.isEmpty()) {
                page = Integer.parseInt(pageParam);
            }
        } catch (NumberFormatException e) {
            page = 1;
        }

        int pageSize = 20;
        int offset = (page - 1) * pageSize;

        try (Connection con = DBConnection.getConnection(); PrintWriter out = response.getWriter()) {
            // Basic check for tables
            boolean hasAssets = tableExists(con, "assets");
            if (!hasAssets) {
                out.write("{\"results\": []}");
                return;
            }

            boolean hasAssetCode = columnExists(con, "assets", "asset_code");
            boolean hasAssetName = columnExists(con, "assets", "asset_name");
            boolean hasRailwayAssetNo = columnExists(con, "assets", "railway_asset_no");
            boolean hasCategoryId = columnExists(con, "assets", "category_id");
            boolean hasCategories = tableExists(con, "asset_categories");
            boolean hasCategoryName = hasCategories && columnExists(con, "asset_categories", "category_name");
            boolean hasRailwayLocations = tableExists(con, "railway_locations");
            boolean hasRailwayLocationId = columnExists(con, "assets", "railway_location_id");
            boolean hasLocationId = columnExists(con, "assets", "location_id");
            boolean hasAssetLocationText = columnExists(con, "assets", "location");
            boolean hasLocationName = hasRailwayLocations && columnExists(con, "railway_locations", "location_name");

            String assetCodeExpr = hasAssetCode ? "COALESCE(a.asset_code, '')" : "''";
            String assetNameExpr = hasAssetName ? "COALESCE(a.asset_name, '')" : "''";
            String railwayAssetNoExpr = hasRailwayAssetNo ? "COALESCE(a.railway_asset_no, '')" : "''";
            String categoryNameExpr = hasCategoryName ? "COALESCE(ac.category_name, 'Uncategorized')" : "'Uncategorized'";

            String assetLocationTextExpression = hasAssetLocationText ? "COALESCE(a.location, '')" : "''";
            String locationJoin = "";
            String locationNameExpression = assetLocationTextExpression;

            if (hasLocationName && hasRailwayLocationId) {
                locationJoin = "LEFT JOIN railway_locations rl ON a.railway_location_id = rl.location_id ";
                locationNameExpression = "COALESCE(rl.location_name, " + assetLocationTextExpression + ")";
            } else if (hasLocationName && hasLocationId) {
                locationJoin = "LEFT JOIN railway_locations rl ON a.location_id = rl.location_id ";
                locationNameExpression = "COALESCE(rl.location_name, " + assetLocationTextExpression + ")";
            }

            StringBuilder sql = new StringBuilder();
            sql.append("SELECT a.asset_id, ")
               .append(assetCodeExpr).append(" AS asset_code, ")
               .append(assetNameExpr).append(" AS asset_name, ")
               .append(railwayAssetNoExpr).append(" AS railway_asset_no, ")
               .append(categoryNameExpr).append(" AS category_name, ")
               .append(locationNameExpression).append(" AS location_name ")
               .append("FROM assets a ");

            if (hasCategories && hasCategoryId && hasCategoryName) {
                sql.append("LEFT JOIN asset_categories ac ON a.category_id = ac.category_id ");
            }
            sql.append(locationJoin);

            StringBuilder whereClause = new StringBuilder("WHERE 1=1 ");
            List<Object> params = new ArrayList<>();

            if (!query.isEmpty()) {
                whereClause.append("AND (");
                boolean added = false;
                if (hasAssetCode) {
                    whereClause.append("a.asset_code LIKE ?");
                    params.add("%" + query + "%");
                    added = true;
                }
                if (hasAssetName) {
                    if (added) whereClause.append(" OR ");
                    whereClause.append("a.asset_name LIKE ?");
                    params.add("%" + query + "%");
                    added = true;
                }
                if (hasRailwayAssetNo) {
                    if (added) whereClause.append(" OR ");
                    whereClause.append("a.railway_asset_no LIKE ?");
                    params.add("%" + query + "%");
                    added = true;
                }
                if (added) {
                    whereClause.append(") ");
                } else {
                    whereClause = new StringBuilder("WHERE 1=1 ");
                    params.clear();
                }
            }

            if (excludeDutyId > 0
                    && tableExists(con, "asset_physical_verification")
                    && columnExists(con, "asset_physical_verification", "duty_id")) {
                whereClause.append("AND a.asset_id NOT IN (SELECT asset_id FROM asset_physical_verification WHERE duty_id = ?) ");
                params.add(excludeDutyId);
            }

            sql.append(whereClause);
            sql.append("ORDER BY a.asset_id ASC LIMIT ? OFFSET ?");
            
            params.add(pageSize);
            params.add(offset);

            StringBuilder json = new StringBuilder();
            json.append("{\"results\": [");

            boolean first = true;
            try (PreparedStatement ps = con.prepareStatement(sql.toString())) {
                for (int i = 0; i < params.size(); i++) {
                    ps.setObject(i + 1, params.get(i));
                }

                try (ResultSet rs = ps.executeQuery()) {
                    while (rs.next()) {
                        if (!first) {
                            json.append(",");
                        }
                        first = false;
                        
                        int assetId = rs.getInt("asset_id");
                        String code = escapeJson(rs.getString("asset_code"));
                        String name = escapeJson(rs.getString("asset_name"));
                        String cat = escapeJson(rs.getString("category_name"));
                        String loc = escapeJson(rs.getString("location_name"));
                        
                        String text = code + " - " + name + " | " + cat + " | " + loc;
                        
                        json.append("{\"id\": \"").append(assetId).append("\", \"text\": \"").append(text).append("\"}");
                    }
                }
            }

            // check if there's more pages
            String countSql = "SELECT COUNT(*) FROM assets a ";
            if (hasCategories && hasCategoryId && hasCategoryName) {
                countSql += "LEFT JOIN asset_categories ac ON a.category_id = ac.category_id ";
            }
            countSql += locationJoin + whereClause.toString();
            
            int total = 0;
            try (PreparedStatement psCount = con.prepareStatement(countSql)) {
                for (int i = 0; i < params.size() - 2; i++) { // exclude limit and offset
                    psCount.setObject(i + 1, params.get(i));
                }
                try (ResultSet rsCount = psCount.executeQuery()) {
                    if (rsCount.next()) {
                        total = rsCount.getInt(1);
                    }
                }
            }

            boolean more = (offset + pageSize) < total;
            json.append("], \"pagination\": {\"more\": ").append(more).append("}}");
            
            out.write(json.toString());
            
        } catch (Exception e) {
            e.printStackTrace();
            response.setStatus(HttpServletResponse.SC_INTERNAL_SERVER_ERROR);
            response.getWriter().write("{\"error\": \"Server error\"}");
        }
    }

    private String escapeJson(String s) {
        if (s == null) return "";
        return s.replace("\\", "\\\\")
                .replace("\"", "\\\"")
                .replace("\b", "\\b")
                .replace("\f", "\\f")
                .replace("\n", "\\n")
                .replace("\r", "\\r")
                .replace("\t", "\\t");
    }

    private boolean tableExists(Connection con, String tableName) {
        String sql = "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = DATABASE() AND table_name = ?";
        try (PreparedStatement ps = con.prepareStatement(sql)) {
            ps.setString(1, tableName);
            try (ResultSet rs = ps.executeQuery()) {
                return rs.next() && rs.getInt(1) > 0;
            }
        } catch (Exception e) { e.printStackTrace(); }
        return false;
    }

    private boolean columnExists(Connection con, String tableName, String columnName) {
        String sql = "SELECT COUNT(*) FROM information_schema.columns WHERE table_schema = DATABASE() AND table_name = ? AND column_name = ?";
        try (PreparedStatement ps = con.prepareStatement(sql)) {
            ps.setString(1, tableName);
            ps.setString(2, columnName);
            try (ResultSet rs = ps.executeQuery()) {
                return rs.next() && rs.getInt(1) > 0;
            }
        } catch (Exception e) { e.printStackTrace(); }
        return false;
    }
}
