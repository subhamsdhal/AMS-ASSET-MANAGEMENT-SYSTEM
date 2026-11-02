package com.mycompany.asset_management_system_ams;

import java.io.IOException;
import java.util.Arrays;
import java.util.List;

import jakarta.servlet.ServletException;
import jakarta.servlet.annotation.WebServlet;
import jakarta.servlet.http.HttpServlet;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import jakarta.servlet.http.HttpSession;

@WebServlet(name = "UpdateCurrencySettingsServlet", urlPatterns = {"/UpdateCurrencySettingsServlet"})
public class UpdateCurrencySettingsServlet extends HttpServlet {

    private static final List<String> ALLOWED_CURRENCIES = Arrays.asList("INR", "USD", "EUR", "GBP");

    private static final List<String> ALLOWED_TIMEZONES = Arrays.asList(
            "Asia/Kolkata",
            "UTC",
            "Asia/Dubai",
            "Europe/London",
            "America/New_York"
    );

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

            String currency = request.getParameter("currency");
            String timezone = request.getParameter("timezone");

            if (currency == null || timezone == null
                    || !ALLOWED_CURRENCIES.contains(currency)
                    || !ALLOWED_TIMEZONES.contains(timezone)) {
                response.sendRedirect("currency_settings.jsp?error=invalid");
                return;
            }

            int userId = getSessionUserId(session);

            // Fault: this used to UPDATE system_settings.currency/timezone - legacy
            // columns nothing else in the app ever reads. Every save on this page
            // showed "updated successfully" while the live currency (read everywhere
            // else via SettingsDAO.getCurrency(), e.g. settings.jsp's Organization
            // tab) never changed. Route through the same ams.* keys SaveSettingsServlet
            // uses, so this page is no longer a no-op and both places always agree.
            SettingsDAO.set("ams.system.currency", currency, userId);
            SettingsDAO.set("ams.system.timezone", timezone, userId);

            try {
                AuditDAO.log(
                        userId,
                        "UPDATE",
                        "system_settings",
                        1,
                        "Currency settings updated by " + username
                                + ". Currency: " + currency
                                + ", Timezone: " + timezone
                );
            } catch (Exception auditException) {
                System.err.println("AuditDAO error: " + auditException.getMessage());
            }

            response.sendRedirect("currency_settings.jsp?msg=updated");

        } catch (Exception e) {
            System.err.println("UpdateCurrencySettingsServlet error: " + e.getMessage());
            response.sendRedirect("currency_settings.jsp?error=server");
        }
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