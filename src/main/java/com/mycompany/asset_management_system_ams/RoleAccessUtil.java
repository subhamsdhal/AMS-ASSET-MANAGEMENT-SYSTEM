package com.mycompany.asset_management_system_ams;

import java.util.Arrays;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.regex.Pattern;

public class RoleAccessUtil {

    private static final Map<String, List<String>> ROLE_MAP = new HashMap<>();
    
    // Fallback static methods for existing JSPs that might call them directly
    public static boolean isFullAccess(String role) {
        return ("SUPER_ADMIN".equals(role) || "ADMIN".equals(role));
    }
    public static boolean isAdmin(String role) {
        return isFullAccess(role);
    }
    public static boolean canManageRoles(String role) {
        return isFullAccess(role);
    }
    public static boolean canAccessAllModules(String role) {
        return isFullAccess(role);
    }

    static {
        // SUPER_ADMIN (Recovery)
        ROLE_MAP.put("/emergency-admin-reset", Arrays.asList("SUPER_ADMIN"));
        ROLE_MAP.put("/emergency_recovery.jsp", Arrays.asList("SUPER_ADMIN"));
        
        // ADMIN (System config, roles, full access)
        List<String> adminOnly = Arrays.asList("ADMIN");
        ROLE_MAP.put("/manage_roles.jsp", adminOnly);
        ROLE_MAP.put("/UpdateUserRoleServlet", adminOnly);
        ROLE_MAP.put("/settings.jsp", adminOnly);
        // NOTE: "/audit_logs.jsp" used to also be put here with adminOnly
        // (ADMIN only, no SUPER_ADMIN/AUDITOR) - silently overwritten later by
        // the correct, wider auditorOps entry below (Audit module section),
        // since ROLE_MAP is a plain HashMap and the last put() for a key wins.
        // Functionally harmless (the later entry matches the JSP's own gate
        // exactly), but a misleading duplicate - removed. Same drift pattern
        // as the "/AddAssetRequestServlet" duplicate found in the Asset
        // Requests module.
        ROLE_MAP.put("/SaveSettingsServlet", adminOnly);
        ROLE_MAP.put("/BackupDatabaseServlet", adminOnly);
        ROLE_MAP.put("/RestoreDatabaseServlet", adminOnly);
        
        // ADMIN + ASSET_MANAGER + SUPER_ADMIN (Asset ops, categories, vendors, etc)
        List<String> assetOps = Arrays.asList("SUPER_ADMIN", "ADMIN", "ASSET_MANAGER");
        ROLE_MAP.put("/add_asset.jsp", assetOps);
        ROLE_MAP.put("/AddAssetServlet", assetOps);
        ROLE_MAP.put("/edit_asset.jsp", assetOps);
        ROLE_MAP.put("/UpdateAssetServlet", assetOps);
        // Fault (Medium-High, fixed): CheckAssetCodeServlet had NO entry here at all.
        // hasAccess() default-denies anything missing from this map (even for
        // SUPER_ADMIN), so RoleAuthorizationFilter 403'd every single call to the live
        // "is this asset code already taken?" AJAX check on Add/Edit Asset, for every
        // role, before the servlet's own logic ever ran. The calling JS only handles
        // HTTP 200, so this failed completely silently - no console error, the check
        // just never fired. Not a security hole (over-restrictive, not under), but a
        // fully broken UX feature. Matches assetOps, same as the two forms it serves.
        ROLE_MAP.put("/CheckAssetCodeServlet", assetOps);
        ROLE_MAP.put("/dispose_asset.jsp", assetOps);
        ROLE_MAP.put("/DisposeAssetServlet", assetOps);
        ROLE_MAP.put("/allocation.jsp", assetOps);
        ROLE_MAP.put("/returns.jsp", assetOps);
        ROLE_MAP.put("/maintenance.jsp", assetOps);
        ROLE_MAP.put("/categories.jsp", assetOps);
        ROLE_MAP.put("/vendors.jsp", assetOps);
        ROLE_MAP.put("/qr_control_center.jsp", assetOps);
        ROLE_MAP.put("/physical_verification.jsp", assetOps);
        ROLE_MAP.put("/add_maintenance.jsp", assetOps);
        ROLE_MAP.put("/add_return.jsp", assetOps);
        ROLE_MAP.put("/add_allocation.jsp", assetOps);

        // Read-only view pages that were pinned to assetOps (SUPER_ADMIN/ADMIN/ASSET_MANAGER
        // only) above, but each page's OWN internal role check - the actual authoritative
        // source, verified by reading each one directly rather than assumed - expects a wider
        // audience. Overriding those specific keys here (each .put() below only replaces its
        // own key; the write/manage pages above using the shared `assetOps` list object, like
        // add_asset.jsp or dispose_asset.jsp, are untouched). Was blocking these roles with a
        // 403 from RoleAuthorizationFilter on pages that both dashboard.jsp's own UI and the
        // target page itself already treated as accessible to them - not caught by the
        // RoleAccessUtilTest suite because it only tests a sample of paths, not every one
        // RoleAccessUtil governs.
        List<String> maintenanceViewOps = Arrays.asList("SUPER_ADMIN", "ADMIN", "ASSET_MANAGER", "AUDITOR");
        // maintenance.jsp's own canExportMaintenance already includes AUDITOR, which only
        // makes sense if Auditors can reach the page in the first place.
        ROLE_MAP.put("/maintenance.jsp", maintenanceViewOps);
        // maintenance_requests.jsp unconditionally redirects every role to maintenance.jsp
        // (its own query/render logic below that redirect is unreachable dead code) - still
        // needs a ROLE_MAP entry so the redirect itself is reachable instead of 403ing first.
        ROLE_MAP.put("/maintenance_requests.jsp", maintenanceViewOps);

        // physical_verification.jsp's own gate (canViewVerification) explicitly allows
        // SUPER_ADMIN/ADMIN/ASSET_MANAGER/AUDITOR/DEPARTMENT_HEAD and redirects everyone else
        // away with ?error=accessDenied - RoleAccessUtil was narrower than the page it gates.
        List<String> verificationViewOps = Arrays.asList("SUPER_ADMIN", "ADMIN", "ASSET_MANAGER", "AUDITOR", "DEPARTMENT_HEAD");
        ROLE_MAP.put("/physical_verification.jsp", verificationViewOps);

        // my_physical_verification_duties.jsp is the self-service page any assigned
        // officer (any role, since the duty-scheduling officer dropdown accepts any
        // active employee) uses to see and submit their own physical verification
        // duties. Open to every role - own gate further restricts to whatever the
        // caller's own employee_id was actually assigned.
        List<String> verificationSelfServiceOps = Arrays.asList("SUPER_ADMIN", "ADMIN", "ASSET_MANAGER", "AUDITOR", "DEPARTMENT_HEAD", "EMPLOYEE");
        ROLE_MAP.put("/my_physical_verification_duties.jsp", verificationSelfServiceOps);

        // AssetSearchServlet is the asset-picker autocomplete AJAX call physical_verification.jsp
        // itself makes - had no entry either, so it 403'd for every role that page just let in
        // except SUPER_ADMIN/ADMIN, breaking the picker for ASSET_MANAGER/AUDITOR/DEPARTMENT_HEAD.
        // EMPLOYEE added on top of verificationViewOps for the self-service asset picker above.
        ROLE_MAP.put("/AssetSearchServlet", verificationSelfServiceOps);

        // UploadAssetDocumentServlet/DownloadAssetDocumentServlet had no entry either - the
        // asset document attach/download feature was completely broken for every role except
        // SUPER_ADMIN, regardless of what each servlet's own (correct) role check said.
        ROLE_MAP.put("/UploadAssetDocumentServlet", assetOps);
        ROLE_MAP.put("/DownloadAssetDocumentServlet", verificationViewOps);
        // Same again - view_asset.jsp's "Generate QR" action, no entry, own gate is
        // SUPER_ADMIN/ADMIN/ASSET_MANAGER (matches assetOps exactly).
        ROLE_MAP.put("/GenerateAssetQrServlet", assetOps);

        // qr_control_center.jsp's own canViewQrControl explicitly includes AUDITOR.
        List<String> qrViewOps = Arrays.asList("SUPER_ADMIN", "ADMIN", "ASSET_MANAGER", "AUDITOR");
        ROLE_MAP.put("/qr_control_center.jsp", qrViewOps);
        // These QR sub-pages had NO entry at all (not even the assetOps one above) - default
        // deny blocked every role but SUPER_ADMIN outright. Each one's own canView*/canViewQr*
        // check independently confirms this exact role set.
        ROLE_MAP.put("/qr_asset_register.jsp", qrViewOps);
        ROLE_MAP.put("/qr_scan_logs.jsp", qrViewOps);
        ROLE_MAP.put("/qr_missing_qr_report.jsp", qrViewOps);
        ROLE_MAP.put("/qr_system_health.jsp", qrViewOps);
        ROLE_MAP.put("/qr_tagging_status.jsp", qrViewOps);

        // warranty_report.jsp has no role gate of its own at all (any logged-in user reaches
        // its rendering code) - RoleAccessUtil is the *only* access control for this page, and
        // it had no entry, so it was 403ing for every role but SUPER_ADMIN. Role set matches
        // dashboard.jsp's own canViewWarranty, the clearest available statement of intent.
        ROLE_MAP.put("/warranty_report.jsp", qrViewOps);

        // Warranty Renewal History (new): view_warranty_history.jsp is read-only,
        // same access level as warranty_report.jsp itself. renew_warranty.jsp and
        // its servlet are a mutating action, restricted to assetOps - matches
        // each page's own internal role check exactly (verified by reading both).
        ROLE_MAP.put("/view_warranty_history.jsp", qrViewOps);
        ROLE_MAP.put("/renew_warranty.jsp", assetOps);
        ROLE_MAP.put("/RenewAssetWarrantyServlet", assetOps);

        // MASTER DATA (Categories & Vendors Management)
        List<String> masterDataOps = Arrays.asList("SUPER_ADMIN", "ADMIN");
        // add_vendor.jsp / category_vendor_mapping.jsp were pinned to masterDataOps
        // (SUPER_ADMIN/ADMIN only), but each page's OWN gate (canManageSuppliers /
        // canManageMapping) explicitly allows ASSET_MANAGER too - blocking the one role
        // whose actual job is vendor/asset management from a page it's supposed to use.
        // Corrected to assetOps here; masterDataOps is kept for any other future
        // admin-only master-data entries.
        ROLE_MAP.put("/add_vendor.jsp", assetOps);
        // Vendor compliance documents (new): upload matches add_vendor.jsp/
        // edit_vendor.jsp's own canManageSuppliers check exactly. Download is
        // read-only, same level as view_vendor.jsp (commonOps, added near that
        // mapping below).
        ROLE_MAP.put("/UploadVendorDocumentServlet", assetOps);
        ROLE_MAP.put("/category_vendor_mapping.jsp", assetOps);

        // ASSET VIEWERS
        List<String> assetViewOps = Arrays.asList("SUPER_ADMIN", "ADMIN", "ASSET_MANAGER", "AUDITOR", "DEPARTMENT_HEAD");
        ROLE_MAP.put("/assets.jsp", assetViewOps);
        ROLE_MAP.put("/view_asset.jsp", assetViewOps);
        // DEPARTMENT_HEAD intentionally excluded — Finding 3: orphaned dept-scoped filter removed from JSP
        List<String> reportExportOps = Arrays.asList("SUPER_ADMIN", "ADMIN", "ASSET_MANAGER", "AUDITOR");
        ROLE_MAP.put("/export_asset_report.jsp", reportExportOps);
        
        // EMPLOYEE MANAGEMENT (Dept Head, Admin, Super Admin)
        List<String> employeeManageOps = Arrays.asList("SUPER_ADMIN", "ADMIN", "DEPARTMENT_HEAD");
        ROLE_MAP.put("/add_employee.jsp", employeeManageOps);
        ROLE_MAP.put("/edit_employee.jsp", employeeManageOps);
        ROLE_MAP.put("/AddEmployeeServlet", employeeManageOps);
        ROLE_MAP.put("/UpdateEmployeeServlet", employeeManageOps);
        ROLE_MAP.put("/DeleteEmployeeServlet", employeeManageOps);
        ROLE_MAP.put("/DisableEmployeeServlet", employeeManageOps);
        ROLE_MAP.put("/UploadEmployeeDocumentServlet", employeeManageOps);
        ROLE_MAP.put("/DeleteEmployeeDocumentServlet", employeeManageOps);
        ROLE_MAP.put("/UploadEmployeeProfileImageServlet", employeeManageOps);
        // Employee Transfer / Retirement (built alongside the Asset
        // Assignment/Allocation audit - transfer moves department + lets each
        // allocated asset be retained or returned; retirement forces all
        // allocated assets to be returned). Same role scope as every other
        // employee-management action above.
        ROLE_MAP.put("/transfer_employee.jsp", employeeManageOps);
        ROLE_MAP.put("/TransferEmployeeServlet", employeeManageOps);
        ROLE_MAP.put("/retire_employee.jsp", employeeManageOps);
        ROLE_MAP.put("/RetireEmployeeServlet", employeeManageOps);
        // Employee self-service side of the same feature: EMPLOYEE states a
        // keep/return preference per asset, reviewed by the roles above on
        // transfer_employee.jsp - not the same role list, deliberately EMPLOYEE-only.
        ROLE_MAP.put("/employee_transfer_preference.jsp", Arrays.asList("EMPLOYEE"));
        ROLE_MAP.put("/SubmitEmployeeTransferPreferenceServlet", Arrays.asList("EMPLOYEE"));

        // EMPLOYEE VIEW (Includes Auditor)
        List<String> employeeViewOps = Arrays.asList("SUPER_ADMIN", "ADMIN", "DEPARTMENT_HEAD", "AUDITOR");
        ROLE_MAP.put("/employees.jsp", employeeViewOps);
        ROLE_MAP.put("/view_employee.jsp", employeeViewOps);
        ROLE_MAP.put("/DownloadEmployeeDocumentServlet", employeeViewOps);
        
        // REPORTS & ANALYTICS (SUPER_ADMIN, ADMIN, ASSET_MANAGER, AUDITOR per reports.jsp allowedRole check)
        List<String> reportsPageOps = Arrays.asList("SUPER_ADMIN", "ADMIN", "ASSET_MANAGER", "AUDITOR", "DEPARTMENT_HEAD");
        ROLE_MAP.put("/reports.jsp", reportsPageOps);
        // Same viewer set as reports.jsp itself, so no role that can open the
        // Reports hub 403s on one of its own cards.
        ROLE_MAP.put("/depreciation_report.jsp", reportsPageOps);
        ROLE_MAP.put("/analytics.jsp", reportsPageOps);

        // AUDITOR (Read-only internal pages)
        List<String> auditorOps = Arrays.asList("SUPER_ADMIN", "ADMIN", "AUDITOR");
        ROLE_MAP.put("/audit_logs.jsp", auditorOps);

        // ─── EXPORT ENDPOINTS — Standard Reports (SUPER_ADMIN, ADMIN, ASSET_MANAGER, AUDITOR) ───
        // These were entirely missing from ROLE_MAP, causing 403 for all roles (root cause of new finding).
        ROLE_MAP.put("/export_allocation_report.jsp",         reportExportOps);
        ROLE_MAP.put("/export_disposal_report.jsp",           reportExportOps);
        ROLE_MAP.put("/export_employee_report.jsp",           reportExportOps);
        ROLE_MAP.put("/export_maintenance.jsp",               reportExportOps);
        ROLE_MAP.put("/export_requests_report.jsp",           reportExportOps);
        ROLE_MAP.put("/export_returns_report.jsp",            reportExportOps);
        ROLE_MAP.put("/export_transfer_report.jsp",           reportExportOps);
        ROLE_MAP.put("/export_warranty_report.jsp",           reportExportOps);
        // export_audit_logs.jsp's own gate is SUPER_ADMIN/ADMIN/AUDITOR only (no
        // ASSET_MANAGER) - matches audit_logs.jsp/view_audit_log.jsp exactly, and
        // matches access_matrix.jsp's documented policy that ASSET_MANAGER has no
        // audit-log access. The shared reportExportOps list (which does include
        // ASSET_MANAGER, correct for every other export above) was too wide for
        // this one - narrowed to auditorOps to match. Not reachable via any link
        // ASSET_MANAGER can see anyway (audit_logs.jsp itself already excludes
        // them), but this keeps RoleAccessUtil an accurate statement of intent
        // rather than relying on that being incidentally true.
        ROLE_MAP.put("/export_audit_logs.jsp",                auditorOps);
        ROLE_MAP.put("/ExportPhysicalVerificationReportServlet", reportExportOps);

        // ─── EXPORT ENDPOINTS — Categories & Vendor Mapping (SUPER_ADMIN, ADMIN, ASSET_MANAGER, AUDITOR) ───
        ROLE_MAP.put("/export_categories_report.jsp",                  reportExportOps);
        ROLE_MAP.put("/export_category_vendor_mapping_report.jsp",     reportExportOps);

        // ─── EXPORT ENDPOINTS — QR Module (SUPER_ADMIN, ADMIN, ASSET_MANAGER, AUDITOR) ───
        ROLE_MAP.put("/export_qr_asset_register.jsp",         reportExportOps);
        ROLE_MAP.put("/export_qr_asset_scan_history_excel.jsp", reportExportOps);
        ROLE_MAP.put("/export_qr_coverage_report_excel.jsp",  reportExportOps);
        ROLE_MAP.put("/export_qr_exception_report_excel.jsp", reportExportOps);
        ROLE_MAP.put("/export_qr_ip_audit_excel.jsp",         reportExportOps);
        ROLE_MAP.put("/export_qr_missing_qr_excel.jsp",       reportExportOps);
        ROLE_MAP.put("/export_qr_reissue_history_excel.jsp",  reportExportOps);
        ROLE_MAP.put("/export_qr_scan_analytics_excel.jsp",   reportExportOps);
        ROLE_MAP.put("/export_qr_scan_logs.jsp",              reportExportOps);
        ROLE_MAP.put("/export_qr_tagging_status.jsp",         reportExportOps);
        ROLE_MAP.put("/export_qr_tagging_status_excel.jsp",   reportExportOps);
        
        // DEPARTMENTS MODULE
        List<String> deptViewOps = Arrays.asList("SUPER_ADMIN", "ADMIN", "DEPARTMENT_HEAD", "AUDITOR", "ASSET_MANAGER", "EMPLOYEE");
        List<String> deptManageOps = Arrays.asList("SUPER_ADMIN", "ADMIN");
        List<String> deptExportOps = Arrays.asList("SUPER_ADMIN", "ADMIN", "DEPARTMENT_HEAD", "AUDITOR", "ASSET_MANAGER");
        
        ROLE_MAP.put("/departments.jsp", deptViewOps);
        ROLE_MAP.put("/view_department.jsp", deptViewOps);
        ROLE_MAP.put("/add_department.jsp", deptManageOps);
        ROLE_MAP.put("/AddDepartmentServlet", deptManageOps);
        ROLE_MAP.put("/edit_department.jsp", deptManageOps);
        ROLE_MAP.put("/UpdateDepartmentServlet", deptManageOps);
        ROLE_MAP.put("/DeleteDepartmentServlet", deptManageOps);
        ROLE_MAP.put("/export_departments_excel.jsp", deptExportOps);

        // ASSET REQUESTS — creation open to all authenticated employees (Step 1 decision)
        List<String> allEmployeeOps = Arrays.asList("SUPER_ADMIN", "ADMIN", "ASSET_MANAGER", "AUDITOR", "DEPARTMENT_HEAD", "EMPLOYEE");
        ROLE_MAP.put("/add_request.jsp", allEmployeeOps);
        ROLE_MAP.put("/AddAssetRequestServlet", allEmployeeOps);
        // view_request.jsp had NO entry at all here, which under this class's default-deny
        // model meant every role except SUPER_ADMIN got a 403 viewing an individual request's
        // details - including on employee_dashboard.jsp's own "View All" (Recent Requests) link
        // and every "?id=" link into it. Not a deliberate restriction (a page nobody but one
        // role can ever open serves no purpose) - grouped with the other read/create request
        // actions since viewing carries materially less risk than approving one.
        ROLE_MAP.put("/view_request.jsp", allEmployeeOps);

        // ASSET REQUESTS — approval restricted to ops roles only (Step 1 decision, DEPARTMENT_HEAD removed)
        List<String> requestApprovalOps = Arrays.asList("SUPER_ADMIN", "ADMIN", "ASSET_MANAGER");
        ROLE_MAP.put("/asset_requests.jsp", requestApprovalOps);
        ROLE_MAP.put("/UpdateRequestStatusServlet", requestApprovalOps);

        // ROLE ASSIGNMENT (Admin-level)
        List<String> deptHeadOps = Arrays.asList("ADMIN", "DEPARTMENT_HEAD");
        ROLE_MAP.put("/role_assignment.jsp", deptHeadOps);

        // ASSET REQUESTS — Department Head's own review stage (Forward/Reject
        // a request sitting at PENDING_DEPT_HEAD). Reuses deptHeadOps
        // (ADMIN + DEPARTMENT_HEAD, SUPER_ADMIN implicit per hasAccess()
        // above) rather than requestApprovalOps just above - this is a
        // distinct stage from the Asset Manager's final approval, matching
        // AssetRequestDAO.forwardOrRejectByDeptHead()'s own department-head-
        // only ownership guard.
        ROLE_MAP.put("/dept_head_asset_requests.jsp", deptHeadOps);
        ROLE_MAP.put("/ReviewAssetRequestByDeptHeadServlet", deptHeadOps);

        // Profile Change Requests: SUPER_ADMIN/ADMIN can review any request;
        // DEPARTMENT_HEAD can also review, but only for their own department's
        // employees - user_profile_requests.jsp filters the list it displays to
        // match, and ReviewProfileChangeRequestServlet independently re-checks
        // that scope server-side before approving/rejecting (see its own
        // comment) rather than trusting the page's filter as the boundary.
        // Reuses deptHeadOps (ADMIN + DEPARTMENT_HEAD, with SUPER_ADMIN
        // implicitly included per hasAccess() below) - same shape as
        // role_assignment.jsp just above.
        ROLE_MAP.put("/user_profile_requests.jsp", deptHeadOps);
        ROLE_MAP.put("/ReviewProfileChangeRequestServlet", deptHeadOps);
        ROLE_MAP.put("/RoleAssignmentServlet", deptHeadOps);
        
        // COMMON (Accessed by multiple roles including EMPLOYEE)
        List<String> commonOps = Arrays.asList("ADMIN", "ASSET_MANAGER", "AUDITOR", "DEPARTMENT_HEAD", "EMPLOYEE");
        ROLE_MAP.put("/dashboard.jsp", Arrays.asList("ADMIN", "ASSET_MANAGER", "AUDITOR", "DEPARTMENT_HEAD"));
        ROLE_MAP.put("/employee_dashboard.jsp", commonOps);
        ROLE_MAP.put("/employee_profile.jsp", commonOps);
        // SubmitProfileChangeRequestServlet is reachable from employee_profile.jsp's
        // new "Request a Profile Change" form - same role set as that page itself
        // (the servlet's own check is "does this session have an employee_id",
        // not a specific role, matching commonOps exactly).
        ROLE_MAP.put("/SubmitProfileChangeRequestServlet", commonOps);
        ROLE_MAP.put("/employee_assets.jsp", commonOps);
        ROLE_MAP.put("/new_employee_asset_request.jsp", commonOps);
        // These four had NO entry at all, and each one's own gate (read directly, not
        // assumed) imposes no role restriction beyond "logged in" - so default-deny was
        // blocking every role but SUPER_ADMIN from pages that impose no restriction of
        // their own. asset_qr_card.jsp/qr_print.jsp are read-only QR display/print views
        // linked from view_asset.jsp; qr_scanner.jsp is the physical QR-scan entry point
        // (any staff member scanning a tag); view_allocation.jsp shows one allocation
        // record's details.
        ROLE_MAP.put("/asset_qr_card.jsp", commonOps);
        ROLE_MAP.put("/qr_print.jsp", commonOps);
        ROLE_MAP.put("/qr_scanner.jsp", commonOps);
        ROLE_MAP.put("/view_allocation.jsp", commonOps);
        // NOTE: "/AddAssetRequestServlet" used to be re-put here with commonOps
        // (no SUPER_ADMIN), silently overwriting the earlier, deliberately
        // documented allEmployeeOps entry above (Asset Requests section) since
        // ROLE_MAP is a plain HashMap - last put() for a key wins. Functionally
        // harmless (SUPER_ADMIN is implicitly allowed on any mapped path
        // regardless of the list, see hasAccess()), but it made the earlier
        // entry's comment ("creation open to all authenticated employees")
        // false, and duplicate keys pointing at near-identical lists in two
        // different sections is exactly the kind of drift this sweep exists to
        // catch. Removed - the Asset Requests section is the single source of
        // truth for this endpoint's role list.
        // employee_maintenance_request.jsp's own gate requires role EMPLOYEE exactly and
        // redirects everyone else away - but it had NO entry here at all, so the one role
        // it's built for was 403'd by RoleAuthorizationFilter before ever reaching that
        // (correct) check. This is what employee_dashboard.jsp's "View All" (Recent
        // Maintenance Requests) link points at.
        ROLE_MAP.put("/employee_maintenance_request.jsp", Arrays.asList("EMPLOYEE"));
        ROLE_MAP.put("/logout.jsp", commonOps);
        ROLE_MAP.put("/change_password.jsp", commonOps);
        ROLE_MAP.put("/ChangePasswordServlet", commonOps);

        // ─────────────────────────────────────────────────────────────────────────
        // SYSTEMATIC SWEEP — every @WebServlet and every top-level .jsp in the app
        // was diffed against the keys above (find/grep all url-patterns and .jsp
        // files, comm -23 against ROLE_MAP's key set). ~90 paths had NO entry at
        // all, meaning default-deny 403'd every role except SUPER_ADMIN (via the
        // bypass) regardless of whether the page's own internal role check already
        // correctly allowed that role. Each one below was individually verified
        // against its own gate (redirect-on-deny code, read directly) rather than
        // assumed. Grouped roughly by the role list each ended up needing.
        // ─────────────────────────────────────────────────────────────────────────

        // -- assetOps (SUPER_ADMIN/ADMIN/ASSET_MANAGER) --
        ROLE_MAP.put("/AddAllocationServlet", assetOps);
        ROLE_MAP.put("/AddCategoryServlet", assetOps);
        ROLE_MAP.put("/AddCategoryVendorMappingServlet", assetOps);
        ROLE_MAP.put("/AddMaintenanceServlet", assetOps); // own gate: isMaintenanceManager(role)
        // Widened beyond assetOps: AddPhysicalVerificationServlet also accepts a
        // self-submission from the officer a duty was actually assigned to (its own
        // isAllowedSubmitter/self-service check), so DEPARTMENT_HEAD/AUDITOR/EMPLOYEE
        // must be able to reach the servlet at all - the filter runs before that
        // internal ownership check ever gets a chance to run.
        ROLE_MAP.put("/AddPhysicalVerificationServlet", Arrays.asList("SUPER_ADMIN", "ADMIN", "ASSET_MANAGER", "AUDITOR", "DEPARTMENT_HEAD", "EMPLOYEE"));
        // Same self-service reasoning as AddPhysicalVerificationServlet just above -
        // this is the officer's own "mark my duty complete" button on
        // my_physical_verification_duties.jsp, gated the rest of the way by its own
        // ownership check (only the employee actually assigned to that duty).
        ROLE_MAP.put("/CompletePhysicalVerificationDutyServlet", Arrays.asList("SUPER_ADMIN", "ADMIN", "ASSET_MANAGER", "AUDITOR", "DEPARTMENT_HEAD", "EMPLOYEE"));
        ROLE_MAP.put("/AddVendorServlet", assetOps);
        ROLE_MAP.put("/BulkGenerateAssetQrServlet", assetOps);
        ROLE_MAP.put("/CategoryVendorMappingAjaxServlet", assetOps);
        ROLE_MAP.put("/DeleteVendorServlet", assetOps);
        ROLE_MAP.put("/GenerateEmployeeLoginServlet", assetOps);
        ROLE_MAP.put("/ManageQrUrlsServlet", assetOps);
        ROLE_MAP.put("/RefreshAssetQrUrlsServlet", assetOps);
        ROLE_MAP.put("/ReissueAssetQrTokenServlet", assetOps);
        ROLE_MAP.put("/ReviewPhysicalVerificationServlet", assetOps);
        // Duty-level checker (approve to COMPLETED / send back to IN_PROGRESS),
        // same reviewer set as the per-report review above.
        ROLE_MAP.put("/ReviewPhysicalVerificationDutyServlet", assetOps);
        ROLE_MAP.put("/SchedulePhysicalVerificationDutyServlet", assetOps);
        ROLE_MAP.put("/UpdateCategoryServlet", assetOps);
        ROLE_MAP.put("/UpdateCategoryStatusServlet", assetOps);
        ROLE_MAP.put("/UpdateCategoryVendorMappingStatusServlet", assetOps);
        ROLE_MAP.put("/UpdateMaintenanceRequestStatusServlet", assetOps);
        ROLE_MAP.put("/UpdateMaintenanceServlet", assetOps);
        ROLE_MAP.put("/UpdateQrTaggingStatusServlet", assetOps);
        ROLE_MAP.put("/UpdateVendorServlet", assetOps);
        ROLE_MAP.put("/add_category.jsp", assetOps);
        ROLE_MAP.put("/edit_category.jsp", assetOps);
        ROLE_MAP.put("/edit_maintenance.jsp", assetOps);
        ROLE_MAP.put("/edit_vendor.jsp", assetOps);
        ROLE_MAP.put("/resolve_maintenance.jsp", assetOps);
        ROLE_MAP.put("/schedule_service.jsp", assetOps);
        ROLE_MAP.put("/asset_register_card.jsp", assetOps);
        ROLE_MAP.put("/qr_bulk_generate.jsp", assetOps);
        ROLE_MAP.put("/qr_tags.jsp", assetOps);
        ROLE_MAP.put("/qr_token_reissue.jsp", assetOps);
        ROLE_MAP.put("/qr_url_refresh.jsp", assetOps);

        // -- EMPLOYEE-only (own gate requires role EMPLOYEE exactly) --
        ROLE_MAP.put("/EmployeeMaintenanceRequestServlet", Arrays.asList("EMPLOYEE"));

        // -- assetOps + EMPLOYEE (return-a-loaned-asset flow: an employee returning
        // their own allocated item, or ops staff processing it) --
        List<String> returnOps = Arrays.asList("SUPER_ADMIN", "ADMIN", "ASSET_MANAGER", "EMPLOYEE");
        ROLE_MAP.put("/AddReturnServlet", returnOps);
        ROLE_MAP.put("/ReturnAllocationServlet", returnOps);
        // add_return.jsp was already present under the shared assetOps list (no
        // EMPLOYEE) - overridden here since its own gate explicitly allows EMPLOYEE
        // and matches AddReturnServlet exactly; a real mismatch, not ambiguous.
        ROLE_MAP.put("/add_return.jsp", returnOps);

        // -- qrViewOps (SUPER_ADMIN/ADMIN/ASSET_MANAGER/AUDITOR) --
        ROLE_MAP.put("/qr_asset_scan_history.jsp", qrViewOps);
        ROLE_MAP.put("/qr_coverage_report.jsp", qrViewOps);
        ROLE_MAP.put("/qr_exception_report.jsp", qrViewOps);
        ROLE_MAP.put("/qr_ip_audit_report.jsp", qrViewOps);
        ROLE_MAP.put("/qr_print_labels.jsp", qrViewOps);
        ROLE_MAP.put("/qr_reissue_history.jsp", qrViewOps);
        ROLE_MAP.put("/qr_scan_analytics.jsp", qrViewOps);
        ROLE_MAP.put("/qr_tagging_work_order.jsp", qrViewOps);
        ROLE_MAP.put("/qr_token_lookup.jsp", qrViewOps);
        ROLE_MAP.put("/view_qr_scan_log.jsp", qrViewOps);
        ROLE_MAP.put("/db_status.jsp", qrViewOps);

        // -- verificationViewOps (SUPER_ADMIN/ADMIN/ASSET_MANAGER/AUDITOR/DEPARTMENT_HEAD) --
        ROLE_MAP.put("/view_verification.jsp", verificationViewOps);

        // -- reportsPageOps (SUPER_ADMIN/ADMIN/ASSET_MANAGER/AUDITOR/DEPARTMENT_HEAD) --
        ROLE_MAP.put("/asset_health.jsp", reportsPageOps);

        // -- reportExportOps (SUPER_ADMIN/ADMIN/ASSET_MANAGER/AUDITOR) --
        ROLE_MAP.put("/view_disposal.jsp", reportExportOps);
        // Disposal list/queue page - same viewer set as view_disposal.jsp
        // (viewing is low-risk; the write action is gated separately below).
        ROLE_MAP.put("/asset_disposals.jsp", reportExportOps);
        // Checker stage of the disposal maker-checker workflow - open to
        // assetOps (SUPER_ADMIN/ADMIN/ASSET_MANAGER), matching the servlet's own
        // canReview check and ReviewAssetTransferServlet's reviewer set below.
        // (Was masterDataOps/SUPER_ADMIN-ADMIN-only until ASSET_MANAGER was
        // added as a reviewer at the servlet/JSP level - this entry was missed
        // in that change and left stale, silently re-blocking ASSET_MANAGER at
        // this filter alone despite the servlet itself now allowing it.)
        ROLE_MAP.put("/ReviewAssetDisposalServlet", assetOps);

        // Employee-to-employee asset transfer workflow. Submitting is open to
        // the same roles that can already touch an allocation record
        // (allEmployeeOps - an employee submits for their own allocated
        // asset; ops roles may submit on behalf of any employee). Reviewing
        // is assetOps (SUPER_ADMIN/ADMIN/ASSET_MANAGER, matching who already
        // manages allocations generally) - EMPLOYEE is structurally excluded
        // from review since it isn't in assetOps at all.
        ROLE_MAP.put("/SubmitAssetTransferServlet", allEmployeeOps);
        ROLE_MAP.put("/ReviewAssetTransferServlet", assetOps);
        ROLE_MAP.put("/asset_transfers.jsp", assetOps);
        // CopilotReportExportServlet's own gate is "everyone except EMPLOYEE", which
        // is exactly this list.
        ROLE_MAP.put("/CopilotReportExportServlet", reportExportOps);

        // -- auditorOps (SUPER_ADMIN/ADMIN/AUDITOR) --
        ROLE_MAP.put("/access_matrix.jsp", auditorOps);
        ROLE_MAP.put("/view_audit_log.jsp", auditorOps);

        // -- adminOnly (SUPER_ADMIN via bypass + ADMIN) --
        ROLE_MAP.put("/SendTestEmailServlet", adminOnly);
        ROLE_MAP.put("/UpdateCurrencySettingsServlet", adminOnly);
        ROLE_MAP.put("/UpdateNotificationSettingsServlet", adminOnly);
        ROLE_MAP.put("/UpdateProfileServlet", adminOnly);
        ROLE_MAP.put("/TunnelControlServlet", adminOnly);
        ROLE_MAP.put("/CloudflareTunnelServlet", adminOnly);
        ROLE_MAP.put("/edit_profile.jsp", adminOnly);
        ROLE_MAP.put("/notification_settings.jsp", adminOnly);
        ROLE_MAP.put("/test_email.jsp", adminOnly);
        ROLE_MAP.put("/currency_settings.jsp", adminOnly);
        ROLE_MAP.put("/backup_restore.jsp", adminOnly);
        ROLE_MAP.put("/database_backup_export.jsp", adminOnly);

        // -- commonOps (logged in, no further role restriction of its own) --
        // Each of these had no restriction beyond session.getAttribute("username")/
        // ("role") being non-null when read directly - any per-role flags in them
        // (isSuperAdmin/isAssetManager/canManage*, etc.) only gate individual buttons,
        // not the page itself, verified by confirming there is no sendRedirect on
        // the false branch of that flag.
        ROLE_MAP.put("/CopilotServlet", commonOps);
        // Same audience as CopilotServlet itself - anyone who can chat with
        // the Copilot can rate one of its answers. Missing this entry is
        // exactly the "default-deny 403s for every role" trap the
        // copilot_quick_stats.jsp comment below already documents -
        // confirmed live the same way while building this feature.
        ROLE_MAP.put("/CopilotFeedbackServlet", commonOps);
        ROLE_MAP.put("/TestCopilotConnectionServlet", commonOps);
        ROLE_MAP.put("/scan_result.jsp", commonOps);
        ROLE_MAP.put("/ams_copilot.jsp", commonOps);
        // Same audience as ams_copilot.jsp - a deliberately AI-free
        // companion page (direct-SQL "records added" counts) linked from it,
        // so it needs the same access level or it 403s for every role
        // (default-deny - confirmed live).
        ROLE_MAP.put("/copilot_quick_stats.jsp", commonOps);
        // Same audience as ams_copilot.jsp again, for the same reason: linked
        // from its sidebar (the "Chat History" button), only ever shows the
        // CURRENT user's own history, and this file's own default-deny would
        // otherwise 403 it for every role the moment this entry is missing -
        // added proactively this time, not after a live 403 like several of
        // this list's neighbors.
        ROLE_MAP.put("/copilot_chat_history.jsp", commonOps);
        ROLE_MAP.put("/CopilotQuickStatsServlet", commonOps);
        ROLE_MAP.put("/alert_center.jsp", commonOps);
        ROLE_MAP.put("/dashboard_help.jsp", commonOps);
        ROLE_MAP.put("/global_search.jsp", commonOps);
        ROLE_MAP.put("/notifications.jsp", commonOps);
        ROLE_MAP.put("/maintenance_history.jsp", commonOps);
        ROLE_MAP.put("/overdue_actions.jsp", commonOps);
        ROLE_MAP.put("/view_category.jsp", commonOps);
        ROLE_MAP.put("/view_location.jsp", commonOps);
        ROLE_MAP.put("/view_maintenance.jsp", commonOps);
        ROLE_MAP.put("/view_return.jsp", commonOps);
        ROLE_MAP.put("/view_vendor.jsp", commonOps);
        ROLE_MAP.put("/DownloadVendorDocumentServlet", commonOps);
        // employee_requests.jsp / employee_returns.jsp additionally require
        // session "employee_id" to be set, but impose no separate role check -
        // grouped with their sibling employee_dashboard.jsp/employee_profile.jsp/
        // employee_assets.jsp, which already use this same commonOps list.
        ROLE_MAP.put("/employee_requests.jsp", commonOps);
        ROLE_MAP.put("/employee_returns.jsp", commonOps);

        // ─── Asset Category Management module pass ───────────────────────────
        // categories.jsp's own canExportCategories flag (Export Excel button) and
        // category_vendor_mapping.jsp's own canExportMappingReport flag both
        // explicitly include AUDITOR - which only makes sense if Auditors can
        // reach the page in the first place. Both pages were pinned to assetOps
        // (SUPER_ADMIN/ADMIN/ASSET_MANAGER only, no AUDITOR), so an Auditor was
        // 403'd by RoleAccessUtil before ever seeing a page whose own code
        // assumed they could get there. Same bug pattern as the earlier
        // maintenance.jsp fix - widened to reportExportOps to match what each
        // page's own export-permission check actually implies.
        ROLE_MAP.put("/categories.jsp", reportExportOps);
        ROLE_MAP.put("/category_vendor_mapping.jsp", reportExportOps);

        // ─── Asset Assignment/Allocation module pass ──────────────────────────
        // allocation.jsp: same button-implies-access pattern as categories.jsp
        // above - its own canExportAllocationReport flag includes AUDITOR, but
        // the page was pinned to assetOps (no AUDITOR). Widened to match.
        ROLE_MAP.put("/allocation.jsp", reportExportOps);

        // returns.jsp: same pattern, but wider - its own canCreateReturn flag
        // explicitly includes EMPLOYEE (an employee returning their own
        // allocated asset via the "New Return" button, consistent with
        // add_return.jsp/AddReturnServlet/ReturnAllocationServlet all already
        // allowing EMPLOYEE - see returnOps above) and canExportReturnReport
        // includes AUDITOR. The page itself has no hard redirect beyond
        // "logged in" - assetOps was blocking both roles the page's own code
        // was clearly written to admit. (This corrects an inconsistency from
        // the earlier RoleAccessUtil sweep, where this exact page was reviewed
        // and left unchanged on the mistaken assumption that a narrower
        // existing mapping was automatically a working one - it wasn't; it
        // silently broke the page for EMPLOYEE and AUDITOR the same way
        // maintenance.jsp and categories.jsp did before their fixes.)
        List<String> returnsPageOps = Arrays.asList("SUPER_ADMIN", "ADMIN", "ASSET_MANAGER", "AUDITOR", "EMPLOYEE");
        ROLE_MAP.put("/returns.jsp", returnsPageOps);

        // ─── Maintenance/Service Requests module pass ─────────────────────────
        // maintenance.jsp was pinned to maintenanceViewOps (no DEPARTMENT_HEAD),
        // but the page's own code calls MaintenanceRequestDAO.getEmployeeMaintenance
        // RequestsForRole(role, userId), which has a deliberate, non-trivial
        // DEPARTMENT_HEAD branch: it resolves the caller's department (via
        // employees.user_id, falling back to departments.department_head_user_id)
        // and scopes the employee-maintenance-request table to it. That's not
        // incidental - it's a real, built feature for Department Heads to review
        // maintenance requests from their own department (view-only; the
        // Approve/Reject/Complete buttons still correctly stay restricted to
        // canManageMaintenance's narrower assetOps list). RoleAccessUtil was
        // blocking Department Heads from ever reaching the page this was built
        // for. Same "button/branch implies access" pattern as the allocation.jsp
        // and returns.jsp fixes above - widened to reportsPageOps (adds
        // DEPARTMENT_HEAD; matches assetOps + AUDITOR + DEPARTMENT_HEAD exactly).
        ROLE_MAP.put("/maintenance.jsp", reportsPageOps);
        ROLE_MAP.put("/maintenance_requests.jsp", reportsPageOps);
    }

    /**
     * Centralized role check with DEFAULT DENY.
     */
    public static boolean hasAccess(String role, String requestURI) {
        // Allow public paths (login, css, js, images, html, png, jpg, logout)
        // Also includes the pre-authentication account-recovery/activation flow -
        // these pages and servlets must be reachable by visitors with no session.
        if (requestURI.endsWith("/login.jsp") || requestURI.endsWith("/LoginServlet") || requestURI.endsWith("/logout.jsp") ||
            requestURI.endsWith("/forgot_password.jsp") || requestURI.endsWith("/ForgotPasswordServlet") ||
            requestURI.endsWith("/reset_password.jsp") || requestURI.endsWith("/ResetPasswordServlet") ||
            // public_asset_view.jsp/public_scan_result.jsp are the whole point of a public QR
            // tag - anyone scanning one is, by definition, not logged in. SecurityHeadersFilter
            // already treats these as public; this class didn't, and since role == null returns
            // false immediately below, every anonymous public QR scan was being redirected to
            // login.jsp by RoleAuthorizationFilter - the entire public-facing feature was broken
            // for the audience it exists for.
            requestURI.endsWith("/public_asset_view.jsp") || requestURI.endsWith("/public_scan_result.jsp") ||
            requestURI.contains("/css/") || requestURI.contains("/js/") || requestURI.contains("/images/") ||
            requestURI.endsWith(".html") || requestURI.endsWith(".png") || requestURI.endsWith(".jpg")) {
            return true;
        }

        if (role == null) return false;
        String upperRole = role.toUpperCase();

        boolean isSuperAdmin = "SUPER_ADMIN".equals(upperRole);

        // Exact match checking
        for (Map.Entry<String, List<String>> entry : ROLE_MAP.entrySet()) {
            if (requestURI.endsWith(entry.getKey())) {
                // SUPER_ADMIN is implicitly allowed on any path that IS explicitly
                // mapped here, even where that specific entry's author didn't list
                // it - e.g. "/dashboard.jsp" only lists ADMIN/ASSET_MANAGER/AUDITOR/
                // DEPARTMENT_HEAD, which was locking SUPER_ADMIN out of the
                // dashboard immediately after every login. This is deliberately
                // scoped to entries that exist in ROLE_MAP, NOT a blanket bypass:
                // RoleAccessUtilTest.testDefaultDenyForUnknownEndpoint asserts that
                // even SUPER_ADMIN must hit default-deny on a genuinely unmapped
                // path like "/api/hack" (defense in depth against a compromised
                // super-admin session probing for something that was never
                // supposed to exist) - that invariant is preserved below, this
                // branch never runs for paths that aren't in the loop at all.
                return isSuperAdmin || entry.getValue().contains(upperRole);
            }
        }

        // DEFAULT DENY for anything not explicitly mapped - applies to SUPER_ADMIN too.
        return false;
    }

    /**
     * Centralized role check for logical modules and actions.
     * Flagged: SUPER_ADMIN is currently NOT a standing implicit rule app-wide in RoleAccessUtil.
     * It must be explicitly mapped for every module/action.
     */
    public static boolean hasAccess(String role, String module, String action) {
        if (role == null) return false;
        String upperRole = role.toUpperCase();
        
        if ("DEPARTMENT_MANAGEMENT".equals(module)) {
            if ("VIEW".equals(action)) {
                return Arrays.asList("SUPER_ADMIN", "ADMIN", "DEPARTMENT_HEAD", "AUDITOR", "ASSET_MANAGER", "EMPLOYEE").contains(upperRole);
            }
            if ("CREATE".equals(action) || "EDIT".equals(action) || "DELETE".equals(action)) {
                return Arrays.asList("SUPER_ADMIN", "ADMIN").contains(upperRole);
            }
            if ("EXPORT".equals(action)) {
                return Arrays.asList("SUPER_ADMIN", "ADMIN", "DEPARTMENT_HEAD", "AUDITOR", "ASSET_MANAGER").contains(upperRole);
            }
        }
        
        return false;
    }
}
