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

    private boolean tableExists(Connection con, String tableName) {
        String sql = "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = DATABASE() AND table_name = ?";

        try (PreparedStatement ps = con.prepareStatement(sql)) {
            ps.setString(1, tableName);

            try (ResultSet rs = ps.executeQuery()) {
                return rs.next() && rs.getInt(1) > 0;
            }

        } catch (Exception e) {
            System.err.println("QR Module DB Error: " + e.getMessage());
        }

        return false;
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

    if (q == null) {
        q = "";
    }

    q = q.trim();

    String generatedAt = new SimpleDateFormat("dd-MMM-yyyy hh:mm a").format(new java.util.Date());
    String fileDate = new SimpleDateFormat("yyyyMMdd_HHmmss").format(new java.util.Date());
    String fileName = "IR_AMS_QR_Reissue_History_" + fileDate + ".xlsx";

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

        Sheet sheet = workbook.createSheet("QR Reissue History");

        CellStyle title = titleStyle(workbook);
        CellStyle subtitle = subtitleStyle(workbook);
        CellStyle header = headerStyle(workbook);
        CellStyle text = textStyle(workbook);
        CellStyle center = centerStyle(workbook);

        setMergedTitle(sheet, 0, 0, 14, "INDIAN RAILWAYS - EAST COAST RAILWAY", title);
        setMergedTitle(sheet, 1, 0, 14, "IR-AMS QR TOKEN REISSUE HISTORY", title);
        setMergedTitle(sheet, 2, 0, 14,
                "Generated By: " + username + " (" + role + ") | Generated At: " + generatedAt
                + (q.isEmpty() ? "" : " | Search: " + sanitizeForExcelCell(q)),
                subtitle);

        Row headerRow = sheet.createRow(4);
        headerRow.setHeightInPoints(32);

        String[] headers = {
                "Sl. No.",
                "History ID",
                "Asset ID",
                "Asset Code",
                "Asset Name",
                "Old QR Token",
                "New QR Token",
                "Old QR URL",
                "New QR URL",
                "Reissue Reason",
                "Reissued By User ID",
                "Reissued By Username",
                "Reissued By Role",
                "Created At",
                "Asset Link"
        };

        for (int i = 0; i < headers.length; i++) {
            setCell(headerRow, i, headers[i], header);
        }

        int rowIndex = 5;
        int serial = 1;

        if (!tableExists(con, "asset_qr_token_history")) {
            Row row = sheet.createRow(rowIndex);
            setCell(row, 0, "1", center);
            setCell(row, 1, "No QR reissue history table found", text);
            setCell(row, 2, "It will be created after first reissue.", text);
        } else {
            StringBuilder where = new StringBuilder(" WHERE 1 = 1 ");
            List<String> params = new ArrayList<String>();

            if (!q.isEmpty()) {
                where.append("AND (")
                        .append("asset_code LIKE ? ")
                        .append("OR asset_name LIKE ? ")
                        .append("OR old_qr_public_token LIKE ? ")
                        .append("OR new_qr_public_token LIKE ? ")
                        .append("OR reissue_reason LIKE ? ")
                        .append("OR reissued_by_username LIKE ? ")
                        .append(") ");

                String searchValue = "%" + q + "%";

                for (int i = 0; i < 6; i++) {
                    params.add(searchValue);
                }
            }

            String sql =
                    "SELECT "
                    + "history_id, asset_id, asset_code, asset_name, "
                    + "old_qr_public_token, new_qr_public_token, old_qr_code, new_qr_code, "
                    + "reissue_reason, reissued_by_user_id, reissued_by_username, reissued_by_role, "
                    + "DATE_FORMAT(created_at, '%d %b %Y, %h:%i %p') AS created_at "
                    + "FROM asset_qr_token_history "
                    + where.toString()
                    + "ORDER BY history_id DESC";

            try (PreparedStatement ps = con.prepareStatement(sql)) {
                for (int i = 0; i < params.size(); i++) {
                    ps.setString(i + 1, params.get(i));
                }

                try (ResultSet rs = ps.executeQuery()) {
                    while (rs.next()) {
                        Row row = sheet.createRow(rowIndex++);
                        row.setHeightInPoints(40);

                        String assetId = rs.getString("asset_id");

                        setCell(row, 0, String.valueOf(serial++), center);
                        setCell(row, 1, rs.getString("history_id"), center);
                        setCell(row, 2, assetId, center);
                        setCell(row, 3, rs.getString("asset_code"), text);
                        setCell(row, 4, rs.getString("asset_name"), text);
                        setCell(row, 5, rs.getString("old_qr_public_token"), text);
                        setCell(row, 6, rs.getString("new_qr_public_token"), text);
                        setCell(row, 7, rs.getString("old_qr_code"), text);
                        setCell(row, 8, rs.getString("new_qr_code"), text);
                        setCell(row, 9, rs.getString("reissue_reason"), text);
                        setCell(row, 10, rs.getString("reissued_by_user_id"), center);
                        setCell(row, 11, rs.getString("reissued_by_username"), text);
                        setCell(row, 12, rs.getString("reissued_by_role"), center);
                        setCell(row, 13, rs.getString("created_at"), center);
                        setCell(row, 14, assetId == null || assetId.trim().isEmpty() ? "N/A" : "view_asset.jsp?id=" + assetId, text);
                    }
                }
            }

            if (serial == 1) {
                Row row = sheet.createRow(5);
                setCell(row, 0, "1", center);
                setCell(row, 1, "No QR reissue history found", text);
                setCell(row, 2, "Selected search is empty.", text);
            }
        }

        sheet.createFreezePane(0, 5);
        sheet.setAutoFilter(new org.apache.poi.ss.util.CellRangeAddress(4, 4, 0, 14));

        int[] widths = {
                2600, 3200, 3200, 5200, 7600, 9000, 9000,
                12000, 12000, 9000, 4200, 5600, 4600, 5600, 6500
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
        <h2>QR Reissue History Excel Export Failed</h2>
        <p>Please check server console for the exact error.</p>
        <p>An internal error occurred while generating the report. Please contact the administrator.</p>
<%
    }

    return;
%>
