package com.mycompany.asset_management_system_ams;

import java.util.logging.Logger;
import java.util.logging.Level;


import java.io.IOException;
import jakarta.servlet.ServletException;
import jakarta.servlet.annotation.WebServlet;
import jakarta.servlet.http.HttpServlet;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import jakarta.servlet.http.HttpSession;

@WebServlet(name = "UpdateCategoryStatusServlet", urlPatterns = {"/UpdateCategoryStatusServlet"})
public class UpdateCategoryStatusServlet extends HttpServlet {
    private static final Logger LOGGER = Logger.getLogger(UpdateCategoryStatusServlet.class.getName());


    // Enabling/disabling a category is a state change and must only happen on
    // POST. This used to also accept doGet(), which meant a plain <a href> link
    // - or any third-party page embedding an <img src="...UpdateCategoryStatusServlet
    // ?id=5&action=disable"> tag, a crawler prefetching links, or a browser's
    // link-prefetch feature - could silently disable/enable a category for
    // whichever admin/asset-manager happened to have it loaded/visited while
    // logged in. categories.jsp's Enable/Disable links were converted to POST
    // forms (matching the pattern already used by UpdateRequestStatusServlet on
    // asset_requests.jsp) to match.
    @Override
    protected void doPost(HttpServletRequest request, HttpServletResponse response)
            throws ServletException, IOException {
        process(request, response);
    }

    private void process(HttpServletRequest request, HttpServletResponse response)
            throws IOException {
        try {
            HttpSession session = request.getSession(false);
            if (session == null || session.getAttribute("username") == null || session.getAttribute("role") == null) {
                response.sendRedirect("login.jsp");
                return;
            }

            String username = String.valueOf(session.getAttribute("username"));
            String role = String.valueOf(session.getAttribute("role"));
            int userId = getSessionInt(session, "user_id", getSessionInt(session, "userId", 1));

            if (!("SUPER_ADMIN".equals(role) || "ADMIN".equals(role)) && !"ASSET_MANAGER".equalsIgnoreCase(role)) {
                response.sendRedirect("categories.jsp?access=denied");
                return;
            }

            int categoryId = parseInt(request.getParameter("id"), parseInt(request.getParameter("categoryId"), 0));
            String action = clean(request.getParameter("action")).toLowerCase();

            if (categoryId <= 0 || action.isEmpty()) {
                response.sendRedirect("categories.jsp?error=invalid");
                return;
            }

            String isActive = "enable".equals(action) || "active".equals(action) ? "YES" : "NO";
            String auditAction = "YES".equals(isActive) ? "ENABLE" : "DISABLE";

            CategoryDAO dao = new CategoryDAO();
            boolean updated = dao.updateCategoryStatus(categoryId, isActive);

            if (updated) {
                AuditDAO.log(userId, auditAction, "asset_categories", categoryId,
                        "Category status changed from UI and stored in MySQL. Category ID: "
                        + categoryId + ", Active: " + isActive + ", Updated by: " + username);
                try {
                    NotificationEventService.EmailRouting routing = NotificationEventService.buildMasterDataRecipients("UPDATED");
                    String detailsTable = "<tr><th>Action:</th><td>Category Status Changed</td></tr>"
                            + "<tr><th>Category ID:</th><td>" + categoryId + "</td></tr>"
                            + "<tr><th>New Status:</th><td>" + isActive + "</td></tr>";
                    String body = NotificationHelper.buildHtmlEmail("", "CATEGORY STATUS UPDATED", detailsTable, "");
                    NotificationHelper.sendNotification(
                            request.getServletContext(), "CATEGORY_ALERT", "CATEGORIES", categoryId,
                            routing.getToEmail(), routing.getCcEmail(), "", "IR-AMS | Category Status Updated | ID: " + categoryId, body);
                } catch (Exception e) {
                    e.printStackTrace();
                }
                // Fault, found live: this redirected with msg=updated no matter
                // which action ran, even though categories.jsp already has
                // dedicated "Category enabled successfully." / "Category disabled
                // successfully." banners (msg=enabled / msg=disabled) that this
                // servlet is the only caller of - they were simply never reached.
                // Confirmed live: disabling a category worked correctly (KPI
                // counts moved, DB updated) but showed the generic, misleading
                // "Category updated successfully." instead.
                response.sendRedirect("categories.jsp?msg=" + ("YES".equals(isActive) ? "enabled" : "disabled"));
            } else {
                response.sendRedirect("categories.jsp?error=failed");
            }

        } catch (Exception e) {
            LOGGER.log(Level.SEVERE, "Exception occurred", e);
            response.sendRedirect("categories.jsp?error=server");
        }
    }

    private int parseInt(String value, int defaultValue) {
        try {
            return Integer.parseInt(value);
        } catch (Exception e) {
            return defaultValue;
        }
    }

    private int getSessionInt(HttpSession session, String key, int defaultValue) {
        try {
            Object value = session.getAttribute(key);
            return value == null ? defaultValue : Integer.parseInt(String.valueOf(value));
        } catch (Exception e) {
            return defaultValue;
        }
    }

    private String clean(String value) {
        return value == null ? "" : value.trim();
    }
}
