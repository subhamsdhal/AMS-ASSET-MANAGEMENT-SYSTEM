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
import java.util.HashMap;
import java.util.HashSet;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import java.util.UUID;

public final class AssetDocumentUploadUtil {

    private static final long MAX_DOCUMENT_SIZE_BYTES = 10L * 1024L * 1024L;
    private static final Set<String> ALLOWED_EXTENSIONS = new HashSet<>(
            Arrays.asList("pdf", "jpg", "jpeg", "png", "webp", "doc", "docx", "xls", "xlsx", "csv")
    );

    // DownloadAssetDocumentServlet serves documents back with whatever content
    // type is stored for them, as a forced "attachment" download - a real but
    // secondary mitigation, not the actual control. The actual control belongs
    // here: derive the stored content type from the validated extension
    // server-side, instead of trusting documentPart.getContentType(), which is
    // just the multipart Content-Type header the uploading browser/client sent
    // and is trivial to spoof (e.g. upload a .pdf with the request's Content-Type
    // manually set to text/html). Unrelated to AssetImageUploadUtil's separate
    // content-type check, which validates the client header against a whitelist
    // rather than ignoring it - either approach works; deriving it removes the
    // client-supplied value from the trust chain entirely for this path.
    private static final Map<String, String> CONTENT_TYPE_BY_EXTENSION = buildContentTypeMap();

    private static Map<String, String> buildContentTypeMap() {
        Map<String, String> map = new HashMap<>();
        map.put("pdf", "application/pdf");
        map.put("jpg", "image/jpeg");
        map.put("jpeg", "image/jpeg");
        map.put("png", "image/png");
        map.put("webp", "image/webp");
        map.put("doc", "application/msword");
        map.put("docx", "application/vnd.openxmlformats-officedocument.wordprocessingml.document");
        map.put("xls", "application/vnd.ms-excel");
        map.put("xlsx", "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet");
        map.put("csv", "text/csv");
        return map;
    }

    private AssetDocumentUploadUtil() {
    }

    public static SavedDocument saveAssetDocument(
            HttpServletRequest request,
            String fieldName,
            String assetCode,
            String documentType) throws IOException, ServletException, UploadException {

        Part documentPart = request.getPart(fieldName);

        if (documentPart == null || documentPart.getSize() <= 0) {
            throw new UploadException("Please choose a document to upload.");
        }

        if (documentPart.getSize() > MAX_DOCUMENT_SIZE_BYTES) {
            throw new UploadException("Asset document must be 10 MB or smaller.");
        }

        String submittedName = documentPart.getSubmittedFileName();

        if (submittedName == null || submittedName.trim().isEmpty()) {
            throw new UploadException("Uploaded document name is missing.");
        }

        String originalFileName = Paths.get(submittedName).getFileName().toString();
        String extension = extensionOf(originalFileName);

        if (!ALLOWED_EXTENSIONS.contains(extension)) {
            throw new UploadException("Allowed document types: PDF, JPG, JPEG, PNG, WEBP, DOC, DOCX, XLS, XLSX, CSV.");
        }

        String safeAssetCode = sanitizeFilePart(assetCode);

        String safeType = AssetDocumentDAO.normalizeDocumentType(documentType).toLowerCase(Locale.ENGLISH);
        String storedName = safeType
                + "-"
                + System.currentTimeMillis()
                + "-"
                + UUID.randomUUID().toString().substring(0, 8)
                + "."
                + extension;

        String relativePath = "documents/asset-documents/" + safeAssetCode + "/" + storedName;
        String derivedContentType = CONTENT_TYPE_BY_EXTENSION.getOrDefault(extension, "application/octet-stream");

        try (InputStream input = documentPart.getInputStream()) {
            com.mycompany.asset_management_system_ams.storage.StorageServiceFactory.getInstance()
                .uploadFile(relativePath, input, derivedContentType, documentPart.getSize());
        } catch (Exception e) {
            throw new UploadException("Failed to upload document to storage: " + e.getMessage());
        }


        return new SavedDocument(
                originalFileName,
                relativePath,
                derivedContentType,
                documentPart.getSize()
        );
    }

    public static void deleteIfManaged(String relativePath) {
        try {
            if (relativePath != null && !relativePath.trim().isEmpty()) {
                com.mycompany.asset_management_system_ams.storage.StorageServiceFactory.getInstance().deleteFile(relativePath);
            }
        } catch (Exception ignored) {
            // File cleanup is best effort; database updates should not fail because a file is locked.
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

    public static class SavedDocument {

        private final String originalFileName;
        private final String storedFilePath;
        private final String mimeType;
        private final long fileSize;

        public SavedDocument(String originalFileName, String storedFilePath, String mimeType, long fileSize) {
            this.originalFileName = originalFileName;
            this.storedFilePath = storedFilePath;
            this.mimeType = mimeType;
            this.fileSize = fileSize;
        }

        public String getOriginalFileName() {
            return originalFileName;
        }

        public String getStoredFilePath() {
            return storedFilePath;
        }

        public String getMimeType() {
            return mimeType;
        }

        public long getFileSize() {
            return fileSize;
        }
    }

    public static class UploadException extends Exception {

        public UploadException(String message) {
            super(message);
        }
    }
}
