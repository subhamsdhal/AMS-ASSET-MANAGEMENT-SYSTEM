package com.mycompany.asset_management_system_ams;

import java.io.IOException;
import java.net.URLEncoder;
import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;

import jakarta.servlet.ServletException;
import jakarta.servlet.annotation.WebServlet;
import jakarta.servlet.http.HttpServlet;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import jakarta.servlet.http.HttpSession;

@WebServlet(name = "EmergencyAdminResetServlet", urlPatterns = {"/emergency-admin-reset"})
public class EmergencyAdminResetServlet extends HttpServlet {

    @Override
    protected void doPost(HttpServletRequest request, HttpServletResponse response)
            throws ServletException, IOException {
        
        Connection con = null;
        PreparedStatement ps = null;
        ResultSet rs = null;

        try {
            HttpSession session = request.getSession(false);
            if (session == null || session.getAttribute("role") == null) {
                response.sendRedirect("login.jsp");
                return;
            }

            String role = session.getAttribute("role").toString();
            int superAdminId = (Integer) session.getAttribute("user_id");

            if (!"SUPER_ADMIN".equalsIgnoreCase(role)) {
                response.sendError(HttpServletResponse.SC_FORBIDDEN, "Only super_admin can perform emergency recovery.");
                return;
            }

            String targetUserIdStr = request.getParameter("targetUserId");
            String password = request.getParameter("password");

            if (targetUserIdStr == null || password == null || password.trim().isEmpty()) {
                response.sendError(HttpServletResponse.SC_BAD_REQUEST, "Missing required parameters.");
                return;
            }

            int targetUserId = Integer.parseInt(targetUserIdStr.trim());
            
            String fallbackRole = request.getParameter("outgoingAdminRole");
            if (fallbackRole == null || fallbackRole.trim().isEmpty()) {
                fallbackRole = "employee";
            }
            fallbackRole = fallbackRole.trim().toLowerCase();
            
            if ("admin".equals(fallbackRole) || "super_admin".equals(fallbackRole)) {
                response.sendError(HttpServletResponse.SC_BAD_REQUEST, "Invalid fallback role for outgoing admin.");
                return;
            }

            con = DBConnection.getConnection();
            con.setAutoCommit(false);

            // 1. Re-authenticate super_admin
            ps = con.prepareStatement("SELECT password_crypt FROM users WHERE user_id = ? AND current_role = 'super_admin'");
            ps.setInt(1, superAdminId);
            rs = ps.executeQuery();
            
            if (!rs.next()) {
                rs.close();
                ps.close();
                con.rollback();
                response.sendError(HttpServletResponse.SC_UNAUTHORIZED, "Super admin user not found.");
                return;
            }
            
            String storedPassword = rs.getString("password_crypt");
            rs.close();
            ps.close();

            if (!PasswordUtil.matches(password, storedPassword)) {
                con.rollback();
                response.sendError(HttpServletResponse.SC_UNAUTHORIZED, "Invalid password for emergency recovery.");
                return;
            }

            // 2. Find target user and verify they exist and are not super_admin
            ps = con.prepareStatement("SELECT current_role FROM users WHERE user_id = ?");
            ps.setInt(1, targetUserId);
            rs = ps.executeQuery();
            if (!rs.next()) {
                rs.close();
                ps.close();
                con.rollback();
                response.sendError(HttpServletResponse.SC_BAD_REQUEST, "Target user not found.");
                return;
            }
            String oldRole = rs.getString("current_role").toLowerCase();
            rs.close();
            ps.close();

            if ("super_admin".equals(oldRole)) {
                con.rollback();
                response.sendError(HttpServletResponse.SC_BAD_REQUEST, "Cannot reassign super_admin to admin.");
                return;
            }
            
            if ("admin".equals(oldRole)) {
                con.rollback();
                response.sendError(HttpServletResponse.SC_BAD_REQUEST, "Target user is already the admin.");
                return;
            }

            // 3. Demote existing admin(s)
            ps = con.prepareStatement("SELECT user_id FROM users WHERE current_role = 'admin'");
            rs = ps.executeQuery();
            java.util.List<Integer> oldAdmins = new java.util.ArrayList<>();
            while (rs.next()) {
                oldAdmins.add(rs.getInt("user_id"));
            }
            rs.close();
            ps.close();

            if (!oldAdmins.isEmpty()) {
                // Also updates role_id alongside current_role - see
                // RoleIdResolver's class doc; this and the promotion below
                // were the two role_id-staleness sources in this servlet.
                Integer fallbackRoleId = RoleIdResolver.resolveRoleId(con, fallbackRole);
                ps = con.prepareStatement("UPDATE users SET current_role = ?, role_id = ? WHERE current_role = 'admin'");
                ps.setString(1, fallbackRole);
                if (fallbackRoleId != null) {
                    ps.setInt(2, fallbackRoleId);
                } else {
                    ps.setNull(2, java.sql.Types.INTEGER);
                }
                ps.executeUpdate();
                ps.close();

                PreparedStatement psLog = con.prepareStatement("INSERT INTO role_assignment_log (assigned_to, assigned_by, old_role, new_role, is_emergency) VALUES (?, ?, ?, ?, ?)");
                for (Integer oldAdminId : oldAdmins) {
                    psLog.setInt(1, oldAdminId);
                    psLog.setInt(2, superAdminId);
                    psLog.setString(3, "admin");
                    psLog.setString(4, fallbackRole);
                    psLog.setBoolean(5, true);
                    psLog.addBatch();
                }
                psLog.executeBatch();
                psLog.close();
            }

            // 4. Promote target user to admin. Also sets role_id in the
            // same statement - see RoleIdResolver's class doc.
            Integer adminRoleId = RoleIdResolver.resolveRoleId(con, "admin");
            ps = con.prepareStatement("UPDATE users SET current_role = 'admin', role_id = ? WHERE user_id = ?");
            if (adminRoleId != null) {
                ps.setInt(1, adminRoleId);
            } else {
                ps.setNull(1, java.sql.Types.INTEGER);
            }
            ps.setInt(2, targetUserId);
            ps.executeUpdate();
            ps.close();

            // 5. Log as emergency
            ps = con.prepareStatement("INSERT INTO role_assignment_log (assigned_to, assigned_by, old_role, new_role, is_emergency) VALUES (?, ?, ?, ?, ?)");
            ps.setInt(1, targetUserId);
            ps.setInt(2, superAdminId);
            ps.setString(3, oldRole);
            ps.setString(4, "admin");
            ps.setBoolean(5, true);
            ps.executeUpdate();
            ps.close();

            con.commit();
            
            response.getWriter().write("Emergency admin reset completed successfully.");

        } catch (Exception e) {
            e.printStackTrace();
            if (con != null) {
                try {
                    con.rollback();
                } catch (Exception rbe) {
                    rbe.printStackTrace();
                }
            }
            response.sendError(HttpServletResponse.SC_INTERNAL_SERVER_ERROR, "An error occurred during emergency recovery.");
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
    }
}
