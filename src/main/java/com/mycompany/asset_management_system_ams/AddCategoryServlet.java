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

@WebServlet(name = "AddCategoryServlet", urlPatterns = {"/AddCategoryServlet"})
public class AddCategoryServlet extends HttpServlet {
    private static final Logger LOGGER = Logger.getLogger(AddCategoryServlet.class.getName());


    @Override
    protected void doPost(HttpServletRequest request, HttpServletResponse response)
            throws ServletException, IOException {

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

            String categoryName = clean(request.getParameter("categoryName"));
            String description = clean(request.getParameter("description"));

            if (categoryName.isEmpty() || description.isEmpty()) {
                response.sendRedirect("add_category.jsp?error=failed");
                return;
            }

            CategoryDAO dao = new CategoryDAO();
            int categoryId = dao.addCategoryAndReturnId(categoryName, description);

            if (categoryId > 0) {
                AuditDAO.log(userId, "ADD", "asset_categories", categoryId,
                        "Category added from UI and stored in MySQL. Category: " + categoryName
                        + ", Added by: " + username);
                        
                try {
                    NotificationEventService.EmailRouting routing = NotificationEventService.buildMasterDataRecipients("ADDED");
                    // Fault (Medium, fixed): categoryName/description are free text embedded
                    // unescaped - same recurring class as audit/10-maintenance.md Finding 1.
                    String detailsTable = "<tr><th>Action:</th><td>New Category Added</td></tr>"
                            + "<tr><th>Category Name:</th><td>" + HtmlEscapeUtil.escape(categoryName) + "</td></tr>"
                            + "<tr><th>Description:</th><td>" + HtmlEscapeUtil.escape(description) + "</td></tr>";
                    String body = NotificationHelper.buildHtmlEmail("", "CATEGORY ADDED", detailsTable, "");
                    NotificationHelper.sendNotification(
                            getServletContext(), "CATEGORY_ALERT", "CATEGORIES", categoryId, 
                            routing.getToEmail(), routing.getCcEmail(), "", "IR-AMS | Category Added | " + categoryName, body);
                } catch (Exception e) {
                    e.printStackTrace();
                }

                response.sendRedirect("categories.jsp?msg=added");
            } else {
                AuditDAO.log(userId, "ADD_BLOCKED", "asset_categories", 0,
                        "Category add failed from UI. Possible duplicate category name: " + categoryName
                        + ", Attempted by: " + username);
                response.sendRedirect("add_category.jsp?error=failed");
            }

        } catch (Exception e) {
            LOGGER.log(Level.SEVERE, "Exception occurred", e);
            response.sendRedirect("add_category.jsp?error=server");
        }
    }

    private boolean canManage(String role) {
        return ("SUPER_ADMIN".equals(role) || "ADMIN".equals(role)) || "ASSET_MANAGER".equalsIgnoreCase(role);
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
