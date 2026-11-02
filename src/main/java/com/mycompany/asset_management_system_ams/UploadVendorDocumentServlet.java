package com.mycompany.asset_management_system_ams;

import jakarta.servlet.ServletException;
import jakarta.servlet.annotation.MultipartConfig;
import jakarta.servlet.annotation.WebServlet;
import jakarta.servlet.http.HttpServlet;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import jakarta.servlet.http.HttpSession;
import java.io.IOException;

/**
 * UploadVendorDocumentServlet - attaches a compliance document (trade
 * license, GST certificate, PAN, other) to a vendor. Restricted to the same
 * role tier that can already edit a vendor (add_vendor.jsp/edit_vendor.jsp's
 * canManageSuppliers: SUPER_ADMIN/ADMIN/ASSET_MANAGER).
 */
@WebServlet(name = "UploadVendorDocumentServlet", urlPatterns = {"/UploadVendorDocumentServlet"})
@MultipartConfig(
        fileSizeThreshold = 1024 * 1024,
        maxFileSize = 10 * 1024 * 1024,
        maxRequestSize = 12 * 1024 * 1024
)
public class UploadVendorDocumentServlet extends HttpServlet {

    @Override
    protected void doPost(HttpServletRequest request, HttpServletResponse response)
            throws ServletException, IOException {

        int vendorId = 0;

        try {
            request.setCharacterEncoding("UTF-8");

            HttpSession session = request.getSession(false);

            if (session == null
                    || session.getAttribute("username") == null
                    || session.getAttribute("role") == null) {
                response.sendRedirect("login.jsp");
                return;
            }

            String username = String.valueOf(session.getAttribute("username"));
            String role = String.valueOf(session.getAttribute("role"));
            int userId = getSessionUserId(session);

            boolean canManageSuppliers = ("SUPER_ADMIN".equals(role) || "ADMIN".equals(role))
                    || "ASSET_MANAGER".equalsIgnoreCase(role);

            if (!canManageSuppliers) {
                response.sendRedirect("view_vendor.jsp?id=" + safeRedirectId(request.getParameter("vendorId")) + "&error=document_denied");
                return;
            }

            vendorId = parseInt(request.getParameter("vendorId"), 0);
            String documentType = VendorDocumentDAO.normalizeDocumentType(request.getParameter("documentType"));

            if (vendorId <= 0) {
                response.sendRedirect("vendors.jsp?error=invalid");
                return;
            }

            VendorDocumentUploadUtil.SavedDocument savedDocument;

            try {
                savedDocument = VendorDocumentUploadUtil.saveVendorDocument(
                        request,
                        "vendorDocument",
                        vendorId,
                        documentType
                );
            } catch (VendorDocumentUploadUtil.UploadException | IllegalStateException uploadEx) {
                AuditDAO.log(
                        userId,
                        "DOCUMENT_UPLOAD_BLOCKED",
                        "vendor_documents",
                        vendorId,
                        "Vendor document upload blocked. Vendor ID: " + vendorId
                        + ", Reason: " + uploadEx.getMessage()
                        + ", Attempted by: " + username
                );

                response.sendRedirect("view_vendor.jsp?id=" + vendorId + "&error=document_upload");
                return;
            }

            VendorDocumentDAO dao = new VendorDocumentDAO();
            int documentId = dao.addDocument(
                    vendorId,
                    documentType,
                    savedDocument.getOriginalFileName(),
                    savedDocument.getStoredFilePath(),
                    savedDocument.getMimeType(),
                    savedDocument.getFileSize(),
                    userId
            );

            if (documentId > 0) {
                AuditDAO.log(
                        userId,
                        "DOCUMENT_UPLOAD",
                        "vendor_documents",
                        documentId,
                        "Vendor document uploaded. Vendor ID: " + vendorId
                        + ", Type: " + documentType
                        + ", File: " + savedDocument.getOriginalFileName()
                        + ", Uploaded by: " + username
                );

                response.sendRedirect("view_vendor.jsp?id=" + vendorId + "&msg=document_added");
            } else {
                VendorDocumentUploadUtil.deleteIfManaged(savedDocument.getStoredFilePath());

                AuditDAO.log(
                        userId,
                        "DOCUMENT_UPLOAD_FAILED",
                        "vendor_documents",
                        vendorId,
                        "Vendor document upload failed during database insert. Vendor ID: " + vendorId
                        + ", Uploaded by: " + username
                );

                response.sendRedirect("view_vendor.jsp?id=" + vendorId + "&error=document_upload");
            }

        } catch (Exception e) {
            e.printStackTrace();

            if (vendorId > 0) {
                response.sendRedirect("view_vendor.jsp?id=" + vendorId + "&error=document_upload");
            } else {
                response.sendRedirect("vendors.jsp?error=server");
            }
        }
    }

    private int getSessionUserId(HttpSession session) {
        // Defaulting to 1 here would misattribute this audit-log entry to
        // whichever real account happens to be user_id 1. AuditDAO.log()
        // resolves 0/null to a NULL "system" row instead.
        Object userIdObj = session.getAttribute("user_id");
        if (userIdObj != null) {
            try {
                return Integer.parseInt(String.valueOf(userIdObj));
            } catch (Exception ignored) {
            }
        }
        return 0;
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
