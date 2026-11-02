package com.mycompany.asset_management_system_ams;

import jakarta.servlet.ServletException;
import jakarta.servlet.annotation.MultipartConfig;
import jakarta.servlet.annotation.WebServlet;
import jakarta.servlet.http.HttpServlet;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import jakarta.servlet.http.HttpSession;
import java.io.IOException;
import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;

@WebServlet(name = "UploadAssetDocumentServlet", urlPatterns = {"/UploadAssetDocumentServlet"})
@MultipartConfig(
        fileSizeThreshold = 1024 * 1024,
        maxFileSize = 10 * 1024 * 1024,
        maxRequestSize = 12 * 1024 * 1024
)
public class UploadAssetDocumentServlet extends HttpServlet {

    @Override
    protected void doPost(HttpServletRequest request, HttpServletResponse response)
            throws ServletException, IOException {

        int assetId = 0;

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
            int userId = getSessionInt(session, "user_id", 1);

            if (userId == 1) {
                userId = getSessionInt(session, "userId", 1);
            }

            if (!("SUPER_ADMIN".equals(role) || "ADMIN".equals(role)) && !"ASSET_MANAGER".equalsIgnoreCase(role)) {
                response.sendRedirect("view_asset.jsp?id=" + safeRedirectId(request.getParameter("assetId")) + "&error=document_denied");
                return;
            }

            assetId = parseInt(request.getParameter("assetId"), 0);
            String documentType = AssetDocumentDAO.normalizeDocumentType(request.getParameter("documentType"));

            if (assetId <= 0) {
                response.sendRedirect("assets.jsp?error=invalid_asset");
                return;
            }

            String assetCode = getAssetCode(assetId);

            if (assetCode.trim().isEmpty()) {
                response.sendRedirect("assets.jsp?error=asset_notfound");
                return;
            }

            AssetDocumentUploadUtil.SavedDocument savedDocument;

            try {
                savedDocument = AssetDocumentUploadUtil.saveAssetDocument(
                        request,
                        "assetDocument",
                        assetCode,
                        documentType
                );
            } catch (AssetDocumentUploadUtil.UploadException | IllegalStateException uploadEx) {
                AuditDAO.log(
                        userId,
                        "DOCUMENT_UPLOAD_BLOCKED",
                        "asset_documents",
                        assetId,
                        "Asset document upload blocked. Asset ID: " + assetId
                        + ", Reason: " + uploadEx.getMessage()
                        + ", Attempted by: " + username
                );

                response.sendRedirect("view_asset.jsp?id=" + assetId + "&error=document_upload");
                return;
            }

            AssetDocumentDAO dao = new AssetDocumentDAO();
            int documentId = dao.addDocument(
                    assetId,
                    documentType,
                    savedDocument.getOriginalFileName(),
                    savedDocument.getStoredFilePath(),
                    savedDocument.getMimeType(),
                    savedDocument.getFileSize(),
                    userId
            );

            if (documentId > 0) {
                // Perform document text extraction
                String realPath = request.getServletContext().getRealPath("/") + savedDocument.getStoredFilePath();
                String extractedText = DocumentTextExtractor.extractText(realPath, savedDocument.getMimeType());
                dao.indexDocumentText(documentId, assetId, savedDocument.getOriginalFileName(), extractedText, userId);

                AuditDAO.log(
                        userId,
                        "DOCUMENT_UPLOAD",
                        "asset_documents",
                        documentId,
                        "Asset document uploaded. Asset ID: " + assetId
                        + ", Type: " + documentType
                        + ", File: " + savedDocument.getOriginalFileName()
                        + ", Uploaded by: " + username
                );

                response.sendRedirect("view_asset.jsp?id=" + assetId + "&msg=document_added");
            } else {
                AssetDocumentUploadUtil.deleteIfManaged(savedDocument.getStoredFilePath());

                AuditDAO.log(
                        userId,
                        "DOCUMENT_UPLOAD_FAILED",
                        "asset_documents",
                        assetId,
                        "Asset document upload failed during database insert. Asset ID: " + assetId
                        + ", Uploaded by: " + username
                );

                response.sendRedirect("view_asset.jsp?id=" + assetId + "&error=document_upload");
            }

        } catch (Exception e) {
            e.printStackTrace();

            if (assetId > 0) {
                response.sendRedirect("view_asset.jsp?id=" + assetId + "&error=document_upload");
            } else {
                response.sendRedirect("assets.jsp?error=server");
            }
        }
    }

    private String getAssetCode(int assetId) {
        String sql = "SELECT asset_code FROM assets WHERE asset_id = ? LIMIT 1";

        try (Connection con = DBConnection.getConnection();
             PreparedStatement ps = con.prepareStatement(sql)) {

            ps.setInt(1, assetId);

            try (ResultSet rs = ps.executeQuery()) {
                if (rs.next()) {
                    return clean(rs.getString("asset_code"));
                }
            }

        } catch (Exception e) {
            e.printStackTrace();
        }

        return "";
    }

    private int getSessionInt(HttpSession session, String key, int fallback) {
        try {
            Object value = session.getAttribute(key);

            if (value == null) {
                return fallback;
            }

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
