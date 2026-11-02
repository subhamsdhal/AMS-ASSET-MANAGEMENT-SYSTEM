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

@WebServlet(name = "UpdateCategoryVendorMappingStatusServlet", urlPatterns = {"/UpdateCategoryVendorMappingStatusServlet"})
public class UpdateCategoryVendorMappingStatusServlet extends HttpServlet {
    private static final Logger LOGGER = Logger.getLogger(UpdateCategoryVendorMappingStatusServlet.class.getName());


    // Enabling/disabling a category-vendor mapping is a state change and must
    // only happen on POST. This used to also accept doGet(), which meant a
    // plain <a href> link - or any third-party page embedding an
    // <img src="...UpdateCategoryVendorMappingStatusServlet?mappingId=5&action=disable">
    // tag, a crawler prefetching links, or a browser's link-prefetch feature -
    // could silently disable/enable a mapping for whichever admin/asset-manager
    // happened to have it loaded/visited while logged in, in turn silently
    // blocking new asset creation under that category+vendor pair (Module 4
    // requires an active mapping to exist). No caller in this webapp actually
    // reaches this servlet via GET (the UI uses the AJAX POST-only sibling,
    // CategoryVendorMappingAjaxServlet), matching the same fix already applied
    // to DisableEmployeeServlet, DeleteEmployeeServlet, DeleteDepartmentServlet,
    // UpdateCategoryStatusServlet, and DeleteVendorServlet.
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
                response.sendRedirect("category_vendor_mapping.jsp?access=denied");
                return;
            }

            int mappingId = parseInt(request.getParameter("mappingId"), parseInt(request.getParameter("id"), 0));
            String action = clean(request.getParameter("action")).toLowerCase();

            if (mappingId <= 0 || action.isEmpty()) {
                response.sendRedirect("category_vendor_mapping.jsp?error=invalid");
                return;
            }

            String status = "enable".equals(action) || "active".equals(action) ? "ACTIVE" : "INACTIVE";
            String auditAction = "ACTIVE".equals(status) ? "ENABLE" : "DISABLE";

            CategoryVendorMappingDAO dao = new CategoryVendorMappingDAO();
            boolean updated = dao.updateMappingStatus(mappingId, status);

            if (updated) {
                AuditDAO.log(userId, auditAction, "category_vendor_mapping", mappingId,
                        "Category-Supplier mapping status changed from UI and stored in MySQL. Mapping ID: "
                        + mappingId + ", Status: " + status + ", Updated by: " + username);
                try {
                    NotificationEventService.EmailRouting routing = NotificationEventService.buildMasterDataRecipients("UPDATED");
                    String detailsTable = "<tr><th>Action:</th><td>Category-Supplier Mapping Status Changed</td></tr>"
                            + "<tr><th>Mapping ID:</th><td>" + mappingId + "</td></tr>"
                            + "<tr><th>New Status:</th><td>" + status + "</td></tr>";
                    String body = NotificationHelper.buildHtmlEmail("", "MAPPING STATUS UPDATED", detailsTable, "");
                    NotificationHelper.sendNotification(
                            request.getServletContext(), "CATEGORY_ALERT", "CATEGORIES", mappingId, 
                            routing.getToEmail(), routing.getCcEmail(), "", "IR-AMS | Category-Supplier Mapping Status Updated", body);
                } catch (Exception e) {
                    e.printStackTrace();
                }
                response.sendRedirect("category_vendor_mapping.jsp?msg=updated");
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

    private String clean(String value) {
        return value == null ? "" : value.trim();
    }
}
