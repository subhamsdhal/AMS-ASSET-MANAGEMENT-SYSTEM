<%@page contentType="text/html" pageEncoding="UTF-8"%>
<%@page import="com.mycompany.asset_management_system_ams.SettingsDAO"%>

<%!
    private String safeValue(String value) {
        if (value == null) {
            return "";
        }

        return value
                .replace("&", "&amp;")
                .replace("<", "&lt;")
                .replace(">", "&gt;")
                .replace("\"", "&quot;")
                .replace("'", "&#39;");
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

    if (!("SUPER_ADMIN".equals(role) || "ADMIN".equals(role))) {
        response.sendRedirect("settings.jsp?access=denied");
        return;
    }

    // Was SELECT * FROM system_settings WHERE setting_id = 1 - legacy columns that
    // UpdateProfileServlet no longer writes to (nothing else in the app ever read
    // them either). Source from SettingsDAO instead, the same store settings.jsp's
    // Organization tab reads/writes, so this page shows the real, live profile.
    String orgName = SettingsDAO.getOrgName();
    String systemName = SettingsDAO.getSystemName();
    String officeLocation = SettingsDAO.getOrgLocation();
    String contactEmail = SettingsDAO.getContactEmail();
    String supportPhone = SettingsDAO.getSupportPhone();
    String currency = SettingsDAO.getCurrency();
    String description = SettingsDAO.get("ams.system.description", "");
    // Fault: the Profile Preview panel below reads "timezone" but this page never
    // declared it - unlike every other field on this same preview, which all have
    // a matching SettingsDAO-backed variable above. 100% JasperException on every
    // visit. Fix: source it the same way settings.jsp does.
    String timezone = SettingsDAO.get("ams.system.timezone", "Asia/Kolkata");

    String msg = request.getParameter("msg");
    String error = request.getParameter("error");
%>

<!DOCTYPE html>
<html>
<head>
    <title>IR-AMS Edit Profile</title>

    <link rel="stylesheet"
          href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.0/css/all.min.css">

    <link rel="stylesheet" href="css/ir-glass.css?v=5000">

    <link rel="stylesheet" href="css/edit_profile.css?v=28001">
</head>

<body>

<div class="app">

    <jsp:include page="sidebar.jsp" />

    <main class="main">

        <jsp:include page="topbar.jsp" />

        <div class="main-scroll-content">

            <section class="asset-hero">
                <h1>Edit Organization Profile</h1>

                <p>
                    Update the official IR-AMS organization profile, system name, office location,
                    support contact details and project description used across the settings console.
                </p>

                <br>

                <div class="hero-pills">
                    <div class="hero-pill">
                        <i class="fa-solid fa-building"></i> Organization
                    </div>

                    <div class="hero-pill">
                        <i class="fa-solid fa-envelope"></i> Contact
                    </div>

                    <div class="hero-pill">
                        <i class="fa-solid fa-circle-info"></i> System Profile
                    </div>

                    <div class="hero-pill">
                        <i class="fa-solid fa-lock"></i> Super Admin Only
                    </div>
                </div>
            </section>

            <% if ("updated".equals(msg)) { %>
                <div class="page-success">
                    <i class="fa-solid fa-circle-check"></i>
                    Organization profile updated successfully.
                </div>
            <% } else if ("invalid".equals(error)) { %>
                <div class="page-error">
                    <i class="fa-solid fa-triangle-exclamation"></i>
                    Please fill all required profile fields correctly.
                </div>
            <% } else if ("server".equals(error)) { %>
                <div class="page-error">
                    <i class="fa-solid fa-triangle-exclamation"></i>
                    Server error occurred while updating organization profile.
                </div>
            <% } %>

            <section class="profile-layout">

                <div class="profile-form-card">

                    <h2>
                        <i class="fa-solid fa-pen-to-square"></i>
                        Profile Configuration
                    </h2>

                    <p>
                        Keep this profile professional because it represents the system identity
                        during project demonstration and report review.
                    </p>

                    <form action="UpdateProfileServlet" method="post">

                        <div class="form-grid">

                            <div class="form-group">
                                <label>
                                    <i class="fa-solid fa-building"></i>
                                    Organization Name
                                </label>

                                <input type="text"
                                       name="orgName"
                                       value="<%= safeValue(orgName) %>"
                                       placeholder="Indian Railway"
                                       maxlength="100"
                                       required>
                            </div>

                            <div class="form-group">
                                <label>
                                    <i class="fa-solid fa-desktop"></i>
                                    System Name
                                </label>

                                <input type="text"
                                       name="systemName"
                                       value="<%= safeValue(systemName) %>"
                                       placeholder="Asset Management System"
                                       maxlength="120"
                                       required>
                            </div>

                            <div class="form-group">
                                <label>
                                    <i class="fa-solid fa-location-dot"></i>
                                    Office Location
                                </label>

                                <input type="text"
                                       name="officeLocation"
                                       value="<%= safeValue(officeLocation) %>"
                                       placeholder="Bhubaneswar Railway Control Room"
                                       maxlength="180"
                                       required>
                            </div>

                            <div class="form-group">
                                <label>
                                    <i class="fa-solid fa-envelope"></i>
                                    Contact Email
                                </label>

                                <input type="email"
                                       name="contactEmail"
                                       value="<%= safeValue(contactEmail) %>"
                                       placeholder="support@irams.local"
                                       maxlength="120"
                                       required>
                            </div>

                            <div class="form-group">
                                <label>
                                    <i class="fa-solid fa-phone"></i>
                                    Support Phone
                                </label>

                                <input type="text"
                                       name="supportPhone"
                                       value="<%= safeValue(supportPhone) %>"
                                       placeholder="+91-0000000000"
                                       maxlength="30"
                                       required>
                            </div>

                            <div class="form-group">
                                <label>
                                    <i class="fa-solid fa-indian-rupee-sign"></i>
                                    Current Currency
                                </label>

                                <input type="text"
                                       value="<%= safeValue(currency) %>"
                                       readonly>
                            </div>

                            <div class="form-group full">
                                <label>
                                    <i class="fa-solid fa-align-left"></i>
                                    System Description
                                </label>

                                <textarea name="description"
                                          placeholder="Write system description..."
                                          maxlength="700"
                                          required><%= safeValue(description) %></textarea>
                            </div>

                        </div>

                        <div class="profile-actions">
                            <button type="submit" class="btn submit-btn">
                                <i class="fa-solid fa-floppy-disk"></i>
                                Save Profile
                            </button>

                            <a href="ams_copilot.jsp"><i class="fa-solid fa-robot"></i> AI Copilot</a>
              <a href="settings.jsp" class="btn secondary-btn">
                                <i class="fa-solid fa-arrow-left"></i>
                                Back to Settings
                            </a>
                        </div>

                    </form>

                </div>

                <div class="profile-preview-card">

                    <div class="preview-logo">
                        <i class="fa-solid fa-train-subway"></i>
                    </div>

                    <h2>Profile Preview</h2>

                    <p>
                        This preview reflects the currently saved IR-AMS organization profile.
                    </p>

                    <div class="profile-preview-row">
                        <span>Organization</span>
                        <strong><%= safeValue(orgName) %></strong>
                    </div>

                    <div class="profile-preview-row">
                        <span>System Name</span>
                        <strong><%= safeValue(systemName) %></strong>
                    </div>

                    <div class="profile-preview-row">
                        <span>Office Location</span>
                        <strong><%= safeValue(officeLocation) %></strong>
                    </div>

                    <div class="profile-preview-row">
                        <span>Contact Email</span>
                        <strong><%= safeValue(contactEmail) %></strong>
                    </div>

                    <div class="profile-preview-row">
                        <span>Support Phone</span>
                        <strong><%= safeValue(supportPhone) %></strong>
                    </div>

                    <div class="profile-preview-row">
                        <span>Timezone</span>
                        <strong><%= safeValue(timezone) %></strong>
                    </div>

                </div>

            </section>

        </div>

    </main>

</div>
<script>
    const contextPath = "<%= request.getContextPath() %>";

    const railBackgrounds = [
        contextPath + "/images/rail-bg-1.jpg",
        contextPath + "/images/rail-bg-2.jpg",
        contextPath + "/images/rail-bg-3.jpg",
        contextPath + "/images/rail-bg-4.jpg",
        contextPath + "/images/rail-bg-5.jpg",
        contextPath + "/images/rail-bg-6.jpg",
        contextPath + "/images/rail-bg-7.jpg"
    ];

    let currentBgIndex = 0;

    function changeRailBackground() {
        currentBgIndex++;

        if (currentBgIndex >= railBackgrounds.length) {
            currentBgIndex = 0;
        }

        document.body.style.setProperty(
                "--rail-bg",
                "url('" + railBackgrounds[currentBgIndex] + "')"
        );
    }

    setInterval(changeRailBackground, 90000);
</script>

<script src="js/topbar-search.js?v=6000000"></script>
<script src="js/user-dropdown.js?v=4"></script>
<script src="js/sidebar-role.js?v=11000"></script>

</body>
</html>