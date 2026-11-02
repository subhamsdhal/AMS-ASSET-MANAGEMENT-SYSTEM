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

/**
 * DownloadVendorDocumentServlet - serves a vendor compliance document back
 * as a forced attachment download. Read access matches view_vendor.jsp's
 * own role set (commonOps in RoleAccessUtil) - anyone who can view the
 * vendor profile can download its compliance documents.
 */
@WebServlet(name = "DownloadVendorDocumentServlet", urlPatterns = {"/DownloadVendorDocumentServlet"})
public class DownloadVendorDocumentServlet extends HttpServlet {

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

        int documentId = parseInt(request.getParameter("id"), 0);

        if (documentId <= 0) {
            response.sendRedirect("vendors.jsp?error=document_missing");
            return;
        }

        VendorDocument document = new VendorDocumentDAO().getDocumentById(documentId);

        if (document == null) {
            response.sendRedirect("vendors.jsp?error=document_missing");
            return;
        }

        try {
            String documentPath = document.getStoredFilePath();
            
            if (documentPath == null || documentPath.trim().isEmpty()) {
                throw new Exception("Invalid file path");
            }

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
            response.sendRedirect("view_vendor.jsp?id=" + document.getVendorId() + "&error=document_missing");
        }
    }

    private int parseInt(String value, int fallback) {
        try {
            return Integer.parseInt(value == null ? "" : value.trim());
        } catch (Exception e) {
            return fallback;
        }
    }

    private String downloadFileName(String value) {
        String clean = value == null ? "vendor-document" : value.trim();

        if (clean.isEmpty()) {
            clean = "vendor-document";
        }

        return clean.replace("\\", "_").replace("/", "_").replace("\"", "'");
    }
}
