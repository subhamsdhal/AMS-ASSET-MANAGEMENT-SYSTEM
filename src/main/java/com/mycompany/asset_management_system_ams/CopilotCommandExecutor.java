package com.mycompany.asset_management_system_ams;

import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.Statement;
import java.util.logging.Level;
import java.util.logging.Logger;

public class CopilotCommandExecutor {
    private static final Logger LOGGER = Logger.getLogger(CopilotCommandExecutor.class.getName());

    public static boolean checkPermission(CopilotCommandPlan plan, String role) {
        if ("SUPER_ADMIN".equals(role) || "ADMIN".equals(role)) {
            return true;
        }
        if ("AUDITOR".equalsIgnoreCase(role)) {
            return false; // read-only
        }
        if ("EMPLOYEE".equalsIgnoreCase(role)) {
            if (plan.intent == CopilotIntentType.CREATE_MAINTENANCE_REQUEST) return true;
            return false;
        }
        if ("DEPARTMENT_HEAD".equalsIgnoreCase(role)) {
            if (plan.intent == CopilotIntentType.APPROVE_ASSET_REQUEST || plan.intent == CopilotIntentType.REJECT_ASSET_REQUEST) return true;
            return false;
        }
        if ("ASSET_MANAGER".equalsIgnoreCase(role)) {
            if (plan.targetModule.equals("EMPLOYEE") || plan.targetModule.equals("DEPARTMENT")) return false;
            // This also grants DELETE_ASSET - previously a real over-grant,
            // since that intent ran a raw hard DELETE that no button
            // anywhere else in the app lets ASSET_MANAGER (or any role)
            // perform. deleteAsset() below now routes DELETE_ASSET through
            // AssetDAO.disposeAsset() instead, the same disposal action
            // ASSET_MANAGER is already permitted to perform from the Assets
            // module (Module 13) - so this broad "anything asset-related"
            // grant is correct again, not a bypass. If a future intent is
            // added under the ASSET module, confirm it maps to something
            // ASSET_MANAGER can already do elsewhere before relying on this
            // catch-all to grant it.
            return true; // Can manage assets, maintenance, allocation
        }
        return false;
    }

    public static String execute(CopilotCommandPlan plan, int userId, String username, String role) {
        Connection con = null;
        try {
            con = DBConnection.getConnection();
            con.setAutoCommit(false); // Begin Transaction

            String result = "";
            switch (plan.intent) {
                case CREATE_EMPLOYEE:
                    result = createEmployee(con, plan, userId, username);
                    break;
                case UPDATE_EMPLOYEE:
                    result = updateEmployee(con, plan, userId, username);
                    break;
                case DISABLE_EMPLOYEE:
                    result = disableEmployee(con, plan, userId, username);
                    break;
                case DELETE_EMPLOYEE:
                    result = deleteEmployee(con, plan, userId, username);
                    break;
                case CREATE_ASSET:
                    result = createAsset(con, plan, userId, username);
                    break;
                case UPDATE_ASSET:
                    result = updateAsset(con, plan, userId, username);
                    break;
                case DELETE_ASSET:
                    result = deleteAsset(con, plan, userId, username);
                    break;
                case ALLOCATE_ASSET:
                    result = allocateAsset(con, plan, userId, username);
                    break;
                case RETURN_ASSET:
                    result = returnAsset(con, plan, userId, username);
                    break;
                case CREATE_MAINTENANCE_REQUEST:
                    result = markMaintenance(con, plan, userId, username, role);
                    break;
                case UPDATE_MAINTENANCE_STATUS:
                    result = updateMaintenanceStatus(con, plan, userId, username);
                    break;
                case APPROVE_ASSET_REQUEST:
                    result = approveRequest(con, plan, userId, username, role);
                    break;
                case REJECT_ASSET_REQUEST:
                    result = rejectRequest(con, plan, userId, username, role);
                    break;
                default:
                    result = "❌ Unsupported command intent: " + plan.intent;
            }

            if (result.startsWith("✅")) {
                con.commit();
            } else {
                con.rollback();
            }
            return result;

        } catch (Exception e) {
            LOGGER.log(Level.SEVERE, "Copilot Command Execution Error", e);
            if (con != null) {
                try {
                    con.rollback();
                } catch (Exception re) {
                    LOGGER.log(Level.SEVERE, "Error during rollback", re);
                }
            }
            return "❌ Command failed due to an internal server issue.";
        } finally {
            if (con != null) {
                try {
                    con.setAutoCommit(true);
                    con.close();
                } catch (Exception ce) {
                    LOGGER.log(Level.WARNING, "Error closing connection", ce);
                }
            }
        }
    }

    private static String createEmployee(Connection con, CopilotCommandPlan plan, int userId, String username) throws Exception {
        String name = plan.extractedFields.get("name");
        String deptName = plan.extractedFields.get("department");
        String designation = plan.extractedFields.get("designation");
        String contact = plan.extractedFields.get("contact");
        
        int deptId = getDepartmentId(con, deptName);
        if (deptId == -1) return "❌ Department '" + deptName + "' not found.";

        try (PreparedStatement ps = con.prepareStatement("INSERT INTO employees (employee_name, department_id, designation, mobile_number, status, created_at) VALUES (?, ?, ?, ?, 'ACTIVE', NOW())", Statement.RETURN_GENERATED_KEYS)) {
            ps.setString(1, name);
            ps.setInt(2, deptId);
            ps.setString(3, designation);
            ps.setString(4, contact);
            ps.executeUpdate();
            
            try (ResultSet rs = ps.getGeneratedKeys()) {
                if (rs.next()) {
                    int empId = rs.getInt(1);
                    // auto generate code
                    String code = "EMP" + String.format("%03d", empId);
                    try (PreparedStatement ps2 = con.prepareStatement("UPDATE employees SET employee_code=? WHERE employee_id=?")) {
                        ps2.setString(1, code);
                        ps2.setInt(2, empId);
                        ps2.executeUpdate();
                    }
                    AuditDAO.log(userId, "CREATE_EMPLOYEE", "employees", empId, "Copilot created employee " + code);
                    return "✅ **Success**: Employee " + code + " has been created successfully.\nYou can view this record in the Employees module.";
                }
            }
        }
        return "❌ Failed to create employee.";
    }

    private static String updateEmployee(Connection con, CopilotCommandPlan plan, int userId, String username) throws Exception {
        String empCode = plan.extractedFields.get("employeeCode");
        String field = plan.extractedFields.get("updateField");
        String value = plan.extractedFields.get("updateValue");
        
        int empId = getEmployeeId(con, empCode);
        if (empId == -1) return "❌ Employee " + empCode + " not found.";

        // The real Edit Employee screen only ever offers ACTIVE/INACTIVE for
        // this field (a fixed dropdown, per UpdateEmployeeServlet.java) - the
        // regex extractor upstream (CopilotCommandDetector.extractUpdateField)
        // instead pulls out whatever free text followed "to", so "update
        // employee EMP006 status to fired" would previously have written the
        // literal string "FIRED" straight into the status column. Nothing
        // else in the app recognizes that value, so every other query and
        // screen that filters on status='ACTIVE' would silently stop seeing
        // that employee without any of the deactivation checks
        // DISABLE_EMPLOYEE/DELETE_EMPLOYEE apply. Reject anything outside the
        // two real values instead of writing it through unchecked.
        if ("status".equals(field) && !"ACTIVE".equals(value) && !"INACTIVE".equals(value)) {
            return "❌ Employee status can only be **ACTIVE** or **INACTIVE**. "
                    + "To deactivate an employee, say **disable employee " + empCode + "** instead.";
        }

        String sql = "";
        if ("mobile".equals(field)) {
            sql = "UPDATE employees SET mobile_number=? WHERE employee_id=?";
        } else if ("status".equals(field)) {
            sql = "UPDATE employees SET status=? WHERE employee_id=?";
        } else if ("department".equals(field)) {
            int deptId = getDepartmentId(con, value);
            if (deptId == -1) return "❌ Department '" + value + "' not found.";
            sql = "UPDATE employees SET department_id=? WHERE employee_id=?";
            value = String.valueOf(deptId);
        } else {
            return "❌ Cannot update field " + field;
        }

        try (PreparedStatement ps = con.prepareStatement(sql)) {
            if ("department".equals(field)) ps.setInt(1, Integer.parseInt(value));
            else ps.setString(1, value);
            ps.setInt(2, empId);
            ps.executeUpdate();
        }
        AuditDAO.log(userId, "UPDATE_EMPLOYEE", "employees", empId, "Copilot updated " + field + " to " + value);
        return "✅ **Success**: Employee " + empCode + " has been updated successfully.";
    }

    private static String disableEmployee(Connection con, CopilotCommandPlan plan, int userId, String username) throws Exception {
        String empCode = plan.extractedFields.get("employeeCode");
        int empId = getEmployeeId(con, empCode);
        if (empId == -1) return "❌ Employee " + empCode + " not found.";
        
        try (PreparedStatement ps = con.prepareStatement("UPDATE employees SET status='INACTIVE' WHERE employee_id=?")) {
            ps.setInt(1, empId);
            ps.executeUpdate();
        }
        AuditDAO.log(userId, "DISABLE_EMPLOYEE", "employees", empId, "Copilot disabled employee");
        return "✅ **Success**: Employee " + empCode + " has been disabled.";
    }

    private static String deleteEmployee(Connection con, CopilotCommandPlan plan, int userId, String username) throws Exception {
        String empCode = plan.extractedFields.get("employeeCode");
        int empId = getEmployeeId(con, empCode);
        if (empId == -1) return "❌ Employee " + empCode + " not found.";

        // Fault (Critical, fixed): this used to run a raw "DELETE FROM
        // employees" - a real, permanent hard delete of the row, guarded
        // only by an active-allocation check. That bypassed every other
        // safeguard EmployeeDAO.getEmployeeDeleteBlockReason() enforces for
        // the exact same action everywhere else in this application
        // (DeleteEmployeeServlet, Module 9): the employee must already be
        // deactivated first, and must have no pending/approved asset
        // requests, not just no active allocations. It also physically
        // erased the row instead of using the soft-delete
        // (deleteEmployeePermanently()) the rest of the app relies on to
        // keep allocation/return/audit history intact. Routed through the
        // exact same two DAO calls the real "Delete Employee" button uses,
        // so a chat command can never do something no button in the rest of
        // the application can do.
        EmployeeDAO employeeDao = new EmployeeDAO();
        String blockReason = employeeDao.getEmployeeDeleteBlockReason(empId);
        if (blockReason != null && !blockReason.isEmpty()) {
            return "❌ I cannot delete employee " + empCode + ": " + blockReason;
        }

        boolean deleted = employeeDao.deleteEmployeePermanently(
                empId,
                userId,
                "Deleted via AMS Copilot on behalf of " + username
        );

        if (!deleted) {
            return "❌ Failed to delete employee " + empCode + ".";
        }

        AuditDAO.log(userId, "DELETE_EMPLOYEE", "employees", empId,
                "Copilot deleted employee " + empCode
                + " via the same deactivate-and-dependency-checked path used by the Employees module");
        return "✅ **Success**: Employee " + empCode + " has been removed from the active employee directory. "
                + "Historical allocation, return and audit records are retained.";
    }

    private static String createAsset(Connection con, CopilotCommandPlan plan, int userId, String username) throws Exception {
        String category = plan.extractedFields.get("category");
        String deptName = plan.extractedFields.get("department");
        String brandModel = plan.extractedFields.get("brandModel");
        String costStr = plan.extractedFields.get("cost");
        
        int catId = getCategoryId(con, category);
        if (catId == -1) return "❌ I could not create the asset because category '" + category + "' was not found. Please choose an existing category or create it first.";
        
        int deptId = getDepartmentId(con, deptName);
        if (deptId == -1) return "❌ Department '" + deptName + "' not found.";
        
        try (PreparedStatement ps = con.prepareStatement("INSERT INTO assets (asset_name, category_id, department_id, purchase_cost, asset_status, created_at) VALUES (?, ?, ?, ?, 'AVAILABLE', NOW())", Statement.RETURN_GENERATED_KEYS)) {
            ps.setString(1, brandModel);
            ps.setInt(2, catId);
            ps.setInt(3, deptId);
            ps.setDouble(4, Double.parseDouble(costStr));
            ps.executeUpdate();
            
            try (ResultSet rs = ps.getGeneratedKeys()) {
                if (rs.next()) {
                    int assetId = rs.getInt(1);
                    String code = "AST" + String.format("%03d", assetId);
                    try (PreparedStatement ps2 = con.prepareStatement("UPDATE assets SET asset_code=? WHERE asset_id=?")) {
                        ps2.setString(1, code);
                        ps2.setInt(2, assetId);
                        ps2.executeUpdate();
                    }
                    AuditDAO.log(userId, "CREATE_ASSET", "assets", assetId, "Copilot created asset " + code);
                    return "✅ **Success**: Asset " + code + " has been created successfully.\nYou can view it in the Assets module.";
                }
            }
        }
        return "❌ Failed to create asset.";
    }

    private static String updateAsset(Connection con, CopilotCommandPlan plan, int userId, String username) throws Exception {
        String assetCode = plan.extractedFields.get("assetCode");
        String field = plan.extractedFields.get("updateField");
        String value = plan.extractedFields.get("updateValue");

        int assetId = getAssetId(con, assetCode);
        if (assetId == -1) return "❌ Asset " + assetCode + " not found.";

        // Fault (Critical, same shape as the DELETE_ASSET/DELETE_EMPLOYEE
        // hard-delete finding): this used to run a raw "UPDATE assets SET
        // asset_status=?" for ANY value the regex extractor pulled out of
        // "update asset AST001 status to disposed/allocated/damaged/...".
        // The real Edit Asset screen (UpdateAssetServlet.java) deliberately
        // does the opposite - it reads the asset's current status and
        // re-submits it unchanged ("preservedAssetStatus"), specifically
        // because flipping asset_status directly, with no other side effect,
        // desynchronizes it from the records that make each status
        // meaningful: DISPOSED with no asset_disposal row, ALLOCATED with no
        // asset_allocation row, or DISPOSED while an allocation is still
        // active and the employee still has the item. This path had no
        // active-allocation check, no valid-value check (any string was
        // accepted verbatim), and created none of those records - a second,
        // narrower instance of the same "Copilot's write pipeline
        // reimplements raw SQL instead of the guarded lifecycle method"
        // pattern already fixed for hard deletes. Status changes now only
        // happen through the commands that also create the matching record:
        // allocate/return/dispose/maintenance - exactly like every other UI
        // path into this data.
        if ("status".equals(field)) {
            return "❌ Asset status can't be changed directly - it's a side effect of a real action, "
                    + "not a field to overwrite. Use one of:\n"
                    + "- **allocate asset " + assetCode + " to <employee code>** (sets it to ALLOCATED)\n"
                    + "- **return asset " + assetCode + "** (sets it back to AVAILABLE)\n"
                    + "- **delete asset " + assetCode + "** (disposes it, the only way to reach DISPOSED)\n"
                    + "- **create maintenance request for " + assetCode + "** (sends it for maintenance)";
        }

        String sql = "";
        if ("department".equals(field)) {
            int deptId = getDepartmentId(con, value);
            if (deptId == -1) return "❌ Department '" + value + "' not found.";
            sql = "UPDATE assets SET department_id=? WHERE asset_id=?";
            value = String.valueOf(deptId);
        } else {
            return "❌ Cannot update field " + field;
        }

        try (PreparedStatement ps = con.prepareStatement(sql)) {
            if ("department".equals(field)) ps.setInt(1, Integer.parseInt(value));
            else ps.setString(1, value);
            ps.setInt(2, assetId);
            ps.executeUpdate();
        }
        AuditDAO.log(userId, "UPDATE_ASSET", "assets", assetId, "Copilot updated " + field + " to " + value);
        return "✅ **Success**: Asset " + assetCode + " has been updated successfully.";
    }

    private static String deleteAsset(Connection con, CopilotCommandPlan plan, int userId, String username) throws Exception {
        String assetCode = plan.extractedFields.get("assetCode");
        int assetId = getAssetId(con, assetCode);
        if (assetId == -1) return "❌ Asset " + assetCode + " not found.";

        // Fault (Critical, fixed): this used to run a raw "DELETE FROM
        // assets" - a real, permanent hard delete that exists nowhere else
        // in this application. Every other path to removing an asset from
        // service (DisposeAssetServlet, Module 4/13) goes through
        // AssetDAO.submitDisposal(), which preserves the row
        // (asset_status stays untouched until reviewed) so allocation/return/
        // maintenance/audit history stays intact, and independently
        // re-verifies the asset isn't already disposed and has no active
        // allocation before touching anything. It was also reachable by
        // ASSET_MANAGER, a role that cannot hard-delete an asset through any
        // other screen, servlet, or mechanism in the entire system - only
        // propose a disposal, same as here.
        //
        // Routes through submitDisposal() (the maker stage), never
        // reviewDisposal() - disposal now requires a second-party
        // SUPER_ADMIN/ADMIN review (ReviewAssetDisposalServlet) regardless of
        // entry point, closing the Future Scope maker-checker gap. A chat
        // command must not be able to finalize a disposal that no button in
        // the rest of the application can finalize in one step either -
        // including for SUPER_ADMIN/ADMIN callers, who could otherwise
        // short-circuit the exact control this workflow exists to enforce.
        AssetDAO assetDao = new AssetDAO();
        boolean submitted = assetDao.submitDisposal(
                assetId,
                java.time.LocalDate.now().toString(),
                "OTHER",
                0.0,
                userId,
                "Disposal proposed via AMS Copilot on behalf of " + username
        );

        if (!submitted) {
            return "❌ I could not propose disposal for asset " + assetCode
                    + " - it may already be disposed, already have a pending/completed disposal, or currently have an active allocation. "
                    + "Please return it first if it's allocated.";
        }

        AuditDAO.log(userId, "DISPOSAL_SUBMITTED", "assets", assetId,
                "Copilot proposed disposal of asset " + assetCode
                + " (asset records are never hard-deleted; a Super Admin/Admin must separately review and approve this before the asset is actually marked disposed)");
        return "✅ **Success**: A disposal proposal for asset " + assetCode + " has been submitted for review. "
                + "It will remain in active service until a Super Admin or Admin approves the disposal.";
    }

    // Fault (Critical, same shape as the DELETE_ASSET/DELETE_EMPLOYEE hard-
    // delete finding): this used to run its own raw SELECT/INSERT/UPDATE
    // sequence instead of AssetAllocationDAO.addAllocationAndReturnId() -
    // the exact method AddAllocationServlet (the real "Allocate Asset"
    // screen) calls. That DAO method does two things this raw version
    // skipped entirely: (1) locks the asset row with SELECT ... FOR UPDATE
    // while checking availability, closing a race where two allocation
    // requests for the same asset arriving close together could both pass
    // the "is it AVAILABLE" check before either write lands - allocating
    // the same physical asset to two different employees; (2) verifies the
    // employee is ACTIVE, not just that the employee code exists - nothing
    // else in this application lets an asset be handed to a disabled
    // employee. Routing through the real DAO closes both gaps and also
    // fills in issue_condition/issue_location_id/expected_return_date the
    // way every other allocation in the system has them populated (the raw
    // INSERT above also wrote to an `issued_by` column no real allocation
    // path sets).
    private static String allocateAsset(Connection con, CopilotCommandPlan plan, int userId, String username) throws Exception {
        String ast = plan.extractedFields.get("assetCode");
        String emp = plan.extractedFields.get("employeeCode");
        int assetId = getAssetId(con, ast);
        int empId = getEmployeeId(con, emp);
        if (assetId == -1) return "❌ Asset " + ast + " not found.";
        if (empId == -1) return "❌ Employee " + emp + " not found.";

        AssetAllocationDAO allocationDao = new AssetAllocationDAO();
        int allocationId = allocationDao.addAllocationAndReturnId(
                assetId, empId, java.time.LocalDate.now().toString(), null, "ALLOCATED",
                "Allocated via AMS Copilot on behalf of " + username, userId);

        if (allocationId <= 0) {
            return "❌ I could not allocate " + ast + " to " + emp
                    + " - the asset may not currently be AVAILABLE, or the employee may not be ACTIVE.";
        }

        AuditDAO.log(userId, "ALLOCATION", "asset_allocation", assetId, "Copilot allocated " + ast + " to " + emp);
        return "✅ **Success**: Asset " + ast + " has been successfully allocated to " + emp + ".\nYou can view this in the Allocations module.";
    }

    // Fault (Critical, same shape as above): this used to guess which
    // allocation was being returned via
    // "(SELECT MAX(allocation_id) FROM asset_allocation WHERE asset_id=?)"
    // instead of the specific allocation row already identified below, ran
    // no row lock while doing it, and always forced asset_status straight
    // back to AVAILABLE regardless of the condition the asset was returned
    // in. AssetReturnDAO.addReturnAndReturnId() - what AddReturnServlet (the
    // real "Process Return" screen) actually calls - locks that exact
    // allocation row (SELECT ... FOR UPDATE), refuses a second return
    // against an allocation that already has one (asset_returns.allocation_id
    // is UNIQUE in the schema - the raw version had no such guard and could
    // have thrown an unhandled constraint violation on a double-return
    // race), and routes the asset to AVAILABLE/UNDER_MAINTENANCE/etc. based
    // on the recorded condition the same way every other return in the
    // system does.
    private static String returnAsset(Connection con, CopilotCommandPlan plan, int userId, String username) throws Exception {
        String ast = plan.extractedFields.get("assetCode");
        int assetId = getAssetId(con, ast);
        if (assetId == -1) return "❌ Asset " + ast + " not found.";

        int allocationId = -1;
        try (PreparedStatement ps = con.prepareStatement(
                "SELECT allocation_id FROM asset_allocation WHERE asset_id=? AND allocation_status='ALLOCATED' ORDER BY allocation_id DESC LIMIT 1")) {
            ps.setInt(1, assetId);
            ResultSet rs = ps.executeQuery();
            if (rs.next()) {
                allocationId = rs.getInt(1);
            } else {
                return "⚠️ Asset " + ast + " is not currently allocated.";
            }
        }

        AssetReturnDAO returnDao = new AssetReturnDAO();
        int returnId = returnDao.addReturnAndReturnId(
                allocationId, java.time.LocalDate.now().toString(), "GOOD", username,
                "Returned via AMS Copilot on behalf of " + username);

        if (returnId <= 0) {
            return "❌ I could not process the return for " + ast + " - it may already have been returned.";
        }

        AuditDAO.log(userId, "RETURN", "asset_returns", assetId, "Copilot processed return for " + ast);
        return "✅ **Success**: Asset " + ast + " has been returned and is now available.";
    }

    // Fault (Critical - not a hardening gap, an outright crash): this
    // inserted into a `requested_by` column that has never existed in the
    // maintenance_requests table (schema only has `employee_id` - see
    // schema.sql). Every single CREATE_MAINTENANCE_REQUEST command has been
    // throwing a SQLException on that unknown column, caught by execute()'s
    // outer handler, and surfaced as the generic "Command failed due to an
    // internal server issue" - giving no hint that the real cause is a typo
    // in a column name, not a transient failure. It also bound `userId`
    // (a users.user_id) into what would need to be an employees.employee_id
    // - two different ID spaces - so fixing only the column name would still
    // have inserted the wrong or FK-violating value. This is also the ONLY
    // write action the EMPLOYEE role has via the Copilot (checkPermission()
    // above), so this bug has meant that role's one write capability has
    // never actually worked.
    //
    // Routed through MaintenanceRequestDAO.createMaintenanceRequest() - what
    // EmployeeMaintenanceRequestServlet (the real self-service form) calls -
    // which also closes a second gap: that servlet enforces
    // isAssetCurrentlyAllottedToEmployee() so an employee can only raise a
    // request against an asset actually allotted to them, a restriction the
    // raw version had no way to apply at all (it never resolved an
    // employee_id in the first place). Applied only for the EMPLOYEE role,
    // matching the real form's own scope - ASSET_MANAGER/ADMIN/SUPER_ADMIN
    // are not restricted to "their own" assets anywhere else in the app
    // either, so this does not narrow what they could already do.
    private static String markMaintenance(Connection con, CopilotCommandPlan plan, int userId, String username, String role) throws Exception {
        String ast = plan.extractedFields.get("assetCode");
        String issue = plan.extractedFields.get("issue");
        int assetId = getAssetId(con, ast);
        if (assetId == -1) return "❌ Asset " + ast + " not found.";

        int employeeId = getEmployeeIdByUsername(con, username);
        if (employeeId <= 0) {
            return "❌ I could not resolve your account to an employee record, so I can't file this request. "
                    + "Please use the Maintenance module directly.";
        }

        MaintenanceRequestDAO dao = new MaintenanceRequestDAO();
        if ("EMPLOYEE".equalsIgnoreCase(role) && !dao.isAssetCurrentlyAllottedToEmployee(assetId, employeeId)) {
            return "❌ I could not create a maintenance request for " + ast
                    + " - it is not currently allotted to you.";
        }

        boolean created = dao.createMaintenanceRequest(
                assetId, employeeId, issue != null ? issue : "Initiated via Copilot", null);

        if (!created) {
            return "❌ Failed to create maintenance request for " + ast + ".";
        }

        AuditDAO.log(userId, "MAINTENANCE_REQUEST", "maintenance_requests", assetId, "Copilot created maintenance request for " + ast);
        return "✅ **Success**: Maintenance request created for " + ast + ".";
    }

    private static String updateMaintenanceStatus(Connection con, CopilotCommandPlan plan, int userId, String username) throws Exception {
        String targetId = plan.extractedFields.get("targetId");
        String status = plan.extractedFields.get("status");
        
        try (PreparedStatement ps = con.prepareStatement("UPDATE maintenance_requests SET request_status=? WHERE request_id=?")) {
            ps.setString(1, status);
            ps.setInt(2, Integer.parseInt(targetId));
            int rows = ps.executeUpdate();
            if (rows == 0) return "❌ Maintenance request " + targetId + " not found.";
        }
        AuditDAO.log(userId, "UPDATE_MAINTENANCE", "maintenance_requests", Integer.parseInt(targetId), "Copilot updated maintenance status to " + status);
        return "✅ **Success**: Maintenance request " + targetId + " marked as " + status + ".";
    }

    /**
     * Routed through AssetRequestDAO rather than a raw UPDATE here, closing
     * two real bugs the raw SQL had: (1) it wrote to a `reject_reason`
     * column that doesn't exist anywhere in this schema (only `remarks` /
     * `request_reason` do) - every Copilot reject attempt threw and failed
     * outright; (2) it carried no transition guard, unlike
     * AssetRequestDAO.updateRequestStatus()'s own requiredCurrentStatus
     * check, so it could silently re-process an already-finalized request -
     * the exact anti-pattern already fixed elsewhere in this codebase
     * (ReviewPhysicalVerificationServlet, UpdateRequestStatusServlet).
     *
     * A DEPARTMENT_HEAD's "approve" intent means forward to the Asset
     * Manager (their own review stage, PENDING_DEPT_HEAD -> PENDING), not a
     * final approval - routed through forwardOrRejectByDeptHead(), which
     * also enforces that the request actually belongs to a department this
     * user_id heads. Every other permitted role (SUPER_ADMIN/ADMIN/
     * ASSET_MANAGER, per checkPermission() above) performs the real final
     * approval via updateRequestStatus(), identical to UpdateRequestStatusServlet.
     */
    private static String approveRequest(Connection con, CopilotCommandPlan plan, int userId, String username, String role) throws Exception {
        String targetId = plan.extractedFields.get("targetId");
        int requestId = Integer.parseInt(targetId);
        AssetRequestDAO dao = new AssetRequestDAO();

        boolean updated;
        String successMessage;
        if ("DEPARTMENT_HEAD".equalsIgnoreCase(role)) {
            updated = dao.forwardOrRejectByDeptHead(requestId, "FORWARD", userId, "Forwarded via Copilot");
            successMessage = "✅ **Success**: Asset request " + targetId + " forwarded to the Asset Manager for approval.";
        } else {
            updated = dao.updateRequestStatus(requestId, "APPROVED", username, "Approved via Copilot");
            successMessage = "✅ **Success**: Asset request " + targetId + " approved.";
        }

        if (!updated) {
            return "⚠️ Request " + targetId + " not found, not yours to review, or already processed.";
        }
        AuditDAO.log(userId, "APPROVE_REQUEST", "asset_requests", requestId, "Copilot approved/forwarded request");
        return successMessage;
    }

    private static String rejectRequest(Connection con, CopilotCommandPlan plan, int userId, String username, String role) throws Exception {
        String targetId = plan.extractedFields.get("targetId");
        String reason = plan.extractedFields.get("reason");
        String remarks = reason != null ? reason : "Rejected via Copilot";
        int requestId = Integer.parseInt(targetId);
        AssetRequestDAO dao = new AssetRequestDAO();

        boolean updated;
        if ("DEPARTMENT_HEAD".equalsIgnoreCase(role)) {
            updated = dao.forwardOrRejectByDeptHead(requestId, "REJECT", userId, remarks);
        } else {
            updated = dao.updateRequestStatus(requestId, "REJECTED", username, remarks);
        }

        if (!updated) {
            return "⚠️ Request " + targetId + " not found, not yours to review, or already processed.";
        }
        AuditDAO.log(userId, "REJECT_REQUEST", "asset_requests", requestId, "Copilot rejected request");
        return "✅ **Success**: Asset request " + targetId + " rejected.";
    }

    // --- Helpers ---
    private static int getAssetId(Connection con, String code) throws Exception {
        if (code == null) return -1;
        try (PreparedStatement ps = con.prepareStatement("SELECT asset_id FROM assets WHERE asset_code=?")) {
            ps.setString(1, code);
            ResultSet rs = ps.executeQuery();
            return rs.next() ? rs.getInt(1) : -1;
        }
    }

    private static int getEmployeeId(Connection con, String code) throws Exception {
        if (code == null) return -1;
        try (PreparedStatement ps = con.prepareStatement("SELECT employee_id FROM employees WHERE employee_code=?")) {
            ps.setString(1, code);
            ResultSet rs = ps.executeQuery();
            return rs.next() ? rs.getInt(1) : -1;
        }
    }

    /**
     * Resolves the employee record behind the logged-in Copilot user, the
     * same way EmployeeMaintenanceRequestServlet.getEmployeeIdByUsername()
     * does for its session fallback: match the user's linked employee_id
     * first, or fall back to the username matching an employee_code
     * directly. Kept in sync with that servlet's query deliberately -
     * CREATE_MAINTENANCE_REQUEST needs the same identity resolution it does.
     */
    private static int getEmployeeIdByUsername(Connection con, String username) throws Exception {
        if (username == null || username.trim().isEmpty()) return -1;
        String sql = "SELECT e.employee_id FROM employees e "
                + "LEFT JOIN users u ON u.employee_id = e.employee_id "
                + "WHERE u.username = ? OR LOWER(e.employee_code) = LOWER(?) LIMIT 1";
        try (PreparedStatement ps = con.prepareStatement(sql)) {
            ps.setString(1, username);
            ps.setString(2, username);
            ResultSet rs = ps.executeQuery();
            return rs.next() ? rs.getInt(1) : -1;
        }
    }
    
    private static int getDepartmentId(Connection con, String name) throws Exception {
        if (name == null) return -1;
        try (PreparedStatement ps = con.prepareStatement("SELECT department_id FROM departments WHERE department_name LIKE ? LIMIT 1")) {
            ps.setString(1, "%" + name + "%");
            ResultSet rs = ps.executeQuery();
            return rs.next() ? rs.getInt(1) : -1;
        }
    }

    private static int getCategoryId(Connection con, String name) throws Exception {
        if (name == null) return -1;
        try (PreparedStatement ps = con.prepareStatement("SELECT category_id FROM categories WHERE category_name LIKE ? LIMIT 1")) {
            ps.setString(1, "%" + name + "%");
            ResultSet rs = ps.executeQuery();
            return rs.next() ? rs.getInt(1) : -1;
        }
    }
}
