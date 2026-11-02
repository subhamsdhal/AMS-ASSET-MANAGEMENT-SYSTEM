<%@page contentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet" pageEncoding="UTF-8" trimDirectiveWhitespaces="true"%>
<%@page import="com.mycompany.asset_management_system_ams.DBConnection"%>
<%@page import="java.sql.*"%>
<%@page import="java.util.*"%>
<%@page import="java.text.SimpleDateFormat"%>
<%@page import="java.io.OutputStream"%>
<%@page import="org.apache.poi.ss.usermodel.*"%>
<%@page import="org.apache.poi.xssf.usermodel.XSSFWorkbook"%>
<%@page import="org.apache.poi.ss.util.CellRangeAddress"%>

<%!
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
            System.err.println("QR Module DB Error: " + e.getMessage());
        }

        return false;
    }

    private String safeCell(String value) {
        if (value == null || value.trim().isEmpty()) {
            return "N/A";
        }

        return value.trim();
    }

    private void createMergedTitle(Sheet sheet, int rowIndex, int startCol, int endCol, String title, CellStyle style) {
        Row row = sheet.createRow(rowIndex);
        row.setHeightInPoints(24);

        for (int c = startCol; c <= endCol; c++) {
            Cell cell = row.createCell(c);
            cell.setCellStyle(style);

            if (c == startCol) {
                cell.setCellValue(title);
            }
        }

        sheet.addMergedRegion(new CellRangeAddress(rowIndex, rowIndex, startCol, endCol));
    }

    private void createHeader(Row row, String[] headers, CellStyle style) {
        for (int i = 0; i < headers.length; i++) {
            Cell cell = row.createCell(i);
            cell.setCellValue(headers[i]);
            cell.setCellStyle(style);
        }
    }

    private void setText(Row row, int col, String value, CellStyle style) {
        Cell cell = row.createCell(col);
        cell.setCellValue(safeCell(value));
        cell.setCellStyle(style);
    }

    private void setNumber(Row row, int col, double value, CellStyle style) {
        Cell cell = row.createCell(col);
        cell.setCellValue(value);
        cell.setCellStyle(style);
    }

    private int writeCoverageSection(Connection con,
                                     Sheet sheet,
                                     int rowIndex,
                                     String sectionTitle,
                                     String sql,
                                     CellStyle sectionStyle,
                                     CellStyle headerStyle,
                                     CellStyle dataStyle,
                                     CellStyle centerStyle,
                                     CellStyle numberStyle,
                                     CellStyle percentStyle) {

        createMergedTitle(sheet, rowIndex++, 0, 5, sectionTitle, sectionStyle);

        Row header = sheet.createRow(rowIndex++);
        createHeader(header, new String[]{
            "Sl. No.", "Group Name", "Total Assets", "QR Generated", "QR Missing", "Coverage %"
        }, headerStyle);

        int sl = 1;
        boolean hasData = false;

        try (PreparedStatement ps = con.prepareStatement(sql);
             ResultSet rs = ps.executeQuery()) {

            while (rs.next()) {
                hasData = true;

                String groupName = rs.getString("group_name");
                int totalAssets = rs.getInt("total_assets");
                int qrGenerated = rs.getInt("qr_generated");
                int qrMissing = Math.max(totalAssets - qrGenerated, 0);
                double coverage = totalAssets == 0 ? 0 : qrGenerated / (double) totalAssets;

                Row row = sheet.createRow(rowIndex++);
                setNumber(row, 0, sl++, numberStyle);
                setText(row, 1, groupName, dataStyle);
                setNumber(row, 2, totalAssets, numberStyle);
                setNumber(row, 3, qrGenerated, numberStyle);
                setNumber(row, 4, qrMissing, numberStyle);
                setNumber(row, 5, coverage, percentStyle);
            }

        } catch (Exception e) {
            System.err.println("QR Module DB Error: " + e.getMessage());

            Row row = sheet.createRow(rowIndex++);
            setText(row, 0, "Error", centerStyle);
            setText(row, 1, e.getMessage(), dataStyle);
            setNumber(row, 2, 0, numberStyle);
            setNumber(row, 3, 0, numberStyle);
            setNumber(row, 4, 0, numberStyle);
            setNumber(row, 5, 0, percentStyle);
        }

        if (!hasData) {
            Row row = sheet.createRow(rowIndex++);
            setText(row, 0, "N/A", centerStyle);
            setText(row, 1, "No data available for this coverage section.", dataStyle);
            setNumber(row, 2, 0, numberStyle);
            setNumber(row, 3, 0, numberStyle);
            setNumber(row, 4, 0, numberStyle);
            setNumber(row, 5, 0, percentStyle);
        }

        return rowIndex + 2;
    }

    private void autoSizeColumns(Sheet sheet, int totalCols) {
        for (int i = 0; i < totalCols; i++) {
            sheet.autoSizeColumn(i);

            int width = sheet.getColumnWidth(i);

            if (width < 3500) {
                sheet.setColumnWidth(i, 3500);
            }

            if (width > 9000) {
                sheet.setColumnWidth(i, 9000);
            }
        }
    }
%>
<%
    String username = (String) session.getAttribute("username");
    String role = (String) session.getAttribute("role");

    if (username == null || role == null) {
        response.sendRedirect("login.jsp");
        return;
    }

    boolean allowed = ("SUPER_ADMIN".equals(role) || "ADMIN".equals(role))
            || "ASSET_MANAGER".equals(role)
            || "AUDITOR".equals(role);

    if (!allowed) {
        response.sendRedirect("dashboard.jsp?access=denied");
        return;
    }

    response.reset();

    String fileName = "IR_AMS_QR_Coverage_Report_"
            + new SimpleDateFormat("yyyyMMdd_HHmmss").format(new java.util.Date())
            + ".xlsx";

    response.setContentType("application/vnd.openxmlformats-officedocument.spreadsheetml.sheet");
    response.setHeader("Content-Disposition", "attachment; filename=\"" + fileName + "\"");
    response.setHeader("Cache-Control", "no-cache, no-store, must-revalidate");
    response.setHeader("Pragma", "no-cache");
    response.setDateHeader("Expires", 0);

    Workbook workbook = new XSSFWorkbook();

    try {
        Sheet sheet = workbook.createSheet("QR Coverage");

        Font titleFont = workbook.createFont();
        titleFont.setBold(true);
        titleFont.setFontHeightInPoints((short) 16);
        titleFont.setColor(IndexedColors.DARK_BLUE.getIndex());

        Font subTitleFont = workbook.createFont();
        subTitleFont.setBold(true);
        subTitleFont.setFontHeightInPoints((short) 13);
        subTitleFont.setColor(IndexedColors.DARK_BLUE.getIndex());

        Font metaFont = workbook.createFont();
        metaFont.setBold(true);
        metaFont.setFontHeightInPoints((short) 10);
        metaFont.setColor(IndexedColors.BLUE_GREY.getIndex());

        Font whiteFont = workbook.createFont();
        whiteFont.setBold(true);
        whiteFont.setColor(IndexedColors.WHITE.getIndex());

        Font dataFont = workbook.createFont();
        dataFont.setFontHeightInPoints((short) 10);
        dataFont.setColor(IndexedColors.DARK_BLUE.getIndex());

        CellStyle titleStyle = workbook.createCellStyle();
        titleStyle.setAlignment(HorizontalAlignment.CENTER);
        titleStyle.setVerticalAlignment(VerticalAlignment.CENTER);
        titleStyle.setFont(titleFont);

        CellStyle subTitleStyle = workbook.createCellStyle();
        subTitleStyle.setAlignment(HorizontalAlignment.CENTER);
        subTitleStyle.setVerticalAlignment(VerticalAlignment.CENTER);
        subTitleStyle.setFont(subTitleFont);

        CellStyle metaStyle = workbook.createCellStyle();
        metaStyle.setAlignment(HorizontalAlignment.CENTER);
        metaStyle.setVerticalAlignment(VerticalAlignment.CENTER);
        metaStyle.setFont(metaFont);

        CellStyle sectionStyle = workbook.createCellStyle();
        sectionStyle.setFillForegroundColor(IndexedColors.DARK_BLUE.getIndex());
        sectionStyle.setFillPattern(FillPatternType.SOLID_FOREGROUND);
        sectionStyle.setAlignment(HorizontalAlignment.CENTER);
        sectionStyle.setVerticalAlignment(VerticalAlignment.CENTER);
        sectionStyle.setFont(whiteFont);
        sectionStyle.setBorderTop(BorderStyle.THIN);
        sectionStyle.setBorderBottom(BorderStyle.THIN);
        sectionStyle.setBorderLeft(BorderStyle.THIN);
        sectionStyle.setBorderRight(BorderStyle.THIN);

        CellStyle headerStyle = workbook.createCellStyle();
        headerStyle.setFillForegroundColor(IndexedColors.DARK_BLUE.getIndex());
        headerStyle.setFillPattern(FillPatternType.SOLID_FOREGROUND);
        headerStyle.setAlignment(HorizontalAlignment.CENTER);
        headerStyle.setVerticalAlignment(VerticalAlignment.CENTER);
        headerStyle.setFont(whiteFont);
        headerStyle.setBorderTop(BorderStyle.THIN);
        headerStyle.setBorderBottom(BorderStyle.THIN);
        headerStyle.setBorderLeft(BorderStyle.THIN);
        headerStyle.setBorderRight(BorderStyle.THIN);

        CellStyle dataStyle = workbook.createCellStyle();
        dataStyle.setAlignment(HorizontalAlignment.LEFT);
        dataStyle.setVerticalAlignment(VerticalAlignment.CENTER);
        dataStyle.setFont(dataFont);
        dataStyle.setWrapText(true);
        dataStyle.setBorderTop(BorderStyle.THIN);
        dataStyle.setBorderBottom(BorderStyle.THIN);
        dataStyle.setBorderLeft(BorderStyle.THIN);
        dataStyle.setBorderRight(BorderStyle.THIN);

        CellStyle centerStyle = workbook.createCellStyle();
        centerStyle.cloneStyleFrom(dataStyle);
        centerStyle.setAlignment(HorizontalAlignment.CENTER);

        CellStyle numberStyle = workbook.createCellStyle();
        numberStyle.cloneStyleFrom(centerStyle);
        numberStyle.setDataFormat(workbook.createDataFormat().getFormat("#,##0"));

        CellStyle percentStyle = workbook.createCellStyle();
        percentStyle.cloneStyleFrom(centerStyle);
        percentStyle.setDataFormat(workbook.createDataFormat().getFormat("0.0%"));

        createMergedTitle(sheet, 0, 0, 5, "INDIAN RAILWAYS - EAST COAST RAILWAY", titleStyle);
        createMergedTitle(sheet, 1, 0, 5, "IR-AMS QR COVERAGE REPORT", subTitleStyle);
        createMergedTitle(sheet, 2, 0, 5,
                "Generated By: " + username + " (" + role + ")  |  Generated At: "
                + new SimpleDateFormat("dd-MMM-yyyy hh:mm a", Locale.ENGLISH).format(new java.util.Date()),
                metaStyle);

        int rowIndex = 4;

        try (Connection con = DBConnection.getConnection()) {
            boolean hasAssetsQrToken = columnExists(con, "assets", "qr_public_token");

            if (!hasAssetsQrToken) {
                createMergedTitle(sheet, rowIndex++, 0, 1, "QR Coverage Status", sectionStyle);

                Row header = sheet.createRow(rowIndex++);
                createHeader(header, new String[]{"Status", "Message"}, headerStyle);

                Row row = sheet.createRow(rowIndex++);
                setText(row, 0, "Not Available", centerStyle);
                setText(row, 1, "Column assets.qr_public_token not found. Please complete QR database update first.", dataStyle);

            } else {
                boolean hasDepartmentsTable = tableExists(con, "departments");
                boolean hasAssetCategoriesTable = tableExists(con, "asset_categories");
                boolean hasCategoriesTable = tableExists(con, "categories");
                boolean hasRailwayLocationsTable = tableExists(con, "railway_locations");

                boolean hasDepartmentId = columnExists(con, "assets", "department_id");
                boolean hasCategoryId = columnExists(con, "assets", "category_id");
                boolean hasLocationId = columnExists(con, "assets", "location_id");
                boolean hasLocationText = columnExists(con, "assets", "location");

                String departmentSql;

                if (hasDepartmentId && hasDepartmentsTable) {
                    departmentSql =
                            "SELECT COALESCE(d.department_name, 'Unassigned') AS group_name, "
                            + "COUNT(a.asset_id) AS total_assets, "
                            + "SUM(CASE WHEN a.qr_public_token IS NOT NULL AND TRIM(a.qr_public_token) <> '' THEN 1 ELSE 0 END) AS qr_generated "
                            + "FROM assets a "
                            + "LEFT JOIN departments d ON a.department_id = d.department_id "
                            + "GROUP BY COALESCE(d.department_name, 'Unassigned') "
                            + "ORDER BY total_assets DESC, group_name ASC";
                } else {
                    departmentSql =
                            "SELECT COALESCE(NULLIF(asset_status, ''), 'Unclassified') AS group_name, "
                            + "COUNT(asset_id) AS total_assets, "
                            + "SUM(CASE WHEN qr_public_token IS NOT NULL AND TRIM(qr_public_token) <> '' THEN 1 ELSE 0 END) AS qr_generated "
                            + "FROM assets "
                            + "GROUP BY COALESCE(NULLIF(asset_status, ''), 'Unclassified') "
                            + "ORDER BY total_assets DESC, group_name ASC";
                }

                rowIndex = writeCoverageSection(con, sheet, rowIndex, "Department-wise QR Coverage", departmentSql,
                        sectionStyle, headerStyle, dataStyle, centerStyle, numberStyle, percentStyle);

                String categorySql;

                if (hasCategoryId && hasAssetCategoriesTable) {
                    categorySql =
                            "SELECT COALESCE(c.category_name, 'Uncategorized') AS group_name, "
                            + "COUNT(a.asset_id) AS total_assets, "
                            + "SUM(CASE WHEN a.qr_public_token IS NOT NULL AND TRIM(a.qr_public_token) <> '' THEN 1 ELSE 0 END) AS qr_generated "
                            + "FROM assets a "
                            + "LEFT JOIN asset_categories c ON a.category_id = c.category_id "
                            + "GROUP BY COALESCE(c.category_name, 'Uncategorized') "
                            + "ORDER BY total_assets DESC, group_name ASC";
                } else if (hasCategoryId && hasCategoriesTable) {
                    categorySql =
                            "SELECT COALESCE(c.category_name, 'Uncategorized') AS group_name, "
                            + "COUNT(a.asset_id) AS total_assets, "
                            + "SUM(CASE WHEN a.qr_public_token IS NOT NULL AND TRIM(a.qr_public_token) <> '' THEN 1 ELSE 0 END) AS qr_generated "
                            + "FROM assets a "
                            + "LEFT JOIN categories c ON a.category_id = c.category_id "
                            + "GROUP BY COALESCE(c.category_name, 'Uncategorized') "
                            + "ORDER BY total_assets DESC, group_name ASC";
                } else {
                    categorySql =
                            "SELECT COALESCE(NULLIF(asset_status, ''), 'Unclassified') AS group_name, "
                            + "COUNT(asset_id) AS total_assets, "
                            + "SUM(CASE WHEN qr_public_token IS NOT NULL AND TRIM(qr_public_token) <> '' THEN 1 ELSE 0 END) AS qr_generated "
                            + "FROM assets "
                            + "GROUP BY COALESCE(NULLIF(asset_status, ''), 'Unclassified') "
                            + "ORDER BY total_assets DESC, group_name ASC";
                }

                rowIndex = writeCoverageSection(con, sheet, rowIndex, "Category-wise QR Coverage", categorySql,
                        sectionStyle, headerStyle, dataStyle, centerStyle, numberStyle, percentStyle);

                String statusSql =
                        "SELECT COALESCE(NULLIF(asset_status, ''), 'Unknown Status') AS group_name, "
                        + "COUNT(asset_id) AS total_assets, "
                        + "SUM(CASE WHEN qr_public_token IS NOT NULL AND TRIM(qr_public_token) <> '' THEN 1 ELSE 0 END) AS qr_generated "
                        + "FROM assets "
                        + "GROUP BY COALESCE(NULLIF(asset_status, ''), 'Unknown Status') "
                        + "ORDER BY total_assets DESC, group_name ASC";

                rowIndex = writeCoverageSection(con, sheet, rowIndex, "Asset Status-wise QR Coverage", statusSql,
                        sectionStyle, headerStyle, dataStyle, centerStyle, numberStyle, percentStyle);

                String locationSql;

                if (hasLocationId && hasRailwayLocationsTable && hasLocationText) {
                    locationSql =
                            "SELECT COALESCE(rl.location_name, NULLIF(a.location, ''), 'Unspecified Location') AS group_name, "
                            + "COUNT(a.asset_id) AS total_assets, "
                            + "SUM(CASE WHEN a.qr_public_token IS NOT NULL AND TRIM(a.qr_public_token) <> '' THEN 1 ELSE 0 END) AS qr_generated "
                            + "FROM assets a "
                            + "LEFT JOIN railway_locations rl ON a.location_id = rl.location_id "
                            + "GROUP BY COALESCE(rl.location_name, NULLIF(a.location, ''), 'Unspecified Location') "
                            + "ORDER BY total_assets DESC, group_name ASC";
                } else if (hasLocationId && hasRailwayLocationsTable) {
                    locationSql =
                            "SELECT COALESCE(rl.location_name, 'Unspecified Location') AS group_name, "
                            + "COUNT(a.asset_id) AS total_assets, "
                            + "SUM(CASE WHEN a.qr_public_token IS NOT NULL AND TRIM(a.qr_public_token) <> '' THEN 1 ELSE 0 END) AS qr_generated "
                            + "FROM assets a "
                            + "LEFT JOIN railway_locations rl ON a.location_id = rl.location_id "
                            + "GROUP BY COALESCE(rl.location_name, 'Unspecified Location') "
                            + "ORDER BY total_assets DESC, group_name ASC";
                } else if (hasLocationText) {
                    locationSql =
                            "SELECT COALESCE(NULLIF(location, ''), 'Unspecified Location') AS group_name, "
                            + "COUNT(asset_id) AS total_assets, "
                            + "SUM(CASE WHEN qr_public_token IS NOT NULL AND TRIM(qr_public_token) <> '' THEN 1 ELSE 0 END) AS qr_generated "
                            + "FROM assets "
                            + "GROUP BY COALESCE(NULLIF(location, ''), 'Unspecified Location') "
                            + "ORDER BY total_assets DESC, group_name ASC";
                } else {
                    locationSql =
                            "SELECT 'Headquarters / Rail Sadan' AS group_name, "
                            + "COUNT(asset_id) AS total_assets, "
                            + "SUM(CASE WHEN qr_public_token IS NOT NULL AND TRIM(qr_public_token) <> '' THEN 1 ELSE 0 END) AS qr_generated "
                            + "FROM assets";
                }

                rowIndex = writeCoverageSection(con, sheet, rowIndex, "Section / Location-wise QR Coverage", locationSql,
                        sectionStyle, headerStyle, dataStyle, centerStyle, numberStyle, percentStyle);
            }
        }

        autoSizeColumns(sheet, 6);

        out.clear();
        out = pageContext.pushBody();

        OutputStream outputStream = response.getOutputStream();
        workbook.write(outputStream);
        outputStream.flush();

    } catch (Exception e) {
        System.err.println("QR Module DB Error: " + e.getMessage());
        response.reset();
        response.setContentType("text/plain");
        response.getWriter().write("QR Coverage Excel export failed: " + "Please contact the administrator.");
    } finally {
        workbook.close();
    }
return;
%>