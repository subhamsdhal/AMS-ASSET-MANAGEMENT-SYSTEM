<%@page contentType="text/html" pageEncoding="UTF-8"%>

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

    String error = request.getParameter("error");
%>

<!DOCTYPE html>
<html>
<head>
    <title>IR-AMS Add Category</title>

    <link rel="stylesheet"
          href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.0/css/all.min.css">

    <link rel="stylesheet" href="css/ir-glass.css?v=inner-category-supplier-1">
    <link rel="stylesheet" href="css/ams-pro.css?v=inner-category-supplier-1">
    <link rel="stylesheet" href="css/ir-ams-railway-ui.css?v=inner-category-supplier-1">
<link rel="stylesheet" href="css/add_category.css?v=topbarfix1">
</head>

<body class="railway-ui">

<div class="app">

    <jsp:include page="sidebar.jsp" />

    <main class="main railway-main">
        <jsp:include page="topbar.jsp" />

        <div class="main-scroll-content">

            <section class="add-employee-hero">
                <h1>Add New Category</h1>

                <p>
                    Register a new asset classification for railway inventory such as laptop,
                    printer, networking device, furniture, electrical equipment or operational hardware.
                </p>

                <br>

                <div class="hero-pills">
                    <div class="hero-pill">
                        <i class="fa-solid fa-layer-group"></i> Category Entry
                    </div>

                    <div class="hero-pill">
                        <i class="fa-solid fa-boxes-stacked"></i> Asset Classification
                    </div>

                    <div class="hero-pill">
                        <i class="fa-solid fa-circle-check"></i> Active by Default
                    </div>

                    <div class="hero-pill">
                        <i class="fa-solid fa-database"></i> MySQL Insert
                    </div>
                </div>
            </section>

            <section class="glass-panel">

                <h2>Category Registration Form</h2>
                <br>

                <%
                    if ("failed".equals(error)) {
                %>
                    <div class="alert-error">
                        Category could not be added. The category name may already exist.
                    </div>
                <%
                    } else if ("server".equals(error)) {
                %>
                    <div class="alert-error">
                        Server error occurred while adding category.
                    </div>
                <%
                    }
                %>

                <form action="AddCategoryServlet" method="post">

                    <div class="form-grid">

                        <div class="form-group full-width">
                            <label>Category Name</label>
                            <input type="text"
                                   name="categoryName"
                                   placeholder="Example: Laptop / Printer / Router / Furniture"
                                   required>
                        </div>

                        <div class="form-group full-width">
                            <label>Description</label>
                            <textarea name="description"
                                      rows="4"
                                      placeholder="Example: Portable computing devices used by railway departments"
                                      required></textarea>
                        </div>

                    </div>

                    <br>

                    <div class="form-actions">
                        <button type="submit" class="btn">
                            <i class="fa-solid fa-circle-check"></i>
                            Save Category
                        </button>

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