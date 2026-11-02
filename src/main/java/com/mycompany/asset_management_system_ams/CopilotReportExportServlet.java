package com.mycompany.asset_management_system_ams;

import java.io.IOException;
import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.ResultSetMetaData;
import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;

import jakarta.servlet.ServletException;
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
import org.apache.poi.ss.util.CellRangeAddress;
import org.apache.poi.xssf.usermodel.XSSFWorkbook;
import java.util.logging.Logger;
import java.util.logging.Level;

@WebServlet(name = "CopilotReportExportServlet", urlPatterns = {"/CopilotReportExportServlet"})
public class CopilotReportExportServlet extends HttpServlet {

    private static final Logger LOGGER = Logger.getLogger(CopilotReportExportServlet.class.getName());

    @Override
    protected void doGet(HttpServletRequest request, HttpServletResponse response)
            throws ServletException, IOException {
        
        try {
            HttpSession session = request.getSession(false);
            if (session == null || session.getAttribute("username") == null) {
                response.sendRedirect("login.jsp");
                return;
            }

            String username = String.valueOf(session.getAttribute("username"));
            String role = String.valueOf(session.getAttribute("role"));
            
            int userId = getSessionUserId(session);

            if ("EMPLOYEE".equalsIgnoreCase(role)) {
                response.getWriter().write("Access Denied: Your role does not permit downloading reports.");
                return;
            }

            CopilotQueryPlan intent = (CopilotQueryPlan) session.getAttribute("copilotLastQueryPlan");
            if (intent == null) {
                response.getWriter().write("No report found in active session memory to export.");
                return;
            }

            String title = "Copilot Custom Report";
            String sql = ""; // Not supported in this version
            String[] params = null;
            
            response.getWriter().write("Report Export is currently disabled due to pipeline upgrades.");
            if(true) return;

            response.setContentType("application/vnd.openxmlformats-officedocument.spreadsheetml.sheet");
            response.setHeader("Content-Disposition", "attachment; filename=\"Copilot_Export_" + title.replaceAll("[^a-zA-Z0-9_-]", "_") + ".xlsx\"");

            try (Connection con = DBConnection.getConnection();
                 PreparedStatement ps = con.prepareStatement(sql);
                 Workbook workbook = new XSSFWorkbook()) {

                if (params != null) {
                    for (int i = 0; i < params.length; i++) {
                        ps.setString(i + 1, params[i]);
                    }
                }

                try (ResultSet rs = ps.executeQuery()) {
                    ResultSetMetaData md = rs.getMetaData();
                    int columnCount = md.getColumnCount();

                    Sheet sheet = workbook.createSheet("Copilot Data");

                    // Title styles
                    CellStyle titleStyle = workbook.createCellStyle();
                    Font titleFont = workbook.createFont();
                    titleFont.setBold(true);
                    titleFont.setFontHeightInPoints((short) 14);
                    titleStyle.setFont(titleFont);
                    titleStyle.setAlignment(HorizontalAlignment.CENTER);

                    // Header styles
                    CellStyle headerStyle = workbook.createCellStyle();
                    Font headerFont = workbook.createFont();
                    headerFont.setBold(true);
                    headerFont.setColor(IndexedColors.WHITE.getIndex());
                    headerStyle.setFont(headerFont);
                    headerStyle.setFillForegroundColor(IndexedColors.DARK_BLUE.getIndex());
                    headerStyle.setFillPattern(FillPatternType.SOLID_FOREGROUND);
                    headerStyle.setAlignment(HorizontalAlignment.CENTER);
                    headerStyle.setVerticalAlignment(VerticalAlignment.CENTER);
                    headerStyle.setBorderTop(BorderStyle.THIN);
                    headerStyle.setBorderBottom(BorderStyle.THIN);
                    headerStyle.setBorderLeft(BorderStyle.THIN);
                    headerStyle.setBorderRight(BorderStyle.THIN);

                    // Data styles
                    CellStyle dataStyle = workbook.createCellStyle();
                    dataStyle.setBorderTop(BorderStyle.THIN);
                    dataStyle.setBorderBottom(BorderStyle.THIN);
                    dataStyle.setBorderLeft(BorderStyle.THIN);
                    dataStyle.setBorderRight(BorderStyle.THIN);
                    
                    // Row 0: Title
                    Row row0 = sheet.createRow(0);
                    Cell cell0 = row0.createCell(0);
                    cell0.setCellValue(title);
                    cell0.setCellStyle(titleStyle);
                    sheet.addMergedRegion(new CellRangeAddress(0, 0, 0, columnCount - 1));
                    
                    // Row 1: Meta
                    Row row1 = sheet.createRow(1);
                    row1.createCell(0).setCellValue("Generated By: " + username + " (" + role + ") | Date: " + LocalDateTime.now().format(DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss")));
                    sheet.addMergedRegion(new CellRangeAddress(1, 1, 0, columnCount - 1));

                    // Row 2: Empty
                    
                    // Row 3: Headers
                    Row headerRow = sheet.createRow(3);
                    for (int i = 1; i <= columnCount; i++) {
                        Cell c = headerRow.createCell(i - 1);
                        c.setCellValue(md.getColumnLabel(i).toUpperCase());
                        c.setCellStyle(headerStyle);
                    }
                    
                    sheet.createFreezePane(0, 4);

                    // Rows: Data
                    int rowIdx = 4;
                    while (rs.next()) {
                        Row r = sheet.createRow(rowIdx++);
                        for (int i = 1; i <= columnCount; i++) {
                            Cell c = r.createCell(i - 1);
                            c.setCellValue(rs.getString(i) != null ? rs.getString(i) : "N/A");
                            c.setCellStyle(dataStyle);
                        }
                    }

                    for (int i = 0; i < columnCount; i++) {
                        sheet.autoSizeColumn(i);
                    }

                    workbook.write(response.getOutputStream());
                }

                // Log audit
                try (PreparedStatement logPs = con.prepareStatement("INSERT INTO audit_logs (user_id, username, module_name, action_type, action_details) VALUES (?, ?, 'COPILOT', 'EXPORT', ?)")) {
                    logPs.setInt(1, userId);
                    logPs.setString(2, username);
                    logPs.setString(3, "Exported Report: " + title);
                    logPs.executeUpdate();
                }

            }
        } catch (Exception e) {
            LOGGER.log(Level.SEVERE, "Export Error", e);
            response.getWriter().write("Export failed due to an internal server issue. Please try again or contact administrator.");
        }
    }

    private int getSessionUserId(HttpSession session) {
        String[] names = {"userId", "user_id"};
        for (String name : names) {
            try {
                Object value = session.getAttribute(name);
                if (value != null) {
                    int parsed = Integer.parseInt(String.valueOf(value));
                    if (parsed > 0) {
                        return parsed;
                    }
                }
            } catch (Exception ignored) {}
        }
        return 0;
    }
}
