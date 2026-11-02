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

@WebServlet(name = "UpdateCategoryServlet", urlPatterns = {"/UpdateCategoryServlet"})
public class UpdateCategoryServlet extends HttpServlet {
    private static final Logger LOGGER = Logger.getLogger(UpdateCategoryServlet.class.getName());


    @Override
    protected void doPost(HttpServletRequest request, HttpServletResponse response)
            throws ServletException, IOException {

        int categoryId = 0;

        try {
            request.setCharacterEncoding("UTF-8");

            HttpSession session = request.getSession(false);
            if (session == null || session.getAttribute("username") == null || session.getAttribute("role") == null) {
                response.sendRedirect("login.jsp");
                return;
            }

            String username = String.valueOf(session.getAttribute("username"));
            String role = String.valueOf(session.getAttribute("role"));
            int userId = getSessionInt(session, "user_id", getSessionInt(session, "userId", 1));

            if (!canManage(role)) {
                response.sendRedirect("categories.jsp?access=denied");
                return;
            }

            categoryId = parseInt(request.getParameter("categoryId"), 0);
            String categoryName = clean(request.getParameter("categoryName"));
            String description = clean(request.getParameter("description"));
            String isActive = clean(request.getParameter("isActive"));

            if (categoryId <= 0 || categoryName.isEmpty() || description.isEmpty()) {
                response.sendRedirect("edit_category.jsp?id=" + categoryId + "&error=failed");
                return;
            }

            if (isActive.isEmpty()) {
                isActive = "YES";
            }

            CategoryDAO dao = new CategoryDAO();
            boolean updated = dao.updateCategory(categoryId, categoryName, description, isActive);

            if (updated) {
                AuditDAO.log(userId, "UPDATE", "asset_categories", categoryId,
                        "Category updated from UI and stored in MySQL. Category: " + categoryName
                        + ", Active: " + isActive + ", Updated by: " + username);
                        
                try {
                    NotificationEventService.EmailRouting routing = NotificationEventService.buildMasterDataRecipients("UPDATED");
                    // Fault (Medium, fixed): categoryName is free text embedded unescaped -
                    // same recurring class as audit/10-maintenance.md Finding 1.
                    String detailsTable = "<tr><th>Action:</th><td>Category Updated</td></tr>"
                            + "<tr><th>Category Name:</th><td>" + HtmlEscapeUtil.escape(categoryName) + "</td></tr>"
                            + "<tr><th>Status:</th><td>" + isActive + "</td></tr>";
                    String body = NotificationHelper.buildHtmlEmail("", "CATEGORY UPDATED", detailsTable, "");
                    NotificationHelper.sendNotification(
                            getServletContext(), "CATEGORY_ALERT", "CATEGORIES", categoryId, 
                            routing.getToEmail(), routing.getCcEmail(), "", "IR-AMS | Category Updated | " + categoryName, body);
                } catch (Exception e) {
                    e.printStackTrace();
                }

                response.sendRedirect("categories.jsp?msg=updated");
            } else {
                AuditDAO.log(userId, "UPDATE_BLOCKED", "asset_categories", categoryId,
                        "Category update failed from UI. Category ID: " + categoryId
                        + ", Attempted by: " + username);
                response.sendRedirect("edit_category.jsp?id=" + categoryId + "&error=failed");
            }

        } catch (Exception e) {
            LOGGER.log(Level.SEVERE, "Exception occurred", e);
            response.sendRedirect("edit_category.jsp?id=" + categoryId + "&error=server");
        }
    }

    private boolean canManage(String role) {
        return ("SUPER_ADMIN".equals(role) || "ADMIN".equals(role)) || "ASSET_MANAGER".equalsIgnoreCase(role);
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
