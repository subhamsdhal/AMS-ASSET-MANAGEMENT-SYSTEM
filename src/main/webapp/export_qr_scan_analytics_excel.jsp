<%@page contentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet" pageEncoding="UTF-8" trimDirectiveWhitespaces="true"%>
<%@page import="com.mycompany.asset_management_system_ams.DBConnection"%>
<%@page import="java.sql.*"%>
<%@page import="java.util.*"%>
<%@page import="java.text.SimpleDateFormat"%>
<%@page import="java.io.OutputStream"%>
<%@page import="org.apache.poi.ss.usermodel.*"%>
<%@page import="org.apache.poi.xssf.usermodel.XSSFWorkbook"%>
<%@page import="org.apache.poi.ss.util.CellRangeAddress"%>

<%!
    private boolean tableExists(Connection con, String tableName) {
        String sql = "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = DATABASE() AND table_name = ?";

        try (PreparedStatement ps = con.prepareStatement(sql)) {
            ps.setString(1, tableName);

            try (ResultSet rs = ps.executeQuery()) {
                return rs.next() && rs.getInt(1) > 0;
            }

        } catch (Exception e) {
            System.err.println("QR Module DB Error: " + e.getMessage());
        }

        return false;
    }

    private int sqlInt(Connection con, String sql) {
        try (PreparedStatement ps = con.prepareStatement(sql);
             ResultSet rs = ps.executeQuery()) {

            if (rs.next()) {
                return rs.getInt(1);
            }

        } catch (Exception e) {
            System.err.println("QR Module DB Error: " + e.getMessage());
        }

        return 0;
    }

    private String safeCell(String value) {
        if (value == null || value.trim().isEmpty()) {
            return "N/A";
        }

        return value.trim();
    }

    private void createMergedTitle(Sheet sheet, int rowIndex, int startCol, int endCol, String title, CellStyle style) {
        Row row = sheet.createRow(rowIndex);
        row.setHeightInPoints(24);

        for (int c = startCol; c <= endCol; c++) {
            Cell cell = row.createCell(c);
            cell.setCellStyle(style);

            if (c == startCol) {
                cell.setCellValue(title);
            }
        }

        sheet.addMergedRegion(new CellRangeAddress(rowIndex, rowIndex, startCol, endCol));
    }

    private void createHeader(Row row, String[] headers, CellStyle style) {
        for (int i = 0; i < headers.length; i++) {
            Cell cell = row.createCell(i);
            cell.setCellValue(headers[i]);
            cell.setCellStyle(style);
        }
    }

    private void setText(Row row, int col, String value, CellStyle style) {
        Cell cell = row.createCell(col);
        cell.setCellValue(safeCell(value));
        cell.setCellStyle(style);
    }

    private void setNumber(Row row, int col, double value, CellStyle style) {
        Cell cell = row.createCell(col);
        cell.setCellValue(value);
        cell.setCellStyle(style);
    }

    private void autoSizeColumns(Sheet sheet, int totalCols) {
        for (int i = 0; i < totalCols; i++) {
            sheet.autoSizeColumn(i);

            int width = sheet.getColumnWidth(i);

            if (width < 3500) {
                sheet.setColumnWidth(i, 3500);
            }

            if (width > 9500) {
                sheet.setColumnWidth(i, 9500);
            }
        }
    }
%>

<%
    String username = (String) session.getAttribute("username");
    String role = (String) session.getAttribute("role");

    if (username == null || role == null) {
        response.sendRedirect("login.jsp");
        return;
    }

    boolean allowed = ("SUPER_ADMIN".equals(role) || "ADMIN".equals(role))
            || "ASSET_MANAGER".equals(role)
            || "AUDITOR".equals(role);

    if (!allowed) {
        response.sendRedirect("dashboard.jsp?access=denied");
        return;
    }

    response.reset();

    String fileName = "IR_AMS_QR_Scan_Analytics_Report_"
            + new SimpleDateFormat("yyyyMMdd_HHmmss").format(new java.util.Date())
            + ".xlsx";

    response.setContentType("application/vnd.openxmlformats-officedocument.spreadsheetml.sheet");
    response.setHeader("Content-Disposition", "attachment; filename=\"" + fileName + "\"");
    response.setHeader("Cache-Control", "no-cache, no-store, must-revalidate");
    response.setHeader("Pragma", "no-cache");
    response.setDateHeader("Expires", 0);

    Workbook workbook = new XSSFWorkbook();

    try {
        Sheet sheet = workbook.createSheet("QR Scan Analytics");

        Font titleFont = workbook.createFont();
        titleFont.setBold(true);
        titleFont.setFontHeightInPoints((short) 16);
        titleFont.setColor(IndexedColors.DARK_BLUE.getIndex());

        Font subTitleFont = workbook.createFont();
        subTitleFont.setBold(true);
        subTitleFont.setFontHeightInPoints((short) 13);
        subTitleFont.setColor(IndexedColors.DARK_BLUE.getIndex());

        Font metaFont = workbook.createFont();
        metaFont.setBold(true);
        metaFont.setFontHeightInPoints((short) 10);
        metaFont.setColor(IndexedColors.BLUE_GREY.getIndex());

        Font whiteFont = workbook.createFont();
        whiteFont.setBold(true);
        whiteFont.setColor(IndexedColors.WHITE.getIndex());

        Font dataFont = workbook.createFont();
        dataFont.setFontHeightInPoints((short) 10);
        dataFont.setColor(IndexedColors.DARK_BLUE.getIndex());

        CellStyle titleStyle = workbook.createCellStyle();
        titleStyle.setAlignment(HorizontalAlignment.CENTER);
        titleStyle.setVerticalAlignment(VerticalAlignment.CENTER);
        titleStyle.setFont(titleFont);

        CellStyle subTitleStyle = workbook.createCellStyle();
        subTitleStyle.setAlignment(HorizontalAlignment.CENTER);
        subTitleStyle.setVerticalAlignment(VerticalAlignment.CENTER);
        subTitleStyle.setFont(subTitleFont);

        CellStyle metaStyle = workbook.createCellStyle();
        metaStyle.setAlignment(HorizontalAlignment.CENTER);
        metaStyle.setVerticalAlignment(VerticalAlignment.CENTER);
        metaStyle.setFont(metaFont);

        CellStyle sectionStyle = workbook.createCellStyle();
        sectionStyle.setFillForegroundColor(IndexedColors.DARK_BLUE.getIndex());
        sectionStyle.setFillPattern(FillPatternType.SOLID_FOREGROUND);
        sectionStyle.setAlignment(HorizontalAlignment.CENTER);
        sectionStyle.setVerticalAlignment(VerticalAlignment.CENTER);
        sectionStyle.setFont(whiteFont);
        sectionStyle.setBorderTop(BorderStyle.THIN);
        sectionStyle.setBorderBottom(BorderStyle.THIN);
        sectionStyle.setBorderLeft(BorderStyle.THIN);
        sectionStyle.setBorderRight(BorderStyle.THIN);

        CellStyle headerStyle = workbook.createCellStyle();
        headerStyle.setFillForegroundColor(IndexedColors.DARK_BLUE.getIndex());
        headerStyle.setFillPattern(FillPatternType.SOLID_FOREGROUND);
        headerStyle.setAlignment(HorizontalAlignment.CENTER);
        headerStyle.setVerticalAlignment(VerticalAlignment.CENTER);
        headerStyle.setFont(whiteFont);
        headerStyle.setBorderTop(BorderStyle.THIN);
        headerStyle.setBorderBottom(BorderStyle.THIN);
        headerStyle.setBorderLeft(BorderStyle.THIN);
        headerStyle.setBorderRight(BorderStyle.THIN);

        CellStyle dataStyle = workbook.createCellStyle();
        dataStyle.setAlignment(HorizontalAlignment.LEFT);
        dataStyle.setVerticalAlignment(VerticalAlignment.CENTER);
        dataStyle.setFont(dataFont);
        dataStyle.setWrapText(true);
        dataStyle.setBorderTop(BorderStyle.THIN);
        dataStyle.setBorderBottom(BorderStyle.THIN);
        dataStyle.setBorderLeft(BorderStyle.THIN);
        dataStyle.setBorderRight(BorderStyle.THIN);

        CellStyle centerStyle = workbook.createCellStyle();
        centerStyle.cloneStyleFrom(dataStyle);
        centerStyle.setAlignment(HorizontalAlignment.CENTER);

        CellStyle numberStyle = workbook.createCellStyle();
        numberStyle.cloneStyleFrom(centerStyle);
        numberStyle.setDataFormat(workbook.createDataFormat().getFormat("#,##0"));

        CellStyle percentStyle = workbook.createCellStyle();
        percentStyle.cloneStyleFrom(centerStyle);
        percentStyle.setDataFormat(workbook.createDataFormat().getFormat("0.0%"));

        createMergedTitle(sheet, 0, 0, 7, "INDIAN RAILWAYS - EAST COAST RAILWAY", titleStyle);
        createMergedTitle(sheet, 1, 0, 7, "IR-AMS QR SCAN ANALYTICS REPORT", subTitleStyle);
        createMergedTitle(sheet, 2, 0, 7,
                "Generated By: " + username + " (" + role + ")  |  Generated At: "
                + new SimpleDateFormat("dd-MMM-yyyy hh:mm a", Locale.ENGLISH).format(new java.util.Date()),
                metaStyle);

        int rowIndex = 4;

        try (Connection con = DBConnection.getConnection()) {
            boolean scanTableExists = tableExists(con, "asset_qr_scan_logs");

            if (!scanTableExists) {
                createMergedTitle(sheet, rowIndex++, 0, 1, "QR Scan Analytics Status", sectionStyle);

                Row header = sheet.createRow(rowIndex++);
                createHeader(header, new String[]{"Status", "Message"}, headerStyle);

                Row row = sheet.createRow(rowIndex++);
                setText(row, 0, "Not Available", centerStyle);
                setText(row, 1, "asset_qr_scan_logs table not found. Please import/create the QR scan log table first.", dataStyle);

            } else {
                int totalScans = sqlInt(con, "SELECT COUNT(*) FROM asset_qr_scan_logs");
                int todayScans = sqlInt(con, "SELECT COUNT(*) FROM asset_qr_scan_logs WHERE DATE(scanned_at) = CURDATE()");
                int successScans = sqlInt(con, "SELECT COUNT(*) FROM asset_qr_scan_logs WHERE scan_status = 'SUCCESS'");
                int invalidScans = sqlInt(con, "SELECT COUNT(*) FROM asset_qr_scan_logs WHERE scan_status = 'INVALID_TOKEN'");
                int uniqueAssets = sqlInt(con, "SELECT COUNT(DISTINCT asset_id) FROM asset_qr_scan_logs WHERE asset_id IS NOT NULL");
                int uniqueIp = sqlInt(con, "SELECT COUNT(DISTINCT scan_ip) FROM asset_qr_scan_logs WHERE scan_ip IS NOT NULL AND TRIM(scan_ip) <> ''");

                createMergedTitle(sheet, rowIndex++, 0, 2, "QR Scan Summary", sectionStyle);

                Row summaryHeader = sheet.createRow(rowIndex++);
                createHeader(summaryHeader, new String[]{"Metric", "Value", "Remarks"}, headerStyle);

                String[][] summaryRows = {
                    {"Total QR Scans", String.valueOf(totalScans), "All QR scan entries"},
                    {"Today's QR Scans", String.valueOf(todayScans), "Scans recorded today"},
                    {"Successful Scans", String.valueOf(successScans), "Asset token matched successfully"},
                    {"Invalid Token Scans", String.valueOf(invalidScans), "Invalid or suspicious QR token scans"},
                    {"Unique Assets Scanned", String.valueOf(uniqueAssets), "Distinct assets scanned"},
                    {"Unique IP Addresses", String.valueOf(uniqueIp), "Distinct scan IP addresses"}
                };

                for (String[] item : summaryRows) {
                    Row row = sheet.createRow(rowIndex++);
                    setText(row, 0, item[0], dataStyle);
                    setNumber(row, 1, Double.parseDouble(item[1]), numberStyle);
                    setText(row, 2, item[2], dataStyle);
                }

                rowIndex += 2;

                createMergedTitle(sheet, rowIndex++, 0, 3, "Scan Status Summary", sectionStyle);

                Row statusHeader = sheet.createRow(rowIndex++);
                createHeader(statusHeader, new String[]{"Sl. No.", "Scan Status", "Total Scans", "Share %"}, headerStyle);

                String statusSql =
                        "SELECT COALESCE(NULLIF(scan_status, ''), 'UNKNOWN') AS scan_status, COUNT(*) AS total_scans "
                        + "FROM asset_qr_scan_logs "
                        + "GROUP BY COALESCE(NULLIF(scan_status, ''), 'UNKNOWN') "
                        + "ORDER BY total_scans DESC, scan_status ASC";

                int sl = 1;

                try (PreparedStatement ps = con.prepareStatement(statusSql);
                     ResultSet rs = ps.executeQuery()) {

                    while (rs.next()) {
                        int total = rs.getInt("total_scans");

                        Row row = sheet.createRow(rowIndex++);
                        setNumber(row, 0, sl++, numberStyle);
                        setText(row, 1, rs.getString("scan_status"), dataStyle);
                        setNumber(row, 2, total, numberStyle);
                        setNumber(row, 3, totalScans == 0 ? 0 : total / (double) totalScans, percentStyle);
                    }
                }

                rowIndex += 2;

                createMergedTitle(sheet, rowIndex++, 0, 3, "Scan Source Summary", sectionStyle);

                Row sourceHeader = sheet.createRow(rowIndex++);
                createHeader(sourceHeader, new String[]{"Sl. No.", "Scan Source", "Total Scans", "Share %"}, headerStyle);

                String sourceSql =
                        "SELECT COALESCE(NULLIF(scan_source, ''), 'UNKNOWN') AS scan_source, COUNT(*) AS total_scans "
                        + "FROM asset_qr_scan_logs "
                        + "GROUP BY COALESCE(NULLIF(scan_source, ''), 'UNKNOWN') "
                        + "ORDER BY total_scans DESC, scan_source ASC";

                sl = 1;

                try (PreparedStatement ps = con.prepareStatement(sourceSql);
                     ResultSet rs = ps.executeQuery()) {

                    while (rs.next()) {
                        int total = rs.getInt("total_scans");

                        Row row = sheet.createRow(rowIndex++);
                        setNumber(row, 0, sl++, numberStyle);
                        setText(row, 1, rs.getString("scan_source"), dataStyle);
                        setNumber(row, 2, total, numberStyle);
                        setNumber(row, 3, totalScans == 0 ? 0 : total / (double) totalScans, percentStyle);
                    }
                }

                rowIndex += 2;

                createMergedTitle(sheet, rowIndex++, 0, 6, "Most Scanned Assets", sectionStyle);

                Row topHeader = sheet.createRow(rowIndex++);
                createHeader(topHeader, new String[]{
                    "Sl. No.", "Asset Code", "Asset Name", "Total Scans", "Success", "Invalid", "Last Scan"
                }, headerStyle);

                String topSql =
                        "SELECT "
                        + "COALESCE(a.asset_code, 'Unknown Asset') AS asset_code, "
                        + "COALESCE(a.asset_name, 'Asset not linked') AS asset_name, "
                        + "COUNT(*) AS total_scans, "
                        + "SUM(CASE WHEN q.scan_status = 'SUCCESS' THEN 1 ELSE 0 END) AS success_scans, "
                        + "SUM(CASE WHEN q.scan_status = 'INVALID_TOKEN' THEN 1 ELSE 0 END) AS invalid_scans, "
                        + "DATE_FORMAT(MAX(q.scanned_at), '%d-%b-%Y %h:%i %p') AS last_scan "
                        + "FROM asset_qr_scan_logs q "
                        + "LEFT JOIN assets a ON q.asset_id = a.asset_id "
                        + "WHERE q.asset_id IS NOT NULL "
                        + "GROUP BY q.asset_id, a.asset_code, a.asset_name "
                        + "ORDER BY total_scans DESC, asset_code ASC "
                        + "LIMIT 20";

                sl = 1;

                try (PreparedStatement ps = con.prepareStatement(topSql);
                     ResultSet rs = ps.executeQuery()) {

                    while (rs.next()) {
                        Row row = sheet.createRow(rowIndex++);
                        setNumber(row, 0, sl++, numberStyle);
                        setText(row, 1, rs.getString("asset_code"), dataStyle);
                        setText(row, 2, rs.getString("asset_name"), dataStyle);
                        setNumber(row, 3, rs.getInt("total_scans"), numberStyle);
                        setNumber(row, 4, rs.getInt("success_scans"), numberStyle);
                        setNumber(row, 5, rs.getInt("invalid_scans"), numberStyle);
                        setText(row, 6, rs.getString("last_scan"), centerStyle);
                    }
                }

                rowIndex += 2;

                createMergedTitle(sheet, rowIndex++, 0, 4, "Daily QR Scan Trend - Last 30 Days", sectionStyle);

                Row trendHeader = sheet.createRow(rowIndex++);
                createHeader(trendHeader, new String[]{"Sl. No.", "Scan Date", "Total Scans", "Success", "Invalid Token"}, headerStyle);

                String trendSql =
                        "SELECT "
                        + "DATE_FORMAT(t.scan_date_raw, '%d-%b-%Y') AS scan_date, "
                        + "t.total_scans, "
                        + "t.success_scans, "
                        + "t.invalid_scans "
                        + "FROM ( "
                        + "    SELECT "
                        + "        DATE(scanned_at) AS scan_date_raw, "
                        + "        COUNT(*) AS total_scans, "
                        + "        SUM(CASE WHEN scan_status = 'SUCCESS' THEN 1 ELSE 0 END) AS success_scans, "
                        + "        SUM(CASE WHEN scan_status = 'INVALID_TOKEN' THEN 1 ELSE 0 END) AS invalid_scans "
                        + "    FROM asset_qr_scan_logs "
                        + "    WHERE scanned_at >= DATE_SUB(CURDATE(), INTERVAL 30 DAY) "
                        + "    GROUP BY DATE(scanned_at) "
                        + ") t "
                        + "ORDER BY t.scan_date_raw DESC";

                sl = 1;

                try (PreparedStatement ps = con.prepareStatement(trendSql);
                     ResultSet rs = ps.executeQuery()) {

                    while (rs.next()) {
                        Row row = sheet.createRow(rowIndex++);
                        setNumber(row, 0, sl++, numberStyle);
                        setText(row, 1, rs.getString("scan_date"), centerStyle);
                        setNumber(row, 2, rs.getInt("total_scans"), numberStyle);
                        setNumber(row, 3, rs.getInt("success_scans"), numberStyle);
                        setNumber(row, 4, rs.getInt("invalid_scans"), numberStyle);
                    }
                }

                rowIndex += 2;

                createMergedTitle(sheet, rowIndex++, 0, 3, "QR Exception / Invalid Token IP Audit", sectionStyle);

                Row ipHeader = sheet.createRow(rowIndex++);
                createHeader(ipHeader, new String[]{"Sl. No.", "IP Address", "Exception Scans", "Last Exception Time"}, headerStyle);

                String ipSql =
                        "SELECT "
                        + "COALESCE(NULLIF(scan_ip, ''), 'Unknown IP') AS scan_ip, "
                        + "COUNT(*) AS exception_count, "
                        + "DATE_FORMAT(MAX(scanned_at), '%d-%b-%Y %h:%i %p') AS last_exception "
                        + "FROM asset_qr_scan_logs "
                        + "WHERE scan_status <> 'SUCCESS' OR asset_id IS NULL "
                        + "GROUP BY COALESCE(NULLIF(scan_ip, ''), 'Unknown IP') "
                        + "ORDER BY exception_count DESC, scan_ip ASC "
                        + "LIMIT 20";

                sl = 1;

                try (PreparedStatement ps = con.prepareStatement(ipSql);
                     ResultSet rs = ps.executeQuery()) {

                    while (rs.next()) {
                        Row row = sheet.createRow(rowIndex++);
                        setNumber(row, 0, sl++, numberStyle);
                        setText(row, 1, rs.getString("scan_ip"), dataStyle);
                        setNumber(row, 2, rs.getInt("exception_count"), numberStyle);
                        setText(row, 3, rs.getString("last_exception"), centerStyle);
                    }
                }
            }
        }

        autoSizeColumns(sheet, 8);

        out.clear();
        out = pageContext.pushBody();

        OutputStream outputStream = response.getOutputStream();
        workbook.write(outputStream);
        outputStream.flush();

    } catch (Exception e) {
        System.err.println("QR Module DB Error: " + e.getMessage());
        response.reset();
        response.setContentType("text/plain");
        response.getWriter().write("QR Scan Analytics Excel export failed: " + "Please contact the administrator.");
    } finally {
        workbook.close();
    }
%>
