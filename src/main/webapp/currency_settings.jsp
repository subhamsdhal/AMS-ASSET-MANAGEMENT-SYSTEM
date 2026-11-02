<%@page contentType="text/html" pageEncoding="UTF-8"%>
<%@page import="com.mycompany.asset_management_system_ams.SettingsDAO"%>

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

    // Was SELECT currency, timezone FROM system_settings WHERE setting_id = 1 -
    // legacy columns UpdateCurrencySettingsServlet no longer writes to. Source
    // from SettingsDAO instead, the same store settings.jsp's Organization tab
    // reads/writes, so this page shows the real, live currency/timezone.
    String currency = SettingsDAO.getCurrency();
    String timezone = SettingsDAO.get("ams.system.timezone", "Asia/Kolkata");

    String msg = request.getParameter("msg");
    String error = request.getParameter("error");
%>

<!DOCTYPE html>
<html>
<head>
    <title>IR-AMS Currency Settings</title>

    <link rel="stylesheet"
          href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.0/css/all.min.css">

    <link rel="stylesheet" href="css/ir-glass.css?v=5000">

    <link rel="stylesheet" href="css/currency_settings.css?v=28001">
</head>

<body>

<div class="app">

    <jsp:include page="sidebar.jsp" />

    <main class="main">

        <jsp:include page="topbar.jsp" />

        <div class="main-scroll-content">

            <section class="asset-hero">
                <h1>Currency & Timezone Settings</h1>

                <p>
                    Configure the default financial currency and operational timezone used across
                    asset valuation, purchase cost, maintenance expense and report generation.
                </p>

                <br>

                <div class="hero-pills">
                    <div class="hero-pill">
                        <i class="fa-solid fa-indian-rupee-sign"></i> Currency Control
                    </div>

                    <div class="hero-pill">
                        <i class="fa-solid fa-clock"></i> Timezone
                    </div>

                    <div class="hero-pill">
                        <i class="fa-solid fa-file-excel"></i> Report Format
                    </div>

                    <div class="hero-pill">
                        <i class="fa-solid fa-lock"></i> Super Admin Only
                    </div>
                </div>
            </section>

            <% if ("updated".equals(msg)) { %>
                <div class="page-success">
                    <i class="fa-solid fa-circle-check"></i>
                    Currency and timezone settings updated successfully.
                </div>
            <% } else if ("invalid".equals(error)) { %>
                <div class="page-error">
                    <i class="fa-solid fa-triangle-exclamation"></i>
                    Please select valid currency and timezone values.
                </div>
            <% } else if ("server".equals(error)) { %>
                <div class="page-error">
                    <i class="fa-solid fa-triangle-exclamation"></i>
                    Server error occurred while updating currency settings.
                </div>
            <% } %>

            <section class="settings-form-grid">

                <div class="settings-form-card">

                    <h2>
                        <i class="fa-solid fa-sliders"></i>
                        Update Currency Settings
                    </h2>

                    <p>
                        Select the default currency and timezone. These values will reflect in
                        setting screens and can be used for future report formatting.
                    </p>

                    <form action="UpdateCurrencySettingsServlet" method="post">

                        <div class="form-group">
                            <label>
                                <i class="fa-solid fa-coins"></i>
                                Default Currency
                            </label>

                            <select name="currency" required>
                                <option value="INR" <%= "INR".equals(currency) ? "selected" : "" %>>INR - Indian Rupee ₹</option>
                                <option value="USD" <%= "USD".equals(currency) ? "selected" : "" %>>USD - US Dollar $</option>
                                <option value="EUR" <%= "EUR".equals(currency) ? "selected" : "" %>>EUR - Euro €</option>
                                <option value="GBP" <%= "GBP".equals(currency) ? "selected" : "" %>>GBP - Pound £</option>
                            </select>
                        </div>

                        <div class="form-group">
                            <label>
                                <i class="fa-solid fa-clock"></i>
                                Operational Timezone
                            </label>

                            <select name="timezone" required>
                                <option value="Asia/Kolkata" <%= "Asia/Kolkata".equals(timezone) ? "selected" : "" %>>Asia/Kolkata - India Standard Time</option>
                                <option value="UTC" <%= "UTC".equals(timezone) ? "selected" : "" %>>UTC - Coordinated Universal Time</option>
                                <option value="Asia/Dubai" <%= "Asia/Dubai".equals(timezone) ? "selected" : "" %>>Asia/Dubai - Gulf Standard Time</option>
                                <option value="Europe/London" <%= "Europe/London".equals(timezone) ? "selected" : "" %>>Europe/London</option>
                                <option value="America/New_York" <%= "America/New_York".equals(timezone) ? "selected" : "" %>>America/New_York</option>
                            </select>
                        </div>

                        <br>

                        <button type="submit" class="btn submit-btn">
                            <i class="fa-solid fa-floppy-disk"></i>
                            Save Settings
                        </button>

                        <a href="ams_copilot.jsp"><i class="fa-solid fa-robot"></i> AI Copilot</a>
              <a href="settings.jsp" class="btn secondary-btn">
                            <i class="fa-solid fa-arrow-left"></i>
                            Back to Settings
                        </a>

                    </form>

                </div>

                <div class="settings-form-card">

                    <h2>
                        <i class="fa-solid fa-eye"></i>
                        Current Configuration
                    </h2>

                    <p>
                        Active system-level financial and time configuration currently used by IR-AMS.
                    </p>

                    <div class="currency-preview">

                        <div class="preview-row">
                            <span>Default Currency</span>
                            <strong><%= currency %></strong>
                        </div>

                        <div class="preview-row">
                            <span>Currency Symbol</span>
                            <strong>
                                <%= "USD".equals(currency) ? "$" : "EUR".equals(currency) ? "€" : "GBP".equals(currency) ? "£" : "₹" %>
                            </strong>
                        </div>

                        <div class="preview-row">
                            <span>Timezone</span>
                            <strong><%= timezone %></strong>
                        </div>

                        <div class="preview-row">
                            <span>Access Level</span>
                            <strong>SUPER ADMIN</strong>
                        </div>

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
<script src="js/sidebar-role.js?v=10000"></script>

</body>
</html>