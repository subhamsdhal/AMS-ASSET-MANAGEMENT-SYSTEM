<%@page contentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet" pageEncoding="UTF-8" trimDirectiveWhitespaces="true"%>
<%@page import="java.sql.*"%>
<%@page import="java.time.LocalDateTime"%>
<%@page import="java.time.format.DateTimeFormatter"%>
<%@page import="jakarta.servlet.ServletOutputStream"%>
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
        String sql = "SELECT COUNT(*) FROM information_schema.tables "
                + "WHERE table_schema = DATABASE() AND table_name = ?";

        try (PreparedStatement ps = con.prepareStatement(sql)) {
            ps.setString(1, tableName);

            try (ResultSet rs = ps.executeQuery()) {
                return rs.next() && rs.getInt(1) > 0;
            }

        } catch (Exception e) {
            e.printStackTrace();
            return false;
        }
    }

    private boolean columnExists(Connection con, String tableName, String columnName) {
        String sql = "SELECT COUNT(*) FROM information_schema.columns "
                + "WHERE table_schema = DATABASE() AND table_name = ? AND column_name = ?";

        try (PreparedStatement ps = con.prepareStatement(sql)) {
            ps.setString(1, tableName);
            ps.setString(2, columnName);

            try (ResultSet rs = ps.executeQuery()) {
                return rs.next() && rs.getInt(1) > 0;
            }

        } catch (Exception e) {
            e.printStackTrace();
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
            e.printStackTrace();
        }

        return 0;
    }

    private double sqlDouble(Connection con, String sql) {
        try (PreparedStatement ps = con.prepareStatement(sql);
             ResultSet rs = ps.executeQuery()) {

            if (rs.next()) {
                return rs.getDouble(1);
            }

        } catch (Exception e) {
            e.printStackTrace();
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

    private XSSFCellStyle createSubTitleStyle(XSSFWorkbook workbook, XSSFColor deepBlue) {
        XSSFFont font = workbook.createFont();
        font.setBold(true);
        font.setFontHeightInPoints((short) 12);
        font.setColor(deepBlue);

        XSSFCellStyle style = workbook.createCellStyle();
        style.setFont(font);
        style.setAlignment(HorizontalAlignment.CENTER);
        style.setVerticalAlignment(VerticalAlignment.CENTER);

        return style;
    }

    private XSSFCellStyle createMetaStyle(XSSFWorkbook workbook, XSSFColor greyText) {
        XSSFFont font = workbook.createFont();
        font.setBold(true);
        font.setFontHeightInPoints((short) 10);
        font.setColor(greyText);

        XSSFCellStyle style = workbook.createCellStyle();
        style.setFont(font);
        style.setAlignment(HorizontalAlignment.CENTER);
        style.setVerticalAlignment(VerticalAlignment.CENTER);

        return style;
    }

    private XSSFCellStyle createHeaderStyle(XSSFWorkbook workbook, XSSFColor deepBlue, XSSFColor white, XSSFColor borderGrey) {
        XSSFFont font = workbook.createFont();
        font.setBold(true);
        font.setFontHeightInPoints((short) 10);
        font.setColor(white);

        XSSFCellStyle style = workbook.createCellStyle();
        style.setFont(font);
        style.setFillForegroundColor(deepBlue);
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

    private XSSFCellStyle createDateStyle(XSSFWorkbook workbook, XSSFColor black, XSSFColor borderGrey) {
        XSSFFont font = workbook.createFont();
        font.setFontHeightInPoints((short) 10);
        font.setColor(black);

        XSSFCellStyle style = workbook.createCellStyle();
        style.setFont(font);
        style.setDataFormat(workbook.createDataFormat().getFormat("dd-mmm-yyyy"));
        style.setAlignment(HorizontalAlignment.CENTER);
        style.setVerticalAlignment(VerticalAlignment.CENTER);
        addBorder(style, borderGrey);

        return style;
    }

    private XSSFCellStyle createAmountStyle(XSSFWorkbook workbook, XSSFColor black, XSSFColor borderGrey) {
        XSSFFont font = workbook.createFont();
        font.setFontHeightInPoints((short) 10);
        font.setColor(black);

        XSSFCellStyle style = workbook.createCellStyle();
        style.setFont(font);
        style.setDataFormat(workbook.createDataFormat().getFormat("₹#,##0.00"));
        style.setAlignment(HorizontalAlignment.CENTER);
        style.setVerticalAlignment(VerticalAlignment.CENTER);
        addBorder(style, borderGrey);

        return style;
    }

    private XSSFCellStyle createStatusStyle(
            XSSFWorkbook workbook,
            XSSFColor fillColor,
            XSSFColor textColor,
            XSSFColor borderGrey) {

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

    private void createMergedRow(
            XSSFSheet sheet,
            Row row,
            int firstColumn,
            int lastColumn,
            String value,
            CellStyle style) {

        for (int i = firstColumn; i <= lastColumn; i++) {
            Cell cell = row.createCell(i);

            if (i == firstColumn) {
                cell.setCellValue(value);
            }

            cell.setCellStyle(style);
        }

        sheet.addMergedRegion(new CellRangeAddress(
                row.getRowNum(),
                row.getRowNum(),
                firstColumn,
                lastColumn
        ));
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

    private void createAmountCell(Row row, int column, double value, CellStyle style) {
        Cell cell = row.createCell(column);
        cell.setCellValue(value);
        cell.setCellStyle(style);
    }

    private void createDateCell(Row row, int column, Date value, CellStyle dateStyle, CellStyle textStyle) {
        Cell cell = row.createCell(column);

        if (value != null) {
            cell.setCellValue(value);
            cell.setCellStyle(dateStyle);
        } else {
            cell.setCellValue("-");
            cell.setCellStyle(textStyle);
        }
    }

    private CellStyle getStatusStyle(String status, CellStyle disposedStyle, CellStyle textStyle) {
        if (status == null) {
            return textStyle;
        }

        String s = status.trim().toUpperCase();

        if (s.contains("DISPOSED") || s.contains("SCRAPPED") || s.contains("WRITTEN")) {
            return disposedStyle;
        }

        return textStyle;
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
    response.setHeader("Content-Disposition", "attachment; filename=\"IR_AMS_Disposal_Report.xlsx\"");

    out.clear();
    out = pageContext.pushBody();

    Connection con = null;
    PreparedStatement ps = null;
    ResultSet rs = null;
    XSSFWorkbook workbook = null;

    try {
        workbook = new XSSFWorkbook();

        XSSFSheet sheet = workbook.createSheet("Disposal Report");
        sheet.setZoom(95);
        sheet.setDisplayGridlines(false);

        DefaultIndexedColorMap colorMap = new DefaultIndexedColorMap();

        XSSFColor navy = new XSSFColor(new java.awt.Color(0, 32, 96), colorMap);
        XSSFColor deepBlue = new XSSFColor(new java.awt.Color(0, 102, 204), colorMap);
        XSSFColor white = new XSSFColor(new java.awt.Color(255, 255, 255), colorMap);
        XSSFColor black = new XSSFColor(new java.awt.Color(0, 0, 0), colorMap);
        XSSFColor greyText = new XSSFColor(new java.awt.Color(90, 105, 130), colorMap);
        XSSFColor lightStripe = new XSSFColor(new java.awt.Color(248, 251, 255), colorMap);
        XSSFColor borderGrey = new XSSFColor(new java.awt.Color(191, 191, 191), colorMap);

        XSSFColor disposedFill = new XSSFColor(new java.awt.Color(252, 228, 214), colorMap);
        XSSFColor disposedText = new XSSFColor(new java.awt.Color(156, 0, 6), colorMap);

        XSSFCellStyle titleStyle = createTitleStyle(workbook, navy, white);
        XSSFCellStyle subtitleStyle = createSubTitleStyle(workbook, deepBlue);
        XSSFCellStyle metaStyle = createMetaStyle(workbook, greyText);
        XSSFCellStyle headerStyle = createHeaderStyle(workbook, deepBlue, white, borderGrey);
        XSSFCellStyle textStyle = createTextStyle(workbook, black, borderGrey);
        XSSFCellStyle alternateStyle = createAlternateStyle(workbook, textStyle, lightStripe);
        XSSFCellStyle dateStyle = createDateStyle(workbook, black, borderGrey);
        XSSFCellStyle amountStyle = createAmountStyle(workbook, black, borderGrey);
        XSSFCellStyle disposedStyle = createStatusStyle(workbook, disposedFill, disposedText, borderGrey);

        con = DBConnection.getConnection();

        boolean hasDisposalTable = tableExists(con, "asset_disposal");
        boolean hasAssetsTable = tableExists(con, "assets");
        boolean hasCategoryTable = tableExists(con, "asset_categories");
        boolean hasUsersTable = tableExists(con, "users");

        boolean dHasDisposalId = hasDisposalTable && columnExists(con, "asset_disposal", "disposal_id");
        boolean dHasAssetId = hasDisposalTable && columnExists(con, "asset_disposal", "asset_id");
        boolean dHasDate = hasDisposalTable && columnExists(con, "asset_disposal", "disposal_date");
        boolean dHasReason = hasDisposalTable && columnExists(con, "asset_disposal", "disposal_reason");
        boolean dHasValue = hasDisposalTable && columnExists(con, "asset_disposal", "disposal_value");
        boolean dHasApprovedBy = hasDisposalTable && columnExists(con, "asset_disposal", "approved_by");
        boolean dHasRemarks = hasDisposalTable && columnExists(con, "asset_disposal", "remarks");
        boolean dHasCreatedAt = hasDisposalTable && columnExists(con, "asset_disposal", "created_at");

        boolean aHasAssetId = hasAssetsTable && columnExists(con, "assets", "asset_id");
        boolean aHasAssetCode = hasAssetsTable && columnExists(con, "assets", "asset_code");
        boolean aHasRailwayAssetNo = hasAssetsTable && columnExists(con, "assets", "railway_asset_no");
        boolean aHasAssetName = hasAssetsTable && columnExists(con, "assets", "asset_name");
        boolean aHasCategoryId = hasAssetsTable && columnExists(con, "assets", "category_id");
        boolean aHasStatus = hasAssetsTable && columnExists(con, "assets", "asset_status");

        boolean cHasCategoryId = hasCategoryTable && columnExists(con, "asset_categories", "category_id");
        boolean cHasCategoryName = hasCategoryTable && columnExists(con, "asset_categories", "category_name");

        boolean uHasUserId = hasUsersTable && columnExists(con, "users", "user_id");
        boolean uHasUsername = hasUsersTable && columnExists(con, "users", "username");

        boolean joinAssets = hasDisposalTable && hasAssetsTable && dHasAssetId && aHasAssetId;
        boolean joinCategory = joinAssets && hasCategoryTable && aHasCategoryId && cHasCategoryId;
        boolean joinUsers = hasDisposalTable && hasUsersTable && dHasApprovedBy && uHasUserId;

        int totalDisposals = hasDisposalTable ? sqlInt(con, "SELECT COUNT(*) FROM asset_disposal") : 0;
        double totalDisposalValue = (hasDisposalTable && dHasValue)
                ? sqlDouble(con, "SELECT COALESCE(SUM(disposal_value), 0) FROM asset_disposal")
                : 0.0;
        int currentYearDisposals = (hasDisposalTable && dHasDate)
                ? sqlInt(con, "SELECT COUNT(*) FROM asset_disposal WHERE YEAR(disposal_date) = YEAR(CURDATE())")
                : 0;
        int assetsCovered = (hasDisposalTable && dHasAssetId)
                ? sqlInt(con, "SELECT COUNT(DISTINCT asset_id) FROM asset_disposal")
                : 0;

        String[] headers = {
            "Sl No.",
            "Disposal ID",
            "Asset Code",
            "Asset Name",
            "Category",
            "Disposal Date",
            "Disposal Reason",
            "Disposal Value",
            "Approved By",
            "Asset Status",
            "Remarks",
            "Created On"
        };

        int lastColumnIndex = headers.length - 1;
        int rowIndex = 0;

        Row titleRow = sheet.createRow(rowIndex++);
        titleRow.setHeightInPoints(32);
        createMergedRow(
                sheet,
                titleRow,
                0,
                lastColumnIndex,
                "INDIAN RAILWAY ASSET MANAGEMENT SYSTEM",
                titleStyle
        );

        Row subtitleRow = sheet.createRow(rowIndex++);
        subtitleRow.setHeightInPoints(24);
        createMergedRow(
                sheet,
                subtitleRow,
                0,
                lastColumnIndex,
                "Asset Disposal Report - East Coast Railway / Rail Sadan, Bhubaneswar",
                subtitleStyle
        );

        String generatedTime = LocalDateTime.now().format(DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss"));

        Row generatedRow = sheet.createRow(rowIndex++);
        generatedRow.setHeightInPoints(23);
        createMergedRow(
                sheet,
                generatedRow,
                0,
                lastColumnIndex,
                "Generated By: "
                + username
                + " | Role: "
                + cleanLabel(role)
                + " | Generated On: "
                + generatedTime,
                metaStyle
        );

        Row kpiRow = sheet.createRow(rowIndex++);
        kpiRow.setHeightInPoints(23);
        createMergedRow(
                sheet,
                kpiRow,
                0,
                lastColumnIndex,
                "Total Disposals: "
                + totalDisposals
                + " | Current Year: "
                + currentYearDisposals
                + " | Assets Covered: "
                + assetsCovered
                + " | Total Disposal Value: ₹"
                + String.format(java.util.Locale.ENGLISH, "%,.2f", totalDisposalValue),
                metaStyle
        );

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

        if (!hasDisposalTable) {
            Row noTableRow = sheet.createRow(rowIndex++);
            noTableRow.setHeightInPoints(30);
            createMergedRow(
                    sheet,
                    noTableRow,
                    0,
                    lastColumnIndex,
                    "asset_disposal table was not found in the current database.",
                    textStyle
            );

        } else {
            String disposalIdExpr = dHasDisposalId ? "CAST(d.disposal_id AS CHAR)" : "''";
            String assetCodeExpr = joinAssets
                    ? (aHasAssetCode
                    ? "COALESCE(a.asset_code, '')"
                    : (aHasRailwayAssetNo ? "COALESCE(a.railway_asset_no, '')" : "''"))
                    : "''";
            String assetNameExpr = joinAssets && aHasAssetName ? "COALESCE(a.asset_name, '')" : "''";
            String categoryExpr = joinCategory && cHasCategoryName ? "COALESCE(c.category_name, '')" : "''";
            String dateExpr = dHasDate ? "d.disposal_date" : "NULL";
            String reasonExpr = dHasReason ? "COALESCE(d.disposal_reason, '')" : "''";
            String valueExpr = dHasValue ? "COALESCE(d.disposal_value, 0)" : "0";
            String approvedByExpr = joinUsers && uHasUsername
                    ? "COALESCE(u.username, CAST(d.approved_by AS CHAR), '')"
                    : (dHasApprovedBy ? "COALESCE(CAST(d.approved_by AS CHAR), '')" : "''");
            String statusExpr = joinAssets && aHasStatus ? "COALESCE(a.asset_status, '')" : "''";
            String remarksExpr = dHasRemarks ? "COALESCE(d.remarks, '')" : "''";
            String createdAtExpr = dHasCreatedAt ? "d.created_at" : "NULL";

            String sql = "SELECT "
                    + disposalIdExpr + " AS disposal_id_display, "
                    + assetCodeExpr + " AS asset_code, "
                    + assetNameExpr + " AS asset_name, "
                    + categoryExpr + " AS category_name, "
                    + dateExpr + " AS disposal_date, "
                    + reasonExpr + " AS disposal_reason, "
                    + valueExpr + " AS disposal_value, "
                    + approvedByExpr + " AS approved_by_display, "
                    + statusExpr + " AS asset_status, "
                    + remarksExpr + " AS remarks, "
                    + createdAtExpr + " AS created_at "
                    + "FROM asset_disposal d ";

            if (joinAssets) {
                sql += "LEFT JOIN assets a ON d.asset_id = a.asset_id ";
            }

            if (joinCategory) {
                sql += "LEFT JOIN asset_categories c ON a.category_id = c.category_id ";
            }

            if (joinUsers) {
                sql += "LEFT JOIN users u ON d.approved_by = u.user_id ";
            }

            if (dHasDate) {
                sql += "ORDER BY d.disposal_date DESC";
            } else if (dHasDisposalId) {
                sql += "ORDER BY d.disposal_id DESC";
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
                createTextCell(row, col++, rs.getString("disposal_id_display"), rowTextStyle);
                createTextCell(row, col++, rs.getString("asset_code"), rowTextStyle);
                createTextCell(row, col++, rs.getString("asset_name"), rowTextStyle);
                createTextCell(row, col++, cleanLabel(rs.getString("category_name")), rowTextStyle);
                createDateCell(row, col++, rs.getDate("disposal_date"), dateStyle, rowTextStyle);
                createTextCell(row, col++, rs.getString("disposal_reason"), rowTextStyle);
                createAmountCell(row, col++, rs.getDouble("disposal_value"), amountStyle);
                createTextCell(row, col++, rs.getString("approved_by_display"), rowTextStyle);

                String status = rs.getString("asset_status");
                Cell statusCell = row.createCell(col++);
                statusCell.setCellValue(cleanLabel(status));
                statusCell.setCellStyle(getStatusStyle(status, disposedStyle, rowTextStyle));

                createTextCell(row, col++, rs.getString("remarks"), rowTextStyle);

                Timestamp createdAt = rs.getTimestamp("created_at");
                Cell createdCell = row.createCell(col++);

                if (createdAt != null) {
                    createdCell.setCellValue(createdAt);
                    createdCell.setCellStyle(dateStyle);
                } else {
                    createdCell.setCellValue("-");
                    createdCell.setCellStyle(rowTextStyle);
                }
            }

            if (rowIndex == dataStartRow) {
                Row noRecordRow = sheet.createRow(rowIndex++);
                noRecordRow.setHeightInPoints(30);
                createMergedRow(
                        sheet,
                        noRecordRow,
                        0,
                        lastColumnIndex,
                        "No disposal records found.",
                        textStyle
                );
            }
        }

        sheet.createFreezePane(0, headerRowIndex + 1);
        sheet.setAutoFilter(new CellRangeAddress(headerRowIndex, headerRowIndex, 0, lastColumnIndex));

        sheet.setColumnWidth(0, 3300);
        sheet.setColumnWidth(1, 4300);
        sheet.setColumnWidth(2, 5600);
        sheet.setColumnWidth(3, 7200);
        sheet.setColumnWidth(4, 6200);
        sheet.setColumnWidth(5, 5200);
        sheet.setColumnWidth(6, 12000);
        sheet.setColumnWidth(7, 5200);
        sheet.setColumnWidth(8, 5200);
        sheet.setColumnWidth(9, 5200);
        sheet.setColumnWidth(10, 12000);
        sheet.setColumnWidth(11, 6200);

        try {
            int auditUserId = getSessionUserId(session);

            AuditDAO.log(
                    auditUserId,
                    "EXPORT",
                    "asset_disposal",
                    0,
                    "Asset disposal Excel report exported by " + username
            );
        } catch (Exception auditEx) {
            auditEx.printStackTrace();
        }

        try (ServletOutputStream outputStream = response.getOutputStream()) {
            workbook.write(outputStream);
            outputStream.flush();
        }

    } catch (Exception e) {
        e.printStackTrace();

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