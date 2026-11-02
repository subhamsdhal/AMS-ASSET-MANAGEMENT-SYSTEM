package com.mycompany.asset_management_system_ams;

import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.Statement;
import java.sql.Types;
import java.util.ArrayList;
import java.util.List;

public class AssetDocumentDAO {

    public int addDocument(
            int assetId,
            String documentType,
            String originalFileName,
            String storedFilePath,
            String mimeType,
            long fileSize,
            int uploadedBy) {

        String sql = "INSERT INTO asset_documents "
                + "(asset_id, document_type, original_file_name, stored_file_path, mime_type, file_size, uploaded_by) "
                + "VALUES (?, ?, ?, ?, ?, ?, ?)";

        try (Connection con = DBConnection.getConnection();
             PreparedStatement ps = con.prepareStatement(sql, Statement.RETURN_GENERATED_KEYS)) {

            ps.setInt(1, assetId);
            ps.setString(2, normalizeDocumentType(documentType));
            ps.setString(3, safeValue(originalFileName, "asset-document"));
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
            e.printStackTrace();
        }

        return 0;
    }

    public List<AssetDocument> getDocumentsByAssetId(int assetId) {
        List<AssetDocument> documents = new ArrayList<>();

        String sql = "SELECT ad.document_id, ad.asset_id, ad.document_type, ad.original_file_name, "
                + "ad.stored_file_path, ad.mime_type, COALESCE(ad.file_size, 0) AS file_size, "
                + "COALESCE(ad.uploaded_by, 0) AS uploaded_by, COALESCE(u.username, 'System') AS uploaded_by_username, "
                + "DATE_FORMAT(ad.uploaded_at, '%d %b %Y, %h:%i %p') AS uploaded_at "
                + "FROM asset_documents ad "
                + "LEFT JOIN users u ON ad.uploaded_by = u.user_id "
                + "WHERE ad.asset_id = ? "
                + "ORDER BY ad.uploaded_at DESC, ad.document_id DESC";

        try (Connection con = DBConnection.getConnection();
             PreparedStatement ps = con.prepareStatement(sql)) {

            ps.setInt(1, assetId);

            try (ResultSet rs = ps.executeQuery()) {
                while (rs.next()) {
                    documents.add(mapDocument(rs));
                }
            }

        } catch (Exception e) {
            e.printStackTrace();
        }

        return documents;
    }

    public AssetDocument getDocumentById(int documentId) {
        String sql = "SELECT ad.document_id, ad.asset_id, ad.document_type, ad.original_file_name, "
                + "ad.stored_file_path, ad.mime_type, COALESCE(ad.file_size, 0) AS file_size, "
                + "COALESCE(ad.uploaded_by, 0) AS uploaded_by, COALESCE(u.username, 'System') AS uploaded_by_username, "
                + "DATE_FORMAT(ad.uploaded_at, '%d %b %Y, %h:%i %p') AS uploaded_at "
                + "FROM asset_documents ad "
                + "LEFT JOIN users u ON ad.uploaded_by = u.user_id "
                + "WHERE ad.document_id = ? "
                + "LIMIT 1";

        try (Connection con = DBConnection.getConnection();
             PreparedStatement ps = con.prepareStatement(sql)) {

            ps.setInt(1, documentId);

            try (ResultSet rs = ps.executeQuery()) {
                if (rs.next()) {
                    return mapDocument(rs);
                }
            }

        } catch (Exception e) {
            e.printStackTrace();
        }

        return null;
    }

    private AssetDocument mapDocument(ResultSet rs) throws Exception {
        AssetDocument document = new AssetDocument();
        document.setDocumentId(rs.getInt("document_id"));
        document.setAssetId(rs.getInt("asset_id"));
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
            case "ASSET_PHOTO":
            case "INVOICE":
            case "WARRANTY":
            case "MANUAL":
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

    // --- Copilot Document Indexing ---

    public void indexDocumentText(int documentId, int assetId, String fileName, String extractedText, int uploadedBy) {
        String sql = "INSERT INTO asset_document_text_index (document_id, asset_id, file_name, extracted_text, extraction_status, created_by) "
                   + "VALUES (?, ?, ?, ?, ?, ?)";
        try (Connection con = DBConnection.getConnection();
             PreparedStatement ps = con.prepareStatement(sql)) {
            ps.setInt(1, documentId);
            ps.setInt(2, assetId);
            ps.setString(3, fileName);
            if (extractedText == null || extractedText.trim().isEmpty()) {
                ps.setNull(4, Types.LONGVARCHAR);
                ps.setString(5, "FAILED_OR_EMPTY");
            } else {
                ps.setString(4, extractedText);
                ps.setString(5, "SUCCESS");
            }
            if (uploadedBy <= 0) ps.setNull(6, Types.INTEGER);
            else ps.setInt(6, uploadedBy);
            
            ps.executeUpdate();
        } catch (Exception e) {
            e.printStackTrace();
        }
    }

    public List<String> searchDocumentText(String keyword) {
        List<String> results = new ArrayList<>();
        if (keyword == null || keyword.trim().isEmpty()) return results;
        
        // Basic LIKE search across extracted text for copilot matching
        String sql = "SELECT a.asset_code, a.asset_name, idx.file_name, idx.extracted_text "
                   + "FROM asset_document_text_index idx "
                   + "JOIN assets a ON idx.asset_id = a.asset_id "
                   + "WHERE idx.extraction_status = 'SUCCESS' AND idx.extracted_text LIKE ? "
                   + "LIMIT 5";
        try (Connection con = DBConnection.getConnection();
             PreparedStatement ps = con.prepareStatement(sql)) {
            ps.setString(1, "%" + keyword.trim() + "%");
            try (ResultSet rs = ps.executeQuery()) {
                while (rs.next()) {
                    String text = rs.getString("extracted_text");
                    int idx = text.toLowerCase().indexOf(keyword.toLowerCase());
                    String snippet = text;
                    if (idx > 0) {
                        int start = Math.max(0, idx - 60);
                        int end = Math.min(text.length(), idx + 100);
                        snippet = text.substring(start, end).replace('\n', ' ').trim();
                    } else if (snippet.length() > 150) {
                        snippet = snippet.substring(0, 150) + "...";
                    }
                    results.add(String.format("**Asset %s** (%s) - Document `%s`:\n> \"...%s...\"", 
                        rs.getString("asset_code"), rs.getString("asset_name"), rs.getString("file_name"), snippet));
                }
            }
        } catch (Exception e) {
            e.printStackTrace();
        }
        return results;
    }
}
