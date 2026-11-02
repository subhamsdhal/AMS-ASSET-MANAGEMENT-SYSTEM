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
    response.setHeader("Content-Disposition", "attachment; filename=\"IR_AMS_QR_Asset_Register_Report.xlsx\"");

    out.clear();
    out = pageContext.pushBody();

    Connection con = null;
    PreparedStatement ps = null;
    ResultSet rs = null;
    XSSFWorkbook workbook = null;

    try {
        workbook = new XSSFWorkbook();

        XSSFSheet sheet = workbook.createSheet("QR Asset Register");
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

        XSSFColor generatedFill = new XSSFColor(new java.awt.Color(226, 239, 218), colorMap);
        XSSFColor generatedText = new XSSFColor(new java.awt.Color(0, 97, 0), colorMap);
        XSSFColor missingFill = new XSSFColor(new java.awt.Color(252, 228, 214), colorMap);
        XSSFColor missingText = new XSSFColor(new java.awt.Color(156, 0, 6), colorMap);

        XSSFCellStyle titleStyle = createTitleStyle(workbook, navy, white);
        XSSFCellStyle subtitleStyle = createSubTitleStyle(workbook, blue);
        XSSFCellStyle metaStyle = createMetaStyle(workbook, grey);
        XSSFCellStyle headerStyle = createHeaderStyle(workbook, blue, white, borderGrey);
        XSSFCellStyle textStyle = createTextStyle(workbook, black, borderGrey);
        XSSFCellStyle alternateStyle = createAlternateStyle(workbook, textStyle, stripe);
        XSSFCellStyle dateTimeStyle = createDateTimeStyle(workbook, black, borderGrey);
        XSSFCellStyle generatedStyle = createStatusStyle(workbook, generatedFill, generatedText, borderGrey);
        XSSFCellStyle missingStyle = createStatusStyle(workbook, missingFill, missingText, borderGrey);

        con = DBConnection.getConnection();

        boolean hasAssetsTable = tableExists(con, "assets");
        boolean hasCategoryTable = tableExists(con, "asset_categories");

        boolean aHasAssetId = hasAssetsTable && columnExists(con, "assets", "asset_id");
        boolean aHasAssetCode = hasAssetsTable && columnExists(con, "assets", "asset_code");
        boolean aHasRailwayAssetNo = hasAssetsTable && columnExists(con, "assets", "railway_asset_no");
        boolean aHasAssetName = hasAssetsTable && columnExists(con, "assets", "asset_name");
        boolean aHasCategoryId = hasAssetsTable && columnExists(con, "assets", "category_id");
        boolean aHasStatus = hasAssetsTable && columnExists(con, "assets", "asset_status");
        boolean aHasLocation = hasAssetsTable && columnExists(con, "assets", "location");
        boolean aHasQrCode = hasAssetsTable && columnExists(con, "assets", "qr_code");
        boolean aHasQrPublicToken = hasAssetsTable && columnExists(con, "assets", "qr_public_token");
        boolean aHasQrImagePath = hasAssetsTable && columnExists(con, "assets", "qr_image_path");
        boolean aHasQrGeneratedAt = hasAssetsTable && columnExists(con, "assets", "qr_generated_at");
        boolean aHasCreatedAt = hasAssetsTable && columnExists(con, "assets", "created_at");

        boolean cHasCategoryId = hasCategoryTable && columnExists(con, "asset_categories", "category_id");
        boolean cHasCategoryName = hasCategoryTable && columnExists(con, "asset_categories", "category_name");

        boolean joinCategory = hasAssetsTable && hasCategoryTable && aHasCategoryId && cHasCategoryId;

        int totalAssets = hasAssetsTable ? sqlInt(con, "SELECT COUNT(*) FROM assets") : 0;
        int qrGenerated = hasAssetsTable && aHasQrPublicToken
                ? sqlInt(con, "SELECT COUNT(*) FROM assets WHERE qr_public_token IS NOT NULL AND TRIM(qr_public_token) <> ''")
                : 0;
        int qrMissing = Math.max(totalAssets - qrGenerated, 0);

        String[] headers = {
            "Sl No.",
            "Asset ID",
            "Asset Code",
            "Asset Name",
            "Category",
            "Asset Status",
            "Location",
            "QR Status",
            "QR Code",
            "QR Public Token",
            "QR Image Path",
            "QR Generated On"
        };

        int lastColumnIndex = headers.length - 1;
        int rowIndex = 0;

        Row titleRow = sheet.createRow(rowIndex++);
        titleRow.setHeightInPoints(32);
        createMergedRow(sheet, titleRow, 0, lastColumnIndex, "INDIAN RAILWAY ASSET MANAGEMENT SYSTEM", titleStyle);

        Row subtitleRow = sheet.createRow(rowIndex++);
        subtitleRow.setHeightInPoints(24);
        createMergedRow(sheet, subtitleRow, 0, lastColumnIndex, "QR Asset Register Report - East Coast Railway / Rail Sadan, Bhubaneswar", subtitleStyle);

        String generatedTime = LocalDateTime.now().format(DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss"));

        Row generatedRow = sheet.createRow(rowIndex++);
        generatedRow.setHeightInPoints(23);
        createMergedRow(sheet, generatedRow, 0, lastColumnIndex,
                "Generated By: " + username + " | Role: " + cleanLabel(role) + " | Generated On: " + generatedTime,
                metaStyle);

        Row kpiRow = sheet.createRow(rowIndex++);
        kpiRow.setHeightInPoints(23);
        createMergedRow(sheet, kpiRow, 0, lastColumnIndex,
                "Total Assets: " + totalAssets + " | QR Generated: " + qrGenerated + " | QR Missing: " + qrMissing,
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

        if (!hasAssetsTable) {
            Row noTableRow = sheet.createRow(rowIndex++);
            noTableRow.setHeightInPoints(30);
            createMergedRow(sheet, noTableRow, 0, lastColumnIndex,
                    "assets table was not found in the current database.",
                    textStyle);

        } else {
            String assetIdExpr = aHasAssetId ? "CAST(a.asset_id AS CHAR)" : "''";
            String assetCodeExpr = aHasAssetCode
                    ? "COALESCE(a.asset_code, '')"
                    : (aHasRailwayAssetNo ? "COALESCE(a.railway_asset_no, '')" : "''");
            String assetNameExpr = aHasAssetName ? "COALESCE(a.asset_name, '')" : "''";
            String categoryExpr = joinCategory && cHasCategoryName ? "COALESCE(c.category_name, '')" : "''";
            String statusExpr = aHasStatus ? "COALESCE(a.asset_status, '')" : "''";
            String locationExpr = aHasLocation ? "COALESCE(a.location, '')" : "''";
            String qrCodeExpr = aHasQrCode ? "COALESCE(a.qr_code, '')" : "''";
            String qrTokenExpr = aHasQrPublicToken ? "COALESCE(a.qr_public_token, '')" : "''";
            String qrImageExpr = aHasQrImagePath ? "COALESCE(a.qr_image_path, '')" : "''";
            String qrGeneratedExpr = aHasQrGeneratedAt ? "a.qr_generated_at" : (aHasCreatedAt ? "a.created_at" : "NULL");

            String sql = "SELECT "
                    + assetIdExpr + " AS asset_id_display, "
                    + assetCodeExpr + " AS asset_code, "
                    + assetNameExpr + " AS asset_name, "
                    + categoryExpr + " AS category_name, "
                    + statusExpr + " AS asset_status, "
                    + locationExpr + " AS location, "
                    + qrCodeExpr + " AS qr_code, "
                    + qrTokenExpr + " AS qr_public_token, "
                    + qrImageExpr + " AS qr_image_path, "
                    + qrGeneratedExpr + " AS qr_generated_at "
                    + "FROM assets a ";

            if (joinCategory) {
                sql += "LEFT JOIN asset_categories c ON a.category_id = c.category_id ";
            }

            if (aHasAssetId) {
                sql += "ORDER BY a.asset_id ASC";
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
                createTextCell(row, col++, rs.getString("asset_id_display"), rowTextStyle);
                createTextCell(row, col++, rs.getString("asset_code"), rowTextStyle);
                createTextCell(row, col++, rs.getString("asset_name"), rowTextStyle);
                createTextCell(row, col++, cleanLabel(rs.getString("category_name")), rowTextStyle);
                createTextCell(row, col++, cleanLabel(rs.getString("asset_status")), rowTextStyle);
                createTextCell(row, col++, rs.getString("location"), rowTextStyle);

                String token = rs.getString("qr_public_token");
                Cell qrStatusCell = row.createCell(col++);

                if (token != null && !token.trim().isEmpty()) {
                    qrStatusCell.setCellValue("Generated");
                    qrStatusCell.setCellStyle(generatedStyle);
                } else {
                    qrStatusCell.setCellValue("Missing");
                    qrStatusCell.setCellStyle(missingStyle);
                }

                createTextCell(row, col++, rs.getString("qr_code"), rowTextStyle);
                createTextCell(row, col++, rs.getString("qr_public_token"), rowTextStyle);
                createTextCell(row, col++, rs.getString("qr_image_path"), rowTextStyle);
                createTimestampCell(row, col++, rs.getTimestamp("qr_generated_at"), dateTimeStyle, rowTextStyle);
            }

            if (rowIndex == dataStartRow) {
                Row noRecordRow = sheet.createRow(rowIndex++);
                noRecordRow.setHeightInPoints(30);
                createMergedRow(sheet, noRecordRow, 0, lastColumnIndex, "No QR asset register records found.", textStyle);
            }
        }

        sheet.createFreezePane(0, headerRowIndex + 1);
        sheet.setAutoFilter(new CellRangeAddress(headerRowIndex, headerRowIndex, 0, lastColumnIndex));

        sheet.setColumnWidth(0, 3300);
        sheet.setColumnWidth(1, 4300);
        sheet.setColumnWidth(2, 5600);
        sheet.setColumnWidth(3, 8200);
        sheet.setColumnWidth(4, 6200);
        sheet.setColumnWidth(5, 5600);
        sheet.setColumnWidth(6, 8200);
        sheet.setColumnWidth(7, 5200);
        sheet.setColumnWidth(8, 9000);
        sheet.setColumnWidth(9, 14000);
        sheet.setColumnWidth(10, 14000);
        sheet.setColumnWidth(11, 6200);

        try {
            AuditDAO.log(
                    getSessionUserId(session),
                    "EXPORT",
                    "qr_asset_register",
                    0,
                    "QR asset register Excel report exported by " + username
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