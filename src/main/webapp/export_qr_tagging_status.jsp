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
    response.setHeader("Content-Disposition", "attachment; filename=\"IR_AMS_QR_Tagging_Status_Report.xlsx\"");

    out.clear();
    out = pageContext.pushBody();

    Connection con = null;
    PreparedStatement ps = null;
    ResultSet rs = null;
    XSSFWorkbook workbook = null;

    try {
        workbook = new XSSFWorkbook();

        XSSFSheet sheet = workbook.createSheet("QR Tagging Status");
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

        XSSFColor taggedFill = new XSSFColor(new java.awt.Color(226, 239, 218), colorMap);
        XSSFColor taggedText = new XSSFColor(new java.awt.Color(0, 97, 0), colorMap);
        XSSFColor pendingFill = new XSSFColor(new java.awt.Color(255, 242, 204), colorMap);
        XSSFColor pendingText = new XSSFColor(new java.awt.Color(156, 87, 0), colorMap);
        XSSFColor issueFill = new XSSFColor(new java.awt.Color(252, 228, 214), colorMap);
        XSSFColor issueText = new XSSFColor(new java.awt.Color(156, 0, 6), colorMap);

        XSSFCellStyle titleStyle = createTitleStyle(workbook, navy, white);
        XSSFCellStyle subtitleStyle = createSubTitleStyle(workbook, blue);
        XSSFCellStyle metaStyle = createMetaStyle(workbook, grey);
        XSSFCellStyle headerStyle = createHeaderStyle(workbook, blue, white, borderGrey);
        XSSFCellStyle textStyle = createTextStyle(workbook, black, borderGrey);
        XSSFCellStyle alternateStyle = createAlternateStyle(workbook, textStyle, stripe);
        XSSFCellStyle dateTimeStyle = createDateTimeStyle(workbook, black, borderGrey);

        XSSFCellStyle taggedStyle = createStatusStyle(workbook, taggedFill, taggedText, borderGrey);
        XSSFCellStyle pendingStyle = createStatusStyle(workbook, pendingFill, pendingText, borderGrey);
        XSSFCellStyle issueStyle = createStatusStyle(workbook, issueFill, issueText, borderGrey);

        con = DBConnection.getConnection();

        boolean hasTaggingTable = tableExists(con, "asset_qr_tagging_status");
        boolean hasAssetsTable = tableExists(con, "assets");
        boolean hasUsersTable = tableExists(con, "users");

        boolean qHasTaggingId = hasTaggingTable && columnExists(con, "asset_qr_tagging_status", "tagging_id");
        boolean qHasQrTaggingId = hasTaggingTable && columnExists(con, "asset_qr_tagging_status", "qr_tagging_id");
        boolean qHasStatusId = hasTaggingTable && columnExists(con, "asset_qr_tagging_status", "tag_status_id");
        boolean qHasAssetId = hasTaggingTable && columnExists(con, "asset_qr_tagging_status", "asset_id");
        boolean qHasTagStatus = hasTaggingTable && columnExists(con, "asset_qr_tagging_status", "tag_status");
        boolean qHasTagNumber = hasTaggingTable && columnExists(con, "asset_qr_tagging_status", "tag_number");
        boolean qHasPhysicalTagNo = hasTaggingTable && columnExists(con, "asset_qr_tagging_status", "physical_tag_no");
        boolean qHasTaggedBy = hasTaggingTable && columnExists(con, "asset_qr_tagging_status", "tagged_by");
        boolean qHasTaggedOn = hasTaggingTable && columnExists(con, "asset_qr_tagging_status", "tagged_on");
        boolean qHasCreatedAt = hasTaggingTable && columnExists(con, "asset_qr_tagging_status", "created_at");
        boolean qHasRemarks = hasTaggingTable && columnExists(con, "asset_qr_tagging_status", "remarks");

        boolean aHasAssetId = hasAssetsTable && columnExists(con, "assets", "asset_id");
        boolean aHasAssetCode = hasAssetsTable && columnExists(con, "assets", "asset_code");
        boolean aHasRailwayAssetNo = hasAssetsTable && columnExists(con, "assets", "railway_asset_no");
        boolean aHasAssetName = hasAssetsTable && columnExists(con, "assets", "asset_name");
        boolean aHasLocation = hasAssetsTable && columnExists(con, "assets", "location");
        boolean aHasQrPublicToken = hasAssetsTable && columnExists(con, "assets", "qr_public_token");

        boolean uHasUserId = hasUsersTable && columnExists(con, "users", "user_id");
        boolean uHasUsername = hasUsersTable && columnExists(con, "users", "username");

        boolean joinAssets = hasTaggingTable && hasAssetsTable && qHasAssetId && aHasAssetId;
        boolean joinUsers = hasTaggingTable && hasUsersTable && qHasTaggedBy && uHasUserId;

        int totalTagRecords = hasTaggingTable ? sqlInt(con, "SELECT COUNT(*) FROM asset_qr_tagging_status") : 0;
        int taggedCount = hasTaggingTable && qHasTagStatus ? sqlInt(con, "SELECT COUNT(*) FROM asset_qr_tagging_status WHERE tag_status = 'TAGGED'") : 0;
        int pendingCount = hasTaggingTable && qHasTagStatus ? sqlInt(con, "SELECT COUNT(*) FROM asset_qr_tagging_status WHERE tag_status IN ('PENDING','NOT_TAGGED')") : 0;
        int issueCount = hasTaggingTable && qHasTagStatus ? sqlInt(con, "SELECT COUNT(*) FROM asset_qr_tagging_status WHERE tag_status IN ('DAMAGED','MISSING','REPRINT_REQUIRED')") : 0;

        String[] headers = {
            "Sl No.",
            "Tagging ID",
            "Asset Code",
            "Asset Name",
            "Location",
            "QR Public Token",
            "Tag Number",
            "Tag Status",
            "Tagged By",
            "Tagged On",
            "Remarks"
        };

        int lastColumnIndex = headers.length - 1;
        int rowIndex = 0;

        Row titleRow = sheet.createRow(rowIndex++);
        titleRow.setHeightInPoints(32);
        createMergedRow(sheet, titleRow, 0, lastColumnIndex, "INDIAN RAILWAY ASSET MANAGEMENT SYSTEM", titleStyle);

        Row subtitleRow = sheet.createRow(rowIndex++);
        subtitleRow.setHeightInPoints(24);
        createMergedRow(sheet, subtitleRow, 0, lastColumnIndex, "QR Tagging Status Report - East Coast Railway / Rail Sadan, Bhubaneswar", subtitleStyle);

        String generatedTime = LocalDateTime.now().format(DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss"));

        Row generatedRow = sheet.createRow(rowIndex++);
        generatedRow.setHeightInPoints(23);
        createMergedRow(sheet, generatedRow, 0, lastColumnIndex,
                "Generated By: " + username + " | Role: " + cleanLabel(role) + " | Generated On: " + generatedTime,
                metaStyle);

        Row kpiRow = sheet.createRow(rowIndex++);
        kpiRow.setHeightInPoints(23);
        createMergedRow(sheet, kpiRow, 0, lastColumnIndex,
                "Total Tag Records: " + totalTagRecords
                + " | Tagged: " + taggedCount
                + " | Pending: " + pendingCount
                + " | Issue / Reprint: " + issueCount,
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

        if (!hasTaggingTable) {
            Row noTableRow = sheet.createRow(rowIndex++);
            noTableRow.setHeightInPoints(30);
            createMergedRow(sheet, noTableRow, 0, lastColumnIndex,
                    "asset_qr_tagging_status table was not found in the current database.",
                    textStyle);

        } else {
            String taggingIdExpr = qHasTaggingId
                    ? "CAST(q.tagging_id AS CHAR)"
                    : (qHasQrTaggingId
                    ? "CAST(q.qr_tagging_id AS CHAR)"
                    : (qHasStatusId ? "CAST(q.tag_status_id AS CHAR)" : "''"));

            String assetCodeExpr = joinAssets
                    ? (aHasAssetCode
                    ? "COALESCE(a.asset_code, '')"
                    : (aHasRailwayAssetNo ? "COALESCE(a.railway_asset_no, '')" : "''"))
                    : "''";

            String assetNameExpr = joinAssets && aHasAssetName ? "COALESCE(a.asset_name, '')" : "''";
            String locationExpr = joinAssets && aHasLocation ? "COALESCE(a.location, '')" : "''";
            String tokenExpr = joinAssets && aHasQrPublicToken ? "COALESCE(a.qr_public_token, '')" : "''";
            String tagNumberExpr = qHasTagNumber ? "COALESCE(q.tag_number, '')" : (qHasPhysicalTagNo ? "COALESCE(q.physical_tag_no, '')" : "''");
            String statusExpr = qHasTagStatus ? "COALESCE(q.tag_status, '')" : "''";
            String taggedByExpr = joinUsers && uHasUsername
                    ? "COALESCE(u.username, CAST(q.tagged_by AS CHAR), '')"
                    : (qHasTaggedBy ? "COALESCE(CAST(q.tagged_by AS CHAR), '')" : "''");
            String taggedOnExpr = qHasTaggedOn ? "q.tagged_on" : (qHasCreatedAt ? "q.created_at" : "NULL");
            String remarksExpr = qHasRemarks ? "COALESCE(q.remarks, '')" : "''";

            String sql = "SELECT "
                    + taggingIdExpr + " AS tagging_id_display, "
                    + assetCodeExpr + " AS asset_code, "
                    + assetNameExpr + " AS asset_name, "
                    + locationExpr + " AS location, "
                    + tokenExpr + " AS qr_public_token, "
                    + tagNumberExpr + " AS tag_number, "
                    + statusExpr + " AS tag_status, "
                    + taggedByExpr + " AS tagged_by_display, "
                    + taggedOnExpr + " AS tagged_on, "
                    + remarksExpr + " AS remarks "
                    + "FROM asset_qr_tagging_status q ";

            if (joinAssets) {
                sql += "LEFT JOIN assets a ON q.asset_id = a.asset_id ";
            }

            if (joinUsers) {
                sql += "LEFT JOIN users u ON q.tagged_by = u.user_id ";
            }

            if (qHasTaggedOn) {
                sql += "ORDER BY q.tagged_on DESC";
            } else if (qHasCreatedAt) {
                sql += "ORDER BY q.created_at DESC";
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
                createTextCell(row, col++, rs.getString("tagging_id_display"), rowTextStyle);
                createTextCell(row, col++, rs.getString("asset_code"), rowTextStyle);
                createTextCell(row, col++, rs.getString("asset_name"), rowTextStyle);
                createTextCell(row, col++, rs.getString("location"), rowTextStyle);
                createTextCell(row, col++, rs.getString("qr_public_token"), rowTextStyle);
                createTextCell(row, col++, rs.getString("tag_number"), rowTextStyle);

                String status = rs.getString("tag_status");
                Cell statusCell = row.createCell(col++);
                statusCell.setCellValue(cleanLabel(status));

                if ("TAGGED".equalsIgnoreCase(status)) {
                    statusCell.setCellStyle(taggedStyle);
                } else if ("PENDING".equalsIgnoreCase(status) || "NOT_TAGGED".equalsIgnoreCase(status)) {
                    statusCell.setCellStyle(pendingStyle);
                } else if ("DAMAGED".equalsIgnoreCase(status) || "MISSING".equalsIgnoreCase(status) || "REPRINT_REQUIRED".equalsIgnoreCase(status)) {
                    statusCell.setCellStyle(issueStyle);
                } else {
                    statusCell.setCellStyle(rowTextStyle);
                }

                createTextCell(row, col++, rs.getString("tagged_by_display"), rowTextStyle);
                createTimestampCell(row, col++, rs.getTimestamp("tagged_on"), dateTimeStyle, rowTextStyle);
                createTextCell(row, col++, rs.getString("remarks"), rowTextStyle);
            }

            if (rowIndex == dataStartRow) {
                Row noRecordRow = sheet.createRow(rowIndex++);
                noRecordRow.setHeightInPoints(30);
                createMergedRow(sheet, noRecordRow, 0, lastColumnIndex, "No QR tagging records found.", textStyle);
            }
        }

        sheet.createFreezePane(0, headerRowIndex + 1);
        sheet.setAutoFilter(new CellRangeAddress(headerRowIndex, headerRowIndex, 0, lastColumnIndex));

        sheet.setColumnWidth(0, 3300);
        sheet.setColumnWidth(1, 4300);
        sheet.setColumnWidth(2, 5600);
        sheet.setColumnWidth(3, 8200);
        sheet.setColumnWidth(4, 8200);
        sheet.setColumnWidth(5, 14000);
        sheet.setColumnWidth(6, 6200);
        sheet.setColumnWidth(7, 5600);
        sheet.setColumnWidth(8, 6200);
        sheet.setColumnWidth(9, 6200);
        sheet.setColumnWidth(10, 12000);

        try {
            AuditDAO.log(
                    getSessionUserId(session),
                    "EXPORT",
                    "asset_qr_tagging_status",
                    0,
                    "QR tagging status Excel report exported by " + username
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