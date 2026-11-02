<%@page contentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet" pageEncoding="UTF-8" trimDirectiveWhitespaces="true"%>
<%@page import="java.sql.*"%>
<%@page import="java.time.LocalDateTime"%>
<%@page import="java.time.format.DateTimeFormatter"%>
<%@page import="jakarta.servlet.ServletOutputStream"%>
<%@page import="jakarta.servlet.http.HttpSession"%>
<%@page import="com.mycompany.asset_management_system_ams.DBConnection"%>
<%@page import="com.mycompany.asset_management_system_ams.AuditDAO"%>

<%@page import="org.apache.poi.ss.usermodel.*"%>
<%@page import="org.apache.poi.ss.util.CellRangeAddress"%>
<%@page import="org.apache.poi.xssf.usermodel.*"%>

<%!
    private String safeText(Object value) {
        if (value == null || String.valueOf(value).trim().isEmpty()) {
            return "-";
        }
        return String.valueOf(value).trim();
    }

    private String cleanLabel(String value) {
        if (value == null || value.trim().isEmpty()) {
            return "-";
        }

        String text = value.trim().replace("_", " ").toLowerCase();
        String[] parts = text.split("\\s+");
        StringBuilder out = new StringBuilder();

        for (String part : parts) {
            if (!part.isEmpty()) {
                out.append(Character.toUpperCase(part.charAt(0)))
                        .append(part.substring(1))
                        .append(" ");
            }
        }

        return out.toString().trim();
    }

    private int getSessionUserId(HttpSession session) {
        try {
            Object userIdObj = session.getAttribute("user_id");

            if (userIdObj == null) {
                userIdObj = session.getAttribute("userId");
            }

            if (userIdObj == null) {
                return 1;
            }

            return Integer.parseInt(String.valueOf(userIdObj));
        } catch (Exception e) {
            return 1;
        }
    }

    private boolean tableExists(Connection con, String tableName) {
        String sql = "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = DATABASE() AND table_name = ?";

        try (PreparedStatement ps = con.prepareStatement(sql)) {
            ps.setString(1, tableName);

            try (ResultSet rs = ps.executeQuery()) {
                return rs.next() && rs.getInt(1) > 0;
            }

        } catch (Exception e) {
            System.err.println("QR Module DB Error: " + e.getMessage());
            return false;
        }
    }

    private boolean columnExists(Connection con, String tableName, String columnName) {
        String sql = "SELECT COUNT(*) FROM information_schema.columns WHERE table_schema = DATABASE() AND table_name = ? AND column_name = ?";

        try (PreparedStatement ps = con.prepareStatement(sql)) {
            ps.setString(1, tableName);
            ps.setString(2, columnName);

            try (ResultSet rs = ps.executeQuery()) {
                return rs.next() && rs.getInt(1) > 0;
            }

        } catch (Exception e) {
            System.err.println("QR Module DB Error: " + e.getMessage());
            return false;
        }
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

    private void addBorder(XSSFCellStyle style, XSSFColor borderGrey) {
        style.setBorderTop(BorderStyle.THIN);
        style.setBorderBottom(BorderStyle.THIN);
        style.setBorderLeft(BorderStyle.THIN);
        style.setBorderRight(BorderStyle.THIN);
        style.setTopBorderColor(borderGrey);
        style.setBottomBorderColor(borderGrey);
        style.setLeftBorderColor(borderGrey);
        style.setRightBorderColor(borderGrey);
    }

    private XSSFCellStyle createTitleStyle(XSSFWorkbook workbook, XSSFColor navy, XSSFColor white) {
        XSSFFont font = workbook.createFont();
        font.setBold(true);
        font.setFontHeightInPoints((short) 18);
        font.setColor(white);

        XSSFCellStyle style = workbook.createCellStyle();
        style.setFont(font);
        style.setFillForegroundColor(navy);
        style.setFillPattern(FillPatternType.SOLID_FOREGROUND);
        style.setAlignment(HorizontalAlignment.CENTER);
        style.setVerticalAlignment(VerticalAlignment.CENTER);

        return style;
    }

    private XSSFCellStyle createSubTitleStyle(XSSFWorkbook workbook, XSSFColor blue) {
        XSSFFont font = workbook.createFont();
        font.setBold(true);
        font.setFontHeightInPoints((short) 12);
        font.setColor(blue);

        XSSFCellStyle style = workbook.createCellStyle();
        style.setFont(font);
        style.setAlignment(HorizontalAlignment.CENTER);
        style.setVerticalAlignment(VerticalAlignment.CENTER);

        return style;
    }

    private XSSFCellStyle createMetaStyle(XSSFWorkbook workbook, XSSFColor grey) {
        XSSFFont font = workbook.createFont();
        font.setBold(true);
        font.setFontHeightInPoints((short) 10);
        font.setColor(grey);

        XSSFCellStyle style = workbook.createCellStyle();
        style.setFont(font);
        style.setAlignment(HorizontalAlignment.CENTER);
        style.setVerticalAlignment(VerticalAlignment.CENTER);

        return style;
    }

    private XSSFCellStyle createHeaderStyle(XSSFWorkbook workbook, XSSFColor blue, XSSFColor white, XSSFColor borderGrey) {
        XSSFFont font = workbook.createFont();
        font.setBold(true);
        font.setFontHeightInPoints((short) 10);
        font.setColor(white);

        XSSFCellStyle style = workbook.createCellStyle();
        style.setFont(font);
        style.setFillForegroundColor(blue);
        style.setFillPattern(FillPatternType.SOLID_FOREGROUND);
        style.setAlignment(HorizontalAlignment.CENTER);
        style.setVerticalAlignment(VerticalAlignment.CENTER);
        style.setWrapText(true);
        addBorder(style, borderGrey);

        return style;
    }

    private XSSFCellStyle createTextStyle(XSSFWorkbook workbook, XSSFColor black, XSSFColor borderGrey) {
        XSSFFont font = workbook.createFont();
        font.setFontHeightInPoints((short) 10);
        font.setColor(black);

        XSSFCellStyle style = workbook.createCellStyle();
        style.setFont(font);
        style.setWrapText(true);
        style.setAlignment(HorizontalAlignment.CENTER);
        style.setVerticalAlignment(VerticalAlignment.CENTER);
        addBorder(style, borderGrey);

        return style;
    }

    private XSSFCellStyle createAlternateStyle(XSSFWorkbook workbook, XSSFCellStyle baseStyle, XSSFColor lightStripe) {
        XSSFCellStyle style = workbook.createCellStyle();
        style.cloneStyleFrom(baseStyle);
        style.setFillForegroundColor(lightStripe);
        style.setFillPattern(FillPatternType.SOLID_FOREGROUND);

        return style;
    }

    private XSSFCellStyle createDateTimeStyle(XSSFWorkbook workbook, XSSFColor black, XSSFColor borderGrey) {
        XSSFCellStyle style = createTextStyle(workbook, black, borderGrey);
        style.setDataFormat(workbook.createDataFormat().getFormat("dd-mmm-yyyy hh:mm"));
        return style;
    }

    private XSSFCellStyle createStatusStyle(XSSFWorkbook workbook, XSSFColor fillColor, XSSFColor textColor, XSSFColor borderGrey) {
        XSSFFont font = workbook.createFont();
        font.setBold(true);
        font.setFontHeightInPoints((short) 10);
        font.setColor(textColor);

        XSSFCellStyle style = workbook.createCellStyle();
        style.setFont(font);
        style.setFillForegroundColor(fillColor);
        style.setFillPattern(FillPatternType.SOLID_FOREGROUND);
        style.setAlignment(HorizontalAlignment.CENTER);
        style.setVerticalAlignment(VerticalAlignment.CENTER);
        style.setWrapText(true);
        addBorder(style, borderGrey);

        return style;
    }

    private void createMergedRow(XSSFSheet sheet, Row row, int firstColumn, int lastColumn, String value, CellStyle style) {
        for (int i = firstColumn; i <= lastColumn; i++) {
            Cell cell = row.createCell(i);

            if (i == firstColumn) {
                cell.setCellValue(value);
            }

            cell.setCellStyle(style);
        }

        sheet.addMergedRegion(new CellRangeAddress(row.getRowNum(), row.getRowNum(), firstColumn, lastColumn));
    }

    private void createTextCell(Row row, int column, Object value, CellStyle style) {
        Cell cell = row.createCell(column);
        cell.setCellValue(safeText(value));
        cell.setCellStyle(style);
    }

    private void createNumberCell(Row row, int column, int value, CellStyle style) {
        Cell cell = row.createCell(column);
        cell.setCellValue(value);
        cell.setCellStyle(style);
    }

    private void createTimestampCell(Row row, int column, Timestamp value, CellStyle dateStyle, CellStyle textStyle) {
        Cell cell = row.createCell(column);

        if (value != null) {
            cell.setCellValue(value);
            cell.setCellStyle(dateStyle);
        } else {
            cell.setCellValue("-");
            cell.setCellStyle(textStyle);
        }
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

    if (!("SUPER_ADMIN".equals(role) || "ADMIN".equals(role))
            && !"ASSET_MANAGER".equalsIgnoreCase(role)
            && !"AUDITOR".equalsIgnoreCase(role)) {
        response.sendRedirect("reports.jsp?access=denied");
        return;
    }

    response.reset();
    response.setContentType("application/vnd.openxmlformats-officedocument.spreadsheetml.sheet");
    response.setHeader("Content-Disposition", "attachment; filename=\"IR_AMS_QR_Scan_Logs_Report.xlsx\"");

    out.clear();
    out = pageContext.pushBody();

    Connection con = null;
    PreparedStatement ps = null;
    ResultSet rs = null;
    XSSFWorkbook workbook = null;

    try {
        workbook = new XSSFWorkbook();

        XSSFSheet sheet = workbook.createSheet("QR Scan Logs");
        sheet.setZoom(95);
        sheet.setDisplayGridlines(false);

        DefaultIndexedColorMap colorMap = new DefaultIndexedColorMap();

        XSSFColor navy = new XSSFColor(new java.awt.Color(0, 32, 96), colorMap);
        XSSFColor blue = new XSSFColor(new java.awt.Color(0, 102, 204), colorMap);
        XSSFColor white = new XSSFColor(new java.awt.Color(255, 255, 255), colorMap);
        XSSFColor black = new XSSFColor(new java.awt.Color(0, 0, 0), colorMap);
        XSSFColor grey = new XSSFColor(new java.awt.Color(90, 105, 130), colorMap);
        XSSFColor stripe = new XSSFColor(new java.awt.Color(248, 251, 255), colorMap);
        XSSFColor borderGrey = new XSSFColor(new java.awt.Color(191, 191, 191), colorMap);

        XSSFColor validFill = new XSSFColor(new java.awt.Color(226, 239, 218), colorMap);
        XSSFColor validText = new XSSFColor(new java.awt.Color(0, 97, 0), colorMap);
        XSSFColor invalidFill = new XSSFColor(new java.awt.Color(252, 228, 214), colorMap);
        XSSFColor invalidText = new XSSFColor(new java.awt.Color(156, 0, 6), colorMap);
        XSSFColor warningFill = new XSSFColor(new java.awt.Color(255, 242, 204), colorMap);
        XSSFColor warningText = new XSSFColor(new java.awt.Color(156, 87, 0), colorMap);

        XSSFCellStyle titleStyle = createTitleStyle(workbook, navy, white);
        XSSFCellStyle subtitleStyle = createSubTitleStyle(workbook, blue);
        XSSFCellStyle metaStyle = createMetaStyle(workbook, grey);
        XSSFCellStyle headerStyle = createHeaderStyle(workbook, blue, white, borderGrey);
        XSSFCellStyle textStyle = createTextStyle(workbook, black, borderGrey);
        XSSFCellStyle alternateStyle = createAlternateStyle(workbook, textStyle, stripe);
        XSSFCellStyle dateTimeStyle = createDateTimeStyle(workbook, black, borderGrey);

        XSSFCellStyle validStyle = createStatusStyle(workbook, validFill, validText, borderGrey);
        XSSFCellStyle invalidStyle = createStatusStyle(workbook, invalidFill, invalidText, borderGrey);
        XSSFCellStyle warningStyle = createStatusStyle(workbook, warningFill, warningText, borderGrey);

        con = DBConnection.getConnection();

        boolean hasScanTable = tableExists(con, "asset_qr_scan_logs");
        boolean hasAssetsTable = tableExists(con, "assets");
        boolean hasUsersTable = tableExists(con, "users");

        boolean sHasScanLogId = hasScanTable && columnExists(con, "asset_qr_scan_logs", "scan_log_id");
        boolean sHasLogId = hasScanTable && columnExists(con, "asset_qr_scan_logs", "log_id");
        boolean sHasScanId = hasScanTable && columnExists(con, "asset_qr_scan_logs", "scan_id");
        boolean sHasAssetId = hasScanTable && columnExists(con, "asset_qr_scan_logs", "asset_id");
        boolean sHasScanToken = hasScanTable && columnExists(con, "asset_qr_scan_logs", "scan_token");
        boolean sHasQrPublicToken = hasScanTable && columnExists(con, "asset_qr_scan_logs", "qr_public_token");
        boolean sHasToken = hasScanTable && columnExists(con, "asset_qr_scan_logs", "token");
        boolean sHasScanStatus = hasScanTable && columnExists(con, "asset_qr_scan_logs", "scan_status");
        boolean sHasScannedBy = hasScanTable && columnExists(con, "asset_qr_scan_logs", "scanned_by");
        boolean sHasUserId = hasScanTable && columnExists(con, "asset_qr_scan_logs", "user_id");
        boolean sHasScanTime = hasScanTable && columnExists(con, "asset_qr_scan_logs", "scan_time");
        boolean sHasScannedAt = hasScanTable && columnExists(con, "asset_qr_scan_logs", "scanned_at");
        boolean sHasCreatedAt = hasScanTable && columnExists(con, "asset_qr_scan_logs", "created_at");
        boolean sHasIpAddress = hasScanTable && columnExists(con, "asset_qr_scan_logs", "ip_address");
        boolean sHasUserAgent = hasScanTable && columnExists(con, "asset_qr_scan_logs", "user_agent");
        boolean sHasRemarks = hasScanTable && columnExists(con, "asset_qr_scan_logs", "remarks");

        boolean aHasAssetId = hasAssetsTable && columnExists(con, "assets", "asset_id");
        boolean aHasAssetCode = hasAssetsTable && columnExists(con, "assets", "asset_code");
        boolean aHasRailwayAssetNo = hasAssetsTable && columnExists(con, "assets", "railway_asset_no");
        boolean aHasAssetName = hasAssetsTable && columnExists(con, "assets", "asset_name");

        boolean uHasUserId = hasUsersTable && columnExists(con, "users", "user_id");
        boolean uHasUsername = hasUsersTable && columnExists(con, "users", "username");

        boolean joinAssets = hasScanTable && hasAssetsTable && sHasAssetId && aHasAssetId;
        boolean joinUsersByScannedBy = hasScanTable && hasUsersTable && sHasScannedBy && uHasUserId;
        boolean joinUsersByUserId = hasScanTable && hasUsersTable && sHasUserId && uHasUserId && !joinUsersByScannedBy;

        int totalScans = hasScanTable ? sqlInt(con, "SELECT COUNT(*) FROM asset_qr_scan_logs") : 0;
        int validScans = hasScanTable && sHasScanStatus ? sqlInt(con, "SELECT COUNT(*) FROM asset_qr_scan_logs WHERE scan_status IN ('VALID','SUCCESS','ASSET_FOUND')") : 0;
        int invalidScans = hasScanTable && sHasScanStatus ? sqlInt(con, "SELECT COUNT(*) FROM asset_qr_scan_logs WHERE scan_status IN ('INVALID','INVALID_TOKEN','NOT_FOUND')") : 0;
        int todayScans = hasScanTable && sHasCreatedAt ? sqlInt(con, "SELECT COUNT(*) FROM asset_qr_scan_logs WHERE DATE(created_at) = CURDATE()") : 0;

        String[] headers = {
            "Sl No.",
            "Scan Log ID",
            "Asset Code",
            "Asset Name",
            "Scan Token",
            "Scan Status",
            "Scanned By",
            "Scan Time",
            "IP Address",
            "User Agent",
            "Remarks"
        };

        int lastColumnIndex = headers.length - 1;
        int rowIndex = 0;

        Row titleRow = sheet.createRow(rowIndex++);
        titleRow.setHeightInPoints(32);
        createMergedRow(sheet, titleRow, 0, lastColumnIndex, "INDIAN RAILWAY ASSET MANAGEMENT SYSTEM", titleStyle);

        Row subtitleRow = sheet.createRow(rowIndex++);
        subtitleRow.setHeightInPoints(24);
        createMergedRow(sheet, subtitleRow, 0, lastColumnIndex, "QR Scan Logs Report - East Coast Railway / Rail Sadan, Bhubaneswar", subtitleStyle);

        String generatedTime = LocalDateTime.now().format(DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss"));

        Row generatedRow = sheet.createRow(rowIndex++);
        generatedRow.setHeightInPoints(23);
        createMergedRow(sheet, generatedRow, 0, lastColumnIndex,
                "Generated By: " + username + " | Role: " + cleanLabel(role) + " | Generated On: " + generatedTime,
                metaStyle);

        Row kpiRow = sheet.createRow(rowIndex++);
        kpiRow.setHeightInPoints(23);
        createMergedRow(sheet, kpiRow, 0, lastColumnIndex,
                "Total Scans: " + totalScans
                + " | Valid: " + validScans
                + " | Invalid: " + invalidScans
                + " | Today: " + todayScans,
                metaStyle);

        Row blankRow = sheet.createRow(rowIndex++);
        blankRow.setHeightInPoints(8);

        int headerRowIndex = rowIndex;

        Row headerRow = sheet.createRow(rowIndex++);
        headerRow.setHeightInPoints(32);

        for (int i = 0; i < headers.length; i++) {
            Cell cell = headerRow.createCell(i);
            cell.setCellValue(headers[i]);
            cell.setCellStyle(headerStyle);
        }

        if (!hasScanTable) {
            Row noTableRow = sheet.createRow(rowIndex++);
            noTableRow.setHeightInPoints(30);
            createMergedRow(sheet, noTableRow, 0, lastColumnIndex,
                    "asset_qr_scan_logs table was not found in the current database.",
                    textStyle);

        } else {
            String scanIdExpr = sHasScanLogId
                    ? "CAST(s.scan_log_id AS CHAR)"
                    : (sHasLogId ? "CAST(s.log_id AS CHAR)" : (sHasScanId ? "CAST(s.scan_id AS CHAR)" : "''"));

            String assetCodeExpr = joinAssets
                    ? (aHasAssetCode ? "COALESCE(a.asset_code, '')" : (aHasRailwayAssetNo ? "COALESCE(a.railway_asset_no, '')" : "''"))
                    : "''";

            String assetNameExpr = joinAssets && aHasAssetName ? "COALESCE(a.asset_name, '')" : "''";

            String tokenExpr = sHasScanToken
                    ? "COALESCE(s.scan_token, '')"
                    : (sHasQrPublicToken ? "COALESCE(s.qr_public_token, '')" : (sHasToken ? "COALESCE(s.token, '')" : "''"));

            String statusExpr = sHasScanStatus ? "COALESCE(s.scan_status, '')" : "''";

            String scannedByExpr = "''";

            if (joinUsersByScannedBy && uHasUsername) {
                scannedByExpr = "COALESCE(u.username, CAST(s.scanned_by AS CHAR), '')";
            } else if (joinUsersByUserId && uHasUsername) {
                scannedByExpr = "COALESCE(u.username, CAST(s.user_id AS CHAR), '')";
            } else if (sHasScannedBy) {
                scannedByExpr = "COALESCE(CAST(s.scanned_by AS CHAR), '')";
            } else if (sHasUserId) {
                scannedByExpr = "COALESCE(CAST(s.user_id AS CHAR), '')";
            }

            String scanTimeExpr = sHasScanTime ? "s.scan_time" : (sHasScannedAt ? "s.scanned_at" : (sHasCreatedAt ? "s.created_at" : "NULL"));
            String ipExpr = sHasIpAddress ? "COALESCE(s.ip_address, '')" : "''";
            String userAgentExpr = sHasUserAgent ? "COALESCE(s.user_agent, '')" : "''";
            String remarksExpr = sHasRemarks ? "COALESCE(s.remarks, '')" : "''";

            String sql = "SELECT "
                    + scanIdExpr + " AS scan_log_id_display, "
                    + assetCodeExpr + " AS asset_code, "
                    + assetNameExpr + " AS asset_name, "
                    + tokenExpr + " AS scan_token, "
                    + statusExpr + " AS scan_status, "
                    + scannedByExpr + " AS scanned_by_display, "
                    + scanTimeExpr + " AS scan_time, "
                    + ipExpr + " AS ip_address, "
                    + userAgentExpr + " AS user_agent, "
                    + remarksExpr + " AS remarks "
                    + "FROM asset_qr_scan_logs s ";

            if (joinAssets) {
                sql += "LEFT JOIN assets a ON s.asset_id = a.asset_id ";
            }

            if (joinUsersByScannedBy) {
                sql += "LEFT JOIN users u ON s.scanned_by = u.user_id ";
            } else if (joinUsersByUserId) {
                sql += "LEFT JOIN users u ON s.user_id = u.user_id ";
            }

            if (sHasScanTime) {
                sql += "ORDER BY s.scan_time DESC";
            } else if (sHasScannedAt) {
                sql += "ORDER BY s.scanned_at DESC";
            } else if (sHasCreatedAt) {
                sql += "ORDER BY s.created_at DESC";
            }

            ps = con.prepareStatement(sql);
            rs = ps.executeQuery();

            int slNo = 1;
            int dataStartRow = rowIndex;

            while (rs.next()) {
                Row row = sheet.createRow(rowIndex++);
                row.setHeightInPoints(30);

                CellStyle rowTextStyle = (rowIndex % 2 == 0) ? alternateStyle : textStyle;

                int col = 0;

                createNumberCell(row, col++, slNo++, rowTextStyle);
                createTextCell(row, col++, rs.getString("scan_log_id_display"), rowTextStyle);
                createTextCell(row, col++, rs.getString("asset_code"), rowTextStyle);
                createTextCell(row, col++, rs.getString("asset_name"), rowTextStyle);
                createTextCell(row, col++, rs.getString("scan_token"), rowTextStyle);

                String scanStatus = rs.getString("scan_status");
                Cell statusCell = row.createCell(col++);
                statusCell.setCellValue(cleanLabel(scanStatus));

                if ("VALID".equalsIgnoreCase(scanStatus)
                        || "SUCCESS".equalsIgnoreCase(scanStatus)
                        || "ASSET_FOUND".equalsIgnoreCase(scanStatus)) {
                    statusCell.setCellStyle(validStyle);
                } else if ("INVALID".equalsIgnoreCase(scanStatus)
                        || "INVALID_TOKEN".equalsIgnoreCase(scanStatus)
                        || "NOT_FOUND".equalsIgnoreCase(scanStatus)) {
                    statusCell.setCellStyle(invalidStyle);
                } else if ("WARNING".equalsIgnoreCase(scanStatus)
                        || "REVIEW".equalsIgnoreCase(scanStatus)) {
                    statusCell.setCellStyle(warningStyle);
                } else {
                    statusCell.setCellStyle(rowTextStyle);
                }

                createTextCell(row, col++, rs.getString("scanned_by_display"), rowTextStyle);
                createTimestampCell(row, col++, rs.getTimestamp("scan_time"), dateTimeStyle, rowTextStyle);
                createTextCell(row, col++, rs.getString("ip_address"), rowTextStyle);
                createTextCell(row, col++, rs.getString("user_agent"), rowTextStyle);
                createTextCell(row, col++, rs.getString("remarks"), rowTextStyle);
            }

            if (rowIndex == dataStartRow) {
                Row noRecordRow = sheet.createRow(rowIndex++);
                noRecordRow.setHeightInPoints(30);
                createMergedRow(sheet, noRecordRow, 0, lastColumnIndex, "No QR scan logs found.", textStyle);
            }
        }

        sheet.createFreezePane(0, headerRowIndex + 1);
        sheet.setAutoFilter(new CellRangeAddress(headerRowIndex, headerRowIndex, 0, lastColumnIndex));

        sheet.setColumnWidth(0, 3300);
        sheet.setColumnWidth(1, 4300);
        sheet.setColumnWidth(2, 5600);
        sheet.setColumnWidth(3, 8200);
        sheet.setColumnWidth(4, 14000);
        sheet.setColumnWidth(5, 5600);
        sheet.setColumnWidth(6, 6200);
        sheet.setColumnWidth(7, 6200);
        sheet.setColumnWidth(8, 6200);
        sheet.setColumnWidth(9, 16000);
        sheet.setColumnWidth(10, 12000);

        try {
            AuditDAO.log(
                    getSessionUserId(session),
                    "EXPORT",
                    "asset_qr_scan_logs",
                    0,
                    "QR scan logs Excel report exported by " + username
            );
        } catch (Exception auditEx) {
            auditEx.printStackTrace();
        }

        try (ServletOutputStream outputStream = response.getOutputStream()) {
            workbook.write(outputStream);
            outputStream.flush();
        }

    } catch (Exception e) {
        System.err.println("QR Module DB Error: " + e.getMessage());

    } finally {
        try {
            if (rs != null) {
                rs.close();
            }

            if (ps != null) {
                ps.close();
            }

            if (con != null) {
                con.close();
            }

            if (workbook != null) {
                workbook.close();
            }

        } catch (Exception ex) {
            ex.printStackTrace();
        }
    }
%>