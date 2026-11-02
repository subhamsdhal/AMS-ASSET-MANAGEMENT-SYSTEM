<%@page contentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet" pageEncoding="UTF-8" trimDirectiveWhitespaces="true"%>
<%@page import="com.mycompany.asset_management_system_ams.DBConnection"%>
<%@page import="java.sql.*"%>
<%@page import="java.util.*"%>
<%@page import="java.text.SimpleDateFormat"%>
<%@page import="org.apache.poi.ss.usermodel.*"%>
<%@page import="org.apache.poi.xssf.usermodel.XSSFWorkbook"%>
<%@page import="jakarta.servlet.ServletOutputStream"%>

<%!
    private String safeExcel(String value) {
        if (value == null || value.trim().isEmpty()) {
            return "N/A";
        }

        return value.trim();
    }

    private String cleanFilePart(String value) {
        if (value == null || value.trim().isEmpty()) {
            return "all";
        }

        return value.trim()
                .replaceAll("[^a-zA-Z0-9_-]", "_")
                .replaceAll("_+", "_");
    }

    private CellStyle titleStyle(Workbook workbook) {
        Font font = workbook.createFont();
        font.setBold(true);
        font.setFontHeightInPoints((short) 16);
        font.setColor(IndexedColors.DARK_BLUE.getIndex());

        CellStyle style = workbook.createCellStyle();
        style.setFont(font);
        style.setAlignment(HorizontalAlignment.CENTER);
        style.setVerticalAlignment(VerticalAlignment.CENTER);

        return style;
    }

    private CellStyle subtitleStyle(Workbook workbook) {
        Font font = workbook.createFont();
        font.setBold(true);
        font.setFontHeightInPoints((short) 11);
        font.setColor(IndexedColors.BLUE_GREY.getIndex());

        CellStyle style = workbook.createCellStyle();
        style.setFont(font);
        style.setAlignment(HorizontalAlignment.CENTER);
        style.setVerticalAlignment(VerticalAlignment.CENTER);

        return style;
    }

    private CellStyle headerStyle(Workbook workbook) {
        Font font = workbook.createFont();
        font.setBold(true);
        font.setColor(IndexedColors.WHITE.getIndex());

        CellStyle style = workbook.createCellStyle();
        style.setFont(font);
        style.setFillForegroundColor(IndexedColors.DARK_BLUE.getIndex());
        style.setFillPattern(FillPatternType.SOLID_FOREGROUND);
        style.setAlignment(HorizontalAlignment.CENTER);
        style.setVerticalAlignment(VerticalAlignment.CENTER);
        style.setWrapText(true);
        style.setBorderTop(BorderStyle.THIN);
        style.setBorderBottom(BorderStyle.THIN);
        style.setBorderLeft(BorderStyle.THIN);
        style.setBorderRight(BorderStyle.THIN);

        return style;
    }

    private CellStyle textStyle(Workbook workbook) {
        Font font = workbook.createFont();
        font.setFontHeightInPoints((short) 10);
        font.setColor(IndexedColors.DARK_BLUE.getIndex());

        CellStyle style = workbook.createCellStyle();
        style.setFont(font);
        style.setVerticalAlignment(VerticalAlignment.TOP);
        style.setWrapText(true);
        style.setBorderTop(BorderStyle.THIN);
        style.setBorderBottom(BorderStyle.THIN);
        style.setBorderLeft(BorderStyle.THIN);
        style.setBorderRight(BorderStyle.THIN);

        return style;
    }

    private CellStyle centerStyle(Workbook workbook) {
        CellStyle style = textStyle(workbook);
        style.setAlignment(HorizontalAlignment.CENTER);
        return style;
    }

    private CellStyle highStyle(Workbook workbook) {
        Font font = workbook.createFont();
        font.setBold(true);
        font.setColor(IndexedColors.RED.getIndex());

        CellStyle style = textStyle(workbook);
        style.setFont(font);
        style.setAlignment(HorizontalAlignment.CENTER);
        return style;
    }

    private CellStyle mediumStyle(Workbook workbook) {
        Font font = workbook.createFont();
        font.setBold(true);
        font.setColor(IndexedColors.ORANGE.getIndex());

        CellStyle style = textStyle(workbook);
        style.setFont(font);
        style.setAlignment(HorizontalAlignment.CENTER);
        return style;
    }

    private CellStyle lowStyle(Workbook workbook) {
        Font font = workbook.createFont();
        font.setBold(true);
        font.setColor(IndexedColors.GREEN.getIndex());

        CellStyle style = textStyle(workbook);
        style.setFont(font);
        style.setAlignment(HorizontalAlignment.CENTER);
        return style;
    }

    private void setCell(Row row, int column, String value, CellStyle style) {
        Cell cell = row.createCell(column);
        cell.setCellValue(safeExcel(value));
        cell.setCellStyle(style);
    }

    private void setMergedTitle(Sheet sheet, int rowIndex, int startCol, int endCol, String value, CellStyle style) {
        Row row = sheet.createRow(rowIndex);
        row.setHeightInPoints(28);

        Cell cell = row.createCell(startCol);
        cell.setCellValue(value);
        cell.setCellStyle(style);

        for (int i = startCol + 1; i <= endCol; i++) {
            Cell blankCell = row.createCell(i);
            blankCell.setCellStyle(style);
        }

        sheet.addMergedRegion(new org.apache.poi.ss.util.CellRangeAddress(rowIndex, rowIndex, startCol, endCol));
    }
%>
<%
    String username = (String) session.getAttribute("username");
    String role = (String) session.getAttribute("role");

    if (username == null || role == null) {
        response.sendRedirect("login.jsp");
        return;
    }

    boolean canExport = ("SUPER_ADMIN".equals(role) || "ADMIN".equals(role))
            || "ASSET_MANAGER".equals(role)
            || "AUDITOR".equals(role);

    if (!canExport) {
        response.sendRedirect("dashboard.jsp?access=denied");
        return;
    }

    String q = request.getParameter("q");
    String riskFilter = request.getParameter("risk");

    if (q == null) {
        q = "";
    }

    if (riskFilter == null || riskFilter.trim().isEmpty()) {
        riskFilter = "ALL";
    }

    q = q.trim();
    riskFilter = riskFilter.trim().toUpperCase(Locale.ENGLISH);

    String generatedAt = new SimpleDateFormat("dd-MMM-yyyy hh:mm a").format(new java.util.Date());
    String fileDate = new SimpleDateFormat("yyyyMMdd_HHmmss").format(new java.util.Date());
    String fileName = "IR_AMS_QR_IP_Audit_Report_" + cleanFilePart(riskFilter) + "_" + fileDate + ".xlsx";

    response.reset();
    response.setContentType("application/vnd.openxmlformats-officedocument.spreadsheetml.sheet");
    response.setHeader("Content-Disposition", "attachment; filename=\"" + fileName + "\"");
    response.setHeader("Cache-Control", "no-cache, no-store, must-revalidate");
    response.setHeader("Pragma", "no-cache");
    response.setDateHeader("Expires", 0);

    try {
        out.clear();
        out = pageContext.pushBody();
    } catch (Exception e) {
        e.printStackTrace();
        try {
            com.mycompany.asset_management_system_ams.AuditDAO.log(0, "ERROR", "export", 0, "Failed to export report: " + e.getMessage());
        } catch (Exception ignore) {}
        if (!response.isCommitted()) {
            response.reset();
            response.sendRedirect("qr_ip_audit_report.jsp?error=export_failed");
        }
        return;
    }
%>