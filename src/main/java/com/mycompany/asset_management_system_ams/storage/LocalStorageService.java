package com.mycompany.asset_management_system_ams.storage;

import java.io.InputStream;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.nio.file.StandardCopyOption;
import java.util.logging.Level;
import java.util.logging.Logger;

public class LocalStorageService implements StorageService {
    private static final Logger LOGGER = Logger.getLogger(LocalStorageService.class.getName());
    private final Path rootDir;

    public LocalStorageService() {
        String baseDir = System.getenv("AMS_LOCAL_STORAGE_DIR");
        if (baseDir == null || baseDir.trim().isEmpty()) {
            baseDir = System.getProperty("user.home") + "/AMS_Local_Storage";
        }
        this.rootDir = Paths.get(baseDir).normalize().toAbsolutePath();
        try {
            if (!Files.exists(rootDir)) {
                Files.createDirectories(rootDir);
            }
            LOGGER.log(Level.INFO, "LocalStorageService initialized at {0}", rootDir.toString());
        } catch (Exception e) {
            throw new IllegalStateException("Failed to initialize LocalStorageService at " + rootDir, e);
        }
    }

    @Override
    public String uploadFile(String objectPath, InputStream fileStream, String contentType, long size) throws Exception {
        Path targetPath = rootDir.resolve(objectPath).normalize();
        if (!targetPath.startsWith(rootDir)) {
            throw new SecurityException("Path traversal attempt detected in upload");
        }
        
        Files.createDirectories(targetPath.getParent());
        Files.copy(fileStream, targetPath, StandardCopyOption.REPLACE_EXISTING);
        LOGGER.log(Level.INFO, "Saved file locally: {0}", targetPath);
        return objectPath;
    }

    @Override
    public InputStream downloadFile(String objectPath) throws Exception {
        Path targetPath = rootDir.resolve(objectPath).normalize();
        if (!targetPath.startsWith(rootDir)) {
            throw new SecurityException("Path traversal attempt detected in download");
        }
        if (!Files.exists(targetPath)) {
            throw new java.io.FileNotFoundException("Local file not found: " + targetPath);
        }
        return Files.newInputStream(targetPath);
    }

    @Override
    public boolean deleteFile(String objectPath) throws Exception {
        Path targetPath = rootDir.resolve(objectPath).normalize();
        if (!targetPath.startsWith(rootDir)) {
            return false;
        }
        boolean deleted = Files.deleteIfExists(targetPath);
        if (deleted) {
            LOGGER.log(Level.INFO, "Deleted local file: {0}", targetPath);
        }
        return deleted;
    }
    
    @Override
    public String getFileUrl(String objectPath) {
        return objectPath;
    }
}
