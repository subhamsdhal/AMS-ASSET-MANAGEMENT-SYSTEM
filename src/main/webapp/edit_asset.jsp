<%@page contentType="text/html" pageEncoding="UTF-8"%>
<%@page import="com.mycompany.asset_management_system_ams.Asset"%>
<%@page import="com.mycompany.asset_management_system_ams.AssetDAO"%>
<%@page import="java.sql.*"%>
<%@page import="java.util.Locale"%>
<%@page import="java.text.SimpleDateFormat"%>
<%@page import="com.mycompany.asset_management_system_ams.DBConnection"%>

<%!
    private String safe(Object value) {
        if (value == null) {
            return "";
        }

        return value.toString()
                .replace("&", "&amp;")
                .replace("<", "&lt;")
                .replace(">", "&gt;")
                .replace("\"", "&quot;")
                .replace("'", "&#39;");
    }

    private String jsSafe(Object value) {
        if (value == null) {
            return "";
        }

        return value.toString()
                .replace("\\", "\\\\")
                .replace("\"", "\\\"")
                .replace("'", "\\'")
                .replace("\r", "")
                .replace("\n", "");
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

    if (!("SUPER_ADMIN".equals(role) || "ADMIN".equals(role))
            && !"ASSET_MANAGER".equalsIgnoreCase(role)) {
        response.sendRedirect("assets.jsp?access=denied");
        return;
    }

    String error = request.getParameter("error");

    int assetId = 0;

    try {
        assetId = Integer.parseInt(request.getParameter("id"));
    } catch (Exception e) {
        response.sendRedirect("assets.jsp");
        return;
    }

    AssetDAO dao = new AssetDAO();
    Asset asset = dao.getAssetById(assetId);

    if (asset == null) {
        response.sendRedirect("assets.jsp");
        return;
    }

    String currentAssetImagePath = asset.getAssetImagePath();
    String currentAssetImageSrc = (currentAssetImagePath == null || currentAssetImagePath.trim().isEmpty())
            ? "images/indian-railway-logo.png"
            : currentAssetImagePath.trim();

    String currentCategoryName = asset.getCategoryName();
    String currentVendorName = asset.getVendorName();

    int currentCategoryId = 0;
    int currentVendorId = 0;
    int currentDepartmentId = 0;
    int currentDivisionId = 0;
    int currentLocationId = 0;

    StringBuilder categoryOptions = new StringBuilder();
    StringBuilder departmentOptions = new StringBuilder();
    StringBuilder divisionOptions = new StringBuilder();
    StringBuilder locationOptions = new StringBuilder();
    StringBuilder vendorMapJson = new StringBuilder();

    String todayDate = new SimpleDateFormat("yyyy-MM-dd").format(new java.util.Date());
    String userInitial = username.substring(0, Math.min(2, username.length())).toUpperCase(Locale.ENGLISH);

    Connection con = null;
    PreparedStatement ps = null;
    ResultSet rs = null;

    try {
        con = DBConnection.getConnection();

        String directAssetSql = "SELECT category_id, vendor_id, department_id, division_id, location_id FROM assets WHERE asset_id = ?";
        ps = con.prepareStatement(directAssetSql);
        ps.setInt(1, assetId);
        rs = ps.executeQuery();

        if (rs.next()) {
            currentCategoryId = rs.getInt("category_id");
            currentVendorId = rs.getInt("vendor_id");
            currentDepartmentId = rs.getInt("department_id");
            currentDivisionId = rs.getInt("division_id");
            currentLocationId = rs.getInt("location_id");
        }

        rs.close();
        ps.close();

        String deptSql = "SELECT department_id, department_name FROM departments ORDER BY department_name";
        ps = con.prepareStatement(deptSql);
        rs = ps.executeQuery();
        while (rs.next()) {
            int deptId = rs.getInt("department_id");
            departmentOptions.append("<option value=\"").append(deptId).append("\"");
            if (deptId == currentDepartmentId) departmentOptions.append(" selected");
            departmentOptions.append(">").append(safe(rs.getString("department_name"))).append("</option>");
        }
        rs.close();
        ps.close();

        String divSql = "SELECT division_id, division_name FROM railway_divisions ORDER BY division_name";
        ps = con.prepareStatement(divSql);
        rs = ps.executeQuery();
        while (rs.next()) {
            int divId = rs.getInt("division_id");
            divisionOptions.append("<option value=\"").append(divId).append("\"");
            if (divId == currentDivisionId) divisionOptions.append(" selected");
            divisionOptions.append(">").append(safe(rs.getString("division_name"))).append("</option>");
        }
        rs.close();
        ps.close();

        String locSql = "SELECT location_id, location_name FROM railway_locations ORDER BY location_name";
        ps = con.prepareStatement(locSql);
        rs = ps.executeQuery();
        while (rs.next()) {
            int locId = rs.getInt("location_id");
            locationOptions.append("<option value=\"").append(locId).append("\"");
            if (locId == currentLocationId) locationOptions.append(" selected");
            locationOptions.append(">").append(safe(rs.getString("location_name"))).append("</option>");
        }
        rs.close();
        ps.close();

        if (currentCategoryId > 0) {
            String categoryNameSql = "SELECT category_name FROM asset_categories WHERE category_id = ? LIMIT 1";
            ps = con.prepareStatement(categoryNameSql);
            ps.setInt(1, currentCategoryId);
            rs = ps.executeQuery();

            if (rs.next()) {
                currentCategoryName = rs.getString("category_name");
            }

            rs.close();
            ps.close();
        }

        if (currentCategoryId == 0 && currentCategoryName != null && !currentCategoryName.trim().isEmpty()) {
            String categoryIdSql = "SELECT category_id FROM asset_categories WHERE category_name = ? LIMIT 1";
            ps = con.prepareStatement(categoryIdSql);
            ps.setString(1, currentCategoryName);
            rs = ps.executeQuery();

            if (rs.next()) {
                currentCategoryId = rs.getInt("category_id");
            }

            rs.close();
            ps.close();
        }

        if (currentVendorId > 0) {
            String vendorNameSql = "SELECT vendor_name FROM vendors WHERE vendor_id = ? LIMIT 1";
            ps = con.prepareStatement(vendorNameSql);
            ps.setInt(1, currentVendorId);
            rs = ps.executeQuery();

            if (rs.next()) {
                currentVendorName = rs.getString("vendor_name");
            }

            rs.close();
            ps.close();
        }

        if (currentVendorId == 0 && currentVendorName != null && !currentVendorName.trim().isEmpty()) {
            String vendorIdSql = "SELECT vendor_id FROM vendors WHERE vendor_name = ? LIMIT 1";
            ps = con.prepareStatement(vendorIdSql);
            ps.setString(1, currentVendorName);
            rs = ps.executeQuery();

            if (rs.next()) {
                currentVendorId = rs.getInt("vendor_id");
            }

            rs.close();
            ps.close();
        }

        categoryOptions.append("<option value=\"\">Select Category</option>");

        String categorySql = "SELECT category_id, category_name FROM asset_categories ORDER BY category_name";
        ps = con.prepareStatement(categorySql);
        rs = ps.executeQuery();

        boolean selectedCategoryFound = false;

        while (rs.next()) {
            int categoryId = rs.getInt("category_id");
            String categoryName = rs.getString("category_name");

            boolean selected = currentCategoryId > 0 && categoryId == currentCategoryId;

            if (selected) {
                selectedCategoryFound = true;
            }

            categoryOptions.append("<option value=\"")
                    .append(categoryId)
                    .append("\"");

            if (selected) {
                categoryOptions.append(" selected");
            }

            categoryOptions.append(">")
                    .append(safe(categoryName))
                    .append("</option>");
        }

        rs.close();
        ps.close();

        if (!selectedCategoryFound && currentCategoryId > 0 && currentCategoryName != null && !currentCategoryName.trim().isEmpty()) {
            categoryOptions.append("<option value=\"")
                    .append(currentCategoryId)
                    .append("\" selected>")
                    .append(safe(currentCategoryName))
                    .append(" (Current)")
                    .append("</option>");
        }

        String vendorSql = "SELECT m.category_id, v.vendor_id, v.vendor_name "
                + "FROM category_vendor_mapping m "
                + "JOIN vendors v ON m.vendor_id = v.vendor_id "
                + "WHERE m.status = 'ACTIVE' "
                + "ORDER BY m.category_id, v.vendor_name";

        ps = con.prepareStatement(vendorSql);
        rs = ps.executeQuery();

        vendorMapJson.append("{");

        int previousCategoryId = -1;
        boolean firstCategory = true;
        boolean firstVendorInCategory = true;

        while (rs.next()) {
            int categoryId = rs.getInt("category_id");
            int vendorId = rs.getInt("vendor_id");
            String vendorName = rs.getString("vendor_name");

            if (categoryId != previousCategoryId) {
                if (previousCategoryId != -1) {
                    vendorMapJson.append("]");
                }

                if (!firstCategory) {
                    vendorMapJson.append(",");
                }

                vendorMapJson.append("\"")
                        .append(categoryId)
                        .append("\":[");

                previousCategoryId = categoryId;
                firstCategory = false;
                firstVendorInCategory = true;
            }

            if (!firstVendorInCategory) {
                vendorMapJson.append(",");
            }

            vendorMapJson.append("{\"id\":")
                    .append(vendorId)
                    .append(",\"name\":\"")
                    .append(jsSafe(vendorName))
                    .append("\"}");

            firstVendorInCategory = false;
        }

        if (previousCategoryId != -1) {
            vendorMapJson.append("]");
        }

        vendorMapJson.append("}");

    } catch (Exception e) {
        e.printStackTrace();

        if (categoryOptions.length() == 0) {
            categoryOptions.append("<option value=\"\">Select Category</option>");
        }

        if (currentCategoryId > 0 && currentCategoryName != null && !currentCategoryName.trim().isEmpty()) {
            categoryOptions.append("<option value=\"")
                    .append(currentCategoryId)
                    .append("\" selected>")
                    .append(safe(currentCategoryName))
                    .append(" (Current)")
                    .append("</option>");
        }

        vendorMapJson = new StringBuilder("{}");

    } finally {
        try {
            if (rs != null) {
                rs.close();
            }

            if (ps != null) {
                ps.close();
            }

            if (con != null) {
                con.close();
            }
        } catch (Exception ex) {
            ex.printStackTrace();
        }
    }
%>

<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>Edit Asset - IR-AMS</title>

    <link rel="stylesheet"
          href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.0/css/all.min.css">

    <link rel="stylesheet" href="css/ir-glass.css?v=asset-allocation-inner-1">
    <link rel="stylesheet" href="css/ams-pro.css?v=asset-allocation-inner-1">
    <link rel="stylesheet" href="css/ir-ams-railway-ui.css?v=asset-allocation-inner-1">
<link rel="stylesheet" href="css/edit_asset.css?v=topbarfix1">
</head>

<body class="railway-ui">
<div class="app ams-shell">

    <jsp:include page="sidebar.jsp" />

    <main class="main railway-main">
        <jsp:include page="topbar.jsp" />

        <div class="main-scroll-content edit-asset-board">

            
            <section class="add-asset-hero-new">
                <h1>Edit Railway Asset</h1>

                <p>
                    Modify details for an existing railway asset. Maintain accurate records for
                    purchase details, warranty status, and operational tracking.
                </p>

                <div class="hero-pills">
                    <div class="hero-pill"><i class="fa-solid fa-pen-to-square"></i> Asset Update</div>
                    <div class="hero-pill"><i class="fa-solid fa-qrcode"></i> Persistent QR Identity</div>
                    <div class="hero-pill"><i class="fa-solid fa-truck-field"></i> Category Supplier Mapping</div>
                </div>
            </section>
            <section class="edit-panel">
                <div class="edit-panel-head">
                    <div>
                        <h2>Edit Asset Form</h2>
                        <p>
                            Change core asset details carefully. QR token remains dynamic and will show latest saved asset details.
                        </p>
                    </div>

                    <span class="asset-status-pill">
                        <i class="fa-solid fa-shield-halved"></i>
                        <%= safe(cleanLabel(role)) %> Access
                    </span>
                </div>

                <%
                    if ("failed".equals(error)) {
                %>
                    <div class="edit-alert">
                        <i class="fa-solid fa-triangle-exclamation"></i>
                        Asset could not be updated. Please check the details.
                    </div>
                <%
                    } else if ("invalidvendor".equals(error)) {
                %>
                    <div class="edit-alert">
                        <i class="fa-solid fa-triangle-exclamation"></i>
                        Invalid category-supplier combination. Please select a supplier mapped with the selected category.
                    </div>
                <%
                    } else if ("invaliddate".equals(error)) {
                %>
                    <div class="edit-alert">
                        <i class="fa-solid fa-triangle-exclamation"></i>
                        Invalid date selection. Purchase Date cannot be future and Warranty Expiry cannot be before Purchase Date.
                    </div>
                <%
                    } else if ("server".equals(error)) {
                %>
                    <div class="edit-alert">
                        <i class="fa-solid fa-triangle-exclamation"></i>
                        Server error occurred while updating asset.
                    </div>
                <%
                    } else if ("invalidfile".equals(error)) {
                %>
                    <div class="edit-alert">
                        <i class="fa-solid fa-triangle-exclamation"></i>
                        Asset image must be JPG, JPEG, PNG, or WEBP and not larger than 5 MB.
                    </div>
                <%
                    } else if ("duplicate".equals(error)) {
                %>
                    <div class="edit-alert">
                        <i class="fa-solid fa-triangle-exclamation"></i>
                        Asset Code or Serial Number already exists.
                    </div>
                <%
                    /* Fault: UpdateAssetServlet redirects here with error=duplicate_code
                       specifically when isAssetCodeExists() catches a clash (checked
                       BEFORE the broader isDuplicateAssetCodeOrSerial() check, which is
                       what "duplicate" above covers) - same gap as add_asset.jsp, same
                       fix. */
                    } else if ("duplicate_code".equals(error)) {
                %>
                    <div class="edit-alert">
                        <i class="fa-solid fa-triangle-exclamation"></i>
                        Asset Code already exists. Please use a different Asset Code.
                    </div>
                <%
                    }
                %>

                <form action="UpdateAssetServlet" method="post" id="editAssetForm" enctype="multipart/form-data">
                    <input type="hidden" name="assetId" value="<%= asset.getAssetId() %>">

                    <div class="edit-form-grid">

                        <div class="edit-form-group">
                            <label>
                                <i class="fa-solid fa-barcode"></i>
                                Asset Code
                            </label>

                            <input type="text"
                                   id="assetCodeInput"
                                   name="assetCode"
                                   value="<%= safe(asset.getAssetCode()) %>"
                                   required>
                            <%
                                AssetDAO assetDAO = new AssetDAO();
                                String nextAssetCode = assetDAO.getNextSystemAssetCode();
                            %>
                            <div class="code-helper" style="margin-top: 5px; font-size: 0.85em; color: #555;">
                                System suggested code: <strong><%= safe(nextAssetCode) %></strong>
                                <button type="button" onclick="document.getElementById('assetCodeInput').value='<%= safe(nextAssetCode) %>'; document.getElementById('assetCodeInput').dispatchEvent(new Event('input'));" style="margin-left: 10px; padding: 2px 6px; font-size: 0.9em; cursor: pointer; background: #eee; border: 1px solid #ccc; border-radius: 4px;">Use this code</button>
                            </div>
                            <div id="assetCodeStatus" style="margin-top: 5px; font-size: 0.85em; font-weight: 500;"></div>
                        </div>

                        <div class="edit-form-group">
                            <label>
                                <i class="fa-solid fa-cube"></i>
                                Asset Name
                            </label>

                            <input type="text"
                                   name="assetName"
                                   value="<%= safe(asset.getAssetName()) %>"
                                   required>
                        </div>

                        <div class="edit-form-group">
                            <label>
                                <i class="fa-solid fa-layer-group"></i>
                                Category
                            </label>

                            <select name="categoryId" id="categoryId" required>
                                <%= categoryOptions.toString() %>
                            </select>
                        </div>

                        <div class="edit-form-group">
                            <label>
                                <i class="fa-solid fa-truck-field"></i>
                                Supplier
                            </label>

                            <select name="vendorId" id="vendorId" required>
                                <option value="">Loading Suppliers...</option>
                            </select>
                        </div>

                        <div class="edit-form-group">
                            <label>
                                <i class="fa-solid fa-fingerprint"></i>
                                Serial Number
                            </label>

                            <input type="text"
                                   name="serialNumber"
                                   value="<%= safe(asset.getSerialNumber()) %>"
                                   required>
                        </div>

                        <div class="edit-form-group">
                            <label>
                                <i class="fa-solid fa-qrcode"></i>
                                QR Code / Public QR URL
                            </label>

                            <div class="qr-field-wrap">
                                <input type="text"
                                       name="qrCode"
                                       value="<%= safe(asset.getQrCode()) %>"
                                       required>

                                <a class="qr-open-btn"
                                   href="<%= safe(asset.getQrCode()) %>"
                                   target="_blank"
                                   rel="noopener">
                                    <i class="fa-solid fa-arrow-up-right-from-square"></i>
                                    Open
                                </a>
                            </div>
                        </div>

                        <div class="edit-form-group">
                            <label>
                                <i class="fa-solid fa-sitemap"></i>
                                Department
                            </label>
                            <select name="departmentId" id="departmentId">
                                <option value="0">Select Department</option>
                                <%= departmentOptions.toString() %>
                            </select>
                        </div>

                        <div class="edit-form-group">
                            <label>
                                <i class="fa-solid fa-train"></i>
                                Division
                            </label>
                            <select name="divisionId" id="divisionId">
                                <option value="0">Select Division</option>
                                <%= divisionOptions.toString() %>
                            </select>
                        </div>

                        <div class="edit-form-group">
                            <label>
                                <i class="fa-solid fa-map-location-dot"></i>
                                Location
                            </label>
                            <select name="locationId" id="locationId">
                                <option value="0">Select Location</option>
                                <%= locationOptions.toString() %>
                            </select>
                        </div>

                        <div class="edit-form-group">
                            <label>
                                <i class="fa-solid fa-location-dot"></i>
                                Specific Location / Room / Remarks
                            </label>

                            <input type="text"
                                   name="location"
                                   value="<%= safe(asset.getLocation()) %>">
                        </div>

                        <div class="edit-form-group">
                            <label>
                                <i class="fa-regular fa-calendar-days"></i>
                                Purchase Date
                            </label>

                            <input type="date"
                                   id="purchaseDate"
                                   name="purchaseDate"
                                   value="<%= safe(asset.getPurchaseDate()) %>"
                                   max="<%= todayDate %>"
                                   required>
                        </div>

                        <div class="edit-form-group">
                            <label>
                                <i class="fa-solid fa-indian-rupee-sign"></i>
                                Purchase Cost
                            </label>

                            <input type="number"
                                   name="purchaseCost"
                                   value="<%= asset.getPurchaseCost() %>"
                                   min="0"
                                   step="0.01"
                                   required>
                        </div>

                        <div class="edit-form-group">
                            <label>
                                <i class="fa-regular fa-calendar-xmark"></i>
                                Warranty Expiry
                            </label>

                            <input type="date"
                                   id="warrantyExpiry"
                                   name="warrantyExpiry"
                                   value="<%= safe(asset.getWarrantyExpiry()) %>"
                                   min="<%= safe(asset.getPurchaseDate()) %>"
                                   required>
                        </div>

                        <div class="edit-form-group">
                            <label>
                                <i class="fa-solid fa-chart-line"></i>
                                Depreciation Rate (%)
                            </label>

                            <input type="number"
                                   name="depreciationRate"
                                   value="<%= asset.getDepreciationRate() %>"
                                   min="0"
                                   step="0.01"
                                   required>
                        </div>

                        <div class="edit-form-group file-upload-group">
                            <label>
                                <i class="fa-regular fa-image"></i>
                                Asset Photo
                            </label>

                            <div class="asset-image-edit-row">
                                <img class="asset-image-preview"
                                     src="<%= safe(currentAssetImageSrc) %>"
                                     alt="Current Asset Photo">

                                <div>
                                    <input type="file"
                                           name="assetImage"
                                           accept=".jpg,.jpeg,.png,.webp,image/jpeg,image/png,image/webp">

                                    <div class="upload-hint">
                                        Optional. Choose a new photo to replace the current one. Leave empty to keep the existing image.
                                    </div>
                                </div>
                            </div>
                        </div>

                    </div>

                    <div class="edit-note">
                        <i class="fa-solid fa-circle-info"></i>
                        <div>
                            <strong>Dynamic QR Note:</strong>
                            The printed QR does not need to be reprinted after normal asset detail changes.
                            The same QR token will open the latest saved asset details.
                        </div>
                    </div>

                    <div class="form-actions">
                        <button type="submit" class="edit-btn">
                            <i class="fa-solid fa-floppy-disk"></i>
                            Update Asset
                        </button>

                        <a href="view_asset.jsp?id=<%= asset.getAssetId() %>" class="edit-btn green">
                            <i class="fa-regular fa-eye"></i>
                            View Asset
                        </a>

                        <a href="assets.jsp" class="edit-btn secondary">
                            <i class="fa-solid fa-arrow-left"></i>
                            Back to Assets
                        </a>
                    </div>
                </form>
            </section>

        </div>
    </main>
</div>

<script>
    const categoryVendorMap = <%= vendorMapJson.toString() %>;

    const currentCategoryId = "<%= currentCategoryId %>";
    const currentVendorId = "<%= currentVendorId %>";
    const currentVendorName = "<%= jsSafe(currentVendorName) %>";

    const categorySelect = document.getElementById("categoryId");
    const vendorSelect = document.getElementById("vendorId");

    function loadVendorsByCategory(selectedVendorId) {
        const categoryId = categorySelect ? categorySelect.value : "";
        const vendors = categoryVendorMap[categoryId] || [];

        vendorSelect.innerHTML = "";

        if (!categoryId) {
            vendorSelect.disabled = true;

            const option = document.createElement("option");
            option.value = "";
            option.textContent = "Select Category First";
            vendorSelect.appendChild(option);
            return;
        }

        vendorSelect.disabled = false;

        const defaultOption = document.createElement("option");
        defaultOption.value = "";
        defaultOption.textContent = "Select Supplier";
        vendorSelect.appendChild(defaultOption);

        let selectedVendorFound = false;

        vendors.forEach(vendor => {
            const option = document.createElement("option");
            option.value = vendor.id;
            option.textContent = vendor.name;

            if (String(vendor.id) === String(selectedVendorId)) {
                option.selected = true;
                selectedVendorFound = true;
            }

            vendorSelect.appendChild(option);
        });

        if (selectedVendorId && !selectedVendorFound && currentVendorName) {
            const currentOption = document.createElement("option");
            currentOption.value = selectedVendorId;
            currentOption.textContent = currentVendorName + " (Current Supplier)";
            currentOption.selected = true;
            vendorSelect.appendChild(currentOption);
        }

        if (vendors.length === 0 && !(selectedVendorId && currentVendorName)) {
            vendorSelect.disabled = true;

            const option = document.createElement("option");
            option.value = "";
            option.textContent = "No Supplier Mapped";
            vendorSelect.innerHTML = "";
            vendorSelect.appendChild(option);
        }
    }

    if (categorySelect && currentCategoryId && !categorySelect.value) {
        categorySelect.value = currentCategoryId;
    }

    if (categorySelect) {
        categorySelect.addEventListener("change", function () {
            loadVendorsByCategory("");
        });
    }

    loadVendorsByCategory(currentVendorId);

    const editAssetForm = document.getElementById("editAssetForm");
    const purchaseDateInput = document.getElementById("purchaseDate");
    const warrantyExpiryInput = document.getElementById("warrantyExpiry");

    function getLocalToday() {
        const today = new Date();
        const timezoneOffset = today.getTimezoneOffset() * 60000;
        const localToday = new Date(today.getTime() - timezoneOffset);
        return localToday.toISOString().split("T")[0];
    }

    function setDateRules() {
        const today = getLocalToday();

        if (purchaseDateInput) {
            purchaseDateInput.max = today;
        }

        if (purchaseDateInput && warrantyExpiryInput) {
            if (purchaseDateInput.value) {
                warrantyExpiryInput.min = purchaseDateInput.value;
            }

            purchaseDateInput.addEventListener("change", function () {
                const selectedPurchaseDate = purchaseDateInput.value;

                warrantyExpiryInput.min = selectedPurchaseDate;

                if (warrantyExpiryInput.value
                        && warrantyExpiryInput.value < selectedPurchaseDate) {
                    warrantyExpiryInput.value = "";
                }
            });
        }
    }

    setDateRules();

    if (editAssetForm) {
        editAssetForm.addEventListener("submit", function (event) {
            const today = getLocalToday();

            if (purchaseDateInput && purchaseDateInput.value && purchaseDateInput.value > today) {
                event.preventDefault();
                alert("Purchase Date cannot be a future date.");
                purchaseDateInput.focus();
                return;
            }

            if (purchaseDateInput && warrantyExpiryInput
                    && purchaseDateInput.value
                    && warrantyExpiryInput.value
                    && warrantyExpiryInput.value < purchaseDateInput.value) {
                event.preventDefault();
                alert("Warranty Expiry cannot be before Purchase Date.");
                warrantyExpiryInput.focus();
            }
        });
    }
</script>

<script>
    document.addEventListener("DOMContentLoaded", function () {
        const assetCodeInput = document.getElementById("assetCodeInput");
        const statusDiv = document.getElementById("assetCodeStatus");
        const submitBtn = document.querySelector("#editAssetForm button[type='submit']") || document.querySelector("form button[type='submit']");
        const originalCode = "<%= safe(asset.getAssetCode()) %>";
        const assetId = "<%= asset.getAssetId() %>";
        
        let debounceTimer;

        if (assetCodeInput) {
            assetCodeInput.addEventListener("input", function () {
                clearTimeout(debounceTimer);
                
                const val = this.value.trim();
                
                if (!val || val === originalCode) {
                    statusDiv.innerHTML = "";
                    assetCodeInput.style.borderColor = "";
                    if (submitBtn) submitBtn.disabled = false;
                    return;
                }
                
                debounceTimer = setTimeout(function () {
                    const xhr = new XMLHttpRequest();
                    xhr.open("GET", "<%= request.getContextPath() %>/CheckAssetCodeServlet?assetCode=" + encodeURIComponent(val) + "&assetId=" + assetId, true);
                    xhr.onreadystatechange = function () {
                        if (xhr.readyState === 4 && xhr.status === 200) {
                            try {
                                const resp = JSON.parse(xhr.responseText);
                                if (resp.exists) {
                                    statusDiv.innerHTML = "<span style='color: #dc3545;'><i class='fa-solid fa-triangle-exclamation'></i> " + resp.message + "</span>";
                                    assetCodeInput.style.borderColor = "#dc3545";
                                    if (submitBtn) submitBtn.disabled = true;
                                } else {
                                    statusDiv.innerHTML = "<span style='color: #28a745;'><i class='fa-solid fa-check-circle'></i> " + resp.message + "</span>";
                                    assetCodeInput.style.borderColor = "#28a745";
                                    if (submitBtn) submitBtn.disabled = false;
                                }
                            } catch (e) {
                                console.error("Error parsing duplicate check response", e);
                            }
                        }
                    };
                    xhr.send();
                }, 400);
            });
        }
    });
</script>

<script src="js/topbar-search.js?v=asset-allocation-inner-1"></script>
<script src="js/user-dropdown.js?v=asset-allocation-inner-1"></script>
<script src="js/sidebar-role.js?v=asset-allocation-inner-1"></script>
<script src="js/ir-body-watermark.js?v=asset-allocation-inner-1"></script>
<script src="js/dashboard-actions.js?v=asset-allocation-inner-1"></script>

</body>
</html>
