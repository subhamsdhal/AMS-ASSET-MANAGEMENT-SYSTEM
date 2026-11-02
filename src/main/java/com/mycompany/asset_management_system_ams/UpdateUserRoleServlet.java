package com.mycompany.asset_management_system_ams;

import java.io.IOException;
import java.net.URLEncoder;
import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.util.Arrays;
import java.util.HashSet;
import java.util.Set;

import jakarta.servlet.ServletException;
import jakarta.servlet.annotation.WebServlet;
import jakarta.servlet.http.HttpServlet;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import jakarta.servlet.http.HttpSession;

@WebServlet(name = "UpdateUserRoleServlet", urlPatterns = {"/UpdateUserRoleServlet"})
public class UpdateUserRoleServlet extends HttpServlet {

    // Every literal users.current_role's enum actually accepts. super_admin
    // is included here (a syntactically valid enum value) - it is rejected
    // separately, further down, by its own dedicated
    // cannot_modify_super_admin/cannot_assign_super_admin checks, which give
    // a more specific error than a generic "invalid" would.
    private static final Set<String> VALID_ROLES = new HashSet<>(Arrays.asList(
            "super_admin", "admin", "asset_manager", "auditor", "dept_head", "employee"));

    @Override
    protected void doPost(HttpServletRequest request, HttpServletResponse response)
            throws ServletException, IOException {

        Connection con = null;
        PreparedStatement ps = null;
        ResultSet rs = null;

        try {
            request.setCharacterEncoding("UTF-8");

            HttpSession session = request.getSession(false);

            if (session == null
                    || session.getAttribute("username") == null
                    || session.getAttribute("role") == null) {
                response.sendRedirect("login.jsp");
                return;
            }

            String adminUsername = session.getAttribute("username").toString();
            String adminRole = session.getAttribute("role").toString();
            int adminUserId = (Integer) session.getAttribute("user_id"); // assuming user_id is in session, if not we need it. Let's fetch it if missing.

            // Only ADMIN can perform routine role management
            if (!"ADMIN".equalsIgnoreCase(adminRole) && !"SUPER_ADMIN".equalsIgnoreCase(adminRole)) {
                response.sendRedirect("settings.jsp?access=denied");
                return;
            }

            String userIdText = request.getParameter("userId");
            String newRole = request.getParameter("newRole"); // Expected: super_admin, admin, asset_manager, auditor, dept_head, employee
            String status = request.getParameter("status"); 

            if (userIdText == null || newRole == null || userIdText.trim().isEmpty() || newRole.trim().isEmpty()) {
                response.sendRedirect("manage_roles.jsp?error=invalid");
                return;
            }
            newRole = newRole.trim().toLowerCase();

            // Fault, found live: nothing here ever validated newRole against
            // the actual current_role enum values before using it in an
            // UPDATE - manage_roles.jsp's own dropdown was independently
            // found to sometimes send a value ("department_head") that
            // matches none of them (see RoleIdResolver.toEnumRoleValue's
            // doc, now fixed at that source too). This endpoint accepts a
            // direct POST from any ADMIN/SUPER_ADMIN session regardless of
            // the UI (already established by the self-modification finding
            // above), so the UI sending the right value is not enough on its
            // own - this whitelist is the server-side half of that same
            // defense-in-depth this codebase applies everywhere else.
            if (!VALID_ROLES.contains(newRole)) {
                response.sendRedirect("manage_roles.jsp?error=invalid");
                return;
            }

            String fallbackRole = request.getParameter("outgoingAdminRole");
            if (fallbackRole == null || fallbackRole.trim().isEmpty()) {
                fallbackRole = "employee";
            }
            fallbackRole = fallbackRole.trim().toLowerCase();
            if (!VALID_ROLES.contains(fallbackRole)) {
                response.sendRedirect("manage_roles.jsp?error=invalid_fallback");
                return;
            }

            if ("admin".equals(newRole) && 
                ("admin".equals(fallbackRole) || "super_admin".equals(fallbackRole))) {
                response.sendRedirect("manage_roles.jsp?error=invalid_fallback");
                return;
            }
            
            if (status == null) status = "ACTIVE";
            status = status.toUpperCase();

            int targetUserId;
            try {
                targetUserId = Integer.parseInt(userIdText.trim());
            } catch (Exception numberException) {
                response.sendRedirect("manage_roles.jsp?error=invalid");
                return;
            }

            // Fault (Critical, fixed): nothing below this point ever compared
            // targetUserId to the acting admin's own id, so a direct POST to
            // this servlet could change the caller's own role/status with no
            // server-side check at all - manage_roles.jsp only ever hid the
            // edit form for the admin's own row (isCurrentUser) and had a
            // dead "self" error branch that no code path ever triggered. This
            // is that missing check, placed before any DB work so a
            // self-modification attempt never even opens a transaction.
            if (targetUserId == adminUserId) {
                response.sendRedirect("manage_roles.jsp?error=self");
                return;
            }

            con = DBConnection.getConnection();
            con.setAutoCommit(false); // Start Transaction

            String targetUsername = null;
            String oldRole = null;

            ps = con.prepareStatement("SELECT username, current_role FROM users WHERE user_id = ?");
            ps.setInt(1, targetUserId);
            rs = ps.executeQuery();
            if (rs.next()) {
                targetUsername = rs.getString("username");
                oldRole = rs.getString("current_role").toLowerCase();
            } else {
                rs.close();
                ps.close();
                con.rollback();
                response.sendRedirect("manage_roles.jsp?error=invalid");
                return;
            }
            rs.close();
            ps.close();

            // Zero-Admin / Self-Escalation Safeguards
            // Fault (Critical, fixed): this used to check the TARGET USERNAME
            // string against the literal "super_admin" instead of the
            // target's actual current_role. That protects the real Super
            // Admin account only if it happens to still be named literally
            // "super_admin" - rename it, or seed a second super_admin-role
            // account under a different username (nothing in the schema
            // prevents either), and this check silently stopped applying,
            // letting a plain ADMIN change that account's role to anything,
            // including "employee" - a real privilege-sabotage path found
            // during audit. oldRole (already fetched, already lowercased
            // above) is the actual role of the target account, and is what
            // this safeguard is supposed to be protecting.
            if ("super_admin".equals(oldRole)) {
                 con.rollback();
                 response.sendRedirect("manage_roles.jsp?error=cannot_modify_super_admin");
                 return;
            }
            
            if ("super_admin".equals(newRole)) {
                 con.rollback();
                 response.sendRedirect("manage_roles.jsp?error=cannot_assign_super_admin");
                 return;
            }
            
            if ("admin".equals(oldRole) && !"admin".equals(newRole)) {
                // Someone is trying to demote the admin directly.
                con.rollback();
                response.sendRedirect("manage_roles.jsp?error=demote_admin_directly");
                return;
            }

            // If assigning the admin role to a NEW user
            if ("admin".equals(newRole) && !"admin".equals(oldRole)) {
                // Find current admin(s)
                ps = con.prepareStatement("SELECT user_id FROM users WHERE current_role = 'admin'");
                ResultSet rsAdmin = ps.executeQuery();
                java.util.List<Integer> oldAdmins = new java.util.ArrayList<>();
                while (rsAdmin.next()) {
                    oldAdmins.add(rsAdmin.getInt("user_id"));
                }
                rsAdmin.close();
                ps.close();

                if (!oldAdmins.isEmpty()) {
                    // Demote to fallback role. Also updates role_id in the
                    // same statement - see RoleIdResolver's class doc for why
                    // (this UPDATE was one of the two real, ongoing sources
                    // of the role_id staleness confirmed live against this
                    // project's own database).
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

                    // Log the demotion
                    PreparedStatement psLog = con.prepareStatement("INSERT INTO role_assignment_log (assigned_to, assigned_by, old_role, new_role) VALUES (?, ?, ?, ?)");
                    for (Integer oldAdminId : oldAdmins) {
                        psLog.setInt(1, oldAdminId);
                        psLog.setInt(2, adminUserId);
                        psLog.setString(3, "admin");
                        psLog.setString(4, fallbackRole);
                        psLog.addBatch();
                    }
                    psLog.executeBatch();
                    psLog.close();
                }
            }

            // Update the target user. Also updates role_id alongside
            // current_role in the same statement - see RoleIdResolver's
            // class doc; this was the other of the two real, ongoing
            // sources of the role_id staleness confirmed live.
            Integer newRoleId = RoleIdResolver.resolveRoleId(con, newRole);
            ps = con.prepareStatement("UPDATE users SET current_role = ?, status = ?, role_id = ? WHERE user_id = ?");
            ps.setString(1, newRole);
            ps.setString(2, status);
            if (newRoleId != null) {
                ps.setInt(3, newRoleId);
            } else {
                ps.setNull(3, java.sql.Types.INTEGER);
            }
            ps.setInt(4, targetUserId);
            ps.executeUpdate();
            ps.close();

            // Log the assignment
            ps = con.prepareStatement("INSERT INTO role_assignment_log (assigned_to, assigned_by, old_role, new_role) VALUES (?, ?, ?, ?)");
            ps.setInt(1, targetUserId);
            ps.setInt(2, adminUserId);
            ps.setString(3, oldRole);
            ps.setString(4, newRole);
            ps.executeUpdate();
            ps.close();

            con.commit(); // Commit transaction

            response.sendRedirect("manage_roles.jsp?msg=updated&user=" + URLEncoder.encode(targetUsername, "UTF-8"));

        } catch (Exception e) {
            e.printStackTrace();
            if (con != null) {
                try {
                    con.rollback();
                } catch (Exception rollbackEx) {
                    rollbackEx.printStackTrace();
                }
            }
            response.sendRedirect("manage_roles.jsp?error=server");
        } finally {
            try {
                if (con != null) {
                    con.setAutoCommit(true);
                    con.close();
                }
            } catch (Exception ex) {
                ex.printStackTrace();
            }
        }
    }
}