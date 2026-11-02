<%@page contentType="text/html" pageEncoding="UTF-8"%>
<%@page import="com.mycompany.asset_management_system_ams.DashboardDAO"%>
<%@page import="com.mycompany.asset_management_system_ams.RecentActivity"%>
<%@page import="com.mycompany.asset_management_system_ams.RecentActivityDAO"%>
<%@page import="com.mycompany.asset_management_system_ams.DBConnection"%>
<%@page import="com.mycompany.asset_management_system_ams.SettingsDAO"%>
<%@page import="com.mycompany.asset_management_system_ams.NotificationHelper"%>
<%@page import="java.sql.*"%>
<%@page import="java.util.*"%>
<%@page import="java.text.NumberFormat"%>

<%
    request.setCharacterEncoding("UTF-8");
    response.setCharacterEncoding("UTF-8");
    response.setContentType("text/html; charset=UTF-8");
%>


<%!
    private static final java.util.logging.Logger DASHBOARD_LOGGER =
            java.util.logging.Logger.getLogger("com.mycompany.asset_management_system_ams.dashboard.jsp");

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

    private String normalizeRole(String value) {
        if (value == null || value.trim().isEmpty()) {
            return "";
        }

        return value.trim().toUpperCase(Locale.ENGLISH).replace(" ", "_");
    }

    private String safeInitial(String value) {
        if (value == null || value.trim().isEmpty()) {
            return "U";
        }

        String text = value.trim();
        return text.substring(0, Math.min(2, text.length())).toUpperCase(Locale.ENGLISH);
    }

    private String shortText(String value, int max) {
        if (value == null || value.trim().isEmpty()) {
            return "N/A";
        }

        String text = value.trim();
        return text.length() <= max ? text : text.substring(0, max) + "...";
    }

    private String roleHref(boolean allowed, String url) {
        return allowed ? url : "dashboard.jsp?access=denied";
    }

    private String roleTitle(boolean allowed, String allowedTitle) {
        return allowed ? allowedTitle : "Access restricted for your role";
    }

    private String assetDetailsHref(String assetId, String fallback) {
        if (assetId != null && assetId.matches("\\d+")) {
            return "view_asset.jsp?id=" + assetId;
        }

        return fallback;
    }

    private String indianNumber(long value) {
        try {
            NumberFormat nf = NumberFormat.getNumberInstance(new Locale("en", "IN"));
            nf.setMaximumFractionDigits(0);
            return nf.format(value);
        } catch (Exception e) {
            return String.valueOf(value);
        }
    }

    private String decimalOne(double value) {
        return String.format(Locale.ENGLISH, "%.1f", value);
    }

    private double percent(long part, long total) {
        if (total <= 0) {
            return 0.0;
        }
        return (part * 100.0) / total;
    }

    private int sqlInt(String sql) {
        return sqlInt(sql, null);
    }

    private int sqlInt(String sql, List<Integer> params) {
        int value = 0;

        try (Connection con = DBConnection.getConnection()) {
            if (con == null) {
                DASHBOARD_LOGGER.warning("Dashboard integer query skipped because the database connection is unavailable.");
                return 0;
            }

            try (PreparedStatement ps = con.prepareStatement(sql)) {
                if (params != null) {
                    int paramIndex = 1;
                    for (Integer param : params) {
                        ps.setInt(paramIndex++, param);
                    }
                }
                try (ResultSet rs = ps.executeQuery()) {
                    if (rs.next()) {
                        value = rs.getInt(1);
                    }
                }
            }

        } catch (Exception e) {
            DASHBOARD_LOGGER.log(java.util.logging.Level.WARNING, "Unable to load dashboard integer metric.", e);
        }

        return value;
    }

    // Schema-shape cache for tableExists()/columnExists() below. Every single
    // dashboard page load ran up to 8 information_schema queries (4 tables x
    // 4 columns) just to find out whether optional QR/location columns and
    // tables exist - structure that cannot change while the app is running
    // (a schema migration requires a restart to take effect anywhere else in
    // this codebase too). A JSP page's declared fields belong to one servlet
    // instance shared across all requests/threads by the container, so a
    // simple static map here is a safe, request-scoped-free cache - it's
    // populated once per table/column per app run instead of once per page
    // view. Failures (DB unreachable) are deliberately NOT cached, so a
    // transient outage doesn't get permanently remembered as "doesn't exist."
    private static final java.util.concurrent.ConcurrentHashMap<String, Boolean> SCHEMA_EXISTS_CACHE =
            new java.util.concurrent.ConcurrentHashMap<>();

    private boolean tableExists(String tableName) {
        String cacheKey = "table:" + tableName;
        Boolean cached = SCHEMA_EXISTS_CACHE.get(cacheKey);
        if (cached != null) {
            return cached;
        }

        boolean exists = false;

        String sql = "SELECT COUNT(*) FROM information_schema.tables "
                + "WHERE table_schema = DATABASE() AND table_name = ?";

        try (Connection con = DBConnection.getConnection()) {
            if (con == null) {
                DASHBOARD_LOGGER.warning("Dashboard table check skipped because the database connection is unavailable.");
                return false;
            }

            try (PreparedStatement ps = con.prepareStatement(sql)) {
                ps.setString(1, tableName);

                try (ResultSet rs = ps.executeQuery()) {
                    if (rs.next()) {
                        exists = rs.getInt(1) > 0;
                    }
                }
            }

            SCHEMA_EXISTS_CACHE.put(cacheKey, exists);

        } catch (Exception e) {
            DASHBOARD_LOGGER.log(java.util.logging.Level.WARNING, "Unable to check dashboard table: " + tableName, e);
        }

        return exists;
    }

    private boolean columnExists(String tableName, String columnName) {
        String cacheKey = "column:" + tableName + "." + columnName;
        Boolean cached = SCHEMA_EXISTS_CACHE.get(cacheKey);
        if (cached != null) {
            return cached;
        }

        boolean exists = false;

        String sql = "SELECT COUNT(*) FROM information_schema.columns "
                + "WHERE table_schema = DATABASE() AND table_name = ? AND column_name = ?";

        try (Connection con = DBConnection.getConnection()) {
            if (con == null) {
                DASHBOARD_LOGGER.warning("Dashboard column check skipped because the database connection is unavailable.");
                return false;
            }

            try (PreparedStatement ps = con.prepareStatement(sql)) {
                ps.setString(1, tableName);
                ps.setString(2, columnName);

                try (ResultSet rs = ps.executeQuery()) {
                    if (rs.next()) {
                        exists = rs.getInt(1) > 0;
                    }
                }
            }

            SCHEMA_EXISTS_CACHE.put(cacheKey, exists);

        } catch (Exception e) {
            DASHBOARD_LOGGER.log(java.util.logging.Level.WARNING,
                    "Unable to check dashboard column: " + tableName + "." + columnName, e);
        }

        return exists;
    }

    private List<Map<String, String>> sqlRows(String sql) {
        return sqlRows(sql, null);
    }

    private List<Map<String, String>> sqlRows(String sql, List<Integer> params) {
        List<Map<String, String>> rows = new ArrayList<>();

        try (Connection con = DBConnection.getConnection()) {
            if (con == null) {
                DASHBOARD_LOGGER.warning("Dashboard row query skipped because the database connection is unavailable.");
                return rows;
            }

            try (PreparedStatement ps = con.prepareStatement(sql)) {
                if (params != null) {
                    int paramIndex = 1;
                    for (Integer param : params) {
                        ps.setInt(paramIndex++, param);
                    }
                }
                try (ResultSet rs = ps.executeQuery()) {
                    ResultSetMetaData meta = rs.getMetaData();
                    int count = meta.getColumnCount();

                    while (rs.next()) {
                        Map<String, String> row = new HashMap<>();

                        for (int i = 1; i <= count; i++) {
                            row.put(meta.getColumnLabel(i), rs.getString(i));
                        }

                        rows.add(row);
                    }
                }
            }

        } catch (Exception e) {
            DASHBOARD_LOGGER.log(java.util.logging.Level.WARNING, "Unable to load dashboard row data.", e);
        }

        return rows;
    }

    private String rowValue(Map<String, String> row, String key) {
        if (row == null) {
            return "";
        }

        String value = row.get(key);
        return value == null ? "" : value;
    }

    private long rowLong(Map<String, String> row, String key) {
        try {
            String value = rowValue(row, key);

            if (value == null || value.trim().isEmpty()) {
                return 0;
            }

            return Math.round(Double.parseDouble(value));
        } catch (Exception e) {
            return 0;
        }
    }

    // Was a flat CSS conic-gradient background - visually fine, but a single
    // gradient image has no per-segment DOM elements, so nothing on it could
    // be individually hovered to show that segment's data. Replaced with an
    // SVG made of one real, hoverable <circle> per segment (the standard
    // stroke-dasharray/stroke-dashoffset donut-chart technique: each circle
    // draws a "len" length dash starting "cumulativeOffset" back around the
    // circle, so segments chain together end-to-end), sized (r=45,
    // stroke-width=30, viewBox 0-120) to sit inside the existing
    // .donut/.donut::before "hole punch" so the ring still looks identical
    // to the old gradient at rest - donut-tooltip.js (shared, loaded once)
    // drives the hover highlight + tooltip using the data-label/data-value/
    // data-percent attributes set on each circle here.
    private String donutSegment(String color, double lengthSoFar, double segmentLength, double circumference,
            String label, String value, String percentText) {
        return "<circle class=\"donut-segment\" cx=\"60\" cy=\"60\" r=\"45\" fill=\"none\" "
                + "stroke=\"" + color + "\" "
                + "stroke-dasharray=\"" + decimalOne(segmentLength) + " " + decimalOne(circumference) + "\" "
                + "stroke-dashoffset=\"" + decimalOne(-lengthSoFar) + "\" "
                + "transform=\"rotate(-90 60 60)\" "
                + "data-label=\"" + label + "\" data-value=\"" + value + "\" data-percent=\"" + percentText + "\">"
                + "<title>" + label + ": " + value + " (" + percentText + "%)</title>"
                + "</circle>";
    }

    private String assetDonutSegments(long operational, long maintenance, long damaged, long disposed, long awaiting, long total) {
        double circumference = 2 * Math.PI * 45;

        if (total <= 0) {
            return "<circle cx=\"60\" cy=\"60\" r=\"45\" fill=\"none\" stroke=\"#dbe4f2\" "
                    + "stroke-width=\"30\"></circle>";
        }

        StringBuilder sb = new StringBuilder();
        double cum = 0;
        double len;

        len = circumference * operational / total;
        sb.append(donutSegment("#078c48", cum, len, circumference, "Operational", indianNumber(operational), decimalOne(percent(operational, total))));
        cum += len;

        len = circumference * maintenance / total;
        sb.append(donutSegment("#ff8c24", cum, len, circumference, "Under Maintenance", indianNumber(maintenance), decimalOne(percent(maintenance, total))));
        cum += len;

        len = circumference * damaged / total;
        sb.append(donutSegment("#e93d3d", cum, len, circumference, "Damaged", indianNumber(damaged), decimalOne(percent(damaged, total))));
        cum += len;

        len = circumference * disposed / total;
        sb.append(donutSegment("#7c4dff", cum, len, circumference, "Disposed", indianNumber(disposed), decimalOne(percent(disposed, total))));
        cum += len;

        len = circumference * awaiting / total;
        sb.append(donutSegment("#8a98b5", cum, len, circumference, "Awaiting Verification", indianNumber(awaiting), decimalOne(percent(awaiting, total))));

        return sb.toString();
    }

    private String verificationDonutSegments(long verified, long underProcess, long pending, long total) {
        double circumference = 2 * Math.PI * 45;

        if (total <= 0) {
            return "<circle cx=\"60\" cy=\"60\" r=\"45\" fill=\"none\" stroke=\"#dbe4f2\" "
                    + "stroke-width=\"30\"></circle>";
        }

        StringBuilder sb = new StringBuilder();
        double cum = 0;
        double len;

        len = circumference * verified / total;
        sb.append(donutSegment("#078c48", cum, len, circumference, "Verified", indianNumber(verified), decimalOne(percent(verified, total))));
        cum += len;

        len = circumference * underProcess / total;
        sb.append(donutSegment("#ff8c24", cum, len, circumference, "Under Process", indianNumber(underProcess), decimalOne(percent(underProcess, total))));
        cum += len;

        len = circumference * pending / total;
        sb.append(donutSegment("#e93d3d", cum, len, circumference, "Pending", indianNumber(pending), decimalOne(percent(pending, total))));

        return sb.toString();
    }
%>

<%
    String username = (String) session.getAttribute("username");
    String role = (String) session.getAttribute("role");
    String normalizedRole = normalizeRole(role);

    response.setHeader("Cache-Control", "no-cache, no-store, must-revalidate");
    response.setHeader("Pragma", "no-cache");
    response.setDateHeader("Expires", 0);

    if (username == null || role == null || normalizedRole.isEmpty()) {
        response.sendRedirect("login.jsp");
        return;
    }

    role = normalizedRole;

    if ("EMPLOYEE".equals(role)) {
        response.sendRedirect("employee_dashboard.jsp");
        return;
    }

    DashboardDAO dao = new DashboardDAO();
    RecentActivityDAO activityDAO = new RecentActivityDAO();

    List<RecentActivity> recentActivities = activityDAO.getRecentActivities();

    boolean isSuperAdmin = ("SUPER_ADMIN".equals(role) || "ADMIN".equals(role));
    boolean isAssetManager = "ASSET_MANAGER".equalsIgnoreCase(role);
    boolean isDepartmentHead = "DEPARTMENT_HEAD".equalsIgnoreCase(role);
    boolean isAuditor = "AUDITOR".equalsIgnoreCase(role);
    boolean isEmployee = "EMPLOYEE".equalsIgnoreCase(role);

    boolean canViewAssets = !isEmployee;
    boolean canViewAllocation = isSuperAdmin || isAssetManager;
    boolean canViewMaintenance = isSuperAdmin || isAssetManager || isAuditor;
    boolean canViewAudit = isSuperAdmin || isAuditor;
    boolean canViewWarranty = isSuperAdmin || isAssetManager || isAuditor;
    // physical_verification.jsp's own gate (canViewVerification) explicitly allows
    // Department Head and redirects everyone else away - this flag was narrower than
    // the page it gates, so a Department Head saw this dashboard hide/deny a page they
    // could actually open directly. RoleAccessUtil.java's ROLE_MAP for this path was
    // fixed to match the same page-authoritative role set.
    boolean canVerify = isSuperAdmin || isAssetManager || isAuditor || isDepartmentHead;
    // canRequestRegister used to be true for Department Head too, and every link that
    // used it (bell icon, "Approvals Pending"/"Requests Approved" queue rows, plus the
    // "Requests" hero-tab / "Plan" footer-step via requestDashboardHref, which always
    // resolved to asset_requests.jsp for any non-employee role reaching this page)
    // pointed a Department Head at asset_requests.jsp - the request-APPROVAL console.
    // RoleAccessUtil.java restricts that specific page to SUPER_ADMIN/ADMIN/ASSET_MANAGER
    // only ("Step 1 decision, DEPARTMENT_HEAD removed" - a deliberate, documented policy,
    // not an oversight), so a Department Head clicking any of those was landing on a 403
    // from RoleAuthorizationFilter despite this page's own UI implying they were allowed.
    // Split into the two permissions RoleAccessUtil actually enforces separately:
    // approving requests (ops roles only) vs. creating/viewing them (also Department Head
    // and, in principle, Employee - though Employees never reach this page, they're
    // redirected to employee_dashboard.jsp before this code runs).
    boolean canApproveRequests = isSuperAdmin || isAssetManager;
    boolean canCreateRequest = canApproveRequests || isDepartmentHead || isEmployee;
    boolean canRequest = canCreateRequest;
    // reports.jsp's own gate (allowedRole) explicitly allows Department Head - same
    // narrower-than-the-target-page problem as canVerify above.
    boolean canReport = isSuperAdmin || isAssetManager || isAuditor || isDepartmentHead;
    boolean canViewQr = isSuperAdmin || isAssetManager || isAuditor;
    // Routes to the approval console only if this role can actually use it; everyone
    // else (Department Head included) goes to the request-creation page instead, which
    // RoleAccessUtil confirms they can reach.
    String requestDashboardHref = canApproveRequests ? "asset_requests.jsp" : "add_request.jsp";

    List<Integer> departmentIds = (List<Integer>) session.getAttribute("departmentIds");
    String deptFilter = "";
    String deptFilterA = "";
    String deptFilterEmp = "";
    List<Integer> deptParams = null;
    if (isDepartmentHead && !isSuperAdmin && !isAssetManager && !isAuditor) {
        if (departmentIds != null && !departmentIds.isEmpty()) {
            StringBuilder sb = new StringBuilder(" IN (");
            for (int i = 0; i < departmentIds.size(); i++) {
                sb.append("?");
                if (i < departmentIds.size() - 1) sb.append(",");
            }
            sb.append(") ");
            deptFilter = " AND department_id " + sb.toString();
            deptFilterA = " AND a.department_id " + sb.toString();
            deptFilterEmp = " AND e.department_id " + sb.toString();
            deptParams = departmentIds;
        } else {
            deptFilter = " AND department_id = -1 ";
            deptFilterA = " AND a.department_id = -1 ";
            deptFilterEmp = " AND e.department_id = -1 ";
        }
    }

    int totalAssets = dao.getCount("assets", departmentIds);

    // Was dao.getCount("maintenance_logs", departmentIds) - DashboardDAO.getCount()
    // only applies its department filter for "assets"/"asset_requests"/
    // "asset_allocation"/"asset_returns" (maintenance_logs was never in that list, and
    // it has no department_id column to filter on directly anyway), so a Department
    // Head was seeing the system-wide maintenance log count here while every other
    // number on this page is correctly scoped to their own department(s). Fixed by
    // joining through assets (which does carry department_id) using the same
    // deptFilterA pattern the rest of this page already uses for asset-joined counts.
    int totalMaintenanceLogs = sqlInt(
            "SELECT COUNT(*) FROM maintenance_logs ml JOIN assets a ON ml.asset_id = a.asset_id WHERE 1=1" + deptFilterA,
            deptParams);

    int allocatedAssets = dao.getAssetStatusCount("ALLOCATED", departmentIds);
    int underMaintenanceAssets = dao.getAssetStatusCount("UNDER_MAINTENANCE", departmentIds);
    int disposedAssets = dao.getAssetStatusCount("DISPOSED", departmentIds);
    double totalAssetValue = dao.getTotalAssetValue(departmentIds);

    int operationalAssets = sqlInt("SELECT COUNT(*) FROM assets WHERE asset_status <> 'DISPOSED' AND service_status = 'SERVICEABLE'" + deptFilter, deptParams);
    int maintenanceAssets = sqlInt("SELECT COUNT(*) FROM assets WHERE asset_status = 'UNDER_MAINTENANCE' OR service_status IN ('NEEDS_ATTENTION','UNDER_REPAIR')" + deptFilter, deptParams);
    int damagedAssets = sqlInt("SELECT COUNT(*) FROM assets WHERE asset_status = 'DAMAGED' OR condition_status = 'DAMAGED' OR service_status = 'DAMAGED'" + deptFilter, deptParams);
    int awaitingVerificationAssets = sqlInt("SELECT COUNT(*) FROM assets WHERE last_physical_verification_date IS NULL" + deptFilter, deptParams);

    int verificationsPending = awaitingVerificationAssets;
    int inspectionsDue = sqlInt("SELECT COUNT(*) FROM assets WHERE asset_status <> 'DISPOSED' AND (last_physical_verification_date IS NULL OR last_physical_verification_date < DATE_SUB(CURDATE(), INTERVAL 90 DAY))" + deptFilter, deptParams);
    int maintenanceOverdue = maintenanceAssets;
    int warrantyExpiring = sqlInt("SELECT COUNT(*) FROM assets WHERE warranty_expiry BETWEEN CURDATE() AND DATE_ADD(CURDATE(), INTERVAL 30 DAY)" + deptFilter, deptParams);
    int approvalsPending = sqlInt("SELECT COUNT(*) FROM asset_requests ar JOIN employees e ON ar.employee_id = e.employee_id WHERE ar.request_status = 'PENDING'" + deptFilterEmp, deptParams);
    int procurementPending = sqlInt("SELECT COUNT(*) FROM asset_requests ar JOIN employees e ON ar.employee_id = e.employee_id WHERE ar.request_status = 'APPROVED'" + deptFilterEmp, deptParams);
    int maintenanceRequestsPending = sqlInt("SELECT COUNT(*) FROM maintenance_requests mr JOIN assets a ON mr.asset_id = a.asset_id WHERE mr.request_status = 'PENDING'" + deptFilterA, deptParams);

    int pvTotal = sqlInt("SELECT COUNT(*) FROM asset_physical_verification pv JOIN assets a ON pv.asset_id = a.asset_id WHERE 1=1" + deptFilterA, deptParams);
    int pvVerified = sqlInt("SELECT COUNT(*) FROM asset_physical_verification pv JOIN assets a ON pv.asset_id = a.asset_id WHERE pv.verified_status = 'VERIFIED'" + deptFilterA, deptParams);
    int pvUnderProcess = sqlInt("SELECT COUNT(*) FROM asset_physical_verification pv JOIN assets a ON pv.asset_id = a.asset_id WHERE pv.review_status IN ('SUBMITTED','REVIEWED') AND pv.verified_status <> 'VERIFIED'" + deptFilterA, deptParams);
    int pvPending = Math.max(totalAssets - pvVerified, 0);

    double pvVerifiedPercent = percent(pvVerified, Math.max(totalAssets, pvTotal));

    boolean hasAssetsQrToken = columnExists("assets", "qr_public_token");
    boolean hasQrScanLogs = tableExists("asset_qr_scan_logs");
    boolean hasQrTaggingStatus = tableExists("asset_qr_tagging_status");

    int qrGenerated = hasAssetsQrToken
            ? sqlInt("SELECT COUNT(*) FROM assets WHERE qr_public_token IS NOT NULL AND TRIM(qr_public_token) <> ''" + deptFilter, deptParams)
            : 0;

    int qrMissing = Math.max(totalAssets - qrGenerated, 0);

    int qrTotalScans = hasQrScanLogs
            ? sqlInt("SELECT COUNT(*) FROM asset_qr_scan_logs q JOIN assets a ON q.asset_id = a.asset_id WHERE 1=1" + deptFilterA, deptParams)
            : 0;

    int qrInvalidScans = hasQrScanLogs
            ? sqlInt("SELECT COUNT(*) FROM asset_qr_scan_logs q JOIN assets a ON q.asset_id = a.asset_id WHERE q.scan_status = 'INVALID_TOKEN'" + deptFilterA, deptParams)
            : 0;

    int qrTodayScans = hasQrScanLogs
            ? sqlInt("SELECT COUNT(*) FROM asset_qr_scan_logs q JOIN assets a ON q.asset_id = a.asset_id WHERE DATE(q.scanned_at) = CURDATE()" + deptFilterA, deptParams)
            : 0;

    int qrTagged = hasQrTaggingStatus
            ? sqlInt("SELECT COUNT(*) FROM asset_qr_tagging_status q JOIN assets a ON q.asset_id = a.asset_id WHERE q.tag_status = 'TAGGED'" + deptFilterA, deptParams)
            : 0;

    int qrTagPending = Math.max(qrGenerated - qrTagged, 0);

    boolean hasDepartmentsTable = tableExists("departments");
    boolean hasAssetCategoriesTable = tableExists("asset_categories");
    boolean hasCategoriesTable = tableExists("categories");
    boolean hasRailwayLocationsTable = tableExists("railway_locations");

    boolean hasAssetsDepartmentId = columnExists("assets", "department_id");
    boolean hasAssetsCategoryId = columnExists("assets", "category_id");
    boolean hasAssetsLocationId = columnExists("assets", "location_id");
    boolean hasAssetsLocationText = columnExists("assets", "location");

    String departmentSql;

    if (hasAssetsDepartmentId && hasDepartmentsTable) {
        departmentSql =
                "SELECT COALESCE(d.department_name, 'Unassigned') AS department_name, "
                + "COUNT(a.asset_id) AS total_assets "
                + "FROM assets a "
                + "LEFT JOIN departments d ON a.department_id = d.department_id "
                + "WHERE 1=1 " + deptFilterA + " "
                + "GROUP BY COALESCE(d.department_name, 'Unassigned') "
                + "ORDER BY total_assets DESC, department_name ASC "
                + "LIMIT 6";
    } else if (hasAssetsCategoryId && hasAssetCategoriesTable) {
        departmentSql =
                "SELECT COALESCE(c.category_name, 'Uncategorized') AS department_name, "
                + "COUNT(a.asset_id) AS total_assets "
                + "FROM assets a "
                + "LEFT JOIN asset_categories c ON a.category_id = c.category_id "
                + "WHERE 1=1 " + deptFilterA + " "
                + "GROUP BY COALESCE(c.category_name, 'Uncategorized') "
                + "ORDER BY total_assets DESC, department_name ASC "
                + "LIMIT 6";
    } else if (hasAssetsCategoryId && hasCategoriesTable) {
        departmentSql =
                "SELECT COALESCE(c.category_name, 'Uncategorized') AS department_name, "
                + "COUNT(a.asset_id) AS total_assets "
                + "FROM assets a "
                + "LEFT JOIN categories c ON a.category_id = c.category_id "
                + "WHERE 1=1 " + deptFilterA + " "
                + "GROUP BY COALESCE(c.category_name, 'Uncategorized') "
                + "ORDER BY total_assets DESC, department_name ASC "
                + "LIMIT 6";
    } else {
        departmentSql =
                "SELECT COALESCE(NULLIF(asset_status, ''), 'Unclassified') AS department_name, "
                + "COUNT(asset_id) AS total_assets "
                + "FROM assets "
                + "WHERE 1=1 " + deptFilter + " "
                + "GROUP BY COALESCE(NULLIF(asset_status, ''), 'Unclassified') "
                + "ORDER BY total_assets DESC, department_name ASC "
                + "LIMIT 6";
    }

    String sectionSql;

    if (hasAssetsLocationId && hasRailwayLocationsTable && hasAssetsLocationText) {
        sectionSql =
                "SELECT COALESCE(rl.location_name, NULLIF(a.location, ''), 'Unspecified Location') AS section_name, "
                + "COUNT(a.asset_id) AS total_assets, "
                + "SUM(CASE WHEN a.asset_status <> 'DISPOSED' AND a.service_status <> 'UNSERVICEABLE' THEN 1 ELSE 0 END) AS in_service "
                + "FROM assets a "
                + "LEFT JOIN railway_locations rl ON a.location_id = rl.location_id "
                + "WHERE 1=1 " + deptFilterA + " "
                + "GROUP BY COALESCE(rl.location_name, NULLIF(a.location, ''), 'Unspecified Location') "
                + "ORDER BY total_assets DESC, section_name ASC "
                + "LIMIT 6";
    } else if (hasAssetsLocationId && hasRailwayLocationsTable) {
        sectionSql =
                "SELECT COALESCE(rl.location_name, 'Unspecified Location') AS section_name, "
                + "COUNT(a.asset_id) AS total_assets, "
                + "SUM(CASE WHEN a.asset_status <> 'DISPOSED' AND a.service_status <> 'UNSERVICEABLE' THEN 1 ELSE 0 END) AS in_service "
                + "FROM assets a "
                + "LEFT JOIN railway_locations rl ON a.location_id = rl.location_id "
                + "WHERE 1=1 " + deptFilterA + " "
                + "GROUP BY COALESCE(rl.location_name, 'Unspecified Location') "
                + "ORDER BY total_assets DESC, section_name ASC "
                + "LIMIT 6";
    } else if (hasAssetsLocationText) {
        sectionSql =
                "SELECT COALESCE(NULLIF(location, ''), 'Unspecified Location') AS section_name, "
                + "COUNT(asset_id) AS total_assets, "
                + "SUM(CASE WHEN asset_status <> 'DISPOSED' AND service_status <> 'UNSERVICEABLE' THEN 1 ELSE 0 END) AS in_service "
                + "FROM assets "
                + "WHERE 1=1 " + deptFilter + " "
                + "GROUP BY COALESCE(NULLIF(location, ''), 'Unspecified Location') "
                + "ORDER BY total_assets DESC, section_name ASC "
                + "LIMIT 6";
    } else if (hasAssetsDepartmentId && hasDepartmentsTable) {
        sectionSql =
                "SELECT COALESCE(d.department_name, 'Unassigned Section') AS section_name, "
                + "COUNT(a.asset_id) AS total_assets, "
                + "SUM(CASE WHEN a.asset_status <> 'DISPOSED' AND a.service_status <> 'UNSERVICEABLE' THEN 1 ELSE 0 END) AS in_service "
                + "FROM assets a "
                + "LEFT JOIN departments d ON a.department_id = d.department_id "
                + "WHERE 1=1 " + deptFilterA + " "
                + "GROUP BY COALESCE(d.department_name, 'Unassigned Section') "
                + "ORDER BY total_assets DESC, section_name ASC "
                + "LIMIT 6";
    } else {
        sectionSql =
                "SELECT 'Headquarters / Rail Sadan' AS section_name, "
                + "COUNT(asset_id) AS total_assets, "
                + "SUM(CASE WHEN asset_status <> 'DISPOSED' AND service_status <> 'UNSERVICEABLE' THEN 1 ELSE 0 END) AS in_service "
                + "FROM assets "
                + "WHERE 1=1 " + deptFilter;
    }

    List<Map<String, String>> departmentRows = sqlRows(departmentSql, deptParams);
    List<Map<String, String>> sectionRows = sqlRows(sectionSql, deptParams);

    List<Map<String, String>> recentAssetRows = sqlRows(
            "SELECT asset_id, asset_code, asset_name, asset_status, DATE_FORMAT(created_at, '%d %b %Y') AS added_on "
            + "FROM assets WHERE 1=1 " + deptFilter + " ORDER BY created_at DESC, asset_id DESC LIMIT 5", deptParams);

    List<Map<String, String>> verificationRows = sqlRows(
            "SELECT pv.verification_id, a.asset_id, pv.verified_status, DATE_FORMAT(pv.verified_on, '%d %b %Y, %h:%i %p') AS verified_on, "
            + "a.asset_code, a.asset_name, COALESCE(u.username, 'System') AS verified_by "
            + "FROM asset_physical_verification pv "
            + "LEFT JOIN assets a ON pv.asset_id = a.asset_id "
            + "LEFT JOIN users u ON pv.verified_by_user_id = u.user_id "
            + "WHERE 1=1 " + deptFilterA + " "
            + "ORDER BY pv.verified_on DESC, pv.verification_id DESC LIMIT 4", deptParams);

    boolean dashboardDataWarning = dao.hasQueryError() || activityDAO.hasQueryError();

    String userInitial = safeInitial(username);
%>

<!DOCTYPE html>
<html lang="en-IN">
<head>
    <meta charset="UTF-8">
    <meta http-equiv="Content-Type" content="text/html; charset=UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>IR-AMS Dashboard</title>

    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.0/css/all.min.css">

    <link rel="stylesheet" href="css/ir-glass.css?v=28000">
    <link rel="stylesheet" href="css/ams-pro.css?v=28000">
    <link rel="stylesheet" href="css/ir-ams-railway-ui.css?v=dashboard-footer-fix-1">

    <link rel="stylesheet" href="css/dashboard.css?v=28001">
</head>

<body class="railway-ui">
<div class="app ams-shell">

    <%@ include file="sidebar.jsp" %>

    <main class="main railway-main">
        <%
            // dashboard.jsp keeps its own copy of the topbar markup instead of
            // including topbar.jsp (pre-existing duplication, not introduced here -
            // only this file and add_maintenance.jsp do this; every other page in
            // the app shares the one file). Kept in sync by hand: same session-timer
            // pill, same computation, as topbar.jsp's.
            int dashboardSessionTimeoutMinutes = SettingsDAO.getSessionTimeout();
            if (dashboardSessionTimeoutMinutes < 1 || dashboardSessionTimeoutMinutes > 1440) {
                dashboardSessionTimeoutMinutes = 30;
            }
            // See topbar.jsp's identical marker - kept in sync by hand since
            // this page renders its own copy of the topbar rather than
            // <jsp:include>-ing it.
            String dashboardSessionMarker = session.getAttribute("client_session_marker") != null
                    ? (String) session.getAttribute("client_session_marker") : "legacy-session";
        %>
        <header class="topbar railway-topbar">
            <button class="nav-toggle" type="button" aria-label="Menu">
                <i class="fa-solid fa-bars"></i>
            </button>

            <a href="dashboard.jsp" class="topbar-title topbar-home-link" title="Open Dashboard">
                <h1>IR-AMS</h1>
                <span>Railway Asset Management System</span>
            </a>

            <button class="hq-selector" type="button" data-dashboard-menu="hq" aria-label="Railway unit menu">
                <i class="fa-solid fa-location-dot"></i>
                <div>
                    <strong>East Coast Railway</strong>
                    <span>Headquarters / Rail Sadan, Bhubaneswar</span>
                </div>
                <i class="fa-solid fa-angle-down"></i>
            </button>

            <div class="search-box">
                <i class="fa-solid fa-magnifying-glass"></i>
                <input type="text" id="globalSearch" placeholder="Search assets, holders, departments, sections, reports...">
            </div>

            <div class="top-right topbar-actions">
                <div class="control-active session-timer-pill" id="sessionTimerPill" title="Time remaining before automatic sign-out"
                     data-total-seconds="<%= dashboardSessionTimeoutMinutes * 60 %>" data-context-path="<%= request.getContextPath() %>"
                     data-session-marker="<%= dashboardSessionMarker %>">
                    <i class="fa-regular fa-clock"></i>
                    <span id="sessionTimerText">--:--</span>
                </div>

                <button class="control-active" type="button" data-dashboard-menu="control" aria-label="System control menu">
                    <i class="fa-solid fa-shield-halved"></i>
                    Control Active
                    <i class="fa-solid fa-angle-down"></i>
                </button>

                <a class="top-icon-btn" href="<%= roleHref(canApproveRequests, "asset_requests.jsp") %>" aria-label="Pending approvals" title="<%= roleTitle(canApproveRequests, "Open pending approvals") %>">
                    <i class="fa-regular fa-bell"></i>
                    <% if (approvalsPending > 0) { %>
                    <span class="badge"><%= approvalsPending %></span>
                    <% } %>
                </a>



                <a class="top-icon-btn" href="dashboard_help.jsp" aria-label="Help and support" title="Open help and support">
                    <i class="fa-regular fa-circle-question"></i>
                </a>

                <div class="user-card">
                    <div class="avatar"><%= safeText(userInitial) %></div>
                    <div>
                        <strong><%= safeText(username) %></strong>
                        <span><%= safeText(cleanLabel(role)) %></span>
                    </div>
                </div>
            </div>
        </header>

        <style>
            body.railway-ui .session-timer-pill { color: var(--ir-text, #06215f) !important; cursor: default !important; }
            body.railway-ui .session-timer-pill.session-timer-warning { color: #b45309 !important; }
            body.railway-ui .session-timer-pill.session-timer-critical { color: #b91c1c !important; }
        </style>
        <script src="<%= request.getContextPath() %>/js/session-timer.js?v=1"></script>

        <div class="main-scroll-content dashboard-board">
            <% if ("denied".equals(request.getParameter("access"))) { %>
                <div class="page-error">
                    <i class="fa-solid fa-triangle-exclamation"></i>
                    Access denied. You do not have permission to open that module.
                </div>
            <% } %>

            <%-- Fault: ChangePasswordServlet redirects non-employee roles here after a
                 successful password change, but this page never read the msg
                 parameter at all - a real, successful change showed no confirmation
                 here (employee_dashboard.jsp had the same gap for a different
                 reason - see ChangePasswordServlet's own fix comment). --%>
            <% if ("password_changed".equals(request.getParameter("msg"))) { %>
                <div class="page-success">
                    <i class="fa-solid fa-circle-check"></i>
                    Password changed successfully!
                </div>
            <% } %>

            <% if (dashboardDataWarning) { %>
                <div class="page-error dashboard-load-warning">
                    <i class="fa-solid fa-circle-info"></i>
                    Some dashboard live data could not be refreshed. Please verify database connectivity and try again.
                </div>
            <% } %>

            <section class="dashboard-hero hero-official">
                <div class="hero-copy">
                    <h1>One Railway. One Control.<br>Every Asset. Every Journey.</h1>

                    <p>
                        Unified command for complete asset lifecycle monitoring across holders,
                        departments, sections, maintenance, reports, and physical verification.
                    </p>

                    <div class="hero-tabs">
                        <% if (canViewAssets) { %>
                            <a href="assets.jsp" class="hero-tab">
                                <i class="fa-solid fa-cube"></i>
                                <span>Assets</span>
                            </a>
                        <% } %>

                        <% if (canViewAllocation) { %>
                            <a href="allocation.jsp" class="hero-tab">
                                <i class="fa-solid fa-arrow-right-arrow-left"></i>
                                <span>Allocation</span>
                            </a>
                            
                            <a href="returns.jsp" class="hero-tab">
                                <i class="fa-solid fa-rotate-left"></i>
                                <span>Returns</span>
                            </a>
                        <% } %>

                        <% if (canViewMaintenance) { %>
                            <a href="maintenance.jsp" class="hero-tab">
                                <i class="fa-solid fa-screwdriver-wrench"></i>
                                <span>Maintenance</span>
                            </a>
                        <% } %>

                        <% if (canVerify) { %>
                            <a href="physical_verification.jsp" class="hero-tab">
                                <i class="fa-solid fa-shield-halved"></i>
                                <span>Physical Verification</span>
                            </a>
                        <% } %>

                        <% if (canReport) { %>
                            <a href="reports.jsp" class="hero-tab">
                                <i class="fa-solid fa-chart-simple"></i>
                                <span>Reports</span>
                            </a>
                        <% } %>

                        <% if (canViewQr) { %>
                            <a href="qr_control_center.jsp" class="hero-tab">
                                <i class="fa-solid fa-qrcode"></i>
                                <span>QR Control</span>
                            </a>
                        <% } %>

                        <% if (canRequest) { %>
                            <a href="<%= requestDashboardHref %>" class="hero-tab">
                                <i class="fa-solid fa-file-circle-plus"></i>
                                <span>Requests</span>
                            </a>
                        <% } %>
                    </div>
                </div>

                <div class="hero-odia">
                    <span class="odia">ଓଡ଼ିଶାର ଗୌରବ, ଭାରତର ଶକ୍ତି</span>
                    <span class="english">Odisha's Pride, India's Strength</span>
                </div>
            </section>

            <section class="kpi-grid-dashboard">
                <a class="kpi-card kpi-card-official dashboard-action-link"
                   href="<%= roleHref(canViewAssets, "assets.jsp") %>"
                   title="<%= roleTitle(canViewAssets, "Open all assets") %>">
                    <div class="kpi-icon kpi-icon-circle"><i class="fa-solid fa-cube"></i></div>
                    <div class="kpi-content">
                        <h3 class="kpi-title">Total Assets</h3>
                        <div class="kpi-value"><%= indianNumber(totalAssets) %></div>
                        <%-- This card has nothing to compare totalAssets against - the old
                             percent(totalAssets, max(totalAssets,1)) was mathematically always
                             ~100%, not a real trend. Matches the wording style already used by
                             the "Total Asset Value" card below for the same reason (no
                             period-over-period data exists to show a real trend here). --%>
                        <div class="kpi-trend"><i class="fa-solid fa-arrow-up"></i> Live <span>inventory count</span></div>
                    </div>
                </a>

                <a class="kpi-card kpi-card-official dashboard-action-link"
                   href="<%= roleHref(canViewAllocation, "allocation.jsp") %>"
                   title="<%= roleTitle(canViewAllocation, "Open allocated assets") %>">
                    <div class="kpi-icon kpi-icon-circle orange"><i class="fa-solid fa-user-plus"></i></div>
                    <div class="kpi-content">
                        <h3 class="kpi-title">Allocated Assets</h3>
                        <div class="kpi-value"><%= indianNumber(allocatedAssets) %></div>
                        <div class="kpi-trend"><i class="fa-solid fa-arrow-up"></i> <%= decimalOne(percent(allocatedAssets, totalAssets)) %>% <span>of assets</span></div>
                    </div>
                </a>

                <a class="kpi-card kpi-card-official dashboard-action-link"
                   href="<%= roleHref(canViewAllocation, "allocation.jsp") %>"
                   title="<%= roleTitle(canViewAllocation, "Open assets in use") %>">
                    <div class="kpi-icon kpi-icon-circle"><i class="fa-solid fa-shield-halved"></i></div>
                    <div class="kpi-content">
                        <h3 class="kpi-title">Assets in Use</h3>
                        <div class="kpi-value"><%= indianNumber(allocatedAssets + underMaintenanceAssets) %></div>
                        <div class="kpi-trend"><i class="fa-solid fa-arrow-up"></i> <%= decimalOne(percent(allocatedAssets + underMaintenanceAssets, totalAssets)) %>% <span>active use</span></div>
                    </div>
                </a>

                <a class="kpi-card kpi-card-official dashboard-action-link"
                   href="<%= roleHref(canViewMaintenance, "maintenance.jsp") %>"
                   title="<%= roleTitle(canViewMaintenance, "Open maintenance records") %>">
                    <div class="kpi-icon kpi-icon-circle purple"><i class="fa-solid fa-screwdriver-wrench"></i></div>
                    <div class="kpi-content">
                        <h3 class="kpi-title">Under Maintenance</h3>
                        <div class="kpi-value"><%= indianNumber(underMaintenanceAssets) %></div>
                        <div class="kpi-trend"><i class="fa-solid fa-arrow-up"></i> <%= decimalOne(percent(underMaintenanceAssets, totalAssets)) %>% <span>of assets</span></div>
                    </div>
                </a>

                <a class="kpi-card kpi-card-official dashboard-action-link"
                   href="<%= roleHref(canViewAssets, "assets.jsp") %>"
                   title="<%= roleTitle(canViewAssets, "Open disposed or retired assets") %>">
                    <div class="kpi-icon kpi-icon-circle red"><i class="fa-solid fa-recycle"></i></div>
                    <div class="kpi-content">
                        <h3 class="kpi-title">Disposed / Retired</h3>
                        <div class="kpi-value"><%= indianNumber(disposedAssets) %></div>
                        <div class="kpi-trend"><i class="fa-solid fa-arrow-up"></i> <%= decimalOne(percent(disposedAssets, totalAssets)) %>% <span>of assets</span></div>
                    </div>
                </a>

                <a class="kpi-card kpi-card-official dashboard-action-link"
                   href="<%= roleHref(canReport, "reports.jsp") %>"
                   title="<%= roleTitle(canReport, "Open asset value reports") %>">
                    <div class="kpi-icon kpi-icon-circle green"><i class="fa-solid fa-indian-rupee-sign"></i></div>
                    <div class="kpi-content">
                        <h3 class="kpi-title">Total Asset Value (₹)</h3>
                        <div class="kpi-value"><%= indianNumber(Math.round(totalAssetValue)) %></div>
                        <div class="kpi-trend"><i class="fa-solid fa-arrow-up"></i> Database <span>purchase value</span></div>
                    </div>
                </a>

                <a class="kpi-card kpi-card-official dashboard-action-link"
                   href="<%= roleHref(canViewMaintenance, "maintenance_requests.jsp") %>"
                   title="<%= roleTitle(canViewMaintenance, "Open employee maintenance requests") %>">
                    <div class="kpi-icon kpi-icon-circle blue"><i class="fa-solid fa-wrench"></i></div>
                    <div class="kpi-content">
                        <h3 class="kpi-title">Maint. Requests Pending</h3>
                        <div class="kpi-value"><%= indianNumber(maintenanceRequestsPending) %></div>
                        <div class="kpi-trend"><i class="fa-solid fa-circle-exclamation"></i> Action <span>required</span></div>
                    </div>
                </a>
            </section>

            <% if (canViewQr) { %>
                <section class="official-panel" id="irams-dashboard-qr-panel">
                    <div class="qr-panel-head">
                        <div>
                            <h2>QR Governance Shortcuts</h2>
                            <p>Direct access to QR health, missing QR, tagging, scan logs and QR command center.</p>
                        </div>

                        <div class="qr-panel-actions">
                            <a href="qr_control_center.jsp" class="qr-pill-btn primary">
                                <i class="fa-solid fa-qrcode"></i>
                                Open QR Center
                            </a>

                            <a href="qr_asset_register.jsp" class="qr-pill-btn green">
                                <i class="fa-solid fa-table-list"></i>
                                QR Register
                            </a>
                        </div>
                    </div>

                    <div class="qr-dashboard-grid">
                        <a href="qr_control_center.jsp" class="qr-dashboard-card">
                            <div class="qr-dashboard-icon">
                                <i class="fa-solid fa-qrcode"></i>
                            </div>

                            <div>
                                <strong>QR Control Center</strong>
                                <span class="qr-dashboard-value"><%= indianNumber(qrGenerated) %></span>
                                <span class="qr-dashboard-desc">Generated QR tokens</span>
                            </div>
                        </a>

                        <a href="qr_system_health.jsp" class="qr-dashboard-card green">
                            <div class="qr-dashboard-icon">
                                <i class="fa-solid fa-heart-pulse"></i>
                            </div>

                            <div>
                                <strong>QR System Health</strong>
                                <span class="qr-dashboard-value"><%= hasAssetsQrToken && hasQrScanLogs ? "OK" : "Check" %></span>
                                <span class="qr-dashboard-desc">Tables and readiness</span>
                            </div>
                        </a>

                        <a href="qr_missing_qr_report.jsp" class="qr-dashboard-card red">
                            <div class="qr-dashboard-icon">
                                <i class="fa-solid fa-hourglass-half"></i>
                            </div>

                            <div>
                                <strong>Missing QR</strong>
                                <span class="qr-dashboard-value"><%= indianNumber(qrMissing) %></span>
                                <span class="qr-dashboard-desc">Assets requiring QR</span>
                            </div>
                        </a>

                        <a href="qr_tagging_status.jsp" class="qr-dashboard-card orange">
                            <div class="qr-dashboard-icon">
                                <i class="fa-solid fa-tags"></i>
                            </div>

                            <div>
                                <strong>Tagging Pending</strong>
                                <span class="qr-dashboard-value"><%= indianNumber(qrTagPending) %></span>
                                <span class="qr-dashboard-desc">Physical QR tagging</span>
                            </div>
                        </a>

                        <a href="qr_scan_logs.jsp" class="qr-dashboard-card">
                            <div class="qr-dashboard-icon">
                                <i class="fa-solid fa-list-check"></i>
                            </div>

                            <div>
                                <strong>QR Scan Logs</strong>
                                <span class="qr-dashboard-value"><%= indianNumber(qrTotalScans) %></span>
                                <span class="qr-dashboard-desc">Today: <%= indianNumber(qrTodayScans) %> · Invalid: <%= indianNumber(qrInvalidScans) %></span>
                            </div>
                        </a>
                    </div>
                </section>
            <% } %>

            <%
                // Fault (dead setting, fixed): Settings > Notifications' "Dashboard Alerts"
                // toggle was saved and displayed correctly (it's in NotificationHelper's own
                // ALERT_COLUMNS whitelist) but nothing ever actually checked it - this panel
                // showed unconditionally regardless of the toggle. Gated here, the same on/off
                // switch every other notification-settings toggle already controls its own
                // module by (isAlertSettingEnabled()), defaulting to shown (true) so nothing
                // changes for anyone who has never touched this specific toggle.
                boolean dashboardAlertsEnabled = NotificationHelper.isAlertSettingEnabled("dashboard_alerts", true);
            %>
            <% if (dashboardAlertsEnabled && (inspectionsDue > 0 || maintenanceOverdue > 0 || warrantyExpiring > 0)) { %>
            <section class="official-panel dashboard-alert-panel">
                <div class="panel-header">
                    <h2 class="panel-title"><i class="fa-solid fa-triangle-exclamation"></i> Action Required: Overdue Items</h2>
                </div>
                <div class="dashboard-alert-grid">
                    <% if (inspectionsDue > 0) { %>
                    <div class="dashboard-alert-card">
                        <div class="label">Inspections Due</div>
                        <div class="value"><%= indianNumber(inspectionsDue) %></div>
                        <a href="<%= roleHref(canVerify, "physical_verification.jsp") %>">View Assets <i class="fa-solid fa-arrow-right"></i></a>
                    </div>
                    <% } %>
                    
                    <% if (maintenanceOverdue > 0) { %>
                    <div class="dashboard-alert-card">
                        <div class="label">Maintenance Overdue</div>
                        <div class="value"><%= indianNumber(maintenanceOverdue) %></div>
                        <a href="<%= roleHref(canViewMaintenance, "maintenance.jsp") %>">View Schedule <i class="fa-solid fa-arrow-right"></i></a>
                    </div>
                    <% } %>
                    
                    <% if (warrantyExpiring > 0) { %>
                    <div class="dashboard-alert-card">
                        <div class="label">Warranties Expiring (30 Days)</div>
                        <div class="value"><%= indianNumber(warrantyExpiring) %></div>
                        <a href="<%= roleHref(canViewWarranty, "warranty_report.jsp") %>">View Warranties <i class="fa-solid fa-arrow-right"></i></a>
                    </div>
                    <% } %>
                </div>
            </section>
            <% } %>

            <section class="dashboard-grid-primary">
                <div class="official-panel">
                    <div class="panel-header panel-title-row">
                        <h2 class="panel-title">Asset Health Overview</h2>
                    </div>

                    <div class="donut-wrap donut-layout">
                        <div class="donut donut-chart">
                            <svg class="donut-svg" viewBox="0 0 120 120">
                                <%= assetDonutSegments(operationalAssets, maintenanceAssets, damagedAssets, disposedAssets, awaitingVerificationAssets, totalAssets) %>
                            </svg>
                            <div class="donut-center">
                                <strong><%= indianNumber(totalAssets) %></strong>
                                <span>Total Assets</span>
                            </div>
                        </div>

                        <div class="legend legend-list">
                            <a href="<%= roleHref(canViewAssets, "assets.jsp") %>" class="legend-row dashboard-action-link"><span class="legend-dot dot-green"></span><span>Operational</span><strong><%= indianNumber(operationalAssets) %> (<%= decimalOne(percent(operationalAssets, totalAssets)) %>%)</strong></a>
                            <a href="<%= roleHref(canViewMaintenance, "maintenance.jsp") %>" class="legend-row dashboard-action-link"><span class="legend-dot dot-orange"></span><span>Under Maintenance</span><strong><%= indianNumber(maintenanceAssets) %> (<%= decimalOne(percent(maintenanceAssets, totalAssets)) %>%)</strong></a>
                            <a href="<%= roleHref(canViewMaintenance, "maintenance.jsp") %>" class="legend-row dashboard-action-link"><span class="legend-dot dot-red"></span><span>Damaged</span><strong><%= indianNumber(damagedAssets) %> (<%= decimalOne(percent(damagedAssets, totalAssets)) %>%)</strong></a>
                            <a href="<%= roleHref(canViewAssets, "assets.jsp") %>" class="legend-row dashboard-action-link"><span class="legend-dot dot-purple"></span><span>Disposed</span><strong><%= indianNumber(disposedAssets) %> (<%= decimalOne(percent(disposedAssets, totalAssets)) %>%)</strong></a>
                            <a href="<%= roleHref(canVerify, "physical_verification.jsp") %>" class="legend-row dashboard-action-link"><span class="legend-dot dot-gray"></span><span>Awaiting Verification</span><strong><%= indianNumber(awaitingVerificationAssets) %> (<%= decimalOne(percent(awaitingVerificationAssets, totalAssets)) %>%)</strong></a>
                        </div>
                    </div>

                    <a href="<%= roleHref(canReport, "reports.jsp") %>" class="panel-link">View Detailed Report <i class="fa-solid fa-arrow-right"></i></a>
                </div>

                <div class="official-panel">
                    <div class="panel-header panel-title-row">
                        <h2 class="panel-title">Pending Action Queue</h2>
                    </div>

                    <div class="queue-list">
                        <a href="<%= roleHref(canVerify, "physical_verification.jsp") %>" class="queue-row dashboard-action-link"><div class="queue-icon"><i class="fa-regular fa-clipboard"></i></div><div class="queue-text"><strong>Verifications Pending</strong></div><strong class="queue-count"><%= indianNumber(verificationsPending) %></strong></a>
                        <a href="<%= roleHref(canVerify, "physical_verification.jsp") %>" class="queue-row dashboard-action-link"><div class="queue-icon"><i class="fa-solid fa-magnifying-glass"></i></div><div class="queue-text"><strong>Inspections Due</strong></div><strong class="queue-count"><%= indianNumber(inspectionsDue) %></strong></a>
                        <a href="<%= roleHref(canViewMaintenance, "maintenance.jsp") %>" class="queue-row dashboard-action-link"><div class="queue-icon"><i class="fa-solid fa-screwdriver-wrench"></i></div><div class="queue-text"><strong>Maintenance Overdue</strong></div><strong class="queue-count"><%= indianNumber(maintenanceOverdue) %></strong></a>
                        <a href="<%= roleHref(canViewWarranty, "warranty_report.jsp") %>" class="queue-row dashboard-action-link"><div class="queue-icon"><i class="fa-regular fa-calendar-xmark"></i></div><div class="queue-text"><strong>Warranty Expiring</strong></div><strong class="queue-count"><%= indianNumber(warrantyExpiring) %></strong></a>
                        <a href="<%= roleHref(canApproveRequests, "asset_requests.jsp") %>" class="queue-row dashboard-action-link"><div class="queue-icon"><i class="fa-regular fa-circle-check"></i></div><div class="queue-text"><strong>Approvals Pending</strong></div><strong class="queue-count"><%= indianNumber(approvalsPending) %></strong></a>
                        <a href="<%= roleHref(canApproveRequests, "asset_requests.jsp") %>" class="queue-row dashboard-action-link"><div class="queue-icon"><i class="fa-solid fa-boxes-packing"></i></div><div class="queue-text"><strong>Requests Approved</strong></div><strong class="queue-count"><%= indianNumber(procurementPending) %></strong></a>
                    </div>
                </div>

                <div class="official-panel">
                    <div class="panel-header panel-title-row">
                        <h2 class="panel-title">Physical Verification Status</h2>
                    </div>

                    <div class="donut-wrap donut-layout">
                        <div class="donut donut-chart">
                            <svg class="donut-svg" viewBox="0 0 120 120">
                                <%= verificationDonutSegments(pvVerified, pvUnderProcess, pvPending, Math.max(totalAssets, pvTotal)) %>
                            </svg>
                            <div class="donut-center">
                                <strong><%= decimalOne(pvVerifiedPercent) %>%</strong>
                                <span>Verified</span>
                            </div>
                        </div>

                        <div class="legend legend-list">
                            <a href="<%= roleHref(canVerify, "physical_verification.jsp") %>" class="legend-row dashboard-action-link"><span class="legend-dot dot-green"></span><span>Verified</span><strong><%= indianNumber(pvVerified) %></strong></a>
                            <a href="<%= roleHref(canVerify, "physical_verification.jsp") %>" class="legend-row dashboard-action-link"><span class="legend-dot dot-orange"></span><span>Under Process</span><strong><%= indianNumber(pvUnderProcess) %></strong></a>
                            <a href="<%= roleHref(canVerify, "physical_verification.jsp") %>" class="legend-row dashboard-action-link"><span class="legend-dot dot-red"></span><span>Pending</span><strong><%= indianNumber(pvPending) %></strong></a>
                        </div>
                    </div>

                    <a href="<%= roleHref(canVerify, "physical_verification.jsp") %>" class="panel-link">Go to Verification Dashboard <i class="fa-solid fa-arrow-right"></i></a>
                </div>

                <div class="official-panel">
                    <div class="panel-header panel-title-row">
                        <h2 class="panel-title">Recent Activities</h2>
                        <% if (canViewAudit) { %>
                            <a href="audit_logs.jsp" class="panel-link">View All</a>
                        <% } %>
                    </div>

                    <div class="activity-list">
                        <%
                            if (!canViewAudit) {
                        %>
                            <div class="activity-row">
                                <div class="activity-icon"><i class="fa-solid fa-lock"></i></div>
                                <div class="activity-text activity-body">
                                    <strong>Activity access restricted</strong>
                                    <span>Audit trail is visible to authorized audit roles.</span>
                                </div>
                                <div class="activity-user"><%= safeText(cleanLabel(role)) %></div>
                            </div>
                        <%
                            } else if (recentActivities == null || recentActivities.isEmpty()) {
                        %>
                            <div class="activity-row">
                                <div class="activity-icon"><i class="fa-solid fa-info"></i></div>
                                <div class="activity-text activity-body">
                                    <strong>No recent activity found</strong>
                                    <span>Audit log is empty</span>
                                </div>
                                <div class="activity-user">System</div>
                            </div>
                        <%
                            } else {
                                for (RecentActivity activity : recentActivities) {
                                    String action = activity.getAction() == null ? "ACTIVITY" : activity.getAction().toUpperCase(Locale.ENGLISH);
                                    String iconClass = "fa-circle-info";
                                    String iconColor = "";

                                    if (action.contains("ADD") || action.contains("CREATE") || action.contains("INSERT")) {
                                        iconClass = "fa-plus";
                                        iconColor = "green";
                                    } else if (action.contains("DELETE") || action.contains("DISPOSE")) {
                                        iconClass = "fa-trash";
                                        iconColor = "red";
                                    } else if (action.contains("UPDATE") || action.contains("EDIT")) {
                                        iconClass = "fa-pen";
                                        iconColor = "orange";
                                    } else if (action.contains("LOGIN") || action.contains("VERIFY")) {
                                        iconClass = "fa-shield-halved";
                                        iconColor = "purple";
                                    }
                        %>
                            <a class="activity-row dashboard-action-link" href="<%= roleHref(canViewAudit, "audit_logs.jsp") %>" title="<%= roleTitle(canViewAudit, "Open audit trail") %>">
                                <div class="activity-icon <%= iconColor %>"><i class="fa-solid <%= iconClass %>"></i></div>

                                <div class="activity-text activity-body">
                                    <strong><%= safeText(shortText(activity.getRemarks(), 52)) %></strong>
                                    <span><%= safeText(cleanLabel(activity.getTableName())) %> · <%= safeText(activity.getActionTime()) %><%
                                        String activityIp = activity.getIpAddress();
                                        if (activityIp != null && !activityIp.trim().isEmpty()) {
                                    %> · IP: <%= safeText(activityIp) %><% } %></span>
                                </div>

                                <div class="activity-user"><%= safeText(cleanLabel(action)) %></div>
                            </a>
                        <%
                                }
                            }
                        %>
                    </div>
                </div>
            </section>

            <section class="dashboard-grid-secondary">
                <div class="official-panel dashboard-data-panel">
                    <div class="panel-header panel-title-row">
                        <h2 class="panel-title">Department Wise Asset Distribution</h2>
                    </div>

                    <div class="bar-list department-bar-list">
                        <%
                            if (departmentRows == null || departmentRows.isEmpty()) {
                        %>
                            <div class="dashboard-empty-state">
                                <i class="fa-solid fa-building-columns"></i>
                                <strong>No department asset data found</strong>
                                <span>Add department/category against assets to view this summary.</span>
                            </div>
                        <%
                            } else {
                                long maxDepartmentCount = 1;

                                for (Map<String, String> row : departmentRows) {
                                    long count = rowLong(row, "total_assets");
                                    if (count > maxDepartmentCount) {
                                        maxDepartmentCount = count;
                                    }
                                }

                                for (Map<String, String> row : departmentRows) {
                                    long count = rowLong(row, "total_assets");
                                    double width = Math.max(8, Math.min((count * 100.0) / Math.max(maxDepartmentCount, 1), 100));
                                    double share = percent(count, Math.max(totalAssets, 1));
                        %>
                            <a href="<%= roleHref(canReport, "reports.jsp") %>"
                               class="bar-row dashboard-action-link"
                               title="<%= roleTitle(canReport, "Open department asset report") %>">
                                <span class="bar-label"><%= safeText(shortText(rowValue(row, "department_name"), 18)) %></span>
                                <span class="bar-track">
                                    <span class="bar-fill" style="width:<%= decimalOne(width) %>%"></span>
                                </span>
                                <span class="bar-value"><%= indianNumber(count) %> (<%= decimalOne(share) %>%)</span>
                            </a>
                        <%
                                }
                            }
                        %>
                    </div>

                    <a href="<%= roleHref(canReport, "reports.jsp") %>" class="panel-link">View Full Report <i class="fa-solid fa-arrow-right"></i></a>
                </div>

                <div class="official-panel dashboard-data-panel">
                    <div class="panel-header panel-title-row">
                        <h2 class="panel-title">Section Wise Asset Summary</h2>
                    </div>

                    <div class="section-table-wrap">
                        <table class="section-table">
                            <thead>
                                <tr>
                                    <th>Section / Location</th>
                                    <th>Total Assets</th>
                                    <th>In Service (%)</th>
                                </tr>
                            </thead>

                            <tbody>
                                <%
                                    if (sectionRows == null || sectionRows.isEmpty()) {
                                %>
                                    <tr>
                                        <td colspan="3">
                                            <div class="dashboard-empty-state table-empty">
                                                <i class="fa-solid fa-location-dot"></i>
                                                <strong>No section/location data found</strong>
                                                <span>Add location against assets to view this summary.</span>
                                            </div>
                                        </td>
                                    </tr>
                                <%
                                    } else {
                                        for (Map<String, String> row : sectionRows) {
                                            long total = rowLong(row, "total_assets");
                                            long inService = rowLong(row, "in_service");
                                            double inServicePercent = percent(inService, Math.max(total, 1));
                                %>
                                    <tr>
                                        <td><%= safeText(shortText(rowValue(row, "section_name"), 24)) %></td>
                                        <td><%= indianNumber(total) %></td>
                                        <td class="green-text"><%= decimalOne(inServicePercent) %>%</td>
                                    </tr>
                                <%
                                        }
                                    }
                                %>
                            </tbody>
                        </table>
                    </div>

                    <a href="<%= roleHref(canReport, "reports.jsp") %>" class="panel-link">View All Sections <i class="fa-solid fa-arrow-right"></i></a>
                </div>

                <div class="official-panel">
                    <div class="panel-header panel-title-row">
                        <h2 class="panel-title">Warranty &amp; Maintenance Alerts</h2>
                    </div>

                    <div class="queue-list">
                        <a href="<%= roleHref(canViewWarranty, "warranty_report.jsp") %>" class="queue-row dashboard-action-link"><div class="queue-icon"><i class="fa-solid fa-triangle-exclamation"></i></div><div class="queue-text"><strong>Warranty Expiring in next 30 days</strong></div><strong class="queue-count"><%= indianNumber(warrantyExpiring) %></strong></a>
                        <a href="<%= roleHref(canViewMaintenance, "maintenance.jsp") %>" class="queue-row dashboard-action-link"><div class="queue-icon"><i class="fa-solid fa-triangle-exclamation"></i></div><div class="queue-text"><strong>Maintenance Attention Due</strong></div><strong class="queue-count"><%= indianNumber(maintenanceOverdue) %></strong></a>
                        <a href="<%= roleHref(canViewMaintenance, "maintenance.jsp") %>" class="queue-row dashboard-action-link"><div class="queue-icon"><i class="fa-solid fa-triangle-exclamation"></i></div><div class="queue-text"><strong>Open Maintenance Logs</strong></div><strong class="queue-count"><%= indianNumber(totalMaintenanceLogs) %></strong></a>
                        <a href="<%= roleHref(canViewAssets, "assets.jsp") %>" class="queue-row dashboard-action-link"><div class="queue-icon"><i class="fa-solid fa-check"></i></div><div class="queue-text"><strong>Serviceable Assets</strong></div><strong class="queue-count green"><%= indianNumber(operationalAssets) %></strong></a>
                    </div>

                    <a href="<%= roleHref(canViewWarranty, "warranty_report.jsp") %>" class="panel-link">View All Alerts <i class="fa-solid fa-arrow-right"></i></a>
                </div>

                <div class="official-panel">
                    <div class="panel-header panel-title-row">
                        <h2 class="panel-title">Quick Shortcuts</h2>
                    </div>

                    <div class="quick-grid">
                        <% if (canViewAssets) { %>
                            <a href="assets.jsp" class="quick-tile"><i class="fa-solid fa-cubes"></i><span>Assets</span></a>
                        <% } %>

                        <% if (canViewAllocation) { %>
                            <a href="allocation.jsp" class="quick-tile"><i class="fa-solid fa-arrow-right-arrow-left"></i><span>Allocation</span></a>
                        <% } %>

                        <% if (canViewMaintenance) { %>
                            <a href="maintenance.jsp" class="quick-tile"><i class="fa-solid fa-screwdriver-wrench"></i><span>Maintenance</span></a>
                        <% } %>

                        <% if (canVerify) { %>
                            <a href="physical_verification.jsp" class="quick-tile"><i class="fa-solid fa-shield-halved"></i><span>Verification</span></a>
                        <% } %>

                        <% if (canReport) { %>
                            <a href="reports.jsp" class="quick-tile"><i class="fa-regular fa-clipboard"></i><span>Reports</span></a>
                        <% } %>

                        <% if (canViewQr) { %>
                            <a href="qr_control_center.jsp" class="quick-tile"><i class="fa-solid fa-qrcode"></i><span>QR Center</span></a>
                            <a href="qr_asset_register.jsp" class="quick-tile"><i class="fa-solid fa-table-list"></i><span>QR Register</span></a>
                            <a href="qr_scan_logs.jsp" class="quick-tile"><i class="fa-solid fa-list-check"></i><span>QR Logs</span></a>
                        <% } %>

                        <% if (canViewAudit) { %>
                            <a href="audit_logs.jsp" class="quick-tile"><i class="fa-regular fa-calendar-check"></i><span>Audit Trail</span></a>
                        <% } %>

                        <% if (canCreateRequest) { %>
                            <a href="add_request.jsp" class="quick-tile"><i class="fa-regular fa-square-plus"></i><span>Create Request</span></a>
                        <% } %>
                    </div>
                </div>

                <div class="official-panel">
                    <div class="panel-header panel-title-row">
                        <h2 class="panel-title">Recently Added Assets</h2>
                        <a href="<%= roleHref(canViewAssets, "assets.jsp") %>" class="panel-link">View All</a>
                    </div>

                    <div class="asset-list">
                        <%
                            if (recentAssetRows == null || recentAssetRows.isEmpty()) {
                        %>
                            <div class="dashboard-empty-state">
                                <i class="fa-solid fa-box-open"></i>
                                <strong>No recent assets found</strong>
                                <span>Newly registered assets will appear here.</span>
                            </div>
                        <%
                            } else {
                                for (Map<String, String> row : recentAssetRows) {
                        %>
                            <a class="asset-row dashboard-action-link"
                               href="<%= roleHref(canViewAssets, assetDetailsHref(rowValue(row, "asset_id"), "assets.jsp")) %>"
                               title="<%= roleTitle(canViewAssets, "Open asset details") %>">
                                <div class="asset-icon"><i class="fa-solid fa-train-subway"></i></div>

                                <div class="asset-text">
                                    <strong><%= safeText(shortText(rowValue(row, "asset_name"), 28)) %></strong>
                                    <span><%= safeText(cleanLabel(rowValue(row, "asset_status"))) %> · <%= safeText(rowValue(row, "asset_code")) %></span>
                                </div>

                                <div class="asset-date"><%= safeText(rowValue(row, "added_on")) %></div>
                            </a>
                        <%
                                }
                            }
                        %>
                    </div>
                </div>

                <% if (canVerify) { %>
                    <div class="official-panel recent-verification-panel">
                        <div class="panel-header panel-title-row">
                            <h2 class="panel-title">Recent Physical Verification</h2>
                            <a href="<%= roleHref(canVerify, "physical_verification.jsp") %>" class="panel-link">Open Register</a>
                        </div>

                        <div class="activity-list">
                            <%
                                if (verificationRows == null || verificationRows.isEmpty()) {
                            %>
                                <div class="dashboard-empty-state">
                                    <i class="fa-solid fa-shield-halved"></i>
                                    <strong>No recent verification found</strong>
                                    <span>Physical verification records will appear here.</span>
                                </div>
                            <%
                                } else {
                                    for (Map<String, String> row : verificationRows) {
                            %>
                                <a class="activity-row dashboard-action-link"
                                   href="<%= roleHref(canViewAssets, assetDetailsHref(rowValue(row, "asset_id"), "physical_verification.jsp")) %>"
                                   title="<%= roleTitle(canViewAssets, "Open verified asset details") %>">
                                    <div class="activity-icon green"><i class="fa-solid fa-shield-halved"></i></div>

                                    <div class="activity-text activity-body">
                                        <strong><%= safeText(rowValue(row, "asset_code")) %> - <%= safeText(shortText(rowValue(row, "asset_name"), 50)) %></strong>
                                        <span><%= safeText(cleanLabel(rowValue(row, "verified_status"))) %> · <%= safeText(rowValue(row, "verified_on")) %></span>
                                    </div>

                                    <div class="activity-user"><%= safeText(rowValue(row, "verified_by")) %></div>
                                </a>
                            <%
                                    }
                                }
                            %>
                        </div>
                    </div>
                <% } %>
            </section>

            <section class="dashboard-footer-strip">
                <div class="footer-motto">
                    <div class="footer-shield"><i class="fa-solid fa-shield-halved"></i></div>

                    <div>
                        <strong>Ensure Accuracy. Ensure Accountability.</strong>
                        <span>Official Railway Asset Governance</span>
                    </div>
                </div>

                <a href="<%= roleHref(canRequest, requestDashboardHref) %>" class="process-step dashboard-action-link" title="<%= roleTitle(canRequest, "Open planning and requests") %>">
                    <i class="fa-regular fa-calendar-days"></i>
                    <div>
                        <strong>Plan</strong>
                        <span>Schedule &amp; Prepare</span>
                    </div>
                </a>

                <a href="<%= roleHref(canVerify, "physical_verification.jsp") %>" class="process-step dashboard-action-link" title="<%= roleTitle(canVerify, "Open physical verification") %>">
                    <i class="fa-regular fa-circle-check"></i>
                    <div>
                        <strong>Verify</strong>
                        <span>Check Physical Stock</span>
                    </div>
                </a>

                <a href="<%= roleHref(canViewAudit, "audit_logs.jsp") %>" class="process-step dashboard-action-link" title="<%= roleTitle(canViewAudit, "Open audit validation") %>">
                    <i class="fa-regular fa-file-lines"></i>
                    <div>
                        <strong>Validate</strong>
                        <span>Reconcile Records</span>
                    </div>
                </a>

                <a href="<%= roleHref(canReport, "reports.jsp") %>" class="process-step dashboard-action-link" title="<%= roleTitle(canReport, "Open reports") %>">
                    <i class="fa-solid fa-chart-simple"></i>
                    <div>
                        <strong>Report</strong>
                        <span>MIS &amp; Compliance</span>
                    </div>
                </a>

                <div class="footer-wave-area"></div>

                <div class="footer-copy">
                    © 2026 East Coast Railway · Asset Management System
                </div>

                <div class="footer-emblem">
                    <i class="fa-solid fa-building-columns"></i>
                </div>
            </section>
        </div>
    </main>
</div>

<script src="js/topbar-search.js?v=6000000"></script>
<script src="js/user-dropdown.js?v=dashboard-freeze-role-1"></script>
<script src="js/sidebar-role.js?v=dashboard-freeze-role-1"></script>
<script src="js/ir-body-watermark.js?v=dashboard-watermark-fix"></script>
<script src="js/dashboard-actions.js?v=dashboard-freeze-role-1"></script>
<script src="js/donut-tooltip.js?v=1"></script>
</body>
</html>
