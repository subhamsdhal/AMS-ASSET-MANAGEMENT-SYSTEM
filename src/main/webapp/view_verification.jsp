<%@page contentType="text/html" pageEncoding="UTF-8"%>
<%@page import="com.mycompany.asset_management_system_ams.DBConnection"%>
<%@page import="java.sql.*"%>
<%@page import="java.util.*"%>

<%!
    private String safeText(Object value) {
        if (value == null || String.valueOf(value).trim().isEmpty()) {
            return "N/A";
        }

        return String.valueOf(value).trim()
                .replace("&", "&amp;")
                .replace("<", "&lt;")
                .replace(">", "&gt;")
                .replace("\"", "&quot;")
                .replace("'", "&#39;");
    }

    private String safeValue(Object value) {
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

    private String shortText(String value, int maxLength) {
        if (value == null || value.trim().isEmpty()) {
            return "N/A";
        }

        String text = value.trim();

        if (text.length() <= maxLength) {
            return text;
        }

        return text.substring(0, maxLength) + "...";
    }

    private String rowValue(Map<String, String> row, String key) {
        if (row == null) {
            return "";
        }

        String value = row.get(key);
        return value == null ? "" : value;
    }

    private String statusClass(String status) {
        if (status == null || status.trim().isEmpty()) {
            return "";
        }

        String cleanStatus = status.trim().toUpperCase(Locale.ENGLISH);

        if ("VERIFIED".equals(cleanStatus)
                || "APPROVED".equals(cleanStatus)
                || "COMPLETED".equals(cleanStatus)
                || "SERVICEABLE".equals(cleanStatus)) {
            return "success";
        }

        if ("LOCATION_MISMATCH".equals(cleanStatus)
                || "EMPLOYEE_MISMATCH".equals(cleanStatus)
                || "HOLDER_MISMATCH".equals(cleanStatus)
                || "NEEDS_REVIEW".equals(cleanStatus)
                || "SUBMITTED".equals(cleanStatus)
                || "REVIEWED".equals(cleanStatus)
                || "SCHEDULED".equals(cleanStatus)
                || "IN_PROGRESS".equals(cleanStatus)) {
            return "warning";
        }

        if ("NOT_FOUND".equals(cleanStatus)
                || "DAMAGED".equals(cleanStatus)
                || "UNDER_REPAIR".equals(cleanStatus)
                || "REJECTED".equals(cleanStatus)
                || "CANCELLED".equals(cleanStatus)) {
            return "danger";
        }

        return "";
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
        response.sendRedirect("physical_verification.jsp?error=accessDenied");
        return;
    }

    String success = request.getParameter("success");
    String error = request.getParameter("error");

    String verificationId = request.getParameter("id");

    if (verificationId == null || verificationId.trim().isEmpty()) {
        verificationId = request.getParameter("verification_id");
    }

    if (verificationId == null || verificationId.trim().isEmpty()) {
        response.sendRedirect("physical_verification.jsp?error=invalid");
        return;
    }

    verificationId = verificationId.trim();

    String userInitial = username.substring(0, Math.min(2, username.length())).toUpperCase(Locale.ENGLISH);

    Map<String, String> verification = new HashMap<String, String>();
    List<Map<String, String>> assetVerificationRows = new ArrayList<Map<String, String>>();

    try (Connection con = DBConnection.getConnection()) {

        if (!tableExists(con, "asset_physical_verification")) {
            response.sendRedirect("physical_verification.jsp?error=tableMissing");
            return;
        }

        boolean hasUsers = tableExists(con, "users");
        boolean hasEmployees = tableExists(con, "employees");
        boolean hasDepartments = tableExists(con, "departments");
        boolean hasVendors = tableExists(con, "vendors");
        boolean hasRailwayLocations = tableExists(con, "railway_locations");
        boolean hasPhysicalRounds = tableExists(con, "physical_verification_rounds");
        boolean hasPhysicalDuties = tableExists(con, "physical_verification_duties");

        boolean hasReviewStatus = columnExists(con, "asset_physical_verification", "review_status");
        boolean hasVerifiedOn = columnExists(con, "asset_physical_verification", "verified_on");
        boolean hasRemarks = columnExists(con, "asset_physical_verification", "remarks");
        boolean hasDutyId = columnExists(con, "asset_physical_verification", "duty_id");
        boolean hasActualLocationId = columnExists(con, "asset_physical_verification", "actual_location_id");
        boolean hasActualEmployeeId = columnExists(con, "asset_physical_verification", "actual_employee_id");
        boolean hasOfficerEmployeeId = columnExists(con, "asset_physical_verification", "verification_officer_employee_id");
        boolean hasOfficerDepartmentId = columnExists(con, "asset_physical_verification", "verification_officer_department_id");
        boolean hasVerifiedByUserId = columnExists(con, "asset_physical_verification", "verified_by_user_id");
        boolean hasVerificationRoundId = columnExists(con, "asset_physical_verification", "verification_round_id");

        boolean hasAssetRailwayNo = columnExists(con, "assets", "railway_asset_no");
        boolean hasAssetModelNo = columnExists(con, "assets", "model_number");
        boolean hasAssetServiceStatus = columnExists(con, "assets", "service_status");
        boolean hasAssetSerialNo = columnExists(con, "assets", "serial_number");
        boolean hasAssetLocationText = columnExists(con, "assets", "location");
        boolean hasAssetRailwayLocationId = columnExists(con, "assets", "railway_location_id");
        boolean hasAssetLocationId = columnExists(con, "assets", "location_id");
        boolean hasAssetVendorId = columnExists(con, "assets", "vendor_id");

        boolean hasEmployeeFullName = hasEmployees && columnExists(con, "employees", "full_name");
        boolean hasEmployeeCode = hasEmployees && columnExists(con, "employees", "employee_code");
        boolean hasEmployeeDesignation = hasEmployees && columnExists(con, "employees", "designation");

        String actualEmployeeNameExpression = "''";
        String actualEmployeeCodeExpression = "''";
        String actualEmployeeDesignationExpression = "''";

        String officerEmployeeNameExpression = "''";
        String officerEmployeeCodeExpression = "''";
        String officerEmployeeDesignationExpression = "''";

        if (hasEmployees) {
            if (hasEmployeeFullName) {
                actualEmployeeNameExpression = "COALESCE(ae.full_name, '')";
                officerEmployeeNameExpression = "COALESCE(oe.full_name, '')";
            } else {
                actualEmployeeNameExpression = "COALESCE(ae.employee_name, '')";
                officerEmployeeNameExpression = "COALESCE(ae.employee_name, '')";
            }

            if (hasEmployeeCode) {
                actualEmployeeCodeExpression = "COALESCE(ae.employee_code, '')";
                officerEmployeeCodeExpression = "COALESCE(oe.employee_code, '')";
            }

            if (hasEmployeeDesignation) {
                actualEmployeeDesignationExpression = "COALESCE(ae.designation, '')";
                officerEmployeeDesignationExpression = "COALESCE(oe.designation, '')";
            }
        }

        String assetRailwayNoExpression = hasAssetRailwayNo
                ? "COALESCE(a.railway_asset_no, '')"
                : "''";

        String assetModelNoExpression = hasAssetModelNo
                ? "COALESCE(a.model_number, '')"
                : "''";

        String assetServiceStatusExpression = hasAssetServiceStatus
                ? "COALESCE(a.service_status, '')"
                : "''";

        String assetSerialNoExpression = hasAssetSerialNo
                ? "COALESCE(a.serial_number, '')"
                : "''";

        String assetLocationTextExpression = hasAssetLocationText
                ? "NULLIF(a.location, '')"
                : "NULL";

        String expectedLocationJoin = "";
        String expectedLocationExpression = "COALESCE(" + assetLocationTextExpression + ", 'Not Available')";

        if (hasRailwayLocations && hasAssetRailwayLocationId) {
            expectedLocationJoin = "LEFT JOIN railway_locations el ON a.railway_location_id = el.location_id ";
            expectedLocationExpression = "COALESCE(el.location_name, " + assetLocationTextExpression + ", 'Not Available')";
        } else if (hasRailwayLocations && hasAssetLocationId) {
            expectedLocationJoin = "LEFT JOIN railway_locations el ON a.location_id = el.location_id ";
            expectedLocationExpression = "COALESCE(el.location_name, " + assetLocationTextExpression + ", 'Not Available')";
        }

        String actualLocationJoin = "";
        String actualLocationExpression = "'Not Updated'";
        String actualLocationCodeExpression = "''";

        if (hasRailwayLocations && hasActualLocationId) {
            actualLocationJoin = "LEFT JOIN railway_locations al ON pv.actual_location_id = al.location_id ";
            actualLocationExpression = "COALESCE(al.location_name, 'Not Updated')";
            actualLocationCodeExpression = "COALESCE(al.location_code, '')";
        }

        String actualEmployeeJoin = "";
        if (hasEmployees && hasActualEmployeeId) {
            actualEmployeeJoin = "LEFT JOIN employees ae ON pv.actual_employee_id = ae.employee_id ";
        } else {
            actualEmployeeNameExpression = "''";
            actualEmployeeCodeExpression = "''";
            actualEmployeeDesignationExpression = "''";
        }

        String officerEmployeeJoin = "";
        if (hasEmployees && hasOfficerEmployeeId) {
            officerEmployeeJoin = "LEFT JOIN employees oe ON pv.verification_officer_employee_id = oe.employee_id ";
        } else {
            officerEmployeeNameExpression = "''";
            officerEmployeeCodeExpression = "''";
            officerEmployeeDesignationExpression = "''";
        }

        String officerDepartmentJoin = "";
        String officerDepartmentExpression = "''";

        if (hasDepartments && hasOfficerDepartmentId) {
            officerDepartmentJoin = "LEFT JOIN departments od ON pv.verification_officer_department_id = od.department_id ";
            officerDepartmentExpression = "COALESCE(od.department_name, '')";
        }

        String verifiedByJoin = "";
        String verifiedByExpression = "'System'";

        if (hasUsers && hasVerifiedByUserId) {
            verifiedByJoin = "LEFT JOIN users u ON pv.verified_by_user_id = u.user_id ";
            verifiedByExpression = "COALESCE(u.username, 'System')";
        }

        String roundJoin = "";
        String roundCodeExpression = "''";
        String roundTitleExpression = "''";
        String roundTypeExpression = "''";

        if (hasPhysicalRounds && hasVerificationRoundId) {
            roundJoin = "LEFT JOIN physical_verification_rounds pvr ON pv.verification_round_id = pvr.verification_round_id ";
            roundCodeExpression = "COALESCE(pvr.round_code, '')";
            roundTitleExpression = "COALESCE(pvr.round_title, '')";
            roundTypeExpression = "COALESCE(pvr.verification_type, '')";
        }

        String dutyJoin = "";
        String dutyStatusExpression = "''";
        String dutyScheduledFromExpression = "''";
        String dutyScheduledToExpression = "''";
        String dutyInstructionsExpression = "''";

        if (hasPhysicalDuties && hasDutyId) {
            dutyJoin = "LEFT JOIN physical_verification_duties pvd ON pv.duty_id = pvd.duty_id ";
            dutyStatusExpression = "COALESCE(pvd.duty_status, '')";
            dutyScheduledFromExpression = "COALESCE(DATE_FORMAT(pvd.scheduled_from, '%d %b %Y'), '')";
            dutyScheduledToExpression = "COALESCE(DATE_FORMAT(pvd.scheduled_to, '%d %b %Y'), '')";
            dutyInstructionsExpression = "COALESCE(pvd.instructions, '')";
        }

        String supplierJoin = "";
        String supplierNameExpression = "'No Supplier'";
        String supplierContactExpression = "''";

        if (hasVendors && hasAssetVendorId) {
            supplierJoin = "LEFT JOIN vendors v ON a.vendor_id = v.vendor_id ";
            supplierNameExpression = "COALESCE(v.vendor_name, 'No Supplier')";
            supplierContactExpression = "TRIM(CONCAT(COALESCE(v.phone, ''), CASE WHEN COALESCE(v.email, '') = '' THEN '' ELSE CONCAT(' · ', v.email) END))";
        }

        String verifiedOnExpression = hasVerifiedOn
                ? "COALESCE(DATE_FORMAT(pv.verified_on, '%d %b %Y, %h:%i %p'), '')"
                : "''";

        String verifiedOnRawExpression = hasVerifiedOn
                ? "COALESCE(DATE_FORMAT(pv.verified_on, '%Y-%m-%d'), '')"
                : "''";

        String reviewStatusExpression = hasReviewStatus
                ? "COALESCE(pv.review_status, '')"
                : "''";

        String remarksExpression = hasRemarks
                ? "COALESCE(pv.remarks, '')"
                : "''";

        String dutyIdExpression = hasDutyId
                ? "COALESCE(pv.duty_id, 0)"
                : "0";

        String querySql = "SELECT "
                + "pv.verification_id, "
                + "pv.asset_id, "
                + (hasVerificationRoundId ? "COALESCE(pv.verification_round_id, 0)" : "0") + " AS verification_round_id, "
                + dutyIdExpression + " AS duty_id, "
                + "pv.verified_status, "
                + reviewStatusExpression + " AS review_status, "
                + verifiedOnExpression + " AS verified_on, "
                + verifiedOnRawExpression + " AS verified_on_raw, "
                + remarksExpression + " AS remarks, "
                + "COALESCE(a.asset_code, '') AS asset_code, "
                + assetRailwayNoExpression + " AS railway_asset_no, "
                + "COALESCE(a.asset_name, '') AS asset_name, "
                + assetSerialNoExpression + " AS serial_number, "
                + assetModelNoExpression + " AS model_number, "
                + "COALESCE(a.asset_status, '') AS asset_status, "
                + assetServiceStatusExpression + " AS service_status, "
                + "COALESCE(ac.category_name, 'Uncategorized') AS category_name, "
                + supplierNameExpression + " AS supplier_name, "
                + supplierContactExpression + " AS supplier_contact, "
                + expectedLocationExpression + " AS expected_location, "
                + actualLocationExpression + " AS actual_location, "
                + actualLocationCodeExpression + " AS actual_location_code, "
                + actualEmployeeCodeExpression + " AS actual_employee_code, "
                + actualEmployeeNameExpression + " AS actual_employee_name, "
                + actualEmployeeDesignationExpression + " AS actual_employee_designation, "
                + officerEmployeeCodeExpression + " AS officer_code, "
                + officerEmployeeNameExpression + " AS officer_name, "
                + officerEmployeeDesignationExpression + " AS officer_designation, "
                + officerDepartmentExpression + " AS officer_department_name, "
                + verifiedByExpression + " AS verified_by_username, "
                + roundCodeExpression + " AS round_code, "
                + roundTitleExpression + " AS round_title, "
                + roundTypeExpression + " AS verification_type, "
                + dutyStatusExpression + " AS duty_status, "
                + dutyScheduledFromExpression + " AS scheduled_from, "
                + dutyScheduledToExpression + " AS scheduled_to, "
                + dutyInstructionsExpression + " AS duty_instructions "
                + "FROM asset_physical_verification pv "
                + "LEFT JOIN assets a ON pv.asset_id = a.asset_id "
                + "LEFT JOIN asset_categories ac ON a.category_id = ac.category_id "
                + supplierJoin
                + expectedLocationJoin
                + actualLocationJoin
                + actualEmployeeJoin
                + officerEmployeeJoin
                + officerDepartmentJoin
                + verifiedByJoin
                + roundJoin
                + dutyJoin
                + "WHERE pv.verification_id = ? "
                + "LIMIT 1";

        try (PreparedStatement ps = con.prepareStatement(querySql)) {
            ps.setString(1, verificationId);

            try (ResultSet rs = ps.executeQuery()) {
                ResultSetMetaData meta = rs.getMetaData();
                int count = meta.getColumnCount();

                if (rs.next()) {
                    for (int i = 1; i <= count; i++) {
                        verification.put(meta.getColumnLabel(i), rs.getString(i));
                    }
                }
            }
        }

        if (verification.isEmpty()) {
            response.sendRedirect("physical_verification.jsp?error=notfound");
            return;
        }

        String assetId = rowValue(verification, "asset_id");

        String historySql = "SELECT "
                + "pv.verification_id, "
                + "pv.verified_status, "
                + reviewStatusExpression + " AS review_status, "
                + verifiedOnExpression + " AS verified_on, "
                + remarksExpression + " AS remarks, "
                + verifiedByExpression + " AS verified_by_username "
                + "FROM asset_physical_verification pv "
                + verifiedByJoin
                + "WHERE pv.asset_id = ? "
                + "ORDER BY pv.verification_id DESC "
                + "LIMIT 10";

        try (PreparedStatement ps = con.prepareStatement(historySql)) {
            ps.setString(1, assetId);

            try (ResultSet rs = ps.executeQuery()) {
                ResultSetMetaData meta = rs.getMetaData();
                int count = meta.getColumnCount();

                while (rs.next()) {
                    Map<String, String> row = new HashMap<String, String>();

                    for (int i = 1; i <= count; i++) {
                        row.put(meta.getColumnLabel(i), rs.getString(i));
                    }

                    assetVerificationRows.add(row);
                }
            }
        }

    } catch (Exception e) {
        e.printStackTrace();
        response.sendRedirect("physical_verification.jsp?error=viewFailed");
        return;
    }

    String verificationStatus = rowValue(verification, "verified_status");
    String reviewStatus = rowValue(verification, "review_status");
    String badgeStatusClass = statusClass(verificationStatus);
%>

<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>Verification Details - IR-AMS</title>

    <link rel="stylesheet"
          href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.0/css/all.min.css">

    <link rel="stylesheet" href="css/ir-glass.css?v=28000">
    <link rel="stylesheet" href="css/ams-pro.css?v=28000">
    <link rel="stylesheet" href="css/ir-ams-railway-ui.css?v=view-verification-fixed-1">

    <link rel="stylesheet" href="css/view_verification.css?v=28001">
</head>

<body class="railway-ui">
<div class="app ams-shell">
    <jsp:include page="sidebar.jsp" />

    <main class="main railway-main">
        <jsp:include page="topbar.jsp" />

        <div class="main-scroll-content detail-board">
            <% if ("approved".equals(success)) { %>
                <div class="pv-alert success" style="margin-bottom: 20px;">
                    <i class="fa-solid fa-circle-check"></i> Verification Approved successfully.
                </div>
            <% } else if ("rejected".equals(success)) { %>
                <div class="pv-alert success" style="margin-bottom: 20px;">
                    <i class="fa-solid fa-circle-check"></i> Verification Rejected.
                </div>
            <% } %>

            <% if (error != null && !error.trim().isEmpty()) { %>
                <div class="pv-alert error" style="margin-bottom: 20px;">
                    <i class="fa-solid fa-triangle-exclamation"></i> Action failed: <%= safeText(cleanLabel(error)) %>
                </div>
            <% } %>

            <section class="detail-hero">
                <div>
                    <h1>Verification #<%= safeText(rowValue(verification, "verification_id")) %></h1>

                    <p>
                        <strong><%= safeText(rowValue(verification, "asset_code")) %></strong>
                        · <%= safeText(rowValue(verification, "asset_name")) %>
                        · <%= safeText(cleanLabel(verificationStatus)) %>
                    </p>
                </div>

                <div class="hero-actions">
                    <span class="status-pill <%= badgeStatusClass %>">
                        <i class="fa-solid fa-shield-halved"></i>
                        <%= safeText(cleanLabel(verificationStatus)) %>
                    </span>
                    
                    <%-- Fault (Critical, fixed): review_status's enum never actually
                         contains 'PENDING' (schema.sql: SUBMITTED/REVIEWED/APPROVED/
                         REJECTED, default SUBMITTED), so this button never rendered
                         for any real verification - matching ReviewPhysicalVerificationServlet's
                         identical mismatch. Both now key on the enum's real initial value. --%>
                    <% if (canManageVerification && "SUBMITTED".equalsIgnoreCase(reviewStatus)) { %>
                        <form action="ReviewPhysicalVerificationServlet" method="post" style="display:inline;" onsubmit="return confirm('Are you sure you want to approve this verification?');">
                            <input type="hidden" name="verificationId" value="<%= safeValue(verificationId) %>">
                            <input type="hidden" name="action" value="approve">
                            <button type="submit" class="btn btn-primary" style="background-color: #10b981; border-color: #10b981;">
                                <i class="fa-solid fa-check"></i> Approve
                            </button>
                        </form>
                        
                        <button type="button" class="btn" style="background-color: #ef4444; color: white; border-color: #ef4444;" onclick="document.getElementById('rejectModal').style.display='flex';">
                            <i class="fa-solid fa-xmark"></i> Reject
                        </button>
                    <% } %>

                    <a href="physical_verification.jsp" class="btn">
                        <i class="fa-solid fa-arrow-left"></i>
                        Back
                    </a>

                    <a href="view_asset.jsp?id=<%= safeValue(rowValue(verification, "asset_id")) %>" class="btn btn-primary">
                        <i class="fa-solid fa-cube"></i>
                        Open Asset
                    </a>
                </div>
            </section>

            <section class="summary-grid">
                <div class="summary-card">
                    <span>Asset Code</span>
                    <strong><%= safeText(rowValue(verification, "asset_code")) %></strong>
                </div>

                <div class="summary-card">
                    <span>Verification Status</span>
                    <strong><%= safeText(cleanLabel(verificationStatus)) %></strong>
                </div>

                <div class="summary-card">
                    <span>Review Status</span>
                    <strong><%= safeText(cleanLabel(reviewStatus)) %></strong>
                </div>

                <div class="summary-card">
                    <span>Verified On</span>
                    <strong><%= safeText(rowValue(verification, "verified_on")) %></strong>
                </div>
            </section>

            <section class="detail-grid">

                <div class="detail-panel">
                    <div class="panel-title-row">
                        <h2 class="panel-title">Verification Details</h2>
                    </div>

                    <table class="detail-table">
                        <tr>
                            <th>Verification ID</th>
                            <td><%= safeText(rowValue(verification, "verification_id")) %></td>
                        </tr>

                        <tr>
                            <th>Round Code</th>
                            <td><%= safeText(rowValue(verification, "round_code")) %></td>
                        </tr>

                        <tr>
                            <th>Round Title</th>
                            <td><%= safeText(rowValue(verification, "round_title")) %></td>
                        </tr>

                        <tr>
                            <th>Verification Type</th>
                            <td><%= safeText(cleanLabel(rowValue(verification, "verification_type"))) %></td>
                        </tr>

                        <tr>
                            <th>Duty ID</th>
                            <td><%= safeText(rowValue(verification, "duty_id")) %></td>
                        </tr>

                        <tr>
                            <th>Duty Status</th>
                            <td><%= safeText(cleanLabel(rowValue(verification, "duty_status"))) %></td>
                        </tr>

                        <tr>
                            <th>Scheduled From</th>
                            <td><%= safeText(rowValue(verification, "scheduled_from")) %></td>
                        </tr>

                        <tr>
                            <th>Scheduled To</th>
                            <td><%= safeText(rowValue(verification, "scheduled_to")) %></td>
                        </tr>

                        <tr>
                            <th>Verified Status</th>
                            <td><%= safeText(cleanLabel(verificationStatus)) %></td>
                        </tr>

                        <tr>
                            <th>Review Status</th>
                            <td><%= safeText(cleanLabel(reviewStatus)) %></td>
                        </tr>

                        <tr>
                            <th>Verified On</th>
                            <td><%= safeText(rowValue(verification, "verified_on")) %></td>
                        </tr>

                        <tr>
                            <th>Verified By</th>
                            <td><%= safeText(rowValue(verification, "verified_by_username")) %></td>
                        </tr>

                        <tr>
                            <th>Remarks</th>
                            <td><%= safeText(rowValue(verification, "remarks")) %></td>
                        </tr>
                    </table>
                </div>

                <div class="detail-panel">
                    <div class="panel-title-row">
                        <h2 class="panel-title">Asset Details</h2>
                    </div>

                    <table class="detail-table">
                        <tr>
                            <th>Asset Code</th>
                            <td>
                                <a href="view_asset.jsp?id=<%= safeValue(rowValue(verification, "asset_id")) %>">
                                    <%= safeText(rowValue(verification, "asset_code")) %>
                                </a>
                            </td>
                        </tr>

                        <tr>
                            <th>Railway Asset No.</th>
                            <td><%= safeText(rowValue(verification, "railway_asset_no")) %></td>
                        </tr>

                        <tr>
                            <th>Asset Name</th>
                            <td><%= safeText(rowValue(verification, "asset_name")) %></td>
                        </tr>

                        <tr>
                            <th>Category</th>
                            <td><%= safeText(rowValue(verification, "category_name")) %></td>
                        </tr>

                        <tr>
                            <th>Serial Number</th>
                            <td><%= safeText(rowValue(verification, "serial_number")) %></td>
                        </tr>

                        <tr>
                            <th>Model Number</th>
                            <td><%= safeText(rowValue(verification, "model_number")) %></td>
                        </tr>

                        <tr>
                            <th>Asset Status</th>
                            <td><%= safeText(cleanLabel(rowValue(verification, "asset_status"))) %></td>
                        </tr>

                        <tr>
                            <th>Service Status</th>
                            <td><%= safeText(cleanLabel(rowValue(verification, "service_status"))) %></td>
                        </tr>

                        <tr>
                            <th>Supplier</th>
                            <td><%= safeText(rowValue(verification, "supplier_name")) %></td>
                        </tr>

                        <tr>
                            <th>Supplier Contact</th>
                            <td><%= safeText(rowValue(verification, "supplier_contact")) %></td>
                        </tr>
                    </table>
                </div>

            </section>

            <section class="detail-grid">

                <div class="detail-panel">
                    <div class="panel-title-row">
                        <h2 class="panel-title">Location Verification</h2>
                    </div>

                    <table class="detail-table">
                        <tr>
                            <th>System Location</th>
                            <td><%= safeText(rowValue(verification, "expected_location")) %></td>
                        </tr>

                        <tr>
                            <th>Actual Location</th>
                            <td><%= safeText(rowValue(verification, "actual_location")) %></td>
                        </tr>

                        <tr>
                            <th>Actual Location Code</th>
                            <td><%= safeText(rowValue(verification, "actual_location_code")) %></td>
                        </tr>

                        <tr>
                            <th>Result Note</th>
                            <td>
                                <% if ("LOCATION_MISMATCH".equalsIgnoreCase(verificationStatus)) { %>
                                    Location mismatch reported. Please review system location and physical location.
                                <% } else if ("VERIFIED".equalsIgnoreCase(verificationStatus)) { %>
                                    Location verification is accepted for this record.
                                <% } else { %>
                                    Review location details as per physical verification result.
                                <% } %>
                            </td>
                        </tr>
                    </table>
                </div>

                <div class="detail-panel">
                    <div class="panel-title-row">
                        <h2 class="panel-title">Holder / Officer Details</h2>
                    </div>

                    <table class="detail-table">
                        <tr>
                            <th>Actual Holder Code</th>
                            <td><%= safeText(rowValue(verification, "actual_employee_code")) %></td>
                        </tr>

                        <tr>
                            <th>Actual Holder Name</th>
                            <td><%= safeText(rowValue(verification, "actual_employee_name")) %></td>
                        </tr>

                        <tr>
                            <th>Holder Designation</th>
                            <td><%= safeText(rowValue(verification, "actual_employee_designation")) %></td>
                        </tr>

                        <tr>
                            <th>Officer Code</th>
                            <td><%= safeText(rowValue(verification, "officer_code")) %></td>
                        </tr>

                        <tr>
                            <th>Officer Name</th>
                            <td><%= safeText(rowValue(verification, "officer_name")) %></td>
                        </tr>

                        <tr>
                            <th>Officer Designation</th>
                            <td><%= safeText(rowValue(verification, "officer_designation")) %></td>
                        </tr>

                        <tr>
                            <th>Officer Department</th>
                            <td><%= safeText(rowValue(verification, "officer_department_name")) %></td>
                        </tr>
                    </table>
                </div>

            </section>

            
            <section class="add-asset-hero-new" style="margin-bottom: 20px; background: url('<%= request.getContextPath() %>/images/physical-verification-hero-bg.png') center center / cover no-repeat, linear-gradient(135deg, rgba(255,255,255,0.95), rgba(232,245,255,0.92)) !important;">
                <h1 style="margin: 0; color: #08348f; font-size: 28px; line-height: 1.1; font-weight: 950; text-transform: uppercase; position: relative; z-index: 2;">VIEW VERIFICATION</h1>
                <p style="margin: 8px 0 0 0; color: #18366f; font-size: 13px; font-weight: 800; position: relative; z-index: 2;">Manage your module settings seamlessly</p>
            </section>
            <section class="detail-panel">
                <div class="panel-title-row">
                    <h2 class="panel-title">Duty Instructions</h2>
                </div>

                <table class="detail-table">
                    <tr>
                        <th>Instructions</th>
                        <td><%= safeText(rowValue(verification, "duty_instructions")) %></td>
                    </tr>
                </table>
            </section>

            
            <section class="add-asset-hero-new" style="margin-bottom: 20px; background: url('<%= request.getContextPath() %>/images/physical-verification-hero-bg.png') center center / cover no-repeat, linear-gradient(135deg, rgba(255,255,255,0.95), rgba(232,245,255,0.92)) !important;">
                <h1 style="margin: 0; color: #08348f; font-size: 28px; line-height: 1.1; font-weight: 950; text-transform: uppercase; position: relative; z-index: 2;">VIEW VERIFICATION</h1>
                <p style="margin: 8px 0 0 0; color: #18366f; font-size: 13px; font-weight: 800; position: relative; z-index: 2;">Manage your module settings seamlessly</p>
            </section>
            <section class="detail-panel">
                <div class="panel-title-row">
                    <h2 class="panel-title">Verification History of Same Asset</h2>
                </div>

                <% if (assetVerificationRows == null || assetVerificationRows.isEmpty()) { %>

                    <div class="empty-box">
                        <i class="fa-solid fa-circle-info"></i>
                        <strong>No history found</strong>
                        <span>No other physical verification record is linked with this asset.</span>
                    </div>

                <% } else { %>

                    <div class="timeline-list">
                        <%
                            for (Map<String, String> row : assetVerificationRows) {
                                String rowStatus = rowValue(row, "verified_status");
                                String rowReview = rowValue(row, "review_status");
                        %>

                            <a class="timeline-row" href="view_verification.jsp?id=<%= safeValue(rowValue(row, "verification_id")) %>">
                                <div class="timeline-icon">
                                    <i class="fa-solid fa-shield-halved"></i>
                                </div>

                                <div class="timeline-text">
                                    <strong>
                                        Verification #<%= safeText(rowValue(row, "verification_id")) %>
                                        · <%= safeText(cleanLabel(rowStatus)) %>
                                        · <%= safeText(cleanLabel(rowReview)) %>
                                    </strong>

                                    <span>
                                        <%= safeText(shortText(rowValue(row, "remarks"), 120)) %>
                                        · Verified By:
                                        <%= safeText(rowValue(row, "verified_by_username")) %>
                                    </span>
                                </div>

                                <div class="timeline-date">
                                    <%= safeText(rowValue(row, "verified_on")) %>
                                </div>
                            </a>

                        <%
                            }
                        %>
                    </div>

                <% } %>
            </section>

        </div>
    </main>
</div>

<!-- Reject Modal -->
<div id="rejectModal" style="display:none; position:fixed; top:0; left:0; width:100%; height:100%; background:rgba(0,0,0,0.5); z-index:9999; align-items:center; justify-content:center;">
    <div style="background:white; padding:20px; border-radius:8px; width:400px; max-width:90%;">
        <h3 style="margin-top:0; color:#ef4444;">Reject Verification</h3>
        <p>Please provide a reason for rejecting this verification.</p>
        <form action="ReviewPhysicalVerificationServlet" method="post">
            <input type="hidden" name="verificationId" value="<%= safeValue(verificationId) %>">
            <input type="hidden" name="action" value="reject">
            <textarea name="remarks" required style="width:100%; height:100px; padding:8px; border:1px solid #ccc; border-radius:4px; margin-bottom:15px;" placeholder="Rejection remarks..."></textarea>
            <div style="display:flex; justify-content:flex-end; gap:10px;">
                <button type="button" class="btn" onclick="document.getElementById('rejectModal').style.display='none';">Cancel</button>
                <button type="submit" class="btn btn-primary" style="background-color:#ef4444; border-color:#ef4444;">Submit Rejection</button>
            </div>
        </form>
    </div>
</div>

<script src="https://code.jquery.com/jquery-3.6.0.min.js"></script>
<script>
    $(document).ready(function() {
        // Toast fade out and URL cleanup
        setTimeout(function() {
            $('.pv-alert').fadeOut('slow');
            if (window.history.replaceState) {
                const url = new URL(window.location);
                url.searchParams.delete('success');
                url.searchParams.delete('error');
                window.history.replaceState({path: url.href}, '', url.href);
            }
        }, 5000);
    });
</script>

<script src="js/user-dropdown.js?v=5"></script>
<script src="js/sidebar-role.js?v=view-verification-fixed-1"></script>
<script src="js/topbar-search.js?v=global-search-ready-1"></script>
<script src="js/dashboard-actions.js?v=2"></script>

</body>
</html>