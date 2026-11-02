package com.mycompany.asset_management_system_ams;

import java.io.IOException;

import jakarta.servlet.ServletException;
import jakarta.servlet.annotation.WebServlet;
import jakarta.servlet.http.HttpServlet;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import jakarta.servlet.http.HttpSession;

@WebServlet(name = "UpdateProfileServlet", urlPatterns = {"/UpdateProfileServlet"})
public class UpdateProfileServlet extends HttpServlet {

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

            String username = session.getAttribute("username").toString();
            String role = session.getAttribute("role").toString();

            if (!("SUPER_ADMIN".equals(role) || "ADMIN".equals(role))) {
                response.sendRedirect("settings.jsp?access=denied");
                return;
            }

            String orgName = clean(request.getParameter("orgName"));
            String systemName = clean(request.getParameter("systemName"));
            String officeLocation = clean(request.getParameter("officeLocation"));
            String contactEmail = clean(request.getParameter("contactEmail"));
            String supportPhone = PhoneValidationUtil.validatePhone(request.getParameter("supportPhone"));
            String description = clean(request.getParameter("description"));

            if (orgName.isEmpty()
                    || systemName.isEmpty()
                    || officeLocation.isEmpty()
                    || contactEmail.isEmpty()
                    || description.isEmpty()
                    || orgName.length() > 100
                    || systemName.length() > 120
                    || officeLocation.length() > 180
                    || contactEmail.length() > 120
                    || description.length() > 700
                    || !contactEmail.matches("^[A-Za-z0-9+_.-]+@[A-Za-z0-9.-]+$")) {

                response.sendRedirect("edit_profile.jsp?error=invalid");
                return;
            }

            if (supportPhone == null) {
                response.sendRedirect("edit_profile.jsp?error=invalidphone");
                return;
            }

            int userId = getSessionUserId(session);

            // Fault: this used to UPDATE system_settings.org_name/currency/etc - legacy
            // columns nothing else in the app ever reads. Every save on this page
            // showed "updated successfully" while the live profile (read everywhere
            // else via SettingsDAO, e.g. settings.jsp's Organization tab) never
            // changed. Route through the same ams.* keys SaveSettingsServlet's
            // Organization tab uses, so this page is no longer a no-op and both
            // places always agree.
            SettingsDAO.set("ams.organization.name", orgName, userId);
            SettingsDAO.set("ams.system.name", systemName, userId);
            SettingsDAO.set("ams.organization.location", officeLocation, userId);
            SettingsDAO.set("ams.system.contact.email", contactEmail, userId);
            SettingsDAO.set("ams.system.support.phone", supportPhone, userId);
            SettingsDAO.set("ams.system.description", description, userId);

            try {
                AuditDAO.log(
                        userId,
                        "UPDATE",
                        "system_settings",
                        1,
                        "Organization profile updated by " + username
                                + ". Organization: " + orgName
                                + ", System: " + systemName
                );
            } catch (Exception auditException) {
                auditException.printStackTrace();
            }

            response.sendRedirect("edit_profile.jsp?msg=updated");

        } catch (Exception e) {
            e.printStackTrace();
            response.sendRedirect("edit_profile.jsp?error=server");
        }
    }

    private String clean(String value) {
        if (value == null) {
            return "";
        }

        return value.trim();
    }

    private int getSessionUserId(HttpSession session) {
        // Defaulting to 1 here would misattribute this audit-log entry to whichever
        // real account happens to be user_id 1. AuditDAO.log() resolves 0/null to a
        // NULL "system" row instead, so 0 is the safe default when the session
        // attribute is missing or unparseable.
        Object userIdObj = session.getAttribute("user_id");

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
}