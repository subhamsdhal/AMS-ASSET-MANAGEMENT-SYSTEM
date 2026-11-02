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

    private void ensureTaggingTable(Connection con) throws Exception {
        String sql =
                "CREATE TABLE IF NOT EXISTS asset_qr_tagging_status ("
                + "tagging_id INT AUTO_INCREMENT PRIMARY KEY, "
                + "asset_id INT NOT NULL UNIQUE, "
                + "qr_public_token VARCHAR(120), "
                + "print_status VARCHAR(40) DEFAULT 'PENDING', "
                + "tag_status VARCHAR(40) DEFAULT 'PENDING', "
                + "printed_by_user_id INT, "
                + "tagged_by_user_id INT, "
                + "printed_at TIMESTAMP NULL, "
                + "tagged_at TIMESTAMP NULL, "
                + "remarks VARCHAR(500), "
                + "created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP, "
                + "updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP"
                + ") ENGINE=InnoDB DEFAULT CHARSET=utf8mb4";

        try (PreparedStatement ps = con.prepareStatement(sql)) {
            ps.executeUpdate();
        }
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

    private CellStyle goodStyle(Workbook workbook) {
        Font font = workbook.createFont();
        font.setBold(true);
        font.setColor(IndexedColors.GREEN.getIndex());

        CellStyle style = centerStyle(workbook);
        style.setFont(font);
        return style;
    }

    private CellStyle warnStyle(Workbook workbook) {
        Font font = workbook.createFont();
        font.setBold(true);
        font.setColor(IndexedColors.ORANGE.getIndex());

        CellStyle style = centerStyle(workbook);
        style.setFont(font);
        return style;
    }

    private CellStyle badStyle(Workbook workbook) {
        Font font = workbook.createFont();
        font.setBold(true);
        font.setColor(IndexedColors.RED.getIndex());

        CellStyle style = centerStyle(workbook);
        style.setFont(font);
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

    private CellStyle statusStyle(String status, CellStyle good, CellStyle warn, CellStyle bad, CellStyle center) {
        if (status == null) {
            return warn;
        }

        String value = status.trim().toUpperCase();

        if ("PRINTED".equals(value) || "TAGGED".equals(value)) {
            return good;
        }

        if ("REPRINT_REQUIRED".equals(value) || "DAMAGED".equals(value) || "REMOVED".equals(value)) {
            return bad;
        }

        if ("PENDING".equals(value)) {
            return warn;
        }

        return center;
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
    String printFilter = request.getParameter("print");
    String tagFilter = request.getParameter("tag");

    if (q == null) {
        q = "";
    }

    if (printFilter == null || printFilter.trim().isEmpty()) {
        printFilter = "ALL";
    }

    if (tagFilter == null || tagFilter.trim().isEmpty()) {
        tagFilter = "ALL";
    }

    q = q.trim();
    printFilter = printFilter.trim().toUpperCase(Locale.ENGLISH);
    tagFilter = tagFilter.trim().toUpperCase(Locale.ENGLISH);

    String generatedAt = new SimpleDateFormat("dd-MMM-yyyy hh:mm a").format(new java.util.Date());
    String fileDate = new SimpleDateFormat("yyyyMMdd_HHmmss").format(new java.util.Date());
    String fileName = "IR_AMS_QR_Tagging_Status_" + cleanFilePart(printFilter) + "_" + cleanFilePart(tagFilter) + "_" + fileDate + ".xlsx";

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

        ensureTaggingTable(con);

        Sheet sheet = workbook.createSheet("QR Tagging Status");

        CellStyle title = titleStyle(workbook);
        CellStyle subtitle = subtitleStyle(workbook);
        CellStyle header = headerStyle(workbook);
        CellStyle text = textStyle(workbook);
        CellStyle center = centerStyle(workbook);
        CellStyle good = goodStyle(workbook);
        CellStyle warn = warnStyle(workbook);
        CellStyle bad = badStyle(workbook);

        setMergedTitle(sheet, 0, 0, 18, "INDIAN RAILWAYS - EAST COAST RAILWAY", title);
        setMergedTitle(sheet, 1, 0, 18, "IR-AMS QR PHYSICAL TAGGING STATUS REPORT", title);
        setMergedTitle(sheet, 2, 0, 18,
                "Generated By: " + username + " (" + role + ") | Generated At: " + generatedAt
                + " | Print Filter: " + printFilter
                + " | Tag Filter: " + tagFilter
                + (q.isEmpty() ? "" : " | Search: " + sanitizeForExcelCell(q)),
                subtitle);

        Row headerRow = sheet.createRow(4);
        headerRow.setHeightInPoints(32);

        String[] headers = {
                "Sl. No.",
                "Asset ID",
                "Asset Code",
                "Asset Name",
                "Category",
                "Department",
                "Location",
                "Asset Status",
                "QR Token",
                "QR URL",
                "Print Status",
                "Tag Status",
                "Printed At",
                "Printed By",
                "Tagged At",
                "Tagged By",
                "Remarks",
                "Last Updated",
                "Asset Link"
        };

        for (int i = 0; i < headers.length; i++) {
            setCell(headerRow, i, headers[i], header);
        }

        StringBuilder sql = new StringBuilder();

        sql.append("SELECT ")
                .append("a.asset_id, a.asset_code, a.asset_name, a.asset_status, ")
                .append("a.qr_public_token, a.qr_code, ")
                .append("COALESCE(ac.category_name, 'Uncategorized') AS category_name, ")
                .append("COALESCE(d.department_name, 'Unassigned') AS department_name, ")
                .append("COALESCE(rl.location_name, a.location, 'Not Mentioned') AS location_name, ")
                .append("COALESCE(t.print_status, 'PENDING') AS print_status, ")
                .append("COALESCE(t.tag_status, 'PENDING') AS tag_status, ")
                .append("DATE_FORMAT(t.printed_at, '%d %b %Y, %h:%i %p') AS printed_at, ")
                .append("DATE_FORMAT(t.tagged_at, '%d %b %Y, %h:%i %p') AS tagged_at, ")
                .append("COALESCE(pu.username, 'N/A') AS printed_by, ")
                .append("COALESCE(tu.username, 'N/A') AS tagged_by, ")
                .append("COALESCE(t.remarks, '') AS remarks, ")
                .append("DATE_FORMAT(COALESCE(t.updated_at, a.updated_at), '%d %b %Y, %h:%i %p') AS updated_at ")
                .append("FROM assets a ")
                .append("LEFT JOIN asset_categories ac ON a.category_id = ac.category_id ")
                .append("LEFT JOIN departments d ON a.department_id = d.department_id ")
                .append("LEFT JOIN railway_locations rl ON a.location_id = rl.location_id ")
                .append("LEFT JOIN asset_qr_tagging_status t ON a.asset_id = t.asset_id ")
                .append("LEFT JOIN users pu ON t.printed_by_user_id = pu.user_id ")
                .append("LEFT JOIN users tu ON t.tagged_by_user_id = tu.user_id ")
                .append("WHERE a.qr_public_token IS NOT NULL AND TRIM(a.qr_public_token) <> '' ");

        List<String> params = new ArrayList<String>();

        if (!"ALL".equals(printFilter)) {
            sql.append("AND COALESCE(t.print_status, 'PENDING') = ? ");
            params.add(printFilter);
        }

        if (!"ALL".equals(tagFilter)) {
            sql.append("AND COALESCE(t.tag_status, 'PENDING') = ? ");
            params.add(tagFilter);
        }

        if (!q.isEmpty()) {
            sql.append("AND (")
                    .append("a.asset_code LIKE ? ")
                    .append("OR a.asset_name LIKE ? ")
                    .append("OR a.qr_public_token LIKE ? ")
                    .append("OR d.department_name LIKE ? ")
                    .append("OR ac.category_name LIKE ? ")
                    .append("OR rl.location_name LIKE ? ")
                    .append(") ");

            String searchValue = "%" + q + "%";

            for (int i = 0; i < 6; i++) {
                params.add(searchValue);
            }
        }

        sql.append("ORDER BY d.department_name ASC, rl.location_name ASC, a.asset_code ASC");

        int rowIndex = 5;
        int serial = 1;

        try (PreparedStatement ps = con.prepareStatement(sql.toString())) {
            for (int i = 0; i < params.size(); i++) {
                ps.setString(i + 1, params.get(i));
            }

            try (ResultSet rs = ps.executeQuery()) {
                while (rs.next()) {
                    Row row = sheet.createRow(rowIndex++);
                    row.setHeightInPoints(36);

                    String printStatus = rs.getString("print_status");
                    String tagStatus = rs.getString("tag_status");
                    String assetId = rs.getString("asset_id");

                    setCell(row, 0, String.valueOf(serial++), center);
                    setCell(row, 1, assetId, center);
                    setCell(row, 2, rs.getString("asset_code"), text);
                    setCell(row, 3, rs.getString("asset_name"), text);
                    setCell(row, 4, rs.getString("category_name"), text);
                    setCell(row, 5, rs.getString("department_name"), text);
                    setCell(row, 6, rs.getString("location_name"), text);
                    setCell(row, 7, rs.getString("asset_status"), center);
                    setCell(row, 8, rs.getString("qr_public_token"), text);
                    setCell(row, 9, rs.getString("qr_code"), text);
                    setCell(row, 10, printStatus, statusStyle(printStatus, good, warn, bad, center));
                    setCell(row, 11, tagStatus, statusStyle(tagStatus, good, warn, bad, center));
                    setCell(row, 12, rs.getString("printed_at"), center);
                    setCell(row, 13, rs.getString("printed_by"), center);
                    setCell(row, 14, rs.getString("tagged_at"), center);
                    setCell(row, 15, rs.getString("tagged_by"), center);
                    setCell(row, 16, rs.getString("remarks"), text);
                    setCell(row, 17, rs.getString("updated_at"), center);
                    setCell(row, 18, "view_asset.jsp?id=" + assetId, text);
                }
            }
        }

        if (serial == 1) {
            Row row = sheet.createRow(5);
            setCell(row, 0, "1", center);
            setCell(row, 1, "No QR tagging record found", text);
            setCell(row, 2, "Selected filter is empty.", text);
        }

        sheet.createFreezePane(0, 5);
        sheet.setAutoFilter(new org.apache.poi.ss.util.CellRangeAddress(4, 4, 0, 18));

        int[] widths = {
                2600, 3000, 5200, 7600, 5200, 6000, 7000, 4200, 9000,
                12000, 4300, 4300, 5600, 5200, 5600, 5200, 9000, 5600, 6500
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
        <h2>QR Tagging Status Excel Export Failed</h2>
        <p>Please check server console for the exact error.</p>
        <p>An internal error occurred while generating the report. Please contact the administrator.</p>
<%
    }

    return;
%>
