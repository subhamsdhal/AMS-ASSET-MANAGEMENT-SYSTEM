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

    private XSSFCellStyle titleStyle(XSSFWorkbook workbook, XSSFColor navy, XSSFColor white) {
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

    private XSSFCellStyle subtitleStyle(XSSFWorkbook workbook, XSSFColor blue) {
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

    private XSSFCellStyle metaStyle(XSSFWorkbook workbook, XSSFColor grey) {
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

    private XSSFCellStyle headerStyle(XSSFWorkbook workbook, XSSFColor blue, XSSFColor white, XSSFColor borderGrey) {
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

    private XSSFCellStyle textStyle(XSSFWorkbook workbook, XSSFColor black, XSSFColor borderGrey) {
        XSSFFont font = workbook.createFont();
        font.setFontHeightInPoints((short) 10);
        font.setColor(black);

        XSSFCellStyle style = workbook.createCellStyle();
        style.setFont(font);
        style.setAlignment(HorizontalAlignment.CENTER);
        style.setVerticalAlignment(VerticalAlignment.CENTER);
        style.setWrapText(true);
        addBorder(style, borderGrey);

        return style;
    }

    private XSSFCellStyle alternateStyle(XSSFWorkbook workbook, XSSFCellStyle base, XSSFColor stripe) {
        XSSFCellStyle style = workbook.createCellStyle();
        style.cloneStyleFrom(base);
        style.setFillForegroundColor(stripe);
        style.setFillPattern(FillPatternType.SOLID_FOREGROUND);
        return style;
    }

    private XSSFCellStyle dateStyle(XSSFWorkbook workbook, XSSFColor black, XSSFColor borderGrey) {
        XSSFCellStyle style = textStyle(workbook, black, borderGrey);
        style.setDataFormat(workbook.createDataFormat().getFormat("dd-mmm-yyyy"));
        return style;
    }

    private XSSFCellStyle amountStyle(XSSFWorkbook workbook, XSSFColor black, XSSFColor borderGrey) {
        XSSFCellStyle style = textStyle(workbook, black, borderGrey);
        style.setDataFormat(workbook.createDataFormat().getFormat("₹#,##0.00"));
        return style;
    }

    private XSSFCellStyle statusStyle(XSSFWorkbook workbook, XSSFColor fill, XSSFColor text, XSSFColor borderGrey) {
        XSSFFont font = workbook.createFont();
        font.setBold(true);
        font.setFontHeightInPoints((short) 10);
        font.setColor(text);

        XSSFCellStyle style = workbook.createCellStyle();
        style.setFont(font);
        style.setFillForegroundColor(fill);
        style.setFillPattern(FillPatternType.SOLID_FOREGROUND);
        style.setAlignment(HorizontalAlignment.CENTER);
        style.setVerticalAlignment(VerticalAlignment.CENTER);
        style.setWrapText(true);
        addBorder(style, borderGrey);

        return style;
    }

    private void mergedRow(XSSFSheet sheet, Row row, int firstCol, int lastCol, String value, CellStyle style) {
        for (int i = firstCol; i <= lastCol; i++) {
            Cell cell = row.createCell(i);
            if (i == firstCol) {
                cell.setCellValue(value);
            }
            cell.setCellStyle(style);
        }

        sheet.addMergedRegion(new CellRangeAddress(row.getRowNum(), row.getRowNum(), firstCol, lastCol));
    }

    private void textCell(Row row, int col, Object value, CellStyle style) {
        Cell cell = row.createCell(col);
        cell.setCellValue(safeText(value));
        cell.setCellStyle(style);
    }

    private void numberCell(Row row, int col, int value, CellStyle style) {
        Cell cell = row.createCell(col);
        cell.setCellValue(value);
        cell.setCellStyle(style);
    }

    private void amountCell(Row row, int col, double value, CellStyle style) {
        Cell cell = row.createCell(col);
        cell.setCellValue(value);
        cell.setCellStyle(style);
    }

    private void dateCell(Row row, int col, java.sql.Date value, CellStyle dateStyle, CellStyle textStyle) {
        Cell cell = row.createCell(col);

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
    response.setContentType("application/vnd.openxmlformats-officedocument.spreadsheetml.sheet");
    response.setHeader("Content-Disposition", "attachment; filename=\"IR_AMS_Asset_Report.xlsx\"");

    out.clear();
    out = pageContext.pushBody();

    Connection con = null;
    PreparedStatement ps = null;
    ResultSet rs = null;
    XSSFWorkbook workbook = null;

    try {
        workbook = new XSSFWorkbook();

        XSSFSheet sheet = workbook.createSheet("Asset Report");
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

        XSSFColor greenFill = new XSSFColor(new java.awt.Color(226, 239, 218), colorMap);
        XSSFColor greenText = new XSSFColor(new java.awt.Color(0, 97, 0), colorMap);
        XSSFColor blueFill = new XSSFColor(new java.awt.Color(221, 235, 247), colorMap);
        XSSFColor blueText = new XSSFColor(new java.awt.Color(31, 78, 121), colorMap);
        XSSFColor orangeFill = new XSSFColor(new java.awt.Color(255, 242, 204), colorMap);
        XSSFColor orangeText = new XSSFColor(new java.awt.Color(156, 87, 0), colorMap);
        XSSFColor redFill = new XSSFColor(new java.awt.Color(252, 228, 214), colorMap);
        XSSFColor redText = new XSSFColor(new java.awt.Color(156, 0, 6), colorMap);

        XSSFCellStyle titleStyle = titleStyle(workbook, navy, white);
        XSSFCellStyle subtitleStyle = subtitleStyle(workbook, blue);
        XSSFCellStyle metaStyle = metaStyle(workbook, grey);
        XSSFCellStyle headerStyle = headerStyle(workbook, blue, white, borderGrey);
        XSSFCellStyle textStyle = textStyle(workbook, black, borderGrey);
        XSSFCellStyle alternateStyle = alternateStyle(workbook, textStyle, stripe);
        XSSFCellStyle dateStyle = dateStyle(workbook, black, borderGrey);
        XSSFCellStyle amountStyle = amountStyle(workbook, black, borderGrey);

        XSSFCellStyle availableStyle = statusStyle(workbook, greenFill, greenText, borderGrey);
        XSSFCellStyle allocatedStyle = statusStyle(workbook, blueFill, blueText, borderGrey);
        XSSFCellStyle maintenanceStyle = statusStyle(workbook, orangeFill, orangeText, borderGrey);
        XSSFCellStyle disposedStyle = statusStyle(workbook, redFill, redText, borderGrey);

        con = DBConnection.getConnection();

        int totalAssets = 0;
        int availableAssets = 0;
        int allocatedAssets = 0;
        int maintenanceAssets = 0;
        int disposedAssets = 0;
        double totalValue = 0.0;

        String summarySql = "SELECT "
                + "COUNT(*) AS total_assets, "
                + "SUM(CASE WHEN asset_status = 'AVAILABLE' THEN 1 ELSE 0 END) AS available_assets, "
                + "SUM(CASE WHEN asset_status = 'ALLOCATED' THEN 1 ELSE 0 END) AS allocated_assets, "
                + "SUM(CASE WHEN asset_status = 'UNDER_MAINTENANCE' THEN 1 ELSE 0 END) AS maintenance_assets, "
                + "SUM(CASE WHEN asset_status = 'DISPOSED' THEN 1 ELSE 0 END) AS disposed_assets, "
                + "COALESCE(SUM(purchase_cost), 0) AS total_value "
                + "FROM assets";

        try (PreparedStatement summaryPs = con.prepareStatement(summarySql)) {
            
            try (ResultSet summaryRs = summaryPs.executeQuery()) {

            if (summaryRs.next()) {
                totalAssets = summaryRs.getInt("total_assets");
                availableAssets = summaryRs.getInt("available_assets");
                allocatedAssets = summaryRs.getInt("allocated_assets");
                maintenanceAssets = summaryRs.getInt("maintenance_assets");
                disposedAssets = summaryRs.getInt("disposed_assets");
                totalValue = summaryRs.getDouble("total_value");
            }
            }
        }

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
            "Status",
            "Location",
            "QR Code",
            "Depreciation Rate"
        };

        int lastColumn = headers.length - 1;
        int rowIndex = 0;

        Row titleRow = sheet.createRow(rowIndex++);
        titleRow.setHeightInPoints(32);
        mergedRow(sheet, titleRow, 0, lastColumn, "INDIAN RAILWAY ASSET MANAGEMENT SYSTEM", titleStyle);

        Row subtitleRow = sheet.createRow(rowIndex++);
        subtitleRow.setHeightInPoints(24);
        mergedRow(sheet, subtitleRow, 0, lastColumn, "Asset Register Report - East Coast Railway / Rail Sadan, Bhubaneswar", subtitleStyle);

        String generatedTime = LocalDateTime.now().format(DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss"));

        Row metaRow = sheet.createRow(rowIndex++);
        metaRow.setHeightInPoints(23);
        mergedRow(
                sheet,
                metaRow,
                0,
                lastColumn,
                "Generated By: " + username + " | Role: " + cleanLabel(role) + " | Generated On: " + generatedTime,
                metaStyle
        );

        Row kpiRow = sheet.createRow(rowIndex++);
        kpiRow.setHeightInPoints(23);
        mergedRow(
                sheet,
                kpiRow,
                0,
                lastColumn,
                "Total Assets: " + totalAssets
                + " | Available: " + availableAssets
                + " | Allocated: " + allocatedAssets
                + " | Under Maintenance: " + maintenanceAssets
                + " | Disposed: " + disposedAssets
                + " | Total Value: ₹" + String.format(java.util.Locale.ENGLISH, "%,.2f", totalValue),
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

        String sql = "SELECT "
                + "a.asset_id, "
                + "a.asset_code, "
                + "a.asset_name, "
                + "ac.category_name, "
                + "v.vendor_name, "
                + "a.serial_number, "
                + "a.purchase_date, "
                + "a.purchase_cost, "
                + "a.warranty_expiry, "
                + "a.asset_status, "
                + "a.location, "
                + "a.qr_code, "
                + "a.depreciation_rate "
                + "FROM assets a "
                + "LEFT JOIN asset_categories ac ON a.category_id = ac.category_id "
                + "LEFT JOIN vendors v ON a.vendor_id = v.vendor_id ";
                
        sql += "ORDER BY a.asset_id DESC";

        ps = con.prepareStatement(sql);
        
        rs = ps.executeQuery();

        int slNo = 1;
        int dataStartRow = rowIndex;

        while (rs.next()) {
            Row row = sheet.createRow(rowIndex++);
            row.setHeightInPoints(30);

            CellStyle rowTextStyle = (rowIndex % 2 == 0) ? alternateStyle : textStyle;

            int col = 0;

            numberCell(row, col++, slNo++, rowTextStyle);
            textCell(row, col++, "AST-ID-" + rs.getInt("asset_id"), rowTextStyle);
            textCell(row, col++, rs.getString("asset_code"), rowTextStyle);
            textCell(row, col++, rs.getString("asset_name"), rowTextStyle);
            textCell(row, col++, rs.getString("category_name"), rowTextStyle);
            textCell(row, col++, rs.getString("vendor_name"), rowTextStyle);
            textCell(row, col++, rs.getString("serial_number"), rowTextStyle);
            dateCell(row, col++, rs.getDate("purchase_date"), dateStyle, rowTextStyle);
            amountCell(row, col++, rs.getDouble("purchase_cost"), amountStyle);
            dateCell(row, col++, rs.getDate("warranty_expiry"), dateStyle, rowTextStyle);

            String status = rs.getString("asset_status");
            Cell statusCell = row.createCell(col++);
            statusCell.setCellValue(cleanLabel(status));

            if ("AVAILABLE".equalsIgnoreCase(status)) {
                statusCell.setCellStyle(availableStyle);
            } else if ("ALLOCATED".equalsIgnoreCase(status)) {
                statusCell.setCellStyle(allocatedStyle);
            } else if ("UNDER_MAINTENANCE".equalsIgnoreCase(status)) {
                statusCell.setCellStyle(maintenanceStyle);
            } else if ("DISPOSED".equalsIgnoreCase(status)) {
                statusCell.setCellStyle(disposedStyle);
            } else {
                statusCell.setCellStyle(rowTextStyle);
            }

            textCell(row, col++, rs.getString("location"), rowTextStyle);
            textCell(row, col++, rs.getString("qr_code"), rowTextStyle);
            textCell(row, col++, rs.getDouble("depreciation_rate") + "%", rowTextStyle);
        }

        if (rowIndex == dataStartRow) {
            Row noRecordRow = sheet.createRow(rowIndex++);
            noRecordRow.setHeightInPoints(30);
            mergedRow(sheet, noRecordRow, 0, lastColumn, "No asset records found.", textStyle);
        }

        sheet.createFreezePane(0, headerRowIndex + 1);
        sheet.setAutoFilter(new CellRangeAddress(headerRowIndex, headerRowIndex, 0, lastColumn));

        sheet.setColumnWidth(0, 3300);
        sheet.setColumnWidth(1, 4300);
        sheet.setColumnWidth(2, 5200);
        sheet.setColumnWidth(3, 8200);
        sheet.setColumnWidth(4, 6200);
        sheet.setColumnWidth(5, 6200);
        sheet.setColumnWidth(6, 5600);
        sheet.setColumnWidth(7, 5200);
        sheet.setColumnWidth(8, 5600);
        sheet.setColumnWidth(9, 5200);
        sheet.setColumnWidth(10, 5600);
        sheet.setColumnWidth(11, 7600);
        sheet.setColumnWidth(12, 9000);
        sheet.setColumnWidth(13, 5200);

        try {
            AuditDAO.log(
                    getSessionUserId(session),
                    "EXPORT",
                    "assets",
                    0,
                    "Professional XLSX asset report exported by " + username
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