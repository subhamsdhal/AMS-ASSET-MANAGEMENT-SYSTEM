<%@page contentType="text/html" pageEncoding="UTF-8"%>
<%@page import="com.mycompany.asset_management_system_ams.Category"%>
<%@page import="com.mycompany.asset_management_system_ams.CategoryDAO"%>

<%!
    private String safeText(String value) {
        if (value == null || value.trim().isEmpty()) {
            return "";
        }
        return value.trim()
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

    boolean canManageCategories = ("SUPER_ADMIN".equals(role) || "ADMIN".equals(role))
            || "ASSET_MANAGER".equals(role);

    if (!canManageCategories) {
        response.sendRedirect("categories.jsp?access=denied");
        return;
    }

    int categoryId = 0;

    try {
        categoryId = Integer.parseInt(request.getParameter("id"));
    } catch (Exception e) {
        response.sendRedirect("categories.jsp?error=failed");
        return;
    }

    CategoryDAO dao = new CategoryDAO();
    Category category = dao.getCategoryById(categoryId);

    if (category == null) {
        response.sendRedirect("categories.jsp?error=failed");
        return;
    }

    String error = request.getParameter("error");
    String activeStatus = category.getIsActive() == null ? "YES" : category.getIsActive();
%>

<!DOCTYPE html>
<html>
<head>
    <title>IR-AMS Edit Category</title>

    <link rel="stylesheet"
          href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.0/css/all.min.css">

    <link rel="stylesheet" href="css/ir-glass.css?v=inner-category-supplier-1">
    <link rel="stylesheet" href="css/ams-pro.css?v=inner-category-supplier-1">
    <link rel="stylesheet" href="css/ir-ams-railway-ui.css?v=inner-category-supplier-1">
<link rel="stylesheet" href="css/edit_category.css?v=topbarfix1">
</head>

<body class="railway-ui">

<div class="app">

    <jsp:include page="sidebar.jsp" />

    <main class="main railway-main">
        <jsp:include page="topbar.jsp" />

        <div class="main-scroll-content">

            <section class="add-employee-hero">
                <h1>Edit Category</h1>

                <p>
                    Update railway asset category name, description and active status used by
                    asset registration, request workflow and reporting modules.
                </p>

                <br>

                <div class="hero-pills">
                    <div class="hero-pill">
                        <i class="fa-solid fa-layer-group"></i> CAT-<%= category.getCategoryId() %>
                    </div>

                    <div class="hero-pill">
                        <i class="fa-solid fa-boxes-stacked"></i> <%= category.getAssetCount() %> Assets
                    </div>

                    <div class="hero-pill">
                        <i class="fa-solid fa-file-circle-plus"></i> <%= category.getRequestCount() %> Requests
                    </div>

                    <div class="hero-pill">
                        <i class="fa-solid fa-shield-halved"></i> Admin Controlled
                    </div>
                </div>
            </section>

            <section class="glass-panel">

                <h2>Category Update Form</h2>
                <br>

                <% if ("failed".equals(error)) { %>
                    <div class="alert-error">
                        Category could not be updated. Please check the details.
                    </div>
                <% } %>

                <form action="UpdateCategoryServlet" method="post">

                    <input type="hidden" name="categoryId" value="<%= category.getCategoryId() %>">

                    <div class="form-grid">

                        <div class="form-group">
                            <label>Category Name</label>
                            <input type="text"
                                   name="categoryName"
                                   value="<%= safeText(category.getCategoryName()) %>"
                                   required>
                        </div>

                        <div class="form-group">
                            <label>Status</label>
                            <select name="isActive" required>
                                <option value="YES" <%= "YES".equals(activeStatus) ? "selected" : "" %>>Active</option>
                                <option value="NO" <%= "NO".equals(activeStatus) ? "selected" : "" %>>Inactive</option>
                            </select>
                        </div>

                        <div class="form-group full-width">
                            <label>Description</label>
                            <textarea name="description"
                                      rows="4"
                                      required><%= safeText(category.getDescription()) %></textarea>
                        </div>

                    </div>

                    <br>

                    <div class="form-actions">
                        <button type="submit" class="btn">
                            <i class="fa-solid fa-circle-check"></i>
                            Update Category
                        </button>

                        <a href="view_category.jsp?id=<%= category.getCategoryId() %>" class="btn secondary-btn">
                            <i class="fa-solid fa-eye"></i>
                            View Category
                        </a>

                        <a href="categories.jsp" class="btn secondary-btn">
                            <i class="fa-solid fa-arrow-left"></i>
                            Back to Categories
                        </a>
                    </div>

                </form>

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

<script src="js/topbar-search.js?v=inner-category-supplier-1"></script>
<script src="js/user-dropdown.js?v=inner-category-supplier-1"></script>
<script src="js/sidebar-role.js?v=inner-category-supplier-1"></script>
<script src="js/ir-body-watermark.js?v=inner-category-supplier-1"></script>
<script src="js/dashboard-actions.js?v=inner-category-supplier-1"></script>

</body>
</html>