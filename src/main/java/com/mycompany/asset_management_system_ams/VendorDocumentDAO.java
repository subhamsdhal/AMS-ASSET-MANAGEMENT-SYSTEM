package com.mycompany.asset_management_system_ams;

import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.Statement;
import java.sql.Types;
import java.util.ArrayList;
import java.util.List;
import java.util.logging.Level;
import java.util.logging.Logger;

/**
 * VendorDocumentDAO - reads and writes vendor_documents (compliance
 * documents: trade license, GST certificate, PAN, other compliance proof).
 *
 * Was a gap found comparing against a competing team's build of the same
 * brief: this app's vendors already had a gst_number *text field*, but no
 * way to attach the actual license/certificate documents proving it - the
 * competitor's "Add Vendor" form had a document upload for exactly this.
 * Mirrors AssetDocumentDAO/asset_documents exactly (same self-heal-free,
 * schema.sql-defined table pattern, since asset_documents already ships in
 * schema.sql rather than runtime-creating itself).
 */
public class VendorDocumentDAO {

    private static final Logger LOGGER = Logger.getLogger(VendorDocumentDAO.class.getName());
    private static volatile boolean tableEnsured = false;

    private static void ensureTable(Connection con) {
        if (tableEnsured) {
            return;
        }
        String sql = "CREATE TABLE IF NOT EXISTS vendor_documents ("
                + "document_id INT AUTO_INCREMENT PRIMARY KEY, "
                + "vendor_id INT NOT NULL, "
                + "document_type ENUM('TRADE_LICENSE','GST_CERTIFICATE','PAN_CARD','COMPLIANCE_CERTIFICATE','OTHER') NOT NULL DEFAULT 'OTHER', "
                + "original_file_name VARCHAR(255) NOT NULL, "
                + "stored_file_path VARCHAR(500) NOT NULL, "
                + "mime_type VARCHAR(120) DEFAULT NULL, "
                + "file_size BIGINT DEFAULT NULL, "
                + "uploaded_by INT DEFAULT NULL, "
                + "uploaded_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP, "
                + "KEY idx_vendor_documents_vendor (vendor_id)"
                + ") ENGINE=InnoDB DEFAULT CHARSET=utf8mb4";
        try (PreparedStatement ps = con.prepareStatement(sql)) {
            ps.executeUpdate();
            tableEnsured = true;
        } catch (Exception e) {
            LOGGER.log(Level.WARNING, "Unable to ensure vendor_documents table exists", e);
        }
    }

    public int addDocument(int vendorId, String documentType, String originalFileName,
            String storedFilePath, String mimeType, long fileSize, int uploadedBy) {

        String sql = "INSERT INTO vendor_documents "
                + "(vendor_id, document_type, original_file_name, stored_file_path, mime_type, file_size, uploaded_by) "
                + "VALUES (?, ?, ?, ?, ?, ?, ?)";

        try (Connection con = DBConnection.getConnection();
             PreparedStatement ps = con.prepareStatement(sql, Statement.RETURN_GENERATED_KEYS)) {
            ensureTable(con);

            ps.setInt(1, vendorId);
            ps.setString(2, normalizeDocumentType(documentType));
            ps.setString(3, safeValue(originalFileName, "vendor-document"));
            ps.setString(4, safeValue(storedFilePath, ""));
            ps.setString(5, safeValue(mimeType, null));
            ps.setLong(6, Math.max(fileSize, 0L));

            if (uploadedBy <= 0) {
                ps.setNull(7, Types.INTEGER);
            } else {
                ps.setInt(7, uploadedBy);
            }

            int affected = ps.executeUpdate();

            if (affected > 0) {
                try (ResultSet rs = ps.getGeneratedKeys()) {
                    if (rs.next()) {
                        return rs.getInt(1);
                    }
                }
            }

        } catch (Exception e) {
            LOGGER.log(Level.SEVERE, "addDocument failed for vendor " + vendorId, e);
        }

        return 0;
    }

    public List<VendorDocument> getDocumentsByVendorId(int vendorId) {
        List<VendorDocument> documents = new ArrayList<>();

        String sql = "SELECT vd.document_id, vd.vendor_id, vd.document_type, vd.original_file_name, "
                + "vd.stored_file_path, vd.mime_type, COALESCE(vd.file_size, 0) AS file_size, "
                + "COALESCE(vd.uploaded_by, 0) AS uploaded_by, COALESCE(u.username, 'System') AS uploaded_by_username, "
                + "DATE_FORMAT(vd.uploaded_at, '%d %b %Y, %h:%i %p') AS uploaded_at "
                + "FROM vendor_documents vd "
                + "LEFT JOIN users u ON vd.uploaded_by = u.user_id "
                + "WHERE vd.vendor_id = ? "
                + "ORDER BY vd.uploaded_at DESC, vd.document_id DESC";

        try (Connection con = DBConnection.getConnection();
             PreparedStatement ps = con.prepareStatement(sql)) {
            ensureTable(con);

            ps.setInt(1, vendorId);

            try (ResultSet rs = ps.executeQuery()) {
                while (rs.next()) {
                    documents.add(mapDocument(rs));
                }
            }

        } catch (Exception e) {
            LOGGER.log(Level.WARNING, "getDocumentsByVendorId failed for vendor " + vendorId, e);
        }

        return documents;
    }

    public VendorDocument getDocumentById(int documentId) {
        String sql = "SELECT vd.document_id, vd.vendor_id, vd.document_type, vd.original_file_name, "
                + "vd.stored_file_path, vd.mime_type, COALESCE(vd.file_size, 0) AS file_size, "
                + "COALESCE(vd.uploaded_by, 0) AS uploaded_by, COALESCE(u.username, 'System') AS uploaded_by_username, "
                + "DATE_FORMAT(vd.uploaded_at, '%d %b %Y, %h:%i %p') AS uploaded_at "
                + "FROM vendor_documents vd "
                + "LEFT JOIN users u ON vd.uploaded_by = u.user_id "
                + "WHERE vd.document_id = ? "
                + "LIMIT 1";

        try (Connection con = DBConnection.getConnection();
             PreparedStatement ps = con.prepareStatement(sql)) {
            ensureTable(con);

            ps.setInt(1, documentId);

            try (ResultSet rs = ps.executeQuery()) {
                if (rs.next()) {
                    return mapDocument(rs);
                }
            }

        } catch (Exception e) {
            LOGGER.log(Level.WARNING, "getDocumentById failed for document " + documentId, e);
        }

        return null;
    }

    private VendorDocument mapDocument(ResultSet rs) throws Exception {
        VendorDocument document = new VendorDocument();
        document.setDocumentId(rs.getInt("document_id"));
        document.setVendorId(rs.getInt("vendor_id"));
        document.setDocumentType(rs.getString("document_type"));
        document.setOriginalFileName(rs.getString("original_file_name"));
        document.setStoredFilePath(rs.getString("stored_file_path"));
        document.setMimeType(rs.getString("mime_type"));
        document.setFileSize(rs.getLong("file_size"));
        document.setUploadedBy(rs.getInt("uploaded_by"));
        document.setUploadedByUsername(rs.getString("uploaded_by_username"));
        document.setUploadedAt(rs.getString("uploaded_at"));
        return document;
    }

    public static String normalizeDocumentType(String documentType) {
        String value = documentType == null ? "" : documentType.trim().toUpperCase();

        switch (value) {
            case "TRADE_LICENSE":
            case "GST_CERTIFICATE":
            case "PAN_CARD":
            case "COMPLIANCE_CERTIFICATE":
            case "OTHER":
                return value;
            default:
                return "OTHER";
        }
    }

    private String safeValue(String value, String defaultValue) {
        if (value == null || value.trim().isEmpty()) {
            return defaultValue;
        }
        return value.trim();
    }
}
