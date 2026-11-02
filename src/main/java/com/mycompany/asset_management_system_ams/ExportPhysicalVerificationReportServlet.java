package com.mycompany.asset_management_system_ams;

import java.io.IOException;
import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.util.ArrayList;
import java.util.List;

import jakarta.servlet.ServletException;
import jakarta.servlet.ServletOutputStream;
import jakarta.servlet.annotation.WebServlet;
import jakarta.servlet.http.HttpServlet;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import jakarta.servlet.http.HttpSession;

import org.apache.poi.ss.usermodel.BorderStyle;
import org.apache.poi.ss.usermodel.Cell;
import org.apache.poi.ss.usermodel.CellStyle;
import org.apache.poi.ss.usermodel.FillPatternType;
import org.apache.poi.ss.usermodel.Font;
import org.apache.poi.ss.usermodel.HorizontalAlignment;
import org.apache.poi.ss.usermodel.IndexedColors;
import org.apache.poi.ss.usermodel.Row;
import org.apache.poi.ss.usermodel.Sheet;
import org.apache.poi.ss.usermodel.VerticalAlignment;
import org.apache.poi.ss.usermodel.Workbook;
import org.apache.poi.ss.usermodel.DataFormat;
import org.apache.poi.ss.util.CellRangeAddress;
import org.apache.poi.xssf.usermodel.XSSFWorkbook;

@WebServlet(name = "ExportPhysicalVerificationReportServlet", urlPatterns = {"/ExportPhysicalVerificationReportServlet"})
public class ExportPhysicalVerificationReportServlet extends HttpServlet {

    @Override
    protected void doGet(HttpServletRequest request, HttpServletResponse response)
            throws ServletException, IOException {

        try {
            HttpSession session = request.getSession(false);

            if (session == null
                    || session.getAttribute("username") == null
                    || session.getAttribute("role") == null) {
                response.sendRedirect("login.jsp");
                return;
            }

            String username = String.valueOf(session.getAttribute("username"));
            String role = String.valueOf(session.getAttribute("role"));
            // Default of 0 (not 1) on a missing session attribute - see the same
            // fix applied across the Asset Requests module for why 1 is unsafe here.
            int userId = getSessionInt(session, "user_id", 0);

            if (!canExport(role)) {
                response.sendRedirect("reports.jsp?access=denied");
                return;
            }

            String statusFilter = clean(request.getParameter("status"));
            String fromDate = clean(request.getParameter("from"));
            String toDate = clean(request.getParameter("to"));

            if (statusFilter.isEmpty()) {
                statusFilter = "ALL";
            }

            try (Connection con = DBConnection.getConnection();
                 Workbook workbook = new XSSFWorkbook()) {

                Sheet sheet = workbook.createSheet("Physical Verification");

                String[] headers = {
                    "Sl No.",
                    "Verification ID",
                    "Asset Code",
                    "Railway Asset No.",
                    "Asset Name",
                    "Category",
                    "Asset Status",
                    "Service Status",
                    "Supplier",
                    "Verification Status",
                    "Review Status",
                    "System Location",
                    "Actual Location",
                    "Actual Holder",
                    "Officer",
                    "Officer Department",
                    "Verified By",
                    "Verified On",
                    "Remarks"
                };

                int lastColumnIndex = headers.length - 1;

                CellStyle titleStyle = createTitleStyle(workbook);
                CellStyle subtitleStyle = createSubtitleStyle(workbook);
                CellStyle filterStyle = createFilterStyle(workbook);
                CellStyle headerStyle = createHeaderStyle(workbook);
                CellStyle textStyle = createTextStyle(workbook);
                CellStyle numberStyle = createNumberStyle(workbook);
                CellStyle dateStyle = createDateStyle(workbook, workbook.createDataFormat());
                CellStyle verifiedStyle = createStatusStyle(workbook, IndexedColors.LIGHT_GREEN);
                CellStyle warningStyle = createStatusStyle(workbook, IndexedColors.LIGHT_YELLOW);
                CellStyle dangerStyle = createStatusStyle(workbook, IndexedColors.ROSE);
                CellStyle neutralStyle = createStatusStyle(workbook, IndexedColors.LIGHT_CORNFLOWER_BLUE);

                int rowIndex = 0;

                Row titleRow = sheet.createRow(rowIndex++);
                titleRow.setHeightInPoints(34);
                createMergedRow(
                        sheet,
                        titleRow,
                        0,
                        lastColumnIndex,
                        "Indian Railway Asset Management System",
                        titleStyle
                );

                Row subtitleRow = sheet.createRow(rowIndex++);
                subtitleRow.setHeightInPoints(25);
                createMergedRow(
                        sheet,
                        subtitleRow,
                        0,
                        lastColumnIndex,
                        "Physical Verification Report - East Coast Railway / Rail Sadan, Bhubaneswar",
                        subtitleStyle
                );

                Row filterRow = sheet.createRow(rowIndex++);
                filterRow.setHeightInPoints(24);
                createMergedRow(
                        sheet,
                        filterRow,
                        0,
                        lastColumnIndex,
                        "Generated By: " + username
                        + " | Role: " + formatRole(role)
                        + " | Status: " + statusFilter
                        + " | From: " + (fromDate.isEmpty() ? "All" : fromDate)
                        + " | To: " + (toDate.isEmpty() ? "All" : toDate),
                        filterStyle
                );

                Row blankRow = sheet.createRow(rowIndex++);
                blankRow.setHeightInPoints(8);

                Row headerRow = sheet.createRow(rowIndex++);
                headerRow.setHeightInPoints(32);

                for (int i = 0; i < headers.length; i++) {
                    Cell cell = headerRow.createCell(i);
                    cell.setCellValue(headers[i]);
                    cell.setCellStyle(headerStyle);
                }

                sheet.createFreezePane(0, 5);

                if (!tableExists(con, "asset_physical_verification")) {
                    Row row = sheet.createRow(rowIndex++);
                    createMergedRow(
                            sheet,
                            row,
                            0,
                            lastColumnIndex,
                            "Physical verification table not found.",
                            textStyle
                    );
                } else {
                    rowIndex = fillReportRows(
                            con,
                            sheet,
                            rowIndex,
                            statusFilter,
                            fromDate,
                            toDate,
                            numberStyle,
                            textStyle,
                            dateStyle,
                            verifiedStyle,
                            warningStyle,
                            dangerStyle,
                            neutralStyle,
                            lastColumnIndex
                    );
                }

                for (int i = 0; i < headers.length; i++) {
                    sheet.autoSizeColumn(i);

                    int width = sheet.getColumnWidth(i);

                    if (width < 3800) {
                        sheet.setColumnWidth(i, 3800);
                    }

                    if (width > 11000) {
                        sheet.setColumnWidth(i, 11000);
                    }
                }

                sheet.setColumnWidth(0, 3300);
                sheet.setColumnWidth(1, 4300);
                sheet.setColumnWidth(2, 5600);
                sheet.setColumnWidth(4, 8500);
                sheet.setColumnWidth(8, 7000);
                sheet.setColumnWidth(9, 5600);
                sheet.setColumnWidth(10, 5200);
                sheet.setColumnWidth(11, 8500);
                sheet.setColumnWidth(12, 8500);
                sheet.setColumnWidth(13, 7600);
                sheet.setColumnWidth(14, 7600);
                sheet.setColumnWidth(15, 7600);
                sheet.setColumnWidth(16, 5200);
                sheet.setColumnWidth(17, 7200);   // Verified On date column fixed
                sheet.setColumnWidth(18, 12000);

                safeAuditLog(
                        userId,
                        "EXPORT",
                        "asset_physical_verification",
                        0,
                        "Physical verification Excel report exported by " + username
                );

                response.setContentType("application/vnd.openxmlformats-officedocument.spreadsheetml.sheet");
                response.setHeader(
                        "Content-Disposition",
                        "attachment; filename=\"IR_AMS_Physical_Verification_Report.xlsx\""
                );

                try (ServletOutputStream outputStream = response.getOutputStream()) {
                    workbook.write(outputStream);
                    outputStream.flush();
                }
            }

        } catch (Exception e) {
            e.printStackTrace();
            response.sendRedirect("reports.jsp?error=physical_export");
        }
    }

    private int fillReportRows(
            Connection con,
            Sheet sheet,
            int rowIndex,
            String statusFilter,
            String fromDate,
            String toDate,
            CellStyle numberStyle,
            CellStyle textStyle,
            CellStyle dateStyle,
            CellStyle verifiedStyle,
            CellStyle warningStyle,
            CellStyle dangerStyle,
            CellStyle neutralStyle,
            int lastColumnIndex) throws Exception {

        boolean hasAssets = tableExists(con, "assets");
        boolean hasCategories = tableExists(con, "asset_categories");
        boolean hasVendors = tableExists(con, "vendors");
        boolean hasUsers = tableExists(con, "users");
        boolean hasDepartments = tableExists(con, "departments");
        boolean hasEmployees = tableExists(con, "employees");
        boolean hasRailwayLocations = tableExists(con, "railway_locations");

        boolean pvHasVerificationId = columnExists(con, "asset_physical_verification", "verification_id");
        boolean pvHasAssetId = columnExists(con, "asset_physical_verification", "asset_id");
        boolean pvHasVerifiedStatus = columnExists(con, "asset_physical_verification", "verified_status");
        boolean pvHasReviewStatus = columnExists(con, "asset_physical_verification", "review_status");
        boolean pvHasVerifiedByUserId = columnExists(con, "asset_physical_verification", "verified_by_user_id");
        boolean pvHasActualLocationId = columnExists(con, "asset_physical_verification", "actual_location_id");
        boolean pvHasActualEmployeeId = columnExists(con, "asset_physical_verification", "actual_employee_id");
        boolean pvHasOfficerEmployeeId = columnExists(con, "asset_physical_verification", "verification_officer_employee_id");
        boolean pvHasOfficerDepartmentId = columnExists(con, "asset_physical_verification", "verification_officer_department_id");
        boolean pvHasVerifiedOn = columnExists(con, "asset_physical_verification", "verified_on");
        boolean pvHasRemarks = columnExists(con, "asset_physical_verification", "remarks");

        boolean aHasAssetId = hasAssets && columnExists(con, "assets", "asset_id");
        boolean aHasAssetCode = hasAssets && columnExists(con, "assets", "asset_code");
        boolean aHasRailwayAssetNo = hasAssets && columnExists(con, "assets", "railway_asset_no");
        boolean aHasAssetName = hasAssets && columnExists(con, "assets", "asset_name");
        boolean aHasCategoryId = hasAssets && columnExists(con, "assets", "category_id");
        boolean aHasVendorId = hasAssets && columnExists(con, "assets", "vendor_id");
        boolean aHasAssetStatus = hasAssets && columnExists(con, "assets", "asset_status");
        boolean aHasServiceStatus = hasAssets && columnExists(con, "assets", "service_status");
        boolean aHasLocationText = hasAssets && columnExists(con, "assets", "location");
        boolean aHasRailwayLocationId = hasAssets && columnExists(con, "assets", "railway_location_id");
        boolean aHasLocationId = hasAssets && columnExists(con, "assets", "location_id");

        boolean cHasCategoryId = hasCategories && columnExists(con, "asset_categories", "category_id");
        boolean cHasCategoryName = hasCategories && columnExists(con, "asset_categories", "category_name");

        boolean vHasVendorId = hasVendors && columnExists(con, "vendors", "vendor_id");
        boolean vHasVendorName = hasVendors && columnExists(con, "vendors", "vendor_name");

        boolean uHasUserId = hasUsers && columnExists(con, "users", "user_id");
        boolean uHasUsername = hasUsers && columnExists(con, "users", "username");

        boolean dHasDepartmentId = hasDepartments && columnExists(con, "departments", "department_id");
        boolean dHasDepartmentName = hasDepartments && columnExists(con, "departments", "department_name");

        boolean eHasEmployeeId = hasEmployees && columnExists(con, "employees", "employee_id");
        boolean eHasEmployeeCode = hasEmployees && columnExists(con, "employees", "employee_code");
        boolean eHasEmployeeName = hasEmployees && columnExists(con, "employees", "employee_name");

        boolean locHasLocationId = hasRailwayLocations && columnExists(con, "railway_locations", "location_id");
        boolean locHasLocationName = hasRailwayLocations && columnExists(con, "railway_locations", "location_name");
        boolean locHasOfficeName = hasRailwayLocations && columnExists(con, "railway_locations", "office_name");

        StringBuilder sql = new StringBuilder();

        sql.append("SELECT ");

        sql.append(pvHasVerificationId ? "pv.verification_id" : "0").append(" AS verification_id, ");
        sql.append(pvHasVerifiedStatus ? "COALESCE(pv.verified_status, '')" : "''").append(" AS verified_status, ");
        sql.append(pvHasReviewStatus ? "COALESCE(pv.review_status, '')" : "''").append(" AS review_status, ");
        sql.append(pvHasVerifiedOn ? "pv.verified_on" : "NULL").append(" AS verified_on, ");
        sql.append(pvHasRemarks ? "COALESCE(pv.remarks, '')" : "''").append(" AS remarks, ");

        sql.append(aHasAssetCode ? "COALESCE(a.asset_code, '')" : "''").append(" AS asset_code, ");
        sql.append(aHasRailwayAssetNo ? "COALESCE(a.railway_asset_no, '')" : "''").append(" AS railway_asset_no, ");
        sql.append(aHasAssetName ? "COALESCE(a.asset_name, '')" : "''").append(" AS asset_name, ");
        sql.append(aHasAssetStatus ? "COALESCE(a.asset_status, '')" : "''").append(" AS asset_status, ");
        sql.append(aHasServiceStatus ? "COALESCE(a.service_status, '')" : "''").append(" AS service_status, ");

        sql.append(cHasCategoryName ? "COALESCE(c.category_name, '')" : "''").append(" AS category_name, ");
        sql.append(vHasVendorName ? "COALESCE(v.vendor_name, '')" : "''").append(" AS supplier_name, ");

        if (locHasLocationName && (aHasRailwayLocationId || aHasLocationId)) {
            if (locHasOfficeName) {
                sql.append("TRIM(CONCAT(COALESCE(sysloc.office_name, ''), ' ', COALESCE(sysloc.location_name, '')))");
            } else {
                sql.append("COALESCE(sysloc.location_name, '')");
            }
        } else if (aHasLocationText) {
            sql.append("COALESCE(a.location, '')");
        } else {
            sql.append("''");
        }
        sql.append(" AS system_location, ");

        if (locHasLocationName && pvHasActualLocationId) {
            if (locHasOfficeName) {
                sql.append("TRIM(CONCAT(COALESCE(actloc.office_name, ''), ' ', COALESCE(actloc.location_name, '')))");
            } else {
                sql.append("COALESCE(actloc.location_name, '')");
            }
        } else {
            sql.append("''");
        }
        sql.append(" AS actual_location, ");

        sql.append(createEmployeeNameExpression(
                "holder",
                eHasEmployeeCode,
                eHasEmployeeName
        )).append(" AS actual_holder, ");

        sql.append(createEmployeeNameExpression(
                "officer",
                eHasEmployeeCode,
                eHasEmployeeName
        )).append(" AS officer_name, ");

        sql.append(dHasDepartmentName ? "COALESCE(od.department_name, '')" : "''").append(" AS officer_department, ");
        sql.append(uHasUsername ? "COALESCE(u.username, '')" : "''").append(" AS verified_by ");

        sql.append("FROM asset_physical_verification pv ");

        if (hasAssets && aHasAssetId && pvHasAssetId) {
            sql.append("LEFT JOIN assets a ON pv.asset_id = a.asset_id ");
        }

        if (hasCategories && cHasCategoryId && cHasCategoryName && aHasCategoryId) {
            sql.append("LEFT JOIN asset_categories c ON a.category_id = c.category_id ");
        }

        if (hasVendors && vHasVendorId && vHasVendorName && aHasVendorId) {
            sql.append("LEFT JOIN vendors v ON a.vendor_id = v.vendor_id ");
        }

        if (hasRailwayLocations && locHasLocationId && locHasLocationName && aHasRailwayLocationId) {
            sql.append("LEFT JOIN railway_locations sysloc ON a.railway_location_id = sysloc.location_id ");
        } else if (hasRailwayLocations && locHasLocationId && locHasLocationName && aHasLocationId) {
            sql.append("LEFT JOIN railway_locations sysloc ON a.location_id = sysloc.location_id ");
        }

        if (hasRailwayLocations && locHasLocationId && locHasLocationName && pvHasActualLocationId) {
            sql.append("LEFT JOIN railway_locations actloc ON pv.actual_location_id = actloc.location_id ");
        }

        if (hasEmployees && eHasEmployeeId && pvHasActualEmployeeId) {
            sql.append("LEFT JOIN employees holder ON pv.actual_employee_id = holder.employee_id ");
        }

        if (hasEmployees && eHasEmployeeId && pvHasOfficerEmployeeId) {
            sql.append("LEFT JOIN employees officer ON pv.verification_officer_employee_id = officer.employee_id ");
        }

        if (hasDepartments && dHasDepartmentId && dHasDepartmentName && pvHasOfficerDepartmentId) {
            sql.append("LEFT JOIN departments od ON pv.verification_officer_department_id = od.department_id ");
        }

        if (hasUsers && uHasUserId && uHasUsername && pvHasVerifiedByUserId) {
            sql.append("LEFT JOIN users u ON pv.verified_by_user_id = u.user_id ");
        }

        sql.append("WHERE 1 = 1 ");

        List<String> params = new ArrayList<>();

        if (!"ALL".equalsIgnoreCase(statusFilter) && pvHasVerifiedStatus) {
            sql.append("AND pv.verified_status = ? ");
            params.add(statusFilter);
        }

        if (!fromDate.isEmpty() && pvHasVerifiedOn) {
            sql.append("AND DATE(pv.verified_on) >= ? ");
            params.add(fromDate);
        }

        if (!toDate.isEmpty() && pvHasVerifiedOn) {
            sql.append("AND DATE(pv.verified_on) <= ? ");
            params.add(toDate);
        }

        if (pvHasVerifiedOn && pvHasVerificationId) {
            sql.append("ORDER BY pv.verified_on DESC, pv.verification_id DESC");
        } else if (pvHasVerificationId) {
            sql.append("ORDER BY pv.verification_id DESC");
        }

        int slNo = 1;
        int dataStartRow = rowIndex;

        try (PreparedStatement ps = con.prepareStatement(sql.toString())) {

            for (int i = 0; i < params.size(); i++) {
                ps.setString(i + 1, params.get(i));
            }

            try (ResultSet rs = ps.executeQuery()) {

                while (rs.next()) {
                    Row row = sheet.createRow(rowIndex++);
                    row.setHeightInPoints(28);

                    int col = 0;

                    createCell(row, col++, slNo++, numberStyle);
                    createCell(row, col++, rs.getInt("verification_id"), numberStyle);
                    createCell(row, col++, rs.getString("asset_code"), textStyle);
                    createCell(row, col++, rs.getString("railway_asset_no"), textStyle);
                    createCell(row, col++, rs.getString("asset_name"), textStyle);
                    createCell(row, col++, rs.getString("category_name"), textStyle);
                    createCell(row, col++, formatText(rs.getString("asset_status")), textStyle);
                    createCell(row, col++, formatText(rs.getString("service_status")), textStyle);
                    createCell(row, col++, rs.getString("supplier_name"), textStyle);

                    String verifiedStatus = rs.getString("verified_status");
                    Cell statusCell = row.createCell(col++);
                    statusCell.setCellValue(formatText(verifiedStatus));
                    statusCell.setCellStyle(getStatusStyle(
                            verifiedStatus,
                            verifiedStyle,
                            warningStyle,
                            dangerStyle,
                            neutralStyle
                    ));

                    createCell(row, col++, formatText(rs.getString("review_status")), textStyle);
                    createCell(row, col++, rs.getString("system_location"), textStyle);
                    createCell(row, col++, rs.getString("actual_location"), textStyle);
                    createCell(row, col++, rs.getString("actual_holder"), textStyle);
                    createCell(row, col++, rs.getString("officer_name"), textStyle);
                    createCell(row, col++, rs.getString("officer_department"), textStyle);
                    createCell(row, col++, rs.getString("verified_by"), textStyle);

                    Cell dateCell = row.createCell(col++);

                    if (rs.getTimestamp("verified_on") != null) {
                        dateCell.setCellValue(rs.getTimestamp("verified_on"));
                        dateCell.setCellStyle(dateStyle);
                    } else {
                        dateCell.setCellValue("-");
                        dateCell.setCellStyle(textStyle);
                    }

                    createCell(row, col++, rs.getString("remarks"), textStyle);
                }
            }
        }

        if (rowIndex == dataStartRow) {
            Row row = sheet.createRow(rowIndex++);
            row.setHeightInPoints(28);
            createMergedRow(
                    sheet,
                    row,
                    0,
                    lastColumnIndex,
                    "No physical verification records found.",
                    textStyle
            );
        }

        return rowIndex;
    }

    private String createEmployeeNameExpression(
            String alias,
            boolean hasEmployeeCode,
            boolean hasEmployeeName) {

        String codeExpression = hasEmployeeCode ? "COALESCE(" + alias + ".employee_code, '')" : "''";
        String nameExpression = hasEmployeeName ? "COALESCE(" + alias + ".employee_name, '')" : "''";

        return "TRIM(CONCAT(" + codeExpression + ", CASE WHEN " + codeExpression
                + " <> '' AND " + nameExpression + " <> '' THEN ' - ' ELSE '' END, "
                + nameExpression + "))";
    }

    private boolean canExport(String role) {
        return ("SUPER_ADMIN".equals(role) || "ADMIN".equals(role))
                || "ASSET_MANAGER".equalsIgnoreCase(role)
                || "AUDITOR".equalsIgnoreCase(role);
    }

    private void createMergedRow(Sheet sheet, Row row, int firstColumn, int lastColumn, String value, CellStyle style) {

        for (int columnIndex = firstColumn; columnIndex <= lastColumn; columnIndex++) {
            Cell cell = row.createCell(columnIndex);

            if (columnIndex == firstColumn) {
                if (value == null || value.trim().isEmpty()) {
                    cell.setCellValue("-");
                } else {
                    cell.setCellValue(value.trim());
                }
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

    private void createCell(Row row, int columnIndex, String value, CellStyle style) {
        Cell cell = row.createCell(columnIndex);

        if (value == null || value.trim().isEmpty()) {
            cell.setCellValue("-");
        } else {
            cell.setCellValue(value.trim());
        }

        cell.setCellStyle(style);
    }

    private void createCell(Row row, int columnIndex, int value, CellStyle style) {
        Cell cell = row.createCell(columnIndex);
        cell.setCellValue(value);
        cell.setCellStyle(style);
    }

    private CellStyle createTitleStyle(Workbook workbook) {
        Font font = workbook.createFont();
        font.setBold(true);
        font.setFontHeightInPoints((short) 18);
        font.setColor(IndexedColors.WHITE.getIndex());

        CellStyle style = workbook.createCellStyle();
        style.setFont(font);
        style.setFillForegroundColor(IndexedColors.DARK_BLUE.getIndex());
        style.setFillPattern(FillPatternType.SOLID_FOREGROUND);
        style.setAlignment(HorizontalAlignment.CENTER);
        style.setVerticalAlignment(VerticalAlignment.CENTER);

        return style;
    }

    private CellStyle createSubtitleStyle(Workbook workbook) {
        Font font = workbook.createFont();
        font.setBold(true);
        font.setFontHeightInPoints((short) 12);
        font.setColor(IndexedColors.DARK_BLUE.getIndex());

        CellStyle style = workbook.createCellStyle();
        style.setFont(font);
        style.setAlignment(HorizontalAlignment.CENTER);
        style.setVerticalAlignment(VerticalAlignment.CENTER);

        return style;
    }

    private CellStyle createFilterStyle(Workbook workbook) {
        Font font = workbook.createFont();
        font.setBold(true);
        font.setFontHeightInPoints((short) 10);
        font.setColor(IndexedColors.GREY_80_PERCENT.getIndex());

        CellStyle style = workbook.createCellStyle();
        style.setFont(font);
        style.setAlignment(HorizontalAlignment.CENTER);
        style.setVerticalAlignment(VerticalAlignment.CENTER);

        return style;
    }

    private CellStyle createHeaderStyle(Workbook workbook) {
        Font font = workbook.createFont();
        font.setBold(true);
        font.setColor(IndexedColors.WHITE.getIndex());

        CellStyle style = workbook.createCellStyle();
        style.setFont(font);
        style.setFillForegroundColor(IndexedColors.ROYAL_BLUE.getIndex());
        style.setFillPattern(FillPatternType.SOLID_FOREGROUND);
        style.setAlignment(HorizontalAlignment.CENTER);
        style.setVerticalAlignment(VerticalAlignment.CENTER);
        style.setWrapText(true);
        addThinBorder(style);

        return style;
    }

    private CellStyle createTextStyle(Workbook workbook) {
        Font font = workbook.createFont();
        font.setFontHeightInPoints((short) 10);

        CellStyle style = workbook.createCellStyle();
        style.setFont(font);
        style.setWrapText(true);
        style.setAlignment(HorizontalAlignment.CENTER);
        style.setVerticalAlignment(VerticalAlignment.CENTER);
        addThinBorder(style);

        return style;
    }

    private CellStyle createNumberStyle(Workbook workbook) {
        Font font = workbook.createFont();
        font.setFontHeightInPoints((short) 10);

        CellStyle style = workbook.createCellStyle();
        style.setFont(font);
        style.setAlignment(HorizontalAlignment.CENTER);
        style.setVerticalAlignment(VerticalAlignment.CENTER);
        addThinBorder(style);

        return style;
    }

    private CellStyle createDateStyle(Workbook workbook, DataFormat dataFormat) {
        Font font = workbook.createFont();
        font.setFontHeightInPoints((short) 10);

        CellStyle style = workbook.createCellStyle();
        style.setFont(font);
        style.setDataFormat(dataFormat.getFormat("dd-mmm-yyyy hh:mm"));
        style.setAlignment(HorizontalAlignment.CENTER);
        style.setVerticalAlignment(VerticalAlignment.CENTER);
        addThinBorder(style);

        return style;
    }

    private CellStyle createStatusStyle(Workbook workbook, IndexedColors color) {
        Font font = workbook.createFont();
        font.setBold(true);
        font.setFontHeightInPoints((short) 10);

        CellStyle style = workbook.createCellStyle();
        style.setFont(font);
        style.setFillForegroundColor(color.getIndex());
        style.setFillPattern(FillPatternType.SOLID_FOREGROUND);
        style.setAlignment(HorizontalAlignment.CENTER);
        style.setVerticalAlignment(VerticalAlignment.CENTER);
        addThinBorder(style);

        return style;
    }

    private CellStyle getStatusStyle(
            String status,
            CellStyle verifiedStyle,
            CellStyle warningStyle,
            CellStyle dangerStyle,
            CellStyle neutralStyle) {

        if (status == null) {
            return neutralStyle;
        }

        String value = status.trim().toUpperCase();

        if ("VERIFIED".equals(value)) {
            return verifiedStyle;
        }

        if ("NOT_FOUND".equals(value) || "DAMAGED".equals(value)) {
            return dangerStyle;
        }

        if ("LOCATION_MISMATCH".equals(value)
                || "EMPLOYEE_MISMATCH".equals(value)
                || "UNDER_REPAIR".equals(value)
                || "NEEDS_REVIEW".equals(value)) {
            return warningStyle;
        }

        return neutralStyle;
    }

    private void addThinBorder(CellStyle style) {
        style.setBorderTop(BorderStyle.THIN);
        style.setBorderBottom(BorderStyle.THIN);
        style.setBorderLeft(BorderStyle.THIN);
        style.setBorderRight(BorderStyle.THIN);

        style.setTopBorderColor(IndexedColors.GREY_25_PERCENT.getIndex());
        style.setBottomBorderColor(IndexedColors.GREY_25_PERCENT.getIndex());
        style.setLeftBorderColor(IndexedColors.GREY_25_PERCENT.getIndex());
        style.setRightBorderColor(IndexedColors.GREY_25_PERCENT.getIndex());
    }

    private void safeAuditLog(int userId, String action, String tableName, int recordId, String description) {
        try {
            AuditDAO.log(userId, action, tableName, recordId, description);
        } catch (Exception e) {
            e.printStackTrace();
        }
    }

    private boolean tableExists(Connection con, String tableName) {
        String sql = "SELECT COUNT(*) FROM information_schema.tables "
                + "WHERE table_schema = DATABASE() "
                + "AND table_name = ?";

        try (PreparedStatement ps = con.prepareStatement(sql)) {
            ps.setString(1, tableName);

            try (ResultSet rs = ps.executeQuery()) {
                return rs.next() && rs.getInt(1) > 0;
            }

        } catch (Exception e) {
            e.printStackTrace();
        }

        return false;
    }

    private boolean columnExists(Connection con, String tableName, String columnName) {
        String sql = "SELECT COUNT(*) FROM information_schema.columns "
                + "WHERE table_schema = DATABASE() "
                + "AND table_name = ? "
                + "AND column_name = ?";

        try (PreparedStatement ps = con.prepareStatement(sql)) {
            ps.setString(1, tableName);
            ps.setString(2, columnName);

            try (ResultSet rs = ps.executeQuery()) {
                return rs.next() && rs.getInt(1) > 0;
            }

        } catch (Exception e) {
            e.printStackTrace();
        }

        return false;
    }

    private String clean(String value) {
        if (value == null) {
            return "";
        }

        return value.trim();
    }

    private String formatText(String value) {
        if (value == null || value.trim().isEmpty()) {
            return "-";
        }

        return value.trim().replace("_", " ");
    }

    private int getSessionInt(HttpSession session, String key, int defaultValue) {
        try {
            Object value = session.getAttribute(key);

            if (value == null) {
                Object altValue = session.getAttribute("userId");

                if (altValue == null) {
                    return defaultValue;
                }

                value = altValue;
            }

            return Integer.parseInt(String.valueOf(value));

        } catch (Exception e) {
            return defaultValue;
        }
    }

    private String formatRole(String role) {
        if (role == null || role.trim().isEmpty()) {
            return "Unknown Role";
        }

        String text = role.trim().replace("_", " ").toLowerCase();
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
}