package com.mycompany.asset_management_system_ams;

import org.apache.pdfbox.pdmodel.PDDocument;
import org.apache.pdfbox.text.PDFTextStripper;
import org.apache.pdfbox.Loader;
import org.apache.poi.xwpf.extractor.XWPFWordExtractor;
import org.apache.poi.xwpf.usermodel.XWPFDocument;

import java.io.File;
import java.io.FileInputStream;
import java.nio.file.Files;
import java.util.logging.Level;
import java.util.logging.Logger;

/**
 * Service to extract text from uploaded files (PDF, TXT, DOCX, etc.)
 */
public class DocumentTextExtractor {
    private static final Logger LOGGER = Logger.getLogger(DocumentTextExtractor.class.getName());

    public static String extractText(String filePath, String mimeType) {
        if (filePath == null || filePath.isEmpty()) return null;

        File file = new File(filePath);
        if (!file.exists()) {
            LOGGER.log(Level.WARNING, "File not found for extraction: " + filePath);
            return null;
        }

        try {
            if ("application/pdf".equalsIgnoreCase(mimeType) || filePath.toLowerCase().endsWith(".pdf")) {
                return extractFromPdf(file);
            } else if ("text/plain".equalsIgnoreCase(mimeType) || filePath.toLowerCase().endsWith(".txt")) {
                return extractFromTxt(file);
            } else if ("application/vnd.openxmlformats-officedocument.wordprocessingml.document".equalsIgnoreCase(mimeType) || filePath.toLowerCase().endsWith(".docx")) {
                return extractFromDocx(file);
            } else {
                LOGGER.log(Level.INFO, "Unsupported mime type for text extraction: " + mimeType);
                return null;
            }
        } catch (Exception e) {
            LOGGER.log(Level.WARNING, "Failed to extract text from: " + filePath, e);
            return null;
        }
    }
    private static String extractFromPdf(File file) throws Exception {
        try (PDDocument document = Loader.loadPDF(file)) {
            if (document.isEncrypted()) {
                LOGGER.log(Level.WARNING, "Cannot extract text from encrypted PDF: " + file.getName());
                return null;
            }
            PDFTextStripper stripper = new PDFTextStripper();
            // Limit to first 20 pages to avoid memory issues on huge manuals
            stripper.setEndPage(20);
            return stripper.getText(document);
        }
    }

    private static String extractFromTxt(File file) throws Exception {
        // Read up to a reasonable limit (e.g. 500KB)
        String content = Files.readString(file.toPath());
        if (content.length() > 500000) {
            return content.substring(0, 500000);
        }
        return content;
    }

    private static String extractFromDocx(File file) throws Exception {
        try (FileInputStream fis = new FileInputStream(file);
             XWPFDocument doc = new XWPFDocument(fis);
             XWPFWordExtractor extractor = new XWPFWordExtractor(doc)) {
            String content = extractor.getText();
            if (content != null && content.length() > 500000) {
                return content.substring(0, 500000);
            }
            return content;
        }
    }
}
