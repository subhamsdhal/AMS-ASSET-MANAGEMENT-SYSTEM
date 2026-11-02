<%@page contentType="text/html" pageEncoding="UTF-8"%>
<%@page import="com.mycompany.asset_management_system_ams.Vendor"%>
<%@page import="com.mycompany.asset_management_system_ams.VendorDAO"%>
<%@page import="java.util.Locale"%>

<%!
    private String safeText(Object value) {
        if (value == null || value.toString().trim().isEmpty()) {
            return "";
        }

        return value.toString().trim()
                .replace("&", "&amp;")
                .replace("<", "&lt;")
                .replace(">", "&gt;")
                .replace("\"", "&quot;")
                .replace("'", "&#39;");
    }

    private String displayText(Object value) {
        if (value == null || value.toString().trim().isEmpty()) {
            return "N/A";
        }

        return safeText(value);
    }

    private String cleanLabel(String value) {
        if (value == null || value.trim().isEmpty()) {
            return "N/A";
        }

        String text = value.trim().replace("_", " ").toLowerCase(Locale.ENGLISH);
        String[] parts = text.split("\\s+");
        StringBuilder out = new StringBuilder();

        for (String part : parts) {
            if (part.length() > 0) {
                out.append(Character.toUpperCase(part.charAt(0))).append(part.substring(1)).append(" ");
            }
        }

        return out.toString().trim();
    }
%>

<%
    String username = (String) session.getAttribute("username");
    String role = (String) session.getAttribute("role");

    response.setHeader("Cache-Control", "no-cache, no-store, must-revalidate");
    response.setHeader("Pragma", "no-cache");
    response.setDateHeader("Expires", 0);

    if (username == null || role == null) {
        response.sendRedirect("login.jsp");
        return;
    }

    boolean canManageSuppliers = ("SUPER_ADMIN".equals(role) || "ADMIN".equals(role))
            || "ASSET_MANAGER".equals(role);

    if (!canManageSuppliers) {
        response.sendRedirect("vendors.jsp?access=denied");
        return;
    }

    int vendorId = 0;

    try {
        vendorId = Integer.parseInt(request.getParameter("id"));
    } catch (Exception e) {
        response.sendRedirect("vendors.jsp?error=failed");
        return;
    }

    VendorDAO dao = new VendorDAO();
    Vendor vendor = dao.getVendorById(vendorId);

    if (vendor == null) {
        response.sendRedirect("vendors.jsp?error=failed");
        return;
    }

    String error = request.getParameter("error");
    String userInitial = username.substring(0, Math.min(2, username.length())).toUpperCase(Locale.ENGLISH);
%>

<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>Edit Supplier - IR-AMS</title>

    <link rel="stylesheet"
          href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.0/css/all.min.css">

    <link rel="stylesheet" href="css/ir-glass.css?v=inner-category-supplier-1">
    <link rel="stylesheet" href="css/ams-pro.css?v=inner-category-supplier-1">
    <link rel="stylesheet" href="css/ir-ams-railway-ui.css?v=inner-category-supplier-1">
<link rel="stylesheet" href="css/edit_vendor.css?v=topbarfix1">
</head>

<body class="railway-ui">
<div class="app ams-shell">

    <jsp:include page="sidebar.jsp" />

    <main class="main railway-main">
        <jsp:include page="topbar.jsp" />

        <div class="main-scroll-content edit-supplier-board">

            <section class="edit-supplier-hero">
                <h1>Edit Supplier</h1>

                <p>
                    Update supplier contact information, communication details and official address
                    used for railway procurement, warranty and asset lifecycle records.
                </p>

                <div class="hero-pills">
                    <div class="hero-pill">
                        <i class="fa-solid fa-truck-field"></i>
                        Supplier Update
                    </div>

                    <div class="hero-pill">
                        <i class="fa-solid fa-pen-to-square"></i>
                        Editable Record
                    </div>

                    <div class="hero-pill">
                        <i class="fa-solid fa-link"></i>
                        Linked Assets: <%= vendor.getAssetCount() %>
                    </div>

                    <div class="hero-pill">
                        <i class="fa-solid fa-shield-halved"></i>
                        Admin Controlled
                    </div>
                </div>
            </section>

            <section class="supplier-panel">

                <div class="supplier-panel-head">
                    <div>
                        <h2>Supplier Update Form</h2>
                        <p>
                            Supplier ID SUP-<%= vendor.getVendorId() %>. Backend names remain vendor-based for database safety.
                        </p>
                    </div>

                    <span class="access-pill">
                        <i class="fa-solid fa-shield-halved"></i>
                        <%= displayText(cleanLabel(role)) %> Access
                    </span>
                </div>

                <% if ("failed".equals(error)) { %>
                    <div class="supplier-alert">
                        <i class="fa-solid fa-triangle-exclamation"></i>
                        Supplier could not be updated. Please check the details.
                    </div>
                <% } %>

                <form action="UpdateVendorServlet" method="post" id="editSupplierForm">

                    <input type="hidden" name="vendorId" value="<%= vendor.getVendorId() %>">

                    <div class="supplier-form-grid">

                        <div class="supplier-form-group">
                            <label>
                                <i class="fa-solid fa-building"></i>
                                Supplier Name
                            </label>

                            <input type="text"
                                   name="vendorName"
                                   value="<%= safeText(vendor.getVendorName()) %>"
                                   required>
                        </div>

                        <div class="supplier-form-group">
                            <label>
                                <i class="fa-solid fa-user-tie"></i>
                                Contact Person
                            </label>

                            <input type="text"
                                   name="contactPerson"
                                   value="<%= safeText(vendor.getContactPerson()) %>"
                                   required>
                        </div>

                        <div class="supplier-form-group">
                            <label>
                                <i class="fa-solid fa-envelope"></i>
                                Email
                            </label>

                            <input type="email"
                                   name="email"
                                   value="<%= safeText(vendor.getEmail()) %>"
                                   required>
                        </div>

                        <div class="supplier-form-group">
                            <label>
                                <i class="fa-solid fa-phone"></i>
                                Phone
                            </label>

                            <%-- Fault, found live: same mismatch as add_vendor.jsp
                                 - UpdateVendorServlet.java treats phone as
                                 optional (blank accepted and stored as ""), so
                                 marking it required here only blocked clearing
                                 a phone number that was already wrong, with no
                                 explanation why. --%>
                            <input type="text"
                                   name="phone"
                                   value="<%= safeText(vendor.getPhone()) %>"
                                   maxlength="20">
                        </div>

                        <div class="supplier-form-group full-width">
                            <label>
                                <i class="fa-solid fa-location-dot"></i>
                                Address
                            </label>

                            <%-- Same fault as phone above - UpdateVendorServlet.java
                                 never validates address at all. --%>
                            <textarea name="address"
                                      rows="4"><%= safeText(vendor.getAddress()) %></textarea>
                        </div>

                    </div>

                    <div class="supplier-note">
                        <i class="fa-solid fa-circle-info"></i>

                        <div>
                            <strong>Important:</strong>
                            Changing supplier name or contact details will reflect wherever this supplier is shown in asset records,
                            category-supplier mapping and warranty/maintenance details.
                        </div>
                    </div>

                    <div class="form-actions">
                        <button type="submit" class="supplier-btn">
                            <i class="fa-solid fa-circle-check"></i>
                            Update Supplier
                        </button>

                        <a href="view_vendor.jsp?id=<%= vendor.getVendorId() %>" class="supplier-btn green">
                            <i class="fa-solid fa-eye"></i>
                            View Supplier
                        </a>

                        <a href="vendors.jsp" class="supplier-btn secondary">
                            <i class="fa-solid fa-arrow-left"></i>
                            Back to Suppliers
                        </a>
                    </div>

                </form>

            </section>

        </div>

    </main>

</div>

<script src="js/topbar-search.js?v=inner-category-supplier-1"></script>
<script src="js/user-dropdown.js?v=inner-category-supplier-1"></script>
<script src="js/sidebar-role.js?v=inner-category-supplier-1"></script>
<script src="js/ir-body-watermark.js?v=inner-category-supplier-1"></script>
<script src="js/dashboard-actions.js?v=inner-category-supplier-1"></script>

</body>
</html>
