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

@WebServlet(name = "AddCategoryVendorMappingServlet", urlPatterns = {"/AddCategoryVendorMappingServlet"})
public class AddCategoryVendorMappingServlet extends HttpServlet {
    private static final Logger LOGGER = Logger.getLogger(AddCategoryVendorMappingServlet.class.getName());


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

            if (!("SUPER_ADMIN".equals(role) || "ADMIN".equals(role)) && !"ASSET_MANAGER".equalsIgnoreCase(role)) {
                response.sendRedirect("category_vendor_mapping.jsp?access=denied");
                return;
            }

            int categoryId = parseInt(request.getParameter("categoryId"), 0);
            int vendorId = parseInt(request.getParameter("vendorId"), 0);

            if (categoryId <= 0 || vendorId <= 0) {
                response.sendRedirect("category_vendor_mapping.jsp?error=invalid");
                return;
            }

            CategoryVendorMappingDAO dao = new CategoryVendorMappingDAO();
            
            String currentStatus = dao.getMappingStatus(categoryId, vendorId);

            if ("ACTIVE".equals(currentStatus)) {
                response.sendRedirect("category_vendor_mapping.jsp?msg=duplicate");
                return;
            }

            boolean saved = dao.addOrReactivateMapping(categoryId, vendorId);

            if (saved) {
                AuditDAO.log(userId, "ADD_OR_REACTIVATE", "category_vendor_mapping", 0,
                        "Category-Supplier mapping saved from UI and stored in MySQL. Category ID: "
                        + categoryId + ", Supplier ID: " + vendorId + ", Updated by: " + username);
                try {
                    NotificationEventService.EmailRouting routing = NotificationEventService.buildMasterDataRecipients("UPDATED");
                    String detailsTable = "<tr><th>Action:</th><td>Category-Supplier Mapping Added</td></tr>"
                            + "<tr><th>Category ID:</th><td>" + categoryId + "</td></tr>"
                            + "<tr><th>Supplier ID:</th><td>" + vendorId + "</td></tr>";
                    String body = NotificationHelper.buildHtmlEmail("", "MAPPING ADDED", detailsTable, "");
                    NotificationHelper.sendNotification(
                            request.getServletContext(), "CATEGORY_ALERT", "CATEGORIES", 0, 
                            routing.getToEmail(), routing.getCcEmail(), "", "IR-AMS | Category-Supplier Mapping Added", body);
                } catch (Exception e) {
                    e.printStackTrace();
                }
                
                if ("INACTIVE".equals(currentStatus)) {
                    response.sendRedirect("category_vendor_mapping.jsp?msg=reactivated");
                } else {
                    response.sendRedirect("category_vendor_mapping.jsp?msg=mapped");
                }
            } else {
                response.sendRedirect("category_vendor_mapping.jsp?error=failed");
            }

        } catch (Exception e) {
            LOGGER.log(Level.SEVERE, "Exception occurred", e);
            response.sendRedirect("category_vendor_mapping.jsp?error=server");
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
}
