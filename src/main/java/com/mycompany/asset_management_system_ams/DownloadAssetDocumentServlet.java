package com.mycompany.asset_management_system_ams;

import jakarta.servlet.ServletOutputStream;
import jakarta.servlet.annotation.WebServlet;
import jakarta.servlet.http.HttpServlet;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import jakarta.servlet.http.HttpSession;
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;

@WebServlet(name = "DownloadAssetDocumentServlet", urlPatterns = {"/DownloadAssetDocumentServlet"})
public class DownloadAssetDocumentServlet extends HttpServlet {

    @Override
    protected void doGet(HttpServletRequest request, HttpServletResponse response)
            throws IOException {

        HttpSession session = request.getSession(false);

        if (session == null
                || session.getAttribute("username") == null
                || session.getAttribute("role") == null) {
            response.sendRedirect("login.jsp");
            return;
        }

        String role = String.valueOf(session.getAttribute("role"));

        if (!isAllowedRole(role)) {
            response.sendRedirect("assets.jsp?access=denied");
            return;
        }

        int documentId = parseInt(request.getParameter("id"), 0);

        if (documentId <= 0) {
            response.sendRedirect("assets.jsp?error=document_missing");
            return;
        }

        AssetDocument document = new AssetDocumentDAO().getDocumentById(documentId);

        if (document == null) {
            response.sendRedirect("assets.jsp?error=document_missing");
            return;
        }

        try {
            String documentPath = document.getStoredFilePath();

            String contentType = document.getMimeType();

            if (contentType == null || contentType.trim().isEmpty()) {
                contentType = "application/octet-stream";
            }

            response.reset();
            response.setContentType(contentType);
            response.setHeader(
                    "Content-Disposition",
                    "attachment; filename=\"" + downloadFileName(document.getOriginalFileName()) + "\""
            );
            
            // Note: Cloud Storage streaming does not always provide content length upfront easily
            // unless we do a get blob metadata first, but for now we stream it.
            
            try (java.io.InputStream input = com.mycompany.asset_management_system_ams.storage.StorageServiceFactory.getInstance().downloadFile(documentPath);
                 ServletOutputStream output = response.getOutputStream()) {
                
                byte[] buffer = new byte[8192];
                int bytesRead;
                while ((bytesRead = input.read(buffer)) != -1) {
                    output.write(buffer, 0, bytesRead);
                }
                output.flush();
            }

        } catch (Exception e) {
            e.printStackTrace();
            response.sendRedirect("view_asset.jsp?id=" + document.getAssetId() + "&error=document_missing");
        }
    }

    private boolean isAllowedRole(String role) {
        return ("SUPER_ADMIN".equals(role) || "ADMIN".equals(role))
                || "ASSET_MANAGER".equalsIgnoreCase(role)
                || "AUDITOR".equalsIgnoreCase(role)
                || "DEPARTMENT_HEAD".equalsIgnoreCase(role);
    }

    private int parseInt(String value, int fallback) {
        try {
            return Integer.parseInt(value == null ? "" : value.trim());
        } catch (Exception e) {
            return fallback;
        }
    }

    private String downloadFileName(String value) {
        String clean = value == null ? "asset-document" : value.trim();

        if (clean.isEmpty()) {
            clean = "asset-document";
        }

        return clean.replace("\\", "_").replace("/", "_").replace("\"", "'");
    }
}
