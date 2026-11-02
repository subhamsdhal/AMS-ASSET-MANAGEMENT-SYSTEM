package com.mycompany.asset_management_system_ams;

import java.sql.Connection;
import java.sql.DriverManager;
import java.util.Properties;
import java.util.logging.Level;
import java.util.logging.Logger;

public class DBConnection {

    private static final Logger LOGGER = Logger.getLogger(DBConnection.class.getName());

    // No hardcoded credential fallback: getDbUser()/getDbPassword() require an
    // explicit value from AMS_DB_* environment variables or db.properties. The
    // shipped src/main/resources/db.properties already supplies local-dev
    // defaults (root/root), so this is not a behavior change for anyone running
    // the standard local setup - it only removes a second, hidden copy of the
    // same credential baked into the compiled class.
    private static final String DEFAULT_DB_URL =
            "jdbc:mysql://localhost:3306/asset_management_system"
            + "?useSSL=false"
            + "&allowPublicKeyRetrieval=true"
            + "&serverTimezone=Asia/Kolkata";

    private static final Properties DB_PROPERTIES = loadDbProperties();

    public static Connection getConnection() {
        try {
            Class.forName("com.mysql.cj.jdbc.Driver");

            String user = getDbUser();
            String password = getDbPassword();

            if (user.isEmpty()) {
                LOGGER.log(Level.SEVERE, "Database connection failed: no DB user configured. "
                        + "Set AMS_DB_USER or db.user in db.properties.");
                return null;
            }

            return DriverManager.getConnection(getDbUrl(), user, password);

        } catch (Exception e) {
            LOGGER.log(Level.SEVERE, "Database connection failed. Check db.properties or AMS_DB_* environment variables.", e);
            return null;
        }
    }

    public static String getDbUrl() {
        return firstNonBlank(
                System.getenv("AMS_DB_URL"),
                DB_PROPERTIES.getProperty("db.url"),
                DEFAULT_DB_URL
        );
    }

    public static String getDbUser() {
        return firstNonBlank(
                System.getenv("AMS_DB_USER"),
                DB_PROPERTIES.getProperty("db.user"),
                ""
        );
    }

    public static String getMaskedDbUrl() {
        String url = getDbUrl();

        if (url == null || url.trim().isEmpty()) {
            return "not configured";
        }

        return url.replaceAll("(?i)(password=)[^&;]+", "$1****");
    }

    public static boolean isLocalDatabase() {
        String url = getDbUrl().toLowerCase();
        return url.contains("localhost")
                || url.contains("127.0.0.1")
                || url.contains("//[::1]")
                || url.contains("//0:0:0:0:0:0:0:1");
    }

    private static String getDbPassword() {
        return firstNonBlank(
                System.getenv("AMS_DB_PASSWORD"),
                DB_PROPERTIES.getProperty("db.password"),
                ""
        );
    }

    private static Properties loadDbProperties() {
        Properties properties = new Properties();

        try (java.io.InputStream input = DBConnection.class
                .getClassLoader()
                .getResourceAsStream("db.properties")) {

            if (input != null) {
                properties.load(input);
            }

        } catch (Exception e) {
            LOGGER.log(Level.WARNING, "Unable to load db.properties. Environment variables/defaults will be used.", e);
        }

        return properties;
    }

    private static String firstNonBlank(String first, String second, String third) {
        if (first != null && !first.trim().isEmpty()) {
            return first.trim();
        }

        if (second != null && !second.trim().isEmpty()) {
            return second.trim();
        }

        return third == null ? "" : third.trim();
    }
}
