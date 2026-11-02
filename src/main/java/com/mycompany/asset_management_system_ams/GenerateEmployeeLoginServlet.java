package com.mycompany.asset_management_system_ams;

import java.io.IOException;
import java.security.SecureRandom;
import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;

import jakarta.servlet.ServletException;
import jakarta.servlet.annotation.WebServlet;
import jakarta.servlet.http.HttpServlet;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import jakarta.servlet.http.HttpSession;

@WebServlet(name = "GenerateEmployeeLoginServlet", urlPatterns = {"/GenerateEmployeeLoginServlet"})
public class GenerateEmployeeLoginServlet extends HttpServlet {

    @Override
    protected void doPost(HttpServletRequest request, HttpServletResponse response)
            throws ServletException, IOException {

        response.setContentType("application/json");
        response.setCharacterEncoding("UTF-8");

        HttpSession session = request.getSession(false);
        if (session == null || session.getAttribute("username") == null) {
            response.getWriter().write("{\"status\": \"error\", \"error\": \"Session expired. Please login again.\"}");
            return;
        }

        String role = (String) session.getAttribute("role");
        if (!("SUPER_ADMIN".equals(role) || "ADMIN".equals(role)) && !"ASSET_MANAGER".equalsIgnoreCase(role)) {
            response.getWriter().write("{\"status\": \"error\", \"error\": \"Access denied. You cannot generate logins.\"}");
            return;
        }

        int adminId = getSessionInt(session, "user_id", 1);
        if (adminId == 1) {
            adminId = getSessionInt(session, "userId", 1);
        }

        int employeeId = parseInt(request.getParameter("employeeId"), -1);
        if (employeeId <= 0) {
            response.getWriter().write("{\"status\": \"error\", \"error\": \"Invalid employee ID.\"}");
            return;
        }

        String action = request.getParameter("action");
        if (action == null) {
            action = "generate";
        }

        try (Connection con = DBConnection.getConnection()) {
            // Check if employee exists and already has a login
            String empCode = null;
            String email = null;
            int existingUserId = 0;

            String getEmpSql = "SELECT employee_code, email, user_id FROM employees WHERE employee_id = ?";
            try (PreparedStatement ps = con.prepareStatement(getEmpSql)) {
                ps.setInt(1, employeeId);
                try (ResultSet rs = ps.executeQuery()) {
                    if (rs.next()) {
                        empCode = rs.getString("employee_code");
                        email = rs.getString("email");
                        existingUserId = rs.getInt("user_id");
                        if (rs.wasNull()) {
                            existingUserId = 0;
                        }
                    } else {
                        response.getWriter().write("{\"status\": \"error\", \"error\": \"Employee not found.\"}");
                        return;
                    }
                }
            }

            if ("reset".equals(action)) {
                if (existingUserId <= 0) {
                    response.getWriter().write("{\"status\": \"error\", \"error\": \"Employee does not have a login account yet.\"}");
                    return;
                }
                
                String username = null;
                try (PreparedStatement psUser = con.prepareStatement("SELECT username FROM users WHERE user_id = ?")) {
                    psUser.setInt(1, existingUserId);
                    try (ResultSet rsUser = psUser.executeQuery()) {
                        if (rsUser.next()) {
                            username = rsUser.getString("username");
                        }
                    }
                }
                
                if (username == null) {
                    response.getWriter().write("{\"status\": \"error\", \"error\": \"User record not found.\"}");
                    return;
                }

                // Product decision (explicit, requested twice, risk explained
                // both times): temp password is username+"123" again, not the
                // cryptographically random generateSecurePassword() this
                // branch used previously. This reopens a real account-takeover
                // path - anyone who knows/guesses an employee's username can
                // compute their password before the real employee ever logs
                // in, which also bypasses force_password_change=1's practical
                // protection (the attacker is the one prompted to set the
                // real password). force_password_change=1 is still set below
                // regardless, per the same request, so at least the known
                // default cannot stand indefinitely once the real employee
                // does get in.
                String generatedPassword = username + "123";
                String hashedPassword = PasswordUtil.hash(generatedPassword);

                // password_plaintext is never populated with the real password (security
                // fix, see CHANGELOG-fixes.md Login-2) - the generated password is only
                // ever returned once, in this response, for the admin to hand to the
                // employee; it is not retained anywhere in the database.
                try (PreparedStatement psUpdate = con.prepareStatement(
                        "UPDATE users SET password_plaintext = ?, password_crypt = ?, force_password_change = 1 WHERE user_id = ?")) {
                    psUpdate.setString(1, "");
                    psUpdate.setString(2, hashedPassword);
                    psUpdate.setInt(3, existingUserId);
                    psUpdate.executeUpdate();
                }

                AuditDAO.log(
                        adminId,
                        "UPDATE",
                        "users",
                        existingUserId,
                        "Password reset generated for employee " + empCode
                );

                String jsonResponse = String.format(
                        "{\"status\": \"ok\", \"tempPassword\": \"%s\"}",
                        generatedPassword
                );
                response.getWriter().write(jsonResponse);
                return;
            }

            if (existingUserId > 0) {
                response.getWriter().write("{\"status\": \"error\", \"error\": \"Employee already has a login account.\"}");
                return;
            }

            // Generate
            String generatedUsername = generateUsername(empCode);

            // Ensure unique username
            int attempt = 2;
            String tryUsername = generatedUsername;
            while (usernameExists(con, tryUsername) && attempt < 20) {
                tryUsername = generatedUsername + "_" + attempt;
                attempt++;
            }
            generatedUsername = tryUsername;
            
            // Product decision (explicit, requested twice, risk explained both
            // times): temp password is username+"123" again, not the
            // cryptographically random generateSecurePassword() this branch
            // used previously. This reopens a real account-takeover path -
            // anyone who knows/guesses an employee's username (visible on ID
            // badges, QR labels, employee lists, or predictable from
            // employee_code) can compute their password before the real
            // employee ever logs in, which also bypasses
            // force_password_change=1's practical protection (the attacker is
            // the one prompted to set the real password, locking the
            // legitimate employee out). force_password_change=1 is still set
            // below regardless, per the same request.
            String generatedPassword = generatedUsername + "123";

            int employeeRoleId = getRoleIdByName(con, "EMPLOYEE");
            String hashedPassword = PasswordUtil.hash(generatedPassword);

            con.setAutoCommit(false);
            try {
                // Insert User
                // password_plaintext left blank - see note above on the "reset" branch.
                String insertUser = "INSERT INTO users "
                        + "(username, password_plaintext, password_crypt, email, role_id, employee_id, status, force_password_change, created_by, created_at) "
                        + "VALUES (?, ?, ?, ?, ?, ?, 'ACTIVE', 1, ?, NOW())";

                try (PreparedStatement psu = con.prepareStatement(insertUser, java.sql.Statement.RETURN_GENERATED_KEYS)) {
                    psu.setString(1, generatedUsername);
                    psu.setString(2, "");
                    psu.setString(3, hashedPassword);
                    psu.setString(4, email != null ? email : "");
                    psu.setInt(5, employeeRoleId);
                    psu.setInt(6, employeeId);
                    psu.setInt(7, adminId);
                    psu.executeUpdate();

                    int newUserId = 0;
                    try (ResultSet rsKeys = psu.getGeneratedKeys()) {
                        if (rsKeys.next()) {
                            newUserId = rsKeys.getInt(1);
                        }
                    }

                    if (newUserId > 0) {
                        try (PreparedStatement pse = con.prepareStatement(
                                "UPDATE employees SET user_id = ? WHERE employee_id = ?")) {
                            pse.setInt(1, newUserId);
                            pse.setInt(2, employeeId);
                            pse.executeUpdate();
                        }
                    }
                }

                AuditDAO.log(
                        adminId,
                        "ADD",
                        "users",
                        employeeId, // Target ID (employee)
                        "Login account generated for employee " + empCode + " (Username: " + generatedUsername + ")"
                );

                con.commit();
                
                try {
                    NotificationEventService.EmailRouting routing = NotificationEventService.buildEmployeeRecipients("LOGIN_CREATED", employeeId);
                    String toEmail = routing.getToEmail();
                    String ccEmail = routing.getCcEmail();
                    if (toEmail != null && !toEmail.isEmpty()) {
                        String subject = "IR-AMS | Account Created | " + generatedUsername;
                        String detailsTable = "<tr><th>Action:</th><td>Login Account Created</td></tr>"
                                + "<tr><th>Username:</th><td>" + generatedUsername + "</td></tr>";
                        String actionNote = "Contact the Admin for your temporary password.";
                        String body = NotificationHelper.buildHtmlEmail("", "ACCOUNT CREATED", detailsTable, actionNote);
                        NotificationHelper.sendNotification(
                                getServletContext(), "ACCOUNT_ALERT", "EMPLOYEE_MANAGEMENT", employeeId, 
                                toEmail, ccEmail, "", subject, body);
                    }
                } catch (Exception e) {
                    e.printStackTrace();
                }
                
                String jsonResponse = String.format(
                        "{\"status\": \"ok\", \"username\": \"%s\", \"tempPassword\": \"%s\"}",
                        generatedUsername, generatedPassword
                );
                response.getWriter().write(jsonResponse);

            } catch (Exception e) {
                con.rollback();
                throw e;
            }

        } catch (Exception e) {
            e.printStackTrace();
            response.setStatus(HttpServletResponse.SC_INTERNAL_SERVER_ERROR);
            response.getWriter().write("{\"status\": \"error\", \"error\": \"Internal server error: " + e.getMessage() + "\"}");
        }
    }

    private String generateUsername(String employeeCode) {
        return employeeCode.toLowerCase().replaceAll("[^a-z0-9_]", "");
    }

    // Cryptographically random 12-character temporary password: upper, lower,
    // digit, and symbol pools guaranteed at least one pick each (so it always
    // clears any complexity check downstream), remaining characters drawn from
    // the combined pool, then shuffled so the guaranteed characters aren't
    // always in the same first-four positions. SecureRandom, not Random/Math.random,
    // since this value briefly gates real account access.
    private static final String PWD_UPPER = "ABCDEFGHJKLMNPQRSTUVWXYZ"; // no I/O
    private static final String PWD_LOWER = "abcdefghijkmnopqrstuvwxyz"; // no l
    private static final String PWD_DIGIT = "23456789"; // no 0/1
    private static final String PWD_SYMBOL = "!@#$%&*";
    private static final SecureRandom PWD_RANDOM = new SecureRandom();

    private String generateSecurePassword() {
        String all = PWD_UPPER + PWD_LOWER + PWD_DIGIT + PWD_SYMBOL;
        char[] chars = new char[12];
        chars[0] = PWD_UPPER.charAt(PWD_RANDOM.nextInt(PWD_UPPER.length()));
        chars[1] = PWD_LOWER.charAt(PWD_RANDOM.nextInt(PWD_LOWER.length()));
        chars[2] = PWD_DIGIT.charAt(PWD_RANDOM.nextInt(PWD_DIGIT.length()));
        chars[3] = PWD_SYMBOL.charAt(PWD_RANDOM.nextInt(PWD_SYMBOL.length()));
        for (int i = 4; i < chars.length; i++) {
            chars[i] = all.charAt(PWD_RANDOM.nextInt(all.length()));
        }
        for (int i = chars.length - 1; i > 0; i--) {
            int j = PWD_RANDOM.nextInt(i + 1);
            char tmp = chars[i];
            chars[i] = chars[j];
            chars[j] = tmp;
        }
        return new String(chars);
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
        return 5; // Default fallback to 5 (assuming 5 is EMPLOYEE)
    }

    private int getSessionInt(HttpSession session, String attr, int defaultVal) {
        Object val = session.getAttribute(attr);
        if (val == null) return defaultVal;
        try {
            return Integer.parseInt(val.toString());
        } catch (Exception e) {
            return defaultVal;
        }
    }

    private int parseInt(String val, int defaultVal) {
        if (val == null || val.trim().isEmpty()) return defaultVal;
        try {
            return Integer.parseInt(val.trim());
        } catch (Exception e) {
            return defaultVal;
        }
    }
}
