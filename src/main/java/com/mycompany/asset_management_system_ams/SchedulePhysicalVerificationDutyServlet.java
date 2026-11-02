package com.mycompany.asset_management_system_ams;

import java.io.IOException;
import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.Statement;
import java.time.LocalDate;
import java.util.ArrayList;
import java.util.List;

import jakarta.servlet.ServletException;
import jakarta.servlet.annotation.WebServlet;
import jakarta.servlet.http.HttpServlet;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import jakarta.servlet.http.HttpSession;

@WebServlet(name = "SchedulePhysicalVerificationDutyServlet", urlPatterns = {"/SchedulePhysicalVerificationDutyServlet"})
public class SchedulePhysicalVerificationDutyServlet extends HttpServlet {

    @Override
    protected void doPost(HttpServletRequest request, HttpServletResponse response)
            throws ServletException, IOException {

        Connection con = null;

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

            if (!isAllowedScheduler(role)) {
                response.sendRedirect("physical_verification.jsp?error=scheduleAccessDenied");
                return;
            }

            int verificationRoundId = parseIntSafe(request.getParameter("verificationRoundId"), 0);
            int officerEmployeeId = parseIntSafe(request.getParameter("officerEmployeeId"), 0);

            String scheduledFromText = cleanText(request.getParameter("scheduledFrom"));
            String scheduledToText = cleanText(request.getParameter("scheduledTo"));
            String instructions = cleanText(request.getParameter("instructions"));

            if (officerEmployeeId <= 0) {
                response.sendRedirect("physical_verification.jsp?error=selectOfficer");
                return;
            }

            LocalDate today = LocalDate.now();
            LocalDate scheduledFrom = parseDate(scheduledFromText);
            LocalDate scheduledTo = parseDate(scheduledToText);

            if (scheduledFrom == null) {
                response.sendRedirect("physical_verification.jsp?error=invalidFromDate");
                return;
            }

            if (scheduledTo == null) {
                scheduledTo = scheduledFrom;
            }

            if (scheduledFrom.isBefore(today)) {
                response.sendRedirect("physical_verification.jsp?error=pastDateBlocked");
                return;
            }

            if (scheduledTo.isBefore(today)) {
                response.sendRedirect("physical_verification.jsp?error=pastDateBlocked");
                return;
            }

            if (scheduledTo.isBefore(scheduledFrom)) {
                response.sendRedirect("physical_verification.jsp?error=invalidDateRange");
                return;
            }

            if (instructions.isEmpty()) {
                instructions = "Verify assigned railway assets physically and report mismatch, damage, missing asset or holder/location change if found.";
            }

            con = DBConnection.getConnection();
            con.setAutoCommit(false);

            if (!tableExists(con, "physical_verification_duties")) {
                con.rollback();
                response.sendRedirect("physical_verification.jsp?error=dutyTableMissing");
                return;
            }

            if (verificationRoundId <= 0) {
                verificationRoundId = getOrCreateDefaultRound(con, userId);
            }

            if (verificationRoundId <= 0 && hasWritableColumn(con, "physical_verification_duties", "verification_round_id")
                    && !isColumnNullable(con, "physical_verification_duties", "verification_round_id")) {
                con.rollback();
                response.sendRedirect("physical_verification.jsp?error=roundError");
                return;
            }

            int officerDepartmentId = getEmployeeDepartmentId(con, officerEmployeeId);

            boolean hasRoundId = hasWritableColumn(con, "physical_verification_duties", "verification_round_id");
            boolean hasAssignedEmployeeId = hasWritableColumn(con, "physical_verification_duties", "assigned_employee_id");
            boolean hasAssignedDepartmentId = hasWritableColumn(con, "physical_verification_duties", "assigned_department_id");
            boolean hasDutyStatus = hasWritableColumn(con, "physical_verification_duties", "duty_status");
            boolean hasScheduledFrom = hasWritableColumn(con, "physical_verification_duties", "scheduled_from");
            boolean hasScheduledTo = hasWritableColumn(con, "physical_verification_duties", "scheduled_to");
            boolean hasInstructions = hasWritableColumn(con, "physical_verification_duties", "instructions");
            boolean hasCreatedByUserId = hasWritableColumn(con, "physical_verification_duties", "created_by_user_id");

            if (!hasAssignedEmployeeId) {
                con.rollback();
                response.sendRedirect("physical_verification.jsp?error=dutyEmployeeColumnMissing");
                return;
            }

            if (!hasScheduledFrom) {
                con.rollback();
                response.sendRedirect("physical_verification.jsp?error=dutyDateColumnMissing");
                return;
            }

            if (isActiveDutyAlreadyExists(con, verificationRoundId, officerEmployeeId)) {
                con.rollback();
                response.sendRedirect("physical_verification.jsp?warning=dutyAlreadyExists");
                return;
            }

            String safeDutyStatus = getSafeColumnValue(
                    con,
                    "physical_verification_duties",
                    "duty_status",
                    "SCHEDULED"
            );

            StringBuilder columns = new StringBuilder();
            StringBuilder values = new StringBuilder();

            if (hasRoundId) {
                appendColumn(columns, values, "verification_round_id", "?");
            }

            if (hasAssignedEmployeeId) {
                appendColumn(columns, values, "assigned_employee_id", "?");
            }

            if (hasAssignedDepartmentId) {
                appendColumn(columns, values, "assigned_department_id", "?");
            }

            if (hasDutyStatus) {
                appendColumn(columns, values, "duty_status", "?");
            }

            if (hasScheduledFrom) {
                appendColumn(columns, values, "scheduled_from", "?");
            }

            if (hasScheduledTo) {
                appendColumn(columns, values, "scheduled_to", "?");
            }

            if (hasInstructions) {
                appendColumn(columns, values, "instructions", "?");
            }

            if (hasCreatedByUserId) {
                appendColumn(columns, values, "created_by_user_id", "?");
            }

            String sql = "INSERT INTO physical_verification_duties ("
                    + columns
                    + ") VALUES ("
                    + values
                    + ")";

            int dutyId = 0;

            try (PreparedStatement ps = con.prepareStatement(sql, Statement.RETURN_GENERATED_KEYS)) {

                int index = 1;

                if (hasRoundId) {
                    if (verificationRoundId > 0) {
                        ps.setInt(index++, verificationRoundId);
                    } else {
                        ps.setNull(index++, java.sql.Types.INTEGER);
                    }
                }

                if (hasAssignedEmployeeId) {
                    ps.setInt(index++, officerEmployeeId);
                }

                if (hasAssignedDepartmentId) {
                    if (officerDepartmentId > 0) {
                        ps.setInt(index++, officerDepartmentId);
                    } else {
                        ps.setNull(index++, java.sql.Types.INTEGER);
                    }
                }

                if (hasDutyStatus) {
                    ps.setString(index++, safeDutyStatus);
                }

                if (hasScheduledFrom) {
                    ps.setDate(index++, java.sql.Date.valueOf(scheduledFrom));
                }

                if (hasScheduledTo) {
                    ps.setDate(index++, java.sql.Date.valueOf(scheduledTo));
                }

                if (hasInstructions) {
                    ps.setString(index++, instructions);
                }

                if (hasCreatedByUserId) {
                    ps.setInt(index++, userId);
                }

                ps.executeUpdate();

                try (ResultSet keys = ps.getGeneratedKeys()) {
                    if (keys.next()) {
                        dutyId = keys.getInt(1);
                    }
                }
            }

            con.commit();

            safeAuditLog(
                    userId,
                    "PHYSICAL_VERIFICATION_DUTY_SCHEDULED",
                    "physical_verification_duties",
                    dutyId,
                    "Physical verification duty scheduled for officer employee ID "
                    + officerEmployeeId
                    + " from "
                    + scheduledFrom
                    + " to "
                    + scheduledTo
                    + " by "
                    + username
            );

            response.sendRedirect("physical_verification.jsp?success=dutyScheduled");

        } catch (Exception e) {
            e.printStackTrace();

            try {
                if (con != null) {
                    con.rollback();
                }
            } catch (Exception rollbackEx) {
                rollbackEx.printStackTrace();
            }

            response.sendRedirect("physical_verification.jsp?error=scheduleFailed");

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

    private boolean isAllowedScheduler(String role) {
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

    private LocalDate parseDate(String value) {
        try {
            if (value == null || value.trim().isEmpty()) {
                return null;
            }

            return LocalDate.parse(value.trim());
        } catch (Exception e) {
            return null;
        }
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

    private int getOrCreateDefaultRound(Connection con, int userId) {

        try {
            if (!tableExists(con, "physical_verification_rounds")) {
                return 0;
            }

            if (!columnExists(con, "physical_verification_rounds", "verification_round_id")) {
                return 0;
            }

            String currentYear = String.valueOf(LocalDate.now().getYear());
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

            String safeVerificationType = getSafeColumnValue(
                    con,
                    "physical_verification_rounds",
                    "verification_type",
                    "ANNUAL"
            );

            String safeStatus = getSafeColumnValue(
                    con,
                    "physical_verification_rounds",
                    "status",
                    "IN_PROGRESS"
            );

            boolean hasRoundCode = hasWritableColumn(con, "physical_verification_rounds", "round_code");
            boolean hasRoundTitle = hasWritableColumn(con, "physical_verification_rounds", "round_title");
            boolean hasVerificationType = hasWritableColumn(con, "physical_verification_rounds", "verification_type");
            boolean hasStartDate = hasWritableColumn(con, "physical_verification_rounds", "start_date");
            boolean hasEndDate = hasWritableColumn(con, "physical_verification_rounds", "end_date");
            boolean hasStatus = hasWritableColumn(con, "physical_verification_rounds", "status");
            boolean hasCreatedByUserId = hasWritableColumn(con, "physical_verification_rounds", "created_by_user_id");

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

            if (hasCreatedByUserId) {
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
                    ps.setString(index++, safeStatus);
                }

                if (hasCreatedByUserId) {
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

        return getAnyExistingRoundId(con);
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

    private boolean isActiveDutyAlreadyExists(Connection con, int roundId, int officerEmployeeId) {

        try {
            if (!tableExists(con, "physical_verification_duties")) {
                return false;
            }

            if (!columnExists(con, "physical_verification_duties", "assigned_employee_id")) {
                return false;
            }

            boolean hasRoundId = columnExists(con, "physical_verification_duties", "verification_round_id");
            boolean hasDutyStatus = columnExists(con, "physical_verification_duties", "duty_status");

            StringBuilder sql = new StringBuilder();
            sql.append("SELECT duty_id FROM physical_verification_duties WHERE assigned_employee_id = ? ");

            if (hasRoundId && roundId > 0) {
                sql.append("AND verification_round_id = ? ");
            }

            if (hasDutyStatus) {
                sql.append("AND duty_status IN ('SCHEDULED','IN_PROGRESS') ");
            }

            sql.append("LIMIT 1");

            try (PreparedStatement ps = con.prepareStatement(sql.toString())) {

                int index = 1;

                ps.setInt(index++, officerEmployeeId);

                if (hasRoundId && roundId > 0) {
                    ps.setInt(index++, roundId);
                }

                try (ResultSet rs = ps.executeQuery()) {
                    return rs.next();
                }
            }

        } catch (Exception e) {
            e.printStackTrace();
        }

        return false;
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

    private boolean hasWritableColumn(Connection con, String tableName, String columnName) {

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