package com.mycompany.asset_management_system_ams;

import jakarta.servlet.ServletException;
import jakarta.servlet.annotation.MultipartConfig;
import jakarta.servlet.annotation.WebServlet;
import jakarta.servlet.http.HttpServlet;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import jakarta.servlet.http.HttpSession;
import jakarta.servlet.http.Part;

import java.io.File;
import java.io.IOException;
import java.util.UUID;

@WebServlet("/UploadEmployeeProfileImageServlet")
@MultipartConfig(fileSizeThreshold = 1024 * 1024,
                 maxFileSize = 5242880,      // 5 MB
                 maxRequestSize = 10485760)  // 10 MB
public class UploadEmployeeProfileImageServlet extends HttpServlet {

    private static final String UPLOAD_DIR = "uploads/employee-profiles";

    @Override
    protected void doPost(HttpServletRequest request, HttpServletResponse response) throws ServletException, IOException {
        HttpSession session = request.getSession(false);
        if (session == null || session.getAttribute("user_id") == null || session.getAttribute("role") == null) {
            response.sendRedirect("login.jsp");
            return;
        }

        String loggedInUserIdStr = String.valueOf(session.getAttribute("user_id"));
        String role = (String) session.getAttribute("role");
        
        int loggedInUserId;
        try {
            loggedInUserId = Integer.parseInt(loggedInUserIdStr);
        } catch (NumberFormatException e) {
            response.sendRedirect("login.jsp");
            return;
        }

        String employeeIdStr = request.getParameter("employeeId");
        if (employeeIdStr == null || employeeIdStr.trim().isEmpty()) {
            response.sendRedirect("employees.jsp?error=invalid_employee");
            return;
        }

        int targetEmployeeId;
        try {
            targetEmployeeId = Integer.parseInt(employeeIdStr.trim());
        } catch (NumberFormatException e) {
            response.sendRedirect("employees.jsp?error=invalid_employee");
            return;
        }

        EmployeeDAO employeeDAO = new EmployeeDAO();
        Employee targetEmployee = employeeDAO.getEmployeeById(targetEmployeeId);
        
        if (targetEmployee == null) {
            response.sendRedirect("employees.jsp?error=notfound");
            return;
        }

        // RBAC Check
        boolean isAuthorized = false;
        if ("SUPER_ADMIN".equals(role) || "ADMIN".equals(role)) {
            isAuthorized = true;
        } else if ("DEPARTMENT_HEAD".equals(role)) {
            isAuthorized = employeeDAO.isEmployeeUnderDepartmentHead(targetEmployeeId, loggedInUserId);
        } else if ("EMPLOYEE".equals(role)) {
            int loggedInEmployeeId = employeeDAO.getEmployeeIdByUserId(loggedInUserId);
            isAuthorized = (loggedInEmployeeId == targetEmployeeId);
        }

        if (!isAuthorized) {
            response.sendRedirect("view_employee.jsp?id=" + targetEmployeeId + "&error=unauthorized");
            return;
        }

        try {
            Part filePart = request.getPart("profileImage");
            if (filePart == null || filePart.getSize() == 0) {
                response.sendRedirect("view_employee.jsp?id=" + targetEmployeeId + "&error=missing_file");
                return;
            }

            String contentType = filePart.getContentType();
            if (contentType == null || !(contentType.equals("image/jpeg") || contentType.equals("image/png") || contentType.equals("image/webp"))) {
                response.sendRedirect("view_employee.jsp?id=" + targetEmployeeId + "&error=invalid_type");
                return;
            }

            String submittedFileName = filePart.getSubmittedFileName();
            if (submittedFileName == null || submittedFileName.isEmpty()) {
                response.sendRedirect("view_employee.jsp?id=" + targetEmployeeId + "&error=missing_file");
                return;
            }

            String extension = "";
            int extIndex = submittedFileName.lastIndexOf(".");
            if (extIndex > 0) {
                extension = submittedFileName.substring(extIndex).toLowerCase();
            }

            if (!(extension.equals(".jpg") || extension.equals(".jpeg") || extension.equals(".png") || extension.equals(".webp"))) {
                response.sendRedirect("view_employee.jsp?id=" + targetEmployeeId + "&error=invalid_type");
                return;
            }

            String safeFileName = "emp_" + targetEmployeeId + "_" + UUID.randomUUID().toString() + extension;
            String relativeDbPath = "documents/employee-profiles/" + safeFileName;

            try (java.io.InputStream input = filePart.getInputStream()) {
                com.mycompany.asset_management_system_ams.storage.StorageServiceFactory.getInstance()
                    .uploadFile(relativeDbPath, input, contentType, filePart.getSize());
            }

            boolean success = employeeDAO.updateEmployeeProfileImage(targetEmployeeId, relativeDbPath);

            if (success) {
                response.sendRedirect("view_employee.jsp?id=" + targetEmployeeId + "&msg=profile_image_updated");
            } else {
                response.sendRedirect("view_employee.jsp?id=" + targetEmployeeId + "&error=db_error");
            }
        } catch (Exception e) {
            e.printStackTrace();
            response.sendRedirect("view_employee.jsp?id=" + targetEmployeeId + "&error=upload_failed");
        }
    }
}
