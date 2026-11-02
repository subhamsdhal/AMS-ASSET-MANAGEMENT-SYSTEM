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

@WebServlet(name = "UpdateAssetServlet", urlPatterns = {"/UpdateAssetServlet"})
@MultipartConfig(
        fileSizeThreshold = 1024 * 1024,
        maxFileSize = 5 * 1024 * 1024,
        maxRequestSize = 8 * 1024 * 1024
)
public class UpdateAssetServlet extends HttpServlet {

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

            if (!RoleAccessUtil.hasAccess(role, request.getRequestURI())) {
                response.sendRedirect("assets.jsp?access=denied");
                return;
            }

            assetId = parseInt(request.getParameter("assetId"), 0);

            String assetCode = clean(request.getParameter("assetCode"));
            String assetName = clean(request.getParameter("assetName"));

            int categoryId = parseInt(request.getParameter("categoryId"), 0);
            int vendorId = parseInt(request.getParameter("vendorId"), 0);

            String serialNumber = clean(request.getParameter("serialNumber"));
            String qrCode = clean(request.getParameter("qrCode"));
            String location = clean(request.getParameter("location"));

            String purchaseDate = clean(request.getParameter("purchaseDate"));
            double purchaseCost = parseDouble(request.getParameter("purchaseCost"), -1);

            String warrantyExpiry = clean(request.getParameter("warrantyExpiry"));
            double depreciationRate = parseDouble(request.getParameter("depreciationRate"), -1);
            
            int departmentId = parseInt(request.getParameter("departmentId"), 0);
            int divisionId = parseInt(request.getParameter("divisionId"), 0);
            int locationId = parseInt(request.getParameter("locationId"), 0);

            if (assetId <= 0
                    || assetCode.isEmpty()
                    || assetName.isEmpty()
                    || categoryId <= 0
                    || vendorId <= 0
                    || serialNumber.isEmpty()
                    || qrCode.isEmpty()
                    || (location.isEmpty() && locationId <= 0)
                    || purchaseDate.isEmpty()
                    || warrantyExpiry.isEmpty()
                    || purchaseCost < 0
                    || depreciationRate < 0) {

                AuditDAO.log(
                        userId,
                        "UPDATE_BLOCKED",
                        "assets",
                        assetId,
                        "Asset update blocked due to invalid/missing form details. Attempted by: " + username
                );

                response.sendRedirect("edit_asset.jsp?id=" + assetId + "&error=failed");
                return;
            }
            
            AssetDAO dao = new AssetDAO();
            if (dao.isAssetCodeExists(assetCode, assetId)) {
                response.sendRedirect("edit_asset.jsp?id=" + assetId + "&error=duplicate_code");
                return;
            }

            Asset existingAsset = dao.getAssetById(assetId);

            if (existingAsset == null) {
                response.sendRedirect("assets.jsp?error=notfound");
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
                        "UPDATE_BLOCKED",
                        "assets",
                        assetId,
                        "Asset update blocked due to invalid date format. Attempted by: " + username
                );

                response.sendRedirect("edit_asset.jsp?id=" + assetId + "&error=invaliddate");
                return;
            }

            if (purchaseLocalDate.isAfter(LocalDate.now())
                    || warrantyLocalDate.isBefore(purchaseLocalDate)) {

                AuditDAO.log(
                        userId,
                        "UPDATE_BLOCKED",
                        "assets",
                        assetId,
                        "Asset update blocked due to invalid date rule. "
                        + "Purchase Date: " + purchaseDate
                        + ", Warranty Expiry: " + warrantyExpiry
                        + ", Attempted by: " + username
                );

                response.sendRedirect("edit_asset.jsp?id=" + assetId + "&error=invaliddate");
                return;
            }

            if (!isValidCategorySupplier(categoryId, vendorId)) {
                AuditDAO.log(
                        userId,
                        "UPDATE_BLOCKED",
                        "assets",
                        assetId,
                        "Asset update blocked due to invalid category-supplier combination. "
                        + "Category ID: " + categoryId
                        + ", Supplier ID: " + vendorId
                        + ", Attempted by: " + username
                );

                response.sendRedirect("edit_asset.jsp?id=" + assetId + "&error=invalidvendor");
                return;
            }

            if (dao.isDuplicateAssetCodeOrSerial(assetCode, serialNumber, assetId)) {
                AuditDAO.log(
                        userId,
                        "UPDATE_BLOCKED",
                        "assets",
                        assetId,
                        "Asset update blocked due to duplicate Asset Code or Serial Number. "
                        + "Asset Code: " + assetCode
                        + ", Serial Number: " + serialNumber
                        + ", Attempted by: " + username
                );

                response.sendRedirect("edit_asset.jsp?id=" + assetId + "&error=duplicate");
                return;
            }

            String uploadedImagePath = "";

            try {
                uploadedImagePath = AssetImageUploadUtil.saveAssetImage(request, "assetImage", assetCode);
            } catch (AssetImageUploadUtil.UploadException | IllegalStateException uploadEx) {
                AuditDAO.log(
                        userId,
                        "UPDATE_BLOCKED",
                        "assets",
                        assetId,
                        "Asset update blocked due to invalid image upload. "
                        + "Asset Code: " + assetCode
                        + ", Reason: " + uploadEx.getMessage()
                        + ", Attempted by: " + username
                );

                response.sendRedirect("edit_asset.jsp?id=" + assetId + "&error=invalidfile");
                return;
            }

            String preservedAssetStatus = existingAsset.getAssetStatus();
            String oldImagePath = existingAsset.getAssetImagePath();

            boolean updated = dao.updateAsset(
                    assetId,
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
                    preservedAssetStatus,
                    uploadedImagePath,
                    departmentId,
                    divisionId,
                    locationId
            );

            if (updated) {
                if (!uploadedImagePath.trim().isEmpty()
                        && oldImagePath != null
                        && !oldImagePath.trim().isEmpty()
                        && !oldImagePath.equals(uploadedImagePath)) {
                    AssetImageUploadUtil.deleteIfManaged(oldImagePath);
                }

                AuditDAO.log(
                        userId,
                        "UPDATE",
                        "assets",
                        assetId,
                        "Asset updated: " + assetCode + " - " + assetName
                        + ", Category ID: " + categoryId
                        + ", Supplier ID: " + vendorId
                        + ", Status preserved as: " + preservedAssetStatus
                        + ", Updated by: " + username
                );

                QrSnapshotService.syncAssetQuietly(assetId);

                try {
                    NotificationEventService.sendAssetUpdatedNotice(
                            getServletContext(),
                            assetId,
                            assetCode,
                            assetName,
                            categoryId,
                            vendorId,
                            serialNumber,
                            location,
                            purchaseDate,
                            warrantyExpiry,
                            purchaseCost,
                            preservedAssetStatus,
                            username,
                            role,
                            NotificationHelper.getUserEmailByUsername(username)
                    );
                } catch (Exception notificationEx) {
                    notificationEx.printStackTrace();
                }

                response.sendRedirect("assets.jsp?msg=updated");

            } else {
                AssetImageUploadUtil.deleteIfManaged(uploadedImagePath);

                AuditDAO.log(
                        userId,
                        "UPDATE_BLOCKED",
                        "assets",
                        assetId,
                        "Asset update failed from DAO. Possible duplicate Asset Code/QR or invalid supplier mapping. "
                        + "Asset Code: " + assetCode
                        + ", Updated by: " + username
                );

                response.sendRedirect("edit_asset.jsp?id=" + assetId + "&error=failed");
            }

        } catch (Exception e) {
            e.printStackTrace();

            if (assetId > 0) {
                response.sendRedirect("edit_asset.jsp?id=" + assetId + "&error=server");
            } else {
                response.sendRedirect("assets.jsp?error=server");
            }
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
