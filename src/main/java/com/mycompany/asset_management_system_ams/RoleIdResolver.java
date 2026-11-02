package com.mycompany.asset_management_system_ams;

import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.util.logging.Level;
import java.util.logging.Logger;

/**
 * RoleIdResolver — resolves a {@code users.current_role} enum value to the
 * matching {@code roles.role_id}, so a caller that updates {@code
 * current_role} can keep {@code role_id} in sync in the same statement
 * instead of leaving it to silently drift.
 *
 * Fault, found live during this pass (audit/01-auth-session.md's P0
 * schema-drift finding, followed to its actual root cause): {@code role_id}
 * genuinely exists on this project's live database (schema.sql itself has
 * since been corrected to define it), but neither of the two places that
 * ever write {@code current_role} - {@code UpdateUserRoleServlet} and
 * {@code EmergencyAdminResetServlet} - ever touched {@code role_id} in the
 * same statement. Querying the real database directly confirmed the
 * consequence: {@code role_id} was stale/wrong for most real user rows (only
 * 2 of 12 actually matched what their own {@code current_role} implied) -
 * this was not a one-time historical artifact, it is an ONGOING bug that
 * recurs on every real role change. {@code current_role} remains the actual
 * authorization source (RoleAuthorizationFilter/RoleAccessUtil key off it,
 * never {@code role_id}), so this drift never caused an access-control gap -
 * but any feature that joins through {@code roles} via {@code role_id}
 * (confirmed live in this codebase: AuditDAO, NotificationHelper /
 * NotificationRecipientResolver, DepartmentDAO, RoleAssignmentDAO's own
 * duty-coverage queries) could show a stale/wrong role for an affected user.
 *
 * Public (not package-private) specifically so {@link #toEnumRoleValue}
 * below is callable from manage_roles.jsp - a compiled JSP lives in a
 * different generated package, not this one, so a JSP-reachable method here
 * needs public visibility regardless of how narrow its actual use is.
 */
public final class RoleIdResolver {

    private static final Logger LOGGER = Logger.getLogger(RoleIdResolver.class.getName());

    private RoleIdResolver() {
    }

    /**
     * The reverse of {@link #toRoleName}: maps a {@code roles.role_name}
     * value back to the exact {@code current_role} enum literal it stands
     * for. A plain lowercase of every role name EXCEPT {@code
     * DEPARTMENT_HEAD}, which does not reverse to a valid enum value that
     * way (lowercasing it gives {@code department_head}, not the enum's
     * actual {@code dept_head}).
     *
     * Fault, found live: manage_roles.jsp's role-change dropdown built its
     * option values by lowercasing roleMap.get("roleName") straight from
     * this same roles table with no awareness of this one mismatch -
     * selecting "Department Head" and clicking Update sent
     * {@code newRole=department_head} to UpdateUserRoleServlet, a value that
     * does not match ANY literal in the current_role enum. Confirmed this
     * would either error outright or (MySQL's default non-strict behavior)
     * silently store an empty string, corrupting that user's authorization
     * role entirely - never reached in this pass because it was caught
     * during live verification before actually submitting it. This method
     * is the fix, used by manage_roles.jsp's option-value generation
     * instead of a raw toLowerCase().
     *
     * Returns the input lowercased (best-effort, not null) for any name
     * this mapping doesn't specifically recognise, rather than blocking
     * rendering the page over an unexpected roles-table row.
     */
    public static String toEnumRoleValue(String roleName) {
        if (roleName == null) {
            return "";
        }
        String v = roleName.trim();
        if ("DEPARTMENT_HEAD".equalsIgnoreCase(v)) {
            return "dept_head";
        }
        return v.toLowerCase();
    }

    /**
     * Maps a {@code current_role} enum literal to its {@code roles.role_name}
     * spelling. Every value is a plain uppercase of the enum literal EXCEPT
     * {@code dept_head}, whose enum spelling does not match the roles
     * table's own {@code DEPARTMENT_HEAD} name at all (missing "artment") -
     * confirmed live as the specific reason a real dept_head account's
     * role_id was pointing at the wrong role entirely, not merely a
     * hypothetical case-sensitivity risk a collation would already handle.
     */
    private static String toRoleName(String currentRole) {
        if (currentRole == null) {
            return null;
        }
        String v = currentRole.trim().toLowerCase();
        if (v.isEmpty()) {
            return null;
        }
        if ("dept_head".equals(v)) {
            return "DEPARTMENT_HEAD";
        }
        return v.toUpperCase();
    }

    /**
     * Looks up {@code roles.role_id} for the given {@code current_role}
     * value on the given connection (so it participates in the caller's own
     * transaction rather than opening a second one). Returns {@code null} -
     * never throws - if the role name has no matching row or the lookup
     * fails for any reason; callers should treat {@code null} as "leave
     * role_id unset for this write" rather than block the actual role
     * change on this secondary, display-only lookup succeeding, since
     * {@code current_role} remains the real authorization source regardless
     * of whether this resolves.
     */
    static Integer resolveRoleId(Connection con, String currentRole) {
        String roleName = toRoleName(currentRole);
        if (roleName == null || con == null) {
            return null;
        }
        try (PreparedStatement ps = con.prepareStatement("SELECT role_id FROM roles WHERE role_name = ?")) {
            ps.setString(1, roleName);
            try (ResultSet rs = ps.executeQuery()) {
                if (rs.next()) {
                    return rs.getInt("role_id");
                }
            }
        } catch (Exception e) {
            LOGGER.log(Level.WARNING, "RoleIdResolver.resolveRoleId failed for currentRole=" + currentRole, e);
        }
        return null;
    }
}
