package com.mycompany.asset_management_system_ams.storage;

import com.google.cloud.storage.Blob;
import com.google.cloud.storage.BlobId;
import com.google.cloud.storage.BlobInfo;
import com.google.cloud.storage.Storage;
import com.google.cloud.storage.StorageOptions;
import java.io.InputStream;
import java.nio.channels.Channels;
import java.util.logging.Level;
import java.util.logging.Logger;

public class GoogleCloudStorageService implements StorageService {
    private static final Logger LOGGER = Logger.getLogger(GoogleCloudStorageService.class.getName());
    private final Storage storage;
    private final String bucketName;

    public GoogleCloudStorageService() {
        this.bucketName = System.getenv("AMS_STORAGE_BUCKET");
        if (this.bucketName == null || this.bucketName.trim().isEmpty()) {
            throw new IllegalStateException("AMS_STORAGE_BUCKET environment variable is not set. Production GCS cannot start.");
        }
        
        // This implicitly uses Application Default Credentials. 
        // In Cloud Run, it uses the service account identity.
        try {
            this.storage = StorageOptions.getDefaultInstance().getService();
        } catch (Exception e) {
            throw new IllegalStateException("Failed to initialize Google Cloud Storage service. Ensure ADC is configured.", e);
        }
    }

    @Override
    public String uploadFile(String objectPath, InputStream fileStream, String contentType, long size) throws Exception {
        BlobId blobId = BlobId.of(bucketName, objectPath);
        BlobInfo blobInfo = BlobInfo.newBuilder(blobId).setContentType(contentType).build();
        
        // Use try-with-resources if using WriteChannel, but createFrom handles stream upload directly.
        storage.createFrom(blobInfo, fileStream);
        LOGGER.log(Level.INFO, "Uploaded file to GCS: gs://{0}/{1}", new Object[]{bucketName, objectPath});
        return objectPath;
    }

    @Override
    public InputStream downloadFile(String objectPath) throws Exception {
        Blob blob = storage.get(BlobId.of(bucketName, objectPath));
        if (blob == null || !blob.exists()) {
            throw new java.io.FileNotFoundException("Object " + objectPath + " not found in GCS bucket " + bucketName);
        }
        return Channels.newInputStream(blob.reader());
    }

    @Override
    public boolean deleteFile(String objectPath) throws Exception {
        boolean deleted = storage.delete(BlobId.of(bucketName, objectPath));
        if (deleted) {
            LOGGER.log(Level.INFO, "Deleted file from GCS: gs://{0}/{1}", new Object[]{bucketName, objectPath});
        } else {
            LOGGER.log(Level.WARNING, "Failed to delete or file not found in GCS: gs://{0}/{1}", new Object[]{bucketName, objectPath});
        }
        return deleted;
    }
    
    @Override
    public String getFileUrl(String objectPath) {
        return objectPath; // Rely on explicit servlets to construct the URLs
    }
}
