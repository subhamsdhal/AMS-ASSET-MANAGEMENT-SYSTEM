package com.mycompany.asset_management_system_ams;

import jakarta.servlet.ServletException;
import jakarta.servlet.annotation.MultipartConfig;
import jakarta.servlet.annotation.WebServlet;
import jakarta.servlet.http.HttpServlet;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import jakarta.servlet.http.HttpSession;
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Paths;
import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;

@WebServlet(name = "UploadEmployeeDocumentServlet", urlPatterns = {"/UploadEmployeeDocumentServlet"})
@MultipartConfig(
        fileSizeThreshold = 1024 * 1024,
        maxFileSize = 5 * 1024 * 1024,
        maxRequestSize = 6 * 1024 * 1024
)
public class UploadEmployeeDocumentServlet extends HttpServlet {

    @Override
    protected void doPost(HttpServletRequest request, HttpServletResponse response)
            throws ServletException, IOException {

        int employeeId = 0;

        try {
            request.setCharacterEncoding("UTF-8");

            HttpSession session = request.getSession(false);

            if (session == null || session.getAttribute("username") == null || session.getAttribute("role") == null) {
                response.sendRedirect("login.jsp");
                return;
            }

            String username = String.valueOf(session.getAttribute("username"));
            String role = String.valueOf(session.getAttribute("role"));
            int userId = getSessionInt(session, "user_id", 1);
            if (userId == 1) {
                userId = getSessionInt(session, "userId", 1);
            }

            boolean isDepartmentHead = "DEPARTMENT_HEAD".equalsIgnoreCase(role);
            boolean isSuperAdminOrAdmin = "SUPER_ADMIN".equals(role) || "ADMIN".equals(role);

            if (!isSuperAdminOrAdmin && !isDepartmentHead) {
                response.sendRedirect("view_employee.jsp?id=" + safeRedirectId(request.getParameter("employeeId")) + "&error=document_denied");
                return;
            }

            employeeId = parseInt(request.getParameter("employeeId"), 0);

            if (isDepartmentHead) {
                EmployeeDAO dao = new EmployeeDAO();
                if (!dao.isEmployeeUnderDepartmentHead(employeeId, userId)) {
                    response.sendRedirect("employees.jsp?access=denied");
                    return;
                }
            }
            String documentTitle = clean(request.getParameter("documentTitle"));
            String documentType = clean(request.getParameter("documentType"));

            if (employeeId <= 0) {
                response.sendRedirect("employees.jsp?error=invalid_employee");
                return;
            }

            if (documentTitle.isEmpty() || documentType.isEmpty()) {
                response.sendRedirect("view_employee.jsp?id=" + employeeId + "&error=missing_fields");
                return;
            }

            if (!employeeExists(employeeId)) {
                response.sendRedirect("employees.jsp?error=notfound");
                return;
            }

            EmployeeDocumentUploadUtil.SavedDocument savedDocument;

            try {
                savedDocument = EmployeeDocumentUploadUtil.saveEmployeeDocument(
                        request,
                        "employeeDocument",
                        employeeId
                );
            } catch (EmployeeDocumentUploadUtil.UploadException | IllegalStateException uploadEx) {
                AuditDAO.log(
                        userId,
                        "EMP_DOC_UPLOAD_BLOCKED",
                        "employee_documents",
                        employeeId,
                        "Employee document upload blocked. Employee ID: " + employeeId
                        + ", Reason: " + uploadEx.getMessage()
                        + ", Attempted by: " + username
                );

                response.sendRedirect("view_employee.jsp?id=" + employeeId + "&error=doc_upload_failed");
                return;
            }

            EmployeeDocumentDAO dao = new EmployeeDocumentDAO();
            int documentId = dao.addDocument(
                    employeeId,
                    documentTitle,
                    documentType,
                    savedDocument.getOriginalFileName(),
                    savedDocument.getStoredFileName(),
                    savedDocument.getStoredFilePath(),
                    savedDocument.getMimeType(),
                    savedDocument.getFileSize(),
                    userId
            );

            if (documentId > 0) {
                AuditDAO.log(
                        userId,
                        "EMP_DOC_UPLOAD",
                        "employee_documents",
                        documentId,
                        "Employee document uploaded. Employee ID: " + employeeId
                        + ", Title: " + documentTitle
                        + ", File: " + savedDocument.getOriginalFileName()
                        + ", Uploaded by: " + username
                );

                response.sendRedirect("view_employee.jsp?id=" + employeeId + "&msg=doc_uploaded");
            } else {
                try {
                    Files.deleteIfExists(Paths.get(savedDocument.getStoredFilePath()));
                } catch (Exception ignored) {}

                AuditDAO.log(
                        userId,
                        "EMP_DOC_UPLOAD_FAILED",
                        "employee_documents",
                        employeeId,
                        "Employee document upload failed during DB insert. Employee ID: " + employeeId
                );

                response.sendRedirect("view_employee.jsp?id=" + employeeId + "&error=doc_upload_failed");
            }

        } catch (Exception e) {
            e.printStackTrace();
            if (employeeId > 0) {
                response.sendRedirect("view_employee.jsp?id=" + employeeId + "&error=doc_upload_failed");
            } else {
                response.sendRedirect("employees.jsp?error=server");
            }
        }
    }

    private boolean employeeExists(int employeeId) {
        String sql = "SELECT employee_id FROM employees WHERE employee_id = ? LIMIT 1";
        try (Connection con = DBConnection.getConnection();
             PreparedStatement ps = con.prepareStatement(sql)) {
            ps.setInt(1, employeeId);
            try (ResultSet rs = ps.executeQuery()) {
                return rs.next();
            }
        } catch (Exception e) {
            e.printStackTrace();
        }
        return false;
    }

    private int getSessionInt(HttpSession session, String key, int fallback) {
        try {
            Object value = session.getAttribute(key);
            if (value == null) return fallback;
            return Integer.parseInt(String.valueOf(value));
        } catch (Exception e) {
            return fallback;
        }
    }

    private int parseInt(String value, int fallback) {
        try {
            return Integer.parseInt(clean(value));
        } catch (Exception e) {
            return fallback;
        }
    }

    private String safeRedirectId(String value) {
        int parsed = parseInt(value, 0);
        return parsed > 0 ? String.valueOf(parsed) : "0";
    }

    private String clean(String value) {
        return value == null ? "" : value.trim();
    }
}
