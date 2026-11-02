package com.mycompany.asset_management_system_ams;

import org.junit.jupiter.api.Test;
import static org.junit.jupiter.api.Assertions.*;

public class DepartmentModuleSecurityTest {

    @Test
    public void testDepartmentManagementRoles() {
        // VIEW
        assertTrue(RoleAccessUtil.hasAccess("SUPER_ADMIN", "DEPARTMENT_MANAGEMENT", "VIEW"));
        assertTrue(RoleAccessUtil.hasAccess("ADMIN", "DEPARTMENT_MANAGEMENT", "VIEW"));
        assertTrue(RoleAccessUtil.hasAccess("DEPARTMENT_HEAD", "DEPARTMENT_MANAGEMENT", "VIEW"));
        assertTrue(RoleAccessUtil.hasAccess("AUDITOR", "DEPARTMENT_MANAGEMENT", "VIEW"));
        assertTrue(RoleAccessUtil.hasAccess("ASSET_MANAGER", "DEPARTMENT_MANAGEMENT", "VIEW"));
        assertTrue(RoleAccessUtil.hasAccess("EMPLOYEE", "DEPARTMENT_MANAGEMENT", "VIEW"));

        // CREATE
        assertTrue(RoleAccessUtil.hasAccess("SUPER_ADMIN", "DEPARTMENT_MANAGEMENT", "CREATE"));
        assertTrue(RoleAccessUtil.hasAccess("ADMIN", "DEPARTMENT_MANAGEMENT", "CREATE"));
        assertFalse(RoleAccessUtil.hasAccess("DEPARTMENT_HEAD", "DEPARTMENT_MANAGEMENT", "CREATE"));
        assertFalse(RoleAccessUtil.hasAccess("EMPLOYEE", "DEPARTMENT_MANAGEMENT", "CREATE"));

        // EDIT
        assertTrue(RoleAccessUtil.hasAccess("SUPER_ADMIN", "DEPARTMENT_MANAGEMENT", "EDIT"));
        assertTrue(RoleAccessUtil.hasAccess("ADMIN", "DEPARTMENT_MANAGEMENT", "EDIT"));
        assertFalse(RoleAccessUtil.hasAccess("DEPARTMENT_HEAD", "DEPARTMENT_MANAGEMENT", "EDIT"));
        assertFalse(RoleAccessUtil.hasAccess("EMPLOYEE", "DEPARTMENT_MANAGEMENT", "EDIT"));

        // DELETE
        assertTrue(RoleAccessUtil.hasAccess("SUPER_ADMIN", "DEPARTMENT_MANAGEMENT", "DELETE"));
        assertTrue(RoleAccessUtil.hasAccess("ADMIN", "DEPARTMENT_MANAGEMENT", "DELETE"));
        assertFalse(RoleAccessUtil.hasAccess("DEPARTMENT_HEAD", "DEPARTMENT_MANAGEMENT", "DELETE"));
        assertFalse(RoleAccessUtil.hasAccess("EMPLOYEE", "DEPARTMENT_MANAGEMENT", "DELETE"));

        // EXPORT
        assertTrue(RoleAccessUtil.hasAccess("SUPER_ADMIN", "DEPARTMENT_MANAGEMENT", "EXPORT"));
        assertTrue(RoleAccessUtil.hasAccess("ADMIN", "DEPARTMENT_MANAGEMENT", "EXPORT"));
        assertTrue(RoleAccessUtil.hasAccess("DEPARTMENT_HEAD", "DEPARTMENT_MANAGEMENT", "EXPORT"));
        assertTrue(RoleAccessUtil.hasAccess("AUDITOR", "DEPARTMENT_MANAGEMENT", "EXPORT"));
        assertTrue(RoleAccessUtil.hasAccess("ASSET_MANAGER", "DEPARTMENT_MANAGEMENT", "EXPORT"));
        assertFalse(RoleAccessUtil.hasAccess("EMPLOYEE", "DEPARTMENT_MANAGEMENT", "EXPORT"));
    }
}
