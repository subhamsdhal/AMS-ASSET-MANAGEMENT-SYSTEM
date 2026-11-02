<%@page contentType="text/html" pageEncoding="UTF-8"%>
<%@page import="com.mycompany.asset_management_system_ams.DBConnection"%>
<%@page import="com.mycompany.asset_management_system_ams.AuditDAO"%>
<%@page import="java.sql.*"%>

<%!
    private int parseInt(String value, int fallback) {
        try {
            if (value == null || value.trim().isEmpty()) {
                return fallback;
            }

            return Integer.parseInt(value.trim());
        } catch (Exception e) {
            return fallback;
        }
    }

    private int getSessionInt(HttpSession session, String key, int fallback) {
        try {
            Object value = session.getAttribute(key);

            if (value == null) {
                return fallback;
            }

            return Integer.parseInt(String.valueOf(value));
        } catch (Exception e) {
            return fallback;
        }
    }

    private boolean columnExists(Connection con, String tableName, String columnName) {
        String sql = "SELECT COUNT(*) FROM information_schema.columns "
                + "WHERE table_schema = DATABASE() AND table_name = ? AND column_name = ?";

        try (PreparedStatement ps = con.prepareStatement(sql)) {
            ps.setString(1, tableName);
            ps.setString(2, columnName);

            try (ResultSet rs = ps.executeQuery()) {
                return rs.next() && rs.getInt(1) > 0;
            }

        } catch (Exception e) {
            e.printStackTrace();
        }

        return false;
    }
%>

<%
    String username = (String) session.getAttribute("username");
    String role = (String) session.getAttribute("role");

    response.setHeader("Cache-Control", "no-cache, no-store, must-revalidate");
    response.setHeader("Pragma", "no-cache");
    response.setDateHeader("Expires", 0);

    if (username == null || role == null) {
        response.sendRedirect("login.jsp");
        return;
    }

    boolean canManageMaintenance = ("SUPER_ADMIN".equals(role) || "ADMIN".equals(role))
            || "ASSET_MANAGER".equalsIgnoreCase(role);

    if (!canManageMaintenance) {
        response.sendRedirect("maintenance.jsp?access=denied");
        return;
    }

    // This whole page performs a state change (marks an asset AVAILABLE) in
    // its scriptlet body, which - unlike a servlet's doGet/doPost split -
    // runs on ANY request method by default. Both callers (maintenance.jsp,
    // view_maintenance.jsp) now submit this as a POST form instead of a plain
    // <a href> link, but this guard is the actual control: without it, a
    // simple GET (an <img> tag, a crawler, browser link-prefetch) could
    // silently resolve a maintenance record and put a possibly-still-broken
    // asset back into circulation for whichever admin/asset-manager had it
    // loaded while logged in.
    if (!"POST".equalsIgnoreCase(request.getMethod())) {
        response.sendRedirect("maintenance.jsp?error=method_not_allowed");
        return;
    }

    int maintenanceId = parseInt(request.getParameter("id"), 0);
    int userId = getSessionInt(session, "user_id", 1);

    if (userId == 1) {
        userId = getSessionInt(session, "userId", 1);
    }

    if (maintenanceId <= 0) {
        response.sendRedirect("maintenance.jsp?error=invalid");
        return;
    }

    Connection con = null;

    try {
        con = DBConnection.getConnection();
        con.setAutoCommit(false);

        int assetId = 0;
        String assetStatus = "";

        String readSql = "SELECT ml.asset_id, a.asset_status "
                + "FROM maintenance_logs ml "
                + "JOIN assets a ON ml.asset_id = a.asset_id "
                + "WHERE ml.maintenance_id = ? "
                + "FOR UPDATE";

        try (PreparedStatement ps = con.prepareStatement(readSql)) {
            ps.setInt(1, maintenanceId);

            try (ResultSet rs = ps.executeQuery()) {
                if (rs.next()) {
                    assetId = rs.getInt("asset_id");
                    assetStatus = rs.getString("asset_status");
                }
            }
        }

        if (assetId <= 0) {
            con.rollback();
            response.sendRedirect("maintenance.jsp?error=notfound");
            return;
        }

        if ("AVAILABLE".equalsIgnoreCase(assetStatus)) {
            con.rollback();
            response.sendRedirect("maintenance.jsp?success=already_resolved");
            return;
        }

        if ("DISPOSED".equalsIgnoreCase(assetStatus)) {
            con.rollback();
            response.sendRedirect("maintenance.jsp?error=disposed");
            return;
        }

        String updateAssetSql = "UPDATE assets SET asset_status = 'AVAILABLE' WHERE asset_id = ?";

        try (PreparedStatement ps = con.prepareStatement(updateAssetSql)) {
            ps.setInt(1, assetId);
            ps.executeUpdate();
        }

        boolean hasMaintenanceStatus = columnExists(con, "maintenance_logs", "maintenance_status");
        boolean hasWorkDone = columnExists(con, "maintenance_logs", "work_done");
        boolean hasRemarks = columnExists(con, "maintenance_logs", "remarks");
        boolean hasUpdatedAt = columnExists(con, "maintenance_logs", "updated_at");

        StringBuilder updateLogSql = new StringBuilder("UPDATE maintenance_logs SET maintenance_id = maintenance_id");

        if (hasMaintenanceStatus) {
            updateLogSql.append(", maintenance_status = 'COMPLETED'");
        }

        if (hasWorkDone) {
            updateLogSql.append(", work_done = CASE WHEN work_done IS NULL OR work_done = '' THEN 'Maintenance resolved and asset marked available.' ELSE work_done END");
        }

        if (hasRemarks) {
            updateLogSql.append(", remarks = CONCAT(COALESCE(remarks, ''), CASE WHEN COALESCE(remarks, '') = '' THEN '' ELSE ' | ' END, 'Resolved by: ").append(username.replace("'", "''")).append("')");
        }

        if (hasUpdatedAt) {
            updateLogSql.append(", updated_at = CURRENT_TIMESTAMP");
        }

        updateLogSql.append(" WHERE maintenance_id = ?");

        try (PreparedStatement ps = con.prepareStatement(updateLogSql.toString())) {
            ps.setInt(1, maintenanceId);
            ps.executeUpdate();
        }

        con.commit();

        AuditDAO.log(
                userId,
                "RESOLVE",
                "maintenance_logs",
                maintenanceId,
                "Maintenance resolved. Asset ID: " + assetId + ", Resolved by: " + username
        );

        response.sendRedirect("maintenance.jsp?success=resolved");

    } catch (Exception e) {
        e.printStackTrace();

        try {
            if (con != null) {
                con.rollback();
            }
        } catch (Exception ex) {
            ex.printStackTrace();
        }

        response.sendRedirect("maintenance.jsp?error=server");

    } finally {
        try {
            if (con != null) {
                con.setAutoCommit(true);
                con.close();
            }
        } catch (Exception e) {
            e.printStackTrace();
        }
    }
%>