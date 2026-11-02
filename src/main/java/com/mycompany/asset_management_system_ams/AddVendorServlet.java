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

@WebServlet(name = "AddVendorServlet", urlPatterns = {"/AddVendorServlet"})
public class AddVendorServlet extends HttpServlet {
    private static final Logger LOGGER = Logger.getLogger(AddVendorServlet.class.getName());


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
                response.sendRedirect("vendors.jsp?access=denied");
                return;
            }

            String vendorName = clean(request.getParameter("vendorName"));
            String contactPerson = clean(request.getParameter("contactPerson"));
            String email = clean(request.getParameter("email"));
            String phone = request.getParameter("phone");
            if (phone != null && !phone.trim().isEmpty()) {
                phone = PhoneValidationUtil.validatePhone(phone);
                if (phone == null) {
                    response.sendRedirect("add_vendor.jsp?error=invalidphone");
                    return;
                }
            } else {
                phone = "";
            }
            String address = clean(request.getParameter("address"));

            if (vendorName.isEmpty()) {
                response.sendRedirect("add_vendor.jsp?error=failed");
                return;
            }

            VendorDAO dao = new VendorDAO();
            int vendorId = dao.addVendorAndReturnId(vendorName, contactPerson, email, phone, address);

            if (vendorId > 0) {
                AuditDAO.log(userId, "ADD", "vendors", vendorId,
                        "Supplier added from UI and stored in MySQL. Supplier: " + vendorName
                        + ", Added by: " + username);
                try {
                    NotificationEventService.EmailRouting routing = NotificationEventService.buildMasterDataRecipients("ADDED");
                    // Fault (Medium, fixed): vendorName/contactPerson/email are free text
                    // embedded unescaped - same recurring class as
                    // audit/10-maintenance.md Finding 1.
                    String detailsTable = "<tr><th>Action:</th><td>New Supplier Added</td></tr>"
                            + "<tr><th>Supplier Name:</th><td>" + HtmlEscapeUtil.escape(vendorName) + "</td></tr>"
                            + "<tr><th>Contact:</th><td>" + HtmlEscapeUtil.escape(contactPerson) + " (" + HtmlEscapeUtil.escape(email) + ")</td></tr>";
                    String body = NotificationHelper.buildHtmlEmail("", "SUPPLIER ADDED", detailsTable, "");
                    NotificationHelper.sendNotification(
                            request.getServletContext(), "VENDOR_ALERT", "SUPPLIERS", vendorId, 
                            routing.getToEmail(), routing.getCcEmail(), "", "IR-AMS | Supplier Added | " + vendorName, body);
                } catch (Exception e) {
                    e.printStackTrace();
                }
                response.sendRedirect("vendors.jsp?msg=added");
            } else {
                AuditDAO.log(userId, "ADD_BLOCKED", "vendors", 0,
                        "Supplier add failed from UI. Possible duplicate supplier name/email: "
                        + vendorName + ", Attempted by: " + username);
                response.sendRedirect("add_vendor.jsp?error=failed");
            }

        } catch (Exception e) {
            LOGGER.log(Level.SEVERE, "Exception occurred", e);
            response.sendRedirect("add_vendor.jsp?error=server");
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
