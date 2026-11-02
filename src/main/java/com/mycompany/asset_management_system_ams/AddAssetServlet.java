package com.mycompany.asset_management_system_ams;

import java.io.IOException;
import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.time.LocalDate;

import jakarta.servlet.ServletException;
import jakarta.servlet.annotation.MultipartConfig;
import jakarta.servlet.annotation.WebServlet;
import jakarta.servlet.http.HttpServlet;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import jakarta.servlet.http.HttpSession;

@WebServlet(name = "AddAssetServlet", urlPatterns = {"/AddAssetServlet"})
// Fault: limits were sized for just the asset photo (5MB) - now that this
// form also accepts an optional supporting document (up to 10MB, matching
// UploadAssetDocumentServlet's own limit), a request carrying both files at
// once could exceed the old 8MB maxRequestSize and fail outright. Bumped to
// fit the larger of the two per-file limits plus both files together with
// headroom, rather than the smaller photo-only sizing.
@MultipartConfig(
        fileSizeThreshold = 1024 * 1024,
        maxFileSize = 10 * 1024 * 1024,
        maxRequestSize = 18 * 1024 * 1024
)
public class AddAssetServlet extends HttpServlet {

    @Override
    protected void doPost(HttpServletRequest request, HttpServletResponse response)
            throws ServletException, IOException {

        HttpSession session = request.getSession(false);

        try {
            request.setCharacterEncoding("UTF-8");

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

            if (!RoleAccessUtil.hasAccess(role, request.getRequestURI())) {
                response.sendRedirect("assets.jsp?access=denied");
                return;
            }

            String assetCode = clean(request.getParameter("assetCode"));
            String assetName = clean(request.getParameter("assetName"));

            int categoryId = parseInt(request.getParameter("categoryId"), 0);
            int vendorId = parseInt(request.getParameter("vendorId"), 0);

            String serialNumber = clean(request.getParameter("serialNumber"));
            String location = clean(request.getParameter("location"));

            String purchaseDate = clean(request.getParameter("purchaseDate"));
            double purchaseCost = parseDouble(request.getParameter("purchaseCost"), -1);

            String warrantyExpiry = clean(request.getParameter("warrantyExpiry"));
            double depreciationRate = parseDouble(request.getParameter("depreciationRate"), -1);

            int departmentId = parseInt(request.getParameter("departmentId"), 0);
            int divisionId = parseInt(request.getParameter("divisionId"), 0);
            int locationId = parseInt(request.getParameter("locationId"), 0);

            String qrCode = buildAutoQrCode(assetCode);
            String assetStatus = "AVAILABLE";
            String assetImagePath = "";

            if (assetCode.isEmpty()
                    || assetName.isEmpty()
                    || categoryId <= 0
                    || vendorId <= 0
                    || serialNumber.isEmpty()
                    || (location.isEmpty() && locationId <= 0)
                    || purchaseDate.isEmpty()
                    || warrantyExpiry.isEmpty()
                    || purchaseCost < 0
                    || depreciationRate < 0) {

                AuditDAO.log(
                        userId,
                        "ADD_BLOCKED",
                        "assets",
                        0,
                        "Asset add blocked due to invalid/missing form details. Attempted by: " + username
                );

                response.sendRedirect("add_asset.jsp?error=failed");
                return;
            }
            
            AssetDAO dao = new AssetDAO();
            if (dao.isAssetCodeExists(assetCode, -1)) {
                response.sendRedirect("add_asset.jsp?error=duplicate_code&assetCode=" + java.net.URLEncoder.encode(assetCode, "UTF-8"));
                return;
            }
            LocalDate purchaseLocalDate;
            LocalDate warrantyLocalDate;

            try {
                purchaseLocalDate = LocalDate.parse(purchaseDate);
                warrantyLocalDate = LocalDate.parse(warrantyExpiry);
            } catch (Exception ex) {
                AuditDAO.log(
                        userId,
                        "ADD_BLOCKED",
                        "assets",
                        0,
                        "Asset add blocked due to invalid date format. Attempted by: " + username
                );

                response.sendRedirect("add_asset.jsp?error=invaliddate");
                return;
            }

            if (purchaseLocalDate.isAfter(LocalDate.now())
                    || warrantyLocalDate.isBefore(purchaseLocalDate)) {

                AuditDAO.log(
                        userId,
                        "ADD_BLOCKED",
                        "assets",
                        0,
                        "Asset add blocked due to invalid date rule. "
                        + "Purchase Date: " + purchaseDate
                        + ", Warranty Expiry: " + warrantyExpiry
                        + ", Attempted by: " + username
                );

                response.sendRedirect("add_asset.jsp?error=invaliddate");
                return;
            }

            if (!isValidCategorySupplier(categoryId, vendorId)) {
                AuditDAO.log(
                        userId,
                        "ADD_BLOCKED",
                        "assets",
                        0,
                        "Asset add blocked due to invalid category-supplier combination. "
                        + "Category ID: " + categoryId
                        + ", Supplier ID: " + vendorId
                        + ", Attempted by: " + username
                );

                response.sendRedirect("add_asset.jsp?error=invalidvendor");
                return;
            }
            // dao is already declared above
            if (dao.isDuplicateAssetCodeOrSerial(assetCode, serialNumber, -1)) {
                AuditDAO.log(
                        userId,
                        "ADD_BLOCKED",
                        "assets",
                        0,
                        "Asset add blocked due to duplicate Asset Code or Serial Number. "
                        + "Asset Code: " + assetCode
                        + ", Serial Number: " + serialNumber
                        + ", Attempted by: " + username
                );

                response.sendRedirect("add_asset.jsp?error=duplicate");
                return;
            }

            try {
                assetImagePath = AssetImageUploadUtil.saveAssetImage(request, "assetImage", assetCode);
            } catch (AssetImageUploadUtil.UploadException | IllegalStateException uploadEx) {
                AuditDAO.log(
                        userId,
                        "ADD_BLOCKED",
                        "assets",
                        0,
                        "Asset add blocked due to invalid image upload. "
                        + "Asset Code: " + assetCode
                        + ", Reason: " + uploadEx.getMessage()
                        + ", Attempted by: " + username
                );

                response.sendRedirect("add_asset.jsp?error=invalidfile");
                return;
            }

            boolean inserted = dao.addAsset(
                    assetCode,
                    assetName,
                    categoryId,
                    vendorId,
                    serialNumber,
                    qrCode,
                    location,
                    purchaseDate,
                    purchaseCost,
                    warrantyExpiry,
                    depreciationRate,
                    assetStatus,
                    assetImagePath,
                    departmentId,
                    divisionId,
                    locationId
            );

            if (inserted) {

                AuditDAO.log(
                        userId,
                        "ADD",
                        "assets",
                        0,
                        "New asset added: " + assetCode + " - " + assetName
                        + ", Auto QR: " + qrCode
                        + ", Category ID: " + categoryId
                        + ", Supplier ID: " + vendorId
                        + ", Initial Status: AVAILABLE"
                        + ", Added by: " + username
                );

                try {
                    NotificationEventService.sendAssetAddedNotice(
                            getServletContext(),
                            0,
                            assetCode,
                            assetName,
                            categoryId,
                            vendorId,
                            serialNumber,
                            location,
                            purchaseDate,
                            warrantyExpiry,
                            purchaseCost,
                            username,
                            role,
                            NotificationHelper.getUserEmailByUsername(username)
                    );
                } catch (Exception notificationEx) {
                    notificationEx.printStackTrace();
                }

                // ------- Handle Optional Document Upload (same pattern as
                // AddEmployeeServlet's optional-document-at-creation flow) -------
                // addAsset() above only returns success/failure, not the new row's
                // ID (unlike some other DAO methods) - assetCode is unique (already
                // checked above), so look the new asset_id up by it rather than
                // changing addAsset()'s signature/return type for every existing
                // caller just for this one optional step.
                boolean documentFailed = false;
                String documentType = clean(request.getParameter("documentType"));

                if (!documentType.isEmpty()) {
                    jakarta.servlet.http.Part docPart = null;
                    try {
                        docPart = request.getPart("assetDocument");
                    } catch (Exception ignored) {
                        // No file part present - nothing to attach.
                    }

                    if (docPart != null && docPart.getSize() > 0) {
                        int newAssetId = getAssetIdByCode(assetCode);

                        if (newAssetId > 0) {
                            try {
                                AssetDocumentUploadUtil.SavedDocument savedDocument =
                                        AssetDocumentUploadUtil.saveAssetDocument(request, "assetDocument", assetCode, documentType);

                                AssetDocumentDAO docDao = new AssetDocumentDAO();
                                int documentId = docDao.addDocument(
                                        newAssetId,
                                        documentType,
                                        savedDocument.getOriginalFileName(),
                                        savedDocument.getStoredFilePath(),
                                        savedDocument.getMimeType(),
                                        savedDocument.getFileSize(),
                                        userId
                                );

                                if (documentId > 0) {
                                    try {
                                        String realPath = request.getServletContext().getRealPath("/") + savedDocument.getStoredFilePath();
                                        String extractedText = DocumentTextExtractor.extractText(realPath, savedDocument.getMimeType());
                                        docDao.indexDocumentText(documentId, newAssetId, savedDocument.getOriginalFileName(), extractedText, userId);
                                    } catch (Exception indexEx) {
                                        indexEx.printStackTrace();
                                    }

                                    AuditDAO.log(
                                            userId,
                                            "DOCUMENT_UPLOAD",
                                            "asset_documents",
                                            documentId,
                                            "Asset document uploaded during creation. Asset ID: " + newAssetId
                                            + ", Type: " + documentType
                                            + ", File: " + savedDocument.getOriginalFileName()
                                    );
                                } else {
                                    documentFailed = true;
                                    AssetDocumentUploadUtil.deleteIfManaged(savedDocument.getStoredFilePath());
                                }
                            } catch (Exception uploadEx) {
                                uploadEx.printStackTrace();
                                documentFailed = true;
                            }
                        } else {
                            // Should not happen (we just inserted this exact code) -
                            // but if the lookup somehow fails, don't silently drop
                            // the failure; surface it like any other document
                            // upload problem rather than pretending nothing was
                            // attempted.
                            documentFailed = true;
                        }
                    }
                }
                // ------- End Optional Document Upload -------

                response.sendRedirect(documentFailed ? "assets.jsp?msg=added_doc_failed" : "assets.jsp?msg=added");

            } else {
                AssetImageUploadUtil.deleteIfManaged(assetImagePath);

                AuditDAO.log(
                        userId,
                        "ADD_BLOCKED",
                        "assets",
                        0,
                        "Asset add failed from DAO. Possible duplicate Asset Code/QR or invalid supplier mapping. "
                        + "Asset Code: " + assetCode
                        + ", Auto QR: " + qrCode
                        + ", Added by: " + username
                );

                response.sendRedirect("add_asset.jsp?error=failed");
            }

        } catch (Exception e) {
            e.printStackTrace();
            response.sendRedirect("add_asset.jsp?error=server");
        }
    }

    private boolean isValidCategorySupplier(int categoryId, int vendorId) {

        String sql = "SELECT COUNT(*) AS total "
                + "FROM category_vendor_mapping "
                + "WHERE category_id = ? "
                + "AND vendor_id = ? "
                + "AND status = 'ACTIVE'";

        try (
                Connection con = DBConnection.getConnection();
                PreparedStatement ps = con.prepareStatement(sql)
        ) {
            ps.setInt(1, categoryId);
            ps.setInt(2, vendorId);

            try (ResultSet rs = ps.executeQuery()) {
                if (rs.next()) {
                    return rs.getInt("total") > 0;
                }
            }

        } catch (Exception e) {
            e.printStackTrace();
        }

        return false;
    }

    private String buildAutoQrCode(String assetCode) {

        String code = clean(assetCode)
                .toUpperCase()
                .replaceAll("[^A-Z0-9_-]", "-")
                .replaceAll("-+", "-");

        return "IRAMS-" + code;
    }

    private int getAssetIdByCode(String assetCode) {
        String sql = "SELECT asset_id FROM assets WHERE asset_code = ? LIMIT 1";

        try (Connection con = DBConnection.getConnection();
             PreparedStatement ps = con.prepareStatement(sql)) {

            ps.setString(1, assetCode);

            try (ResultSet rs = ps.executeQuery()) {
                if (rs.next()) {
                    return rs.getInt("asset_id");
                }
            }

        } catch (Exception e) {
            e.printStackTrace();
        }

        return 0;
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

    private double parseDouble(String value, double fallback) {
        try {
            return Double.parseDouble(clean(value));
        } catch (Exception e) {
            return fallback;
        }
    }

    private String clean(String value) {
        if (value == null) {
            return "";
        }

        return value.trim();
    }
}
