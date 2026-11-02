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

    private CellStyle getRequestStatusStyle(String status, CellStyle pendingStyle, CellStyle approvedStyle, CellStyle rejectedStyle, CellStyle fulfilledStyle, CellStyle textStyle) {
        if (status == null) {
            return textStyle;
        }

        String s = status.trim().toUpperCase();

        if (s.contains("PENDING")) {
            return pendingStyle;
        }

        if (s.contains("APPROVED")) {
            return approvedStyle;
        }

        if (s.contains("REJECTED")) {
            return rejectedStyle;
        }

        if (s.contains("FULFILLED") || s.contains("COMPLETED")) {
            return fulfilledStyle;
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
    response.setHeader("Content-Disposition", "attachment; filename=\"IR_AMS_Requests_Report.xlsx\"");

    out.clear();
    out = pageContext.pushBody();

    Connection con = null;
    PreparedStatement ps = null;
    ResultSet rs = null;
    XSSFWorkbook workbook = null;

    try {
        workbook = new XSSFWorkbook();

        XSSFSheet sheet = workbook.createSheet("Requests Report");
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

        XSSFColor pendingFill = new XSSFColor(new java.awt.Color(255, 242, 204), colorMap);
        XSSFColor pendingText = new XSSFColor(new java.awt.Color(156, 87, 0), colorMap);
        XSSFColor approvedFill = new XSSFColor(new java.awt.Color(221, 235, 247), colorMap);
        XSSFColor approvedText = new XSSFColor(new java.awt.Color(31, 78, 121), colorMap);
        XSSFColor rejectedFill = new XSSFColor(new java.awt.Color(252, 228, 214), colorMap);
        XSSFColor rejectedText = new XSSFColor(new java.awt.Color(156, 0, 6), colorMap);
        XSSFColor fulfilledFill = new XSSFColor(new java.awt.Color(226, 239, 218), colorMap);
        XSSFColor fulfilledText = new XSSFColor(new java.awt.Color(0, 97, 0), colorMap);

        XSSFCellStyle titleStyle = createTitleStyle(workbook, navy, white);
        XSSFCellStyle subtitleStyle = createSubTitleStyle(workbook, deepBlue);
        XSSFCellStyle metaStyle = createMetaStyle(workbook, greyText);
        XSSFCellStyle headerStyle = createHeaderStyle(workbook, deepBlue, white, borderGrey);
        XSSFCellStyle textStyle = createTextStyle(workbook, black, borderGrey);
        XSSFCellStyle alternateStyle = createAlternateStyle(workbook, textStyle, lightStripe);
        XSSFCellStyle dateStyle = createDateStyle(workbook, black, borderGrey);

        XSSFCellStyle pendingStyle = createStatusStyle(workbook, pendingFill, pendingText, borderGrey);
        XSSFCellStyle approvedStyle = createStatusStyle(workbook, approvedFill, approvedText, borderGrey);
        XSSFCellStyle rejectedStyle = createStatusStyle(workbook, rejectedFill, rejectedText, borderGrey);
        XSSFCellStyle fulfilledStyle = createStatusStyle(workbook, fulfilledFill, fulfilledText, borderGrey);

        con = DBConnection.getConnection();

        boolean hasRequestsTable = tableExists(con, "asset_requests");
        boolean hasEmployeesTable = tableExists(con, "employees");
        boolean hasDepartmentTable = tableExists(con, "departments");
        boolean hasCategoryTable = tableExists(con, "asset_categories");
        boolean hasUsersTable = tableExists(con, "users");

        boolean rqHasRequestId = hasRequestsTable && columnExists(con, "asset_requests", "request_id");
        boolean rqHasEmployeeId = hasRequestsTable && columnExists(con, "asset_requests", "employee_id");
        boolean rqHasCategoryId = hasRequestsTable && columnExists(con, "asset_requests", "category_id");
        boolean rqHasRequestDate = hasRequestsTable && columnExists(con, "asset_requests", "request_date");
        boolean rqHasStatus = hasRequestsTable && columnExists(con, "asset_requests", "request_status");
        boolean rqHasApprovedBy = hasRequestsTable && columnExists(con, "asset_requests", "approved_by");
        boolean rqHasRemarks = hasRequestsTable && columnExists(con, "asset_requests", "remarks");
        boolean rqHasCreatedAt = hasRequestsTable && columnExists(con, "asset_requests", "created_at");

        boolean eHasEmployeeId = hasEmployeesTable && columnExists(con, "employees", "employee_id");
        boolean eHasEmployeeCode = hasEmployeesTable && columnExists(con, "employees", "employee_code");
        boolean eHasFullName = hasEmployeesTable && columnExists(con, "employees", "full_name");
        boolean eHasEmployeeName = hasEmployeesTable && columnExists(con, "employees", "employee_name");
        boolean eHasName = hasEmployeesTable && columnExists(con, "employees", "name");
        boolean eHasDepartmentId = hasEmployeesTable && columnExists(con, "employees", "department_id");

        boolean dHasDepartmentId = hasDepartmentTable && columnExists(con, "departments", "department_id");
        boolean dHasDepartmentName = hasDepartmentTable && columnExists(con, "departments", "department_name");

        boolean cHasCategoryId = hasCategoryTable && columnExists(con, "asset_categories", "category_id");
        boolean cHasCategoryName = hasCategoryTable && columnExists(con, "asset_categories", "category_name");

        boolean uHasUserId = hasUsersTable && columnExists(con, "users", "user_id");
        boolean uHasUsername = hasUsersTable && columnExists(con, "users", "username");

        boolean joinEmployees = hasRequestsTable && hasEmployeesTable && rqHasEmployeeId && eHasEmployeeId;
        boolean joinDepartment = joinEmployees && hasDepartmentTable && eHasDepartmentId && dHasDepartmentId;
        boolean joinCategory = hasRequestsTable && hasCategoryTable && rqHasCategoryId && cHasCategoryId;
        boolean joinUsers = hasRequestsTable && hasUsersTable && rqHasApprovedBy && uHasUserId;

        int totalRequests = hasRequestsTable ? sqlInt(con, "SELECT COUNT(*) FROM asset_requests") : 0;
        int pendingRequests = hasRequestsTable && rqHasStatus ? sqlInt(con, "SELECT COUNT(*) FROM asset_requests WHERE request_status = 'PENDING'") : 0;
        int approvedRequests = hasRequestsTable && rqHasStatus ? sqlInt(con, "SELECT COUNT(*) FROM asset_requests WHERE request_status = 'APPROVED'") : 0;
        int rejectedRequests = hasRequestsTable && rqHasStatus ? sqlInt(con, "SELECT COUNT(*) FROM asset_requests WHERE request_status = 'REJECTED'") : 0;
        int fulfilledRequests = hasRequestsTable && rqHasStatus ? sqlInt(con, "SELECT COUNT(*) FROM asset_requests WHERE request_status = 'FULFILLED'") : 0;

        String[] headers = {
            "Sl No.",
            "Request ID",
            "Requested By",
            "Employee Code",
            "Department",
            "Requested Category",
            "Request Date",
            "Request Status",
            "Approved By",
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
        createMergedRow(sheet, subtitleRow, 0, lastColumnIndex, "Asset Request Report - East Coast Railway / Rail Sadan, Bhubaneswar", subtitleStyle);

        String generatedTime = LocalDateTime.now().format(DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss"));

        Row generatedRow = sheet.createRow(rowIndex++);
        generatedRow.setHeightInPoints(23);
        createMergedRow(sheet, generatedRow, 0, lastColumnIndex,
                "Generated By: " + username + " | Role: " + cleanLabel(role) + " | Generated On: " + generatedTime,
                metaStyle);

        Row kpiRow = sheet.createRow(rowIndex++);
        kpiRow.setHeightInPoints(23);
        createMergedRow(sheet, kpiRow, 0, lastColumnIndex,
                "Total Requests: " + totalRequests
                + " | Pending: " + pendingRequests
                + " | Approved: " + approvedRequests
                + " | Rejected: " + rejectedRequests
                + " | Fulfilled: " + fulfilledRequests,
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

        if (!hasRequestsTable) {
            Row noTableRow = sheet.createRow(rowIndex++);
            noTableRow.setHeightInPoints(30);
            createMergedRow(sheet, noTableRow, 0, lastColumnIndex,
                    "asset_requests table was not found in the current database.",
                    textStyle);

        } else {
            String requestIdExpr = rqHasRequestId ? "CAST(rq.request_id AS CHAR)" : "''";

            String employeeNameExpr = "''";
            if (joinEmployees) {
                if (eHasFullName) {
                    employeeNameExpr = "COALESCE(e.full_name, '')";
                } else if (eHasEmployeeName) {
                    employeeNameExpr = "COALESCE(e.employee_name, '')";
                } else if (eHasName) {
                    employeeNameExpr = "COALESCE(e.name, '')";
                } else if (eHasEmployeeCode) {
                    employeeNameExpr = "COALESCE(e.employee_code, '')";
                }
            }

            String employeeCodeExpr = joinEmployees && eHasEmployeeCode ? "COALESCE(e.employee_code, '')" : "''";
            String departmentExpr = joinDepartment && dHasDepartmentName ? "COALESCE(d.department_name, '')" : "''";
            String categoryExpr = joinCategory && cHasCategoryName ? "COALESCE(c.category_name, '')" : "''";
            String requestDateExpr = rqHasRequestDate ? "rq.request_date" : "NULL";
            String statusExpr = rqHasStatus ? "COALESCE(rq.request_status, '')" : "''";
            String approvedByExpr = joinUsers && uHasUsername
                    ? "COALESCE(u.username, CAST(rq.approved_by AS CHAR), '')"
                    : (rqHasApprovedBy ? "COALESCE(CAST(rq.approved_by AS CHAR), '')" : "''");
            String remarksExpr = rqHasRemarks ? "COALESCE(rq.remarks, '')" : "''";
            String createdAtExpr = rqHasCreatedAt ? "rq.created_at" : "NULL";

            String sql = "SELECT "
                    + requestIdExpr + " AS request_id_display, "
                    + employeeNameExpr + " AS employee_name, "
                    + employeeCodeExpr + " AS employee_code, "
                    + departmentExpr + " AS department_name, "
                    + categoryExpr + " AS category_name, "
                    + requestDateExpr + " AS request_date, "
                    + statusExpr + " AS request_status, "
                    + approvedByExpr + " AS approved_by_display, "
                    + remarksExpr + " AS remarks, "
                    + createdAtExpr + " AS created_at "
                    + "FROM asset_requests rq ";

            if (joinEmployees) {
                sql += "LEFT JOIN employees e ON rq.employee_id = e.employee_id ";
            }

            if (joinDepartment) {
                sql += "LEFT JOIN departments d ON e.department_id = d.department_id ";
            }

            if (joinCategory) {
                sql += "LEFT JOIN asset_categories c ON rq.category_id = c.category_id ";
            }

            if (joinUsers) {
                sql += "LEFT JOIN users u ON rq.approved_by = u.user_id ";
            }

            if (rqHasRequestDate) {
                sql += "ORDER BY rq.request_date DESC";
            } else if (rqHasRequestId) {
                sql += "ORDER BY rq.request_id DESC";
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
                createTextCell(row, col++, rs.getString("request_id_display"), rowTextStyle);
                createTextCell(row, col++, rs.getString("employee_name"), rowTextStyle);
                createTextCell(row, col++, rs.getString("employee_code"), rowTextStyle);
                createTextCell(row, col++, cleanLabel(rs.getString("department_name")), rowTextStyle);
                createTextCell(row, col++, cleanLabel(rs.getString("category_name")), rowTextStyle);
                createDateCell(row, col++, rs.getDate("request_date"), dateStyle, rowTextStyle);

                String status = rs.getString("request_status");
                Cell statusCell = row.createCell(col++);
                statusCell.setCellValue(cleanLabel(status));
                statusCell.setCellStyle(getRequestStatusStyle(status, pendingStyle, approvedStyle, rejectedStyle, fulfilledStyle, rowTextStyle));

                createTextCell(row, col++, rs.getString("approved_by_display"), rowTextStyle);
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
                createMergedRow(sheet, noRecordRow, 0, lastColumnIndex, "No request records found.", textStyle);
            }
        }

        sheet.createFreezePane(0, headerRowIndex + 1);
        sheet.setAutoFilter(new CellRangeAddress(headerRowIndex, headerRowIndex, 0, lastColumnIndex));

        sheet.setColumnWidth(0, 3300);
        sheet.setColumnWidth(1, 4300);
        sheet.setColumnWidth(2, 7200);
        sheet.setColumnWidth(3, 5200);
        sheet.setColumnWidth(4, 6200);
        sheet.setColumnWidth(5, 6200);
        sheet.setColumnWidth(6, 5200);
        sheet.setColumnWidth(7, 5600);
        sheet.setColumnWidth(8, 5200);
        sheet.setColumnWidth(9, 12000);
        sheet.setColumnWidth(10, 6200);

        try {
            int auditUserId = getSessionUserId(session);

            AuditDAO.log(
                    auditUserId,
                    "EXPORT",
                    "asset_requests",
                    0,
                    "Asset request Excel report exported by " + username
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