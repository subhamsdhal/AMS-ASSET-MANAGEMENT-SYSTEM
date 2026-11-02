package com.mycompany.asset_management_system_ams;

import java.io.IOException;
import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.Statement;
import java.util.ArrayList;
import java.util.List;

import jakarta.servlet.ServletException;
import jakarta.servlet.annotation.WebServlet;
import jakarta.servlet.http.HttpServlet;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import jakarta.servlet.http.HttpSession;

@WebServlet(name = "AddPhysicalVerificationServlet", urlPatterns = {"/AddPhysicalVerificationServlet"})
public class AddPhysicalVerificationServlet extends HttpServlet {

    @Override
    protected void doPost(HttpServletRequest request, HttpServletResponse response)
            throws ServletException, IOException {

        Connection con = null;
        int savedVerificationId = 0;
        boolean isSelfServiceSubmitter = false;
        String accessDeniedRedirect = "physical_verification.jsp?error=";

        try {
            request.setCharacterEncoding("UTF-8");

            HttpSession session = request.getSession(false);

            if (session == null
                    || session.getAttribute("username") == null
                    || session.getAttribute("role") == null) {
                response.sendRedirect("login.jsp");
                return;
            }

            String username = String.valueOf(session.getAttribute("username"));
            String role = String.valueOf(session.getAttribute("role"));
            int userId = getSessionUserId(session);

            int verificationRoundId = parseIntSafe(request.getParameter("verificationRoundId"), 0);
            int dutyId = parseIntSafe(request.getParameter("dutyId"), 0);
            int assetId = parseIntSafe(request.getParameter("assetId"), 0);
            int actualLocationId = parseIntSafe(request.getParameter("actualLocationId"), 0);
            int actualEmployeeId = parseIntSafe(request.getParameter("actualEmployeeId"), 0);
            int officerEmployeeId = parseIntSafe(request.getParameter("officerEmployeeId"), 0);

            String action = request.getParameter("action");
            boolean isSubmitFinal = "submit".equals(action);

            String verifiedStatus = cleanText(request.getParameter("verifiedStatus")).toUpperCase();
            String remarks = cleanText(request.getParameter("remarks"));

            // Two ways in: the full management form (SUPER_ADMIN/ADMIN/ASSET_MANAGER,
            // free choice of officer/duty) or a self-service submission by the officer
            // a duty was actually assigned to (any role - the scheduler's officer
            // dropdown accepts any active employee). Self-service callers can only ever
            // act on their own assigned duty, and officerEmployeeId is forced to their
            // own employee_id server-side regardless of what was posted, so one
            // employee can never submit a report under another employee's identity.
            boolean isManagementSubmitter = isAllowedSubmitter(role);
            int selfEmployeeId = getSessionEmployeeId(session);

            if (!isManagementSubmitter) {
                if (dutyId <= 0 || selfEmployeeId <= 0) {
                    response.sendRedirect("physical_verification.jsp?error=submitAccessDenied");
                    return;
                }

                con = DBConnection.getConnection();

                int dutyOfficerEmployeeId = getDutyOfficerEmployeeId(con, dutyId);

                if (dutyOfficerEmployeeId <= 0 || dutyOfficerEmployeeId != selfEmployeeId) {
                    response.sendRedirect("my_physical_verification_duties.jsp?error=submitAccessDenied");
                    return;
                }

                isSelfServiceSubmitter = true;
                officerEmployeeId = selfEmployeeId;
            }

            accessDeniedRedirect = isSelfServiceSubmitter
                    ? "my_physical_verification_duties.jsp?error="
                    : "physical_verification.jsp?error=";

            if (assetId <= 0) {
                response.sendRedirect(accessDeniedRedirect + "selectAsset");
                return;
            }

            if (officerEmployeeId <= 0) {
                response.sendRedirect(accessDeniedRedirect + "selectOfficer");
                return;
            }

            if (!isValidVerificationStatus(verifiedStatus)) {
                response.sendRedirect(accessDeniedRedirect + "invalidStatus");
                return;
            }

            if (con == null) {
                con = DBConnection.getConnection();
            }
            con.setAutoCommit(false);

            if (!tableExists(con, "asset_physical_verification")) {
                con.rollback();
                response.sendRedirect(accessDeniedRedirect + "tableMissing");
                return;
            }

            boolean hasRoundId = isWritableColumn(con, "asset_physical_verification", "verification_round_id");
            boolean hasDutyId = isWritableColumn(con, "asset_physical_verification", "duty_id");
            boolean hasVerifiedStatus = isWritableColumn(con, "asset_physical_verification", "verified_status");
            boolean hasVerifiedByUserId = isWritableColumn(con, "asset_physical_verification", "verified_by_user_id");
            boolean hasActualLocationId = isWritableColumn(con, "asset_physical_verification", "actual_location_id");
            boolean hasActualEmployeeId = isWritableColumn(con, "asset_physical_verification", "actual_employee_id");
            boolean hasOfficerEmployeeId = isWritableColumn(con, "asset_physical_verification", "verification_officer_employee_id");
            boolean hasOfficerDepartmentId = isWritableColumn(con, "asset_physical_verification", "verification_officer_department_id");
            boolean hasVerifiedOn = isWritableColumn(con, "asset_physical_verification", "verified_on");
            boolean hasRemarks = isWritableColumn(con, "asset_physical_verification", "remarks");

            /*
             * IMPORTANT:
             * Do not insert/update review_status.
             * In your database it is not updatable, most likely generated/calculated.
             */

            if (hasRoundId && verificationRoundId <= 0) {
                verificationRoundId = getOrCreateDefaultRound(con, userId);

                if (verificationRoundId <= 0) {
                    verificationRoundId = getAnyExistingRoundId(con);
                }
            }

            if (hasRoundId
                    && verificationRoundId <= 0
                    && !isColumnNullable(con, "asset_physical_verification", "verification_round_id")) {
                con.rollback();
                response.sendRedirect(accessDeniedRedirect + "roundError");
                return;
            }

            if (dutyId > 0 && officerEmployeeId <= 0) {
                officerEmployeeId = getDutyOfficerEmployeeId(con, dutyId);
            }

            int officerDepartmentId = getEmployeeDepartmentId(con, officerEmployeeId);

            if (hasOfficerDepartmentId
                    && officerDepartmentId <= 0
                    && !isColumnNullable(con, "asset_physical_verification", "verification_officer_department_id")) {
                con.rollback();
                response.sendRedirect(accessDeniedRedirect + "officerDepartmentMissing");
                return;
            }

            String safeVerifiedStatus = getSafeVerificationStatus(con, verifiedStatus);

            if (dutyId > 0) {
                String currentDutyStatus = getDutyStatus(con, dutyId);
                if ("SUBMITTED".equals(currentDutyStatus) || "COMPLETED".equals(currentDutyStatus)) {
                    con.rollback();
                    response.sendRedirect(accessDeniedRedirect + "dutyLocked");
                    return;
                }
            }

            savedVerificationId = findExistingVerificationId(
                    con,
                    hasRoundId,
                    hasDutyId,
                    verificationRoundId,
                    dutyId,
                    assetId
            );

            if (savedVerificationId > 0) {
                updateVerificationRecord(
                        con,
                        savedVerificationId,
                        assetId,
                        verificationRoundId,
                        dutyId,
                        safeVerifiedStatus,
                        userId,
                        actualLocationId,
                        actualEmployeeId,
                        officerEmployeeId,
                        officerDepartmentId,
                        remarks,
                        hasRoundId,
                        hasDutyId,
                        hasVerifiedStatus,
                        hasVerifiedByUserId,
                        hasActualLocationId,
                        hasActualEmployeeId,
                        hasOfficerEmployeeId,
                        hasOfficerDepartmentId,
                        hasVerifiedOn,
                        hasRemarks
                );
            } else {
                savedVerificationId = insertVerificationRecord(
                        con,
                        assetId,
                        verificationRoundId,
                        dutyId,
                        safeVerifiedStatus,
                        userId,
                        actualLocationId,
                        actualEmployeeId,
                        officerEmployeeId,
                        officerDepartmentId,
                        remarks,
                        hasRoundId,
                        hasDutyId,
                        hasVerifiedStatus,
                        hasVerifiedByUserId,
                        hasActualLocationId,
                        hasActualEmployeeId,
                        hasOfficerEmployeeId,
                        hasOfficerDepartmentId,
                        hasVerifiedOn,
                        hasRemarks
                );
            }

            // Fault (Medium, fixed): this used to run unconditionally for both a
            // draft save AND a final submit - meaning saving a mere DRAFT with
            // verifiedStatus=DAMAGED immediately flipped the real asset's live
            // service_status system-wide, before the verifier had even clicked
            // Submit, let alone before anyone reviewed it. A draft is, by
            // definition, not yet final - it must not mutate the live asset
            // record. See audit/07-physical-verification.md Finding 1.
            if (isSubmitFinal) {
                updateAssetAfterVerification(con, assetId, safeVerifiedStatus);
            }
            if (dutyId > 0) {
                updateDutyStatus(con, dutyId, isSubmitFinal ? "SUBMITTED" : "IN_PROGRESS");
            }

            con.commit();

            safeAuditLog(
                    userId,
                    isSubmitFinal ? "PHYSICAL_VERIFICATION_SUBMITTED" : "PHYSICAL_VERIFICATION_DRAFT",
                    "asset_physical_verification",
                    savedVerificationId,
                    "Physical verification " + (isSubmitFinal ? "submitted" : "saved as draft") + " for asset ID "
                    + assetId
                    + " with status "
                    + safeVerifiedStatus
                    + " by "
                    + username
            );

            if (isSelfServiceSubmitter) {
                // view_verification.jsp is not in a self-service submitter's RBAC
                // allowlist (verificationViewOps excludes EMPLOYEE) - send them back to
                // their own duty list instead, where the submission now shows up under
                // "My Submitted Reports".
                response.sendRedirect("my_physical_verification_duties.jsp?success=verificationSaved");
            } else if (savedVerificationId > 0) {
                response.sendRedirect("view_verification.jsp?id=" + savedVerificationId);
            } else {
                response.sendRedirect("physical_verification.jsp?success=verificationSaved");
            }

        } catch (Exception e) {
            e.printStackTrace();

            try {
                if (con != null) {
                    con.rollback();
                }
            } catch (Exception rollbackEx) {
                rollbackEx.printStackTrace();
            }

            response.sendRedirect(accessDeniedRedirect + "saveFailed");

        } finally {
            try {
                if (con != null) {
                    con.setAutoCommit(true);
                    con.close();
                }
            } catch (Exception closeEx) {
                closeEx.printStackTrace();
            }
        }
    }

    private int insertVerificationRecord(
            Connection con,
            int assetId,
            int verificationRoundId,
            int dutyId,
            String safeVerifiedStatus,
            int userId,
            int actualLocationId,
            int actualEmployeeId,
            int officerEmployeeId,
            int officerDepartmentId,
            String remarks,
            boolean hasRoundId,
            boolean hasDutyId,
            boolean hasVerifiedStatus,
            boolean hasVerifiedByUserId,
            boolean hasActualLocationId,
            boolean hasActualEmployeeId,
            boolean hasOfficerEmployeeId,
            boolean hasOfficerDepartmentId,
            boolean hasVerifiedOn,
            boolean hasRemarks) throws Exception {

        StringBuilder insertColumns = new StringBuilder();
        StringBuilder insertValues = new StringBuilder();

        appendColumn(insertColumns, insertValues, "asset_id", "?");

        if (hasRoundId) {
            appendColumn(insertColumns, insertValues, "verification_round_id", "?");
        }

        if (hasDutyId) {
            appendColumn(insertColumns, insertValues, "duty_id", "?");
        }

        if (hasVerifiedStatus) {
            appendColumn(insertColumns, insertValues, "verified_status", "?");
        }

        if (hasVerifiedByUserId) {
            appendColumn(insertColumns, insertValues, "verified_by_user_id", "?");
        }

        if (hasActualLocationId) {
            appendColumn(insertColumns, insertValues, "actual_location_id", "?");
        }

        if (hasActualEmployeeId) {
            appendColumn(insertColumns, insertValues, "actual_employee_id", "?");
        }

        if (hasOfficerEmployeeId) {
            appendColumn(insertColumns, insertValues, "verification_officer_employee_id", "?");
        }

        if (hasOfficerDepartmentId) {
            appendColumn(insertColumns, insertValues, "verification_officer_department_id", "?");
        }

        if (hasVerifiedOn) {
            appendColumn(insertColumns, insertValues, "verified_on", "CURRENT_TIMESTAMP");
        }

        if (hasRemarks) {
            appendColumn(insertColumns, insertValues, "remarks", "?");
        }

        String insertSql = "INSERT INTO asset_physical_verification ("
                + insertColumns
                + ") VALUES ("
                + insertValues
                + ")";

        int savedVerificationId = 0;

        try (PreparedStatement ps = con.prepareStatement(insertSql, Statement.RETURN_GENERATED_KEYS)) {

            int index = 1;

            ps.setInt(index++, assetId);

            if (hasRoundId) {
                if (verificationRoundId <= 0) {
                    ps.setNull(index++, java.sql.Types.INTEGER);
                } else {
                    ps.setInt(index++, verificationRoundId);
                }
            }

            if (hasDutyId) {
                if (dutyId <= 0) {
                    ps.setNull(index++, java.sql.Types.INTEGER);
                } else {
                    ps.setInt(index++, dutyId);
                }
            }

            if (hasVerifiedStatus) {
                ps.setString(index++, safeVerifiedStatus);
            }

            if (hasVerifiedByUserId) {
                ps.setInt(index++, userId);
            }

            if (hasActualLocationId) {
                if (actualLocationId <= 0) {
                    ps.setNull(index++, java.sql.Types.INTEGER);
                } else {
                    ps.setInt(index++, actualLocationId);
                }
            }

            if (hasActualEmployeeId) {
                if (actualEmployeeId <= 0) {
                    ps.setNull(index++, java.sql.Types.INTEGER);
                } else {
                    ps.setInt(index++, actualEmployeeId);
                }
            }

            if (hasOfficerEmployeeId) {
                ps.setInt(index++, officerEmployeeId);
            }

            if (hasOfficerDepartmentId) {
                if (officerDepartmentId <= 0) {
                    ps.setNull(index++, java.sql.Types.INTEGER);
                } else {
                    ps.setInt(index++, officerDepartmentId);
                }
            }

            if (hasRemarks) {
                ps.setString(index++, remarks);
            }

            ps.executeUpdate();

            try (ResultSet keys = ps.getGeneratedKeys()) {
                if (keys.next()) {
                    savedVerificationId = keys.getInt(1);
                }
            }
        }

        return savedVerificationId;
    }

    private void updateVerificationRecord(
            Connection con,
            int savedVerificationId,
            int assetId,
            int verificationRoundId,
            int dutyId,
            String safeVerifiedStatus,
            int userId,
            int actualLocationId,
            int actualEmployeeId,
            int officerEmployeeId,
            int officerDepartmentId,
            String remarks,
            boolean hasRoundId,
            boolean hasDutyId,
            boolean hasVerifiedStatus,
            boolean hasVerifiedByUserId,
            boolean hasActualLocationId,
            boolean hasActualEmployeeId,
            boolean hasOfficerEmployeeId,
            boolean hasOfficerDepartmentId,
            boolean hasVerifiedOn,
            boolean hasRemarks) throws Exception {

        StringBuilder updateSql = new StringBuilder();
        updateSql.append("UPDATE asset_physical_verification SET asset_id = ?");

        if (hasRoundId) {
            updateSql.append(", verification_round_id = ?");
        }

        if (hasDutyId) {
            updateSql.append(", duty_id = ?");
        }

        if (hasVerifiedStatus) {
            updateSql.append(", verified_status = ?");
        }

        if (hasVerifiedByUserId) {
            updateSql.append(", verified_by_user_id = ?");
        }

        if (hasActualLocationId) {
            updateSql.append(", actual_location_id = ?");
        }

        if (hasActualEmployeeId) {
            updateSql.append(", actual_employee_id = ?");
        }

        if (hasOfficerEmployeeId) {
            updateSql.append(", verification_officer_employee_id = ?");
        }

        if (hasOfficerDepartmentId) {
            updateSql.append(", verification_officer_department_id = ?");
        }

        if (hasVerifiedOn) {
            updateSql.append(", verified_on = CURRENT_TIMESTAMP");
        }

        if (hasRemarks) {
            updateSql.append(", remarks = ?");
        }

        updateSql.append(" WHERE verification_id = ?");

        try (PreparedStatement ps = con.prepareStatement(updateSql.toString())) {

            int index = 1;

            ps.setInt(index++, assetId);

            if (hasRoundId) {
                if (verificationRoundId <= 0) {
                    ps.setNull(index++, java.sql.Types.INTEGER);
                } else {
                    ps.setInt(index++, verificationRoundId);
                }
            }

            if (hasDutyId) {
                if (dutyId <= 0) {
                    ps.setNull(index++, java.sql.Types.INTEGER);
                } else {
                    ps.setInt(index++, dutyId);
                }
            }

            if (hasVerifiedStatus) {
                ps.setString(index++, safeVerifiedStatus);
            }

            if (hasVerifiedByUserId) {
                ps.setInt(index++, userId);
            }

            if (hasActualLocationId) {
                if (actualLocationId <= 0) {
                    ps.setNull(index++, java.sql.Types.INTEGER);
                } else {
                    ps.setInt(index++, actualLocationId);
                }
            }

            if (hasActualEmployeeId) {
                if (actualEmployeeId <= 0) {
                    ps.setNull(index++, java.sql.Types.INTEGER);
                } else {
                    ps.setInt(index++, actualEmployeeId);
                }
            }

            if (hasOfficerEmployeeId) {
                ps.setInt(index++, officerEmployeeId);
            }

            if (hasOfficerDepartmentId) {
                if (officerDepartmentId <= 0) {
                    ps.setNull(index++, java.sql.Types.INTEGER);
                } else {
                    ps.setInt(index++, officerDepartmentId);
                }
            }

            if (hasRemarks) {
                ps.setString(index++, remarks);
            }

            ps.setInt(index++, savedVerificationId);

            ps.executeUpdate();
        }
    }

    private boolean isAllowedSubmitter(String role) {
        return ("SUPER_ADMIN".equals(role) || "ADMIN".equals(role))
                || "ASSET_MANAGER".equalsIgnoreCase(role);
    }

    private int getSessionUserId(HttpSession session) {
        // Default of 0 (not 1) on a missing session attribute - see the same
        // fix applied across the Asset Requests module for why 1 is unsafe here.
        try {
            Object userIdObj = session.getAttribute("user_id");

            if (userIdObj == null) {
                userIdObj = session.getAttribute("userId");
            }

            if (userIdObj == null) {
                return 0;
            }

            return Integer.parseInt(String.valueOf(userIdObj));
        } catch (Exception e) {
            return 0;
        }
    }

    private int getSessionEmployeeId(HttpSession session) {
        try {
            Object employeeIdObj = session.getAttribute("employee_id");

            if (employeeIdObj == null) {
                return 0;
            }

            return Integer.parseInt(String.valueOf(employeeIdObj));
        } catch (Exception e) {
            return 0;
        }
    }

    private int parseIntSafe(String value, int defaultValue) {
        try {
            if (value == null || value.trim().isEmpty()) {
                return defaultValue;
            }

            return Integer.parseInt(value.trim());
        } catch (Exception e) {
            return defaultValue;
        }
    }

    private String cleanText(String value) {
        if (value == null) {
            return "";
        }

        return value.trim();
    }

    private boolean isValidVerificationStatus(String status) {
        return "VERIFIED".equals(status)
                || "LOCATION_MISMATCH".equals(status)
                || "EMPLOYEE_MISMATCH".equals(status)
                || "NOT_FOUND".equals(status)
                || "DAMAGED".equals(status)
                || "UNDER_REPAIR".equals(status)
                || "NEEDS_REVIEW".equals(status);
    }

    private String getSafeVerificationStatus(Connection con, String requestedStatus) {
        try {
            if (!columnExists(con, "asset_physical_verification", "verified_status")) {
                return requestedStatus;
            }

            String columnType = getColumnType(con, "asset_physical_verification", "verified_status");

            if (columnType != null && columnType.toLowerCase().startsWith("enum")) {
                List<String> values = parseEnumValues(columnType);

                if (values.contains(requestedStatus)) {
                    return requestedStatus;
                }

                if (values.contains("VERIFIED")) {
                    return "VERIFIED";
                }

                if (!values.isEmpty()) {
                    return values.get(0);
                }
            }
        } catch (Exception e) {
            e.printStackTrace();
        }

        return requestedStatus;
    }

    private int getOrCreateDefaultRound(Connection con, int userId) {

        try {
            if (!tableExists(con, "physical_verification_rounds")) {
                return 0;
            }

            if (!columnExists(con, "physical_verification_rounds", "verification_round_id")) {
                return 0;
            }

            String currentYear = String.valueOf(java.time.LocalDate.now().getYear());
            String roundCode = "PV-HQ-" + currentYear + "-AUTO";

            if (columnExists(con, "physical_verification_rounds", "round_code")) {

                String findSql = "SELECT verification_round_id "
                        + "FROM physical_verification_rounds "
                        + "WHERE round_code = ? "
                        + "LIMIT 1";

                try (PreparedStatement ps = con.prepareStatement(findSql)) {
                    ps.setString(1, roundCode);

                    try (ResultSet rs = ps.executeQuery()) {
                        if (rs.next()) {
                            return rs.getInt("verification_round_id");
                        }
                    }
                }
            }

            String safeVerificationType = getSafeRoundValue(
                    con,
                    "verification_type",
                    new String[]{"ANNUAL", "FULL", "GENERAL", "PHYSICAL", "STOCK", "SCHEDULED"},
                    "ANNUAL"
            );

            String safeRoundStatus = getSafeRoundValue(
                    con,
                    "status",
                    new String[]{"IN_PROGRESS", "ACTIVE", "OPEN", "SCHEDULED", "PENDING"},
                    "IN_PROGRESS"
            );

            boolean hasRoundCode = isWritableColumn(con, "physical_verification_rounds", "round_code");
            boolean hasRoundTitle = isWritableColumn(con, "physical_verification_rounds", "round_title");
            boolean hasVerificationType = isWritableColumn(con, "physical_verification_rounds", "verification_type");
            boolean hasStartDate = isWritableColumn(con, "physical_verification_rounds", "start_date");
            boolean hasEndDate = isWritableColumn(con, "physical_verification_rounds", "end_date");
            boolean hasStatus = isWritableColumn(con, "physical_verification_rounds", "status");
            boolean hasCreatedBy = isWritableColumn(con, "physical_verification_rounds", "created_by_user_id");

            StringBuilder columns = new StringBuilder();
            StringBuilder values = new StringBuilder();

            if (hasRoundCode) {
                appendColumn(columns, values, "round_code", "?");
            }

            if (hasRoundTitle) {
                appendColumn(columns, values, "round_title", "?");
            }

            if (hasVerificationType) {
                appendColumn(columns, values, "verification_type", "?");
            }

            if (hasStartDate) {
                appendColumn(columns, values, "start_date", "CURDATE()");
            }

            if (hasEndDate) {
                appendColumn(columns, values, "end_date", "NULL");
            }

            if (hasStatus) {
                appendColumn(columns, values, "status", "?");
            }

            if (hasCreatedBy) {
                appendColumn(columns, values, "created_by_user_id", "?");
            }

            if (columns.length() == 0) {
                return 0;
            }

            String insertSql = "INSERT INTO physical_verification_rounds ("
                    + columns
                    + ") VALUES ("
                    + values
                    + ")";

            try (PreparedStatement ps = con.prepareStatement(insertSql, Statement.RETURN_GENERATED_KEYS)) {

                int index = 1;

                if (hasRoundCode) {
                    ps.setString(index++, roundCode);
                }

                if (hasRoundTitle) {
                    ps.setString(index++, "Rail Sadan Headquarters Physical Verification " + currentYear);
                }

                if (hasVerificationType) {
                    ps.setString(index++, safeVerificationType);
                }

                if (hasStatus) {
                    ps.setString(index++, safeRoundStatus);
                }

                if (hasCreatedBy) {
                    ps.setInt(index++, userId);
                }

                ps.executeUpdate();

                try (ResultSet keys = ps.getGeneratedKeys()) {
                    if (keys.next()) {
                        return keys.getInt(1);
                    }
                }
            }

        } catch (Exception e) {
            e.printStackTrace();
        }

        return 0;
    }

    private String getSafeRoundValue(Connection con, String columnName, String[] preferred, String fallback) {
        try {
            if (!columnExists(con, "physical_verification_rounds", columnName)) {
                return fallback;
            }

            String columnType = getColumnType(con, "physical_verification_rounds", columnName);

            if (columnType != null && columnType.toLowerCase().startsWith("enum")) {
                List<String> values = parseEnumValues(columnType);

                for (String value : preferred) {
                    if (values.contains(value)) {
                        return value;
                    }
                }

                if (!values.isEmpty()) {
                    return values.get(0);
                }
            }
        } catch (Exception e) {
            e.printStackTrace();
        }

        return fallback;
    }

    private int getAnyExistingRoundId(Connection con) {
        try {
            if (!tableExists(con, "physical_verification_rounds")) {
                return 0;
            }

            if (!columnExists(con, "physical_verification_rounds", "verification_round_id")) {
                return 0;
            }

            String sql = "SELECT verification_round_id "
                    + "FROM physical_verification_rounds "
                    + "ORDER BY verification_round_id DESC "
                    + "LIMIT 1";

            try (PreparedStatement ps = con.prepareStatement(sql);
                 ResultSet rs = ps.executeQuery()) {

                if (rs.next()) {
                    return rs.getInt("verification_round_id");
                }
            }

        } catch (Exception e) {
            e.printStackTrace();
        }

        return 0;
    }

    private int getEmployeeDepartmentId(Connection con, int employeeId) {

        try {
            if (employeeId <= 0 || !tableExists(con, "employees")) {
                return 0;
            }

            if (!columnExists(con, "employees", "department_id")) {
                return 0;
            }

            String sql = "SELECT department_id "
                    + "FROM employees "
                    + "WHERE employee_id = ? "
                    + "LIMIT 1";

            try (PreparedStatement ps = con.prepareStatement(sql)) {
                ps.setInt(1, employeeId);

                try (ResultSet rs = ps.executeQuery()) {
                    if (rs.next()) {
                        return rs.getInt("department_id");
                    }
                }
            }

        } catch (Exception e) {
            e.printStackTrace();
        }

        return 0;
    }

    private int getDutyOfficerEmployeeId(Connection con, int dutyId) throws Exception {

        if (dutyId <= 0 || !tableExists(con, "physical_verification_duties")) {
            return 0;
        }

        if (!columnExists(con, "physical_verification_duties", "assigned_employee_id")) {
            return 0;
        }

        String sql = "SELECT assigned_employee_id "
                + "FROM physical_verification_duties "
                + "WHERE duty_id = ? "
                + "LIMIT 1";

        try (PreparedStatement ps = con.prepareStatement(sql)) {
            ps.setInt(1, dutyId);

            try (ResultSet rs = ps.executeQuery()) {
                if (rs.next()) {
                    return rs.getInt("assigned_employee_id");
                }
            }
        }

        return 0;
    }

    private int findExistingVerificationId(Connection con, boolean hasRoundId, boolean hasDutyId,
            int roundId, int dutyId, int assetId) throws Exception {

        if (hasRoundId && hasDutyId && roundId > 0 && dutyId > 0) {
            String sql = "SELECT verification_id "
                    + "FROM asset_physical_verification "
                    + "WHERE verification_round_id = ? "
                    + "AND duty_id = ? "
                    + "AND asset_id = ? "
                    + "ORDER BY verification_id DESC "
                    + "LIMIT 1";

            try (PreparedStatement ps = con.prepareStatement(sql)) {
                ps.setInt(1, roundId);
                ps.setInt(2, dutyId);
                ps.setInt(3, assetId);

                try (ResultSet rs = ps.executeQuery()) {
                    if (rs.next()) {
                        return rs.getInt("verification_id");
                    }
                }
            }
        }

        // Fault (fixed): this fallback used to match on round+asset alone,
        // with no duty involved at all - so submitting the same asset under a
        // DIFFERENT duty within the same round (e.g. re-verified in a later
        // duty, or picked twice across two officers' duties) would silently
        // find and overwrite a completely unrelated existing record instead
        // of inserting a new one - including one that had already been
        // reviewed/approved, corrupting its status/remarks and re-pointing
        // its duty_id. Only reachable now when the caller genuinely has no
        // duty to scope by at all (dutyId <= 0, the admin form's "No Duty /
        // Direct Verification" option) - any duty-linked submission is
        // required to go through the exact round+duty+asset match above or
        // insert a fresh row, never fall back to this looser one.
        if (hasRoundId && roundId > 0 && dutyId <= 0) {
            String sql = "SELECT verification_id "
                    + "FROM asset_physical_verification "
                    + "WHERE verification_round_id = ? "
                    + "AND asset_id = ? "
                    + (hasDutyId ? "AND (duty_id IS NULL OR duty_id <= 0) " : "")
                    + "ORDER BY verification_id DESC "
                    + "LIMIT 1";

            try (PreparedStatement ps = con.prepareStatement(sql)) {
                ps.setInt(1, roundId);
                ps.setInt(2, assetId);

                try (ResultSet rs = ps.executeQuery()) {
                    if (rs.next()) {
                        return rs.getInt("verification_id");
                    }
                }
            }
        }

        return 0;
    }

    private void updateAssetAfterVerification(Connection con, int assetId, String verifiedStatus) {

        try {
            if (!tableExists(con, "assets")) {
                return;
            }

            boolean hasServiceStatus = isWritableColumn(con, "assets", "service_status");
            boolean hasLastPvDate = isWritableColumn(con, "assets", "last_physical_verification_date");
            boolean hasAssetStatus = isWritableColumn(con, "assets", "asset_status");

            String assetStatus = null;
            String serviceStatus = null;

            if ("VERIFIED".equals(verifiedStatus)) {
                serviceStatus = "SERVICEABLE";
            } else if ("DAMAGED".equals(verifiedStatus)) {
                serviceStatus = "NEEDS_ATTENTION";
            } else if ("UNDER_REPAIR".equals(verifiedStatus)) {
                assetStatus = "UNDER_MAINTENANCE";
                serviceStatus = "UNDER_REPAIR";
            } else if ("NOT_FOUND".equals(verifiedStatus)
                    || "LOCATION_MISMATCH".equals(verifiedStatus)
                    || "EMPLOYEE_MISMATCH".equals(verifiedStatus)
                    || "NEEDS_REVIEW".equals(verifiedStatus)) {
                serviceStatus = "NEEDS_ATTENTION";
            }

            if (assetStatus != null) {
                assetStatus = getSafeColumnValue(con, "assets", "asset_status", assetStatus);
            }

            if (serviceStatus != null) {
                serviceStatus = getSafeColumnValue(con, "assets", "service_status", serviceStatus);
            }

            StringBuilder sql = new StringBuilder("UPDATE assets SET asset_id = asset_id");

            if (assetStatus != null && hasAssetStatus) {
                sql.append(", asset_status = ?");
            }

            if (serviceStatus != null && hasServiceStatus) {
                sql.append(", service_status = ?");
            }

            if (hasLastPvDate) {
                sql.append(", last_physical_verification_date = CURDATE()");
            }

            sql.append(" WHERE asset_id = ?");

            try (PreparedStatement ps = con.prepareStatement(sql.toString())) {

                int index = 1;

                if (assetStatus != null && hasAssetStatus) {
                    ps.setString(index++, assetStatus);
                }

                if (serviceStatus != null && hasServiceStatus) {
                    ps.setString(index++, serviceStatus);
                }

                ps.setInt(index++, assetId);
                ps.executeUpdate();
            }

        } catch (Exception e) {
            e.printStackTrace();
        }
    }

    private String getDutyStatus(Connection con, int dutyId) {
        String sql = "SELECT duty_status FROM physical_verification_duties WHERE duty_id = ?";
        try (PreparedStatement ps = con.prepareStatement(sql)) {
            ps.setInt(1, dutyId);
            try (ResultSet rs = ps.executeQuery()) {
                if (rs.next()) {
                    return rs.getString("duty_status");
                }
            }
        } catch (Exception e) {
            e.printStackTrace();
        }
        return "";
    }

    private void updateDutyStatus(Connection con, int dutyId, String newStatus) {

        try {
            if (dutyId <= 0 || !tableExists(con, "physical_verification_duties")) {
                return;
            }

            if (!isWritableColumn(con, "physical_verification_duties", "duty_status")) {
                return;
            }

            String safeStatus = getSafeColumnValue(
                    con,
                    "physical_verification_duties",
                    "duty_status",
                    newStatus
            );

            if (safeStatus == null || safeStatus.trim().isEmpty()) {
                return;
            }

            String sql = "UPDATE physical_verification_duties "
                    + "SET duty_status = ? "
                    + "WHERE duty_id = ?";

            try (PreparedStatement ps = con.prepareStatement(sql)) {
                ps.setString(1, safeStatus);
                ps.setInt(2, dutyId);
                ps.executeUpdate();
            }

        } catch (Exception e) {
            e.printStackTrace();
        }
    }

    private void safeAuditLog(int userId, String action, String tableName, int recordId, String description) {
        try {
            AuditDAO.log(userId, action, tableName, recordId, description);
        } catch (Exception e) {
            e.printStackTrace();
        }
    }

    private void appendColumn(StringBuilder columns, StringBuilder values, String column, String valueExpression) {

        if (columns.length() > 0) {
            columns.append(", ");
            values.append(", ");
        }

        columns.append(column);
        values.append(valueExpression);
    }

    private boolean tableExists(Connection con, String tableName) {
        String sql = "SELECT COUNT(*) FROM information_schema.tables "
                + "WHERE table_schema = DATABASE() "
                + "AND table_name = ?";

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

    private boolean isWritableColumn(Connection con, String tableName, String columnName) {
        String sql = "SELECT EXTRA, GENERATION_EXPRESSION "
                + "FROM information_schema.columns "
                + "WHERE table_schema = DATABASE() "
                + "AND table_name = ? "
                + "AND column_name = ? "
                + "LIMIT 1";

        try (PreparedStatement ps = con.prepareStatement(sql)) {
            ps.setString(1, tableName);
            ps.setString(2, columnName);

            try (ResultSet rs = ps.executeQuery()) {
                if (rs.next()) {
                    String extra = rs.getString("EXTRA");
                    String generationExpression = rs.getString("GENERATION_EXPRESSION");

                    if (extra != null && extra.toLowerCase().contains("generated")) {
                        return false;
                    }

                    if (generationExpression != null && !generationExpression.trim().isEmpty()) {
                        return false;
                    }

                    return true;
                }
            }

        } catch (Exception e) {
            e.printStackTrace();
        }

        return false;
    }

    private boolean isColumnNullable(Connection con, String tableName, String columnName) {
        String sql = "SELECT IS_NULLABLE "
                + "FROM information_schema.columns "
                + "WHERE table_schema = DATABASE() "
                + "AND table_name = ? "
                + "AND column_name = ? "
                + "LIMIT 1";

        try (PreparedStatement ps = con.prepareStatement(sql)) {
            ps.setString(1, tableName);
            ps.setString(2, columnName);

            try (ResultSet rs = ps.executeQuery()) {
                if (rs.next()) {
                    return "YES".equalsIgnoreCase(rs.getString("IS_NULLABLE"));
                }
            }

        } catch (Exception e) {
            e.printStackTrace();
        }

        return true;
    }

    private String getColumnType(Connection con, String tableName, String columnName) {
        String sql = "SELECT COLUMN_TYPE "
                + "FROM information_schema.columns "
                + "WHERE table_schema = DATABASE() "
                + "AND table_name = ? "
                + "AND column_name = ? "
                + "LIMIT 1";

        try (PreparedStatement ps = con.prepareStatement(sql)) {
            ps.setString(1, tableName);
            ps.setString(2, columnName);

            try (ResultSet rs = ps.executeQuery()) {
                if (rs.next()) {
                    return rs.getString("COLUMN_TYPE");
                }
            }

        } catch (Exception e) {
            e.printStackTrace();
        }

        return "";
    }

    private String getSafeColumnValue(Connection con, String tableName, String columnName, String requestedValue) {
        try {
            if (!columnExists(con, tableName, columnName)) {
                return requestedValue;
            }

            String columnType = getColumnType(con, tableName, columnName);

            if (columnType != null && columnType.toLowerCase().startsWith("enum")) {
                List<String> values = parseEnumValues(columnType);

                if (values.contains(requestedValue)) {
                    return requestedValue;
                }

                if (!values.isEmpty()) {
                    return values.get(0);
                }
            }

        } catch (Exception e) {
            e.printStackTrace();
        }

        return requestedValue;
    }

    private List<String> parseEnumValues(String columnType) {
        List<String> values = new ArrayList<>();

        if (columnType == null) {
            return values;
        }

        String text = columnType.trim();

        if (!text.toLowerCase().startsWith("enum(")) {
            return values;
        }

        text = text.substring(5, text.length() - 1);

        StringBuilder current = new StringBuilder();
        boolean insideQuote = false;

        for (int i = 0; i < text.length(); i++) {
            char ch = text.charAt(i);

            if (ch == '\'') {
                insideQuote = !insideQuote;
                continue;
            }

            if (ch == ',' && !insideQuote) {
                values.add(current.toString().trim().toUpperCase());
                current.setLength(0);
            } else {
                current.append(ch);
            }
        }

        if (current.length() > 0) {
            values.add(current.toString().trim().toUpperCase());
        }

        return values;
    }
}