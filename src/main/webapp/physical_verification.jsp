<%@page contentType="text/html" pageEncoding="UTF-8"%>
<%@page import="com.mycompany.asset_management_system_ams.DBConnection"%>
<%@page import="java.sql.*"%>
<%@page import="java.util.*"%>

<%!
    private String safe(Object value) {
        if (value == null) {
            return "";
        }

        return String.valueOf(value).trim()
                .replace("&", "&amp;")
                .replace("<", "&lt;")
                .replace(">", "&gt;")
                .replace("\"", "&quot;")
                .replace("'", "&#39;");
    }

    private String display(Object value) {
        if (value == null || String.valueOf(value).trim().isEmpty()) {
            return "N/A";
        }

        return safe(value);
    }

    public String formatNumber(int number) {
        if (number >= 100000) {
            return String.format("%.2fL", number / 100000.0);
        }
        if (number >= 1000) {
            return String.format("%.1fK", number / 1000.0);
        }
        return String.valueOf(number);
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
                out.append(Character.toUpperCase(part.charAt(0)))
                        .append(part.substring(1))
                        .append(" ");
            }
        }

        return out.toString().trim();
    }

    private String shortText(String value, int max) {
        if (value == null || value.trim().isEmpty()) {
            return "N/A";
        }

        String text = value.trim();

        if (text.length() <= max) {
            return text;
        }

        return text.substring(0, max) + "...";
    }

    private boolean tableExists(Connection con, String tableName) {
        String sql = "SELECT COUNT(*) FROM information_schema.tables "
                + "WHERE table_schema = DATABASE() AND table_name = ?";

        try (PreparedStatement ps = con.prepareStatement(sql)) {
            ps.setString(1, tableName);

            try (ResultSet rs = ps.executeQuery()) {
                return rs.next() && rs.getInt(1) > 0;
            }

        } catch (Exception e) {
            e.printStackTrace();
        }

        return false;
    }

    private boolean columnExists(Connection con, String tableName, String columnName) {
        String sql = "SELECT COUNT(*) FROM information_schema.columns "
                + "WHERE table_schema = DATABASE() "
                + "AND table_name = ? "
                + "AND column_name = ?";

        try (PreparedStatement ps = con.prepareStatement(sql)) {
            ps.setString(1, tableName);
            ps.setString(2, columnName);

            try (ResultSet rs = ps.executeQuery()) {
                return rs.next() && rs.getInt(1) > 0;
            }

        } catch (Exception e) {
            e.printStackTrace();
        }

        return false;
    }

    private String rowValue(Map<String, String> row, String key) {
        if (row == null) {
            return "";
        }

        String value = row.get(key);
        return value == null ? "" : value;
    }

    private String badgeClass(String status) {
        if (status == null) {
            return "neutral";
        }

        String s = status.trim().toUpperCase(Locale.ENGLISH);

        if ("VERIFIED".equals(s) || "APPROVED".equals(s) || "COMPLETED".equals(s)) {
            return "success";
        }

        if ("LOCATION_MISMATCH".equals(s)
                || "EMPLOYEE_MISMATCH".equals(s)
                || "NEEDS_REVIEW".equals(s)
                || "SCHEDULED".equals(s)
                || "IN_PROGRESS".equals(s)
                || "SUBMITTED".equals(s)) {
            return "warning";
        }

        if ("NOT_FOUND".equals(s)
                || "DAMAGED".equals(s)
                || "UNDER_REPAIR".equals(s)
                || "REJECTED".equals(s)
                || "CANCELLED".equals(s)) {
            return "danger";
        }

        return "neutral";
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

    boolean canManageVerification = ("SUPER_ADMIN".equals(role) || "ADMIN".equals(role))
            || "ASSET_MANAGER".equalsIgnoreCase(role);

    boolean canViewVerification = canManageVerification
            || "DEPARTMENT_HEAD".equalsIgnoreCase(role)
            || "AUDITOR".equalsIgnoreCase(role);

    if (!canViewVerification) {
        response.sendRedirect("dashboard.jsp?error=accessDenied");
        return;
    }

    // Matches ExportPhysicalVerificationReportServlet's own canExport(role) gate
    // (and its RoleAccessUtil entry, reportExportOps) exactly: SUPER_ADMIN/ADMIN/
    // ASSET_MANAGER/AUDITOR. DEPARTMENT_HEAD can view this page but was seeing an
    // Export button that always redirected to reports.jsp?access=denied - a
    // dead-end button rather than a security hole, but still worth hiding rather
    // than showing an action that can never succeed.
    boolean canExportVerification = canManageVerification || "AUDITOR".equalsIgnoreCase(role);

    String success = request.getParameter("success");
    String error = request.getParameter("error");
    String warning = request.getParameter("warning");

    String todayDate = java.time.LocalDate.now().toString();
    String userInitial = username.substring(0, Math.min(2, username.length())).toUpperCase(Locale.ENGLISH);

    int totalAssets = 0;
    int verifiedCount = 0;
    int mismatchCount = 0;
    int notFoundCount = 0;
    int reviewCount = 0;
    int activeDutyCount = 0;
    int recentCount = 0;

    List<Map<String, String>> assetList = new ArrayList<Map<String, String>>();
    List<Map<String, String>> employeeList = new ArrayList<Map<String, String>>();
    List<Map<String, String>> locationList = new ArrayList<Map<String, String>>();
    List<Map<String, String>> dutyList = new ArrayList<Map<String, String>>();
    List<Map<String, String>> recentVerificationList = new ArrayList<Map<String, String>>();

    // Fault: previously declared inside the try(con) block below, alongside the
    // query logic that populates them. That try block closes well before the
    // template reaches the QR-prefill <select> around line 630, so Jasper could
    // not resolve either variable there ("cannot be resolved to a variable") -
    // this page 500'd on every single visit. Fix: declare both at this outer
    // scope (shared with totalAssets, todayDate, etc. above) so they stay in
    // scope for the rest of the generated _jspService method; only the
    // DB-dependent assignment logic remains inside the try block.
    String qrAssetIdParam = request.getParameter("assetId");
    String qrAssetText = null;

    try (Connection con = DBConnection.getConnection()) {

        boolean hasRailwayLocations = tableExists(con, "railway_locations");
        boolean hasRailwaySections = tableExists(con, "railway_sections");
        boolean hasDepartments = tableExists(con, "departments");
        boolean hasEmployees = tableExists(con, "employees");
        boolean hasAssetPhysicalVerification = tableExists(con, "asset_physical_verification");
        boolean hasRounds = tableExists(con, "physical_verification_rounds");
        boolean hasDuties = tableExists(con, "physical_verification_duties");

        boolean hasAssetRailwayNo = columnExists(con, "assets", "railway_asset_no");
        boolean hasAssetServiceStatus = columnExists(con, "assets", "service_status");
        boolean hasAssetRailwayLocationId = columnExists(con, "assets", "railway_location_id");
        boolean hasAssetLocationId = columnExists(con, "assets", "location_id");
        boolean hasAssetLocationText = columnExists(con, "assets", "location");
        boolean hasAssetSectionId = columnExists(con, "assets", "section_id");

        boolean hasEmployeeFullName = hasEmployees && columnExists(con, "employees", "full_name");
        boolean hasEmployeeStatus = hasEmployees && columnExists(con, "employees", "status");
        boolean hasEmployeeCode = hasEmployees && columnExists(con, "employees", "employee_code");
        boolean hasEmployeeDesignation = hasEmployees && columnExists(con, "employees", "designation");
        boolean hasEmployeeDepartment = hasEmployees && columnExists(con, "employees", "department_id");

        boolean hasLocationCode = hasRailwayLocations && columnExists(con, "railway_locations", "location_code");
        boolean hasLocationOffice = hasRailwayLocations && columnExists(con, "railway_locations", "office_name");
        boolean hasLocationName = hasRailwayLocations && columnExists(con, "railway_locations", "location_name");

        boolean hasReviewStatus = hasAssetPhysicalVerification && columnExists(con, "asset_physical_verification", "review_status");
        boolean hasVerifiedOn = hasAssetPhysicalVerification && columnExists(con, "asset_physical_verification", "verified_on");
        boolean hasRemarks = hasAssetPhysicalVerification && columnExists(con, "asset_physical_verification", "remarks");

        try (PreparedStatement ps = con.prepareStatement("SELECT COUNT(*) AS total FROM assets");
             ResultSet rs = ps.executeQuery()) {
            if (rs.next()) {
                totalAssets = rs.getInt("total");
            }
        }

        if (hasAssetPhysicalVerification) {
            String countSql = "SELECT "
                    + "SUM(CASE WHEN verified_status = 'VERIFIED' THEN 1 ELSE 0 END) AS verified_count, "
                    + "SUM(CASE WHEN verified_status IN ('LOCATION_MISMATCH','EMPLOYEE_MISMATCH') THEN 1 ELSE 0 END) AS mismatch_count, "
                    + "SUM(CASE WHEN verified_status = 'NOT_FOUND' THEN 1 ELSE 0 END) AS not_found_count, "
                    + "SUM(CASE WHEN verified_status IN ('DAMAGED','UNDER_REPAIR','NEEDS_REVIEW') THEN 1 ELSE 0 END) AS review_count, "
                    + "COUNT(*) AS recent_count "
                    + "FROM asset_physical_verification";

            try (PreparedStatement ps = con.prepareStatement(countSql);
                 ResultSet rs = ps.executeQuery()) {

                if (rs.next()) {
                    verifiedCount = rs.getInt("verified_count");
                    mismatchCount = rs.getInt("mismatch_count");
                    notFoundCount = rs.getInt("not_found_count");
                    reviewCount = rs.getInt("review_count");
                    recentCount = rs.getInt("recent_count");
                }
            }
        }

        if (hasDuties) {
            String dutyCountSql = "SELECT COUNT(*) AS total "
                    + "FROM physical_verification_duties "
                    + "WHERE duty_status IN ('SCHEDULED','IN_PROGRESS','SUBMITTED')";

            try (PreparedStatement ps = con.prepareStatement(dutyCountSql);
                 ResultSet rs = ps.executeQuery()) {

                if (rs.next()) {
                    activeDutyCount = rs.getInt("total");
                }
            }
        }

        String assetLocationTextExpression = hasAssetLocationText ? "COALESCE(a.location, '')" : "''";
        String locationJoin = "";
        String locationNameExpression = assetLocationTextExpression;

        if (hasRailwayLocations && hasLocationName && hasAssetRailwayLocationId) {
            locationJoin = "LEFT JOIN railway_locations rl ON a.railway_location_id = rl.location_id ";
            locationNameExpression = "COALESCE(rl.location_name, " + assetLocationTextExpression + ")";
        } else if (hasRailwayLocations && hasLocationName && hasAssetLocationId) {
            locationJoin = "LEFT JOIN railway_locations rl ON a.location_id = rl.location_id ";
            locationNameExpression = "COALESCE(rl.location_name, " + assetLocationTextExpression + ")";
        }

        String sectionJoin = "";
        String sectionNameExpression = "''";

        if (hasRailwaySections && hasAssetSectionId && columnExists(con, "railway_sections", "section_name")) {
            sectionJoin = "LEFT JOIN railway_sections rs ON a.section_id = rs.section_id ";
            sectionNameExpression = "COALESCE(rs.section_name, '')";
        }

        String assetRailwayNoExpression = hasAssetRailwayNo ? "COALESCE(a.railway_asset_no, '')" : "''";
        String serviceStatusExpression = hasAssetServiceStatus ? "COALESCE(a.service_status, '')" : "''";

        if (qrAssetIdParam != null && !qrAssetIdParam.trim().isEmpty()) {
            String assetSql = "SELECT a.asset_id, "
                    + "COALESCE(a.asset_code, '') AS asset_code, "
                    + "COALESCE(a.asset_name, '') AS asset_name, "
                    + "COALESCE(ac.category_name, 'Uncategorized') AS category_name, "
                    + locationNameExpression + " AS location_name "
                    + "FROM assets a "
                    + "LEFT JOIN asset_categories ac ON a.category_id = ac.category_id "
                    + locationJoin
                    + "WHERE a.asset_id = ?";

            try (PreparedStatement ps = con.prepareStatement(assetSql)) {
                ps.setInt(1, Integer.parseInt(qrAssetIdParam));
                try (ResultSet rs = ps.executeQuery()) {
                    if (rs.next()) {
                        String code = safe(rs.getObject("asset_code"));
                        String name = safe(rs.getObject("asset_name"));
                        String cat = safe(rs.getObject("category_name"));
                        String loc = safe(rs.getObject("location_name"));
                        qrAssetText = code + " - " + name + " | " + cat + " | " + loc;
                    } else {
                        qrAssetIdParam = null;
                    }
                }
            } catch (Exception e) {
                e.printStackTrace();
                qrAssetIdParam = null;
            }
        }

        if (hasEmployees) {
            String employeeNameExpression = hasEmployeeFullName
                    ? "COALESCE(e.full_name, '')"
                    : "COALESCE(e.employee_name, '')";

            String employeeCodeExpression = hasEmployeeCode ? "COALESCE(e.employee_code, '')" : "''";
            String designationExpression = hasEmployeeDesignation ? "COALESCE(e.designation, '')" : "''";
            String departmentJoin = "";
            String departmentExpression = "''";

            if (hasDepartments && hasEmployeeDepartment) {
                departmentJoin = "LEFT JOIN departments d ON e.department_id = d.department_id ";
                departmentExpression = "COALESCE(d.department_name, '')";
            }

            String employeeWhere = hasEmployeeStatus ? "WHERE e.status = 'ACTIVE' " : "";

            String employeeSql = "SELECT e.employee_id, "
                    + employeeCodeExpression + " AS employee_code, "
                    + employeeNameExpression + " AS employee_name, "
                    + designationExpression + " AS designation, "
                    + (hasEmployeeDepartment ? "COALESCE(e.department_id, 0)" : "0") + " AS department_id, "
                    + departmentExpression + " AS department_name "
                    + "FROM employees e "
                    + departmentJoin
                    + employeeWhere
                    + "ORDER BY employee_name ASC";

            try (PreparedStatement ps = con.prepareStatement(employeeSql);
                 ResultSet rs = ps.executeQuery()) {

                while (rs.next()) {
                    Map<String, String> row = new HashMap<String, String>();

                    row.put("employee_id", safe(rs.getObject("employee_id")));
                    row.put("employee_code", safe(rs.getObject("employee_code")));
                    row.put("employee_name", safe(rs.getObject("employee_name")));
                    row.put("designation", safe(rs.getObject("designation")));
                    row.put("department_id", safe(rs.getObject("department_id")));
                    row.put("department_name", safe(rs.getObject("department_name")));

                    employeeList.add(row);
                }
            }
        }

        if (hasRailwayLocations) {
            String locationCodeExpression = hasLocationCode ? "COALESCE(location_code, '')" : "''";
            String officeNameExpression = hasLocationOffice ? "COALESCE(office_name, '')" : "''";
            String locationNameOnlyExpression = hasLocationName ? "COALESCE(location_name, '')" : "CONCAT('Location ID ', location_id)";

            String locationSql = "SELECT location_id, "
                    + locationCodeExpression + " AS location_code, "
                    + officeNameExpression + " AS office_name, "
                    + locationNameOnlyExpression + " AS location_name "
                    + "FROM railway_locations "
                    + "ORDER BY location_id ASC";

            try (PreparedStatement ps = con.prepareStatement(locationSql);
                 ResultSet rs = ps.executeQuery()) {

                while (rs.next()) {
                    Map<String, String> row = new HashMap<String, String>();

                    row.put("location_id", safe(rs.getObject("location_id")));
                    row.put("location_code", safe(rs.getObject("location_code")));
                    row.put("office_name", safe(rs.getObject("office_name")));
                    row.put("location_name", safe(rs.getObject("location_name")));

                    locationList.add(row);
                }
            }
        }

        if (hasDuties) {
            String dutySql = "SELECT pvd.duty_id, pvd.verification_round_id, "
                    + (hasRounds ? "COALESCE(pvr.round_code, '')" : "''") + " AS round_code, "
                    + "pvd.assigned_employee_id, "
                    + "pvd.assigned_department_id, "
                    + "COALESCE(pvd.duty_status, '') AS duty_status, "
                    + "COALESCE(DATE_FORMAT(pvd.scheduled_from, '%Y-%m-%d'), '') AS scheduled_from, "
                    + "COALESCE(DATE_FORMAT(pvd.scheduled_to, '%Y-%m-%d'), '') AS scheduled_to, "
                    + "COALESCE(pvd.instructions, '') AS instructions, "
                    + (hasEmployees ? (hasEmployeeCode ? "COALESCE(e.employee_code, '')" : "''") : "''") + " AS employee_code, "
                    + (hasEmployees ? (hasEmployeeFullName ? "COALESCE(e.full_name, '')" : "COALESCE(e.employee_name, '')") : "''") + " AS employee_name, "
                    + (hasDepartments ? "COALESCE(d.department_name, '')" : "''") + " AS department_name "
                    + "FROM physical_verification_duties pvd "
                    + (hasRounds ? "LEFT JOIN physical_verification_rounds pvr ON pvd.verification_round_id = pvr.verification_round_id " : "")
                    + (hasEmployees ? "LEFT JOIN employees e ON pvd.assigned_employee_id = e.employee_id " : "")
                    + (hasDepartments ? "LEFT JOIN departments d ON pvd.assigned_department_id = d.department_id " : "")
                    + "ORDER BY pvd.duty_id DESC";

            try (PreparedStatement ps = con.prepareStatement(dutySql);
                 ResultSet rs = ps.executeQuery()) {

                while (rs.next()) {
                    Map<String, String> row = new HashMap<String, String>();

                    row.put("duty_id", safe(rs.getObject("duty_id")));
                    row.put("verification_round_id", safe(rs.getObject("verification_round_id")));
                    row.put("round_code", safe(rs.getObject("round_code")));
                    row.put("assigned_employee_id", safe(rs.getObject("assigned_employee_id")));
                    row.put("assigned_department_id", safe(rs.getObject("assigned_department_id")));
                    row.put("duty_status", safe(rs.getObject("duty_status")));
                    row.put("scheduled_from", safe(rs.getObject("scheduled_from")));
                    row.put("scheduled_to", safe(rs.getObject("scheduled_to")));
                    row.put("instructions", safe(rs.getObject("instructions")));
                    row.put("employee_code", safe(rs.getObject("employee_code")));
                    row.put("employee_name", safe(rs.getObject("employee_name")));
                    row.put("department_name", safe(rs.getObject("department_name")));

                    dutyList.add(row);
                }
            }
        }

        if (hasAssetPhysicalVerification) {
            String recentSql = "SELECT pv.verification_id, pv.asset_id, "
                    + "pv.verified_status, "
                    + (hasReviewStatus ? "COALESCE(pv.review_status, '')" : "''") + " AS review_status, "
                    + (hasVerifiedOn ? "COALESCE(DATE_FORMAT(pv.verified_on, '%d %b %Y, %h:%i %p'), '')" : "''") + " AS verified_on, "
                    + (hasRemarks ? "COALESCE(pv.remarks, '')" : "''") + " AS remarks, "
                    + "COALESCE(a.asset_code, '') AS asset_code, "
                    + "COALESCE(a.asset_name, '') AS asset_name "
                    + "FROM asset_physical_verification pv "
                    + "LEFT JOIN assets a ON pv.asset_id = a.asset_id "
                    + "ORDER BY pv.verification_id DESC "
                    + "LIMIT 30";

            try (PreparedStatement ps = con.prepareStatement(recentSql);
                 ResultSet rs = ps.executeQuery()) {

                while (rs.next()) {
                    Map<String, String> row = new HashMap<String, String>();

                    row.put("verification_id", safe(rs.getObject("verification_id")));
                    row.put("asset_id", safe(rs.getObject("asset_id")));
                    row.put("verified_status", safe(rs.getObject("verified_status")));
                    row.put("review_status", safe(rs.getObject("review_status")));
                    row.put("verified_on", safe(rs.getObject("verified_on")));
                    row.put("remarks", safe(rs.getObject("remarks")));
                    row.put("asset_code", safe(rs.getObject("asset_code")));
                    row.put("asset_name", safe(rs.getObject("asset_name")));

                    recentVerificationList.add(row);
                }
            }
        }

    } catch (Exception e) {
        e.printStackTrace();
        error = "pageLoadFailed";
    }
%>

<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>Physical Verification - IR-AMS</title>

    <link rel="stylesheet"
          href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.0/css/all.min.css">

    <link rel="stylesheet" href="css/ir-glass.css?v=final-reference-1">
    <link rel="stylesheet" href="css/ams-pro.css?v=final-reference-1">
    <link rel="stylesheet" href="css/ir-ams-railway-ui.css?v=final-reference-1">
<link rel="stylesheet" href="css/physical_verification.css?v=topbarfix1">
    <link href="https://cdn.jsdelivr.net/npm/select2@4.1.0-rc.0/dist/css/select2.min.css" rel="stylesheet" />
</head>

<body class="railway-ui">
<div class="app ams-shell">

    
    <jsp:include page="sidebar.jsp" />

    <main class="main railway-main">
        <jsp:include page="topbar.jsp" />

        <div class="main-scroll-content pv-board">

            <% if ("verificationSaved".equals(success)) { %>
                <div class="pv-alert success">
                    <i class="fa-solid fa-circle-check"></i>
                    Physical verification record saved successfully.
                </div>
            <% } else if ("dutyScheduled".equals(success)) { %>
                <div class="pv-alert success">
                    <i class="fa-solid fa-circle-check"></i>
                    Physical verification duty scheduled successfully.
                </div>
            <% } else if ("dutyApproved".equals(success)) { %>
                <div class="pv-alert success">
                    <i class="fa-solid fa-circle-check"></i>
                    Duty approved and marked complete. It is now closed and moved to the officer's duty history.
                </div>
            <% } else if ("dutySentBack".equals(success)) { %>
                <div class="pv-alert success">
                    <i class="fa-solid fa-circle-check"></i>
                    Duty sent back to the officer for revision. It is now in progress again.
                </div>
            <% } %>

            <% if ("dutyAlreadyExists".equals(warning)) { %>
                <div class="pv-alert warning">
                    <i class="fa-solid fa-triangle-exclamation"></i>
                    Active duty already exists for the selected officer in this round.
                </div>
            <% } %>

            <% if (error != null && !error.trim().isEmpty()) { %>
                <div class="pv-alert error">
                    <i class="fa-solid fa-triangle-exclamation"></i>
                    Action failed: <%= display(cleanLabel(error)) %>
                </div>
            <% } %>

            <section class="pv-hero">
                <h1>Physical Verification Control</h1>

                <p>
                    Verify railway assets physically, schedule verification duties, record location/holder mismatch,
                    track damaged/not found assets and maintain audit-ready verification history.
                </p>

                <div class="hero-pills">
                    <div class="hero-pill"><i class="fa-solid fa-shield-halved"></i> Verification Control</div>
                    <div class="hero-pill"><i class="fa-solid fa-user-check"></i> Officer Duty</div>
                    <div class="hero-pill"><i class="fa-solid fa-location-dot"></i> Location Check</div>
                    <div class="hero-pill"><i class="fa-solid fa-file-export"></i> Export Ready</div>
                </div>
            </section>

            <section class="kpi-grid">
                <div class="kpi-card">
                    <div class="kpi-icon"><i class="fa-solid fa-cubes"></i></div>
                    <h3>Total Assets</h3>
                    <p><%= formatNumber(totalAssets) %></p>
                </div>

                <div class="kpi-card">
                    <div class="kpi-icon"><i class="fa-solid fa-circle-check"></i></div>
                    <h3>Verified</h3>
                    <p><%= formatNumber(verifiedCount) %></p>
                </div>

                <div class="kpi-card">
                    <div class="kpi-icon"><i class="fa-solid fa-triangle-exclamation"></i></div>
                    <h3>Mismatch</h3>
                    <p><%= formatNumber(mismatchCount) %></p>
                </div>

                <div class="kpi-card">
                    <div class="kpi-icon"><i class="fa-solid fa-magnifying-glass"></i></div>
                    <h3>Not Found</h3>
                    <p><%= formatNumber(notFoundCount) %></p>
                </div>

                <div class="kpi-card">
                    <div class="kpi-icon"><i class="fa-solid fa-screwdriver-wrench"></i></div>
                    <h3>Review / Repair</h3>
                    <p><%= formatNumber(reviewCount) %></p>
                </div>

                <div class="kpi-card">
                    <div class="kpi-icon"><i class="fa-solid fa-user-clock"></i></div>
                    <h3>Active Duties</h3>
                    <p><%= formatNumber(activeDutyCount) %></p>
                </div>

                <div class="kpi-card">
                    <div class="kpi-icon"><i class="fa-solid fa-database"></i></div>
                    <h3>Total Records</h3>
                    <p><%= formatNumber(recentCount) %></p>
                </div>
            </section>

            <section class="pv-layout">

                <div class="pv-panel">
                    <div class="pv-panel-head">
                        <div>
                            <h2>Submit Physical Verification</h2>
                            <p>Record asset physical status, actual location, actual holder and officer details.</p>
                        </div>

                        <% if (canExportVerification) { %>
                            <a href="ExportPhysicalVerificationReportServlet" class="pv-btn secondary">
                                <i class="fa-solid fa-file-excel"></i>
                                Export
                            </a>
                        <% } %>
                    </div>

                    <% if (canManageVerification) { %>

                        <form action="AddPhysicalVerificationServlet" method="post" id="verificationForm">

                            <div class="pv-form-grid">

                                <div class="pv-field full">
                                    <label><i class="fa-solid fa-cube"></i> Asset</label>

                                    <select name="assetId" id="assetId" required style="width: 100%;">
                                        <% if (qrAssetIdParam != null && qrAssetText != null) { %>
                                            <option value="<%= safe(qrAssetIdParam) %>" selected="selected"><%= display(qrAssetText) %></option>
                                        <% } %>
                                    </select>
                                </div>

                                <div class="pv-field">
                                    <label><i class="fa-solid fa-list-check"></i> Duty</label>

                                    <select name="dutyId" id="dutyId">
                                        <option value="0">No Duty / Direct Verification</option>

                                        <%
                                            for (Map<String, String> duty : dutyList) {
                                                if (!"COMPLETED".equalsIgnoreCase(rowValue(duty, "duty_status"))
                                                        && !"CANCELLED".equalsIgnoreCase(rowValue(duty, "duty_status"))) {
                                        %>
                                            <option value="<%= safe(rowValue(duty, "duty_id")) %>"
                                                    data-round="<%= safe(rowValue(duty, "verification_round_id")) %>"
                                                    data-officer="<%= safe(rowValue(duty, "assigned_employee_id")) %>">
                                                Duty #<%= display(rowValue(duty, "duty_id")) %>
                                                -
                                                <%= display(rowValue(duty, "employee_name")) %>
                                                (<%= display(cleanLabel(rowValue(duty, "duty_status"))) %>)
                                            </option>
                                        <%
                                                }
                                            }
                                        %>
                                    </select>
                                </div>

                                <input type="hidden" name="verificationRoundId" id="verificationRoundId" value="0">

                                <div class="pv-field">
                                    <label><i class="fa-solid fa-user-shield"></i> Verification Officer</label>

                                    <select name="officerEmployeeId" id="officerEmployeeId" required>
                                        <option value="">Select Officer</option>

                                        <%
                                            for (Map<String, String> emp : employeeList) {
                                        %>
                                            <option value="<%= safe(rowValue(emp, "employee_id")) %>">
                                                <%= display(rowValue(emp, "employee_code")) %>
                                                -
                                                <%= display(rowValue(emp, "employee_name")) %>
                                                |
                                                <%= display(rowValue(emp, "department_name")) %>
                                            </option>
                                        <%
                                            }
                                        %>
                                    </select>
                                </div>

                                <div class="pv-field">
                                    <label><i class="fa-solid fa-location-dot"></i> Actual Location</label>

                                    <select name="actualLocationId">
                                        <option value="0">Not Updated / Same as System</option>

                                        <%
                                            for (Map<String, String> loc : locationList) {
                                        %>
                                            <option value="<%= safe(rowValue(loc, "location_id")) %>">
                                                <%= display(rowValue(loc, "location_code")) %>
                                                -
                                                <%= display(rowValue(loc, "office_name")) %>
                                                /
                                                <%= display(rowValue(loc, "location_name")) %>
                                            </option>
                                        <%
                                            }
                                        %>
                                    </select>
                                </div>

                                <div class="pv-field">
                                    <label><i class="fa-solid fa-user"></i> Actual Holder</label>

                                    <select name="actualEmployeeId">
                                        <option value="0">Not Assigned / No Holder</option>

                                        <%
                                            for (Map<String, String> emp : employeeList) {
                                        %>
                                            <option value="<%= safe(rowValue(emp, "employee_id")) %>">
                                                <%= display(rowValue(emp, "employee_code")) %>
                                                -
                                                <%= display(rowValue(emp, "employee_name")) %>
                                            </option>
                                        <%
                                            }
                                        %>
                                    </select>
                                </div>

                                <div class="pv-field">
                                    <label><i class="fa-solid fa-shield-halved"></i> Verification Status</label>

                                    <select name="verifiedStatus" required>
                                        <option value="VERIFIED">VERIFIED - Asset found and correct</option>
                                        <option value="LOCATION_MISMATCH">LOCATION_MISMATCH - Location mismatch</option>
                                        <option value="EMPLOYEE_MISMATCH">EMPLOYEE_MISMATCH - Holder mismatch</option>
                                        <option value="NOT_FOUND">NOT_FOUND - Asset not found</option>
                                        <option value="DAMAGED">DAMAGED - Asset damaged</option>
                                        <option value="UNDER_REPAIR">UNDER_REPAIR - Under repair</option>
                                        <option value="NEEDS_REVIEW">NEEDS_REVIEW - Needs review</option>
                                    </select>
                                </div>

                                <div class="pv-field full">
                                    <label><i class="fa-solid fa-pen"></i> Remarks</label>

                                    <textarea name="remarks"
                                              placeholder="Write physical verification remark, mismatch note, condition details or officer observation..."></textarea>
                                </div>

                            </div>

                            <%-- Fault: this wrapper's opening tag was missing entirely - the
                                 closing </div> below had nothing of its own to match, so the
                                 browser's error-recovery parsing walked UP the stack and closed
                                 the whole .pv-panel early instead (the nearest real <div>
                                 ancestor, with the still-open <form> silently popped along with
                                 it). That, in turn, made the NEXT </div> (intended to close this
                                 .pv-panel) a stray tag too, which closed .main-scroll-content
                                 itself way too early - ejecting "Schedule Officer Duty" and both
                                 history panels below it out of the scrollable container entirely,
                                 so they rendered overlapping the hero/KPI section above instead of
                                 in their own place on the page. Restored to match the identical,
                                 correctly-formed .pv-actions wrapper already used a few dozen
                                 lines below for the "Schedule Duty" button. --%>
                            <div class="pv-actions">
                                <button type="submit" name="action" value="draft" class="pv-btn secondary">
                                    <i class="fa-solid fa-floppy-disk"></i>
                                    Save Draft
                                </button>

                                <button type="submit" name="action" value="submit" class="pv-btn" onclick="return confirm('Submit Final will lock this duty. Proceed?');">
                                    <i class="fa-solid fa-circle-check"></i>
                                    Submit Final
                                </button>

                                <button type="reset" class="pv-btn secondary">
                                    <i class="fa-solid fa-rotate-left"></i>
                                    Reset
                                </button>
                            </div>

                        </form>

                    <% } else { %>

                        <div class="pv-alert warning">
                            <i class="fa-solid fa-circle-info"></i>
                            You can view verification records, but you do not have permission to submit new verification.
                        </div>

                    <% } %>
                </div>

                <div class="pv-panel">
                    <div class="pv-panel-head">
                        <div>
                            <h2>Schedule Officer Duty</h2>
                            <p>Assign physical verification duty to a responsible officer/employee.</p>
                        </div>
                    </div>

                    <% if (canManageVerification) { %>

                        <form action="SchedulePhysicalVerificationDutyServlet" method="post" id="dutyForm">

                            <input type="hidden" name="verificationRoundId" value="0">

                            <div class="pv-form-grid">
                                <div class="pv-field full">
                                    <label><i class="fa-solid fa-user-shield"></i> Officer / Employee</label>

                                    <select name="officerEmployeeId" required>
                                        <option value="">Select Officer</option>

                                        <%
                                            for (Map<String, String> emp : employeeList) {
                                        %>
                                            <option value="<%= safe(rowValue(emp, "employee_id")) %>">
                                                <%= display(rowValue(emp, "employee_code")) %>
                                                -
                                                <%= display(rowValue(emp, "employee_name")) %>
                                                |
                                                <%= display(rowValue(emp, "department_name")) %>
                                            </option>
                                        <%
                                            }
                                        %>
                                    </select>
                                </div>

                                <div class="pv-field">
                                    <label><i class="fa-regular fa-calendar-days"></i> Scheduled From</label>

                                    <div class="date-input-wrap">
                                        <input type="date"
                                               id="scheduledFrom"
                                               name="scheduledFrom"
                                               value="<%= todayDate %>"
                                               min="<%= todayDate %>"
                                               required>

                                        <button type="button"
                                                class="date-picker-btn"
                                                data-date-picker="scheduledFrom"
                                                title="Open calendar">
                                            <i class="fa-regular fa-calendar-days"></i>
                                        </button>
                                    </div>

                                    
                                </div>

                                <div class="pv-field">
                                    <label><i class="fa-regular fa-calendar-check"></i> Scheduled To</label>

                                    <div class="date-input-wrap">
                                        <input type="date"
                                               id="scheduledTo"
                                               name="scheduledTo"
                                               min="<%= todayDate %>"
                                               required>

                                        <button type="button"
                                                class="date-picker-btn"
                                                data-date-picker="scheduledTo"
                                                title="Open calendar">
                                            <i class="fa-regular fa-calendar-check"></i>
                                        </button>
                                    </div>

                                    
                                </div>

                                <div class="pv-field full">
                                    <label><i class="fa-solid fa-clipboard-list"></i> Instructions</label>

                                    <textarea name="instructions"
                                              placeholder="Write duty scope, location/department coverage and reporting instruction.">Verify assigned railway assets physically and report mismatch, damage, missing asset or holder/location change if found.</textarea>
                                </div>
                            </div>

                            <div class="pv-actions">
                                <button type="submit" class="pv-btn">
                                    <i class="fa-solid fa-calendar-check"></i>
                                    Schedule Duty
                                </button>
                            </div>

                        </form>

                    <% } else { %>

                        <div class="pv-alert warning">
                            <i class="fa-solid fa-circle-info"></i>
                            Duty scheduling is available only to Super Admin and Asset Manager.
                        </div>

                    <% } %>
                </div>

            </section>

            <section class="pv-panel">
                <div class="pv-panel-head">
                    <div>
                        <h2>Active / Recent Verification Duties</h2>
                        <p>Scheduled duties and officer assignments for physical verification.</p>
                    </div>
                </div>

                <div class="pv-table-wrap">
                    <table class="pv-table" id="dutyTable">
                        <thead>
                            <tr>
                                <th onclick="sortDutyTable(0)" style="cursor: pointer;" title="Click to sort">Duty <i class="fa-solid fa-sort" style="color: #cbd5e1; margin-left: 4px;"></i></th>
                                <th onclick="sortDutyTable(1)" style="cursor: pointer;" title="Click to sort">Officer <i class="fa-solid fa-sort" style="color: #cbd5e1; margin-left: 4px;"></i></th>
                                <th onclick="sortDutyTable(2)" style="cursor: pointer;" title="Click to sort">Department <i class="fa-solid fa-sort" style="color: #cbd5e1; margin-left: 4px;"></i></th>
                                <th onclick="sortDutyTable(3)" style="cursor: pointer;" title="Click to sort">Round <i class="fa-solid fa-sort" style="color: #cbd5e1; margin-left: 4px;"></i></th>
                                <th onclick="sortDutyTable(4)" style="cursor: pointer;" title="Click to sort">Schedule <i class="fa-solid fa-sort" style="color: #cbd5e1; margin-left: 4px;"></i></th>
                                <th onclick="sortDutyTable(5)" style="cursor: pointer;" title="Click to sort">Status <i class="fa-solid fa-sort" style="color: #cbd5e1; margin-left: 4px;"></i></th>
                                <th onclick="sortDutyTable(6)" style="cursor: pointer;" title="Click to sort">Instructions <i class="fa-solid fa-sort" style="color: #cbd5e1; margin-left: 4px;"></i></th>
                                <th>Action</th>
                            </tr>
                        </thead>

                        <tbody>
                            <% if (dutyList.isEmpty()) { %>
                                <tr>
                                    <td colspan="8">
                                        <strong>No duty scheduled yet.</strong>
                                    </td>
                                </tr>
                            <% } else {
                                for (Map<String, String> duty : dutyList) {
                                    String dutyStatusUpper = rowValue(duty, "duty_status").trim().toUpperCase(Locale.ENGLISH);
                            %>
                                <tr>
                                    <td>Duty #<%= display(rowValue(duty, "duty_id")) %></td>
                                    <td>
                                        <strong><%= display(rowValue(duty, "employee_name")) %></strong>
                                        <br>
                                        <span><%= display(rowValue(duty, "employee_code")) %></span>
                                    </td>
                                    <td><%= display(rowValue(duty, "department_name")) %></td>
                                    <td><%= display(rowValue(duty, "round_code")) %></td>
                                    <td>
                                        <%= display(rowValue(duty, "scheduled_from")) %>
                                        to
                                        <%= display(rowValue(duty, "scheduled_to")) %>
                                    </td>
                                    <td>
                                        <span class="badge <%= badgeClass(rowValue(duty, "duty_status")) %>">
                                            <%= display(cleanLabel(rowValue(duty, "duty_status"))) %>
                                        </span>
                                    </td>
                                    <td><%= display(shortText(rowValue(duty, "instructions"), 80)) %></td>
                                    <td style="white-space: nowrap !important;">
                                        <% if (canManageVerification && "SUBMITTED".equals(dutyStatusUpper)) { %>
                                            <form action="ReviewPhysicalVerificationDutyServlet" method="post" style="display:inline;"
                                                  onsubmit="return confirm('Approve this duty as complete? The officer\'s active duty will close and move to their duty history.');">
                                                <input type="hidden" name="dutyId" value="<%= safe(rowValue(duty, "duty_id")) %>">
                                                <input type="hidden" name="action" value="approve">
                                                <button type="submit" class="mini-link" style="border:none; background:none; cursor:pointer; color:#15803d;" title="Approve">
                                                    <i class="fa-solid fa-check"></i> Approve
                                                </button>
                                            </form>
                                            <form action="ReviewPhysicalVerificationDutyServlet" method="post" style="display:inline; margin-left:8px;"
                                                  onsubmit="return confirm('Send this duty back to the officer? It will reopen as In Progress so they can revise their reports.');">
                                                <input type="hidden" name="dutyId" value="<%= safe(rowValue(duty, "duty_id")) %>">
                                                <input type="hidden" name="action" value="sendback">
                                                <button type="submit" class="mini-link" style="border:none; background:none; cursor:pointer; color:#b91c1c;" title="Send Back">
                                                    <i class="fa-solid fa-rotate-left"></i> Send Back
                                                </button>
                                            </form>
                                        <% } else if ("SUBMITTED".equals(dutyStatusUpper)) { %>
                                            <span class="badge warning">Awaiting Review</span>
                                        <% } else { %>
                                            <span>-</span>
                                        <% } %>
                                    </td>
                                </tr>
                            <%
                                }
                            }
                            %>
                        </tbody>
                    </table>
                </div>
            </section>

            <section class="pv-panel">
                <div class="pv-panel-head">
                    <div>
                        <h2>Recent Physical Verification Records</h2>
                        <p>Latest asset verification records saved in the system.</p>
                    </div>
                </div>

                <div class="pv-table-wrap">
                    <table class="pv-table" id="recordTable">
                        <thead>
                            <tr>
                                <th onclick="sortRecordTable(0)" style="cursor: pointer;" title="Click to sort">Verification <i class="fa-solid fa-sort" style="color: #cbd5e1; margin-left: 4px;"></i></th>
                                <th onclick="sortRecordTable(1)" style="cursor: pointer;" title="Click to sort">Asset <i class="fa-solid fa-sort" style="color: #cbd5e1; margin-left: 4px;"></i></th>
                                <th onclick="sortRecordTable(2)" style="cursor: pointer;" title="Click to sort">Status <i class="fa-solid fa-sort" style="color: #cbd5e1; margin-left: 4px;"></i></th>
                                <th onclick="sortRecordTable(3)" style="cursor: pointer;" title="Click to sort">Review <i class="fa-solid fa-sort" style="color: #cbd5e1; margin-left: 4px;"></i></th>
                                <th onclick="sortRecordTable(4)" style="cursor: pointer;" title="Click to sort">Verified On <i class="fa-solid fa-sort" style="color: #cbd5e1; margin-left: 4px;"></i></th>
                                <th onclick="sortRecordTable(5)" style="cursor: pointer;" title="Click to sort">Remarks <i class="fa-solid fa-sort" style="color: #cbd5e1; margin-left: 4px;"></i></th>
                                <th onclick="sortRecordTable(6)" style="cursor: pointer;" title="Click to sort">Action <i class="fa-solid fa-sort" style="color: #cbd5e1; margin-left: 4px;"></i></th>
                            </tr>
                        </thead>

                        <tbody>
                            <% if (recentVerificationList.isEmpty()) { %>
                                <tr>
                                    <td colspan="7">
                                        <strong>No verification record found.</strong>
                                    </td>
                                </tr>
                            <% } else {
                                for (Map<String, String> row : recentVerificationList) {
                            %>
                                <tr>
                                    <td>PV-<%= display(rowValue(row, "verification_id")) %></td>
                                    <td>
                                        <strong><%= display(rowValue(row, "asset_code")) %></strong>
                                        <br>
                                        <span><%= display(rowValue(row, "asset_name")) %></span>
                                    </td>
                                    <td>
                                        <span class="badge <%= badgeClass(rowValue(row, "verified_status")) %>">
                                            <%= display(cleanLabel(rowValue(row, "verified_status"))) %>
                                        </span>
                                    </td>
                                    <td><%= display(cleanLabel(rowValue(row, "review_status"))) %></td>
                                    <td><%= display(rowValue(row, "verified_on")) %></td>
                                    <td><%= display(shortText(rowValue(row, "remarks"), 80)) %></td>
                                    <td>
                                        <a href="view_verification.jsp?id=<%= safe(rowValue(row, "verification_id")) %>"
                                           class="mini-link">
                                            <i class="fa-solid fa-eye"></i>
                                            View
                                        </a>
                                    </td>
                                </tr>
                            <%
                                }
                            }
                            %>
                        </tbody>
                    </table>
                </div>
            </section>

        </div>
    </main>
</div>

<script>
    const dutySelect = document.getElementById("dutyId");
    const roundInput = document.getElementById("verificationRoundId");
    const officerSelect = document.getElementById("officerEmployeeId");

    if (dutySelect) {
        dutySelect.addEventListener("change", function () {
            const selected = dutySelect.options[dutySelect.selectedIndex];

            if (selected) {
                const roundId = selected.getAttribute("data-round") || "0";
                const officerId = selected.getAttribute("data-officer") || "";

                if (roundInput) {
                    roundInput.value = roundId;
                }

                if (officerSelect && officerId !== "") {
                    officerSelect.value = officerId;
                }
            }
        });
    }

    const scheduledFrom = document.getElementById("scheduledFrom");
    const scheduledTo = document.getElementById("scheduledTo");
    const dutyForm = document.getElementById("dutyForm");
    const todayDate = "<%= todayDate %>";

    function openDatePicker(inputId) {
        const input = document.getElementById(inputId);

        if (!input) {
            return;
        }

        input.focus();

        if (typeof input.showPicker === "function") {
            input.showPicker();
        }
    }

    function validateScheduleDates() {
        if (!scheduledFrom || !scheduledTo) {
            return true;
        }

        scheduledFrom.setCustomValidity("");
        scheduledTo.setCustomValidity("");

        scheduledFrom.min = todayDate;
        scheduledTo.min = scheduledFrom.value || todayDate;

        if (scheduledFrom.value && scheduledFrom.value < todayDate) {
            scheduledFrom.value = todayDate;
            scheduledFrom.setCustomValidity("Past dates are not allowed.");
            return false;
        }

        if (scheduledTo.value && scheduledTo.value < todayDate) {
            scheduledTo.value = todayDate;
            scheduledTo.setCustomValidity("Past dates are not allowed.");
            return false;
        }

        if (scheduledFrom.value && scheduledTo.value && scheduledTo.value < scheduledFrom.value) {
            scheduledTo.value = scheduledFrom.value;
            scheduledTo.setCustomValidity("Scheduled To date cannot be before Scheduled From date.");
            return false;
        }

        return true;
    }

    document.querySelectorAll("[data-date-picker]").forEach(function (btn) {
        btn.addEventListener("click", function () {
            openDatePicker(btn.getAttribute("data-date-picker"));
        });
    });

    [scheduledFrom, scheduledTo].forEach(function (input) {
        if (!input) {
            return;
        }

        input.addEventListener("keydown", function (event) {
            event.preventDefault();
        });

        input.addEventListener("paste", function (event) {
            event.preventDefault();
        });

        input.addEventListener("change", function () {
            validateScheduleDates();
        });
    });

    if (scheduledFrom && scheduledTo) {
        scheduledTo.min = scheduledFrom.value || todayDate;

        scheduledFrom.addEventListener("change", function () {
            scheduledTo.min = scheduledFrom.value || todayDate;

            if (scheduledTo.value && scheduledTo.value < scheduledFrom.value) {
                scheduledTo.value = scheduledFrom.value;
            }
        });
    }

    if (dutyForm) {
        dutyForm.addEventListener("submit", function (event) {
            if (!validateScheduleDates()) {
                event.preventDefault();

                if (scheduledFrom && !scheduledFrom.checkValidity()) {
                    scheduledFrom.reportValidity();
                } else if (scheduledTo && !scheduledTo.checkValidity()) {
                    scheduledTo.reportValidity();
                }

                return false;
            }

            return true;
        });
    }
</script>

<script src="https://code.jquery.com/jquery-3.6.0.min.js"></script>
<script src="https://cdn.jsdelivr.net/npm/select2@4.1.0-rc.0/dist/js/select2.min.js"></script>
<script>
    $(document).ready(function() {
        $('#assetId').select2({
            placeholder: 'Search Asset (Code, Name)',
            ajax: {
                url: 'AssetSearchServlet',
                dataType: 'json',
                delay: 250,
                data: function(params) {
                    return {
                        q: params.term,
                        page: params.page
                    };
                },
                processResults: function(data, params) {
                    params.page = params.page || 1;
                    return {
                        results: data.results,
                        pagination: {
                            more: data.pagination.more
                        }
                    };
                },
                cache: true
            },
            minimumInputLength: 0
        });

        // Toast fade out and URL cleanup
        setTimeout(function() {
            $('.pv-alert').fadeOut('slow');
            if (window.history.replaceState) {
                const url = new URL(window.location);
                url.searchParams.delete('success');
                url.searchParams.delete('error');
                url.searchParams.delete('warning');
                window.history.replaceState({path: url.href}, '', url.href);
            }
        }, 5000);

        // Prevent double submission and show spinner
        $('#verificationForm').on('submit', function() {
            if ($(this).data('submitted') === true) {
                return false;
            }
            $(this).data('submitted', true);
            const submitBtns = $(this).find('button[type="submit"]');
            submitBtns.prop('disabled', true);
            submitBtns.filter('[value="submit"]').html('<i class="fa-solid fa-spinner fa-spin"></i> Processing...');
            return true;
        });
        
        $('#dutyForm').on('submit', function() {
            if ($(this).data('submitted') === true) {
                return false;
            }
            $(this).data('submitted', true);
            const submitBtn = $(this).find('button[type="submit"]');
            submitBtn.prop('disabled', true);
            submitBtn.html('<i class="fa-solid fa-spinner fa-spin"></i> Scheduling...');
            return true;
        });
    });
</script>

<script src="js/topbar-search.js?v=final-reference-1"></script>
<script src="js/user-dropdown.js?v=final-reference-1"></script>
<script src="js/sidebar-role.js?v=final-reference-1"></script>
<script src="js/ir-body-watermark.js?v=final-reference-1"></script>
<script src="js/dashboard-actions.js?v=final-reference-1"></script>
<script>
    var sortDirectionsDuty = [true, true, true, true, true, true, true];
    var sortDirectionsRecord = [true, true, true, true, true, true, true];
    
    function sortTableGeneric(tableId, columnIndex, sortDirectionsArray) {
        var table = document.getElementById(tableId);
        if (!table) return;
        
        var tbody = table.querySelector("tbody");
        if (!tbody) return;
        
        var rows = Array.from(tbody.querySelectorAll("tr"));
        if (rows.length === 1 && rows[0].querySelector("td[colspan]")) return; // Empty records row

        var asc = sortDirectionsArray[columnIndex];
        sortDirectionsArray[columnIndex] = !asc;

        rows.sort(function(a, b) {
            var cellA = a.querySelectorAll("td")[columnIndex];
            var cellB = b.querySelectorAll("td")[columnIndex];

            if (!cellA || !cellB) return 0;
            
            var valA = cellA.innerText || cellA.textContent;
            var valB = cellB.innerText || cellB.textContent;
            
            valA = valA.trim().toLowerCase();
            valB = valB.trim().toLowerCase();
            
            if (valA < valB) return asc ? -1 : 1;
            if (valA > valB) return asc ? 1 : -1;
            return 0;
        });

        rows.forEach(function(row) {
            tbody.appendChild(row);
        });
        
        var headers = table.querySelectorAll("thead th");
        headers.forEach(function(th, idx) {
            var icon = th.querySelector("i.fa-sort, i.fa-sort-up, i.fa-sort-down");
            if (icon) {
                icon.className = "fa-solid fa-sort";
                if (idx === columnIndex) {
                    icon.className = asc ? "fa-solid fa-sort-up" : "fa-solid fa-sort-down";
                }
            }
        });
    }

    function sortDutyTable(columnIndex) {
        sortTableGeneric("dutyTable", columnIndex, sortDirectionsDuty);
    }
    
    function sortRecordTable(columnIndex) {
        sortTableGeneric("recordTable", columnIndex, sortDirectionsRecord);
    }
</script>

</body>
</html>