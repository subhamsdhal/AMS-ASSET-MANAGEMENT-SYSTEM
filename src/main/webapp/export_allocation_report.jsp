<%@page contentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet" pageEncoding="UTF-8" trimDirectiveWhitespaces="true"%>
<%@page import="java.sql.*"%>
<%@page import="java.io.ByteArrayOutputStream"%>
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

    private boolean tableExists(Connection con, String tableName) {
        String sql = "SELECT COUNT(*) FROM information_schema.tables "
                + "WHERE table_schema = DATABASE() AND table_name = ?";

        try (PreparedStatement ps = con.prepareStatement(sql)) {
            ps.setString(1, tableName);

            try (ResultSet rs = ps.executeQuery()) {
                return rs.next() && rs.getInt(1) > 0;
            }

        } catch (Exception e) {
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
            return 0;
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
        font.setFontHeightInPoints((short) 17);
        font.setColor(white);

        XSSFCellStyle style = workbook.createCellStyle();
        style.setFont(font);
        style.setFillForegroundColor(navy);
        style.setFillPattern(FillPatternType.SOLID_FOREGROUND);
        style.setAlignment(HorizontalAlignment.CENTER);
        style.setVerticalAlignment(VerticalAlignment.CENTER);

        return style;
    }

    private XSSFCellStyle createMetaStyle(XSSFWorkbook workbook, XSSFColor fill, XSSFColor black, XSSFColor borderGrey) {
        XSSFFont font = workbook.createFont();
        font.setBold(true);
        font.setFontHeightInPoints((short) 10);
        font.setColor(black);

        XSSFCellStyle style = workbook.createCellStyle();
        style.setFont(font);
        style.setFillForegroundColor(fill);
        style.setFillPattern(FillPatternType.SOLID_FOREGROUND);
        style.setAlignment(HorizontalAlignment.CENTER);
        style.setVerticalAlignment(VerticalAlignment.CENTER);
        addBorder(style, borderGrey);

        return style;
    }

    private XSSFCellStyle createHeaderStyle(XSSFWorkbook workbook, XSSFColor blue, XSSFColor white, XSSFColor borderGrey) {
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

    private XSSFCellStyle createDateStyle(XSSFWorkbook workbook, XSSFCellStyle baseStyle) {
        XSSFCellStyle style = workbook.createCellStyle();
        style.cloneStyleFrom(baseStyle);
        style.setDataFormat(workbook.createDataFormat().getFormat("dd-mmm-yyyy"));
        return style;
    }

    private XSSFCellStyle createStatusStyle(XSSFWorkbook workbook, XSSFColor fill, XSSFColor text, XSSFColor borderGrey) {
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

    out.clear();
    out = pageContext.pushBody();

    Connection con = null;
    PreparedStatement ps = null;
    ResultSet rs = null;
    XSSFWorkbook workbook = null;

    try {
        workbook = new XSSFWorkbook();

        XSSFSheet sheet = workbook.createSheet("Allocation Report");
        sheet.setZoom(95);
        sheet.setDisplayGridlines(false);

        DefaultIndexedColorMap colorMap = new DefaultIndexedColorMap();

        XSSFColor navy = new XSSFColor(new java.awt.Color(31, 78, 121), colorMap);
        XSSFColor blue = new XSSFColor(new java.awt.Color(47, 85, 151), colorMap);
        XSSFColor softBlue = new XSSFColor(new java.awt.Color(221, 235, 247), colorMap);
        XSSFColor white = new XSSFColor(new java.awt.Color(255, 255, 255), colorMap);
        XSSFColor black = new XSSFColor(new java.awt.Color(0, 0, 0), colorMap);
        XSSFColor stripe = new XSSFColor(new java.awt.Color(248, 250, 252), colorMap);
        XSSFColor borderGrey = new XSSFColor(new java.awt.Color(191, 191, 191), colorMap);

        XSSFColor allocatedFill = new XSSFColor(new java.awt.Color(221, 235, 247), colorMap);
        XSSFColor allocatedText = new XSSFColor(new java.awt.Color(31, 78, 121), colorMap);
        XSSFColor returnedFill = new XSSFColor(new java.awt.Color(226, 239, 218), colorMap);
        XSSFColor returnedText = new XSSFColor(new java.awt.Color(0, 97, 0), colorMap);

        XSSFCellStyle titleStyle = createTitleStyle(workbook, navy, white);
        XSSFCellStyle metaStyle = createMetaStyle(workbook, softBlue, black, borderGrey);
        XSSFCellStyle headerStyle = createHeaderStyle(workbook, blue, white, borderGrey);
        XSSFCellStyle textStyle = createTextStyle(workbook, black, borderGrey);
        XSSFCellStyle alternateStyle = createAlternateStyle(workbook, textStyle, stripe);
        XSSFCellStyle dateStyle = createDateStyle(workbook, textStyle);
        XSSFCellStyle allocatedStyle = createStatusStyle(workbook, allocatedFill, allocatedText, borderGrey);
        XSSFCellStyle returnedStyle = createStatusStyle(workbook, returnedFill, returnedText, borderGrey);

        con = DBConnection.getConnection();

        boolean hasAllocation = tableExists(con, "asset_allocation");
        boolean hasAssets = tableExists(con, "assets");
        boolean hasEmployees = tableExists(con, "employees");
        boolean hasDepartments = tableExists(con, "departments");

        boolean aaId = hasAllocation && columnExists(con, "asset_allocation", "allocation_id");
        boolean aaAssetId = hasAllocation && columnExists(con, "asset_allocation", "asset_id");
        boolean aaEmpId = hasAllocation && columnExists(con, "asset_allocation", "employee_id");
        boolean aaAllocationDate = hasAllocation && columnExists(con, "asset_allocation", "allocation_date");
        boolean aaReturnDate = hasAllocation && columnExists(con, "asset_allocation", "return_date");
        boolean aaStatus = hasAllocation && columnExists(con, "asset_allocation", "allocation_status");
        boolean aaRemarks = hasAllocation && columnExists(con, "asset_allocation", "remarks");

        boolean aId = hasAssets && columnExists(con, "assets", "asset_id");
        boolean aCode = hasAssets && columnExists(con, "assets", "asset_code");
        boolean aRailwayNo = hasAssets && columnExists(con, "assets", "railway_asset_no");
        boolean aName = hasAssets && columnExists(con, "assets", "asset_name");

        boolean eId = hasEmployees && columnExists(con, "employees", "employee_id");
        boolean eCode = hasEmployees && columnExists(con, "employees", "employee_code");
        boolean eFirst = hasEmployees && columnExists(con, "employees", "employee_name");
        boolean eLast = hasEmployees && columnExists(con, "employees", "employee_name");
        boolean eFull = hasEmployees && columnExists(con, "employees", "full_name");
        boolean eName = hasEmployees && columnExists(con, "employees", "employee_name");
        boolean eDept = hasEmployees && columnExists(con, "employees", "department_id");

        boolean dId = hasDepartments && columnExists(con, "departments", "department_id");
        boolean dName = hasDepartments && columnExists(con, "departments", "department_name");

        boolean joinAssets = hasAllocation && hasAssets && aaAssetId && aId;
        boolean joinEmployees = hasAllocation && hasEmployees && aaEmpId && eId;
        boolean joinDepartments = joinEmployees && hasDepartments && eDept && dId;

        int totalAllocations = hasAllocation ? sqlInt(con, "SELECT COUNT(*) FROM asset_allocation") : 0;
        int activeAllocations = hasAllocation && aaStatus
                ? sqlInt(con, "SELECT COUNT(*) FROM asset_allocation WHERE allocation_status = 'ALLOCATED'")
                : 0;
        int returnedAllocations = hasAllocation && aaStatus
                ? sqlInt(con, "SELECT COUNT(*) FROM asset_allocation WHERE allocation_status = 'RETURNED'")
                : 0;
        int assetsCovered = hasAllocation && aaAssetId
                ? sqlInt(con, "SELECT COUNT(DISTINCT asset_id) FROM asset_allocation")
                : 0;

        String[] headers = {
            "Sl No.",
            "Allocation ID",
            "Asset Code",
            "Asset Name",
            "Employee Code",
            "Holder / Employee",
            "Department",
            "Allocation Date",
            "Return Date",
            "Status",
            "Remarks"
        };

        int lastColumn = headers.length - 1;
        int rowIndex = 0;

        Row titleRow = sheet.createRow(rowIndex++);
        titleRow.setHeightInPoints(30);
        createMergedRow(sheet, titleRow, 0, lastColumn, "INDIAN RAILWAY ASSET MANAGEMENT SYSTEM | ALLOCATION REPORT", titleStyle);

        String generatedTime = LocalDateTime.now().format(DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss"));

        Row metaRow = sheet.createRow(rowIndex++);
        metaRow.setHeightInPoints(23);
        createMergedRow(
                sheet,
                metaRow,
                0,
                lastColumn,
                "Generated By: " + username
                + " | Role: " + cleanLabel(role)
                + " | Generated On: " + generatedTime,
                metaStyle
        );

        Row kpiRow = sheet.createRow(rowIndex++);
        kpiRow.setHeightInPoints(23);
        createMergedRow(
                sheet,
                kpiRow,
                0,
                lastColumn,
                "Total Allocations: " + totalAllocations
                + " | Active: " + activeAllocations
                + " | Returned: " + returnedAllocations
                + " | Assets Covered: " + assetsCovered,
                metaStyle
        );

        int headerRowIndex = rowIndex;

        Row headerRow = sheet.createRow(rowIndex++);
        headerRow.setHeightInPoints(30);

        for (int i = 0; i < headers.length; i++) {
            Cell cell = headerRow.createCell(i);
            cell.setCellValue(headers[i]);
            cell.setCellStyle(headerStyle);
        }

        if (!hasAllocation) {
            Row row = sheet.createRow(rowIndex++);
            row.setHeightInPoints(30);
            createMergedRow(sheet, row, 0, lastColumn, "asset_allocation table not found.", textStyle);

        } else {
            String allocationIdExpr = aaId ? "CAST(aa.allocation_id AS CHAR)" : "''";

            String assetCodeExpr = joinAssets
                    ? (aCode ? "COALESCE(a.asset_code, '')" : (aRailwayNo ? "COALESCE(a.railway_asset_no, '')" : "''"))
                    : "''";

            String assetNameExpr = joinAssets && aName ? "COALESCE(a.asset_name, '')" : "''";
            String empCodeExpr = joinEmployees && eCode ? "COALESCE(e.employee_code, '')" : "''";

            String empNameExpr = "''";

            if (joinEmployees) {
                if (eFull) {
                    empNameExpr = "COALESCE(e.full_name, '')";
                } else if (eName) {
                    empNameExpr = "COALESCE(e.employee_name, '')";
                } else if (eFirst && eLast) {
                    empNameExpr = "COALESCE(e.employee_name, '')";
                } else if (eFirst) {
                    empNameExpr = "COALESCE(e.employee_name, '')";
                }
            }

            String deptExpr = joinDepartments && dName ? "COALESCE(d.department_name, '')" : "''";
            String allocationDateExpr = aaAllocationDate ? "aa.allocation_date" : "NULL";
            String returnDateExpr = aaReturnDate ? "aa.return_date" : "NULL";
            String statusExpr = aaStatus ? "COALESCE(aa.allocation_status, '')" : "''";
            String remarksExpr = aaRemarks ? "COALESCE(aa.remarks, '')" : "''";

            String sql = "SELECT "
                    + allocationIdExpr + " AS allocation_id_display, "
                    + assetCodeExpr + " AS asset_code, "
                    + assetNameExpr + " AS asset_name, "
                    + empCodeExpr + " AS employee_code, "
                    + empNameExpr + " AS employee_name, "
                    + deptExpr + " AS department_name, "
                    + allocationDateExpr + " AS allocation_date, "
                    + returnDateExpr + " AS return_date, "
                    + statusExpr + " AS allocation_status, "
                    + remarksExpr + " AS remarks "
                    + "FROM asset_allocation aa ";

            if (joinAssets) {
                sql += "LEFT JOIN assets a ON aa.asset_id = a.asset_id ";
            }

            if (joinEmployees) {
                sql += "LEFT JOIN employees e ON aa.employee_id = e.employee_id ";
            }

            if (joinDepartments) {
                sql += "LEFT JOIN departments d ON e.department_id = d.department_id ";
            }

            if (aaId) {
                sql += "ORDER BY aa.allocation_id DESC";
            }

            ps = con.prepareStatement(sql);
            rs = ps.executeQuery();

            int slNo = 1;
            int dataStartRow = rowIndex;

            while (rs.next()) {
                Row row = sheet.createRow(rowIndex++);
                row.setHeightInPoints(28);

                CellStyle rowStyle = (rowIndex % 2 == 0) ? alternateStyle : textStyle;

                int col = 0;

                numberCell(row, col++, slNo++, rowStyle);
                textCell(row, col++, rs.getString("allocation_id_display"), rowStyle);
                textCell(row, col++, rs.getString("asset_code"), rowStyle);
                textCell(row, col++, rs.getString("asset_name"), rowStyle);
                textCell(row, col++, rs.getString("employee_code"), rowStyle);
                textCell(row, col++, rs.getString("employee_name"), rowStyle);
                textCell(row, col++, rs.getString("department_name"), rowStyle);
                dateCell(row, col++, rs.getDate("allocation_date"), dateStyle, rowStyle);
                dateCell(row, col++, rs.getDate("return_date"), dateStyle, rowStyle);

                String status = rs.getString("allocation_status");
                Cell statusCell = row.createCell(col++);
                statusCell.setCellValue(cleanLabel(status));

                if ("ALLOCATED".equalsIgnoreCase(status)) {
                    statusCell.setCellStyle(allocatedStyle);
                } else if ("RETURNED".equalsIgnoreCase(status)) {
                    statusCell.setCellStyle(returnedStyle);
                } else {
                    statusCell.setCellStyle(rowStyle);
                }

                textCell(row, col++, rs.getString("remarks"), rowStyle);
            }

            if (rowIndex == dataStartRow) {
                Row row = sheet.createRow(rowIndex++);
                row.setHeightInPoints(30);
                createMergedRow(sheet, row, 0, lastColumn, "No allocation records found.", textStyle);
            }
        }

        sheet.createFreezePane(0, headerRowIndex + 1);
        sheet.setAutoFilter(new CellRangeAddress(headerRowIndex, headerRowIndex, 0, lastColumn));

        sheet.setColumnWidth(0, 3300);
        sheet.setColumnWidth(1, 4600);
        sheet.setColumnWidth(2, 5600);
        sheet.setColumnWidth(3, 8200);
        sheet.setColumnWidth(4, 5200);
        sheet.setColumnWidth(5, 8200);
        sheet.setColumnWidth(6, 7600);
        sheet.setColumnWidth(7, 5200);
        sheet.setColumnWidth(8, 5200);
        sheet.setColumnWidth(9, 5200);
        sheet.setColumnWidth(10, 12000);

        try {
            AuditDAO.log(
                    getSessionUserId(session),
                    "EXPORT",
                    "asset_allocation",
                    0,
                    "Allocation Excel report exported by " + username
            );
        } catch (Exception auditEx) {
            auditEx.printStackTrace();
        }

        ByteArrayOutputStream baos = new ByteArrayOutputStream();
        workbook.write(baos);

        response.reset();
        response.setHeader("Cache-Control", "no-cache, no-store, must-revalidate");
        response.setHeader("Pragma", "no-cache");
        response.setDateHeader("Expires", 0);
        response.setContentType("application/vnd.openxmlformats-officedocument.spreadsheetml.sheet");
        response.setHeader("Content-Disposition", "attachment; filename=\"IR_AMS_Allocation_Report.xlsx\"");
        response.setContentLength(baos.size());

        try (ServletOutputStream outputStream = response.getOutputStream()) {
            baos.writeTo(outputStream);
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