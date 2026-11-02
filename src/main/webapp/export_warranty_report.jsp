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

    private XSSFCellStyle createDateStyle(XSSFWorkbook workbook, XSSFColor black, XSSFColor borderGrey) {
        XSSFCellStyle style = createTextStyle(workbook, black, borderGrey);
        style.setDataFormat(workbook.createDataFormat().getFormat("dd-mmm-yyyy"));
        return style;
    }

    private XSSFCellStyle createAmountStyle(XSSFWorkbook workbook, XSSFColor black, XSSFColor borderGrey) {
        XSSFCellStyle style = createTextStyle(workbook, black, borderGrey);
        style.setDataFormat(workbook.createDataFormat().getFormat("₹#,##0.00"));
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

    private void createAmountCell(Row row, int column, double value, CellStyle style) {
        Cell cell = row.createCell(column);
        cell.setCellValue(value);
        cell.setCellStyle(style);
    }

    private void createDateCell(Row row, int column, java.sql.Date value, CellStyle dateStyle, CellStyle textStyle) {
        Cell cell = row.createCell(column);

        if (value != null) {
            cell.setCellValue(value);
            cell.setCellStyle(dateStyle);
        } else {
            cell.setCellValue("-");
            cell.setCellStyle(textStyle);
        }
    }

    private CellStyle getWarrantyStatusStyle(
            String status,
            CellStyle activeStyle,
            CellStyle expiringStyle,
            CellStyle expiredStyle,
            CellStyle textStyle) {

        if (status == null) {
            return textStyle;
        }

        String s = status.trim().toUpperCase();

        if (s.contains("EXPIRED")) {
            return expiredStyle;
        }

        if (s.contains("EXPIRING")) {
            return expiringStyle;
        }

        if (s.contains("ACTIVE")) {
            return activeStyle;
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
    response.setHeader("Content-Disposition", "attachment; filename=\"IR_AMS_Warranty_Report.xlsx\"");

    out.clear();
    out = pageContext.pushBody();

    Connection con = null;
    PreparedStatement ps = null;
    ResultSet rs = null;
    XSSFWorkbook workbook = null;

    try {
        workbook = new XSSFWorkbook();

        XSSFSheet sheet = workbook.createSheet("Warranty Report");
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

        XSSFColor activeFill = new XSSFColor(new java.awt.Color(226, 239, 218), colorMap);
        XSSFColor activeText = new XSSFColor(new java.awt.Color(0, 97, 0), colorMap);

        XSSFColor expiringFill = new XSSFColor(new java.awt.Color(255, 242, 204), colorMap);
        XSSFColor expiringText = new XSSFColor(new java.awt.Color(156, 87, 0), colorMap);

        XSSFColor expiredFill = new XSSFColor(new java.awt.Color(252, 228, 214), colorMap);
        XSSFColor expiredText = new XSSFColor(new java.awt.Color(156, 0, 6), colorMap);

        XSSFCellStyle titleStyle = createTitleStyle(workbook, navy, white);
        XSSFCellStyle subtitleStyle = createSubTitleStyle(workbook, blue);
        XSSFCellStyle metaStyle = createMetaStyle(workbook, grey);
        XSSFCellStyle headerStyle = createHeaderStyle(workbook, blue, white, borderGrey);
        XSSFCellStyle textStyle = createTextStyle(workbook, black, borderGrey);
        XSSFCellStyle alternateStyle = createAlternateStyle(workbook, textStyle, stripe);
        XSSFCellStyle dateStyle = createDateStyle(workbook, black, borderGrey);
        XSSFCellStyle amountStyle = createAmountStyle(workbook, black, borderGrey);

        XSSFCellStyle activeStyle = createStatusStyle(workbook, activeFill, activeText, borderGrey);
        XSSFCellStyle expiringStyle = createStatusStyle(workbook, expiringFill, expiringText, borderGrey);
        XSSFCellStyle expiredStyle = createStatusStyle(workbook, expiredFill, expiredText, borderGrey);

        con = DBConnection.getConnection();

        boolean hasAssetsTable = tableExists(con, "assets");
        boolean hasCategoriesTable = tableExists(con, "asset_categories");
        boolean hasVendorsTable = tableExists(con, "vendors");

        boolean aHasAssetId = hasAssetsTable && columnExists(con, "assets", "asset_id");
        boolean aHasAssetCode = hasAssetsTable && columnExists(con, "assets", "asset_code");
        boolean aHasRailwayAssetNo = hasAssetsTable && columnExists(con, "assets", "railway_asset_no");
        boolean aHasAssetName = hasAssetsTable && columnExists(con, "assets", "asset_name");
        boolean aHasCategoryId = hasAssetsTable && columnExists(con, "assets", "category_id");
        boolean aHasVendorId = hasAssetsTable && columnExists(con, "assets", "vendor_id");
        boolean aHasSerialNumber = hasAssetsTable && columnExists(con, "assets", "serial_number");
        boolean aHasPurchaseDate = hasAssetsTable && columnExists(con, "assets", "purchase_date");
        boolean aHasPurchaseCost = hasAssetsTable && columnExists(con, "assets", "purchase_cost");
        boolean aHasWarrantyExpiry = hasAssetsTable && columnExists(con, "assets", "warranty_expiry");
        boolean aHasAssetStatus = hasAssetsTable && columnExists(con, "assets", "asset_status");
        boolean aHasLocation = hasAssetsTable && columnExists(con, "assets", "location");

        boolean cHasCategoryId = hasCategoriesTable && columnExists(con, "asset_categories", "category_id");
        boolean cHasCategoryName = hasCategoriesTable && columnExists(con, "asset_categories", "category_name");

        boolean vHasVendorId = hasVendorsTable && columnExists(con, "vendors", "vendor_id");
        boolean vHasVendorName = hasVendorsTable && columnExists(con, "vendors", "vendor_name");
        boolean vHasSupplierName = hasVendorsTable && columnExists(con, "vendors", "supplier_name");

        boolean joinCategory = hasAssetsTable && hasCategoriesTable && aHasCategoryId && cHasCategoryId;
        boolean joinVendor = hasAssetsTable && hasVendorsTable && aHasVendorId && vHasVendorId;

        int totalWarrantyAssets = hasAssetsTable && aHasWarrantyExpiry
                ? sqlInt(con, "SELECT COUNT(*) FROM assets WHERE warranty_expiry IS NOT NULL")
                : 0;

        int activeWarranty = hasAssetsTable && aHasWarrantyExpiry
                ? sqlInt(con, "SELECT COUNT(*) FROM assets WHERE warranty_expiry IS NOT NULL AND warranty_expiry > DATE_ADD(CURDATE(), INTERVAL 30 DAY)")
                : 0;

        int expiringWarranty = hasAssetsTable && aHasWarrantyExpiry
                ? sqlInt(con, "SELECT COUNT(*) FROM assets WHERE warranty_expiry IS NOT NULL AND warranty_expiry BETWEEN CURDATE() AND DATE_ADD(CURDATE(), INTERVAL 30 DAY)")
                : 0;

        int expiredWarranty = hasAssetsTable && aHasWarrantyExpiry
                ? sqlInt(con, "SELECT COUNT(*) FROM assets WHERE warranty_expiry IS NOT NULL AND warranty_expiry < CURDATE()")
                : 0;

        String[] headers = {
            "Sl No.",
            "Asset ID",
            "Asset Code",
            "Asset Name",
            "Category",
            "Supplier",
            "Serial Number",
            "Purchase Date",
            "Purchase Cost",
            "Warranty Expiry",
            "Days Remaining",
            "Warranty Status",
            "Asset Status",
            "Location"
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
                "Warranty Expiry Report - East Coast Railway / Rail Sadan, Bhubaneswar",
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
                "Warranty Assets: "
                + totalWarrantyAssets
                + " | Active: "
                + activeWarranty
                + " | Expiring in 30 Days: "
                + expiringWarranty
                + " | Expired: "
                + expiredWarranty,
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

        if (!hasAssetsTable) {
            Row noTableRow = sheet.createRow(rowIndex++);
            noTableRow.setHeightInPoints(30);
            createMergedRow(
                    sheet,
                    noTableRow,
                    0,
                    lastColumnIndex,
                    "assets table was not found in the current database.",
                    textStyle
            );

        } else {
            String assetIdExpr = aHasAssetId ? "CAST(a.asset_id AS CHAR)" : "''";
            String assetCodeExpr = aHasAssetCode
                    ? "COALESCE(a.asset_code, '')"
                    : (aHasRailwayAssetNo ? "COALESCE(a.railway_asset_no, '')" : "''");
            String assetNameExpr = aHasAssetName ? "COALESCE(a.asset_name, '')" : "''";
            String categoryExpr = joinCategory && cHasCategoryName ? "COALESCE(c.category_name, '')" : "''";

            String supplierExpr = "''";

            if (joinVendor) {
                if (vHasVendorName) {
                    supplierExpr = "COALESCE(v.vendor_name, '')";
                } else if (vHasSupplierName) {
                    supplierExpr = "COALESCE(v.supplier_name, '')";
                }
            }

            String serialExpr = aHasSerialNumber ? "COALESCE(a.serial_number, '')" : "''";
            String purchaseDateExpr = aHasPurchaseDate ? "a.purchase_date" : "NULL";
            String purchaseCostExpr = aHasPurchaseCost ? "COALESCE(a.purchase_cost, 0)" : "0";
            String warrantyExpiryExpr = aHasWarrantyExpiry ? "a.warranty_expiry" : "NULL";
            String daysRemainingExpr = aHasWarrantyExpiry ? "DATEDIFF(a.warranty_expiry, CURDATE())" : "0";

            String warrantyStatusExpr = aHasWarrantyExpiry
                    ? "CASE "
                    + "WHEN a.warranty_expiry IS NULL THEN 'NO_WARRANTY_DATE' "
                    + "WHEN a.warranty_expiry < CURDATE() THEN 'EXPIRED' "
                    + "WHEN a.warranty_expiry BETWEEN CURDATE() AND DATE_ADD(CURDATE(), INTERVAL 30 DAY) THEN 'EXPIRING_SOON' "
                    + "ELSE 'ACTIVE' "
                    + "END"
                    : "'NO_WARRANTY_DATE'";

            String assetStatusExpr = aHasAssetStatus ? "COALESCE(a.asset_status, '')" : "''";
            String locationExpr = aHasLocation ? "COALESCE(a.location, '')" : "''";

            String sql = "SELECT "
                    + assetIdExpr + " AS asset_id_display, "
                    + assetCodeExpr + " AS asset_code, "
                    + assetNameExpr + " AS asset_name, "
                    + categoryExpr + " AS category_name, "
                    + supplierExpr + " AS supplier_name, "
                    + serialExpr + " AS serial_number, "
                    + purchaseDateExpr + " AS purchase_date, "
                    + purchaseCostExpr + " AS purchase_cost, "
                    + warrantyExpiryExpr + " AS warranty_expiry, "
                    + daysRemainingExpr + " AS days_remaining, "
                    + warrantyStatusExpr + " AS warranty_status, "
                    + assetStatusExpr + " AS asset_status, "
                    + locationExpr + " AS location "
                    + "FROM assets a ";

            if (joinCategory) {
                sql += "LEFT JOIN asset_categories c ON a.category_id = c.category_id ";
            }

            if (joinVendor) {
                sql += "LEFT JOIN vendors v ON a.vendor_id = v.vendor_id ";
            }

            if (aHasWarrantyExpiry) {
                sql += "WHERE a.warranty_expiry IS NOT NULL ";
                sql += "ORDER BY a.warranty_expiry ASC";
            } else if (aHasAssetId) {
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
                createTextCell(row, col++, rs.getString("supplier_name"), rowTextStyle);
                createTextCell(row, col++, rs.getString("serial_number"), rowTextStyle);
                createDateCell(row, col++, rs.getDate("purchase_date"), dateStyle, rowTextStyle);
                createAmountCell(row, col++, rs.getDouble("purchase_cost"), amountStyle);
                createDateCell(row, col++, rs.getDate("warranty_expiry"), dateStyle, rowTextStyle);
                createNumberCell(row, col++, rs.getInt("days_remaining"), rowTextStyle);

                String warrantyStatus = rs.getString("warranty_status");
                Cell statusCell = row.createCell(col++);
                statusCell.setCellValue(cleanLabel(warrantyStatus));
                statusCell.setCellStyle(getWarrantyStatusStyle(
                        warrantyStatus,
                        activeStyle,
                        expiringStyle,
                        expiredStyle,
                        rowTextStyle
                ));

                createTextCell(row, col++, cleanLabel(rs.getString("asset_status")), rowTextStyle);
                createTextCell(row, col++, rs.getString("location"), rowTextStyle);
            }

            if (rowIndex == dataStartRow) {
                Row noRecordRow = sheet.createRow(rowIndex++);
                noRecordRow.setHeightInPoints(30);
                createMergedRow(
                        sheet,
                        noRecordRow,
                        0,
                        lastColumnIndex,
                        "No warranty records found.",
                        textStyle
                );
            }
        }

        sheet.createFreezePane(0, headerRowIndex + 1);
        sheet.setAutoFilter(new CellRangeAddress(headerRowIndex, headerRowIndex, 0, lastColumnIndex));

        sheet.setColumnWidth(0, 3300);
        sheet.setColumnWidth(1, 4300);
        sheet.setColumnWidth(2, 5600);
        sheet.setColumnWidth(3, 8200);
        sheet.setColumnWidth(4, 6200);
        sheet.setColumnWidth(5, 6200);
        sheet.setColumnWidth(6, 6200);
        sheet.setColumnWidth(7, 5200);
        sheet.setColumnWidth(8, 5600);
        sheet.setColumnWidth(9, 5600);
        sheet.setColumnWidth(10, 5200);
        sheet.setColumnWidth(11, 6200);
        sheet.setColumnWidth(12, 5600);
        sheet.setColumnWidth(13, 8200);

        try {
            AuditDAO.log(
                    getSessionUserId(session),
                    "EXPORT",
                    "warranty_report",
                    0,
                    "Warranty Excel report exported by " + username
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