<%@page contentType="text/html" pageEncoding="UTF-8"%>
<%@page import="com.mycompany.asset_management_system_ams.DBConnection"%>
<%@page import="java.sql.*"%>
<%@page import="java.util.*"%>

<%!
    public static class SearchItem {
        String moduleKey = "";
        String moduleTitle = "";
        String moduleIcon = "";
        String titleText = "";
        String detailText = "";
        String targetUrl = "";
        String dateText = "";
    }

    private String safeText(String value) {
        if (value == null || value.trim().isEmpty()) {
            return "N/A";
        }

        return value.trim()
                .replace("&", "&amp;")
                .replace("<", "&lt;")
                .replace(">", "&gt;")
                .replace("\"", "&quot;")
                .replace("'", "&#39;");
    }

    private String cleanLabel(String value) {
        if (value == null || value.trim().isEmpty()) {
            return "N/A";
        }

        String text = value.trim().replace("_", " ").toLowerCase(Locale.ENGLISH);
        String[] parts = text.split("\\s+");
        StringBuilder out = new StringBuilder();

        for (String part : parts) {
            if (part.length() > 0) {
                out.append(Character.toUpperCase(part.charAt(0))).append(part.substring(1)).append(" ");
            }
        }

        return out.toString().trim();
    }

    private String shortText(String value, int max) {
        if (value == null || value.trim().isEmpty()) {
            return "N/A";
        }

        String text = value.trim();
        return text.length() <= max ? text : text.substring(0, max) + "...";
    }

    private int countQuestionMarks(String sql) {
        int count = 0;
        boolean insideSingleQuote = false;
        boolean insideDoubleQuote = false;

        for (int i = 0; i < sql.length(); i++) {
            char ch = sql.charAt(i);

            if (ch == '\'' && !insideDoubleQuote) {
                if (insideSingleQuote && i + 1 < sql.length() && sql.charAt(i + 1) == '\'') {
                    i++;
                    continue;
                }

                insideSingleQuote = !insideSingleQuote;
                continue;
            }

            if (ch == '"' && !insideSingleQuote) {
                insideDoubleQuote = !insideDoubleQuote;
                continue;
            }

            if (ch == '?' && !insideSingleQuote && !insideDoubleQuote) {
                count++;
            }
        }

        return count;
    }

    private boolean tableExists(Connection con, String tableName) {
        String sql = "SELECT COUNT(*) FROM information_schema.tables "
                + "WHERE table_schema = DATABASE() AND table_name = ?";

        try (PreparedStatement ps = con.prepareStatement(sql)) {
            ps.setString(1, tableName);

            try (ResultSet rs = ps.executeQuery()) {
                if (rs.next()) {
                    return rs.getInt(1) > 0;
                }
            }

        } catch (Exception e) {
            e.printStackTrace();
        }

        return false;
    }

    private boolean columnExists(Connection con, String tableName, String columnName) {
        String sql = "SELECT COUNT(*) FROM information_schema.columns "
                + "WHERE table_schema = DATABASE() AND table_name = ? AND column_name = ?";

        try (PreparedStatement ps = con.prepareStatement(sql)) {
            ps.setString(1, tableName);
            ps.setString(2, columnName);

            try (ResultSet rs = ps.executeQuery()) {
                if (rs.next()) {
                    return rs.getInt(1) > 0;
                }
            }

        } catch (Exception e) {
            e.printStackTrace();
        }

        return false;
    }

    private String buildWhere(List<String> conditions) {
        if (conditions == null || conditions.isEmpty()) {
            return "1 = 0";
        }

        StringBuilder sb = new StringBuilder();

        for (int i = 0; i < conditions.size(); i++) {
            if (i > 0) {
                sb.append(" OR ");
            }

            sb.append(conditions.get(i));
        }

        return sb.toString();
    }

    private List<SearchItem> runSearch(Connection con, String sql, String keyword, List<String> debug) {
        List<SearchItem> items = new ArrayList<>();

        try (PreparedStatement ps = con.prepareStatement(sql)) {
            String value = "%" + keyword + "%";
            int count = countQuestionMarks(sql);

            for (int i = 1; i <= count; i++) {
                ps.setString(i, value);
            }

            try (ResultSet rs = ps.executeQuery()) {
                while (rs.next()) {
                    SearchItem item = new SearchItem();

                    item.moduleKey = rs.getString("module_key");
                    item.moduleTitle = rs.getString("module_title");
                    item.moduleIcon = rs.getString("module_icon");
                    item.titleText = rs.getString("title_text");
                    item.detailText = rs.getString("detail_text");
                    item.targetUrl = rs.getString("target_url");
                    item.dateText = rs.getString("date_text");

                    items.add(item);
                }
            }

        } catch (Exception e) {
            debug.add("Internal error parsing search query.");
            e.printStackTrace();
        }

        return items;
    }

    private void addAll(List<SearchItem> all, Connection con, String sql, String keyword, List<String> debug) {
        all.addAll(runSearch(con, sql, keyword, debug));
    }
%>

<%
    String username = (String) session.getAttribute("username");
    String role = (String) session.getAttribute("role");

    response.setHeader("Cache-Control", "no-cache, no-store, must-revalidate");
    response.setHeader("Pragma", "no-cache");
    response.setDateHeader("Expires", 0);

    if (username == null || role == null) {
        response.sendRedirect("login.jsp");
        return;
    }

    boolean isSuperAdmin = ("SUPER_ADMIN".equals(role) || "ADMIN".equals(role));
    boolean isAssetManager = "ASSET_MANAGER".equals(role);
    boolean isAuditor = "AUDITOR".equals(role);
    boolean isDepartmentHead = "DEPARTMENT_HEAD".equals(role);

    boolean canViewAdminData = isSuperAdmin || isAssetManager || isAuditor;
    boolean canViewAudit = isSuperAdmin || isAuditor;

    // Fault (Critical, fixed): the Assets and Employees result blocks below
    // used to run unconditionally for any authenticated role, including
    // EMPLOYEE - unlike the Disposal/Audit blocks further down, which were
    // already correctly gated by canViewAdminData/canViewAudit. That let any
    // employee browse the full asset register and the full employee
    // directory through this search box, even though the dedicated pages
    // those results link to (view_asset.jsp / view_employee.jsp) both
    // explicitly exclude EMPLOYEE via RoleAccessUtil - a search feature
    // built on top of those modules was silently more permissive than the
    // modules themselves. These flags mirror RoleAccessUtil's own role
    // lists for each target page exactly (assetViewOps / employeeViewOps /
    // verificationViewOps), so this page can never disclose more than
    // navigating to the linked page directly already would.
    boolean canViewAssets = isSuperAdmin || isAssetManager || isAuditor || isDepartmentHead;
    boolean canViewEmployees = isSuperAdmin || isDepartmentHead || isAuditor;
    boolean canViewVerification = isSuperAdmin || isAssetManager || isAuditor || isDepartmentHead;

    // Fault (High, fixed): audit/26-global-search.md Finding 1 confirmed the
    // Assets/Employees leak above, and explicitly flagged the remaining
    // categories as "more likely to lean toward unguarded... should be
    // confirmed" rather than assumed. They were: Categories, Vendors,
    // Allocation, Maintenance, and Requests all ran unconditionally here too,
    // same gap, same shape. Each flag below mirrors the effective
    // RoleAccessUtil entry for that category's own dedicated page exactly
    // (categories.jsp/vendors.jsp/allocation.jsp/maintenance.jsp/
    // asset_requests.jsp), so none of these blocks can disclose more than
    // navigating to the linked page directly already would. Returns is
    // deliberately left unguarded - returns.jsp's own RoleAccessUtil entry
    // (returnsPageOps) intentionally includes EMPLOYEE, matching the rest of
    // this codebase's design for employees returning their own assets.
    boolean canViewCategories = isSuperAdmin || isAssetManager || isAuditor;
    boolean canViewVendors = isSuperAdmin || isAssetManager;
    boolean canViewAllocation = isSuperAdmin || isAssetManager || isAuditor;
    boolean canViewMaintenance = isSuperAdmin || isAssetManager || isAuditor || isDepartmentHead;
    boolean canViewRequests = isSuperAdmin || isAssetManager;

    String q = request.getParameter("q");

    if (q == null) {
        q = "";
    }

    q = q.trim();

    String userInitial = username.substring(0, Math.min(2, username.length())).toUpperCase(Locale.ENGLISH);

    List<SearchItem> allResults = new ArrayList<>();
    List<String> debugMessages = new ArrayList<>();

    if (!q.isEmpty()) {
        try (Connection con = DBConnection.getConnection()) {

            boolean hasAssets = tableExists(con, "assets");
            boolean hasEmployees = tableExists(con, "employees");
            boolean hasDepartments = tableExists(con, "departments");
            boolean hasCategories = tableExists(con, "asset_categories");
            boolean hasVendors = tableExists(con, "vendors");
            boolean hasLocations = tableExists(con, "railway_locations");
            boolean hasDivisions = tableExists(con, "railway_divisions");
            boolean hasAllocation = tableExists(con, "asset_allocation");
            boolean hasReturns = tableExists(con, "asset_returns");
            boolean hasMaintenance = tableExists(con, "maintenance_logs");
            boolean hasRequests = tableExists(con, "asset_requests");
            boolean hasPhysicalVerification = tableExists(con, "physical_verification");
            boolean hasOldVerification = tableExists(con, "asset_physical_verification");
            boolean hasDisposal = tableExists(con, "asset_disposal");
            boolean hasAudit = tableExists(con, "audit_logs");

            if (canViewAssets && hasAssets) {
                boolean assetHasRailwayNo = columnExists(con, "assets", "railway_asset_no");
                boolean assetHasMakeBrand = columnExists(con, "assets", "make_brand");
                boolean assetHasItemSpec = columnExists(con, "assets", "item_specification");
                boolean assetHasSerial = columnExists(con, "assets", "serial_number");
                boolean assetHasModel = columnExists(con, "assets", "model_number");
                boolean assetHasLocationText = columnExists(con, "assets", "location");
                boolean assetHasStatus = columnExists(con, "assets", "asset_status");
                boolean assetHasCondition = columnExists(con, "assets", "condition_status");
                boolean assetHasService = columnExists(con, "assets", "service_status");
                boolean assetHasQr = columnExists(con, "assets", "qr_code");
                boolean assetHasToken = columnExists(con, "assets", "qr_public_token");
                boolean assetHasRemarks = columnExists(con, "assets", "remarks");
                boolean assetHasUpdatedAt = columnExists(con, "assets", "updated_at");
                boolean assetHasLocationId = columnExists(con, "assets", "location_id");
                boolean assetHasRailwayLocationId = columnExists(con, "assets", "railway_location_id");

                String locationJoin = "";
                String locationExpr = "''";

                if (hasLocations && assetHasLocationId) {
                    locationJoin = "LEFT JOIN railway_locations rl ON a.location_id = rl.location_id ";
                    locationExpr = assetHasLocationText ? "COALESCE(rl.location_name, a.location, '')" : "COALESCE(rl.location_name, '')";
                } else if (hasLocations && assetHasRailwayLocationId) {
                    locationJoin = "LEFT JOIN railway_locations rl ON a.railway_location_id = rl.location_id ";
                    locationExpr = assetHasLocationText ? "COALESCE(rl.location_name, a.location, '')" : "COALESCE(rl.location_name, '')";
                } else if (assetHasLocationText) {
                    locationExpr = "COALESCE(a.location, '')";
                }

                String categoryJoin = hasCategories ? "LEFT JOIN asset_categories ac ON a.category_id = ac.category_id " : "";
                String vendorJoin = hasVendors ? "LEFT JOIN vendors v ON a.vendor_id = v.vendor_id " : "";
                String departmentJoin = hasDepartments && columnExists(con, "assets", "department_id") ? "LEFT JOIN departments d ON a.department_id = d.department_id " : "";

                String categoryExpr = hasCategories ? "COALESCE(ac.category_name, 'Uncategorized')" : "'Uncategorized'";
                String vendorExpr = hasVendors ? "COALESCE(v.vendor_name, 'No Vendor')" : "'No Vendor'";
                String departmentExpr = departmentJoin.length() > 0 ? "COALESCE(d.department_name, 'Unassigned')" : "'Unassigned'";
                String statusExpr = assetHasStatus ? "COALESCE(a.asset_status, '')" : "''";
                String serviceExpr = assetHasService ? "COALESCE(a.service_status, '')" : "''";
                String dateExpr = assetHasUpdatedAt ? "DATE_FORMAT(a.updated_at, '%d %b %Y')" : "''";

                List<String> conditions = new ArrayList<>();
                conditions.add("a.asset_code LIKE ?");
                conditions.add("a.asset_name LIKE ?");

                if (assetHasRailwayNo) conditions.add("a.railway_asset_no LIKE ?");
                if (assetHasMakeBrand) conditions.add("a.make_brand LIKE ?");
                if (assetHasItemSpec) conditions.add("a.item_specification LIKE ?");
                if (assetHasSerial) conditions.add("a.serial_number LIKE ?");
                if (assetHasModel) conditions.add("a.model_number LIKE ?");
                if (assetHasLocationText) conditions.add("a.location LIKE ?");
                if (assetHasStatus) conditions.add("a.asset_status LIKE ?");
                if (assetHasCondition) conditions.add("a.condition_status LIKE ?");
                if (assetHasService) conditions.add("a.service_status LIKE ?");
                if (assetHasQr) conditions.add("a.qr_code LIKE ?");
                if (assetHasToken) conditions.add("a.qr_public_token LIKE ?");
                if (assetHasRemarks) conditions.add("a.remarks LIKE ?");
                if (hasCategories) conditions.add("ac.category_name LIKE ?");
                if (hasVendors) conditions.add("v.vendor_name LIKE ?");
                if (departmentJoin.length() > 0) conditions.add("d.department_name LIKE ?");

                if (locationJoin.length() > 0) {
                    conditions.add("rl.location_name LIKE ?");

                    if (columnExists(con, "railway_locations", "location_code")) {
                        conditions.add("rl.location_code LIKE ?");
                    }
                }

                String sql =
                        "SELECT "
                        + "'assets' AS module_key, "
                        + "'Assets' AS module_title, "
                        + "'fa-cube' AS module_icon, "
                        + "CONCAT(a.asset_code, ' · ', a.asset_name) AS title_text, "
                        + "CONCAT_WS(' · ', " + categoryExpr + ", " + vendorExpr + ", " + departmentExpr + ", " + locationExpr + ", " + statusExpr + ", " + serviceExpr + ") AS detail_text, "
                        + "CONCAT('view_asset.jsp?id=', a.asset_id) AS target_url, "
                        + dateExpr + " AS date_text "
                        + "FROM assets a "
                        + categoryJoin
                        + vendorJoin
                        + departmentJoin
                        + locationJoin
                        + "WHERE " + buildWhere(conditions) + " "
                        + "ORDER BY a.asset_id DESC "
                        + "LIMIT 30";

                addAll(allResults, con, sql, q, debugMessages);
            }

            if (canViewEmployees && hasEmployees) {
                boolean empHasFullName = columnExists(con, "employees", "full_name");
                
                boolean empHasEmployeeName = columnExists(con, "employees", "employee_name");
                boolean empHasStatus = columnExists(con, "employees", "status");
                boolean empHasEmployeeStatus = columnExists(con, "employees", "employee_status");
                boolean empHasDesignation = columnExists(con, "employees", "designation");
                boolean empHasEmail = columnExists(con, "employees", "email");
                boolean empHasPhone = columnExists(con, "employees", "phone");
                boolean empHasUpdatedAt = columnExists(con, "employees", "updated_at");

                String employeeNameExpr;

                if (empHasFullName) {
                    employeeNameExpr = "COALESCE(e.full_name, '')";
                } else if (empHasEmployeeName) {
                    employeeNameExpr = "COALESCE(e.employee_name, '')";
                } else if (empHasEmployeeName) {
                    employeeNameExpr = "COALESCE(e.employee_name, '')";
                } else {
                    employeeNameExpr = "COALESCE(e.employee_code, '')";
                }

                String employeeStatusExpr = empHasEmployeeStatus ? "COALESCE(e.employee_status, '')" : (empHasStatus ? "COALESCE(e.status, '')" : "''");
                String designationExpr = empHasDesignation ? "COALESCE(e.designation, '')" : "''";
                String departmentJoin = hasDepartments && columnExists(con, "employees", "department_id") ? "LEFT JOIN departments d ON e.department_id = d.department_id " : "";
                String departmentExpr = departmentJoin.length() > 0 ? "COALESCE(d.department_name, 'No Department')" : "'No Department'";
                String dateExpr = empHasUpdatedAt ? "DATE_FORMAT(e.updated_at, '%d %b %Y')" : "''";

                List<String> conditions = new ArrayList<>();
                conditions.add("e.employee_code LIKE ?");
                conditions.add(employeeNameExpr + " LIKE ?");

                if (empHasDesignation) conditions.add("e.designation LIKE ?");
                if (empHasEmail) conditions.add("e.email LIKE ?");
                if (empHasPhone) conditions.add("e.phone LIKE ?");
                if (empHasEmployeeStatus) conditions.add("e.employee_status LIKE ?");
                if (empHasStatus) conditions.add("e.status LIKE ?");
                if (departmentJoin.length() > 0) conditions.add("d.department_name LIKE ?");

                String sql =
                        "SELECT "
                        + "'employees' AS module_key, "
                        + "'Holders / Employees' AS module_title, "
                        + "'fa-id-card' AS module_icon, "
                        + "CONCAT(e.employee_code, ' · ', " + employeeNameExpr + ") AS title_text, "
                        + "CONCAT_WS(' · ', " + designationExpr + ", " + departmentExpr + ", " + employeeStatusExpr + ") AS detail_text, "
                        + "CONCAT('view_employee.jsp?id=', e.employee_id) AS target_url, "
                        + dateExpr + " AS date_text "
                        + "FROM employees e "
                        + departmentJoin
                        + "WHERE " + buildWhere(conditions) + " "
                        + "ORDER BY e.employee_id DESC "
                        + "LIMIT 30";

                addAll(allResults, con, sql, q, debugMessages);
            }

            if (canViewCategories && hasCategories) {
                boolean catHasStatus = columnExists(con, "asset_categories", "status");
                boolean catHasActive = columnExists(con, "asset_categories", "is_active");
                boolean catHasLife = columnExists(con, "asset_categories", "useful_life_years");
                boolean catHasDep = columnExists(con, "asset_categories", "default_depreciation_rate");
                boolean catHasUpdatedAt = columnExists(con, "asset_categories", "updated_at");

                String statusExpr = catHasStatus ? "COALESCE(status, '')" : (catHasActive ? "IF(is_active = 1, 'ACTIVE', 'INACTIVE')" : "''");
                String lifeExpr = catHasLife ? "CONCAT('Useful Life: ', useful_life_years, ' years')" : "''";
                String depExpr = catHasDep ? "CONCAT('Depreciation: ', default_depreciation_rate, '%')" : "''";
                String dateExpr = catHasUpdatedAt ? "DATE_FORMAT(updated_at, '%d %b %Y')" : "''";

                List<String> conditions = new ArrayList<>();
                conditions.add("category_name LIKE ?");

                if (columnExists(con, "asset_categories", "description")) conditions.add("description LIKE ?");
                if (catHasStatus) conditions.add("status LIKE ?");

                String sql =
                        "SELECT "
                        + "'categories' AS module_key, "
                        + "'Asset Categories' AS module_title, "
                        + "'fa-sitemap' AS module_icon, "
                        + "category_name AS title_text, "
                        + "CONCAT_WS(' · ', COALESCE(description, ''), " + lifeExpr + ", " + depExpr + ", " + statusExpr + ") AS detail_text, "
                        + "CONCAT('view_category.jsp?id=', category_id) AS target_url, "
                        + dateExpr + " AS date_text "
                        + "FROM asset_categories "
                        + "WHERE " + buildWhere(conditions) + " "
                        + "ORDER BY category_name ASC "
                        + "LIMIT 30";

                addAll(allResults, con, sql, q, debugMessages);
            }

            if (canViewVendors && hasVendors) {
                boolean vendorHasGst = columnExists(con, "vendors", "gst_number");
                boolean vendorHasStatus = columnExists(con, "vendors", "vendor_status");
                boolean vendorHasUpdatedAt = columnExists(con, "vendors", "updated_at");

                String gstExpr = vendorHasGst ? "COALESCE(gst_number, '')" : "''";
                String statusExpr = vendorHasStatus ? "COALESCE(vendor_status, '')" : "''";
                String dateExpr = vendorHasUpdatedAt ? "DATE_FORMAT(updated_at, '%d %b %Y')" : "''";

                List<String> conditions = new ArrayList<>();
                conditions.add("vendor_name LIKE ?");

                if (columnExists(con, "vendors", "contact_person")) conditions.add("contact_person LIKE ?");
                if (columnExists(con, "vendors", "email")) conditions.add("email LIKE ?");
                if (columnExists(con, "vendors", "phone")) conditions.add("phone LIKE ?");
                if (columnExists(con, "vendors", "address")) conditions.add("address LIKE ?");
                if (vendorHasGst) conditions.add("gst_number LIKE ?");
                if (vendorHasStatus) conditions.add("vendor_status LIKE ?");

                String sql =
                        "SELECT "
                        + "'vendors' AS module_key, "
                        + "'Vendors' AS module_title, "
                        + "'fa-truck-field' AS module_icon, "
                        + "vendor_name AS title_text, "
                        + "CONCAT_WS(' · ', COALESCE(contact_person, ''), COALESCE(phone, ''), COALESCE(email, ''), " + gstExpr + ", " + statusExpr + ") AS detail_text, "
                        + "CONCAT('view_vendor.jsp?id=', vendor_id) AS target_url, "
                        + dateExpr + " AS date_text "
                        + "FROM vendors "
                        + "WHERE " + buildWhere(conditions) + " "
                        + "ORDER BY vendor_name ASC "
                        + "LIMIT 30";

                addAll(allResults, con, sql, q, debugMessages);
            }

            if (hasLocations) {
                boolean locHasUpdatedAt = columnExists(con, "railway_locations", "updated_at");
                String departmentJoin = hasDepartments && columnExists(con, "railway_locations", "department_id") ? "LEFT JOIN departments d ON rl.department_id = d.department_id " : "";
                String divisionJoin = hasDivisions && columnExists(con, "railway_locations", "division_id") ? "LEFT JOIN railway_divisions rd ON rl.division_id = rd.division_id " : "";
                String departmentExpr = departmentJoin.length() > 0 ? "COALESCE(d.department_name, 'No Department')" : "'No Department'";
                String divisionExpr = divisionJoin.length() > 0 ? "COALESCE(rd.division_name, '')" : "''";
                String dateExpr = locHasUpdatedAt ? "DATE_FORMAT(rl.updated_at, '%d %b %Y')" : "''";

                List<String> conditions = new ArrayList<>();

                if (columnExists(con, "railway_locations", "location_code")) conditions.add("rl.location_code LIKE ?");

                conditions.add("rl.location_name LIKE ?");

                if (columnExists(con, "railway_locations", "location_type")) conditions.add("rl.location_type LIKE ?");
                if (columnExists(con, "railway_locations", "building_block")) conditions.add("rl.building_block LIKE ?");
                if (columnExists(con, "railway_locations", "floor_level")) conditions.add("rl.floor_level LIKE ?");
                if (columnExists(con, "railway_locations", "room_no")) conditions.add("rl.room_no LIKE ?");
                if (columnExists(con, "railway_locations", "status")) conditions.add("rl.status LIKE ?");
                if (departmentJoin.length() > 0) conditions.add("d.department_name LIKE ?");
                if (divisionJoin.length() > 0) conditions.add("rd.division_name LIKE ?");

                String sql =
                        "SELECT "
                        + "'locations' AS module_key, "
                        + "'Sections / Locations' AS module_title, "
                        + "'fa-location-dot' AS module_icon, "
                        + "CONCAT(COALESCE(rl.location_code, ''), ' · ', rl.location_name) AS title_text, "
                        + "CONCAT_WS(' · ', COALESCE(rl.location_type, ''), COALESCE(rl.building_block, ''), COALESCE(rl.floor_level, ''), COALESCE(rl.room_no, ''), " + departmentExpr + ", " + divisionExpr + ") AS detail_text, "
                        + "CONCAT('view_location.jsp?id=', rl.location_id) AS target_url, "
                        + dateExpr + " AS date_text "
                        + "FROM railway_locations rl "
                        + departmentJoin
                        + divisionJoin
                        + "WHERE " + buildWhere(conditions) + " "
                        + "ORDER BY rl.location_name ASC "
                        + "LIMIT 30";

                addAll(allResults, con, sql, q, debugMessages);
            }

            if (canViewAllocation && hasAllocation && hasAssets && hasEmployees) {
                boolean allocHasIssueCondition = columnExists(con, "asset_allocation", "issue_condition");
                boolean allocHasUpdatedAt = columnExists(con, "asset_allocation", "updated_at");

                boolean empHasFullName = columnExists(con, "employees", "full_name");
                
                boolean empHasEmployeeName = columnExists(con, "employees", "employee_name");

                String employeeNameExpr = empHasFullName ? "COALESCE(e.full_name, '')"
                        : ((empHasEmployeeName) ? "COALESCE(e.employee_name, '')" : "COALESCE(e.employee_code, '')");

                String issueExpr = allocHasIssueCondition ? "COALESCE(aa.issue_condition, '')" : "''";
                String dateExpr = allocHasUpdatedAt ? "DATE_FORMAT(aa.updated_at, '%d %b %Y')" : "DATE_FORMAT(aa.allocation_date, '%d %b %Y')";

                List<String> conditions = new ArrayList<>();
                conditions.add("a.asset_code LIKE ?");
                conditions.add("a.asset_name LIKE ?");
                conditions.add("e.employee_code LIKE ?");
                conditions.add(employeeNameExpr + " LIKE ?");
                conditions.add("aa.allocation_status LIKE ?");

                if (allocHasIssueCondition) conditions.add("aa.issue_condition LIKE ?");
                if (columnExists(con, "asset_allocation", "remarks")) conditions.add("aa.remarks LIKE ?");

                String sql =
                        "SELECT "
                        + "'allocation' AS module_key, "
                        + "'Allocation' AS module_title, "
                        + "'fa-arrow-right-arrow-left' AS module_icon, "
                        + "CONCAT(a.asset_code, ' · ', a.asset_name) AS title_text, "
                        + "CONCAT_WS(' · ', CONCAT('Holder: ', " + employeeNameExpr + "), COALESCE(e.employee_code, ''), COALESCE(aa.allocation_status, ''), " + issueExpr + ", DATE_FORMAT(aa.allocation_date, '%d %b %Y')) AS detail_text, "
                        + "CONCAT('view_allocation.jsp?id=', aa.allocation_id) AS target_url, "
                        + dateExpr + " AS date_text "
                        + "FROM asset_allocation aa "
                        + "LEFT JOIN assets a ON aa.asset_id = a.asset_id "
                        + "LEFT JOIN employees e ON aa.employee_id = e.employee_id "
                        + "WHERE " + buildWhere(conditions) + " "
                        + "ORDER BY aa.allocation_id DESC "
                        + "LIMIT 30";

                addAll(allResults, con, sql, q, debugMessages);
            }

            if (hasReturns && hasAssets && hasEmployees && hasAllocation) {
                boolean retHasAssetId = columnExists(con, "asset_returns", "asset_id");
                boolean retHasEmployeeId = columnExists(con, "asset_returns", "employee_id");
                boolean retHasAction = columnExists(con, "asset_returns", "action_after_return");
                boolean retHasUpdatedAt = columnExists(con, "asset_returns", "updated_at");

                boolean empHasFullName = columnExists(con, "employees", "full_name");
                
                boolean empHasEmployeeName = columnExists(con, "employees", "employee_name");

                String assetJoin = retHasAssetId ? "LEFT JOIN assets a ON ar.asset_id = a.asset_id " : "LEFT JOIN assets a ON aa.asset_id = a.asset_id ";
                String employeeJoin = retHasEmployeeId ? "LEFT JOIN employees e ON ar.employee_id = e.employee_id " : "LEFT JOIN employees e ON aa.employee_id = e.employee_id ";

                String employeeNameExpr = empHasFullName ? "COALESCE(e.full_name, '')"
                        : ((empHasEmployeeName) ? "COALESCE(e.employee_name, '')" : "COALESCE(e.employee_code, '')");

                String actionExpr = retHasAction ? "COALESCE(ar.action_after_return, '')" : "''";
                String dateExpr = retHasUpdatedAt ? "DATE_FORMAT(ar.updated_at, '%d %b %Y')" : "DATE_FORMAT(ar.return_date, '%d %b %Y')";

                List<String> conditions = new ArrayList<>();
                conditions.add("a.asset_code LIKE ?");
                conditions.add("a.asset_name LIKE ?");
                conditions.add("e.employee_code LIKE ?");
                conditions.add(employeeNameExpr + " LIKE ?");
                conditions.add("ar.return_condition LIKE ?");

                if (retHasAction) conditions.add("ar.action_after_return LIKE ?");
                if (columnExists(con, "asset_returns", "remarks")) conditions.add("ar.remarks LIKE ?");

                String sql =
                        "SELECT "
                        + "'returns' AS module_key, "
                        + "'Returns' AS module_title, "
                        + "'fa-rotate-left' AS module_icon, "
                        + "CONCAT(a.asset_code, ' · ', a.asset_name) AS title_text, "
                        + "CONCAT_WS(' · ', CONCAT('Holder: ', " + employeeNameExpr + "), COALESCE(ar.return_condition, ''), " + actionExpr + ", DATE_FORMAT(ar.return_date, '%d %b %Y')) AS detail_text, "
                        + "CONCAT('view_return.jsp?id=', ar.return_id) AS target_url, "
                        + dateExpr + " AS date_text "
                        + "FROM asset_returns ar "
                        + "LEFT JOIN asset_allocation aa ON ar.allocation_id = aa.allocation_id "
                        + assetJoin
                        + employeeJoin
                        + "WHERE " + buildWhere(conditions) + " "
                        + "ORDER BY ar.return_id DESC "
                        + "LIMIT 30";

                addAll(allResults, con, sql, q, debugMessages);
            }

            if (canViewMaintenance && hasMaintenance && hasAssets) {
                boolean maintHasIssue = columnExists(con, "maintenance_logs", "issue_reported");
                boolean maintHasWork = columnExists(con, "maintenance_logs", "work_done");
                boolean maintHasStatus = columnExists(con, "maintenance_logs", "maintenance_status");
                boolean maintHasDesc = columnExists(con, "maintenance_logs", "description");
                boolean maintHasPerformedBy = columnExists(con, "maintenance_logs", "performed_by");
                boolean maintHasUpdatedAt = columnExists(con, "maintenance_logs", "updated_at");
                boolean maintHasVendorId = columnExists(con, "maintenance_logs", "vendor_id");

                String vendorJoin = hasVendors && maintHasVendorId ? "LEFT JOIN vendors v ON ml.vendor_id = v.vendor_id " : "";
                String vendorExpr = vendorJoin.length() > 0 ? "COALESCE(v.vendor_name, 'No Vendor')" : "'No Vendor'";
                String statusExpr = maintHasStatus ? "COALESCE(ml.maintenance_status, '')" : "''";
                String issueExpr = maintHasIssue ? "COALESCE(ml.issue_reported, '')" : (maintHasDesc ? "COALESCE(ml.description, '')" : "''");
                String dateExpr = maintHasUpdatedAt ? "DATE_FORMAT(ml.updated_at, '%d %b %Y')" : "DATE_FORMAT(ml.maintenance_date, '%d %b %Y')";

                List<String> conditions = new ArrayList<>();
                conditions.add("a.asset_code LIKE ?");
                conditions.add("a.asset_name LIKE ?");
                conditions.add("ml.maintenance_type LIKE ?");

                if (maintHasIssue) conditions.add("ml.issue_reported LIKE ?");
                if (maintHasWork) conditions.add("ml.work_done LIKE ?");
                if (maintHasStatus) conditions.add("ml.maintenance_status LIKE ?");
                if (maintHasDesc) conditions.add("ml.description LIKE ?");
                if (maintHasPerformedBy) conditions.add("ml.performed_by LIKE ?");
                if (columnExists(con, "maintenance_logs", "remarks")) conditions.add("ml.remarks LIKE ?");
                if (vendorJoin.length() > 0) conditions.add("v.vendor_name LIKE ?");

                String sql =
                        "SELECT "
                        + "'maintenance' AS module_key, "
                        + "'Maintenance' AS module_title, "
                        + "'fa-screwdriver-wrench' AS module_icon, "
                        + "CONCAT(a.asset_code, ' · ', a.asset_name) AS title_text, "
                        + "CONCAT_WS(' · ', COALESCE(ml.maintenance_type, ''), " + statusExpr + ", CONCAT('₹', COALESCE(ml.cost, 0)), " + vendorExpr + ", " + issueExpr + ") AS detail_text, "
                        + "CONCAT('view_maintenance.jsp?id=', ml.maintenance_id) AS target_url, "
                        + dateExpr + " AS date_text "
                        + "FROM maintenance_logs ml "
                        + "LEFT JOIN assets a ON ml.asset_id = a.asset_id "
                        + vendorJoin
                        + "WHERE " + buildWhere(conditions) + " "
                        + "ORDER BY ml.maintenance_id DESC "
                        + "LIMIT 30";

                addAll(allResults, con, sql, q, debugMessages);
            }

            if (canViewRequests && hasRequests && hasEmployees && hasCategories) {
                boolean reqHasType = columnExists(con, "asset_requests", "request_type");
                boolean reqHasPriority = columnExists(con, "asset_requests", "priority");
                boolean reqHasReason = columnExists(con, "asset_requests", "request_reason");
                boolean reqHasUpdatedAt = columnExists(con, "asset_requests", "updated_at");

                boolean empHasFullName = columnExists(con, "employees", "full_name");
                
                boolean empHasEmployeeName = columnExists(con, "employees", "employee_name");

                String employeeNameExpr = empHasFullName ? "COALESCE(e.full_name, '')"
                        : ((empHasEmployeeName) ? "COALESCE(e.employee_name, '')" : "COALESCE(e.employee_code, '')");

                String typeExpr = reqHasType ? "COALESCE(ar.request_type, '')" : "''";
                String priorityExpr = reqHasPriority ? "COALESCE(ar.priority, '')" : "''";
                String reasonExpr = reqHasReason ? "COALESCE(ar.request_reason, '')" : "COALESCE(ar.remarks, '')";
                String dateExpr = reqHasUpdatedAt ? "DATE_FORMAT(ar.updated_at, '%d %b %Y')" : "DATE_FORMAT(ar.request_date, '%d %b %Y')";

                List<String> conditions = new ArrayList<>();
                conditions.add("e.employee_code LIKE ?");
                conditions.add(employeeNameExpr + " LIKE ?");
                conditions.add("ac.category_name LIKE ?");
                conditions.add("ar.request_status LIKE ?");

                if (reqHasType) conditions.add("ar.request_type LIKE ?");
                if (reqHasPriority) conditions.add("ar.priority LIKE ?");
                if (reqHasReason) conditions.add("ar.request_reason LIKE ?");
                if (columnExists(con, "asset_requests", "remarks")) conditions.add("ar.remarks LIKE ?");

                String sql =
                        "SELECT "
                        + "'requests' AS module_key, "
                        + "'Planning & Requests' AS module_title, "
                        + "'fa-square-plus' AS module_icon, "
                        + "CONCAT('Request #', ar.request_id, ' · ', " + employeeNameExpr + ") AS title_text, "
                        + "CONCAT_WS(' · ', COALESCE(ac.category_name, 'No Category'), " + typeExpr + ", COALESCE(ar.request_status, ''), " + priorityExpr + ", " + reasonExpr + ") AS detail_text, "
                        + "CONCAT('view_request.jsp?id=', ar.request_id) AS target_url, "
                        + dateExpr + " AS date_text "
                        + "FROM asset_requests ar "
                        + "LEFT JOIN employees e ON ar.employee_id = e.employee_id "
                        + "LEFT JOIN asset_categories ac ON ar.category_id = ac.category_id "
                        + "WHERE " + buildWhere(conditions) + " "
                        + "ORDER BY ar.request_id DESC "
                        + "LIMIT 30";

                addAll(allResults, con, sql, q, debugMessages);
            }

            if (canViewVerification && hasPhysicalVerification && hasAssets) {
                List<String> conditions = new ArrayList<>();
                conditions.add("a.asset_code LIKE ?");
                conditions.add("a.asset_name LIKE ?");
                conditions.add("pv.verification_status LIKE ?");
                conditions.add("pv.asset_found LIKE ?");
                conditions.add("pv.physical_condition LIKE ?");

                if (columnExists(con, "physical_verification", "remarks")) {
                    conditions.add("pv.remarks LIKE ?");
                }

                String sql =
                        "SELECT "
                        + "'verification' AS module_key, "
                        + "'Physical Verification' AS module_title, "
                        + "'fa-shield-halved' AS module_icon, "
                        + "CONCAT(a.asset_code, ' · ', a.asset_name) AS title_text, "
                        + "CONCAT_WS(' · ', COALESCE(pv.verification_status, ''), CONCAT('Found: ', COALESCE(pv.asset_found, '')), COALESCE(pv.physical_condition, ''), DATE_FORMAT(pv.verification_date, '%d %b %Y')) AS detail_text, "
                        + "CONCAT('view_verification.jsp?id=', pv.verification_id) AS target_url, "
                        + "DATE_FORMAT(pv.updated_at, '%d %b %Y') AS date_text "
                        + "FROM physical_verification pv "
                        + "LEFT JOIN assets a ON pv.asset_id = a.asset_id "
                        + "WHERE " + buildWhere(conditions) + " "
                        + "ORDER BY pv.verification_id DESC "
                        + "LIMIT 30";

                addAll(allResults, con, sql, q, debugMessages);

            } else if (canViewVerification && hasOldVerification && hasAssets) {
                List<String> conditions = new ArrayList<>();
                conditions.add("a.asset_code LIKE ?");
                conditions.add("a.asset_name LIKE ?");
                conditions.add("pv.verified_status LIKE ?");
                conditions.add("pv.review_status LIKE ?");

                if (columnExists(con, "asset_physical_verification", "remarks")) {
                    conditions.add("pv.remarks LIKE ?");
                }

                String sql =
                        "SELECT "
                        + "'verification' AS module_key, "
                        + "'Physical Verification' AS module_title, "
                        + "'fa-shield-halved' AS module_icon, "
                        + "CONCAT(a.asset_code, ' · ', a.asset_name) AS title_text, "
                        + "CONCAT_WS(' · ', COALESCE(pv.verified_status, ''), COALESCE(pv.review_status, ''), DATE_FORMAT(pv.verified_on, '%d %b %Y')) AS detail_text, "
                        + "CONCAT('view_asset.jsp?id=', pv.asset_id) AS target_url, "
                        + "DATE_FORMAT(pv.verified_on, '%d %b %Y') AS date_text "
                        + "FROM asset_physical_verification pv "
                        + "LEFT JOIN assets a ON pv.asset_id = a.asset_id "
                        + "WHERE " + buildWhere(conditions) + " "
                        + "ORDER BY pv.verification_id DESC "
                        + "LIMIT 30";

                addAll(allResults, con, sql, q, debugMessages);
            }

            if (canViewAdminData && hasDisposal && hasAssets) {
                boolean dispHasStatus = columnExists(con, "asset_disposal", "disposal_status");
                boolean dispHasRemarks = columnExists(con, "asset_disposal", "remarks");
                boolean dispHasUpdatedAt = columnExists(con, "asset_disposal", "updated_at");

                String statusExpr = dispHasStatus ? "COALESCE(ad.disposal_status, '')" : "''";
                String dateExpr = dispHasUpdatedAt ? "DATE_FORMAT(ad.updated_at, '%d %b %Y')" : "DATE_FORMAT(ad.disposal_date, '%d %b %Y')";

                List<String> conditions = new ArrayList<>();
                conditions.add("a.asset_code LIKE ?");
                conditions.add("a.asset_name LIKE ?");
                conditions.add("ad.disposal_reason LIKE ?");

                if (dispHasStatus) conditions.add("ad.disposal_status LIKE ?");
                if (dispHasRemarks) conditions.add("ad.remarks LIKE ?");

                String sql =
                        "SELECT "
                        + "'disposal' AS module_key, "
                        + "'Disposal / Retired Assets' AS module_title, "
                        + "'fa-recycle' AS module_icon, "
                        + "CONCAT(a.asset_code, ' · ', a.asset_name) AS title_text, "
                        + "CONCAT_WS(' · ', COALESCE(ad.disposal_reason, ''), " + statusExpr + ", CONCAT('₹', COALESCE(ad.disposal_value, 0)), DATE_FORMAT(ad.disposal_date, '%d %b %Y')) AS detail_text, "
                        + "CONCAT('view_disposal.jsp?id=', ad.disposal_id) AS target_url, "
                        + dateExpr + " AS date_text "
                        + "FROM asset_disposal ad "
                        + "LEFT JOIN assets a ON ad.asset_id = a.asset_id "
                        + "WHERE " + buildWhere(conditions) + " "
                        + "ORDER BY ad.disposal_id DESC "
                        + "LIMIT 30";

                addAll(allResults, con, sql, q, debugMessages);
            }

            if (canViewAudit && hasAudit) {
                boolean auditNew = columnExists(con, "audit_logs", "module_name");
                boolean auditOld = columnExists(con, "audit_logs", "table_name");

                if (auditNew) {
                    List<String> conditions = new ArrayList<>();
                    conditions.add("username LIKE ?");
                    conditions.add("user_role LIKE ?");
                    conditions.add("module_name LIKE ?");
                    conditions.add("action_type LIKE ?");
                    conditions.add("CAST(record_id AS CHAR) LIKE ?");
                    conditions.add("action_details LIKE ?");
                    conditions.add("ip_address LIKE ?");

                    String sql =
                            "SELECT "
                            + "'audit' AS module_key, "
                            + "'Audit Trail' AS module_title, "
                            + "'fa-clipboard-check' AS module_icon, "
                            + "CONCAT(COALESCE(module_name, 'Module'), ' · ', COALESCE(action_type, 'Action')) AS title_text, "
                            + "CONCAT_WS(' · ', COALESCE(username, 'System'), COALESCE(user_role, ''), CONCAT('Record: ', COALESCE(record_id, 'N/A')), COALESCE(action_details, '')) AS detail_text, "
                            + "CONCAT('view_audit_log.jsp?id=', audit_id) AS target_url, "
                            + "DATE_FORMAT(created_at, '%d %b %Y') AS date_text "
                            + "FROM audit_logs "
                            + "WHERE " + buildWhere(conditions) + " "
                            + "ORDER BY audit_id DESC "
                            + "LIMIT 30";

                    addAll(allResults, con, sql, q, debugMessages);

                } else if (auditOld) {
                    List<String> conditions = new ArrayList<>();
                    conditions.add("action LIKE ?");
                    conditions.add("table_name LIKE ?");
                    conditions.add("CAST(record_id AS CHAR) LIKE ?");
                    conditions.add("remarks LIKE ?");

                    String sql =
                            "SELECT "
                            + "'audit' AS module_key, "
                            + "'Audit Trail' AS module_title, "
                            + "'fa-clipboard-check' AS module_icon, "
                            + "CONCAT(COALESCE(table_name, 'Table'), ' · ', COALESCE(action, 'Action')) AS title_text, "
                            + "CONCAT_WS(' · ', CONCAT('Record: ', COALESCE(record_id, 'N/A')), COALESCE(remarks, '')) AS detail_text, "
                            + "'audit_logs.jsp' AS target_url, "
                            + "DATE_FORMAT(action_time, '%d %b %Y') AS date_text "
                            + "FROM audit_logs "
                            + "WHERE " + buildWhere(conditions) + " "
                            + "ORDER BY audit_id DESC "
                            + "LIMIT 30";

                    addAll(allResults, con, sql, q, debugMessages);
                }
            }

        } catch (Exception e) {
            debugMessages.add("Error executing search.");
            e.printStackTrace();
        }
    }

    LinkedHashMap<String, List<SearchItem>> groupedResults = new LinkedHashMap<>();

    for (SearchItem item : allResults) {
        if (!groupedResults.containsKey(item.moduleKey)) {
            groupedResults.put(item.moduleKey, new ArrayList<SearchItem>());
        }

        groupedResults.get(item.moduleKey).add(item);
    }

    int totalResults = allResults.size();
%>

<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>Global Search - IR-AMS</title>

    <link rel="stylesheet"
          href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.0/css/all.min.css">

    <link rel="stylesheet" href="css/ir-glass.css?v=28000">
    <link rel="stylesheet" href="css/ams-pro.css?v=28000">
    <link rel="stylesheet" href="css/ir-ams-railway-ui.css?v=global-search-compatible-final-2">

    <link rel="stylesheet" href="css/global_search.css?v=28001">
</head>

<body class="railway-ui">
<div class="app ams-shell">

    <jsp:include page="sidebar.jsp" />

    <main class="main railway-main">
        <jsp:include page="topbar.jsp" />

        <div class="main-scroll-content global-search-board">

            <section class="global-search-hero">
                <div>
                    <h1>Global Search</h1>

                    <% if (q.isEmpty()) { %>
                        <p>Search across assets, holders, departments, categories, vendors, locations, allocation, returns, maintenance, requests, verification, disposal, and audit trail.</p>
                    <% } else { %>
                        <p>Showing matching records for: <strong>"<%= safeText(q) %>"</strong></p>
                    <% } %>
                </div>

                <div class="search-summary">
                    <strong><%= totalResults %></strong>
                    <span>Total Results</span>
                </div>
            </section>

            <% if (!q.isEmpty()) { %>
                <div class="search-filter-line">
                    <% for (Map.Entry<String, List<SearchItem>> entry : groupedResults.entrySet()) {
                        List<SearchItem> group = entry.getValue();

                        if (!group.isEmpty()) {
                            SearchItem first = group.get(0);
                    %>
                        <span class="search-filter-pill">
                            <i class="fa-solid <%= safeText(first.moduleIcon) %>"></i>
                            <%= safeText(first.moduleTitle) %>
                            <%= group.size() %>
                        </span>
                    <%  }
                    } %>
                </div>
            <% } %>

            <% if (!debugMessages.isEmpty() && isSuperAdmin) { %>
                <div class="debug-box">
                    <strong>Search Debug:</strong><br>
                    <% for (String msg : debugMessages) { %>
                        • <%= safeText(msg) %><br>
                    <% } %>
                </div>
            <% } %>

            <% if (q.isEmpty()) { %>

                <div class="search-empty">
                    <i class="fa-solid fa-magnifying-glass"></i>
                    <strong>Search Asset Management System</strong>
                    <span>Type laptop, printer, dell, employee name, asset code, department, vendor, or location.</span>
                </div>

            <% } else if (totalResults == 0) { %>

                <div class="search-empty">
                    <i class="fa-regular fa-folder-open"></i>
                    <strong>No matching result found</strong>
                    <span>If laptop/printer/dell still shows zero, your database has no seed data imported. Check assets and vendors table data.</span>
                </div>

            <% } else { %>

                <div class="search-page-grid">

                    <% for (Map.Entry<String, List<SearchItem>> entry : groupedResults.entrySet()) {
                        List<SearchItem> group = entry.getValue();

                        if (group == null || group.isEmpty()) {
                            continue;
                        }

                        SearchItem first = group.get(0);
                    %>

                        <div class="search-module-card">
                            <div class="search-module-header">
                                <h2 class="search-module-title">
                                    <i class="fa-solid <%= safeText(first.moduleIcon) %>"></i>
                                    <%= safeText(first.moduleTitle) %>
                                </h2>
                                <span class="search-count-badge"><%= group.size() %></span>
                            </div>

                            <div class="result-list">
                                <% for (SearchItem item : group) { %>
                                    <a class="result-row" href="<%= safeText(item.targetUrl) %>">
                                        <div class="result-icon">
                                            <i class="fa-solid <%= safeText(item.moduleIcon) %>"></i>
                                        </div>

                                        <div class="result-main">
                                            <strong><%= safeText(item.titleText) %></strong>
                                            <span><%= safeText(shortText(item.detailText, 135)) %></span>
                                        </div>

                                        <div class="result-action">
                                            <%= safeText(item.dateText) %>
                                            <i class="fa-solid fa-arrow-right"></i>
                                        </div>
                                    </a>
                                <% } %>
                            </div>
                        </div>

                    <% } %>

                </div>

            <% } %>

        </div>
    </main>
</div>

<script src="js/user-dropdown.js?v=5"></script>
<script src="js/sidebar-role.js?v=7000"></script>
<script src="js/topbar-search.js?v=global-search-ready-1"></script>
<script src="js/dashboard-actions.js?v=1"></script>
</body>
</html>