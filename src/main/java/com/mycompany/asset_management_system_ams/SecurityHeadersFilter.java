package com.mycompany.asset_management_system_ams;

import java.io.IOException;
import java.util.Locale;

import jakarta.servlet.Filter;
import jakarta.servlet.FilterChain;
import jakarta.servlet.FilterConfig;
import jakarta.servlet.ServletException;
import jakarta.servlet.ServletRequest;
import jakarta.servlet.ServletResponse;
import jakarta.servlet.annotation.WebFilter;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import jakarta.servlet.http.HttpSession;

@WebFilter(filterName = "SecurityHeadersFilter", urlPatterns = {"/*"})
public class SecurityHeadersFilter implements Filter {

    @Override
    public void init(FilterConfig filterConfig) throws ServletException {
    }

    @Override
    public void doFilter(ServletRequest servletRequest, ServletResponse servletResponse, FilterChain chain)
            throws IOException, ServletException {

        HttpServletRequest request = (HttpServletRequest) servletRequest;
        HttpServletResponse response = (HttpServletResponse) servletResponse;

        // Bind IP/User-Agent for the lifetime of this request so AuditDAO.log()
        // (called from ~40+ places with no HttpServletRequest in scope) can pick
        // them up without threading a request parameter through every call
        // site. Cleared in the finally block below - Tomcat reuses worker
        // threads, so leaving this set would leak into whatever request runs
        // next on the same thread.
        RequestContext.set(resolveClientIp(request), request.getHeader("User-Agent"));

        try {
            applySecurityHeaders(response);

            String path = getRequestPath(request);

            if (isPublicPath(path)) {
                chain.doFilter(servletRequest, servletResponse);
                return;
            }

            HttpSession session = request.getSession(false);

            if (session == null
                    || session.getAttribute("username") == null
                    || session.getAttribute("role") == null) {
                response.sendRedirect(request.getContextPath() + "/login.jsp");
                return;
            }

            Boolean forcePasswordChange = (Boolean) session.getAttribute("force_password_change");
            if (forcePasswordChange != null && forcePasswordChange) {
                String lowerPath = path.toLowerCase(Locale.ENGLISH);
                if (!lowerPath.endsWith("/change_password.jsp") && !lowerPath.endsWith("/changepasswordservlet") && !lowerPath.endsWith("/logout.jsp")) {
                    response.sendRedirect(request.getContextPath() + "/change_password.jsp");
                    return;
                }
            }

            String role = normalizeRole(String.valueOf(session.getAttribute("role")));

            if (!isAllowedForRole(path, role)) {
                response.sendRedirect(request.getContextPath() + "/dashboard.jsp?access=denied");
                return;
            }

            chain.doFilter(servletRequest, servletResponse);
        } finally {
            RequestContext.clear();
        }
    }

    /**
     * Prefers X-Forwarded-For (first hop) over getRemoteAddr() so a request
     * arriving through the app's own ngrok/Cloudflare mobile-QR tunnel is
     * logged with the real client IP instead of the tunnel's local address.
     * Falls back to getRemoteAddr() when no forwarding header is present
     * (the normal, non-tunneled case).
     */
    private String resolveClientIp(HttpServletRequest request) {
        String forwarded = request.getHeader("X-Forwarded-For");
        if (forwarded != null && !forwarded.trim().isEmpty()) {
            String first = forwarded.split(",")[0].trim();
            if (!first.isEmpty()) {
                return first;
            }
        }
        String remoteAddr = request.getRemoteAddr();
        return remoteAddr == null ? "" : remoteAddr;
    }

    @Override
    public void destroy() {
    }

    private void applySecurityHeaders(HttpServletResponse response) {
        response.setHeader("X-Content-Type-Options", "nosniff");
        response.setHeader("X-Frame-Options", "SAMEORIGIN");
        response.setHeader("Referrer-Policy", "strict-origin-when-cross-origin");
        response.setHeader("Permissions-Policy", "camera=(self), geolocation=(), microphone=(self)");
        response.setHeader("Cache-Control", "no-store, no-cache, must-revalidate, max-age=0");
        response.setHeader("Pragma", "no-cache");
        response.setDateHeader("Expires", 0);
    }

    private String getRequestPath(HttpServletRequest request) {
        String contextPath = request.getContextPath();
        String uri = request.getRequestURI();

        if (contextPath != null && !contextPath.isEmpty() && uri.startsWith(contextPath)) {
            return uri.substring(contextPath.length());
        }

        return uri;
    }

    private boolean isPublicPath(String path) {
        String normalized = path == null ? "/" : path.trim();
        String lower = normalized.toLowerCase(Locale.ENGLISH);

        if (lower.equals("/")
                || lower.equals("/index.html")
                || lower.equals("/login.jsp")
                || lower.equals("/loginservlet")
                || lower.equals("/forgot_password.jsp")
                || lower.equals("/forgotpasswordservlet")
                || lower.equals("/reset_password.jsp")
                || lower.equals("/resetpasswordservlet")
                || lower.equals("/public_asset_view.jsp")
                || lower.equals("/public_scan_result.jsp")) {
            return true;
        }

        return lower.startsWith("/css/")
                || lower.startsWith("/js/")
                || lower.startsWith("/images/")
                || lower.startsWith("/assets/")
                || lower.startsWith("/fonts/")
                || lower.endsWith(".css")
                || lower.endsWith(".js")
                || lower.endsWith(".png")
                || lower.endsWith(".jpg")
                || lower.endsWith(".jpeg")
                || lower.endsWith(".webp")
                || lower.endsWith(".gif")
                || lower.endsWith(".ico")
                || lower.endsWith(".svg")
                || lower.endsWith(".woff")
                || lower.endsWith(".woff2")
                || lower.endsWith(".ttf");
    }

    private String normalizeRole(String role) {
        if (role == null) {
            return "";
        }

        return role.trim().toUpperCase(Locale.ENGLISH).replace(' ', '_');
    }

    private boolean isAllowedForRole(String path, String role) {
        String lower = path == null ? "/" : path.trim().toLowerCase(Locale.ENGLISH);

        if (lower.equals("/") || lower.isEmpty()) {
            lower = "/dashboard.jsp";
        }

        if ("SUPER_ADMIN".equals(role) || "ADMIN".equals(role)) {
            return true;
        }

        if (isAuthenticatedCommonPath(lower)) {
            return true;
        }

        if (isSuperAdminOnlyPath(lower)) {
            return false;
        }

        if (isDepartmentWritePath(lower)) {
            return false;
        }

        if ("ASSET_MANAGER".equals(role)) {
            return isAssetManagerPath(lower);
        }

        if ("DEPARTMENT_HEAD".equals(role)) {
            return isDepartmentHeadPath(lower);
        }

        if ("AUDITOR".equals(role)) {
            return isAuditorPath(lower);
        }

        if ("EMPLOYEE".equals(role)) {
            return isEmployeePath(lower);
        }

        return false;
    }

    private boolean isAuthenticatedCommonPath(String lower) {
        return lower.endsWith("/dashboard.jsp")
                || lower.endsWith("/dashboard_help.jsp")
                || lower.endsWith("/global_search.jsp")
                || lower.endsWith("/logout.jsp")
                || lower.endsWith("/change_password.jsp")
                || lower.endsWith("/changepasswordservlet")
                || lower.endsWith("/ams_copilot.jsp")
                || lower.endsWith("/copilotservlet")
                || lower.endsWith("/copilotreportexportservlet")
                // Fault: both were previously listed in isSuperAdminOnlyPath()
                // below, which blocks every role except SUPER_ADMIN/ADMIN (those
                // two bypass this whole method via the blanket check above). But
                // RoleAccessUtil's ROLE_MAP puts both pages in commonOps (ADMIN,
                // ASSET_MANAGER, AUDITOR, DEPARTMENT_HEAD, EMPLOYEE), and
                // alert_center.jsp's own internal logic computes a per-role
                // canViewAdminData flag to show a reduced view rather than deny
                // entry - so ASSET_MANAGER/AUDITOR/DEPARTMENT_HEAD/EMPLOYEE were
                // all wrongly locked out of both pages. Moved here to match the
                // intended "any authenticated role" access.
                || lower.endsWith("/alert_center.jsp")
                || lower.endsWith("/overdue_actions.jsp")
                // Fault: same commonOps mismatch - notifications.jsp had no entry
                // in any role-specific gate except a since-added EMPLOYEE-only
                // one, leaving ASSET_MANAGER/AUDITOR/DEPARTMENT_HEAD still locked
                // out even though RoleAccessUtil's commonOps covers them too.
                || lower.endsWith("/notifications.jsp")
                // Fault (found in a full audit against RoleAccessUtil): every path
                // below is mapped there to the exact same commonOps list (ADMIN,
                // ASSET_MANAGER, AUDITOR, DEPARTMENT_HEAD, EMPLOYEE - i.e. every
                // real authenticated role) - so they belong here, checked once
                // before role dispatch, rather than duplicated piecemeal across
                // isAssetManagerPath/isDepartmentHeadPath/isAuditorPath/
                // isEmployeePath (where most were simply missing from 2-3 of the
                // four, silently blocking that role regardless of RoleAccessUtil).
                || lower.endsWith("/testcopilotconnectionservlet")
                || lower.endsWith("/copilotfeedbackservlet")
                || lower.endsWith("/copilotquickstatsservlet")
                || lower.endsWith("/scan_result.jsp")
                || lower.endsWith("/copilot_quick_stats.jsp")
                || lower.endsWith("/copilot_chat_history.jsp")
                || lower.endsWith("/employee_dashboard.jsp")
                || lower.endsWith("/employee_profile.jsp")
                || lower.endsWith("/submitprofilechangerequestservlet")
                || lower.endsWith("/employee_assets.jsp")
                || lower.endsWith("/new_employee_asset_request.jsp")
                || lower.endsWith("/employee_requests.jsp")
                || lower.endsWith("/employee_returns.jsp")
                || lower.endsWith("/asset_qr_card.jsp")
                || lower.endsWith("/qr_print.jsp")
                || lower.endsWith("/qr_scanner.jsp")
                || lower.endsWith("/view_allocation.jsp")
                || lower.endsWith("/view_category.jsp")
                || lower.endsWith("/view_location.jsp")
                || lower.endsWith("/view_maintenance.jsp")
                || lower.endsWith("/maintenance_history.jsp")
                || lower.endsWith("/view_return.jsp")
                || lower.endsWith("/view_vendor.jsp")
                || lower.endsWith("/downloadvendordocumentservlet");
    }

    private boolean isSuperAdminOnlyPath(String lower) {
        return lower.endsWith("/settings.jsp")
                || lower.endsWith("/backup_restore.jsp")
                || lower.endsWith("/database_backup_export.jsp")
                || lower.endsWith("/manage_roles.jsp")
                || lower.endsWith("/notification_settings.jsp")
                || lower.endsWith("/currency_settings.jsp")
                || lower.endsWith("/test_email.jsp")
                || lower.endsWith("/backupdatabaseservlet")
                || lower.endsWith("/restoredatabaseservlet")
                || lower.endsWith("/savesettingsservlet")
                || lower.endsWith("/updateuserroleservlet")
                || lower.endsWith("/updatenotificationsettingsservlet")
                || lower.endsWith("/updatecurrencysettingsservlet")
                || lower.endsWith("/sendtestemailservlet")
                || lower.endsWith("/tunnelcontrolservlet")
                || lower.endsWith("/cloudflaretunnelservlet")
                // Fault (full audit against RoleAccessUtil): db_status.jsp
                // (qrViewOps: SA/ADMIN/ASSET_MANAGER/AUDITOR) and access_matrix.jsp
                // (auditorOps: SA/ADMIN/AUDITOR) were both force-denied here for
                // every role but SUPER_ADMIN/ADMIN, before the role-specific check
                // ever ran - blocking ASSET_MANAGER/AUDITOR from pages RoleAccessUtil
                // explicitly grants them. Moved to isQrViewPath/isAuditPath (below)
                // respectively, where the normal per-role dispatch actually applies.
                //
                // edit_profile.jsp/UpdateProfileServlet is the opposite fault: it's
                // the ADMIN-only organization-settings page (org name/contact email/
                // support phone via SettingsDAO - not a personal user-profile page,
                // despite the name), gated ADMIN-only by its own code and by
                // RoleAccessUtil's adminOnly - but was previously in
                // isAuthenticatedCommonPath, silently letting every other role
                // through this filter. Moved here to match.
                || lower.endsWith("/edit_profile.jsp")
                || lower.endsWith("/updateprofileservlet");
    }

    private boolean isDepartmentWritePath(String lower) {
        return lower.endsWith("/add_department.jsp")
                || lower.endsWith("/edit_department.jsp")
                || lower.endsWith("/adddepartmentservlet")
                || lower.endsWith("/updatedepartmentservlet")
                || lower.endsWith("/deletedepartmentservlet");
    }

    private boolean isDepartmentReadPath(String lower) {
        return lower.endsWith("/departments.jsp")
                || lower.endsWith("/view_department.jsp")
                || lower.endsWith("/export_departments_excel.jsp");
    }

    private boolean isAssetReadPath(String lower) {
        return lower.endsWith("/assets.jsp")
                || lower.endsWith("/view_asset.jsp")
                || lower.endsWith("/asset_documents.jsp")
                || lower.endsWith("/downloadassetdocumentservlet");
    }

    private boolean isAssetManagePath(String lower) {
        return isAssetReadPath(lower)
                || lower.endsWith("/add_asset.jsp")
                || lower.endsWith("/edit_asset.jsp")
                || lower.endsWith("/dispose_asset.jsp")
                || lower.endsWith("/view_disposal.jsp")
                || lower.endsWith("/addassetservlet")
                || lower.endsWith("/updateassetservlet")
                || lower.endsWith("/disposeassetservlet")
                || lower.endsWith("/uploadassetdocumentservlet")
                || lower.endsWith("/generateassetqrservlet")
                || lower.endsWith("/renew_warranty.jsp")
                || lower.endsWith("/renewassetwarrantyservlet");
    }

    // DEPARTMENT_HEAD's employee view+manage set - matches RoleAccessUtil's
    // employeeManageOps (add/edit/transfer/retire/delete/disable/documents)
    // and employeeViewOps (view+download) exactly, both of which include
    // DEPARTMENT_HEAD. Deliberately NOT generateemployeeloginservlet - that one
    // is assetOps only (ASSET_MANAGER, not DEPARTMENT_HEAD), so it lives
    // directly in isAssetManagerPath instead.
    //
    // Fault (full audit against RoleAccessUtil): transfer_employee.jsp/
    // TransferEmployeeServlet/retire_employee.jsp/RetireEmployeeServlet -
    // the employee transfer/retirement feature RoleAccessUtil's own comment
    // says was "built... for Department Heads" - plus DeleteEmployeeServlet/
    // DisableEmployeeServlet/UploadEmployeeDocumentServlet/
    // DeleteEmployeeDocumentServlet/UploadEmployeeProfileImageServlet/
    // DownloadEmployeeDocumentServlet, were all missing from this method
    // entirely, silently blocking every one of them for DEPARTMENT_HEAD
    // regardless of RoleAccessUtil.
    private boolean isEmployeePathForManagers(String lower) {
        return lower.endsWith("/employees.jsp")
                || lower.endsWith("/view_employee.jsp")
                || lower.endsWith("/add_employee.jsp")
                || lower.endsWith("/edit_employee.jsp")
                || lower.endsWith("/addemployeeservlet")
                || lower.endsWith("/updateemployeeservlet")
                || lower.endsWith("/deleteemployeeservlet")
                || lower.endsWith("/disableemployeeservlet")
                || lower.endsWith("/uploademployeedocumentservlet")
                || lower.endsWith("/deleteemployeedocumentservlet")
                || lower.endsWith("/uploademployeeprofileimageservlet")
                || lower.endsWith("/downloademployeedocumentservlet")
                || lower.endsWith("/transfer_employee.jsp")
                || lower.endsWith("/transferemployeeservlet")
                || lower.endsWith("/retire_employee.jsp")
                || lower.endsWith("/retireemployeeservlet");
    }

    private boolean isCatalogPath(String lower) {
        return lower.endsWith("/categories.jsp")
                || lower.endsWith("/add_category.jsp")
                || lower.endsWith("/edit_category.jsp")
                || lower.endsWith("/view_category.jsp")
                || lower.endsWith("/vendors.jsp")
                || lower.endsWith("/add_vendor.jsp")
                || lower.endsWith("/edit_vendor.jsp")
                || lower.endsWith("/view_vendor.jsp")
                || lower.endsWith("/uploadvendordocumentservlet")
                || lower.endsWith("/downloadvendordocumentservlet")
                || lower.endsWith("/category_vendor_mapping.jsp")
                || lower.endsWith("/addcategoryservlet")
                || lower.endsWith("/updatecategoryservlet")
                || lower.endsWith("/updatecategorystatusservlet")
                || lower.endsWith("/addvendorservlet")
                || lower.endsWith("/updatevendorservlet")
                || lower.endsWith("/deletevendorservlet")
                || lower.endsWith("/addcategoryvendormappingservlet")
                || lower.endsWith("/updatecategoryvendormappingstatusservlet");
    }

    // add_request.jsp/view_request.jsp/AddAssetRequestServlet - RoleAccessUtil's
    // allEmployeeOps (view/create, open to every real role including EMPLOYEE).
    // Deliberately separate from the approval-only pair below.
    private boolean isRequestViewCreatePath(String lower) {
        return lower.endsWith("/add_request.jsp")
                || lower.endsWith("/view_request.jsp")
                || lower.endsWith("/addassetrequestservlet");
    }

    // asset_requests.jsp/UpdateRequestStatusServlet - RoleAccessUtil's
    // requestApprovalOps (SUPER_ADMIN/ADMIN/ASSET_MANAGER only - "Step 1
    // decision, DEPARTMENT_HEAD removed", per that entry's own comment).
    private boolean isRequestApprovalPath(String lower) {
        return lower.endsWith("/asset_requests.jsp")
                || lower.endsWith("/updaterequeststatusservlet");
    }

    private boolean isRequestPath(String lower) {
        return isRequestViewCreatePath(lower) || isRequestApprovalPath(lower);
    }

    private boolean isAllocationPath(String lower) {
        return lower.endsWith("/allocation.jsp")
                || lower.endsWith("/add_allocation.jsp")
                || lower.endsWith("/view_allocation.jsp")
                || lower.endsWith("/addallocationservlet")
                || lower.endsWith("/returnallocationservlet");
    }

    private boolean isReturnPath(String lower) {
        return lower.endsWith("/returns.jsp")
                || lower.endsWith("/add_return.jsp")
                || lower.endsWith("/view_return.jsp")
                || lower.endsWith("/addreturnservlet");
    }

    private boolean isMaintenanceReadPath(String lower) {
        return lower.endsWith("/maintenance.jsp")
                || lower.endsWith("/view_maintenance.jsp")
                || lower.endsWith("/maintenance_history.jsp");
    }

    private boolean isMaintenanceManagePath(String lower) {
        return isMaintenanceReadPath(lower)
                || lower.endsWith("/add_maintenance.jsp")
                || lower.endsWith("/edit_maintenance.jsp")
                || lower.endsWith("/schedule_service.jsp")
                || lower.endsWith("/resolve_maintenance.jsp")
                || lower.endsWith("/addmaintenanceservlet")
                || lower.endsWith("/updatemaintenanceservlet");
    }

    private boolean isVerificationPath(String lower) {
        return lower.endsWith("/physical_verification.jsp")
                || lower.endsWith("/view_verification.jsp")
                || lower.endsWith("/addphysicalverificationservlet")
                || lower.endsWith("/schedulephysicalverificationdutyservlet")
                || lower.endsWith("/exportphysicalverificationreportservlet")
                // my_physical_verification_duties.jsp is the self-service duty
                // list/submit page any assigned officer uses; assetsearchservlet
                // is the asset-picker autocomplete both that page and
                // physical_verification.jsp's own submit form call. Neither was
                // listed here before, so ASSET_MANAGER/DEPARTMENT_HEAD/AUDITOR
                // (all of which route through this same method) were blocked at
                // this filter regardless of what RoleAccessUtil separately allows.
                || lower.endsWith("/my_physical_verification_duties.jsp")
                || lower.endsWith("/assetsearchservlet")
                // Duty-level checker (approve to COMPLETED / send back to
                // IN_PROGRESS) and the officer's own "mark my duty complete"
                // self-service action - both new, same gap as the rest of this
                // method's history: RoleAccessUtil already allows them, this
                // second gate did not until now.
                || lower.endsWith("/reviewphysicalverificationdutyservlet")
                || lower.endsWith("/completephysicalverificationdutyservlet");
    }

    private boolean isReportPath(String lower) {
        return lower.endsWith("/reports.jsp")
                || lower.endsWith("/analytics.jsp")
                || lower.endsWith("/asset_health.jsp")
                || lower.endsWith("/warranty_report.jsp")
                || lower.endsWith("/export_asset_report.jsp")
                || lower.endsWith("/export_allocation_report.jsp")
                || lower.endsWith("/export_disposal_report.jsp")
                || lower.endsWith("/export_employee_report.jsp")
                || lower.endsWith("/export_maintenance.jsp")
                || lower.endsWith("/export_requests_report.jsp")
                || lower.endsWith("/export_returns_report.jsp")
                // Fault: RoleAccessUtil's reportExportOps (and reports.jsp's own
                // report card) both allow this new export the same as every other
                // one here, but this second, independent gate never learned about
                // it - same class of gap as the others already documented in this
                // method, just introduced when the page itself was added rather
                // than pre-existing.
                || lower.endsWith("/export_transfer_report.jsp")
                || lower.endsWith("/export_warranty_report.jsp")
                || lower.endsWith("/view_warranty_history.jsp");
    }

    private boolean isAuditPath(String lower) {
        return lower.endsWith("/audit_logs.jsp")
                || lower.endsWith("/view_audit_log.jsp")
                || lower.endsWith("/export_audit_logs.jsp")
                // Moved out of isSuperAdminOnlyPath - RoleAccessUtil's auditorOps
                // (SA/ADMIN/AUDITOR) grants this, matching the rest of this
                // method's reviewer set exactly (deliberately NOT called from
                // isAssetManagerPath below - ASSET_MANAGER has no audit-log
                // access per RoleAccessUtil's own documented policy).
                || lower.endsWith("/access_matrix.jsp");
    }

    private boolean isQrViewPath(String lower) {
        return lower.contains("/qr_")
                // Moved out of isSuperAdminOnlyPath - RoleAccessUtil's qrViewOps
                // (SA/ADMIN/ASSET_MANAGER/AUDITOR) grants this the same as every
                // other page in this method.
                || lower.endsWith("/db_status.jsp")
                || lower.contains("/asset_qr_card.jsp")
                || lower.contains("/asset_register_card.jsp")
                || lower.contains("/view_qr_scan_log.jsp");
    }

    private boolean isQrManagePath(String lower) {
        return lower.endsWith("/qr_bulk_generate.jsp")
                || lower.endsWith("/qr_url_refresh.jsp")
                || lower.endsWith("/qr_token_reissue.jsp")
                || lower.endsWith("/qr_reissue_history.jsp")
                || lower.endsWith("/bulkgenerateassetqrservlet")
                || lower.endsWith("/manageqrurlsservlet")
                || lower.endsWith("/refreshassetqrurlsservlet")
                || lower.endsWith("/refreshassetqrurlservlet")
                || lower.endsWith("/reissueassetqrtokenservlet")
                || lower.endsWith("/updateqrtaggingstatusservlet");
    }

    private boolean isAssetManagerPath(String lower) {
        return isAssetManagePath(lower)
                || isDepartmentReadPath(lower)
                || isCatalogPath(lower)
                || isRequestPath(lower)
                || isAllocationPath(lower)
                || isReturnPath(lower)
                || isMaintenanceManagePath(lower)
                || isVerificationPath(lower)
                || isReportPath(lower)
                || isQrViewPath(lower)
                || isQrManagePath(lower)
                // Fault (full audit against RoleAccessUtil): this used to also
                // call isEmployeePathForManagers(lower) and isAuditPath(lower),
                // but RoleAccessUtil's employeeManageOps/employeeViewOps and
                // auditorOps both deliberately EXCLUDE ASSET_MANAGER (the latter
                // with an explicit "ASSET_MANAGER has no audit-log access"
                // policy comment) - this filter was silently wider than the
                // documented policy for both. GenerateEmployeeLoginServlet is
                // the one employee-management endpoint ASSET_MANAGER genuinely
                // does get (assetOps), so it moves here on its own instead.
                || lower.endsWith("/generateemployeeloginservlet")
                // Fault: missing entirely (confirmed by grep) despite assetOps
                // (SUPER_ADMIN/ADMIN/ASSET_MANAGER) granting it in RoleAccessUtil.
                || lower.endsWith("/updatemaintenancerequeststatusservlet")
                // Fault: none of these six were listed anywhere in this filter at
                // all (confirmed with a full-file grep), even though
                // RoleAccessUtil's reportExportOps/assetOps/allEmployeeOps/
                // commonOps and each page/servlet's own internal role check all
                // already grant ASSET_MANAGER access - this second, independent
                // gate silently blocked the entire Asset Transfers and Asset
                // Disposals review/create modules for every role except
                // SUPER_ADMIN/ADMIN (who bypass this method entirely), regardless
                // of what those other checks separately allow.
                || lower.endsWith("/asset_disposals.jsp")
                || lower.endsWith("/reviewassetdisposalservlet")
                || lower.endsWith("/asset_transfers.jsp")
                || lower.endsWith("/reviewassettransferservlet")
                || lower.endsWith("/submitassettransferservlet")
                || lower.endsWith("/employee_assets.jsp");
    }

    private boolean isDepartmentHeadPath(String lower) {
        return isAssetReadPath(lower)
                // Fault (full audit against RoleAccessUtil): was a hand-listed
                // 6-entry subset of isEmployeePathForManagers - see that method's
                // own comment for the transfer/retire/document-management
                // entries this was missing entirely.
                || isEmployeePathForManagers(lower)
                || isDepartmentReadPath(lower)
                // Fault (full audit against RoleAccessUtil): was the full
                // isRequestPath() (view/create + approval) - but RoleAccessUtil's
                // requestApprovalOps explicitly excludes DEPARTMENT_HEAD from
                // asset_requests.jsp/UpdateRequestStatusServlet ("Step 1 decision,
                // DEPARTMENT_HEAD removed") while allEmployeeOps still grants the
                // view/create pair. Narrowed to match.
                || isRequestViewCreatePath(lower)
                // Fault: maintenance.jsp itself already reaches DEPARTMENT_HEAD via
                // isReportPath below, but view_maintenance.jsp/maintenance_history.jsp
                // (commonOps, includes DEPARTMENT_HEAD) were never listed anywhere
                // reachable from this method.
                || isMaintenanceReadPath(lower)
                || lower.endsWith("/view_location.jsp")
                // Fault: RoleAccessUtil's reportsPageOps (and reports.jsp/
                // analytics.jsp's own internal role checks) both explicitly
                // include DEPARTMENT_HEAD, but this gate never called
                // isReportPath() the way isAssetManagerPath/isAuditorPath do -
                // department heads were blocked from both report pages.
                || isReportPath(lower)
                // Fault: same class of gap - RoleAccessUtil's deptHeadOps grants
                // DEPARTMENT_HEAD both role_assignment.jsp/RoleAssignmentServlet
                // (pre-existing) and, as of profile-change-request review now
                // being opened up to department heads, user_profile_requests.jsp/
                // ReviewProfileChangeRequestServlet too - none of the four were
                // ever listed here, so DEPARTMENT_HEAD was blocked at this gate
                // regardless of what RoleAccessUtil or the pages themselves allow.
                || lower.endsWith("/role_assignment.jsp")
                || lower.endsWith("/roleassignmentservlet")
                || lower.endsWith("/user_profile_requests.jsp")
                || lower.endsWith("/reviewprofilechangerequestservlet")
                // Fault: same class of gap as above - RoleAccessUtil's commonOps
                // (employee_assets.jsp) and allEmployeeOps (SubmitAssetTransferServlet)
                // both include DEPARTMENT_HEAD, but neither was listed here.
                || lower.endsWith("/employee_assets.jsp")
                || lower.endsWith("/submitassettransferservlet");
    }

    private boolean isAuditorPath(String lower) {
        // Fault: downloademployeedocumentservlet added to the read-only
        // exemption list below - RoleAccessUtil's employeeViewOps includes
        // AUDITOR for it, same reasoning as the pre-existing
        // downloadassetdocumentservlet exemption.
        if (isQrManagePath(lower)
                || lower.contains("/add_")
                || lower.contains("/edit_")
                || lower.endsWith("servlet") && !lower.endsWith("/downloadassetdocumentservlet")
                && !lower.endsWith("/exportphysicalverificationreportservlet")
                && !lower.endsWith("/downloademployeedocumentservlet")) {
            return false;
        }

        return isAssetReadPath(lower)
                || isDepartmentReadPath(lower)
                || isMaintenanceReadPath(lower)
                || isVerificationPath(lower)
                || isReportPath(lower)
                || isAuditPath(lower)
                || isQrViewPath(lower)
                || lower.endsWith("/view_location.jsp")
                // Fault: RoleAccessUtil's reportExportOps/commonOps both include
                // AUDITOR for these two read-only .jsp pages; neither was listed
                // here. (The write-side servlets for both modules stay correctly
                // blocked below by this method's own blanket "servlet" rule, same
                // as every other write action for this read-only role.)
                || lower.endsWith("/asset_disposals.jsp")
                || lower.endsWith("/employee_assets.jsp")
                // Fault (full audit against RoleAccessUtil): none of these three
                // groups were reachable for AUDITOR at all. The write-side pages/
                // servlets inside each (add_vendor.jsp, AddReturnServlet,
                // AddAllocationServlet, add_employee.jsp, DeleteEmployeeServlet,
                // etc.) are still correctly blocked by this method's own guard
                // above (the "/add_"/"/edit_"/blanket-servlet rules), leaving
                // only the read-only pages RoleAccessUtil actually grants AUDITOR
                // (categories.jsp/view_category.jsp/vendors.jsp/view_vendor.jsp/
                // category_vendor_mapping.jsp via isCatalogPath; returns.jsp/
                // view_return.jsp via isReturnPath; allocation.jsp/
                // view_allocation.jsp via isAllocationPath; employees.jsp/
                // view_employee.jsp/DownloadEmployeeDocumentServlet - exempted
                // above - via isEmployeePathForManagers) actually reachable.
                || isCatalogPath(lower)
                || isReturnPath(lower)
                || isAllocationPath(lower)
                || isEmployeePathForManagers(lower);
    }

    private boolean isEmployeePath(String lower) {
        return lower.endsWith("/employee_dashboard.jsp")
                || lower.endsWith("/employee_profile.jsp")
                || lower.endsWith("/employee_assets.jsp")
                || lower.endsWith("/employee_requests.jsp")
                || lower.endsWith("/new_employee_asset_request.jsp")
                || lower.endsWith("/employee_returns.jsp")
                || lower.endsWith("/view_request.jsp")
                || lower.endsWith("/addassetrequestservlet")
                // Fault: add_request.jsp's own gate explicitly allows EMPLOYEE
                // (matches RoleAccessUtil's allEmployeeOps) - missing here.
                || lower.endsWith("/add_request.jsp")
                // Reachable from employee_profile.jsp's "Request a Profile
                // Change" form - kept in the same role group as that page,
                // matching its own existing (narrower than RoleAccessUtil's
                // commonOps) effective access here.
                || lower.endsWith("/submitprofilechangerequestservlet")
                // Fault: employee_maintenance_request.jsp / employee_transfer_
                // preference.jsp (and the servlets their forms POST to) already
                // had matching EMPLOYEE-only entries in RoleAccessUtil and each
                // page's own internal role check requires EMPLOYEE exactly - but
                // this method, the definitive gate actually consulted for the
                // EMPLOYEE role, never listed any of the four, so every request
                // (GET the page or POST the form) was blocked here before ever
                // reaching the page/servlet's own check. Both employee self-
                // service features were completely inaccessible to the only
                // role meant to use them. Fix: add all four.
                || lower.endsWith("/employee_maintenance_request.jsp")
                || lower.endsWith("/employee_transfer_preference.jsp")
                || lower.endsWith("/employeemaintenancerequestservlet")
                || lower.endsWith("/submitemployeetransferpreferenceservlet")
                // Self-service physical verification duty list/submit - deliberately
                // NOT the whole isVerificationPath() group (that also covers
                // physical_verification.jsp/view_verification.jsp/schedule/export,
                // which stay admin-only per RoleAccessUtil's verificationViewOps/
                // assetOps - EMPLOYEE gets only these three, matching the narrower
                // self-service RBAC entries added there).
                || lower.endsWith("/my_physical_verification_duties.jsp")
                || lower.endsWith("/addphysicalverificationservlet")
                || lower.endsWith("/assetsearchservlet")
                // Officer's own "mark my duty complete" self-service action -
                // same self-service group as the three just above, gated the
                // rest of the way by the servlet's own ownership check (only
                // the employee actually assigned to that duty). Deliberately
                // NOT reviewphysicalverificationdutyservlet - approving/sending
                // back a duty stays admin/asset-manager only, same as the
                // isVerificationPath() comment above explains for the page-level
                // equivalent.
                || lower.endsWith("/completephysicalverificationdutyservlet")
                // Fault: RoleAccessUtil's allEmployeeOps grants EMPLOYEE this
                // servlet too (it's the form action behind employee_assets.jsp's
                // own "Request Transfer" button, already listed above) - not
                // listed here, so an ordinary employee could reach the page and
                // see the button but every actual submission attempt was
                // silently blocked at this filter.
                || lower.endsWith("/submitassettransferservlet")
                // Fault (full audit against RoleAccessUtil): the self-service
                // "return my own allocated asset" flow - returnOps/returnsPageOps
                // both explicitly include EMPLOYEE ("an employee returning their
                // own allocated item", per RoleAccessUtil's own comment) - none of
                // these four were listed here at all, so an ordinary employee
                // could never actually submit a return.
                || lower.endsWith("/returns.jsp")
                || lower.endsWith("/add_return.jsp")
                || lower.endsWith("/addreturnservlet")
                || lower.endsWith("/returnallocationservlet");
        // notifications.jsp/alert_center.jsp moved to isAuthenticatedCommonPath()
        // above - they're commonOps in RoleAccessUtil (every real role, not just
        // EMPLOYEE), and isAuthenticatedCommonPath is checked before role
        // dispatch even reaches this method, so listing them here too would
        // just be dead code.
    }
}
