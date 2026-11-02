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

    private XSSFCellStyle createConditionStyle(XSSFWorkbook workbook, XSSFColor fillColor, XSSFColor textColor, XSSFColor borderGrey) {
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

    private CellStyle getConditionStyle(String condition, CellStyle goodStyle, CellStyle damagedStyle, CellStyle repairStyle, CellStyle textStyle) {
        if (condition == null) {
            return textStyle;
        }

        String c = condition.trim().toUpperCase();

        if (c.contains("GOOD")) {
            return goodStyle;
        }

        if (c.contains("DAMAGED")) {
            return damagedStyle;
        }

        if (c.contains("REPAIR") || c.contains("NEEDS")) {
            return repairStyle;
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
    response.setHeader("Content-Disposition", "attachment; filename=\"IR_AMS_Returns_Report.xlsx\"");

    out.clear();
    out = pageContext.pushBody();

    Connection con = null;
    PreparedStatement ps = null;
    ResultSet rs = null;
    XSSFWorkbook workbook = null;

    try {
        workbook = new XSSFWorkbook();

        XSSFSheet sheet = workbook.createSheet("Returns Report");
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

        XSSFColor goodFill = new XSSFColor(new java.awt.Color(226, 239, 218), colorMap);
        XSSFColor goodText = new XSSFColor(new java.awt.Color(0, 97, 0), colorMap);
        XSSFColor damagedFill = new XSSFColor(new java.awt.Color(252, 228, 214), colorMap);
        XSSFColor damagedText = new XSSFColor(new java.awt.Color(156, 0, 6), colorMap);
        XSSFColor repairFill = new XSSFColor(new java.awt.Color(255, 242, 204), colorMap);
        XSSFColor repairText = new XSSFColor(new java.awt.Color(156, 87, 0), colorMap);

        XSSFCellStyle titleStyle = createTitleStyle(workbook, navy, white);
        XSSFCellStyle subtitleStyle = createSubTitleStyle(workbook, deepBlue);
        XSSFCellStyle metaStyle = createMetaStyle(workbook, greyText);
        XSSFCellStyle headerStyle = createHeaderStyle(workbook, deepBlue, white, borderGrey);
        XSSFCellStyle textStyle = createTextStyle(workbook, black, borderGrey);
        XSSFCellStyle alternateStyle = createAlternateStyle(workbook, textStyle, lightStripe);
        XSSFCellStyle dateStyle = createDateStyle(workbook, black, borderGrey);

        XSSFCellStyle goodStyle = createConditionStyle(workbook, goodFill, goodText, borderGrey);
        XSSFCellStyle damagedStyle = createConditionStyle(workbook, damagedFill, damagedText, borderGrey);
        XSSFCellStyle repairStyle = createConditionStyle(workbook, repairFill, repairText, borderGrey);

        con = DBConnection.getConnection();

        boolean hasReturnsTable = tableExists(con, "asset_returns");
        boolean hasAllocationTable = tableExists(con, "asset_allocation");
        boolean hasAssetsTable = tableExists(con, "assets");
        boolean hasEmployeesTable = tableExists(con, "employees");
        boolean hasDepartmentTable = tableExists(con, "departments");
        boolean hasUsersTable = tableExists(con, "users");

        boolean rHasReturnId = hasReturnsTable && columnExists(con, "asset_returns", "return_id");
        boolean rHasAllocationId = hasReturnsTable && columnExists(con, "asset_returns", "allocation_id");
        boolean rHasReturnDate = hasReturnsTable && columnExists(con, "asset_returns", "return_date");
        boolean rHasCondition = hasReturnsTable && columnExists(con, "asset_returns", "return_condition");
        boolean rHasReceivedBy = hasReturnsTable && columnExists(con, "asset_returns", "received_by");
        boolean rHasRemarks = hasReturnsTable && columnExists(con, "asset_returns", "remarks");
        boolean rHasCreatedAt = hasReturnsTable && columnExists(con, "asset_returns", "created_at");

        boolean alHasAllocationId = hasAllocationTable && columnExists(con, "asset_allocation", "allocation_id");
        boolean alHasAssetId = hasAllocationTable && columnExists(con, "asset_allocation", "asset_id");
        boolean alHasEmployeeId = hasAllocationTable && columnExists(con, "asset_allocation", "employee_id");
        boolean alHasAllocationDate = hasAllocationTable && columnExists(con, "asset_allocation", "allocation_date");

        boolean aHasAssetId = hasAssetsTable && columnExists(con, "assets", "asset_id");
        boolean aHasAssetCode = hasAssetsTable && columnExists(con, "assets", "asset_code");
        boolean aHasRailwayAssetNo = hasAssetsTable && columnExists(con, "assets", "railway_asset_no");
        boolean aHasAssetName = hasAssetsTable && columnExists(con, "assets", "asset_name");

        boolean eHasEmployeeId = hasEmployeesTable && columnExists(con, "employees", "employee_id");
        boolean eHasEmployeeCode = hasEmployeesTable && columnExists(con, "employees", "employee_code");
        boolean eHasFullName = hasEmployeesTable && columnExists(con, "employees", "full_name");
        boolean eHasEmployeeName = hasEmployeesTable && columnExists(con, "employees", "employee_name");
        boolean eHasName = hasEmployeesTable && columnExists(con, "employees", "name");
        boolean eHasDepartmentId = hasEmployeesTable && columnExists(con, "employees", "department_id");

        boolean dHasDepartmentId = hasDepartmentTable && columnExists(con, "departments", "department_id");
        boolean dHasDepartmentName = hasDepartmentTable && columnExists(con, "departments", "department_name");

        boolean uHasUserId = hasUsersTable && columnExists(con, "users", "user_id");
        boolean uHasUsername = hasUsersTable && columnExists(con, "users", "username");

        boolean joinAllocation = hasReturnsTable && hasAllocationTable && rHasAllocationId && alHasAllocationId;
        boolean joinAssets = joinAllocation && hasAssetsTable && alHasAssetId && aHasAssetId;
        boolean joinEmployees = joinAllocation && hasEmployeesTable && alHasEmployeeId && eHasEmployeeId;
        boolean joinDepartment = joinEmployees && hasDepartmentTable && eHasDepartmentId && dHasDepartmentId;
        boolean joinUsers = hasReturnsTable && hasUsersTable && rHasReceivedBy && uHasUserId;

        int totalReturns = hasReturnsTable ? sqlInt(con, "SELECT COUNT(*) FROM asset_returns") : 0;
        int goodReturns = hasReturnsTable && rHasCondition ? sqlInt(con, "SELECT COUNT(*) FROM asset_returns WHERE return_condition = 'GOOD'") : 0;
        int damagedReturns = hasReturnsTable && rHasCondition ? sqlInt(con, "SELECT COUNT(*) FROM asset_returns WHERE return_condition = 'DAMAGED'") : 0;
        int repairReturns = hasReturnsTable && rHasCondition ? sqlInt(con, "SELECT COUNT(*) FROM asset_returns WHERE return_condition IN ('NEEDS_REPAIR','UNDER_REPAIR')") : 0;
        int currentYearReturns = hasReturnsTable && rHasReturnDate ? sqlInt(con, "SELECT COUNT(*) FROM asset_returns WHERE YEAR(return_date) = YEAR(CURDATE())") : 0;

        String[] headers = {
            "Sl No.",
            "Return ID",
            "Allocation ID",
            "Asset Code",
            "Asset Name",
            "Holder / Employee",
            "Department",
            "Allocation Date",
            "Return Date",
            "Return Condition",
            "Received By",
            "Remarks",
            "Created On"
        };

        int lastColumnIndex = headers.length - 1;
        int rowIndex = 0;

        Row titleRow = sheet.createRow(rowIndex++);
        titleRow.setHeightInPoints(32);
        createMergedRow(sheet, titleRow, 0, lastColumnIndex, "INDIAN RAILWAY ASSET MANAGEMENT SYSTEM", titleStyle);

        Row subtitleRow = sheet.createRow(rowIndex++);
        subtitleRow.setHeightInPoints(24);
        createMergedRow(sheet, subtitleRow, 0, lastColumnIndex, "Asset Return Report - East Coast Railway / Rail Sadan, Bhubaneswar", subtitleStyle);

        String generatedTime = LocalDateTime.now().format(DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss"));

        Row generatedRow = sheet.createRow(rowIndex++);
        generatedRow.setHeightInPoints(23);
        createMergedRow(sheet, generatedRow, 0, lastColumnIndex,
                "Generated By: " + username + " | Role: " + cleanLabel(role) + " | Generated On: " + generatedTime,
                metaStyle);

        Row kpiRow = sheet.createRow(rowIndex++);
        kpiRow.setHeightInPoints(23);
        createMergedRow(sheet, kpiRow, 0, lastColumnIndex,
                "Total Returns: " + totalReturns
                + " | Current Year: " + currentYearReturns
                + " | Good: " + goodReturns
                + " | Damaged: " + damagedReturns
                + " | Needs Repair: " + repairReturns,
                metaStyle);

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

        if (!hasReturnsTable) {
            Row noTableRow = sheet.createRow(rowIndex++);
            noTableRow.setHeightInPoints(30);
            createMergedRow(sheet, noTableRow, 0, lastColumnIndex,
                    "asset_returns table was not found in the current database.",
                    textStyle);

        } else {
            String returnIdExpr = rHasReturnId ? "CAST(r.return_id AS CHAR)" : "''";
            String allocationIdExpr = rHasAllocationId ? "CAST(r.allocation_id AS CHAR)" : "''";
            String assetCodeExpr = joinAssets
                    ? (aHasAssetCode ? "COALESCE(a.asset_code, '')" : (aHasRailwayAssetNo ? "COALESCE(a.railway_asset_no, '')" : "''"))
                    : "''";
            String assetNameExpr = joinAssets && aHasAssetName ? "COALESCE(a.asset_name, '')" : "''";

            String holderExpr = "''";
            if (joinEmployees) {
                if (eHasFullName) {
                    holderExpr = "COALESCE(e.full_name, '')";
                } else if (eHasEmployeeName) {
                    holderExpr = "COALESCE(e.employee_name, '')";
                } else if (eHasName) {
                    holderExpr = "COALESCE(e.name, '')";
                } else if (eHasEmployeeCode) {
                    holderExpr = "COALESCE(e.employee_code, '')";
                }
            }

            String departmentExpr = joinDepartment && dHasDepartmentName ? "COALESCE(d.department_name, '')" : "''";
            String allocationDateExpr = joinAllocation && alHasAllocationDate ? "al.allocation_date" : "NULL";
            String returnDateExpr = rHasReturnDate ? "r.return_date" : "NULL";
            String conditionExpr = rHasCondition ? "COALESCE(r.return_condition, '')" : "''";
            String receivedByExpr = joinUsers && uHasUsername
                    ? "COALESCE(u.username, CAST(r.received_by AS CHAR), '')"
                    : (rHasReceivedBy ? "COALESCE(CAST(r.received_by AS CHAR), '')" : "''");
            String remarksExpr = rHasRemarks ? "COALESCE(r.remarks, '')" : "''";
            String createdAtExpr = rHasCreatedAt ? "r.created_at" : "NULL";

            String sql = "SELECT "
                    + returnIdExpr + " AS return_id_display, "
                    + allocationIdExpr + " AS allocation_id_display, "
                    + assetCodeExpr + " AS asset_code, "
                    + assetNameExpr + " AS asset_name, "
                    + holderExpr + " AS holder_name, "
                    + departmentExpr + " AS department_name, "
                    + allocationDateExpr + " AS allocation_date, "
                    + returnDateExpr + " AS return_date, "
                    + conditionExpr + " AS return_condition, "
                    + receivedByExpr + " AS received_by_display, "
                    + remarksExpr + " AS remarks, "
                    + createdAtExpr + " AS created_at "
                    + "FROM asset_returns r ";

            if (joinAllocation) {
                sql += "LEFT JOIN asset_allocation al ON r.allocation_id = al.allocation_id ";
            }

            if (joinAssets) {
                sql += "LEFT JOIN assets a ON al.asset_id = a.asset_id ";
            }

            if (joinEmployees) {
                sql += "LEFT JOIN employees e ON al.employee_id = e.employee_id ";
            }

            if (joinDepartment) {
                sql += "LEFT JOIN departments d ON e.department_id = d.department_id ";
            }

            if (joinUsers) {
                sql += "LEFT JOIN users u ON r.received_by = u.user_id ";
            }

            if (rHasReturnDate) {
                sql += "ORDER BY r.return_date DESC";
            } else if (rHasReturnId) {
                sql += "ORDER BY r.return_id DESC";
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
                createTextCell(row, col++, rs.getString("return_id_display"), rowTextStyle);
                createTextCell(row, col++, rs.getString("allocation_id_display"), rowTextStyle);
                createTextCell(row, col++, rs.getString("asset_code"), rowTextStyle);
                createTextCell(row, col++, rs.getString("asset_name"), rowTextStyle);
                createTextCell(row, col++, rs.getString("holder_name"), rowTextStyle);
                createTextCell(row, col++, cleanLabel(rs.getString("department_name")), rowTextStyle);
                createDateCell(row, col++, rs.getDate("allocation_date"), dateStyle, rowTextStyle);
                createDateCell(row, col++, rs.getDate("return_date"), dateStyle, rowTextStyle);

                String condition = rs.getString("return_condition");
                Cell conditionCell = row.createCell(col++);
                conditionCell.setCellValue(cleanLabel(condition));
                conditionCell.setCellStyle(getConditionStyle(condition, goodStyle, damagedStyle, repairStyle, rowTextStyle));

                createTextCell(row, col++, rs.getString("received_by_display"), rowTextStyle);
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
                createMergedRow(sheet, noRecordRow, 0, lastColumnIndex, "No return records found.", textStyle);
            }
        }

        sheet.createFreezePane(0, headerRowIndex + 1);
        sheet.setAutoFilter(new CellRangeAddress(headerRowIndex, headerRowIndex, 0, lastColumnIndex));

        sheet.setColumnWidth(0, 3300);
        sheet.setColumnWidth(1, 4300);
        sheet.setColumnWidth(2, 4600);
        sheet.setColumnWidth(3, 5600);
        sheet.setColumnWidth(4, 7200);
        sheet.setColumnWidth(5, 7200);
        sheet.setColumnWidth(6, 6200);
        sheet.setColumnWidth(7, 5200);
        sheet.setColumnWidth(8, 5200);
        sheet.setColumnWidth(9, 5600);
        sheet.setColumnWidth(10, 5200);
        sheet.setColumnWidth(11, 12000);
        sheet.setColumnWidth(12, 6200);

        try {
            int auditUserId = getSessionUserId(session);

            AuditDAO.log(
                    auditUserId,
                    "EXPORT",
                    "asset_returns",
                    0,
                    "Asset return Excel report exported by " + username
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