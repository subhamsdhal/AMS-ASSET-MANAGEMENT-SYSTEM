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

    // Fault (Low, fixed): the raw search term used to be written directly into a
    // visible Excel cell as report metadata with no sanitization against a
    // leading =, +, -, or @ - the classic CSV/Excel formula-injection pattern.
    // Only used at the point of display; the original q is still used unchanged
    // for the actual SQL LIKE filter (already safely parameterized). See
    // audit/24-reports-exports.md Finding 1.
    private String sanitizeForExcelCell(String value) {
        if (value == null || value.isEmpty()) {
            return value;
        }
        char first = value.charAt(0);
        if (first == '=' || first == '+' || first == '-' || first == '@') {
            return "'" + value;
        }
        return value;
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

    private CellStyle successStyle(Workbook workbook) {
        Font font = workbook.createFont();
        font.setBold(true);
        font.setColor(IndexedColors.GREEN.getIndex());

        CellStyle style = textStyle(workbook);
        style.setFont(font);
        style.setAlignment(HorizontalAlignment.CENTER);
        return style;
    }

    private CellStyle dangerStyle(Workbook workbook) {
        Font font = workbook.createFont();
        font.setBold(true);
        font.setColor(IndexedColors.RED.getIndex());

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
    String statusFilter = request.getParameter("status");

    if (q == null) {
        q = "";
    }

    if (statusFilter == null || statusFilter.trim().isEmpty()) {
        statusFilter = "ALL";
    }

    q = q.trim();
    statusFilter = statusFilter.trim().toUpperCase(Locale.ENGLISH);

    String generatedAt = new SimpleDateFormat("dd-MMM-yyyy hh:mm a").format(new java.util.Date());
    String fileDate = new SimpleDateFormat("yyyyMMdd_HHmmss").format(new java.util.Date());
    String fileName = "IR_AMS_QR_Asset_Scan_History_" + cleanFilePart(statusFilter) + "_" + fileDate + ".xlsx";

    response.reset();
    response.setContentType("application/vnd.openxmlformats-officedocument.spreadsheetml.sheet");
    response.setHeader("Content-Disposition", "attachment; filename=\"" + fileName + "\"");
    response.setHeader("Cache-Control", "no-cache, no-store, must-revalidate");
    response.setHeader("Pragma", "no-cache");
    response.setDateHeader("Expires", 0);

    try {
        out.clear();
        out = pageContext.pushBody();
    } catch (Exception ignored) {
    }

    try (Workbook workbook = new XSSFWorkbook();
         Connection con = DBConnection.getConnection()) {

        Sheet sheet = workbook.createSheet("QR Asset Scan History");

        CellStyle title = titleStyle(workbook);
        CellStyle subtitle = subtitleStyle(workbook);
        CellStyle header = headerStyle(workbook);
        CellStyle text = textStyle(workbook);
        CellStyle center = centerStyle(workbook);
        CellStyle success = successStyle(workbook);
        CellStyle danger = dangerStyle(workbook);

        setMergedTitle(sheet, 0, 0, 15, "INDIAN RAILWAYS - EAST COAST RAILWAY", title);
        setMergedTitle(sheet, 1, 0, 15, "IR-AMS QR ASSET SCAN HISTORY REPORT", title);
        setMergedTitle(sheet, 2, 0, 15,
                "Generated By: " + username + " (" + role + ") | Generated At: " + generatedAt
                + " | Status Filter: " + statusFilter
                + (q.isEmpty() ? "" : " | Search: " + sanitizeForExcelCell(q)),
                subtitle);

        Row headerRow = sheet.createRow(4);
        headerRow.setHeightInPoints(32);

        String[] headers = {
                "Sl. No.",
                "Scan ID",
                "Asset ID",
                "Asset Code",
                "Asset Name",
                "Department",
                "Category",
                "QR Token",
                "Scan Status",
                "Scan Source",
                "IP Address",
                "Browser / Device",
                "Remarks",
                "Scanned At",
                "Scan Detail Link",
                "Asset Link"
        };

        for (int i = 0; i < headers.length; i++) {
            setCell(headerRow, i, headers[i], header);
        }

        StringBuilder where = new StringBuilder(" WHERE 1 = 1 ");
        List<String> params = new ArrayList<String>();

        if (!"ALL".equals(statusFilter)) {
            where.append("AND q.scan_status = ? ");
            params.add(statusFilter);
        }

        if (!q.isEmpty()) {
            where.append("AND (")
                    .append("a.asset_code LIKE ? ")
                    .append("OR a.asset_name LIKE ? ")
                    .append("OR q.qr_public_token LIKE ? ")
                    .append("OR q.scan_ip LIKE ? ")
                    .append("OR d.department_name LIKE ? ")
                    .append("OR ac.category_name LIKE ? ")
                    .append(") ");

            String searchValue = "%" + q + "%";

            for (int i = 0; i < 6; i++) {
                params.add(searchValue);
            }
        }

        String sql =
                "SELECT "
                + "q.scan_id, q.asset_id, q.qr_public_token, q.scan_status, q.scan_source, "
                + "q.scan_ip, q.scan_user_agent, q.remarks, "
                + "DATE_FORMAT(q.scanned_at, '%d %b %Y, %h:%i %p') AS scanned_at, "
                + "COALESCE(a.asset_code, 'No Linked Asset') AS asset_code, "
                + "COALESCE(a.asset_name, 'Asset not linked') AS asset_name, "
                + "COALESCE(d.department_name, 'Not Available') AS department_name, "
                + "COALESCE(ac.category_name, 'Not Available') AS category_name "
                + "FROM asset_qr_scan_logs q "
                + "LEFT JOIN assets a ON q.asset_id = a.asset_id "
                + "LEFT JOIN departments d ON a.department_id = d.department_id "
                + "LEFT JOIN asset_categories ac ON a.category_id = ac.category_id "
                + where.toString()
                + "ORDER BY q.scan_id DESC";

        int rowIndex = 5;
        int serial = 1;

        try (PreparedStatement ps = con.prepareStatement(sql)) {
            for (int i = 0; i < params.size(); i++) {
                ps.setString(i + 1, params.get(i));
            }

            try (ResultSet rs = ps.executeQuery()) {
                while (rs.next()) {
                    Row row = sheet.createRow(rowIndex++);
                    row.setHeightInPoints(38);

                    String scanStatus = rs.getString("scan_status");
                    CellStyle statusStyle = "SUCCESS".equalsIgnoreCase(scanStatus) ? success : danger;

                    String scanId = rs.getString("scan_id");
                    String assetId = rs.getString("asset_id");

                    setCell(row, 0, String.valueOf(serial++), center);
                    setCell(row, 1, scanId, center);
                    setCell(row, 2, assetId, center);
                    setCell(row, 3, rs.getString("asset_code"), text);
                    setCell(row, 4, rs.getString("asset_name"), text);
                    setCell(row, 5, rs.getString("department_name"), text);
                    setCell(row, 6, rs.getString("category_name"), text);
                    setCell(row, 7, rs.getString("qr_public_token"), text);
                    setCell(row, 8, scanStatus, statusStyle);
                    setCell(row, 9, rs.getString("scan_source"), center);
                    setCell(row, 10, rs.getString("scan_ip"), text);
                    setCell(row, 11, rs.getString("scan_user_agent"), text);
                    setCell(row, 12, rs.getString("remarks"), text);
                    setCell(row, 13, rs.getString("scanned_at"), center);
                    setCell(row, 14, "view_qr_scan_log.jsp?id=" + scanId, text);
                    setCell(row, 15, assetId == null || assetId.trim().isEmpty() ? "N/A" : "view_asset.jsp?id=" + assetId, text);
                }
            }
        }

        if (serial == 1) {
            Row row = sheet.createRow(5);
            setCell(row, 0, "1", center);
            setCell(row, 1, "No QR asset scan history found", text);
            setCell(row, 2, "Selected filters are clean.", text);
        }

        sheet.createFreezePane(0, 5);
        sheet.setAutoFilter(new org.apache.poi.ss.util.CellRangeAddress(4, 4, 0, 15));

        int[] widths = {
                2600, 3000, 3000, 5200, 7600, 6000, 5200, 9000,
                4200, 4200, 5200, 15000, 10000, 5600, 6500, 6500
        };

        for (int i = 0; i < widths.length; i++) {
            sheet.setColumnWidth(i, widths[i]);
        }

        ServletOutputStream outputStream = response.getOutputStream();
        workbook.write(outputStream);
        outputStream.flush();

    } catch (Exception e) {
        System.err.println("QR Module DB Error: " + e.getMessage());
        response.reset();
        response.setContentType("text/html;charset=UTF-8");
%>
        <h2>QR Asset Scan History Excel Export Failed</h2>
        <p>Please check server console for the exact error.</p>
        <p>An internal error occurred while generating the report. Please contact the administrator.</p>
<%
    }

    return;
%>
