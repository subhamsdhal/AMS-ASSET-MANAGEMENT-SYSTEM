package com.mycompany.asset_management_system_ams;

import jakarta.servlet.ServletContext;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.Part;
import java.io.IOException;
import java.io.InputStream;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.nio.file.StandardCopyOption;
import java.util.Arrays;
import java.util.HashSet;
import java.util.Locale;
import java.util.Set;
import java.util.UUID;

public final class AssetImageUploadUtil {

    private static final long MAX_IMAGE_SIZE_BYTES = 5L * 1024L * 1024L;
    private static final Set<String> ALLOWED_EXTENSIONS = new HashSet<>(
            Arrays.asList("jpg", "jpeg", "png", "webp")
    );
    private static final Set<String> ALLOWED_CONTENT_TYPES = new HashSet<>(
            Arrays.asList("image/jpeg", "image/png", "image/webp")
    );

    private AssetImageUploadUtil() {
    }

    public static String saveAssetImage(HttpServletRequest request, String fieldName, String assetCode)
            throws IOException, ServletException, UploadException {

        Part imagePart = request.getPart(fieldName);

        if (imagePart == null || imagePart.getSize() <= 0) {
            return "";
        }

        if (imagePart.getSize() > MAX_IMAGE_SIZE_BYTES) {
            throw new UploadException("Asset image must be 5 MB or smaller.");
        }

        String submittedName = imagePart.getSubmittedFileName();

        if (submittedName == null || submittedName.trim().isEmpty()) {
            return "";
        }

        String fileName = Paths.get(submittedName).getFileName().toString();
        String extension = extensionOf(fileName);

        if (!ALLOWED_EXTENSIONS.contains(extension)) {
            throw new UploadException("Only JPG, JPEG, PNG, and WEBP asset images are allowed.");
        }

        String contentType = imagePart.getContentType();

        if (contentType != null
                && !contentType.trim().isEmpty()
                && !ALLOWED_CONTENT_TYPES.contains(contentType.toLowerCase(Locale.ENGLISH))) {
            throw new UploadException("Uploaded asset image content type is not allowed.");
        }

        String safeAssetCode = sanitizeFilePart(assetCode);
        String storedName = safeAssetCode
                + "-"
                + System.currentTimeMillis()
                + "-"
                + UUID.randomUUID().toString().substring(0, 8)
                + "."
                + extension;

        String relativePath = "assets/" + storedName;
        
        try (InputStream input = imagePart.getInputStream()) {
            com.mycompany.asset_management_system_ams.storage.StorageServiceFactory.getInstance()
                .uploadFile(relativePath, input, contentType != null ? contentType : "application/octet-stream", imagePart.getSize());
        } catch (Exception e) {
            throw new UploadException("Failed to upload image to storage: " + e.getMessage());
        }

        return relativePath;
    }

    public static void deleteIfManaged(String relativePath) {
        try {
            if (relativePath != null && !relativePath.trim().isEmpty()) {
                com.mycompany.asset_management_system_ams.storage.StorageServiceFactory.getInstance().deleteFile(relativePath);
            }
        } catch (Exception ignored) {
            // Cleanup is best-effort; database updates should not fail because an old file is locked.
        }
    }

    private static String extensionOf(String fileName) {
        int dot = fileName.lastIndexOf('.');

        if (dot < 0 || dot == fileName.length() - 1) {
            return "";
        }

        return fileName.substring(dot + 1).toLowerCase(Locale.ENGLISH);
    }

    private static String sanitizeFilePart(String value) {
        String safe = value == null ? "" : value.trim().toUpperCase(Locale.ENGLISH)
                .replaceAll("[^A-Z0-9_-]", "-")
                .replaceAll("-+", "-");

        if (safe.isEmpty()) {
            safe = "ASSET";
        }

        if (safe.length() > 50) {
            safe = safe.substring(0, 50);
        }

        return safe;
    }

    public static class UploadException extends Exception {

        public UploadException(String message) {
            super(message);
        }
    }
}
