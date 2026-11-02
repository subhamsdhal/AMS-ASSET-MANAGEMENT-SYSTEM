package com.mycompany.asset_management_system_ams.storage;

import java.io.InputStream;

public interface StorageService {
    /**
     * Uploads a file to the persistent storage.
     * @param objectPath The logical path/key of the object (e.g. "assets/123/uuid-file.jpg")
     * @param fileStream The input stream of the file content
     * @param contentType The MIME type of the file
     * @param size The size of the file in bytes
     * @return The final object path
     * @throws Exception if upload fails
     */
    String uploadFile(String objectPath, InputStream fileStream, String contentType, long size) throws Exception;

    /**
     * Downloads a file from the persistent storage.
     * @param objectPath The logical path/key of the object
     * @return InputStream of the file content
     * @throws Exception if download fails
     */
    InputStream downloadFile(String objectPath) throws Exception;

    /**
     * Deletes a file from the persistent storage.
     * @param objectPath The logical path/key of the object
     * @return true if deleted, false if not found
     * @throws Exception if deletion fails
     */
    boolean deleteFile(String objectPath) throws Exception;
    
    /**
     * Returns the configured public base URL or generates a signed URL if supported.
     * (Currently, the app will use DownloadFromCloudStorageServlet for authenticated downloads).
     */
    String getFileUrl(String objectPath);
}
