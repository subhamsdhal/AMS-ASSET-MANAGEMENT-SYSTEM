package com.mycompany.asset_management_system_ams;

import java.io.IOException;
import java.io.PrintWriter;
import java.sql.Blob;
import java.sql.Clob;
import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.ResultSetMetaData;
import java.sql.Types;
import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.Comparator;
import java.util.List;

import jakarta.servlet.ServletException;
import jakarta.servlet.annotation.WebServlet;
import jakarta.servlet.http.HttpServlet;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import jakarta.servlet.http.HttpSession;

@WebServlet(name = "BackupDatabaseServlet", urlPatterns = {"/BackupDatabaseServlet"})
public class BackupDatabaseServlet extends HttpServlet {

    private static final List<String> PRIORITY_ORDER = Arrays.asList(
            "roles",
            "departments",
            "users",
            "employees",
            "asset_categories",
            "vendors",
            "assets",
            "asset_requests",
            "asset_allocation",
            "asset_returns",
            "maintenance_logs",
            "asset_disposal",
            "audit_logs"
    );

    @Override
    protected void doGet(HttpServletRequest request, HttpServletResponse response)
            throws ServletException, IOException {

        Connection con = null;

        String username = "";
        String role = "";
        String loginEmail = "";
        String fileName = "N/A";
        int tableCount = 0;

        try {
            HttpSession session = request.getSession(false);

            if (session == null
                    || session.getAttribute("username") == null
                    || session.getAttribute("role") == null) {
                response.sendRedirect("login.jsp");
                return;
            }

            username = session.getAttribute("username").toString();
            role = session.getAttribute("role").toString();
            loginEmail = NotificationHelper.getUserEmailByUsername(username);

            if (!("SUPER_ADMIN".equals(role) || "ADMIN".equals(role))) {
                response.sendRedirect("settings.jsp?access=denied");
                return;
            }

            String timestamp = LocalDateTime.now().format(DateTimeFormatter.ofPattern("yyyyMMdd_HHmmss"));
            fileName = "IR_AMS_Database_Backup_" + timestamp + ".sql";

            response.reset();
            response.setCharacterEncoding("UTF-8");
            response.setContentType("application/sql; charset=UTF-8");
            response.setHeader("Content-Disposition", "attachment; filename=\"" + fileName + "\"");

            con = DBConnection.getConnection();

            if (con == null) {
                throw new IllegalStateException("Database connection is not available.");
            }

            PrintWriter writer = response.getWriter();

            tableCount = writeFullBackup(con, writer, username);

            writer.flush();

            int userId = getSessionUserId(session);

            try {
                AuditDAO.log(
                        userId,
                        "BACKUP",
                        "database",
                        0,
                        "Database SQL backup downloaded by " + username
                        + ". File: " + fileName
                        + ". Tables included: " + tableCount
                );
            } catch (Exception auditException) {
                log("Backup audit log failed", auditException);
            }

            sendBackupAlert(
                    "SUCCESS",
                    username,
                    role,
                    loginEmail,
                    fileName,
                    tableCount,
                    ""
            );

        } catch (Exception e) {
            log("Database backup failed", e);

            if (username != null && !username.trim().isEmpty()) {
                sendBackupAlert(
                        "FAILED",
                        username,
                        role,
                        loginEmail,
                        fileName,
                        tableCount,
                        e.getClass().getSimpleName() + ": " + e.getMessage()
                );
            }

            if (!response.isCommitted()) {
                response.sendRedirect("backup_restore.jsp?error=server");
            }

        } finally {
            try {
                if (con != null) {
                    con.close();
                }
            } catch (Exception ex) {
                log("Unable to close backup database connection", ex);
            }
        }
    }

    private void sendBackupAlert(String status, String username, String role, String loginEmail,
            String fileName, int tableCount, String errorMessage) {

        try {
            String details = "Operation Type: Database Backup\n"
                    + "Status: " + safe(status, "N/A") + "\n"
                    + "Backup File: " + safe(fileName, "N/A") + "\n"
                    + "Tables Included: " + tableCount + "\n";

            if ("FAILED".equalsIgnoreCase(status)) {
                details += "Error Message: " + safe(errorMessage, "N/A") + "\n";
            }

            details += "\nSecurity Note: Database backup contains system data and should be stored securely.";

            NotificationEventService.EmailRouting routing = NotificationEventService.buildSettingsSecurityRecipients("BACKUP", 0);
            String toEmail = routing.getToEmail();
            String ccEmail = routing.getCcEmail();

            NotificationHelper.sendNotification(
                    getServletContext(),
                    "ADMIN_SECURITY_ALERT",
                    "Backup and Restore",
                    0,
                    toEmail,
                    ccEmail,
                    "",
                    "Database Backup " + status,
                    details.replace("\n", "<br>")
            );

        } catch (Exception e) {
            log("Backup alert failed", e);
        }
    }

    private int getSessionUserId(HttpSession session) {
        // Defaulting to 1 here would misattribute this audit-log entry (a database
        // backup download) to whichever real account happens to be user_id 1.
        // AuditDAO.log() resolves 0/null to a NULL "system" row instead.
        Object userIdObj = session.getAttribute("user_id");

        if (userIdObj == null) {
            userIdObj = session.getAttribute("userId");
        }

        if (userIdObj instanceof Integer) {
            return (Integer) userIdObj;
        }

        if (userIdObj != null) {
            try {
                return Integer.parseInt(userIdObj.toString());
            } catch (Exception e) {
                return 0;
            }
        }

        return 0;
    }

    // Writes a complete SQL dump (DROP + CREATE + INSERT for every table) to
    // any PrintWriter - extracted from doGet() so RestoreDatabaseServlet can
    // reuse the exact same, already-correct dump logic to take an automatic
    // safety backup immediately before executing a restore (see
    // RestoreDatabaseServlet.createPreRestoreSafetyBackup() / audit/23's
    // Finding 1: restore previously had no rollback safety net at all).
    // Returns the number of tables included, for audit-log/UI purposes.
    static int writeFullBackup(Connection con, PrintWriter writer, String generatedBy) throws Exception {
        writer.println("-- =====================================================");
        writer.println("-- INDIAN RAILWAY ASSET MANAGEMENT SYSTEM");
        writer.println("-- DATABASE BACKUP FILE");
        writer.println("-- Generated By : " + generatedBy);
        writer.println("-- Generated On : " + LocalDateTime.now().format(DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss")));
        writer.println("-- =====================================================");
        writer.println();

        writer.println("SET NAMES utf8mb4;");
        writer.println("SET FOREIGN_KEY_CHECKS = 0;");
        writer.println();

        List<String> tableNames = getOrderedTableNames(con);

        List<String> reverseTableNames = new ArrayList<>(tableNames);
        Collections.reverse(reverseTableNames);

        writer.println("-- =====================================================");
        writer.println("-- DROP EXISTING TABLES");
        writer.println("-- =====================================================");
        writer.println();

        for (String tableName : reverseTableNames) {
            writer.println("DROP TABLE IF EXISTS " + quoteIdentifier(tableName) + ";");
        }

        writer.println();

        writer.println("-- =====================================================");
        writer.println("-- TABLE STRUCTURE");
        writer.println("-- =====================================================");
        writer.println();

        for (String tableName : tableNames) {
            writeTableStructure(con, writer, tableName);
        }

        writer.println();

        writer.println("-- =====================================================");
        writer.println("-- TABLE DATA");
        writer.println("-- =====================================================");
        writer.println();

        for (String tableName : tableNames) {
            writeTableData(con, writer, tableName);
        }

        writer.println();
        writer.println("SET FOREIGN_KEY_CHECKS = 1;");
        writer.println();
        writer.println("-- Backup completed successfully.");

        return tableNames.size();
    }

    private static List<String> getOrderedTableNames(Connection con) throws Exception {
        List<String> tableNames = new ArrayList<>();

        PreparedStatement ps = con.prepareStatement(
                "SELECT TABLE_NAME "
                + "FROM INFORMATION_SCHEMA.TABLES "
                + "WHERE TABLE_SCHEMA = DATABASE() "
                + "AND TABLE_TYPE = 'BASE TABLE'"
        );

        ResultSet rs = ps.executeQuery();

        while (rs.next()) {
            tableNames.add(rs.getString("TABLE_NAME"));
        }

        rs.close();
        ps.close();

        Collections.sort(tableNames, new Comparator<String>() {
            @Override
            public int compare(String tableOne, String tableTwo) {
                int indexOne = PRIORITY_ORDER.indexOf(tableOne);
                int indexTwo = PRIORITY_ORDER.indexOf(tableTwo);

                if (indexOne == -1) {
                    indexOne = 1000;
                }

                if (indexTwo == -1) {
                    indexTwo = 1000;
                }

                if (indexOne != indexTwo) {
                    return Integer.compare(indexOne, indexTwo);
                }

                return tableOne.compareToIgnoreCase(tableTwo);
            }
        });

        return tableNames;
    }

    private static void writeTableStructure(Connection con, PrintWriter writer, String tableName) throws Exception {
        PreparedStatement ps = con.prepareStatement("SHOW CREATE TABLE " + quoteIdentifier(tableName));
        ResultSet rs = ps.executeQuery();

        if (rs.next()) {
            String createStatement = rs.getString(2);

            writer.println("-- Structure for table " + quoteIdentifier(tableName));
            writer.println(createStatement + ";");
            writer.println();
        }

        rs.close();
        ps.close();
    }

    private static void writeTableData(Connection con, PrintWriter writer, String tableName) throws Exception {
        PreparedStatement ps = con.prepareStatement("SELECT * FROM " + quoteIdentifier(tableName));
        ResultSet rs = ps.executeQuery();
        ResultSetMetaData metaData = rs.getMetaData();

        int columnCount = metaData.getColumnCount();

        writer.println("-- Data for table " + quoteIdentifier(tableName));

        int rowCount = 0;

        while (rs.next()) {
            StringBuilder insertSql = new StringBuilder();

            insertSql.append("INSERT INTO ");
            insertSql.append(quoteIdentifier(tableName));
            insertSql.append(" (");

            for (int i = 1; i <= columnCount; i++) {
                if (i > 1) {
                    insertSql.append(", ");
                }

                insertSql.append(quoteIdentifier(metaData.getColumnName(i)));
            }

            insertSql.append(") VALUES (");

            for (int i = 1; i <= columnCount; i++) {
                if (i > 1) {
                    insertSql.append(", ");
                }

                Object value = rs.getObject(i);
                int columnType = metaData.getColumnType(i);

                insertSql.append(toSqlValue(value, columnType));
            }

            insertSql.append(");");

            writer.println(insertSql.toString());
            rowCount++;
        }

        if (rowCount == 0) {
            writer.println("-- No data found.");
        }

        writer.println();

        rs.close();
        ps.close();
    }

    private static String quoteIdentifier(String identifier) {
        if (identifier == null) {
            return "``";
        }

        return "`" + identifier.replace("`", "``") + "`";
    }

    private static String toSqlValue(Object value, int columnType) throws Exception {
        if (value == null) {
            return "NULL";
        }

        if (value instanceof byte[]) {
            byte[] bytes = (byte[]) value;
            StringBuilder hex = new StringBuilder("0x");

            for (byte b : bytes) {
                hex.append(String.format("%02X", b));
            }

            return hex.toString();
        }

        if (value instanceof Blob) {
            Blob blob = (Blob) value;
            byte[] bytes = blob.getBytes(1, (int) blob.length());
            StringBuilder hex = new StringBuilder("0x");

            for (byte b : bytes) {
                hex.append(String.format("%02X", b));
            }

            return hex.toString();
        }

        if (value instanceof Clob) {
            Clob clob = (Clob) value;
            String clobValue = clob.getSubString(1, (int) clob.length());
            return "'" + escapeSql(clobValue) + "'";
        }

        if (isNumericColumn(columnType)) {
            return value.toString();
        }

        if (columnType == Types.BOOLEAN || columnType == Types.BIT) {
            if (value instanceof Boolean) {
                return ((Boolean) value) ? "1" : "0";
            }

            return value.toString();
        }

        return "'" + escapeSql(value.toString()) + "'";
    }

    private static boolean isNumericColumn(int columnType) {
        return columnType == Types.INTEGER
                || columnType == Types.BIGINT
                || columnType == Types.SMALLINT
                || columnType == Types.TINYINT
                || columnType == Types.FLOAT
                || columnType == Types.DOUBLE
                || columnType == Types.REAL
                || columnType == Types.NUMERIC
                || columnType == Types.DECIMAL;
    }

    private static String escapeSql(String text) {
        if (text == null) {
            return "";
        }

        return text
                .replace("\\", "\\\\")
                .replace("'", "''")
                .replace("\r", "\\r")
                .replace("\n", "\\n")
                .replace("\t", "\\t");
    }

    private String safe(String value, String fallback) {
        if (value == null || value.trim().isEmpty()) {
            return fallback;
        }

        return value.trim();
    }
}
