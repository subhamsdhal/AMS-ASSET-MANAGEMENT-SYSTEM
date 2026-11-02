package com.mycompany.asset_management_system_ams;

import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.util.ArrayList;
import java.util.List;

public class EmployeeDocumentDAO {

    public int addDocument(int employeeId, String documentTitle, String documentType,
            String originalFileName, String storedFileName, String storedFilePath,
            String mimeType, long fileSize, int uploadedBy) {
        String sql = "INSERT INTO employee_documents "
                + "(employee_id, document_title, document_type, original_file_name, stored_file_name, stored_file_path, mime_type, file_size, uploaded_by, status) "
                + "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 'ACTIVE')";

        try (Connection con = DBConnection.getConnection();
             PreparedStatement ps = con.prepareStatement(sql, PreparedStatement.RETURN_GENERATED_KEYS)) {

            ps.setInt(1, employeeId);
            ps.setString(2, documentTitle);
            ps.setString(3, documentType);
            ps.setString(4, originalFileName);
            ps.setString(5, storedFileName);
            ps.setString(6, storedFilePath);
            ps.setString(7, mimeType);
            ps.setLong(8, fileSize);
            ps.setInt(9, uploadedBy);

            int affectedRows = ps.executeUpdate();
            if (affectedRows > 0) {
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

    public List<EmployeeDocument> getDocumentsByEmployeeId(int employeeId) {
        List<EmployeeDocument> list = new ArrayList<>();
        String sql = "SELECT d.*, u.username AS uploaded_by_name "
                + "FROM employee_documents d "
                + "LEFT JOIN users u ON d.uploaded_by = u.user_id "
                + "WHERE d.employee_id = ? AND d.status = 'ACTIVE' "
                + "ORDER BY d.uploaded_at DESC";

        try (Connection con = DBConnection.getConnection();
             PreparedStatement ps = con.prepareStatement(sql)) {

            ps.setInt(1, employeeId);

            try (ResultSet rs = ps.executeQuery()) {
                while (rs.next()) {
                    EmployeeDocument doc = new EmployeeDocument();
                    doc.setDocumentId(rs.getInt("document_id"));
                    doc.setEmployeeId(rs.getInt("employee_id"));
                    doc.setDocumentTitle(rs.getString("document_title"));
                    doc.setDocumentType(rs.getString("document_type"));
                    doc.setOriginalFileName(rs.getString("original_file_name"));
                    doc.setStoredFileName(rs.getString("stored_file_name"));
                    doc.setStoredFilePath(rs.getString("stored_file_path"));
                    doc.setMimeType(rs.getString("mime_type"));
                    doc.setFileSize(rs.getLong("file_size"));
                    doc.setUploadedBy(rs.getInt("uploaded_by"));
                    doc.setUploadedByName(rs.getString("uploaded_by_name"));
                    doc.setUploadedAt(rs.getTimestamp("uploaded_at"));
                    doc.setStatus(rs.getString("status"));
                    list.add(doc);
                }
            }
        } catch (Exception e) {
            e.printStackTrace();
        }
        return list;
    }

    public EmployeeDocument getDocumentById(int documentId) {
        String sql = "SELECT * FROM employee_documents WHERE document_id = ? AND status = 'ACTIVE'";
        try (Connection con = DBConnection.getConnection();
             PreparedStatement ps = con.prepareStatement(sql)) {

            ps.setInt(1, documentId);

            try (ResultSet rs = ps.executeQuery()) {
                if (rs.next()) {
                    EmployeeDocument doc = new EmployeeDocument();
                    doc.setDocumentId(rs.getInt("document_id"));
                    doc.setEmployeeId(rs.getInt("employee_id"));
                    doc.setDocumentTitle(rs.getString("document_title"));
                    doc.setDocumentType(rs.getString("document_type"));
                    doc.setOriginalFileName(rs.getString("original_file_name"));
                    doc.setStoredFileName(rs.getString("stored_file_name"));
                    doc.setStoredFilePath(rs.getString("stored_file_path"));
                    doc.setMimeType(rs.getString("mime_type"));
                    doc.setFileSize(rs.getLong("file_size"));
                    doc.setUploadedBy(rs.getInt("uploaded_by"));
                    doc.setUploadedAt(rs.getTimestamp("uploaded_at"));
                    doc.setStatus(rs.getString("status"));
                    return doc;
                }
            }
        } catch (Exception e) {
            e.printStackTrace();
        }
        return null;
    }

    public boolean deactivateEmployeeDocument(int documentId) {
        String sql = "UPDATE employee_documents SET status = 'INACTIVE' WHERE document_id = ?";
        try (Connection con = DBConnection.getConnection();
             PreparedStatement ps = con.prepareStatement(sql)) {
            ps.setInt(1, documentId);
            return ps.executeUpdate() > 0;
        } catch (Exception e) {
            e.printStackTrace();
        }
        return false;
    }
}
