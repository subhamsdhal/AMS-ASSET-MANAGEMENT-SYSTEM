<%@page contentType="text/html" pageEncoding="UTF-8"%>
<%
    String sidebarUserRole = "";
    Object sidebarRoleObj = session.getAttribute("role");
    if (sidebarRoleObj != null) {
        sidebarUserRole = sidebarRoleObj.toString()
                .trim()
                .toUpperCase(java.util.Locale.ENGLISH)
                .replace(" ", "_")
                .replace("&", "&amp;")
                .replace("<", "&lt;")
                .replace(">", "&gt;")
                .replace("\"", "&quot;")
                .replace("'", "&#39;");
    }
    
    boolean isFullAccess = "SUPER_ADMIN".equals(sidebarUserRole) || "ADMIN".equals(sidebarUserRole);
%>
<aside class="sidebar railway-sidebar" data-user-role="<%= sidebarUserRole %>">
        <div class="logo-box railway-brand">
            <div class="railway-sidebar-brand-center">
                <img src="images/indian-railway-logo.png" alt="Indian Railways">

                <div class="logo-text">
                    <span class="railway-title-hindi">भारतीय रेल</span>
                    <span class="railway-title-english">INDIAN RAILWAYS</span>

                    <span class="railway-zone-name">
                        पूर्व तट रेलवे<br>
                        EAST COAST RAILWAY
                    </span>

                    <div class="railway-office-block">
                        मुख्यालय / रेल सदन<br>
                        HEADQUARTERS / RAIL SADAN<br>
                        भुवनेश्वर, ओडिशा<br>
                        BHUBANESWAR, ODISHA
                    </div>
                </div>
            </div>
        </div>

        <%!
    private static final java.util.Map<String, String> MENU_MAP = new java.util.HashMap<>();
    static {
        MENU_MAP.put("dashboard.jsp", "dashboard");
        MENU_MAP.put("employee_dashboard.jsp", "dashboard");
        MENU_MAP.put("global_search.jsp", "dashboard");
        MENU_MAP.put("assets.jsp", "assets");
        MENU_MAP.put("add_asset.jsp", "assets");
        MENU_MAP.put("edit_asset.jsp", "assets");
        MENU_MAP.put("view_asset.jsp", "assets");
        MENU_MAP.put("asset_documents.jsp", "assets");
        MENU_MAP.put("employees.jsp", "employees");
        MENU_MAP.put("add_employee.jsp", "employees");
        MENU_MAP.put("edit_employee.jsp", "employees");
        MENU_MAP.put("view_employee.jsp", "employees");
        MENU_MAP.put("edit_profile.jsp", "employees");
        MENU_MAP.put("departments.jsp", "departments");
        MENU_MAP.put("add_department.jsp", "departments");
        MENU_MAP.put("edit_department.jsp", "departments");
        MENU_MAP.put("view_department.jsp", "departments");
        MENU_MAP.put("export_departments_excel.jsp", "departments");
        MENU_MAP.put("categories.jsp", "categories");
        MENU_MAP.put("add_category.jsp", "categories");
        MENU_MAP.put("edit_category.jsp", "categories");
        MENU_MAP.put("view_category.jsp", "categories");
        MENU_MAP.put("vendors.jsp", "vendors");
        MENU_MAP.put("add_vendor.jsp", "vendors");
        MENU_MAP.put("edit_vendor.jsp", "vendors");
        MENU_MAP.put("view_vendor.jsp", "vendors");
        MENU_MAP.put("category_vendor_mapping.jsp", "category_vendor_mapping");
        MENU_MAP.put("asset_requests.jsp", "asset_requests");
        MENU_MAP.put("dept_head_asset_requests.jsp", "dept_head_asset_requests");
        MENU_MAP.put("asset_disposals.jsp", "asset_disposals");
        MENU_MAP.put("view_disposal.jsp", "asset_disposals");
        MENU_MAP.put("asset_transfers.jsp", "asset_transfers");
        MENU_MAP.put("add_request.jsp", "asset_requests");
        MENU_MAP.put("view_request.jsp", "asset_requests");
        MENU_MAP.put("allocation.jsp", "allocation");
        MENU_MAP.put("add_allocation.jsp", "allocation");
        MENU_MAP.put("view_allocation.jsp", "allocation");
        MENU_MAP.put("returns.jsp", "returns");
        MENU_MAP.put("add_return.jsp", "returns");
        MENU_MAP.put("view_return.jsp", "returns");
        MENU_MAP.put("maintenance.jsp", "maintenance");
        MENU_MAP.put("add_maintenance.jsp", "maintenance");
        MENU_MAP.put("edit_maintenance.jsp", "maintenance");
        MENU_MAP.put("view_maintenance.jsp", "maintenance");
        MENU_MAP.put("schedule_service.jsp", "maintenance");
        MENU_MAP.put("resolve_maintenance.jsp", "maintenance");
        MENU_MAP.put("maintenance_history.jsp", "maintenance");
        MENU_MAP.put("dispose_asset.jsp", "disposal");
        MENU_MAP.put("view_disposal.jsp", "disposal");
        MENU_MAP.put("physical_verification.jsp", "physical_verification");
        MENU_MAP.put("view_verification.jsp", "physical_verification");
        MENU_MAP.put("my_physical_verification_duties.jsp", "my_physical_verification");
        MENU_MAP.put("reports.jsp", "reports");
        MENU_MAP.put("analytics.jsp", "reports");
        MENU_MAP.put("warranty_report.jsp", "reports");
        MENU_MAP.put("export_allocation_report.jsp", "reports");
        MENU_MAP.put("export_asset_report.jsp", "reports");
        MENU_MAP.put("export_disposal_report.jsp", "reports");
        MENU_MAP.put("export_employee_report.jsp", "reports");
        MENU_MAP.put("export_maintenance.jsp", "reports");
        MENU_MAP.put("export_requests_report.jsp", "reports");
        MENU_MAP.put("export_returns_report.jsp", "reports");
        MENU_MAP.put("audit_logs.jsp", "audit_logs");
        MENU_MAP.put("view_audit_log.jsp", "audit_logs");
        MENU_MAP.put("export_audit_logs.jsp", "audit_logs");
        MENU_MAP.put("qr_scanner.jsp", "qr_control_center");
        MENU_MAP.put("scan_result.jsp", "qr_control_center");
        MENU_MAP.put("public_scan_result.jsp", "qr_control_center");
        MENU_MAP.put("qr_control_center.jsp", "qr_control_center");
        MENU_MAP.put("qr_bulk_generate.jsp", "qr_control_center");
        MENU_MAP.put("qr_print.jsp", "qr_control_center");
        MENU_MAP.put("qr_print_labels.jsp", "qr_control_center");
        MENU_MAP.put("qr_tags.jsp", "qr_control_center");
        MENU_MAP.put("qr_token_lookup.jsp", "qr_control_center");
        MENU_MAP.put("qr_token_reissue.jsp", "qr_control_center");
        MENU_MAP.put("qr_url_refresh.jsp", "qr_control_center");
        MENU_MAP.put("asset_qr_card.jsp", "qr_control_center");
        MENU_MAP.put("qr_tagging_work_order.jsp", "qr_control_center");
        MENU_MAP.put("qr_asset_register.jsp", "qr_control_center");
        MENU_MAP.put("asset_register_card.jsp", "qr_control_center");
        MENU_MAP.put("export_qr_asset_register.jsp", "qr_control_center");
        MENU_MAP.put("qr_tagging_status.jsp", "qr_control_center");
        MENU_MAP.put("export_qr_tagging_status.jsp", "qr_control_center");
        MENU_MAP.put("export_qr_tagging_status_excel.jsp", "qr_control_center");
        MENU_MAP.put("qr_scan_logs.jsp", "qr_control_center");
        MENU_MAP.put("view_qr_scan_log.jsp", "qr_control_center");
        MENU_MAP.put("export_qr_scan_logs.jsp", "qr_control_center");
        MENU_MAP.put("qr_asset_scan_history.jsp", "qr_control_center");
        MENU_MAP.put("export_qr_asset_scan_history_excel.jsp", "qr_control_center");
        MENU_MAP.put("qr_coverage_report.jsp", "qr_control_center");
        MENU_MAP.put("export_qr_coverage_report_excel.jsp", "qr_control_center");
        MENU_MAP.put("qr_exception_report.jsp", "qr_control_center");
        MENU_MAP.put("export_qr_exception_report_excel.jsp", "qr_control_center");
        MENU_MAP.put("qr_ip_audit_report.jsp", "qr_control_center");
        MENU_MAP.put("export_qr_ip_audit_excel.jsp", "qr_control_center");
        MENU_MAP.put("qr_missing_qr_report.jsp", "qr_control_center");
        MENU_MAP.put("export_qr_missing_qr_excel.jsp", "qr_control_center");
        MENU_MAP.put("qr_reissue_history.jsp", "qr_control_center");
        MENU_MAP.put("export_qr_reissue_history_excel.jsp", "qr_control_center");
        MENU_MAP.put("qr_scan_analytics.jsp", "qr_control_center");
        MENU_MAP.put("export_qr_scan_analytics_excel.jsp", "qr_control_center");
        MENU_MAP.put("qr_system_health.jsp", "qr_control_center");
        MENU_MAP.put("ams_copilot.jsp", "ams_copilot");
        MENU_MAP.put("copilot_quick_stats.jsp", "ams_copilot");
        MENU_MAP.put("settings.jsp", "settings");
        MENU_MAP.put("db_status.jsp", "settings");
        MENU_MAP.put("backup_restore.jsp", "settings");
        MENU_MAP.put("database_backup_export.jsp", "settings");
        MENU_MAP.put("manage_roles.jsp", "settings");
        MENU_MAP.put("notification_settings.jsp", "settings");
        MENU_MAP.put("notifications.jsp", "settings");
        MENU_MAP.put("currency_settings.jsp", "settings");
        MENU_MAP.put("alert_center.jsp", "settings");
        MENU_MAP.put("overdue_actions.jsp", "settings");
        MENU_MAP.put("change_password.jsp", "settings");
        MENU_MAP.put("test_email.jsp", "settings");
        MENU_MAP.put("view_location.jsp", "settings");
        MENU_MAP.put("access_matrix.jsp", "settings");
        MENU_MAP.put("asset_health.jsp", "reports");
        MENU_MAP.put("dashboard_help.jsp", "dashboard");
        MENU_MAP.put("employee_profile.jsp", "employees");
        MENU_MAP.put("employee_assets.jsp", "assets");
        MENU_MAP.put("employee_requests.jsp", "asset_requests");
        MENU_MAP.put("new_employee_asset_request.jsp", "asset_requests");
        MENU_MAP.put("employee_returns.jsp", "returns");
        MENU_MAP.put("employee_maintenance_request.jsp", "employee_maintenance");
        MENU_MAP.put("maintenance_requests.jsp", "maintenance_requests");
        MENU_MAP.put("role_assignment.jsp", "role_assignment");
        MENU_MAP.put("user_profile_requests.jsp", "user_profile_requests");
    }
%>
<%
    String uri = request.getRequestURI();
    String pageName = uri.substring(uri.lastIndexOf("/") + 1).toLowerCase();
    String activeMenu = MENU_MAP.getOrDefault(pageName, "dashboard");
%>

        <nav class="menu">
            <% if ("EMPLOYEE".equals(sidebarUserRole)) { %>
                <a href="employee_dashboard.jsp" class="<%= activeMenu.equals("dashboard") ? "active" : "" %>"><i class="fa-solid fa-house"></i> My Dashboard</a>
                <a href="employee_profile.jsp" class="<%= activeMenu.equals("employees") ? "active" : "" %>"><i class="fa-solid fa-user"></i> My Profile</a>
                <a href="employee_assets.jsp" class="<%= activeMenu.equals("assets") ? "active" : "" %>"><i class="fa-solid fa-laptop"></i> My Assets</a>
                <a href="employee_requests.jsp" class="<%= activeMenu.equals("asset_requests") ? "active" : "" %>"><i class="fa-solid fa-file-contract"></i> My Asset Requests</a>
                <a href="employee_returns.jsp" class="<%= activeMenu.equals("returns") ? "active" : "" %>"><i class="fa-solid fa-rotate-left"></i> My Returns</a>
                <a href="employee_maintenance_request.jsp" class="<%= activeMenu.equals("employee_maintenance") ? "active" : "" %>"><i class="fa-solid fa-wrench"></i> My Maintenance Requests</a>
                <a href="my_physical_verification_duties.jsp" class="<%= activeMenu.equals("my_physical_verification") ? "active" : "" %>"><i class="fa-solid fa-shield-halved"></i> My Physical Verification Duties</a>
                <a href="change_password.jsp" class="<%= activeMenu.equals("settings") ? "active" : "" %>"><i class="fa-solid fa-key"></i> Change Password</a>
            <% } else { %>
                <a href="dashboard.jsp" class="<%= activeMenu.equals("dashboard") ? "active" : "" %>"><i class="fa-solid fa-house"></i> Dashboard</a>
                <a href="assets.jsp" class="<%= activeMenu.equals("assets") ? "active" : "" %>"><i class="fa-solid fa-cubes"></i> Assets</a>
                <a href="employees.jsp" class="<%= activeMenu.equals("employees") ? "active" : "" %>"><i class="fa-solid fa-users"></i> Employees</a>
                <% if (isFullAccess) { %>
                <a href="role_assignment.jsp" class="<%= activeMenu.equals("role_assignment") ? "active" : "" %>"><i class="fa-solid fa-user-shield"></i> Role & Duty Assignment</a>
                <% } %>
                <a href="departments.jsp" class="<%= activeMenu.equals("departments") ? "active" : "" %>" id="menu-departments"><i class="fa-solid fa-building"></i> Departments</a>
                <a href="categories.jsp" class="<%= activeMenu.equals("categories") ? "active" : "" %>"><i class="fa-solid fa-sitemap"></i> Categories</a>
                <a href="vendors.jsp" class="<%= activeMenu.equals("vendors") ? "active" : "" %>"><i class="fa-solid fa-truck-field"></i> Suppliers</a>
                <a href="category_vendor_mapping.jsp" class="<%= activeMenu.equals("category_vendor_mapping") ? "active" : "" %>"><i class="fa-solid fa-link"></i> Category Supplier Mapping</a>
                <%-- DEPARTMENT_HEAD's own review stage is a separate page/servlet
                     (dept_head_asset_requests.jsp / RoleAccessUtil's deptHeadOps),
                     not asset_requests.jsp (requestApprovalOps = SUPER_ADMIN/ADMIN/
                     ASSET_MANAGER only) - linking DEPARTMENT_HEAD to asset_requests.jsp
                     here was a latent bug: the link rendered but always 403'd them. --%>
                <% if ("DEPARTMENT_HEAD".equals(sidebarUserRole)) { %>
                <a href="dept_head_asset_requests.jsp" class="<%= activeMenu.equals("dept_head_asset_requests") ? "active" : "" %>"><i class="fa-solid fa-file-circle-plus"></i> Asset Requests (Dept Head Review)</a>
                <% } else { %>
                <a href="asset_requests.jsp" class="<%= activeMenu.equals("asset_requests") ? "active" : "" %>"><i class="fa-solid fa-file-circle-plus"></i> Asset Requests</a>
                <% } %>
                <a href="allocation.jsp" class="<%= activeMenu.equals("allocation") ? "active" : "" %>"><i class="fa-solid fa-arrows-rotate"></i> Allocation</a>
                <a href="returns.jsp" class="<%= activeMenu.equals("returns") ? "active" : "" %>"><i class="fa-solid fa-rotate-left"></i> Returns</a>
                <a href="maintenance.jsp" class="<%= activeMenu.equals("maintenance") ? "active" : "" %>"><i class="fa-solid fa-screwdriver-wrench"></i> Maintenance</a>
                <a href="physical_verification.jsp" class="<%= activeMenu.equals("physical_verification") ? "active" : "" %>"><i class="fa-solid fa-shield-halved"></i> Physical Verification</a>
                <%-- Self-service duty list/submit view for whichever employee a duty was
                     actually assigned to - relevant even to SUPER_ADMIN/ADMIN/ASSET_MANAGER
                     when they assign a duty to themselves, and to DEPARTMENT_HEAD/AUDITOR
                     who can view physical_verification.jsp but not submit through it. --%>
                <a href="my_physical_verification_duties.jsp" class="<%= activeMenu.equals("my_physical_verification") ? "active" : "" %>"><i class="fa-solid fa-clipboard-check"></i> My Physical Verification Duties</a>
                <%-- asset_disposals.jsp is reportExportOps (SUPER_ADMIN/ADMIN/
                     ASSET_MANAGER/AUDITOR) - excludes DEPARTMENT_HEAD, who is
                     otherwise shown every link in this branch. Guarded here
                     rather than repeating the dept_head_asset_requests.jsp
                     broken-link bug fixed earlier: a rendered link that
                     always 403s the role viewing it. --%>
                <% if (!"DEPARTMENT_HEAD".equals(sidebarUserRole)) { %>
                <a href="asset_disposals.jsp" class="<%= activeMenu.equals("asset_disposals") ? "active" : "" %>"><i class="fa-solid fa-recycle"></i> Asset Disposals</a>
                <% } %>
                <%-- asset_transfers.jsp is assetOps (SUPER_ADMIN/ADMIN/
                     ASSET_MANAGER only) - excludes both AUDITOR and
                     DEPARTMENT_HEAD, same reasoning as above. --%>
                <% if (!"DEPARTMENT_HEAD".equals(sidebarUserRole) && !"AUDITOR".equals(sidebarUserRole)) { %>
                <a href="asset_transfers.jsp" class="<%= activeMenu.equals("asset_transfers") ? "active" : "" %>"><i class="fa-solid fa-right-left"></i> Asset Transfers</a>
                <% } %>
                <a href="reports.jsp" class="<%= activeMenu.equals("reports") ? "active" : "" %>"><i class="fa-solid fa-chart-pie"></i> Reports & Analytics</a>
                <a href="audit_logs.jsp" class="<%= activeMenu.equals("audit_logs") ? "active" : "" %>"><i class="fa-solid fa-clipboard-check"></i> Audit</a>
                <a href="qr_control_center.jsp" class="<%= activeMenu.equals("qr_control_center") ? "active" : "" %>"><i class="fa-solid fa-border-all"></i> QR Control Center</a>
                <a href="ams_copilot.jsp" class="<%= activeMenu.equals("ams_copilot") ? "active" : "" %>"><i class="fa-solid fa-robot"></i> AI Copilot</a>
                <a href="settings.jsp" class="<%= activeMenu.equals("settings") ? "active" : "" %>"><i class="fa-solid fa-gear"></i> Settings</a>
            <% } %>
            <a href="logout.jsp" class="logout"><i class="fa-solid fa-right-from-bracket"></i> Logout</a>
        </nav>

        <div class="sidebar-wave"></div>
    </aside>
