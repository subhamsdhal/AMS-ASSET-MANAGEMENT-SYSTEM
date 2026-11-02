package com.mycompany.asset_management_system_ams;

import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.mockito.MockedStatic;

import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.util.List;
import java.util.Locale;

import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.mockStatic;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;
import static org.mockito.Mockito.atLeastOnce;

/**
 * Regression coverage for the Critical AI Copilot finding: DELETE_ASSET and
 * DELETE_EMPLOYEE used to run raw "DELETE FROM assets"/"DELETE FROM
 * employees" statements - a real, permanent hard delete that exists nowhere
 * else in this application (Assets are only ever disposed, Employees are
 * only ever soft-deleted). Both intents are now routed through
 * AssetDAO.disposeAsset()/EmployeeDAO's real delete-block-reason-checked
 * soft-delete instead of hand-rolled SQL in CopilotCommandExecutor.
 *
 * These tests deliberately don't try to drive either DAO all the way to a
 * successful disposal/delete (that would require re-simulating each DAO's
 * full internal query sequence, tightly coupling this test to their private
 * implementation details). Instead, each scenario lets the real DAO code
 * reach its own natural "not found" exit, then asserts - across every SQL
 * statement issued anywhere during the whole command, not just the last one
 * - that no raw DELETE against assets/employees is ever executed. That is
 * the actual property this fix guarantees, independent of whether a given
 * disposal/delete attempt ultimately succeeds or is blocked.
 */
public class CopilotCommandExecutorSecurityTest {

    @Test
    public void testDeleteAsset_NeverIssuesRawHardDelete() throws Exception {
        Connection con = mock(Connection.class);
        PreparedStatement ps = mock(PreparedStatement.class);
        ResultSet rs = mock(ResultSet.class);

        when(con.prepareStatement(anyString())).thenReturn(ps);
        when(ps.executeQuery()).thenReturn(rs);
        // First rs.next() call is CopilotCommandExecutor.getAssetId()'s own
        // lookup - let it "find" the asset. Every subsequent call (i.e.
        // AssetDAO.disposeAsset()'s own re-check inside its own connection)
        // returns false, so the real disposeAsset() code takes its
        // currentStatus.isEmpty() branch and rolls back cleanly - it never
        // reaches the INSERT/UPDATE section, let alone a DELETE.
        when(rs.next()).thenReturn(true, false);
        when(rs.getInt(1)).thenReturn(101);

        CopilotCommandPlan plan = new CopilotCommandPlan();
        plan.intent = CopilotIntentType.DELETE_ASSET;
        plan.targetModule = "ASSET";
        plan.extractedFields.put("assetCode", "AST101");

        try (MockedStatic<DBConnection> mockedDb = mockStatic(DBConnection.class)) {
            mockedDb.when(DBConnection::getConnection).thenReturn(con);

            String result = CopilotCommandExecutor.execute(plan, 1, "asset_manager_user", "ASSET_MANAGER");

            // Whatever the outcome, it must not be the old hard-delete
            // success message.
            assertFalse(result.contains("permanently deleted"),
                    "DELETE_ASSET must never report a permanent deletion - assets are only ever disposed");

            ArgumentCaptor<String> sqlCaptor = ArgumentCaptor.forClass(String.class);
            verify(con, atLeastOnce()).prepareStatement(sqlCaptor.capture());
            List<String> allSql = sqlCaptor.getAllValues();

            for (String sql : allSql) {
                String normalized = sql.toUpperCase(Locale.ENGLISH).replaceAll("\\s+", " ").trim();
                assertFalse(normalized.contains("DELETE FROM ASSETS"),
                        "Found a raw hard-delete statement against assets: " + sql);
            }
        }
    }

    @Test
    public void testDeleteEmployee_NeverIssuesRawHardDelete() throws Exception {
        Connection con = mock(Connection.class);
        PreparedStatement ps = mock(PreparedStatement.class);
        ResultSet rs = mock(ResultSet.class);

        when(con.prepareStatement(anyString())).thenReturn(ps);
        when(ps.executeQuery()).thenReturn(rs);
        // First rs.next() call is CopilotCommandExecutor.getEmployeeId()'s
        // own lookup - let it "find" the employee. Every subsequent call
        // (EmployeeDAO.getEmployeeById(), used inside
        // getEmployeeDeleteBlockReason()) returns false, so the real DAO
        // code reports "Employee record not found" and returns before ever
        // reaching deleteEmployeePermanently()'s UPDATE, let alone a DELETE.
        when(rs.next()).thenReturn(true, false);
        when(rs.getInt(1)).thenReturn(202);

        CopilotCommandPlan plan = new CopilotCommandPlan();
        plan.intent = CopilotIntentType.DELETE_EMPLOYEE;
        plan.targetModule = "EMPLOYEE";
        plan.extractedFields.put("employeeCode", "EMP202");

        try (MockedStatic<DBConnection> mockedDb = mockStatic(DBConnection.class)) {
            mockedDb.when(DBConnection::getConnection).thenReturn(con);

            String result = CopilotCommandExecutor.execute(plan, 1, "admin_user", "ADMIN");

            assertFalse(result.contains("permanently deleted"),
                    "DELETE_EMPLOYEE must never report a permanent deletion - employees are only ever soft-deleted");

            ArgumentCaptor<String> sqlCaptor = ArgumentCaptor.forClass(String.class);
            verify(con, atLeastOnce()).prepareStatement(sqlCaptor.capture());
            List<String> allSql = sqlCaptor.getAllValues();

            for (String sql : allSql) {
                String normalized = sql.toUpperCase(Locale.ENGLISH).replaceAll("\\s+", " ").trim();
                assertFalse(normalized.contains("DELETE FROM EMPLOYEES"),
                        "Found a raw hard-delete statement against employees: " + sql);
            }
        }
    }

    @Test
    public void testCheckPermission_AssetManagerCanTriggerAssetDeletion() {
        // ASSET_MANAGER is deliberately still granted DELETE_ASSET - now
        // safe because it maps to AssetDAO.disposeAsset(), the same
        // disposal action ASSET_MANAGER is already permitted to perform
        // from the Assets module (Module 13), not a hard delete.
        CopilotCommandPlan plan = new CopilotCommandPlan();
        plan.intent = CopilotIntentType.DELETE_ASSET;
        plan.targetModule = "ASSET";

        assertTrue(CopilotCommandExecutor.checkPermission(plan, "ASSET_MANAGER"));
    }

    @Test
    public void testCheckPermission_AssetManagerCannotTriggerEmployeeDeletion() {
        CopilotCommandPlan plan = new CopilotCommandPlan();
        plan.intent = CopilotIntentType.DELETE_EMPLOYEE;
        plan.targetModule = "EMPLOYEE";

        assertFalse(CopilotCommandExecutor.checkPermission(plan, "ASSET_MANAGER"));
    }

    /**
     * Regression coverage for a second instance of the same finding-shape
     * bug: UPDATE_ASSET's "status" field used to run a raw
     * "UPDATE assets SET asset_status=?" for whatever value the regex
     * extractor pulled out of the message (e.g. "update asset AST101 status
     * to disposed"). That bypassed UpdateAssetServlet's deliberate
     * preservation of the existing status and created none of the records
     * (asset_disposal, asset_allocation) that make a status change
     * meaningful elsewhere in the app - the same "raw SQL instead of the
     * guarded lifecycle path" pattern the DELETE_ASSET fix above addresses.
     * Status changes must now be refused here and redirected to the real
     * workflow commands, with no SQL touching asset_status at all.
     */
    @Test
    public void testUpdateAsset_StatusFieldNeverWritesAssetStatus() throws Exception {
        Connection con = mock(Connection.class);
        PreparedStatement ps = mock(PreparedStatement.class);
        ResultSet rs = mock(ResultSet.class);

        when(con.prepareStatement(anyString())).thenReturn(ps);
        when(ps.executeQuery()).thenReturn(rs);
        // getAssetId()'s own lookup "finds" the asset; nothing else should
        // ever be queried or written if the status guard works.
        when(rs.next()).thenReturn(true);
        when(rs.getInt(1)).thenReturn(101);

        CopilotCommandPlan plan = new CopilotCommandPlan();
        plan.intent = CopilotIntentType.UPDATE_ASSET;
        plan.targetModule = "ASSET";
        plan.extractedFields.put("assetCode", "AST101");
        plan.extractedFields.put("updateField", "status");
        plan.extractedFields.put("updateValue", "DISPOSED");

        try (MockedStatic<DBConnection> mockedDb = mockStatic(DBConnection.class)) {
            mockedDb.when(DBConnection::getConnection).thenReturn(con);

            String result = CopilotCommandExecutor.execute(plan, 1, "asset_manager_user", "ASSET_MANAGER");

            assertTrue(result.contains("can't be changed directly"),
                    "UPDATE_ASSET status field must be refused, not silently applied: " + result);

            ArgumentCaptor<String> sqlCaptor = ArgumentCaptor.forClass(String.class);
            verify(con, atLeastOnce()).prepareStatement(sqlCaptor.capture());
            for (String sql : sqlCaptor.getAllValues()) {
                String normalized = sql.toUpperCase(Locale.ENGLISH).replaceAll("\\s+", " ").trim();
                assertFalse(normalized.contains("SET ASSET_STATUS"),
                        "Found a raw asset_status write that bypasses the guarded lifecycle path: " + sql);
            }
        }
    }

    /**
     * Companion coverage for UPDATE_EMPLOYEE's "status" field, which used to
     * write the extractor's free-text value straight into the status column
     * with no check against the two real values (ACTIVE/INACTIVE) the actual
     * Edit Employee dropdown offers.
     */
    @Test
    public void testUpdateEmployee_InvalidStatusValueRejected() throws Exception {
        Connection con = mock(Connection.class);
        PreparedStatement ps = mock(PreparedStatement.class);
        ResultSet rs = mock(ResultSet.class);

        when(con.prepareStatement(anyString())).thenReturn(ps);
        when(ps.executeQuery()).thenReturn(rs);
        when(rs.next()).thenReturn(true);
        when(rs.getInt(1)).thenReturn(202);

        CopilotCommandPlan plan = new CopilotCommandPlan();
        plan.intent = CopilotIntentType.UPDATE_EMPLOYEE;
        plan.targetModule = "EMPLOYEE";
        plan.extractedFields.put("employeeCode", "EMP202");
        plan.extractedFields.put("updateField", "status");
        plan.extractedFields.put("updateValue", "FIRED");

        try (MockedStatic<DBConnection> mockedDb = mockStatic(DBConnection.class)) {
            mockedDb.when(DBConnection::getConnection).thenReturn(con);

            String result = CopilotCommandExecutor.execute(plan, 1, "admin_user", "ADMIN");

            assertTrue(result.contains("can only be"),
                    "An out-of-enum employee status must be refused, not written through: " + result);

            ArgumentCaptor<String> sqlCaptor = ArgumentCaptor.forClass(String.class);
            verify(con, atLeastOnce()).prepareStatement(sqlCaptor.capture());
            for (String sql : sqlCaptor.getAllValues()) {
                String normalized = sql.toUpperCase(Locale.ENGLISH).replaceAll("\\s+", " ").trim();
                assertFalse(normalized.contains("SET STATUS"),
                        "Found a raw employees.status write with an unvalidated value: " + sql);
            }
        }
    }

    /**
     * Regression coverage for ALLOCATE_ASSET now routing through
     * AssetAllocationDAO.addAllocationAndReturnId() instead of a raw
     * SELECT/INSERT/UPDATE sequence. The concrete property this locks in:
     * the employee-active check runs with row-level locking (FOR UPDATE) -
     * neither of which the old raw version did at all. Rather than fully
     * simulating a successful allocation (tightly coupling this test to the
     * DAO's internals), this lets the DAO reach its own natural "employee is
     * not ACTIVE" exit and asserts the guarded query was actually issued
     * before that happened.
     */
    @Test
    public void testAllocateAsset_RoutesThroughGuardedDaoWithActiveEmployeeCheck() throws Exception {
        Connection con = mock(Connection.class);
        PreparedStatement ps = mock(PreparedStatement.class);
        ResultSet rs = mock(ResultSet.class);

        when(con.prepareStatement(anyString())).thenReturn(ps);
        when(ps.executeQuery()).thenReturn(rs);
        // 1st call: getAssetId() finds the asset. 2nd call: getEmployeeId()
        // finds the employee. 3rd call: AssetAllocationDAO.isActiveEmployee()'s
        // own FOR-UPDATE-locked check finds no ACTIVE row - the DAO takes its
        // "not active" branch and rolls back before ever reaching the INSERT.
        when(rs.next()).thenReturn(true, true, false);
        when(rs.getInt(1)).thenReturn(101);

        CopilotCommandPlan plan = new CopilotCommandPlan();
        plan.intent = CopilotIntentType.ALLOCATE_ASSET;
        plan.targetModule = "ALLOCATION";
        plan.extractedFields.put("assetCode", "AST101");
        plan.extractedFields.put("employeeCode", "EMP055");

        try (MockedStatic<DBConnection> mockedDb = mockStatic(DBConnection.class)) {
            mockedDb.when(DBConnection::getConnection).thenReturn(con);

            String result = CopilotCommandExecutor.execute(plan, 1, "asset_manager_user", "ASSET_MANAGER");

            assertTrue(result.contains("could not allocate"),
                    "An inactive employee must block allocation via the guarded DAO path: " + result);

            ArgumentCaptor<String> sqlCaptor = ArgumentCaptor.forClass(String.class);
            verify(con, atLeastOnce()).prepareStatement(sqlCaptor.capture());
            boolean sawLockedActiveEmployeeCheck = false;
            for (String sql : sqlCaptor.getAllValues()) {
                String normalized = sql.toUpperCase(Locale.ENGLISH).replaceAll("\\s+", " ").trim();
                if (normalized.contains("EMPLOYEE_STATUS = 'ACTIVE'") && normalized.contains("FOR UPDATE")) {
                    sawLockedActiveEmployeeCheck = true;
                }
            }
            assertTrue(sawLockedActiveEmployeeCheck,
                    "Expected the row-locked, employee-active-status check AssetAllocationDAO performs - "
                            + "the old raw path never verified employee status at all.");
        }
    }

    /**
     * Companion coverage for RETURN_ASSET now routing through
     * AssetReturnDAO.addReturnAndReturnId() instead of guessing the
     * allocation being returned via a MAX(allocation_id) subquery with no
     * row lock. Locks in that the specific, already-identified allocation
     * row is re-checked under FOR UPDATE before any write happens.
     */
    @Test
    public void testReturnAsset_RoutesThroughGuardedDaoWithRowLock() throws Exception {
        Connection con = mock(Connection.class);
        PreparedStatement ps = mock(PreparedStatement.class);
        ResultSet rs = mock(ResultSet.class);

        when(con.prepareStatement(anyString())).thenReturn(ps);
        when(ps.executeQuery()).thenReturn(rs);
        // 1st call: getAssetId() finds the asset. 2nd call: the ALLOCATED
        // allocation lookup finds one. 3rd call: AssetReturnDAO's own
        // FOR-UPDATE-locked getActiveAllocation() finds no matching row (e.g.
        // it was returned by another request in between) - the DAO takes its
        // natural "not found" exit before ever reaching the INSERT.
        when(rs.next()).thenReturn(true, true, false);
        when(rs.getInt(1)).thenReturn(101);

        CopilotCommandPlan plan = new CopilotCommandPlan();
        plan.intent = CopilotIntentType.RETURN_ASSET;
        plan.targetModule = "RETURN";
        plan.extractedFields.put("assetCode", "AST101");

        try (MockedStatic<DBConnection> mockedDb = mockStatic(DBConnection.class)) {
            mockedDb.when(DBConnection::getConnection).thenReturn(con);

            String result = CopilotCommandExecutor.execute(plan, 1, "asset_manager_user", "ASSET_MANAGER");

            assertTrue(result.contains("could not process the return"),
                    "A no-longer-active allocation must block the return via the guarded DAO path: " + result);

            ArgumentCaptor<String> sqlCaptor = ArgumentCaptor.forClass(String.class);
            verify(con, atLeastOnce()).prepareStatement(sqlCaptor.capture());
            boolean sawLockedAllocationCheck = false;
            for (String sql : sqlCaptor.getAllValues()) {
                String normalized = sql.toUpperCase(Locale.ENGLISH).replaceAll("\\s+", " ").trim();
                if (normalized.contains("ALLOCATION_ID = ?") && normalized.contains("FOR UPDATE")) {
                    sawLockedAllocationCheck = true;
                }
            }
            assertTrue(sawLockedAllocationCheck,
                    "Expected the row-locked allocation re-check AssetReturnDAO performs - the old raw "
                            + "path guessed the allocation via MAX(allocation_id) with no lock at all.");
        }
    }

    /**
     * Regression coverage for CREATE_MAINTENANCE_REQUEST, which used to
     * insert into a `requested_by` column that has never existed in the
     * maintenance_requests table (schema only has `employee_id`) - every
     * invocation threw a SQLException, caught upstream and surfaced as a
     * generic "internal server issue". Now routed through
     * MaintenanceRequestDAO.createMaintenanceRequest(), the same method
     * EmployeeMaintenanceRequestServlet (the real self-service form) calls.
     * This locks in the never-existed column can't reappear, and that an
     * EMPLOYEE is blocked from filing a request against an asset not
     * allotted to them - exactly as that real form enforces, and something
     * the old raw version had no way to check at all since it never
     * resolved an employee_id in the first place.
     */
    @Test
    public void testCreateMaintenanceRequest_EmployeeCannotFileForAssetNotAllottedToThem() throws Exception {
        Connection con = mock(Connection.class);
        PreparedStatement ps = mock(PreparedStatement.class);
        ResultSet rs = mock(ResultSet.class);

        when(con.prepareStatement(anyString())).thenReturn(ps);
        when(ps.executeQuery()).thenReturn(rs);
        // 1st call: getAssetId() finds the asset (101). 2nd call:
        // getEmployeeIdByUsername() resolves the employee (55). 3rd call:
        // MaintenanceRequestDAO.isAssetCurrentlyAllottedToEmployee()'s
        // COUNT(*) comes back 0 - not allotted.
        when(rs.next()).thenReturn(true, true, true);
        when(rs.getInt(1)).thenReturn(101, 55, 0);

        CopilotCommandPlan plan = new CopilotCommandPlan();
        plan.intent = CopilotIntentType.CREATE_MAINTENANCE_REQUEST;
        plan.targetModule = "MAINTENANCE";
        plan.extractedFields.put("assetCode", "AST101");
        plan.extractedFields.put("issue", "Screen flickering");

        try (MockedStatic<DBConnection> mockedDb = mockStatic(DBConnection.class)) {
            mockedDb.when(DBConnection::getConnection).thenReturn(con);

            String result = CopilotCommandExecutor.execute(plan, 1, "employee_user", "EMPLOYEE");

            assertTrue(result.contains("not currently allotted to you"),
                    "An employee must not be able to file a maintenance request against an asset that "
                            + "isn't theirs: " + result);

            ArgumentCaptor<String> sqlCaptor = ArgumentCaptor.forClass(String.class);
            verify(con, atLeastOnce()).prepareStatement(sqlCaptor.capture());
            for (String sql : sqlCaptor.getAllValues()) {
                String normalized = sql.toUpperCase(Locale.ENGLISH).replaceAll("\\s+", " ").trim();
                assertFalse(normalized.contains("REQUESTED_BY"),
                        "Found a reference to the column that never existed in maintenance_requests: " + sql);
            }
        }
    }

    @Test
    public void testCreateMaintenanceRequest_NeverWritesToNonExistentRequestedByColumn() throws Exception {
        Connection con = mock(Connection.class);
        PreparedStatement ps = mock(PreparedStatement.class);
        ResultSet rs = mock(ResultSet.class);

        when(con.prepareStatement(anyString())).thenReturn(ps);
        when(ps.executeQuery()).thenReturn(rs);
        when(ps.executeUpdate()).thenReturn(1);
        // ASSET_MANAGER isn't restricted to "their own" assets, so
        // isAssetCurrentlyAllottedToEmployee() is never even called - just
        // asset lookup (101) then employee lookup (55) before the insert.
        when(rs.next()).thenReturn(true, true);
        when(rs.getInt(1)).thenReturn(101, 55);

        CopilotCommandPlan plan = new CopilotCommandPlan();
        plan.intent = CopilotIntentType.CREATE_MAINTENANCE_REQUEST;
        plan.targetModule = "MAINTENANCE";
        plan.extractedFields.put("assetCode", "AST101");
        plan.extractedFields.put("issue", "Fan noise");

        try (MockedStatic<DBConnection> mockedDb = mockStatic(DBConnection.class)) {
            mockedDb.when(DBConnection::getConnection).thenReturn(con);

            String result = CopilotCommandExecutor.execute(plan, 1, "asset_manager_user", "ASSET_MANAGER");

            assertTrue(result.contains("✅"), "Expected a successful creation: " + result);

            ArgumentCaptor<String> sqlCaptor = ArgumentCaptor.forClass(String.class);
            verify(con, atLeastOnce()).prepareStatement(sqlCaptor.capture());
            boolean sawCorrectInsert = false;
            for (String sql : sqlCaptor.getAllValues()) {
                String normalized = sql.toUpperCase(Locale.ENGLISH).replaceAll("\\s+", " ").trim();
                assertFalse(normalized.contains("REQUESTED_BY"),
                        "Found a reference to the column that never existed in maintenance_requests: " + sql);
                if (normalized.contains("INSERT INTO MAINTENANCE_REQUESTS") && normalized.contains("EMPLOYEE_ID")) {
                    sawCorrectInsert = true;
                }
            }
            assertTrue(sawCorrectInsert,
                    "Expected the insert to use the real employee_id column via MaintenanceRequestDAO.");
        }
    }
}
