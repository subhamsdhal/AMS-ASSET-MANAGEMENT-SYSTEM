package com.mycompany.asset_management_system_ams.storage;

import java.util.logging.Level;
import java.util.logging.Logger;

public class StorageServiceFactory {
    private static final Logger LOGGER = Logger.getLogger(StorageServiceFactory.class.getName());
    private static StorageService instance;

    public static synchronized StorageService getInstance() {
        if (instance == null) {
            String provider = System.getenv("AMS_STORAGE_PROVIDER");
            if (provider == null || provider.trim().isEmpty()) {
                // If AMS_ENV=production, or missing, we default to GCS for safety in production.
                // We do NOT fallback to LocalStorageService silently.
                String env = System.getenv("AMS_ENV");
                if ("development".equalsIgnoreCase(env)) {
                    LOGGER.log(Level.WARNING, "AMS_STORAGE_PROVIDER is not set, but AMS_ENV=development. Falling back to LocalStorageService.");
                    instance = new LocalStorageService();
                } else {
                    LOGGER.log(Level.INFO, "AMS_STORAGE_PROVIDER is not set. Defaulting to GoogleCloudStorageService for production.");
                    instance = new GoogleCloudStorageService();
                }
            } else if ("local".equalsIgnoreCase(provider.trim())) {
                LOGGER.log(Level.INFO, "Using LocalStorageService as requested by AMS_STORAGE_PROVIDER=local");
                instance = new LocalStorageService();
            } else if ("gcs".equalsIgnoreCase(provider.trim())) {
                LOGGER.log(Level.INFO, "Using GoogleCloudStorageService as requested by AMS_STORAGE_PROVIDER=gcs");
                instance = new GoogleCloudStorageService();
            } else {
                throw new IllegalStateException("Unknown AMS_STORAGE_PROVIDER: " + provider);
            }
        }
        return instance;
    }
}
