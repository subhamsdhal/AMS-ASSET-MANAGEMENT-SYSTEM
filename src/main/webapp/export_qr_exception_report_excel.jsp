<%@page contentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet" pageEncoding="UTF-8" trimDirectiveWhitespaces="true"%>
<%@page import="com.mycompany.asset_management_system_ams.DBConnection"%>
<%@page import="java.sql.*"%>
<%@page import="java.util.*"%>
<%@page import="java.text.SimpleDateFormat"%>
<%@page import="org.apache.poi.ss.usermodel.*"%>
<%@page import="org.apache.poi.xssf.usermodel.XSSFWorkbook"%>
<%@page import="jakarta.servlet.ServletOutputStream"%>
<%@page import="jakarta.servlet.http.HttpServletRequest"%>

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

    private String appBaseUrl(HttpServletRequest request) {
        String scheme = request.getHeader("X-Forwarded-Proto");

        if (scheme == null || scheme.trim().isEmpty()) {
            scheme = request.getScheme();
        }

        String host = request.getHeader("X-Forwarded-Host");

        if (host == null || host.trim().isEmpty()) {
            host = request.getServerName();

            int port = request.getServerPort();

            if (!("http".equalsIgnoreCase(scheme) && port == 80)
                    && !("https".equalsIgnoreCase(scheme) && port == 443)) {
                host = host + ":" + port;
            }
        }

        return scheme + "://" + host + request.getContextPath();
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
        font.setFontHeightInPoints((short) 10);
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
        font.setColor(IndexedColors.BLUE.getIndex());

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

    private void addExcelRow(Sheet sheet, int rowIndex, int serial, String issueType, String severity,
            String assetId, String assetCode, String assetName, String departmentName, String assetStatus,
            String token, String storedUrl, String expectedUrl, String details, String refTime,
            CellStyle text, CellStyle center, CellStyle high, CellStyle medium, CellStyle low) {

        Row row = sheet.createRow(rowIndex);
        row.setHeightInPoints(38);

        CellStyle severityStyle = low;

        if ("HIGH".equalsIgnoreCase(severity)) {
            severityStyle = high;
        } else if ("MEDIUM".equalsIgnoreCase(severity)) {
            severityStyle = medium;
        }

        setCell(row, 0, String.valueOf(serial), center);
        setCell(row, 1, issueType, severityStyle);
        setCell(row, 2, severity, severityStyle);
        setCell(row, 3, assetId, center);
        setCell(row, 4, assetCode, text);
        setCell(row, 5, assetName, text);
        setCell(row, 6, departmentName, text);
        setCell(row, 7, assetStatus, center);
        setCell(row, 8, token, text);
        setCell(row, 9, storedUrl, text);
        setCell(row, 10, expectedUrl, text);
        setCell(row, 11, details, text);
        setCell(row, 12, refTime, center);
        setCell(row, 13, assetId == null || assetId.trim().isEmpty() ? "N/A" : "view_asset.jsp?id=" + assetId, text);
    }
return;
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
    String issueFilter = request.getParameter("issue");

    if (q == null) {
        q = "";
    }

    if (issueFilter == null || issueFilter.trim().isEmpty()) {
        issueFilter = "ALL";
    }

    q = q.trim();
    issueFilter = issueFilter.trim().toUpperCase(Locale.ENGLISH);

    String baseUrl = appBaseUrl(request);

    String generatedAt = new SimpleDateFormat("dd-MMM-yyyy hh:mm a").format(new java.util.Date());
    String fileDate = new SimpleDateFormat("yyyyMMdd_HHmmss").format(new java.util.Date());
    String fileName = "IR_AMS_QR_Exception_Report_" + cleanFilePart(issueFilter) + "_" + fileDate + ".xlsx";

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

        Sheet sheet = workbook.createSheet("QR Exceptions");

        CellStyle title = titleStyle(workbook);
        CellStyle subtitle = subtitleStyle(workbook);
        CellStyle header = headerStyle(workbook);
        CellStyle text = textStyle(workbook);
        CellStyle center = centerStyle(workbook);
        CellStyle high = highStyle(workbook);
        CellStyle medium = mediumStyle(workbook);
        CellStyle low = lowStyle(workbook);

        setMergedTitle(sheet, 0, 0, 13, "INDIAN RAILWAYS - EAST COAST RAILWAY", title);
        setMergedTitle(sheet, 1, 0, 13, "IR-AMS QR EXCEPTION REPORT", title);
        setMergedTitle(sheet, 2, 0, 13,
                "Generated By: " + username + " (" + role + ") | Generated At: " + generatedAt
                + " | Issue Filter: " + issueFilter
                + (q.isEmpty() ? "" : " | Search: " + sanitizeForExcelCell(q)),
                subtitle);

        Row headerRow = sheet.createRow(4);
        headerRow.setHeightInPoints(32);

        String[] headers = {
                "Sl. No.",
                "Issue Type",
                "Severity",
                "Asset ID",
                "Asset Code",
                "Asset Name",
                "Department",
                "Asset Status",
                "QR Token",
                "Stored URL",
                "Expected URL / Action",
                "Details",
                "Reference Time",
                "Asset Link"
        };

        for (int i = 0; i < headers.length; i++) {
            setCell(headerRow, i, headers[i], header);
        }

        int rowIndex = 5;
        int serial = 1;

        if ("ALL".equals(issueFilter) || "MISSING_TOKEN".equals(issueFilter)) {
            StringBuilder sql = new StringBuilder();

            sql.append("SELECT ")
                    .append("a.asset_id, a.asset_code, a.asset_name, a.asset_status, ")
                    .append("COALESCE(d.department_name, 'Unassigned') AS department_name, ")
                    .append("COALESCE(a.qr_public_token, '') AS token_value, ")
                    .append("COALESCE(a.qr_code, '') AS stored_url, ")
                    .append("DATE_FORMAT(a.updated_at, '%d %b %Y, %h:%i %p') AS ref_time ")
                    .append("FROM assets a ")
                    .append("LEFT JOIN departments d ON a.department_id = d.department_id ")
                    .append("WHERE a.qr_public_token IS NULL OR TRIM(a.qr_public_token) = '' ");

            List<String> params = new ArrayList<String>();

            if (!q.isEmpty()) {
                sql.append("AND (a.asset_code LIKE ? OR a.asset_name LIKE ? OR d.department_name LIKE ?) ");
                String searchValue = "%" + q + "%";
                params.add(searchValue);
                params.add(searchValue);
                params.add(searchValue);
            }

            sql.append("ORDER BY a.asset_id DESC");

            try (PreparedStatement ps = con.prepareStatement(sql.toString())) {
                for (int i = 0; i < params.size(); i++) {
                    ps.setString(i + 1, params.get(i));
                }

                try (ResultSet rs = ps.executeQuery()) {
                    while (rs.next()) {
                        addExcelRow(sheet, rowIndex++, serial++, "MISSING_TOKEN", "HIGH",
                                rs.getString("asset_id"),
                                rs.getString("asset_code"),
                                rs.getString("asset_name"),
                                rs.getString("department_name"),
                                rs.getString("asset_status"),
                                rs.getString("token_value"),
                                rs.getString("stored_url"),
                                "Generate QR token first",
                                "Asset does not have QR public token. Generate QR before printing label.",
                                rs.getString("ref_time"),
                                text, center, high, medium, low);
                    }
                }
            }
        }

        if ("ALL".equals(issueFilter) || "URL_MISMATCH".equals(issueFilter)) {
            StringBuilder sql = new StringBuilder();

            sql.append("SELECT ")
                    .append("a.asset_id, a.asset_code, a.asset_name, a.asset_status, ")
                    .append("COALESCE(d.department_name, 'Unassigned') AS department_name, ")
                    .append("a.qr_public_token AS token_value, ")
                    .append("COALESCE(a.qr_code, '') AS stored_url, ")
                    .append("DATE_FORMAT(a.updated_at, '%d %b %Y, %h:%i %p') AS ref_time ")
                    .append("FROM assets a ")
                    .append("LEFT JOIN departments d ON a.department_id = d.department_id ")
                    .append("WHERE a.qr_public_token IS NOT NULL AND TRIM(a.qr_public_token) <> '' ")
                    .append("AND (a.qr_code IS NULL OR TRIM(a.qr_code) = '' ")
                    .append("OR a.qr_code <> CONCAT(?, '/public_asset_view.jsp?token=', a.qr_public_token)) ");

            List<String> params = new ArrayList<String>();
            params.add(baseUrl);

            if (!q.isEmpty()) {
                sql.append("AND (a.asset_code LIKE ? OR a.asset_name LIKE ? OR d.department_name LIKE ? OR a.qr_public_token LIKE ? OR a.qr_code LIKE ?) ");

                String searchValue = "%" + q + "%";

                for (int i = 0; i < 5; i++) {
                    params.add(searchValue);
                }
            }

            sql.append("ORDER BY a.asset_id DESC");

            try (PreparedStatement ps = con.prepareStatement(sql.toString())) {
                for (int i = 0; i < params.size(); i++) {
                    ps.setString(i + 1, params.get(i));
                }

                try (ResultSet rs = ps.executeQuery()) {
                    while (rs.next()) {
                        String token = rs.getString("token_value");

                        addExcelRow(sheet, rowIndex++, serial++, "URL_MISMATCH", "MEDIUM",
                                rs.getString("asset_id"),
                                rs.getString("asset_code"),
                                rs.getString("asset_name"),
                                rs.getString("department_name"),
                                rs.getString("asset_status"),
                                token,
                                rs.getString("stored_url"),
                                baseUrl + "/public_asset_view.jsp?token=" + token,
                                "Stored QR URL does not match current application base URL. Use QR URL Refresh.",
                                rs.getString("ref_time"),
                                text, center, high, medium, low);
                    }
                }
            }
        }

        if (tableExists(con, "asset_qr_scan_logs") && ("ALL".equals(issueFilter) || "INVALID_TOKEN".equals(issueFilter))) {
            StringBuilder sql = new StringBuilder();

            sql.append("SELECT ")
                    .append("q.asset_id, COALESCE(a.asset_code, 'No Linked Asset') AS asset_code, ")
                    .append("COALESCE(a.asset_name, 'Invalid token was not linked with any asset') AS asset_name, ")
                    .append("COALESCE(a.asset_status, '') AS asset_status, ")
                    .append("COALESCE(d.department_name, 'Not Available') AS department_name, ")
                    .append("COALESCE(q.qr_public_token, '') AS token_value, ")
                    .append("COALESCE(q.remarks, '') AS details, ")
                    .append("DATE_FORMAT(q.scanned_at, '%d %b %Y, %h:%i %p') AS ref_time ")
                    .append("FROM asset_qr_scan_logs q ")
                    .append("LEFT JOIN assets a ON q.asset_id = a.asset_id ")
                    .append("LEFT JOIN departments d ON a.department_id = d.department_id ")
                    .append("WHERE q.scan_status = 'INVALID_TOKEN' ");

            List<String> params = new ArrayList<String>();

            if (!q.isEmpty()) {
                sql.append("AND (a.asset_code LIKE ? OR a.asset_name LIKE ? OR d.department_name LIKE ? OR q.qr_public_token LIKE ? OR q.remarks LIKE ?) ");

                String searchValue = "%" + q + "%";

                for (int i = 0; i < 5; i++) {
                    params.add(searchValue);
                }
            }

            sql.append("ORDER BY q.scan_id DESC");

            try (PreparedStatement ps = con.prepareStatement(sql.toString())) {
                for (int i = 0; i < params.size(); i++) {
                    ps.setString(i + 1, params.get(i));
                }

                try (ResultSet rs = ps.executeQuery()) {
                    while (rs.next()) {
                        addExcelRow(sheet, rowIndex++, serial++, "INVALID_TOKEN", "LOW",
                                rs.getString("asset_id"),
                                rs.getString("asset_code"),
                                rs.getString("asset_name"),
                                rs.getString("department_name"),
                                rs.getString("asset_status"),
                                rs.getString("token_value"),
                                "N/A",
                                "No matching asset found",
                                rs.getString("details"),
                                rs.getString("ref_time"),
                                text, center, high, medium, low);
                    }
                }
            }
        }

        if (serial == 1) {
            Row row = sheet.createRow(5);
            row.setHeightInPoints(28);
            setCell(row, 0, "1", center);
            setCell(row, 1, "No QR exception found", low);
            setCell(row, 2, "OK", low);
            setCell(row, 3, "Selected filters are clean.", text);
        }

        sheet.createFreezePane(0, 5);
        sheet.setAutoFilter(new org.apache.poi.ss.util.CellRangeAddress(4, 4, 0, 13));

        int[] widths = {
                2600, 5200, 3600, 3000, 5200, 7500, 6000, 4200,
                8500, 12000, 12000, 10000, 5600, 6500
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
return;
%>
        <h2>QR Exception Report Excel Export Failed</h2>
        <p>Please check server console for the exact error.</p>
        <p>An internal error occurred while generating the report. Please contact the administrator.</p>
<%
    }

    return;
return;
%>