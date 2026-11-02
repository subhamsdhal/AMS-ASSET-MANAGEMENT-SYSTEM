<%@page contentType="text/html" pageEncoding="UTF-8"%>
<%@page import="java.util.Locale"%>

<%!
    private String safeText(Object value) {
        if (value == null || value.toString().trim().isEmpty()) {
            return "N/A";
        }

        return value.toString().trim()
                .replace("&", "&amp;")
                .replace("<", "&lt;")
                .replace(">", "&gt;")
                .replace("\"", "&quot;")
                .replace("'", "&#39;");
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

    String error = request.getParameter("error");
    String userInitial = username.substring(0, Math.min(2, username.length())).toUpperCase(Locale.ENGLISH);
%>

<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>Add Supplier - IR-AMS</title>

    <link rel="stylesheet"
          href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.0/css/all.min.css">

    <link rel="stylesheet" href="css/ir-glass.css?v=inner-category-supplier-1">
    <link rel="stylesheet" href="css/ams-pro.css?v=inner-category-supplier-1">
    <link rel="stylesheet" href="css/ir-ams-railway-ui.css?v=inner-category-supplier-1">
<link rel="stylesheet" href="css/add_vendor.css?v=topbarfix1">
</head>

<body class="railway-ui">
<div class="app ams-shell">

    <jsp:include page="sidebar.jsp" />

    <main class="main railway-main">
        <jsp:include page="topbar.jsp" />
        <div class="main-scroll-content add-supplier-board">

            <section class="add-supplier-hero">
                <h1>Add New Supplier</h1>

                <p>
                    Register a new railway procurement supplier with official contact details,
                    email, phone number and address for asset purchase and warranty records.
                </p>

                <div class="hero-pills">
                    <div class="hero-pill">
                        <i class="fa-solid fa-truck-field"></i> Supplier Entry
                    </div>

                    <div class="hero-pill">
                        <i class="fa-solid fa-address-book"></i> Contact Mapping
                    </div>

                    <div class="hero-pill">
                        <i class="fa-solid fa-boxes-stacked"></i> Procurement Support
                    </div>

                    <div class="hero-pill">
                        <i class="fa-solid fa-database"></i> MySQL Insert
                    </div>
                </div>
            </section>

            <section class="supplier-panel">

                <div class="supplier-panel-head">
                    <div>
                        <h2>Supplier Registration Form</h2>
                        <p>
                            Add supplier details carefully. These records will be used in asset purchase, warranty and category-supplier mapping.
                        </p>
                    </div>

                    <span class="access-pill">
                        <i class="fa-solid fa-shield-halved"></i>
                        <%= safeText(cleanLabel(role)) %> Access
                    </span>
                </div>

                <%
                    if ("failed".equals(error)) {
                %>
                    <div class="supplier-alert">
                        <i class="fa-solid fa-triangle-exclamation"></i>
                        Supplier could not be added. Please check the details.
                    </div>
                <%
                    } else if ("server".equals(error)) {
                %>
                    <div class="supplier-alert">
                        <i class="fa-solid fa-triangle-exclamation"></i>
                        Server error occurred while adding supplier.
                    </div>
                <%
                    }
                %>

                <form action="AddVendorServlet" method="post" id="addSupplierForm">

                    <div class="supplier-form-grid">

                        <div class="supplier-form-group">
                            <label>
                                <i class="fa-solid fa-building"></i>
                                Supplier Name
                            </label>

                            <input type="text"
                                   name="vendorName"
                                   placeholder="Example: Dell India Pvt. Ltd."
                                   required>
                        </div>

                        <div class="supplier-form-group">
                            <label>
                                <i class="fa-solid fa-user-tie"></i>
                                Contact Person
                            </label>

                            <input type="text"
                                   name="contactPerson"
                                   placeholder="Example: Rahul Sharma"
                                   required>
                        </div>

                        <div class="supplier-form-group">
                            <label>
                                <i class="fa-solid fa-envelope"></i>
                                Email
                            </label>

                            <input type="email"
                                   name="email"
                                   placeholder="Example: supplier@company.com"
                                   required>
                        </div>

                        <div class="supplier-form-group">
                            <label>
                                <i class="fa-solid fa-phone"></i>
                                Phone
                            </label>

                            <%-- Fault, found live: this was marked required, but
                                 AddVendorServlet.java treats phone as genuinely
                                 optional (blank is accepted and stored as "") -
                                 the form was rejecting submissions the server
                                 itself has never required, with no visible
                                 explanation of why. Not required, matching what
                                 the server actually enforces. --%>
                            <input type="text"
                                   name="phone"
                                   placeholder="Example: 9876543210 (optional)"
                                   maxlength="20">
                        </div>

                        <div class="supplier-form-group full-width">
                            <label>
                                <i class="fa-solid fa-location-dot"></i>
                                Address
                            </label>

                            <%-- Same fault as phone above - AddVendorServlet.java
                                 never validates address at all, so it was never
                                 truly required server-side either. --%>
                            <textarea name="address"
                                      rows="4"
                                      placeholder="Example: Bhubaneswar, Odisha (optional)"></textarea>
                        </div>

                    </div>

                    <div class="supplier-note">
                        <i class="fa-solid fa-circle-info"></i>

                        <div>
                            <strong>Important:</strong>
                            Supplier records are stored in the existing vendor table internally.
                            UI shows Supplier, but backend names remain unchanged for project safety.
                        </div>
                    </div>

                    <div class="form-actions">
                        <button type="submit" class="supplier-btn">
                            <i class="fa-solid fa-circle-check"></i>
                            Save Supplier
                        </button>

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