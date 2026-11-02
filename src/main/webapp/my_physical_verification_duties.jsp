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
    Object employeeIdObj = session.getAttribute("employee_id");

    response.setHeader("Cache-Control", "no-cache, no-store, must-revalidate");
    response.setHeader("Pragma", "no-cache");
    response.setDateHeader("Expires", 0);

    if (username == null || role == null || employeeIdObj == null) {
        response.sendRedirect("login.jsp");
        return;
    }

    int employeeId;
    try {
        employeeId = Integer.parseInt(String.valueOf(employeeIdObj));
    } catch (Exception e) {
        employeeId = 0;
    }

    if (employeeId <= 0) {
        response.sendRedirect("login.jsp");
        return;
    }

    String success = request.getParameter("success");
    String error = request.getParameter("error");

    String qrAssetIdParam = request.getParameter("assetId");
    String qrAssetText = null;

    List<Map<String, String>> dutyList = new ArrayList<Map<String, String>>();
    List<Map<String, String>> openDutyList = new ArrayList<Map<String, String>>();
    List<Map<String, String>> myReportList = new ArrayList<Map<String, String>>();
    List<Map<String, String>> locationList = new ArrayList<Map<String, String>>();

    try (Connection con = DBConnection.getConnection()) {

        boolean hasDuties = tableExists(con, "physical_verification_duties");
        boolean hasRounds = tableExists(con, "physical_verification_rounds");
        boolean hasVerification = tableExists(con, "asset_physical_verification");
        boolean hasAssets = tableExists(con, "assets");
        boolean hasRailwayLocations = tableExists(con, "railway_locations");

        boolean hasRoundCode = hasRounds && columnExists(con, "physical_verification_rounds", "round_code");
        boolean hasRoundTitle = hasRounds && columnExists(con, "physical_verification_rounds", "round_title");

        if (qrAssetIdParam != null && !qrAssetIdParam.trim().isEmpty() && hasAssets) {
            String assetSql = "SELECT a.asset_id, "
                    + "COALESCE(a.asset_code, '') AS asset_code, "
                    + "COALESCE(a.asset_name, '') AS asset_name "
                    + "FROM assets a "
                    + "WHERE a.asset_id = ?";

            try (PreparedStatement ps = con.prepareStatement(assetSql)) {
                ps.setInt(1, Integer.parseInt(qrAssetIdParam));
                try (ResultSet rs = ps.executeQuery()) {
                    if (rs.next()) {
                        qrAssetText = safe(rs.getObject("asset_code")) + " - " + safe(rs.getObject("asset_name"));
                    } else {
                        qrAssetIdParam = null;
                    }
                }
            } catch (Exception e) {
                e.printStackTrace();
                qrAssetIdParam = null;
            }
        }

        if (hasDuties) {
            String roundJoin = "";
            String roundCodeExpression = "''";
            String roundTitleExpression = "''";

            if (hasRounds) {
                roundJoin = "LEFT JOIN physical_verification_rounds r ON d.verification_round_id = r.verification_round_id ";
                roundCodeExpression = hasRoundCode ? "COALESCE(r.round_code, '')" : "''";
                roundTitleExpression = hasRoundTitle ? "COALESCE(r.round_title, '')" : "''";
            }

            String dutySql = "SELECT d.duty_id, d.verification_round_id, d.duty_status, "
                    + "d.scheduled_from, d.scheduled_to, d.instructions, "
                    + roundCodeExpression + " AS round_code, "
                    + roundTitleExpression + " AS round_title "
                    + "FROM physical_verification_duties d "
                    + roundJoin
                    + "WHERE d.assigned_employee_id = ? "
                    + "ORDER BY d.scheduled_from DESC, d.duty_id DESC";

            try (PreparedStatement ps = con.prepareStatement(dutySql)) {
                ps.setInt(1, employeeId);

                try (ResultSet rs = ps.executeQuery()) {
                    while (rs.next()) {
                        Map<String, String> row = new HashMap<String, String>();
                        row.put("duty_id", safe(rs.getObject("duty_id")));
                        row.put("verification_round_id", safe(rs.getObject("verification_round_id")));
                        row.put("duty_status", safe(rs.getObject("duty_status")));
                        row.put("scheduled_from", safe(rs.getObject("scheduled_from")));
                        row.put("scheduled_to", safe(rs.getObject("scheduled_to")));
                        row.put("instructions", safe(rs.getObject("instructions")));
                        row.put("round_code", safe(rs.getObject("round_code")));
                        row.put("round_title", safe(rs.getObject("round_title")));

                        dutyList.add(row);

                        String status = rowValue(row, "duty_status").toUpperCase(Locale.ENGLISH);
                        if ("SCHEDULED".equals(status) || "IN_PROGRESS".equals(status)) {
                            openDutyList.add(row);
                        }
                    }
                }
            }
        }

        if (hasVerification && hasAssets) {
            boolean hasOfficerEmployeeId = columnExists(con, "asset_physical_verification", "verification_officer_employee_id");
            boolean hasVerifDutyId = columnExists(con, "asset_physical_verification", "duty_id");
            boolean hasActualLocationId = columnExists(con, "asset_physical_verification", "actual_location_id");

            if (hasOfficerEmployeeId) {
                // A "Draft" is a verification record whose duty hasn't been
                // finalized (SUBMITTED/COMPLETED) yet - there's no separate
                // draft flag on the verification row itself, the duty's own
                // status is what actually gates further edits (see the
                // dutyLocked check in AddPhysicalVerificationServlet). Joining
                // it here lets the UI show which of the officer's own reports
                // can still be reopened and edited.
                String dutyStatusJoin = "";
                String dutyStatusExpression = "''";

                if (hasVerifDutyId && hasDuties) {
                    dutyStatusJoin = "LEFT JOIN physical_verification_duties d ON pv.duty_id = d.duty_id ";
                    dutyStatusExpression = "COALESCE(d.duty_status, '')";
                }

                String reportSql = "SELECT pv.verification_id, pv.asset_id, pv.verified_status, pv.review_status, "
                        + "pv.verified_on, pv.remarks, "
                        + (hasVerifDutyId ? "COALESCE(pv.duty_id, 0)" : "0") + " AS duty_id, "
                        + (hasActualLocationId ? "COALESCE(pv.actual_location_id, 0)" : "0") + " AS actual_location_id, "
                        + dutyStatusExpression + " AS duty_status, "
                        + "COALESCE(a.asset_code, '') AS asset_code, "
                        + "COALESCE(a.asset_name, '') AS asset_name "
                        + "FROM asset_physical_verification pv "
                        + "LEFT JOIN assets a ON pv.asset_id = a.asset_id "
                        + dutyStatusJoin
                        + "WHERE pv.verification_officer_employee_id = ? "
                        + "ORDER BY pv.verified_on DESC "
                        + "LIMIT 100";

                try (PreparedStatement ps = con.prepareStatement(reportSql)) {
                    ps.setInt(1, employeeId);

                    try (ResultSet rs = ps.executeQuery()) {
                        while (rs.next()) {
                            Map<String, String> row = new HashMap<String, String>();
                            row.put("verification_id", safe(rs.getObject("verification_id")));
                            row.put("asset_id", safe(rs.getObject("asset_id")));
                            row.put("verified_status", safe(rs.getObject("verified_status")));
                            row.put("review_status", safe(rs.getObject("review_status")));
                            row.put("verified_on", safe(rs.getObject("verified_on")));
                            row.put("remarks", safe(rs.getObject("remarks")));
                            row.put("duty_id", safe(rs.getObject("duty_id")));
                            row.put("actual_location_id", safe(rs.getObject("actual_location_id")));
                            row.put("duty_status", safe(rs.getObject("duty_status")));
                            row.put("asset_code", safe(rs.getObject("asset_code")));
                            row.put("asset_name", safe(rs.getObject("asset_name")));

                            String dutyStatusUpper = rowValue(row, "duty_status").toUpperCase(Locale.ENGLISH);
                            boolean isEditable = "SCHEDULED".equals(dutyStatusUpper) || "IN_PROGRESS".equals(dutyStatusUpper);
                            row.put("is_draft", isEditable ? "1" : "0");

                            myReportList.add(row);
                        }
                    }
                }
            }
        }

        if (hasRailwayLocations) {
            boolean hasLocationCode = columnExists(con, "railway_locations", "location_code");
            boolean hasOfficeName = columnExists(con, "railway_locations", "office_name");
            boolean hasLocationName = columnExists(con, "railway_locations", "location_name");

            String locationSql = "SELECT location_id, "
                    + (hasLocationCode ? "COALESCE(location_code, '')" : "''") + " AS location_code, "
                    + (hasOfficeName ? "COALESCE(office_name, '')" : "''") + " AS office_name, "
                    + (hasLocationName ? "COALESCE(location_name, '')" : "''") + " AS location_name "
                    + "FROM railway_locations "
                    + "ORDER BY location_code ASC";

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

    } catch (Exception e) {
        e.printStackTrace();
        error = "pageLoadFailed";
    }
%>

<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>My Physical Verification Duties - IR-AMS</title>

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
                    Your physical verification report was saved successfully.
                </div>
            <% } else if ("dutySubmitted".equals(success)) { %>
                <div class="pv-alert success">
                    <i class="fa-solid fa-circle-check"></i>
                    Duty marked complete and sent for review. A Super Admin, Admin or Asset Manager will approve it or send it back to you.
                </div>
            <% } %>

            <% if (error != null && !error.trim().isEmpty()) { %>
                <div class="pv-alert error">
                    <i class="fa-solid fa-triangle-exclamation"></i>
                    Action failed: <%= display(cleanLabel(error)) %>
                </div>
            <% } %>

            <section class="pv-hero">
                <h1>My Physical Verification Duties</h1>

                <p>
                    Duties assigned to you as a physical verification officer. Submit your findings for each
                    asset you verify - including any damage, mismatch or missing-asset problem you observe.
                </p>

                <div class="hero-pills">
                    <div class="hero-pill"><i class="fa-solid fa-user-check"></i> My Duties</div>
                    <div class="hero-pill"><i class="fa-solid fa-clipboard-check"></i> My Reports</div>
                </div>
            </section>

            <section class="pv-layout">

                <div class="pv-panel">
                    <div class="pv-panel-head">
                        <div>
                            <h2>Submit Verification Report</h2>
                            <p>Pick one of your open duties, search one or more assets you verified, and record what you found. The same status and remarks are recorded against every asset you select.</p>
                        </div>
                    </div>

                    <% if (openDutyList.isEmpty()) { %>

                        <div class="pv-alert warning">
                            <i class="fa-solid fa-circle-info"></i>
                            You have no open (scheduled / in-progress) physical verification duty right now.
                        </div>

                    <% } else { %>

                        <form action="AddPhysicalVerificationServlet" method="post" id="myVerificationForm">

                            <input type="hidden" name="officerEmployeeId" value="<%= employeeId %>">
                            <input type="hidden" name="verificationRoundId" id="verificationRoundId" value="0">

                            <div class="pv-form-grid">

                                <div class="pv-field">
                                    <label><i class="fa-solid fa-list-check"></i> Duty</label>

                                    <select name="dutyId" id="dutyId" required>
                                        <option value="">Select Duty</option>

                                        <%
                                            for (Map<String, String> duty : openDutyList) {
                                        %>
                                            <option value="<%= safe(rowValue(duty, "duty_id")) %>"
                                                    data-round="<%= safe(rowValue(duty, "verification_round_id")) %>"
                                                    data-round-title="<%= safe(rowValue(duty, "round_title")) %>"
                                                    data-status="<%= safe(cleanLabel(rowValue(duty, "duty_status"))) %>"
                                                    data-from="<%= safe(rowValue(duty, "scheduled_from")) %>"
                                                    data-to="<%= safe(rowValue(duty, "scheduled_to")) %>"
                                                    data-instructions="<%= safe(rowValue(duty, "instructions")) %>">
                                                Duty #<%= display(rowValue(duty, "duty_id")) %>
                                                -
                                                <%= display(rowValue(duty, "round_code")) %>
                                                (<%= display(cleanLabel(rowValue(duty, "duty_status"))) %>)
                                            </option>
                                        <%
                                            }
                                        %>
                                    </select>
                                </div>

                                <div class="pv-field full">
                                    <label><i class="fa-solid fa-cubes"></i> Asset(s)</label>

                                    <select name="assetId" id="assetId" required multiple="multiple" style="width: 100%;">
                                        <% if (qrAssetIdParam != null && qrAssetText != null) { %>
                                            <option value="<%= safe(qrAssetIdParam) %>" selected="selected"><%= display(qrAssetText) %></option>
                                        <% } %>
                                    </select>
                                    <span class="pv-field-hint">Select as many assets as you verified with the same result - each gets its own report entry.</span>
                                </div>

                                <div class="pv-field">
                                    <label><i class="fa-solid fa-location-dot"></i> Actual Location</label>

                                    <select name="actualLocationId" id="actualLocationId">
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
                                    <span class="pv-field-hint">Only if different from the system-recorded location.</span>
                                </div>

                                <div class="pv-field">
                                    <label><i class="fa-solid fa-shield-halved"></i> Verification Status</label>

                                    <select name="verifiedStatus" id="verifiedStatus" required>
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

                                    <textarea name="remarks" id="remarks"
                                              placeholder="Describe what you found - condition, mismatch, damage or missing-asset details..."></textarea>
                                </div>

                            </div>

                            <%-- Same reason as #submitProgress below - no pv-alert
                                 class up front, JS adds it only when actually editing
                                 a draft. --%>
                            <div id="editingNotice" style="display:none;">
                                <i class="fa-solid fa-pen-to-square"></i>
                                <span id="editingNoticeText"></span>
                                <button type="button" id="cancelEditBtn" class="pv-btn secondary" style="margin-left:auto;">Cancel Edit</button>
                            </div>

                            <%-- No pv-alert class here by default - that class carries
                                 `display: flex !important` from the shared stylesheet,
                                 which silently wins over an inline style="display:none"
                                 and left this rendering as a permanent empty box. The
                                 class is added by JS only once there is actually a
                                 message to show. --%>
                            <div id="submitProgress" style="display:none;"></div>

                            <div class="pv-actions">
                                <button type="submit" name="action" value="draft" class="pv-btn secondary">
                                    <i class="fa-solid fa-floppy-disk"></i>
                                    Save Draft
                                </button>

                                <button type="submit" name="action" value="submit" class="pv-btn primary">
                                    <i class="fa-solid fa-paper-plane"></i>
                                    Submit Report
                                </button>
                            </div>

                        </form>

                    <% } %>
                </div>

                <div class="pv-panel">
                    <div class="pv-panel-head">
                        <div>
                            <h2>Duty Details</h2>
                            <p>Round, schedule and instructions for the duty you pick on the left.</p>
                        </div>
                    </div>

                    <%-- No duty is ever pre-selected on page load, so this
                         placeholder always starts visible regardless of
                         whether openDutyList is empty - the JS duty-change
                         handler is what swaps it out once something is
                         actually picked. --%>
                    <div id="dutyDetailsEmpty" class="pv-alert warning">
                        <i class="fa-solid fa-circle-info"></i>
                        Select a duty to see its details here.
                    </div>

                    <div id="dutyDetailsCard" style="display:none;">
                        <div class="duty-info-list">
                            <div class="duty-info-row">
                                <span class="duty-info-label"><i class="fa-solid fa-layer-group"></i> Round</span>
                                <strong class="duty-info-value" id="dutyDetailRound">-</strong>
                            </div>
                            <div class="duty-info-row">
                                <span class="duty-info-label"><i class="fa-solid fa-circle-dot"></i> Status</span>
                                <strong class="duty-info-value" id="dutyDetailStatus">-</strong>
                            </div>
                            <div class="duty-info-row">
                                <span class="duty-info-label"><i class="fa-regular fa-calendar-days"></i> Scheduled</span>
                                <strong class="duty-info-value" id="dutyDetailSchedule">-</strong>
                            </div>
                        </div>

                        <div class="duty-info-instructions">
                            <span class="duty-info-label"><i class="fa-solid fa-clipboard-list"></i> Instructions</span>
                            <p id="dutyDetailInstructions">-</p>
                        </div>

                        <%-- Only meaningful once at least one report has been saved against
                             this duty (duty_status IN_PROGRESS) - a SCHEDULED duty has zero
                             reports yet, so there is nothing to hand off for review. Separate
                             from the Submit Report button in the form above: that one only
                             fires alongside whichever asset happens to be in that particular
                             batch, so an officer who already reported every asset across
                             earlier draft batches would otherwise have to pick one more asset
                             just to have a submit action available. This button needs no
                             asset selected at all - it just closes out the duty itself. --%>
                        <div id="dutyCompleteBox" style="display:none; margin-top:18px;">
                            <form action="CompletePhysicalVerificationDutyServlet" method="post"
                                  onsubmit="return confirm('Mark this duty as complete? It will be sent to a Super Admin, Admin or Asset Manager for review, and you won\'t be able to add more reports to it unless they send it back.');">
                                <input type="hidden" name="dutyId" id="completeDutyId" value="">
                                <button type="submit" class="pv-btn primary">
                                    <i class="fa-solid fa-flag-checkered"></i>
                                    Mark Duty as Complete
                                </button>
                            </form>
                        </div>
                    </div>

                    <div class="quick-guide">
                        <span class="duty-info-label"><i class="fa-solid fa-circle-question"></i> Quick Guide</span>
                        <ul>
                            <li>Pick your open duty, then search and select every asset you checked.</li>
                            <li>Use <strong>DAMAGED</strong>, <strong>NOT_FOUND</strong>, <strong>LOCATION_MISMATCH</strong> or <strong>EMPLOYEE_MISMATCH</strong> to flag a problem.</li>
                            <li><strong>Save Draft</strong> keeps a report editable; <strong>Submit Report</strong> locks that report in.</li>
                            <li>Once every asset is reported, use <strong>Mark Duty as Complete</strong> to send the whole duty for review.</li>
                        </ul>
                    </div>
                </div>

            </section>

            <section class="pv-panel">
                <div class="pv-panel-head">
                    <div>
                        <h2>My Assigned Duties</h2>
                        <p>All physical verification duties assigned to you.</p>
                    </div>
                </div>

                <div class="pv-table-wrap">
                    <table class="pv-table">
                        <thead>
                            <tr>
                                <th>Duty</th>
                                <th>Round</th>
                                <th>Schedule</th>
                                <th>Status</th>
                                <th>Instructions</th>
                            </tr>
                        </thead>

                        <tbody>
                            <% if (dutyList.isEmpty()) { %>
                                <tr>
                                    <td colspan="5">
                                        <strong>No physical verification duty has been assigned to you yet.</strong>
                                    </td>
                                </tr>
                            <% } else {
                                for (Map<String, String> duty : dutyList) {
                            %>
                                <tr>
                                    <td>Duty #<%= display(rowValue(duty, "duty_id")) %></td>
                                    <td>
                                        <strong><%= display(rowValue(duty, "round_code")) %></strong>
                                        <br>
                                        <span><%= display(rowValue(duty, "round_title")) %></span>
                                    </td>
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
                                    <td><%= display(shortText(rowValue(duty, "instructions"), 100)) %></td>
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
                        <h2>My Submitted Reports</h2>
                        <p>Physical verification reports you have submitted, and their review status.</p>
                    </div>
                </div>

                <div class="pv-table-wrap">
                    <table class="pv-table">
                        <thead>
                            <tr>
                                <th>Verification</th>
                                <th>Asset</th>
                                <th>Status</th>
                                <th>Report</th>
                                <th>Review</th>
                                <th>Submitted On</th>
                                <th>Remarks</th>
                                <th>Action</th>
                            </tr>
                        </thead>

                        <tbody>
                            <% if (myReportList.isEmpty()) { %>
                                <tr>
                                    <td colspan="8">
                                        <strong>You have not submitted any verification report yet.</strong>
                                    </td>
                                </tr>
                            <% } else {
                                for (Map<String, String> row : myReportList) {
                                    boolean isDraft = "1".equals(rowValue(row, "is_draft"));
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
                                    <td>
                                        <% if (isDraft) { %>
                                            <span class="badge warning">Draft</span>
                                        <% } else { %>
                                            <span class="badge success">Final</span>
                                        <% } %>
                                    </td>
                                    <td style="white-space: nowrap !important;"><%= display(cleanLabel(rowValue(row, "review_status"))) %></td>
                                    <td><%= display(rowValue(row, "verified_on")) %></td>
                                    <td><%= display(shortText(rowValue(row, "remarks"), 80)) %></td>
                                    <td style="white-space: nowrap !important;">
                                        <% if (isDraft) { %>
                                            <button type="button" class="mini-link edit-draft-btn" style="white-space: nowrap !important;"
                                                    data-duty-id="<%= safe(rowValue(row, "duty_id")) %>"
                                                    data-asset-id="<%= safe(rowValue(row, "asset_id")) %>"
                                                    data-asset-code="<%= safe(rowValue(row, "asset_code")) %>"
                                                    data-asset-name="<%= safe(rowValue(row, "asset_name")) %>"
                                                    data-status="<%= safe(rowValue(row, "verified_status")) %>"
                                                    data-location-id="<%= safe(rowValue(row, "actual_location_id")) %>"
                                                    data-remarks="<%= safe(rowValue(row, "remarks")) %>">
                                                <i class="fa-solid fa-pen"></i>
                                                Edit
                                            </button>
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

        </div>
    </main>
</div>

<script>
    const dutySelect = document.getElementById("dutyId");
    const roundInput = document.getElementById("verificationRoundId");
    const dutyDetailsEmpty = document.getElementById("dutyDetailsEmpty");
    const dutyDetailsCard = document.getElementById("dutyDetailsCard");
    const dutyDetailRound = document.getElementById("dutyDetailRound");
    const dutyDetailStatus = document.getElementById("dutyDetailStatus");
    const dutyDetailSchedule = document.getElementById("dutyDetailSchedule");
    const dutyDetailInstructions = document.getElementById("dutyDetailInstructions");
    const dutyCompleteBox = document.getElementById("dutyCompleteBox");
    const completeDutyId = document.getElementById("completeDutyId");

    if (dutySelect) {
        dutySelect.addEventListener("change", function () {
            const selected = dutySelect.options[dutySelect.selectedIndex];
            const hasDuty = selected && selected.value;

            if (roundInput) {
                roundInput.value = (hasDuty && selected.getAttribute("data-round")) || "0";
            }

            if (dutyDetailsEmpty && dutyDetailsCard) {
                // .pv-alert carries `display: flex !important` from the shared
                // stylesheet, which silently wins over a plain inline
                // `style.display` toggle - setProperty(..., 'important') is
                // required to actually hide/show it from here.
                if (hasDuty) {
                    dutyDetailsEmpty.style.setProperty("display", "none", "important");
                    dutyDetailsCard.style.setProperty("display", "block", "important");

                    var roundCode = selected.textContent.split(" - ")[1] || "";
                    dutyDetailRound.textContent = (selected.getAttribute("data-round-title") || roundCode || "N/A");
                    dutyDetailStatus.textContent = selected.getAttribute("data-status") || "N/A";

                    var from = selected.getAttribute("data-from") || "N/A";
                    var to = selected.getAttribute("data-to") || "N/A";
                    dutyDetailSchedule.textContent = from + " to " + to;

                    dutyDetailInstructions.textContent = selected.getAttribute("data-instructions") || "No specific instructions provided.";
                } else {
                    dutyDetailsEmpty.style.setProperty("display", "flex", "important");
                    dutyDetailsCard.style.setProperty("display", "none", "important");
                }
            }

            // Only offered once the duty already has at least one report saved
            // (data-status "In Progress") - a duty that's still just
            // "Scheduled" has nothing to hand off for review yet. Only
            // SCHEDULED/IN_PROGRESS duties ever appear in this dropdown at
            // all (openDutyList), so this is the only distinction that
            // actually matters here.
            if (dutyCompleteBox && completeDutyId) {
                var status = hasDuty ? (selected.getAttribute("data-status") || "") : "";
                if (hasDuty && status === "In Progress") {
                    completeDutyId.value = selected.value;
                    dutyCompleteBox.style.setProperty("display", "block", "important");
                } else {
                    completeDutyId.value = "";
                    dutyCompleteBox.style.setProperty("display", "none", "important");
                }
            }
        });
    }
</script>

<script src="https://code.jquery.com/jquery-3.6.0.min.js"></script>
<script src="https://cdn.jsdelivr.net/npm/select2@4.1.0-rc.0/dist/js/select2.min.js"></script>
<script>
    $(document).ready(function() {
        $('#assetId').select2({
            placeholder: 'Search and select one or more assets (Code, Name)',
            closeOnSelect: false,
            ajax: {
                url: 'AssetSearchServlet',
                dataType: 'json',
                delay: 250,
                data: function(params) {
                    // excludeDutyId keeps an asset already reported under the
                    // currently-selected duty out of the picker, so a fresh
                    // batch can't silently re-select and overwrite it - see
                    // AssetSearchServlet's own comment on this parameter.
                    return {
                        q: params.term,
                        page: params.page,
                        excludeDutyId: dutySelect ? dutySelect.value : ''
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

        setTimeout(function() {
            $('.pv-alert').fadeOut('slow');
            if (window.history.replaceState) {
                const url = new URL(window.location);
                url.searchParams.delete('success');
                url.searchParams.delete('error');
                window.history.replaceState({path: url.href}, '', url.href);
            }
        }, 5000);

        // Multi-asset submit: the servlet still records one verification per
        // asset, so a duty with several assets checked at once is filed as one
        // sequential batch of identical (status/remarks/location) submissions
        // rather than a form field the servlet doesn't understand. Sequential,
        // not parallel, so a mid-batch failure stops cleanly instead of leaving
        // an unpredictable subset of assets saved.
        var form = document.getElementById('myVerificationForm');
        if (form) {
            form.addEventListener('submit', function (evt) {
                evt.preventDefault();

                if (form.dataset.submitting === 'true') {
                    return;
                }

                var assetIds = $('#assetId').val() || [];
                if (assetIds.length === 0) {
                    alert('Select at least one asset.');
                    return;
                }

                var dutyId = form.dutyId.value;
                if (!dutyId) {
                    alert('Select a duty.');
                    return;
                }

                var actionValue = (evt.submitter && evt.submitter.value) || 'draft';
                var progress = document.getElementById('submitProgress');
                var buttons = form.querySelectorAll('button[type="submit"]');

                form.dataset.submitting = 'true';
                buttons.forEach(function (b) { b.disabled = true; });

                if (progress) {
                    progress.className = 'pv-alert warning';
                    progress.innerHTML = '<i class="fa-solid fa-spinner fa-spin"></i> Saving 0 / ' + assetIds.length + ' asset(s)...';
                }

                var baseFields = {
                    officerEmployeeId: form.officerEmployeeId.value,
                    verificationRoundId: form.verificationRoundId.value,
                    dutyId: dutyId,
                    actualLocationId: form.actualLocationId.value,
                    verifiedStatus: form.verifiedStatus.value,
                    remarks: form.remarks.value
                };

                function submitOne(index) {
                    if (index >= assetIds.length) {
                        if (progress) {
                            progress.innerHTML = '<i class="fa-solid fa-circle-check"></i> Saved ' + assetIds.length + ' asset(s). Redirecting...';
                        }
                        window.location.href = 'my_physical_verification_duties.jsp?success=verificationSaved';
                        return;
                    }

                    // AddPhysicalVerificationServlet locks the whole duty (SUBMITTED)
                    // the moment ANY asset in it is saved with action=submit - a real
                    // single-asset guard against adding more entries after the
                    // officer says "I'm done". A straight per-asset action=submit
                    // loop would hit that lock on the 2nd asset in the same batch, so
                    // every asset but the last one is saved as an in-progress draft
                    // (which never locks) and only the final asset carries the
                    // user's actual chosen action - the duty ends up SUBMITTED (if
                    // that's what was chosen) only once every asset is already saved.
                    var isLastAsset = index === assetIds.length - 1;
                    var fields = Object.assign({}, baseFields, {
                        assetId: assetIds[index],
                        action: isLastAsset ? actionValue : 'draft'
                    });
                    var body = new URLSearchParams(fields);

                    fetch('AddPhysicalVerificationServlet', {
                        method: 'POST',
                        credentials: 'same-origin',
                        headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
                        body: body.toString()
                    }).then(function (response) {
                        var finalUrl = response.url || '';

                        if (finalUrl.indexOf('error=') !== -1) {
                            var errorMatch = finalUrl.match(/error=([^&]+)/);
                            var errorCode = errorMatch ? decodeURIComponent(errorMatch[1]) : 'saveFailed';
                            throw new Error('Asset ' + assetIds[index] + ' failed: ' + errorCode);
                        }

                        if (progress) {
                            progress.innerHTML = '<i class="fa-solid fa-spinner fa-spin"></i> Saving ' + (index + 1) + ' / ' + assetIds.length + ' asset(s)...';
                        }

                        submitOne(index + 1);
                    }).catch(function (err) {
                        if (progress) {
                            progress.className = 'pv-alert error';
                            progress.innerHTML = '<i class="fa-solid fa-triangle-exclamation"></i> ' + err.message
                                + ' - ' + index + ' of ' + assetIds.length + ' asset(s) were saved before this failure. Reload the page to see what was recorded.';
                        }

                        form.dataset.submitting = 'false';
                        buttons.forEach(function (b) { b.disabled = false; });
                    });
                }

                submitOne(0);
            });
        }

        // "Edit" on a Draft row in My Submitted Reports: re-opens that report
        // in the form above, pre-filled, so the officer can review/change it
        // and re-save. This relies on AddPhysicalVerificationServlet finding
        // the existing row by (round, duty, asset) and UPDATing it in place
        // rather than inserting a new one - it only works for as long as the
        // duty stays open, which is exactly when a row is shown as "Draft"
        // here in the first place.
        $(document).on('click', '.edit-draft-btn', function () {
            var btn = $(this);
            var dutyId = btn.data('duty-id');
            var assetId = String(btn.data('asset-id'));
            var assetCode = btn.data('asset-code');
            var assetName = btn.data('asset-name');
            var status = btn.data('status');
            var locationId = btn.data('location-id');
            var remarksText = btn.data('remarks');

            if (dutySelect) {
                dutySelect.value = dutyId;
                dutySelect.dispatchEvent(new Event('change'));
            }

            var $asset = $('#assetId');
            $asset.empty();
            var opt = new Option(assetCode + ' - ' + assetName, assetId, true, true);
            $asset.append(opt).trigger('change');

            var statusSelect = document.getElementById('verifiedStatus');
            if (statusSelect && status) {
                statusSelect.value = status;
            }

            var locationSelect = document.getElementById('actualLocationId');
            if (locationSelect) {
                locationSelect.value = (locationId && locationId !== '0') ? String(locationId) : '0';
            }

            var remarksField = document.getElementById('remarks');
            if (remarksField) {
                remarksField.value = remarksText || '';
            }

            var notice = document.getElementById('editingNotice');
            var noticeText = document.getElementById('editingNoticeText');
            if (notice && noticeText) {
                noticeText.textContent = 'Editing your ' + assetCode + ' report on Duty #' + dutyId
                    + ' - Save Draft to keep working on it, or Submit Report to finalize.';
                notice.className = 'pv-alert warning';
            }

            document.getElementById('myVerificationForm').scrollIntoView({ behavior: 'smooth', block: 'start' });
        });

        $(document).on('click', '#cancelEditBtn', function () {
            window.location.href = 'my_physical_verification_duties.jsp';
        });
    });
</script>

<%-- Same shared topbar/sidebar scripts every other authenticated page loads
     (see physical_verification.jsp) - missing here meant clicking the
     emp006-style user-card in the topbar did nothing on this page, since
     user-dropdown.js is what turns that static name/avatar into a clickable
     Dashboard/Logout menu for every role. --%>
<script src="js/topbar-search.js?v=1"></script>
<script src="js/user-dropdown.js?v=1"></script>
<script src="js/sidebar-role.js?v=1"></script>
<script src="js/ir-body-watermark.js?v=1"></script>
<script src="js/dashboard-actions.js?v=1"></script>

</body>
</html>
