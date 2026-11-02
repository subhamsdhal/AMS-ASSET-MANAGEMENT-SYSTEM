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

@WebServlet(name = "DeleteVendorServlet", urlPatterns = {"/DeleteVendorServlet"})
public class DeleteVendorServlet extends HttpServlet {
    private static final Logger LOGGER = Logger.getLogger(DeleteVendorServlet.class.getName());


    // Disabling a supplier is a state change (vendor_status -> INACTIVE, plus
    // cascading its category-supplier mappings to INACTIVE) and must only
    // happen on POST - this used to also accept doGet(), reachable via a
    // plain <a href> link on vendors.jsp with only a client-side confirm()
    // dialog for protection. Same "state change via GET" pattern fixed
    // repeatedly elsewhere in this audit.
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
                response.sendRedirect("vendors.jsp?access=denied");
                return;
            }

            int vendorId = parseInt(request.getParameter("id"), parseInt(request.getParameter("vendorId"), 0));
            if (vendorId <= 0) {
                response.sendRedirect("vendors.jsp?error=invalid");
                return;
            }

            // Fault, found live: vendors.jsp had no way to show a disabled
            // supplier as anything other than a normal active row (see
            // Vendor.java's status field note) - once "deleted", a supplier
            // could never be brought back from the UI at all. action=enable
            // added as a sibling of the original disable behavior (still the
            // default, so the existing delete form below - and anything else
            // posting here without an action param - keeps working exactly
            // as before) rather than as a new servlet, so the existing
            // RoleAccessUtil permission entry for this path covers it too.
            String action = clean(request.getParameter("action"));
            boolean reactivate = "enable".equalsIgnoreCase(action);

            VendorDAO dao = new VendorDAO();
            boolean ok = reactivate ? dao.reactivateVendor(vendorId) : dao.deleteVendor(vendorId);

            if (ok) {
                AuditDAO.log(userId, reactivate ? "ENABLE" : "DISABLE", "vendors", vendorId,
                        "Supplier " + (reactivate ? "reactivated" : "disabled") + " from UI and MySQL vendor_status changed to "
                        + (reactivate ? "ACTIVE" : "INACTIVE") + ". Supplier ID: " + vendorId + ", Updated by: " + username);
                try {
                    NotificationEventService.EmailRouting routing = NotificationEventService.buildMasterDataRecipients(reactivate ? "UPDATED" : "DELETED");
                    String detailsTable = "<tr><th>Action:</th><td>" + (reactivate ? "Supplier Reactivated" : "Supplier Deleted (Disabled)") + "</td></tr>"
                            + "<tr><th>Supplier ID:</th><td>" + vendorId + "</td></tr>";
                    String body = NotificationHelper.buildHtmlEmail("", reactivate ? "SUPPLIER REACTIVATED" : "SUPPLIER DELETED", detailsTable, "");
                    NotificationHelper.sendNotification(
                            request.getServletContext(), "VENDOR_ALERT", "SUPPLIERS", vendorId,
                            routing.getToEmail(), routing.getCcEmail(), "", "IR-AMS | Supplier " + (reactivate ? "Reactivated" : "Deleted") + " | ID: " + vendorId, body);
                } catch (Exception e) {
                    e.printStackTrace();
                }
                response.sendRedirect("vendors.jsp?msg=" + (reactivate ? "reactivated" : "deleted"));
            } else {
                response.sendRedirect("vendors.jsp?error=" + (reactivate ? "reactivatefailed" : "deletefailed"));
            }

        } catch (Exception e) {
            LOGGER.log(Level.SEVERE, "Exception occurred", e);
            response.sendRedirect("vendors.jsp?error=server");
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
