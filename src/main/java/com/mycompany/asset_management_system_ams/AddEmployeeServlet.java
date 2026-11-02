package com.mycompany.asset_management_system_ams;

import java.io.IOException;
import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;

import jakarta.servlet.ServletException;
import jakarta.servlet.annotation.MultipartConfig;
import jakarta.servlet.annotation.WebServlet;
import jakarta.servlet.http.HttpServlet;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import jakarta.servlet.http.HttpSession;
import jakarta.servlet.http.Part;
import java.nio.file.Files;
import java.nio.file.Paths;
import java.util.logging.Level;
import java.util.logging.Logger;

@WebServlet(name = "AddEmployeeServlet", urlPatterns = {"/AddEmployeeServlet"})
@MultipartConfig(
        fileSizeThreshold = 1024 * 1024,
        maxFileSize = 5 * 1024 * 1024,
        maxRequestSize = 6 * 1024 * 1024
)
public class AddEmployeeServlet extends HttpServlet {
    private static final Logger LOGGER = Logger.getLogger(AddEmployeeServlet.class.getName());

    @Override
    protected void doPost(HttpServletRequest request, HttpServletResponse response)
            throws ServletException, IOException {

        try {
            request.setCharacterEncoding("UTF-8");

            HttpSession session = request.getSession(false);

            if (session == null
                    || session.getAttribute("username") == null
                    || session.getAttribute("role") == null) {
                response.sendRedirect("login.jsp");
                return;
            }

            String username = String.valueOf(session.getAttribute("username"));
            String role = String.valueOf(session.getAttribute("role"));

            int userId = getSessionInt(session, "user_id", 1);

            if (userId == 1) {
                userId = getSessionInt(session, "userId", 1);
            }

            if (!canManageEmployeeRecords(role)) {
                response.sendRedirect("employees.jsp?access=denied");
                return;
            }

            String employeeCode = clean(request.getParameter("employeeCode"));
            String employeeName = clean(request.getParameter("employeeName"));
            String email = clean(request.getParameter("email"));
            String phone = PhoneValidationUtil.validatePhone(request.getParameter("phone"));

            int departmentId = parseInt(request.getParameter("departmentId"), 0);

            if ("DEPARTMENT_HEAD".equalsIgnoreCase(role)) {
                if (!DepartmentDAO.isDepartmentUnderDepartmentHead(departmentId, userId)) {
                    response.sendRedirect("employees.jsp?access=denied");
                    return;
                }
            }

            String designation = clean(request.getParameter("designation"));
            String joiningDate = clean(request.getParameter("joiningDate"));

            if (employeeCode.isEmpty()) {
                employeeCode = generateNextEmployeeCode();
            }

            if (employeeCode.isEmpty()
                    || employeeName.isEmpty()
                    || email.isEmpty()
                    || departmentId <= 0
                    || designation.isEmpty()
                    || joiningDate.isEmpty()) {
                response.sendRedirect("add_employee.jsp?error=failed");
                return;
            }

            if (phone == null) {
                response.sendRedirect("add_employee.jsp?error=invalidphone");
                return;
            }

            if (!isValidDepartment(departmentId)) {
                response.sendRedirect("add_employee.jsp?error=invaliddepartment");
                return;
            }

            if (!DateValidationUtil.isPastOrToday(joiningDate)) {
                response.sendRedirect("add_employee.jsp?error=invaliddate");
                return;
            }

            String status = "ACTIVE";

            // Fault (Critical): this used to force createLogin = true (and
            // isAutoLogin = true, switching to a different, less-safe
            // username-collision strategy below - see its removed branch)
            // for ANY employee code numbered EMP006 or higher, completely
            // overriding whatever the admin actually chose on the "Create
            // System Login Account & Send Email" checkbox. generateNextEmployeeCode()
            // (the code the Add Employee form suggests by default) was
            // already producing EMP012 on this live database - meaning this
            // silently overrode the checkbox for every single new employee,
            // in both directions: leaving it unchecked (e.g. the employee
            // hasn't started yet, or logins are being provisioned in a
            // separate batch later) still created a real login and sent a
            // real welcome email regardless. The isAutoLogin path also had
            // its own separate bug: on a username collision it just
            // silently skipped creating the login entirely (no error, no
            // audit trail) instead of the safer manual-path behavior below,
            // which retries with a "_2", "_3", ... suffix. Removed the
            // override entirely - createLogin now reflects only what was
            // actually submitted, and every login-creation attempt goes
            // through the one (safer) collision-handling path.
            String createLoginParam = clean(request.getParameter("createLogin"));
            boolean createLogin = "1".equals(createLoginParam) || "true".equalsIgnoreCase(createLoginParam);

            EmployeeDAO dao = new EmployeeDAO();

            try (Connection con = DBConnection.getConnection()) {
                con.setAutoCommit(false);
                try {
                    int employeeId = dao.addEmployeeReturnId(
                            con, employeeCode, employeeName, email, phone,
                            departmentId, designation, joiningDate, status
                    );

                    if (employeeId > 0) {
                        String departmentName = getDepartmentName(con, departmentId);

                    AuditDAO.log(
                            userId,
                            "ADD",
                            "employees",
                            employeeId,
                            "New employee record created by " + username
                            + " (" + formatRoleName(role) + ")"
                            + ". Employee: " + employeeCode + " - " + employeeName
                            + ". Department: " + departmentName
                    );

                    con.commit(); // Option B: Commit employee independently

                    // ------- Create Login Account -------
                    String generatedUsername = "";
                    String generatedPassword = "";
                    boolean loginCreationFailed = false;

                    if (createLogin && employeeId > 0) {
                        try {
                            generatedUsername = generateUsername(employeeCode, email);

                            // Ensure unique username - retry with a "_2", "_3", ...
                            // suffix on collision rather than silently giving up.
                            int attempt = 2;
                            String tryUsername = generatedUsername;
                            while (usernameExists(con, tryUsername) && attempt < 20) {
                                tryUsername = generatedUsername + "_" + attempt;
                                attempt++;
                            }
                            generatedUsername = tryUsername;

                            // Bare block, not a leftover: kept the account-creation
                            // code below at its original nesting level (was
                            // "if (!skipCreation) { ... }" - skipCreation is gone
                            // now that the only collision case retries with a
                            // suffix above instead of silently bailing out) rather
                            // than reindenting ~60 lines just for cosmetics.
                            {
                                int employeeRoleId = getRoleIdByName(con, "EMPLOYEE");
                                if (employeeRoleId == 0) {
                                    LOGGER.warning("Role 'EMPLOYEE' not found in roles table. Falling back to 'USER'.");
                                    employeeRoleId = getRoleIdByName(con, "USER");
                                }
                                if (employeeRoleId == 0) {
                                    LOGGER.warning("Fallback role 'USER' not found either. Defaulting to role ID 2.");
                                    employeeRoleId = 2;
                                }

                                generatedPassword = generateTempPassword(employeeCode);
                                String hashedPassword = PasswordUtil.hash(generatedPassword);

                                String insertUser = "INSERT INTO users "
                                        + "(username, password_plaintext, password_crypt, email, role_id, current_role, employee_id, status, force_password_change, created_by, created_at) "
                                        + "VALUES (?, ?, ?, ?, ?, 'employee', ?, 'ACTIVE', 1, ?, NOW())";

                                try (java.sql.PreparedStatement psu = con.prepareStatement(insertUser)) {
                                    psu.setString(1, generatedUsername);
                                    psu.setString(2, ""); // Do not store plaintext password
                                    psu.setString(3, hashedPassword);
                                    psu.setString(4, email);
                                    psu.setInt(5, employeeRoleId);
                                    psu.setInt(6, employeeId);
                                    psu.setInt(7, userId);
                                    psu.executeUpdate();
                                }

                                // Update employees.user_id back-link
                                int newUserId = getUserIdByUsername(con, generatedUsername);
                                if (newUserId > 0) {
                                    try (java.sql.PreparedStatement pse = con.prepareStatement(
                                            "UPDATE employees SET user_id = ? WHERE employee_id = ?")) {
                                        pse.setInt(1, newUserId);
                                        pse.setInt(2, employeeId);
                                        pse.executeUpdate();
                                    }
                                }

                                AuditDAO.log(
                                        userId,
                                        "ADD",
                                        "users",
                                        newUserId,
                                        "Login account created for employee " + employeeCode
                                        + ". Username: " + generatedUsername
                                        + ". Created by: " + username
                                );

                                // Send welcome email with plain-text password (SMTP optional).
                                // Was unconditional - the "New Employee Welcome Email" toggle on
                                // Settings > Notifications saved successfully but had no effect
                                // on whether this email actually went out.
                                if (!email.isEmpty() && SettingsDAO.getBoolean("ams.notify.new.employee.email", true)) {
                                    try {
                                        EmailService.sendEmployeeWelcomeEmail(
                                                email,
                                                employeeName,
                                                employeeCode,
                                                generatedUsername,
                                                generatedPassword,
                                                "EMPLOYEE",
                                                departmentName
                                        );
                                    } catch (Exception e) {
                                        LOGGER.log(Level.SEVERE, "Failed to send welcome email to " + email, e);
                                    }
                                }
                            }
                            
                            con.commit(); // Commit login creation independently
                        } catch (Exception e) {
                            con.rollback(); // Rollback only the login creation
                            LOGGER.log(Level.SEVERE, "Exception while creating login for employee " + employeeId, e);
                            loginCreationFailed = true;
                            generatedUsername = ""; // Prevent success popup
                        }
                    }
                    // ------- End Login Account -------

                    sendNewEmployeeRecordNotice(
                            employeeId,
                            employeeCode,
                            employeeName,
                            email,
                            phone,
                            departmentId,
                            departmentName,
                            designation,
                            joiningDate,
                            status,
                            username,
                            role,
                            NotificationHelper.getUserEmailByUsername(username)
                    );

                    // Pass credentials to session for success display
                    if (createLogin && !generatedUsername.isEmpty()) {
                        HttpSession sess = request.getSession();
                        sess.setAttribute("last_created_emp_code", employeeCode);
                        sess.setAttribute("last_created_username", generatedUsername);
                        sess.setAttribute("last_created_password", generatedPassword);
                        sess.setAttribute("last_created_emp_name", employeeName);
                    }
                    
                    // ------- Handle Optional Document Upload -------
                    String documentTitle = clean(request.getParameter("documentTitle"));
                    String documentType = clean(request.getParameter("documentType"));
                    Part filePart = request.getPart("employeeDocument");
                    
                    boolean documentSaved = false;
                    boolean documentFailed = false;

                    if (filePart != null && filePart.getSize() > 0 && !documentTitle.isEmpty() && !documentType.isEmpty()) {
                        try {
                            EmployeeDocumentUploadUtil.SavedDocument savedDocument = 
                                EmployeeDocumentUploadUtil.saveEmployeeDocument(request, "employeeDocument", employeeId);
                            
                            EmployeeDocumentDAO docDao = new EmployeeDocumentDAO();
                            int documentId = docDao.addDocument(
                                    employeeId,
                                    documentTitle,
                                    documentType,
                                    savedDocument.getOriginalFileName(),
                                    savedDocument.getStoredFileName(),
                                    savedDocument.getStoredFilePath(),
                                    savedDocument.getMimeType(),
                                    savedDocument.getFileSize(),
                                    userId
                            );
                            
                            if (documentId > 0) {
                                documentSaved = true;
                                AuditDAO.log(
                                        userId,
                                        "EMP_DOC_UPLOAD",
                                        "employee_documents",
                                        documentId,
                                        "Employee document uploaded during creation. Employee ID: " + employeeId
                                        + ", Title: " + documentTitle
                                );
                            } else {
                                documentFailed = true;
                                try {
                                    Files.deleteIfExists(Paths.get(savedDocument.getStoredFilePath()));
                                } catch (Exception ignored) {}
                            }
                        } catch (Exception e) {
                            e.printStackTrace();
                            documentFailed = true;
                        }
                    }
                    // ------- End Optional Document Upload -------

                    con.commit();
                    
                    if (documentFailed) {
                        if (createLogin && !generatedUsername.isEmpty()) {
                            response.sendRedirect("employees.jsp?msg=added_with_login_doc_failed");
                        } else if (loginCreationFailed) {
                            response.sendRedirect("employees.jsp?msg=added_doc_failed&login_err=1");
                        } else {
                            response.sendRedirect("employees.jsp?msg=added_doc_failed");
                        }
                    } else {
                        if (createLogin && !generatedUsername.isEmpty()) {
                            response.sendRedirect("employees.jsp?msg=added_with_login");
                        } else if (loginCreationFailed) {
                            response.sendRedirect("employees.jsp?msg=added&login_err=1");
                        } else {
                            response.sendRedirect("employees.jsp?msg=added");
                        }
                    }
                } else {
                    con.rollback();
                    response.sendRedirect("add_employee.jsp?error=failed");
                }
            } catch (Exception e) {
                con.rollback();
                throw e;
            }
        }

        } catch (Exception e) {
            e.printStackTrace();
            response.sendRedirect("add_employee.jsp?error=server");
        }
    }

    private boolean canManageEmployeeRecords(String role) {
        return ("SUPER_ADMIN".equals(role) || "ADMIN".equals(role))
                || "DEPARTMENT_HEAD".equalsIgnoreCase(role);
    }

    private String generateNextEmployeeCode() {
        String nextEmployeeCode = "";

        String sql = "SELECT COALESCE(MAX(CAST(SUBSTRING(employee_code, 4) AS UNSIGNED)), 0) + 1 AS next_no "
                + "FROM employees "
                + "WHERE employee_code REGEXP '^EMP[0-9]+$'";

        try (Connection con = DBConnection.getConnection();
             PreparedStatement ps = con.prepareStatement(sql);
             ResultSet rs = ps.executeQuery()) {

            if (rs.next()) {
                nextEmployeeCode = String.format("EMP%03d", rs.getInt("next_no"));
            }
        } catch (Exception e) {
            e.printStackTrace();
        }

        return nextEmployeeCode;
    }

    private boolean isValidDepartment(int departmentId) {
        String sql = "SELECT COUNT(*) FROM departments WHERE department_id = ? AND status = 'ACTIVE'";

        try (Connection con = DBConnection.getConnection();
             PreparedStatement ps = con.prepareStatement(sql)) {

            ps.setInt(1, departmentId);

            try (ResultSet rs = ps.executeQuery()) {
                return rs.next() && rs.getInt(1) > 0;
            }
        } catch (Exception e) {
            e.printStackTrace();
        }

        return false;
    }

    private void sendNewEmployeeRecordNotice(
            int employeeId,
            String employeeCode,
            String employeeName,
            String employeeEmail,
            String phone,
            int departmentId,
            String departmentName,
            String designation,
            String joiningDate,
            String status,
            String createdBy,
            String creatorRole,
            String creatorEmail
    ) {
        try {
            NotificationEventService.EmailRouting routing = NotificationEventService.buildEmployeeRecipients("ADDED", employeeId);
            String toEmail = routing.getToEmail();
            String ccEmail = routing.getCcEmail();

            String subject = "IR-AMS | New Employee Record Created | " + safe(employeeCode, "N/A");

            // Fault: every one of these is either directly form-submitted
            // (employeeCode/employeeName/designation/employeeEmail/phone) or a
            // DB-sourced free-text field (departmentName), landing straight in an
            // HTML email body with no escaping - same class of finding already
            // fixed in DisposeAssetServlet earlier. HtmlEscapeUtil.escape() is a
            // no-op on already-plain text, so this is a pure hardening change.
            String detailsTable = "<tr><th>Status:</th><td>Record Created</td></tr>"
                    + "<tr><th>Priority:</th><td>Normal</td></tr>"
                    + "<tr><th>Module:</th><td>Employee Administration</td></tr>"
                    + "<tr><th>Reference ID:</th><td>" + HtmlEscapeUtil.escape(safe(employeeCode, "N/A")) + " / Employee ID " + (employeeId > 0 ? employeeId : "N/A") + "</td></tr>"
                    + "<tr><td colspan='2' style='background-color: #f1f5f9; text-align: center;'><b>EMPLOYEE RECORD</b></td></tr>"
                    + "<tr><th>Employee Code:</th><td>" + HtmlEscapeUtil.escape(safe(employeeCode, "N/A")) + "</td></tr>"
                    + "<tr><th>Name:</th><td>" + HtmlEscapeUtil.escape(safe(employeeName, "")) + "</td></tr>"
                    + "<tr><th>Department:</th><td>" + HtmlEscapeUtil.escape(safe(departmentName, "N/A")) + "</td></tr>"
                    + "<tr><th>Designation:</th><td>" + HtmlEscapeUtil.escape(safe(designation, "N/A")) + "</td></tr>"
                    + "<tr><th>Joining Date:</th><td>" + safe(joiningDate, "N/A") + "</td></tr>"
                    + "<tr><th>Record Status:</th><td>" + formatNormalText(status) + "</td></tr>"
                    + "<tr><td colspan='2' style='background-color: #f1f5f9; text-align: center;'><b>CONTACT DETAILS</b></td></tr>"
                    + "<tr><th>Email:</th><td>" + HtmlEscapeUtil.escape(safe(employeeEmail, "N/A")) + "</td></tr>"
                    + "<tr><th>Phone:</th><td>" + HtmlEscapeUtil.escape(safe(phone, "N/A")) + "</td></tr>"
                    + "<tr><td colspan='2' style='background-color: #f1f5f9; text-align: center;'><b>CREATED BY</b></td></tr>"
                    + "<tr><th>User:</th><td>" + HtmlEscapeUtil.escape(safe(createdBy, "N/A")) + "</td></tr>"
                    + "<tr><th>Role:</th><td>" + formatRoleName(creatorRole) + "</td></tr>"
                    + "<tr><th>Account:</th><td>" + HtmlEscapeUtil.escape(safe(creatorEmail, "N/A")) + "</td></tr>";
            
            String actionNote = getActionRequiredText(creatorRole);

            String body = NotificationHelper.buildHtmlEmail("", "NEW EMPLOYEE RECORD", detailsTable, actionNote);

            NotificationHelper.sendNotification(
                    getServletContext(),
                    "EMPLOYEE_ADMIN_ALERT",
                    "EMPLOYEE_MANAGEMENT",
                    employeeId,
                    toEmail,
                    ccEmail,
                    "",
                    subject,
                    body
            );

        } catch (Exception e) {
            e.printStackTrace();
        }
    }

    private String getActionRequiredText(String creatorRole) {
        if ("DEPARTMENT_HEAD".equalsIgnoreCase(creatorRole)) {
            return "Super Admin may review the newly created employee record for administrative verification and future system access processing.";
        }

        return "Review the employee record and ensure department, designation, contact details, and status are correct before asset allocation or system access processing.";
    }

    private String getDepartmentName(Connection con, int departmentId) {
        String sql = "SELECT department_name FROM departments WHERE department_id = ?";
        try (PreparedStatement ps = con.prepareStatement(sql)) {
            ps.setInt(1, departmentId);
            try (ResultSet rs = ps.executeQuery()) {
                if (rs.next()) {
                    return rs.getString("department_name");
                }
            }
        } catch (Exception e) {
            e.printStackTrace();
        }
        return "N/A";
    }

    private int getSessionInt(HttpSession session, String key, int fallback) {
        try {
            Object value = session.getAttribute(key);

            if (value == null) {
                return fallback;
            }

            return Integer.parseInt(String.valueOf(value));

        } catch (Exception e) {
            return fallback;
        }
    }

    private int parseInt(String value, int fallback) {
        try {
            return Integer.parseInt(clean(value));
        } catch (Exception e) {
            return fallback;
        }
    }

    private String clean(String value) {
        if (value == null) {
            return "";
        }

        return value.trim();
    }

    private String safe(String value, String fallback) {
        if (value == null || value.trim().isEmpty()) {
            return fallback;
        }

        return value.trim();
    }

    private String formatRoleName(String roleName) {
        if (roleName == null || roleName.trim().isEmpty()) {
            return "N/A";
        }

        String text = roleName.trim().replace("_", " ").toLowerCase();
        String[] words = text.split(" ");
        StringBuilder formatted = new StringBuilder();

        for (String word : words) {
            if (word.trim().isEmpty()) {
                continue;
            }

            formatted.append(word.substring(0, 1).toUpperCase())
                    .append(word.substring(1))
                    .append(" ");
        }

        return formatted.toString().trim();
    }

    private String formatNormalText(String value) {
        if (value == null || value.trim().isEmpty()) {
            return "N/A";
        }

        String text = value.trim().replace("_", " ").toLowerCase();
        return text.substring(0, 1).toUpperCase() + text.substring(1);
    }


    // ---- Helper stubs for username/role lookups used in user creation ----

    private String generateUsername(String employeeCode, String email) {
        return employeeCode.toLowerCase().replaceAll("[^a-z0-9_]", "");
    }

    private String generateTempPassword(String employeeCode) {
        java.security.SecureRandom rnd = new java.security.SecureRandom();
        String chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789!@#$%^&*";
        StringBuilder sb = new StringBuilder(12);
        for (int i = 0; i < 12; i++) {
            sb.append(chars.charAt(rnd.nextInt(chars.length())));
        }
        return sb.toString();
    }

    private boolean usernameExists(Connection con, String username) {
        try (PreparedStatement ps = con.prepareStatement(
                "SELECT COUNT(*) FROM users WHERE username = ?")) {
            ps.setString(1, username);
            try (ResultSet rs = ps.executeQuery()) {
                return rs.next() && rs.getInt(1) > 0;
            }
        } catch (Exception e) {
            return false;
        }
    }

    private int getRoleIdByName(Connection con, String roleName) {
        try (PreparedStatement ps = con.prepareStatement(
                "SELECT role_id FROM roles WHERE role_name = ? LIMIT 1")) {
            ps.setString(1, roleName);
            try (ResultSet rs = ps.executeQuery()) {
                if (rs.next()) {
                    return rs.getInt("role_id");
                }
            }
        } catch (Exception e) {
            e.printStackTrace();
        }
        return 0;
    }

    private int getUserIdByUsername(Connection con, String username) {
        try (PreparedStatement ps = con.prepareStatement(
                "SELECT user_id FROM users WHERE username = ? ORDER BY user_id DESC LIMIT 1")) {
            ps.setString(1, username);
            try (ResultSet rs = ps.executeQuery()) {
                if (rs.next()) {
                    return rs.getInt("user_id");
                }
            }
        } catch (Exception e) {
            e.printStackTrace();
        }
        return 0;
    }
}
