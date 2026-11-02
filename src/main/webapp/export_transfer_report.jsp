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
    // Same styling/helper set as export_disposal_report.jsp, kept in lockstep
    // so every export in this app looks and behaves the same way.

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

    private CellStyle getStatusStyle(
            String status,
            CellStyle completedStyle,
            CellStyle rejectedStyle,
            CellStyle pendingStyle,
            CellStyle textStyle) {

        if (status == null) {
            return textStyle;
        }

        String s = status.trim().toUpperCase();

        if (s.equals("COMPLETED")) {
            return completedStyle;
        }

        if (s.equals("REJECTED")) {
            return rejectedStyle;
        }

        if (s.equals("PENDING")) {
            return pendingStyle;
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

    // Same reviewer/export role set as the transfer review page itself
    // (ReviewAssetTransferServlet) plus AUDITOR, matching the pattern
    // export_disposal_report.jsp uses for its own export access.
    if (!("SUPER_ADMIN".equals(role) || "ADMIN".equals(role))
            && !"ASSET_MANAGER".equalsIgnoreCase(role)
            && !"AUDITOR".equalsIgnoreCase(role)) {
        response.sendRedirect("reports.jsp?access=denied");
        return;
    }

    response.reset();
    response.setContentType("application/vnd.openxmlformats-officedocument.spreadsheetml.sheet");
    response.setHeader("Content-Disposition", "attachment; filename=\"IR_AMS_Transfer_Report.xlsx\"");

    out.clear();
    out = pageContext.pushBody();

    Connection con = null;
    PreparedStatement ps = null;
    ResultSet rs = null;
    XSSFWorkbook workbook = null;

    try {
        workbook = new XSSFWorkbook();

        XSSFSheet sheet = workbook.createSheet("Transfer Report");
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

        XSSFColor completedFill = new XSSFColor(new java.awt.Color(224, 247, 233), colorMap);
        XSSFColor completedText = new XSSFColor(new java.awt.Color(15, 118, 78), colorMap);
        XSSFColor rejectedFill = new XSSFColor(new java.awt.Color(252, 228, 214), colorMap);
        XSSFColor rejectedText = new XSSFColor(new java.awt.Color(156, 0, 6), colorMap);
        XSSFColor pendingFill = new XSSFColor(new java.awt.Color(255, 243, 205), colorMap);
        XSSFColor pendingText = new XSSFColor(new java.awt.Color(133, 100, 4), colorMap);

        XSSFCellStyle titleStyle = createTitleStyle(workbook, navy, white);
        XSSFCellStyle subtitleStyle = createSubTitleStyle(workbook, deepBlue);
        XSSFCellStyle metaStyle = createMetaStyle(workbook, greyText);
        XSSFCellStyle headerStyle = createHeaderStyle(workbook, deepBlue, white, borderGrey);
        XSSFCellStyle textStyle = createTextStyle(workbook, black, borderGrey);
        XSSFCellStyle alternateStyle = createAlternateStyle(workbook, textStyle, lightStripe);
        XSSFCellStyle dateStyle = createDateStyle(workbook, black, borderGrey);
        XSSFCellStyle completedStyle = createStatusStyle(workbook, completedFill, completedText, borderGrey);
        XSSFCellStyle rejectedStyle = createStatusStyle(workbook, rejectedFill, rejectedText, borderGrey);
        XSSFCellStyle pendingStyle = createStatusStyle(workbook, pendingFill, pendingText, borderGrey);

        con = DBConnection.getConnection();

        int totalRequests = sqlInt(con, "SELECT COUNT(*) FROM asset_transfer_requests");
        int pendingRequests = sqlInt(con, "SELECT COUNT(*) FROM asset_transfer_requests WHERE request_status = 'PENDING'");
        int completedRequests = sqlInt(con, "SELECT COUNT(*) FROM asset_transfer_requests WHERE request_status = 'COMPLETED'");
        int rejectedRequests = sqlInt(con, "SELECT COUNT(*) FROM asset_transfer_requests WHERE request_status = 'REJECTED'");

        String[] headers = {
            "Sl No.",
            "Request ID",
            "Asset Code",
            "Asset Name",
            "From Employee",
            "To Employee",
            "Transfer Reason",
            "Status",
            "Requested By",
            "Requested Date",
            "Reviewed By",
            "Reviewed Date"
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
                "Asset Transfer Report - East Coast Railway / Rail Sadan, Bhubaneswar",
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
                "Total Requests: "
                + totalRequests
                + " | Pending Review: "
                + pendingRequests
                + " | Completed: "
                + completedRequests
                + " | Rejected: "
                + rejectedRequests,
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

        // Mirrors AssetTransferDAO.getAllTransferRequests()'s own query -
        // same joins, same columns - so the export always matches what the
        // Asset Transfers screen shows.
        String sql = "SELECT tr.request_id, a.asset_code, a.asset_name, "
                + "fe.employee_code AS from_code, fe.employee_name AS from_name, "
                + "te.employee_code AS to_code, te.employee_name AS to_name, "
                + "tr.transfer_reason, tr.request_status, "
                + "COALESCE(ru.username, '') AS requested_by_name, "
                + "tr.requested_date, "
                + "COALESCE(rvu.username, '') AS reviewed_by_name, "
                + "tr.reviewed_date "
                + "FROM asset_transfer_requests tr "
                + "JOIN assets a ON tr.asset_id = a.asset_id "
                + "JOIN employees fe ON tr.from_employee_id = fe.employee_id "
                + "JOIN employees te ON tr.to_employee_id = te.employee_id "
                + "LEFT JOIN users ru ON tr.requested_by = ru.user_id "
                + "LEFT JOIN users rvu ON tr.reviewed_by = rvu.user_id "
                + "ORDER BY tr.request_id DESC";

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
            createTextCell(row, col++, "XFER-" + rs.getInt("request_id"), rowTextStyle);
            createTextCell(row, col++, rs.getString("asset_code"), rowTextStyle);
            createTextCell(row, col++, rs.getString("asset_name"), rowTextStyle);
            createTextCell(row, col++, rs.getString("from_name") + " (" + rs.getString("from_code") + ")", rowTextStyle);
            createTextCell(row, col++, rs.getString("to_name") + " (" + rs.getString("to_code") + ")", rowTextStyle);
            createTextCell(row, col++, rs.getString("transfer_reason"), rowTextStyle);

            String status = rs.getString("request_status");
            Cell statusCell = row.createCell(col++);
            statusCell.setCellValue(cleanLabel(status));
            statusCell.setCellStyle(getStatusStyle(status, completedStyle, rejectedStyle, pendingStyle, rowTextStyle));

            createTextCell(row, col++, rs.getString("requested_by_name"), rowTextStyle);
            createDateCell(row, col++, rs.getDate("requested_date"), dateStyle, rowTextStyle);
            createTextCell(row, col++, rs.getString("reviewed_by_name"), rowTextStyle);
            createDateCell(row, col++, rs.getDate("reviewed_date"), dateStyle, rowTextStyle);
        }

        if (rowIndex == dataStartRow) {
            Row noRecordRow = sheet.createRow(rowIndex++);
            noRecordRow.setHeightInPoints(30);
            createMergedRow(
                    sheet,
                    noRecordRow,
                    0,
                    lastColumnIndex,
                    "No transfer records found.",
                    textStyle
            );
        }

        sheet.createFreezePane(0, headerRowIndex + 1);
        sheet.setAutoFilter(new CellRangeAddress(headerRowIndex, headerRowIndex, 0, lastColumnIndex));

        sheet.setColumnWidth(0, 3300);
        sheet.setColumnWidth(1, 4300);
        sheet.setColumnWidth(2, 5600);
        sheet.setColumnWidth(3, 7200);
        sheet.setColumnWidth(4, 7200);
        sheet.setColumnWidth(5, 7200);
        sheet.setColumnWidth(6, 10000);
        sheet.setColumnWidth(7, 5200);
        sheet.setColumnWidth(8, 5200);
        sheet.setColumnWidth(9, 5200);
        sheet.setColumnWidth(10, 5200);
        sheet.setColumnWidth(11, 5200);

        try {
            int auditUserId = getSessionUserId(session);

            AuditDAO.log(
                    auditUserId,
                    "EXPORT",
                    "asset_transfer_requests",
                    0,
                    "Asset transfer Excel report exported by " + username
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
