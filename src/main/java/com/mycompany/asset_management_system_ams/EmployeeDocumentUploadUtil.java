package com.mycompany.asset_management_system_ams;

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

public final class EmployeeDocumentUploadUtil {

    private static final long MAX_DOCUMENT_SIZE_BYTES = 5L * 1024L * 1024L; // 5 MB
    private static final Set<String> ALLOWED_EXTENSIONS = new HashSet<>(
            Arrays.asList("pdf", "jpg", "jpeg", "png", "doc", "docx")
    );

    // DownloadEmployeeDocumentServlet serves these back with Content-Disposition:
    // inline (not a forced attachment download, unlike the asset-document path),
    // so a spoofed client Content-Type header here would render directly as live
    // HTML in the app's own authenticated origin - a real stored-XSS-via-upload
    // path, not just a theoretical one. Mirrors the fix already applied to
    // AssetDocumentUploadUtil: derive the stored content type from the
    // already-validated extension server-side instead of trusting
    // documentPart.getContentType(), which is just the multipart Content-Type
    // header the uploading client sent and is trivial to spoof.
    private static final Map<String, String> CONTENT_TYPE_BY_EXTENSION = buildContentTypeMap();

    private static Map<String, String> buildContentTypeMap() {
        Map<String, String> map = new HashMap<>();
        map.put("pdf", "application/pdf");
        map.put("jpg", "image/jpeg");
        map.put("jpeg", "image/jpeg");
        map.put("png", "image/png");
        map.put("doc", "application/msword");
        map.put("docx", "application/vnd.openxmlformats-officedocument.wordprocessingml.document");
        return map;
    }

    private EmployeeDocumentUploadUtil() {
    }

    public static SavedDocument saveEmployeeDocument(
            HttpServletRequest request,
            String fieldName,
            int employeeId) throws IOException, ServletException, UploadException {

        Part documentPart = request.getPart(fieldName);

        if (documentPart == null || documentPart.getSize() <= 0) {
            throw new UploadException("Please choose a document to upload.");
        }

        if (documentPart.getSize() > MAX_DOCUMENT_SIZE_BYTES) {
            throw new UploadException("Employee document must be 5 MB or smaller.");
        }

        String submittedName = documentPart.getSubmittedFileName();

        if (submittedName == null || submittedName.trim().isEmpty()) {
            throw new UploadException("Uploaded document name is missing.");
        }

        String originalFileName = Paths.get(submittedName).getFileName().toString();
        String extension = extensionOf(originalFileName);

        if (!ALLOWED_EXTENSIONS.contains(extension)) {
            throw new UploadException("Allowed document types: PDF, JPG, JPEG, PNG, DOC, DOCX.");
        }

        String storedName = employeeId
                + "_"
                + System.currentTimeMillis()
                + "_"
                + UUID.randomUUID().toString().substring(0, 8)
                + "."
                + extension;

        String relativePath = "documents/employee_documents/" + storedName;
        
        // Derived from the already-validated extension, not read from
        // documentPart.getContentType() - see the note on CONTENT_TYPE_BY_EXTENSION above.
        String derivedContentType = CONTENT_TYPE_BY_EXTENSION.getOrDefault(extension, "application/octet-stream");

        try (InputStream input = documentPart.getInputStream()) {
            com.mycompany.asset_management_system_ams.storage.StorageServiceFactory.getInstance()
                .uploadFile(relativePath, input, derivedContentType, documentPart.getSize());
        } catch (Exception e) {
            throw new UploadException("Failed to upload employee document to storage: " + e.getMessage());
        }


        return new SavedDocument(
                originalFileName,
                storedName,
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
            // File cleanup is best effort
        }
    }

    private static String extensionOf(String fileName) {
        int dot = fileName.lastIndexOf('.');
        if (dot < 0 || dot == fileName.length() - 1) {
            return "";
        }
        return fileName.substring(dot + 1).toLowerCase(Locale.ENGLISH);
    }

    public static class SavedDocument {
        private final String originalFileName;
        private final String storedFileName;
        private final String storedFilePath;
        private final String mimeType;
        private final long fileSize;

        public SavedDocument(String originalFileName, String storedFileName, String storedFilePath, String mimeType, long fileSize) {
            this.originalFileName = originalFileName;
            this.storedFileName = storedFileName;
            this.storedFilePath = storedFilePath;
            this.mimeType = mimeType;
            this.fileSize = fileSize;
        }

        public String getOriginalFileName() {
            return originalFileName;
        }

        public String getStoredFileName() {
            return storedFileName;
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
