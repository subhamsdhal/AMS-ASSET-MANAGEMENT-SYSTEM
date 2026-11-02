package com.mycompany.asset_management_system_ams;

import jakarta.servlet.ServletException;
import jakarta.servlet.annotation.WebServlet;
import jakarta.servlet.http.HttpServlet;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import jakarta.servlet.http.HttpSession;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.nio.file.Files;
import java.nio.file.Path;

@WebServlet(name = "DownloadEmployeeDocumentServlet", urlPatterns = {"/DownloadEmployeeDocumentServlet"})
public class DownloadEmployeeDocumentServlet extends HttpServlet {

    @Override
    protected void doGet(HttpServletRequest request, HttpServletResponse response)
            throws ServletException, IOException {

        try {
            HttpSession session = request.getSession(false);

            if (session == null || session.getAttribute("username") == null || session.getAttribute("role") == null) {
                response.sendRedirect("login.jsp");
                return;
            }

            String role = String.valueOf(session.getAttribute("role"));

            boolean isSuperAdminOrAdmin = "SUPER_ADMIN".equals(role) || "ADMIN".equals(role);
            boolean isDepartmentHead = "DEPARTMENT_HEAD".equalsIgnoreCase(role);
            boolean isAuditor = "AUDITOR".equalsIgnoreCase(role);

            if (!isSuperAdminOrAdmin && !isDepartmentHead && !isAuditor) {
                response.sendRedirect("employees.jsp?error=access_denied");
                return;
            }

            int userId = 1;
            if (session.getAttribute("user_id") != null) {
                userId = Integer.parseInt(session.getAttribute("user_id").toString());
            } else if (session.getAttribute("userId") != null) {
                userId = Integer.parseInt(session.getAttribute("userId").toString());
            }

            int documentId = parseInt(request.getParameter("id"), 0);

            if (documentId <= 0) {
                response.sendRedirect("employees.jsp?error=invalid_document");
                return;
            }

            EmployeeDocumentDAO dao = new EmployeeDocumentDAO();
            EmployeeDocument document = dao.getDocumentById(documentId);

            if (document == null) {
                response.sendRedirect("employees.jsp?error=document_notfound");
                return;
            }

            if (isDepartmentHead) {
                EmployeeDAO empDao = new EmployeeDAO();
                if (!empDao.isEmployeeUnderDepartmentHead(document.getEmployeeId(), userId)) {
                    response.sendRedirect("employees.jsp?error=access_denied");
                    return;
                }
            }

            String filePath;
            try {
                filePath = document.getStoredFilePath();
                if (filePath == null || filePath.trim().isEmpty()) {
                    throw new Exception("Invalid file path");
                }
            } catch (Exception e) {
                response.sendRedirect("view_employee.jsp?id=" + document.getEmployeeId() + "&error=document_missing");
                return;
            }

            String mimeType = document.getMimeType();
            if (mimeType == null || mimeType.isEmpty()) {
                mimeType = "application/octet-stream";
            }

            response.setContentType(mimeType);
            response.setHeader("Content-Disposition", "inline; filename=\"" + document.getOriginalFileName() + "\"");

            try (InputStream in = com.mycompany.asset_management_system_ams.storage.StorageServiceFactory.getInstance().downloadFile(filePath);
                 OutputStream out = response.getOutputStream()) {

                byte[] buffer = new byte[8192];
                int bytesRead;
                while ((bytesRead = in.read(buffer)) != -1) {
                    out.write(buffer, 0, bytesRead);
                }
            }

        } catch (Exception e) {
            e.printStackTrace();
            response.sendRedirect("employees.jsp?error=server");
        }
    }

    private int parseInt(String value, int fallback) {
        try {
            return Integer.parseInt(value == null ? "" : value.trim());
        } catch (Exception e) {
            return fallback;
        }
    }
}
