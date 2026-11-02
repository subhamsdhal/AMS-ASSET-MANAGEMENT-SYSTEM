<%@page contentType="text/plain" pageEncoding="UTF-8"%>
<%@page import="com.mycompany.asset_management_system_ams.DBConnection"%>
<%@page import="java.sql.*"%>
<%@page import="java.util.*"%>
<%@page import="java.text.SimpleDateFormat"%>
<%@page import="java.io.PrintWriter"%>

<%!
    private String quoteIdentifier(String name) {
        if (name == null) {
            return "``";
        }

        return "`" + name.replace("`", "``") + "`";
    }

    private String sqlString(String value) {
        if (value == null) {
            return "NULL";
        }

        return "'"
                + value.replace("\\", "\\\\")
                        .replace("'", "''")
                        .replace("\r", "\\r")
                        .replace("\n", "\\n")
                        .replace("\t", "\\t")
                + "'";
    }

    private String bytesToHex(byte[] bytes) {
        if (bytes == null) {
            return "NULL";
        }

        StringBuilder sb = new StringBuilder("0x");

        for (byte b : bytes) {
            sb.append(String.format("%02X", b));
        }

        return sb.toString();
    }

    private String valueToSql(ResultSet rs, int columnIndex, int sqlType) throws SQLException {
        Object obj = rs.getObject(columnIndex);

        if (obj == null || rs.wasNull()) {
            return "NULL";
        }

        switch (sqlType) {
            case Types.TINYINT:
            case Types.SMALLINT:
            case Types.INTEGER:
            case Types.BIGINT:
            case Types.FLOAT:
            case Types.REAL:
            case Types.DOUBLE:
            case Types.NUMERIC:
            case Types.DECIMAL:
                return String.valueOf(obj);

            case Types.BIT:
            case Types.BOOLEAN:
                return rs.getBoolean(columnIndex) ? "1" : "0";

            case Types.DATE:
                // Fault: bare "Date" is ambiguous here - both java.sql.* and
                // java.util.* are imported above (java.util.Date is used
                // correctly elsewhere in this file), so Jasper's javac step
                // failed with "The type Date is ambiguous" on every request,
                // 500-ing this entire export page. Fix: qualify explicitly -
                // rs.getDate() returns java.sql.Date.
                java.sql.Date date = rs.getDate(columnIndex);
                return date == null ? "NULL" : sqlString(date.toString());

            case Types.TIME:
                Time time = rs.getTime(columnIndex);
                return time == null ? "NULL" : sqlString(time.toString());

            case Types.TIMESTAMP:
            case -101:
            case -102:
                Timestamp timestamp = rs.getTimestamp(columnIndex);
                return timestamp == null ? "NULL" : sqlString(timestamp.toString());

            case Types.BINARY:
            case Types.VARBINARY:
            case Types.LONGVARBINARY:
            case Types.BLOB:
                return bytesToHex(rs.getBytes(columnIndex));

            default:
                return sqlString(rs.getString(columnIndex));
        }
    }

    private ArrayList<String> getTables(Connection con) throws SQLException {
        ArrayList<String> tables = new ArrayList<String>();

        DatabaseMetaData meta = con.getMetaData();
        String catalog = con.getCatalog();

        try (ResultSet rs = meta.getTables(catalog, null, "%", new String[]{"TABLE"})) {
            while (rs.next()) {
                String tableName = rs.getString("TABLE_NAME");

                if (tableName != null && !tableName.startsWith("sys_")) {
                    tables.add(tableName);
                }
            }
        }

        Collections.sort(tables);
        return tables;
    }

    private String getCreateTable(Connection con, String tableName) throws SQLException {
        String sql = "SHOW CREATE TABLE " + quoteIdentifier(tableName);

        try (Statement st = con.createStatement();
             ResultSet rs = st.executeQuery(sql)) {

            if (rs.next()) {
                return rs.getString(2);
            }
        }

        return "";
    }
%>

<%
    String username = (String) session.getAttribute("username");
    String role = (String) session.getAttribute("role");

    if (username == null || role == null) {
        response.sendRedirect("login.jsp");
        return;
    }

    if (!("SUPER_ADMIN".equals(role) || "ADMIN".equals(role))) {
        response.sendRedirect("dashboard.jsp?access=denied");
        return;
    }

    String timestampText = new SimpleDateFormat("yyyyMMdd_HHmmss").format(new java.util.Date());
    String filename = "RailwayAMS_Backup_" + timestampText + ".sql";

    response.reset();
    response.setContentType("application/sql; charset=UTF-8");
    response.setHeader("Content-Disposition", "attachment; filename=\"" + filename + "\"");
    response.setHeader("Cache-Control", "no-cache, no-store, must-revalidate");
    response.setHeader("Pragma", "no-cache");
    response.setDateHeader("Expires", 0);

    PrintWriter writer = response.getWriter();

    try (Connection con = DBConnection.getConnection()) {
        String databaseName = "";

        try (Statement st = con.createStatement();
             ResultSet rs = st.executeQuery("SELECT DATABASE()")) {
            if (rs.next()) {
                databaseName = rs.getString(1);
            }
        }

        ArrayList<String> tables = getTables(con);

        writer.println("-- =========================================================");
        writer.println("-- Railway Asset Management System Database Backup");
        writer.println("-- Organization : East Coast Railway / Indian Railways");
        writer.println("-- Database     : " + databaseName);
        writer.println("-- Generated On : " + new java.util.Date());
        writer.println("-- Generated By : " + username);
        writer.println("-- =========================================================");
        writer.println();
        writer.println("SET FOREIGN_KEY_CHECKS=0;");
        writer.println("SET SQL_MODE = 'NO_AUTO_VALUE_ON_ZERO';");
        writer.println("START TRANSACTION;");
        writer.println();

        for (String tableName : tables) {
            writer.println();
            writer.println("-- ---------------------------------------------------------");
            writer.println("-- Table structure for " + quoteIdentifier(tableName));
            writer.println("-- ---------------------------------------------------------");
            writer.println();

            writer.println("DROP TABLE IF EXISTS " + quoteIdentifier(tableName) + ";");

            String createTable = getCreateTable(con, tableName);

            if (createTable != null && !createTable.trim().isEmpty()) {
                writer.println(createTable + ";");
            }

            writer.println();
        }

        for (String tableName : tables) {
            writer.println();
            writer.println("-- ---------------------------------------------------------");
            writer.println("-- Data for " + quoteIdentifier(tableName));
            writer.println("-- ---------------------------------------------------------");
            writer.println();

            String selectSql = "SELECT * FROM " + quoteIdentifier(tableName);

            try (Statement st = con.createStatement();
                 ResultSet rs = st.executeQuery(selectSql)) {

                ResultSetMetaData meta = rs.getMetaData();
                int columnCount = meta.getColumnCount();

                StringBuilder columnNames = new StringBuilder();

                for (int i = 1; i <= columnCount; i++) {
                    if (i > 1) {
                        columnNames.append(", ");
                    }

                    columnNames.append(quoteIdentifier(meta.getColumnName(i)));
                }

                int rowNumber = 0;

                while (rs.next()) {
                    StringBuilder values = new StringBuilder();

                    for (int i = 1; i <= columnCount; i++) {
                        if (i > 1) {
                            values.append(", ");
                        }

                        values.append(valueToSql(rs, i, meta.getColumnType(i)));
                    }

                    writer.println("INSERT INTO "
                            + quoteIdentifier(tableName)
                            + " ("
                            + columnNames
                            + ") VALUES ("
                            + values
                            + ");");

                    rowNumber++;

                    if (rowNumber % 500 == 0) {
                        writer.flush();
                    }
                }

                if (rowNumber == 0) {
                    writer.println("-- No rows found.");
                }
            }
        }

        writer.println();
        writer.println("COMMIT;");
        writer.println("SET FOREIGN_KEY_CHECKS=1;");
        writer.println();
        writer.println("-- Backup completed successfully.");

        writer.flush();

    } catch (Exception e) {
        writer.println();
        writer.println("-- Backup failed:");
        writer.println("-- Server error while generating backup.");
        writer.println("-- Check the application server log for technical details.");
        application.log("Database backup export failed", e);
        writer.flush();
    }
%>
