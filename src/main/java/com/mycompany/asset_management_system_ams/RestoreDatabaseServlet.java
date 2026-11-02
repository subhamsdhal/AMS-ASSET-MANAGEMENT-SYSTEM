package com.mycompany.asset_management_system_ams;

import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStreamWriter;
import java.io.PrintWriter;
import java.nio.charset.StandardCharsets;
import java.sql.Connection;
import java.sql.Statement;
import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.util.ArrayList;
import java.util.List;

import jakarta.servlet.ServletException;
import jakarta.servlet.annotation.MultipartConfig;
import jakarta.servlet.annotation.WebServlet;
import jakarta.servlet.http.HttpServlet;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import jakarta.servlet.http.HttpSession;
import jakarta.servlet.http.Part;

@WebServlet(name = "RestoreDatabaseServlet", urlPatterns = {"/RestoreDatabaseServlet"})
@MultipartConfig(
        fileSizeThreshold = 1024 * 1024,
        maxFileSize = 50 * 1024 * 1024,
        maxRequestSize = 60 * 1024 * 1024
)
public class RestoreDatabaseServlet extends HttpServlet {

    private static final String RESTORE_CONFIRMATION = "RESTORE RAILWAY AMS";

    @Override
    protected void doPost(HttpServletRequest request, HttpServletResponse response)
            throws ServletException, IOException {

        Connection con = null;

        String username = "";
        String role = "";
        String loginEmail = "";
        String submittedFileName = "N/A";
        int executedStatements = 0;
        String safetyBackupPath = "N/A";

        try {
            request.setCharacterEncoding("UTF-8");

            HttpSession session = request.getSession(false);

            if (session == null
                    || session.getAttribute("username") == null
                    || session.getAttribute("role") == null) {
                response.sendRedirect("login.jsp");
                return;
            }

            username = session.getAttribute("username").toString();
            role = session.getAttribute("role").toString();
            loginEmail = NotificationHelper.getUserEmailByUsername(username);

            if (!("SUPER_ADMIN".equals(role) || "ADMIN".equals(role))) {
                response.sendRedirect("settings.jsp?access=denied");
                return;
            }

            String confirmation = request.getParameter("restoreConfirmation");

            if (confirmation == null || !RESTORE_CONFIRMATION.equals(confirmation.trim())) {
                response.sendRedirect("backup_restore.jsp?error=confirm");
                return;
            }

            Part backupFilePart = request.getPart("backupFile");

            if (backupFilePart == null || backupFilePart.getSize() == 0) {
                response.sendRedirect("backup_restore.jsp?error=nofile");
                return;
            }

            submittedFileName = backupFilePart.getSubmittedFileName();

            if (submittedFileName == null || !submittedFileName.toLowerCase().endsWith(".sql")) {
                response.sendRedirect("backup_restore.jsp?error=invalid");
                return;
            }

            String sqlScript = readUploadedSqlFile(backupFilePart);

            if (sqlScript == null || sqlScript.trim().isEmpty()) {
                response.sendRedirect("backup_restore.jsp?error=nofile");
                return;
            }

            List<String> sqlStatements = splitSqlStatements(sqlScript);

            con = DBConnection.getConnection();

            if (con == null) {
                response.sendRedirect("backup_restore.jsp?error=db");
                return;
            }

            // Fault (Critical, fixed - audit/23 Finding 1): this loop used to run
            // with no transaction wrapping and no safety net of any kind. If the
            // uploaded script failed partway through (malformed statement,
            // constraint violation, truncated upload), the database was left in
            // whatever partial state execution reached, with no way back to
            // either the pre-restore state or a completed restore - for a feature
            // whose entire purpose is disaster recovery, that's precisely backwards.
            // True mid-restore atomicity isn't fully achievable here anyway (MySQL
            // DDL like CREATE/DROP TABLE, which a real backup file is full of,
            // implicitly commits and can't be rolled back even inside a
            // transaction) - so per the audit's own recommendation, the fix is a
            // guaranteed way back: take a full, real backup of the CURRENT
            // database automatically, immediately before touching anything. If
            // that backup can't be taken, the restore is aborted before any
            // destructive statement runs - failing safe rather than proceeding
            // without a way back.
            try {
                safetyBackupPath = createPreRestoreSafetyBackup(con, username);
            } catch (Exception backupException) {
                log("Pre-restore safety backup failed - aborting restore before any statement ran", backupException);
                response.sendRedirect("backup_restore.jsp?error=safetybackup");
                return;
            }

            try (Statement statement = con.createStatement()) {
                statement.setQueryTimeout(120);
                statement.execute("SET FOREIGN_KEY_CHECKS = 0");

                for (String sql : sqlStatements) {
                    String cleanSql = sql.trim();

                    if (cleanSql.isEmpty()) {
                        continue;
                    }

                    statement.execute(cleanSql);
                    executedStatements++;
                }

                statement.execute("SET FOREIGN_KEY_CHECKS = 1");
            } catch (Exception restoreException) {
                log("Restore failed partway through (" + executedStatements + " statements applied) - "
                        + "the pre-restore state was saved to " + safetyBackupPath
                        + " before this restore began; restore that file to return to the prior state.",
                        restoreException);
                throw restoreException;
            }

            int userId = getSessionUserId(session);

            try {
                AuditDAO.log(
                        userId,
                        "RESTORE",
                        "database",
                        0,
                        "Database restored from SQL backup by " + username
                        + ". File: " + submittedFileName
                        + ". Executed statements: " + executedStatements
                        + ". Pre-restore safety backup: " + safetyBackupPath
                );
            } catch (Exception auditException) {
                log("Restore audit log failed", auditException);
            }

            sendRestoreAlert(
                    "SUCCESS",
                    username,
                    role,
                    loginEmail,
                    submittedFileName,
                    executedStatements,
                    "",
                    safetyBackupPath
            );

            response.sendRedirect("backup_restore.jsp?msg=restored&count=" + executedStatements);

        } catch (Exception e) {
            log("Database restore failed", e);

            if (username != null && !username.trim().isEmpty()) {
                sendRestoreAlert(
                        "FAILED",
                        username,
                        role,
                        loginEmail,
                        submittedFileName,
                        executedStatements,
                        e.getClass().getSimpleName() + ": " + e.getMessage(),
                        safetyBackupPath
                );
            }

            response.sendRedirect("backup_restore.jsp?error=server");

        } finally {
            try {
                if (con != null) {
                    try (Statement statement = con.createStatement()) {
                        statement.execute("SET FOREIGN_KEY_CHECKS = 1");
                    } catch (Exception foreignKeyException) {
                        log("Unable to re-enable foreign key checks after restore", foreignKeyException);
                    }

                    con.close();
                }
            } catch (Exception ex) {
                log("Unable to close restore database connection", ex);
            }
        }
    }

    private void sendRestoreAlert(String status, String username, String role, String loginEmail,
            String submittedFileName, int executedStatements, String errorMessage, String safetyBackupPath) {

        try {
            String details = "Operation Type: Database Restore\n"
                    + "Status: " + safe(status, "N/A") + "\n"
                    + "Uploaded File: " + safe(submittedFileName, "N/A") + "\n"
                    + "Executed SQL Statements: " + executedStatements + "\n"
                    + "Pre-Restore Safety Backup: " + safe(safetyBackupPath, "N/A") + "\n";

            if ("FAILED".equalsIgnoreCase(status)) {
                details += "Error Message: " + safe(errorMessage, "N/A") + "\n"
                        + "Recovery: restore the pre-restore safety backup listed above to return to the "
                        + "state immediately before this attempt.\n";
            }

            details += "\nSecurity Note: Database restore is a critical administrative operation. "
                    + "Please verify that the restored data is correct and trusted.";

            AdminSecurityAlertHelper.sendAdminActionAlert(
                    getServletContext(),
                    0,
                    "Database Restore " + status,
                    "Backup and Restore",
                    username,
                    role,
                    loginEmail,
                    details
            );

        } catch (Exception e) {
            log("Restore alert failed", e);
        }
    }

    private int getSessionUserId(HttpSession session) {
        // Defaulting to 1 here would misattribute this audit-log entry (a database
        // restore - the most consequential action in this module) to whichever real
        // account happens to be user_id 1. AuditDAO.log() resolves 0/null to a NULL
        // "system" row instead.
        Object userIdObj = session.getAttribute("user_id");

        if (userIdObj == null) {
            userIdObj = session.getAttribute("userId");
        }

        if (userIdObj instanceof Integer) {
            return (Integer) userIdObj;
        }

        if (userIdObj != null) {
            try {
                return Integer.parseInt(userIdObj.toString());
            } catch (Exception e) {
                return 0;
            }
        }

        return 0;
    }

    // Writes a full database dump to WEB-INF/db_backups (not web-accessible,
    // same convention as this app's other server-side-only files) using the
    // exact same, already-correct dump logic BackupDatabaseServlet's own
    // download endpoint uses (writeFullBackup()), just pointed at a file
    // instead of the HTTP response. Returns the absolute path written, or
    // throws if the directory can't be created/written to - callers must
    // treat a thrown exception as "do not proceed with the restore".
    private String createPreRestoreSafetyBackup(Connection con, String username) throws Exception {
        String backupsRealPath = getServletContext().getRealPath("/WEB-INF/db_backups");
        File backupsDir = new File(backupsRealPath);
        if (!backupsDir.exists() && !backupsDir.mkdirs()) {
            throw new IOException("Could not create pre-restore backup directory: " + backupsRealPath);
        }

        String timestamp = LocalDateTime.now().format(DateTimeFormatter.ofPattern("yyyyMMdd_HHmmss"));
        File backupFile = new File(backupsDir, "pre_restore_safety_backup_" + timestamp + ".sql");

        try (PrintWriter writer = new PrintWriter(
                new OutputStreamWriter(new FileOutputStream(backupFile), StandardCharsets.UTF_8))) {
            writer.println("-- Automatic pre-restore safety backup - taken immediately before a");
            writer.println("-- database restore triggered by " + username + " on "
                    + LocalDateTime.now().format(DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss")) + ".");
            writer.println("-- Restore this file to return to the state immediately before that restore.");
            writer.println();
            BackupDatabaseServlet.writeFullBackup(con, writer, username + " (automatic, pre-restore)");
            writer.flush();
            if (writer.checkError()) {
                throw new IOException("Error writing pre-restore safety backup to " + backupFile.getAbsolutePath());
            }
        }

        return backupFile.getAbsolutePath();
    }

    private String readUploadedSqlFile(Part part) throws Exception {
        try (InputStream inputStream = part.getInputStream();
             ByteArrayOutputStream outputStream = new ByteArrayOutputStream()) {

            byte[] buffer = new byte[8192];

            int bytesRead;

            while ((bytesRead = inputStream.read(buffer)) != -1) {
                outputStream.write(buffer, 0, bytesRead);
            }

            return new String(outputStream.toByteArray(), StandardCharsets.UTF_8);
        }
    }

    private List<String> splitSqlStatements(String sqlScript) {
        List<String> statements = new ArrayList<>();

        StringBuilder currentStatement = new StringBuilder();

        boolean insideSingleQuote = false;
        boolean insideDoubleQuote = false;
        boolean insideBacktick = false;
        boolean insideLineComment = false;
        boolean insideBlockComment = false;

        char previousChar = '\0';

        for (int i = 0; i < sqlScript.length(); i++) {
            char currentChar = sqlScript.charAt(i);
            char nextChar = i + 1 < sqlScript.length() ? sqlScript.charAt(i + 1) : '\0';

            if (insideLineComment) {
                if (currentChar == '\n') {
                    insideLineComment = false;
                    currentStatement.append('\n');
                }

                previousChar = currentChar;
                continue;
            }

            if (insideBlockComment) {
                if (currentChar == '*' && nextChar == '/') {
                    insideBlockComment = false;
                    i++;
                    previousChar = '/';
                }

                continue;
            }

            if (!insideSingleQuote && !insideDoubleQuote && !insideBacktick) {
                if (currentChar == '-' && nextChar == '-') {
                    char afterNext = i + 2 < sqlScript.length() ? sqlScript.charAt(i + 2) : '\0';

                    if (Character.isWhitespace(afterNext)) {
                        insideLineComment = true;
                        i++;
                        previousChar = '-';
                        continue;
                    }
                }

                if (currentChar == '#') {
                    insideLineComment = true;
                    previousChar = currentChar;
                    continue;
                }

                if (currentChar == '/' && nextChar == '*') {
                    insideBlockComment = true;
                    i++;
                    previousChar = '*';
                    continue;
                }
            }

            if (currentChar == '\'' && !insideDoubleQuote && !insideBacktick && previousChar != '\\') {
                insideSingleQuote = !insideSingleQuote;
            } else if (currentChar == '"' && !insideSingleQuote && !insideBacktick && previousChar != '\\') {
                insideDoubleQuote = !insideDoubleQuote;
            } else if (currentChar == '`' && !insideSingleQuote && !insideDoubleQuote) {
                insideBacktick = !insideBacktick;
            }

            if (currentChar == ';'
                    && !insideSingleQuote
                    && !insideDoubleQuote
                    && !insideBacktick) {

                String statement = currentStatement.toString().trim();

                if (!statement.isEmpty()) {
                    statements.add(statement);
                }

                currentStatement.setLength(0);

            } else {
                currentStatement.append(currentChar);
            }

            previousChar = currentChar;
        }

        String lastStatement = currentStatement.toString().trim();

        if (!lastStatement.isEmpty()) {
            statements.add(lastStatement);
        }

        return statements;
    }

    private String safe(String value, String fallback) {
        if (value == null || value.trim().isEmpty()) {
            return fallback;
        }

        return value.trim();
    }
}
