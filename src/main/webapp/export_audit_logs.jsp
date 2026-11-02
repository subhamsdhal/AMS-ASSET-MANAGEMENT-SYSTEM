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
        style.setDataFormat(workbook.createDataFormat().getFormat("dd-mmm-yyyy hh:mm"));
        style.setAlignment(HorizontalAlignment.CENTER);
        style.setVerticalAlignment(VerticalAlignment.CENTER);
        addBorder(style, borderGrey);

        return style;
    }

    private XSSFCellStyle createNumberStyle(XSSFWorkbook workbook, XSSFColor black, XSSFColor borderGrey) {
        XSSFFont font = workbook.createFont();
        font.setFontHeightInPoints((short) 10);
        font.setColor(black);

        XSSFCellStyle style = workbook.createCellStyle();
        style.setFont(font);
        style.setAlignment(HorizontalAlignment.CENTER);
        style.setVerticalAlignment(VerticalAlignment.CENTER);
        addBorder(style, borderGrey);

        return style;
    }

    private XSSFCellStyle createActionStyle(
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

    private CellStyle getActionStyle(
            String actionType,
            CellStyle exportStyle,
            CellStyle updateStyle,
            CellStyle deleteStyle,
            CellStyle createStyle,
            CellStyle blockedStyle,
            CellStyle normalStyle) {

        if (actionType == null) {
            return normalStyle;
        }

        String action = actionType.trim().toUpperCase();

        if (action.contains("EXPORT") || action.contains("REPORT")) {
            return exportStyle;
        }

        if (action.contains("UPDATE")
                || action.contains("EDIT")
                || action.contains("CHANGE")
                || action.contains("SCHEDULE")) {
            return updateStyle;
        }

        if (action.contains("DELETE")
                || action.contains("DISPOSE")
                || action.contains("REMOVE")
                || action.contains("REJECT")) {
            return deleteStyle;
        }

        if (action.contains("ADD")
                || action.contains("CREATE")
                || action.contains("INSERT")
                || action.contains("SAVE")
                || action.contains("SUBMIT")) {
            return createStyle;
        }

        if (action.contains("BLOCKED") || action.contains("DENIED")) {
            return blockedStyle;
        }

        return normalStyle;
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

    if (!("SUPER_ADMIN".equals(role) || "ADMIN".equals(role)) && !"AUDITOR".equalsIgnoreCase(role)) {
        response.sendRedirect("dashboard.jsp?access=denied");
        return;
    }

    response.reset();
    response.setContentType("application/vnd.openxmlformats-officedocument.spreadsheetml.sheet");
    response.setHeader("Content-Disposition", "attachment; filename=\"IR_AMS_Audit_Logs_Report.xlsx\"");

    out.clear();
    out = pageContext.pushBody();

    Connection con = null;
    PreparedStatement ps = null;
    ResultSet rs = null;
    XSSFWorkbook workbook = null;

    try {
        workbook = new XSSFWorkbook();

        XSSFSheet sheet = workbook.createSheet("Audit Logs");
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

        XSSFColor exportFill = new XSSFColor(new java.awt.Color(221, 235, 247), colorMap);
        XSSFColor exportText = new XSSFColor(new java.awt.Color(31, 78, 121), colorMap);

        XSSFColor updateFill = new XSSFColor(new java.awt.Color(255, 242, 204), colorMap);
        XSSFColor updateText = new XSSFColor(new java.awt.Color(156, 87, 0), colorMap);

        XSSFColor deleteFill = new XSSFColor(new java.awt.Color(252, 228, 214), colorMap);
        XSSFColor deleteText = new XSSFColor(new java.awt.Color(156, 0, 6), colorMap);

        XSSFColor createFill = new XSSFColor(new java.awt.Color(226, 239, 218), colorMap);
        XSSFColor createText = new XSSFColor(new java.awt.Color(0, 97, 0), colorMap);

        XSSFColor blockedFill = new XSSFColor(new java.awt.Color(255, 230, 204), colorMap);
        XSSFColor blockedText = new XSSFColor(new java.awt.Color(180, 83, 9), colorMap);

        XSSFCellStyle titleStyle = createTitleStyle(workbook, navy, white);
        XSSFCellStyle subtitleStyle = createSubTitleStyle(workbook, deepBlue);
        XSSFCellStyle metaStyle = createMetaStyle(workbook, greyText);
        XSSFCellStyle headerStyle = createHeaderStyle(workbook, deepBlue, white, borderGrey);
        XSSFCellStyle textStyle = createTextStyle(workbook, black, borderGrey);
        XSSFCellStyle alternateStyle = createAlternateStyle(workbook, textStyle, lightStripe);
        XSSFCellStyle dateStyle = createDateStyle(workbook, black, borderGrey);
        XSSFCellStyle numberStyle = createNumberStyle(workbook, black, borderGrey);

        XSSFCellStyle exportStyle = createActionStyle(workbook, exportFill, exportText, borderGrey);
        XSSFCellStyle updateStyle = createActionStyle(workbook, updateFill, updateText, borderGrey);
        XSSFCellStyle deleteStyle = createActionStyle(workbook, deleteFill, deleteText, borderGrey);
        XSSFCellStyle createStyle = createActionStyle(workbook, createFill, createText, borderGrey);
        XSSFCellStyle blockedStyle = createActionStyle(workbook, blockedFill, blockedText, borderGrey);

        con = DBConnection.getConnection();

        int totalLogs = 0;
        int todayLogs = 0;
        int exportLogs = 0;
        int modulesAffected = 0;
        int usersInvolved = 0;
        int blockedLogs = 0;

        String summarySql = "SELECT "
                + "COUNT(*) AS total_logs, "
                + "SUM(CASE WHEN DATE(created_at) = CURDATE() THEN 1 ELSE 0 END) AS today_logs, "
                + "SUM(CASE WHEN UPPER(action_type) LIKE '%EXPORT%' THEN 1 ELSE 0 END) AS export_logs, "
                + "SUM(CASE WHEN UPPER(action_type) LIKE '%BLOCKED%' OR UPPER(action_type) LIKE '%DENIED%' THEN 1 ELSE 0 END) AS blocked_logs, "
                + "COUNT(DISTINCT module_name) AS modules_affected, "
                + "COUNT(DISTINCT user_id) AS users_involved "
                + "FROM audit_logs";

        try (PreparedStatement summaryPs = con.prepareStatement(summarySql);
             ResultSet summaryRs = summaryPs.executeQuery()) {

            if (summaryRs.next()) {
                totalLogs = summaryRs.getInt("total_logs");
                todayLogs = summaryRs.getInt("today_logs");
                exportLogs = summaryRs.getInt("export_logs");
                blockedLogs = summaryRs.getInt("blocked_logs");
                modulesAffected = summaryRs.getInt("modules_affected");
                usersInvolved = summaryRs.getInt("users_involved");
            }
        }

        String[] headers = {
            "Sl No.",
            "Audit ID",
            "User ID",
            "Username",
            "User Role",
            "Module",
            "Action Type",
            "Record ID",
            "Action Details",
            "IP Address",
            "User Agent",
            "Created On"
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
                "Audit Logs Report - East Coast Railway / Rail Sadan, Bhubaneswar",
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
                "Total Logs: "
                + totalLogs
                + " | Today: "
                + todayLogs
                + " | Exports: "
                + exportLogs
                + " | Blocked/Denied: "
                + blockedLogs
                + " | Modules: "
                + modulesAffected
                + " | Users: "
                + usersInvolved,
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

        String sql = "SELECT "
                + "audit_id, "
                + "COALESCE(user_id, '') AS user_id, "
                + "COALESCE(username, 'System') AS username, "
                + "COALESCE(user_role, 'SYSTEM') AS user_role, "
                + "COALESCE(module_name, 'SYSTEM') AS module_name, "
                + "COALESCE(action_type, 'GENERAL_ACTION') AS action_type, "
                + "COALESCE(record_id, '') AS record_id, "
                + "COALESCE(action_details, '') AS action_details, "
                + "COALESCE(ip_address, '') AS ip_address, "
                + "COALESCE(user_agent, '') AS user_agent, "
                + "created_at "
                + "FROM audit_logs "
                + "ORDER BY created_at DESC, audit_id DESC";

        ps = con.prepareStatement(sql);
        rs = ps.executeQuery();

        int slNo = 1;
        int dataStartRow = rowIndex;

        while (rs.next()) {
            Row row = sheet.createRow(rowIndex++);
            row.setHeightInPoints(30);

            CellStyle rowTextStyle = (rowIndex % 2 == 0) ? alternateStyle : textStyle;

            int col = 0;

            createNumberCell(row, col++, slNo++, numberStyle);
            createTextCell(row, col++, "AUD-" + rs.getInt("audit_id"), rowTextStyle);
            createTextCell(row, col++, rs.getString("user_id"), rowTextStyle);
            createTextCell(row, col++, rs.getString("username"), rowTextStyle);
            createTextCell(row, col++, cleanLabel(rs.getString("user_role")), rowTextStyle);
            createTextCell(row, col++, cleanLabel(rs.getString("module_name")), rowTextStyle);

            String actionType = rs.getString("action_type");
            Cell actionCell = row.createCell(col++);
            actionCell.setCellValue(cleanLabel(actionType));
            actionCell.setCellStyle(getActionStyle(
                    actionType,
                    exportStyle,
                    updateStyle,
                    deleteStyle,
                    createStyle,
                    blockedStyle,
                    rowTextStyle
            ));

            createTextCell(row, col++, rs.getString("record_id"), rowTextStyle);
            createTextCell(row, col++, rs.getString("action_details"), rowTextStyle);
            createTextCell(row, col++, rs.getString("ip_address"), rowTextStyle);
            createTextCell(row, col++, rs.getString("user_agent"), rowTextStyle);

            Cell createdCell = row.createCell(col++);

            Timestamp createdAt = rs.getTimestamp("created_at");

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
            noRecordRow.setHeightInPoints(28);
            createMergedRow(
                    sheet,
                    noRecordRow,
                    0,
                    lastColumnIndex,
                    "No audit logs found.",
                    textStyle
            );
        }

        sheet.createFreezePane(0, headerRowIndex + 1);
        sheet.setAutoFilter(new CellRangeAddress(headerRowIndex, headerRowIndex, 0, lastColumnIndex));

        for (int i = 0; i < headers.length; i++) {
            sheet.autoSizeColumn(i);

            int width = sheet.getColumnWidth(i);

            if (width < 3800) {
                sheet.setColumnWidth(i, 3800);
            }

            if (width > 12000) {
                sheet.setColumnWidth(i, 12000);
            }
        }

        sheet.setColumnWidth(0, 3300);
        sheet.setColumnWidth(1, 4300);
        sheet.setColumnWidth(2, 4300);
        sheet.setColumnWidth(3, 5600);
        sheet.setColumnWidth(4, 5600);
        sheet.setColumnWidth(5, 7200);
        sheet.setColumnWidth(6, 7200);
        sheet.setColumnWidth(7, 4300);
        sheet.setColumnWidth(8, 16000);
        sheet.setColumnWidth(9, 6000);
        sheet.setColumnWidth(10, 14000);
        sheet.setColumnWidth(11, 7600);

        try {
            int auditUserId = getSessionUserId(session);

            AuditDAO.log(
                    auditUserId,
                    "EXPORT",
                    "audit_logs",
                    0,
                    "Audit logs Excel report exported by " + username
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