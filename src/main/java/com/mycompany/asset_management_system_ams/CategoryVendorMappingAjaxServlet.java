package com.mycompany.asset_management_system_ams;

import java.io.IOException;
import java.io.PrintWriter;
import java.util.logging.Logger;
import java.util.logging.Level;
import jakarta.servlet.ServletException;
import jakarta.servlet.annotation.WebServlet;
import jakarta.servlet.http.HttpServlet;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import jakarta.servlet.http.HttpSession;

@WebServlet(name = "CategoryVendorMappingAjaxServlet", urlPatterns = {"/CategoryVendorMappingAjaxServlet"})
public class CategoryVendorMappingAjaxServlet extends HttpServlet {
    private static final Logger LOGGER = Logger.getLogger(CategoryVendorMappingAjaxServlet.class.getName());

    @Override
    protected void doPost(HttpServletRequest request, HttpServletResponse response)
            throws ServletException, IOException {

        response.setContentType("application/json");
        response.setCharacterEncoding("UTF-8");
        PrintWriter out = response.getWriter();

        HttpSession session = request.getSession(false);
        if (session == null || session.getAttribute("username") == null) {
            response.setStatus(HttpServletResponse.SC_UNAUTHORIZED);
            out.print("{\"success\":false,\"error\":\"Not authenticated\"}");
            out.flush();
            return;
        }

        String role = (String) session.getAttribute("role");
        boolean canManage = ("SUPER_ADMIN".equals(role) || "ADMIN".equals(role) || "ASSET_MANAGER".equalsIgnoreCase(role));

        if (!canManage) {
            response.setStatus(HttpServletResponse.SC_FORBIDDEN);
            out.print("{\"success\":false,\"error\":\"Access denied\"}");
            out.flush();
            return;
        }

        String mappingIdParam = request.getParameter("mappingId");
        String action = request.getParameter("action");

        if (mappingIdParam == null || mappingIdParam.trim().isEmpty() || action == null || action.trim().isEmpty()) {
            out.print("{\"success\":false,\"error\":\"Missing parameters\"}");
            out.flush();
            return;
        }

        try {
            int mappingId = Integer.parseInt(mappingIdParam);
            String status = "enable".equalsIgnoreCase(action) ? "ACTIVE" : "INACTIVE";

            CategoryVendorMappingDAO dao = new CategoryVendorMappingDAO();
            boolean updated = dao.updateMappingStatus(mappingId, status);

            if (updated) {
                // category_vendor_mapping.jsp's Activate/Deactivate button calls this
                // endpoint (not UpdateCategoryVendorMappingStatusServlet, which is unused
                // from the UI) - it was updating the DB with no AuditDAO entry and no
                // notification email at all, unlike every other mapping/category mutation
                // in this module. Every real activate/deactivate in production was
                // silently invisible to the audit log. Matched to the sibling servlet's
                // logging so this action is no longer an audit-trail gap.
                String username = String.valueOf(session.getAttribute("username"));
                int userId = getSessionInt(session, "user_id", getSessionInt(session, "userId", 1));
                String auditAction = "ACTIVE".equals(status) ? "ENABLE" : "DISABLE";

                AuditDAO.log(userId, auditAction, "category_vendor_mapping", mappingId,
                        "Category-Supplier mapping status changed from UI (AJAX) and stored in MySQL. Mapping ID: "
                        + mappingId + ", Status: " + status + ", Updated by: " + username);

                try {
                    NotificationEventService.EmailRouting routing = NotificationEventService.buildMasterDataRecipients("UPDATED");
                    String detailsTable = "<tr><th>Action:</th><td>Category-Supplier Mapping Status Changed</td></tr>"
                            + "<tr><th>Mapping ID:</th><td>" + mappingId + "</td></tr>"
                            + "<tr><th>New Status:</th><td>" + status + "</td></tr>";
                    String body = NotificationHelper.buildHtmlEmail("", "MAPPING STATUS UPDATED", detailsTable, "");
                    NotificationHelper.sendNotification(
                            getServletContext(), "CATEGORY_ALERT", "CATEGORIES", mappingId,
                            routing.getToEmail(), routing.getCcEmail(), "", "IR-AMS | Category-Supplier Mapping Status Updated", body);
                } catch (Exception notifyEx) {
                    LOGGER.log(Level.WARNING, "Mapping status notification failed", notifyEx);
                }

                out.print("{\"success\":true}");
            } else {
                out.print("{\"success\":false,\"error\":\"Failed to update mapping status\"}");
            }
        } catch (NumberFormatException e) {
            out.print("{\"success\":false,\"error\":\"Invalid mapping ID\"}");
        } catch (Exception e) {
            LOGGER.log(Level.SEVERE, "Exception occurred while toggling mapping status via AJAX", e);
            response.setStatus(HttpServletResponse.SC_INTERNAL_SERVER_ERROR);
            out.print("{\"success\":false,\"error\":\"Server error occurred\"}");
        } finally {
            out.flush();
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
