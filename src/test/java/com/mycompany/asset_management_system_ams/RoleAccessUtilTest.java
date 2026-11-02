package com.mycompany.asset_management_system_ams;

import org.junit.jupiter.api.Test;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

public class RoleAccessUtilTest {

    @Test
    public void testDefaultDenyForUnknownEndpoint() {
        // Any unknown endpoint should return false (DENY) for any role
        assertFalse(RoleAccessUtil.hasAccess("ADMIN", "/unknown_secret_page.jsp"));
        assertFalse(RoleAccessUtil.hasAccess("EMPLOYEE", "/unknown_secret_page.jsp"));
        assertFalse(RoleAccessUtil.hasAccess("SUPER_ADMIN", "/api/hack"));
        assertFalse(RoleAccessUtil.hasAccess("DEPARTMENT_HEAD", "/unmapped_endpoint"));
    }

    @Test
    public void testAllowedEndpoints() {
        // Mapped endpoints should be accessible by allowed roles
        assertTrue(RoleAccessUtil.hasAccess("SUPER_ADMIN", "/emergency-admin-reset"));
        assertFalse(RoleAccessUtil.hasAccess("ADMIN", "/emergency-admin-reset")); // admin shouldn't have access

        assertTrue(RoleAccessUtil.hasAccess("ADMIN", "/manage_roles.jsp"));
        assertFalse(RoleAccessUtil.hasAccess("EMPLOYEE", "/manage_roles.jsp"));
        
        assertTrue(RoleAccessUtil.hasAccess("DEPARTMENT_HEAD", "/dashboard.jsp"));
        assertTrue(RoleAccessUtil.hasAccess("EMPLOYEE", "/employee_dashboard.jsp"));
        assertTrue(RoleAccessUtil.hasAccess("ASSET_MANAGER", "/assets.jsp"));
        assertFalse(RoleAccessUtil.hasAccess("EMPLOYEE", "/assets.jsp"));
    }

    @Test
    public void testSelfEscalationBypassBlocked() {
        // A non-admin user (e.g., EMPLOYEE) attempting to call UpdateUserRoleServlet directly
        // must receive DENY (false) before the Servlet even executes.
        assertFalse(RoleAccessUtil.hasAccess("EMPLOYEE", "/UpdateUserRoleServlet"));
        assertFalse(RoleAccessUtil.hasAccess("ASSET_MANAGER", "/UpdateUserRoleServlet"));
        assertFalse(RoleAccessUtil.hasAccess("DEPARTMENT_HEAD", "/UpdateUserRoleServlet"));
        assertFalse(RoleAccessUtil.hasAccess("AUDITOR", "/UpdateUserRoleServlet"));
    }

    @Test
    public void testPublicEndpoints() {
        // Static resources and login pages should be accessible even with null role
        assertTrue(RoleAccessUtil.hasAccess(null, "/login.jsp"));
        assertTrue(RoleAccessUtil.hasAccess(null, "/css/style.css"));
        assertTrue(RoleAccessUtil.hasAccess("EMPLOYEE", "/js/script.js"));
    }

    @Test
    public void testAssetOperationsAccess() {
        // SUPER_ADMIN, ADMIN, ASSET_MANAGER can access dispose/view and edit
        assertTrue(RoleAccessUtil.hasAccess("SUPER_ADMIN", "/dispose_asset.jsp"));
        assertTrue(RoleAccessUtil.hasAccess("ADMIN", "/DisposeAssetServlet"));
        assertTrue(RoleAccessUtil.hasAccess("ASSET_MANAGER", "/view_asset.jsp"));
        assertTrue(RoleAccessUtil.hasAccess("SUPER_ADMIN", "/assets.jsp"));
        
        // AUDITOR should be read-only for assets (view/export only, no create/edit/dispose)
        assertTrue(RoleAccessUtil.hasAccess("AUDITOR", "/assets.jsp"));
        assertTrue(RoleAccessUtil.hasAccess("AUDITOR", "/view_asset.jsp"));
        assertTrue(RoleAccessUtil.hasAccess("AUDITOR", "/export_asset_report.jsp"));
        
        assertFalse(RoleAccessUtil.hasAccess("AUDITOR", "/AddAssetServlet"));
        assertFalse(RoleAccessUtil.hasAccess("AUDITOR", "/UpdateAssetServlet"));
        assertFalse(RoleAccessUtil.hasAccess("AUDITOR", "/DisposeAssetServlet"));
        assertFalse(RoleAccessUtil.hasAccess("AUDITOR", "/add_asset.jsp"));
        assertFalse(RoleAccessUtil.hasAccess("AUDITOR", "/edit_asset.jsp"));
        assertFalse(RoleAccessUtil.hasAccess("AUDITOR", "/dispose_asset.jsp"));
    }
}
