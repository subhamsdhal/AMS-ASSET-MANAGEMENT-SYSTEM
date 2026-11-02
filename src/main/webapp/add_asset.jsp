<%@page contentType="text/html" pageEncoding="UTF-8"%>
<%@page import="java.sql.*"%>
<%@page import="java.util.Locale"%>
<%@page import="java.text.SimpleDateFormat"%>
<%@page import="com.mycompany.asset_management_system_ams.DBConnection"%>
<%@page import="com.mycompany.asset_management_system_ams.AssetDAO"%>

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
    String prevAssetCode = request.getParameter("assetCode");
    
    AssetDAO assetDAO = new AssetDAO();
    String nextAssetCode = assetDAO.getNextSystemAssetCode();

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

        String categorySql = "SELECT category_id, category_name "
                + "FROM asset_categories "
                + "ORDER BY category_name";

        ps = con.prepareStatement(categorySql);
        rs = ps.executeQuery();

        while (rs.next()) {
            categoryOptions.append("<option value=\"")
                    .append(rs.getInt("category_id"))
                    .append("\">")
                    .append(safe(rs.getString("category_name")))
                    .append("</option>");
        }

        rs.close();
        ps.close();

        String deptSql = "SELECT department_id, department_name FROM departments ORDER BY department_name";
        ps = con.prepareStatement(deptSql);
        rs = ps.executeQuery();
        while (rs.next()) {
            departmentOptions.append("<option value=\"").append(rs.getInt("department_id")).append("\">")
                    .append(safe(rs.getString("department_name"))).append("</option>");
        }
        rs.close();
        ps.close();

        String divSql = "SELECT division_id, division_name FROM railway_divisions ORDER BY division_name";
        ps = con.prepareStatement(divSql);
        rs = ps.executeQuery();
        while (rs.next()) {
            divisionOptions.append("<option value=\"").append(rs.getInt("division_id")).append("\">")
                    .append(safe(rs.getString("division_name"))).append("</option>");
        }
        rs.close();
        ps.close();

        String locSql = "SELECT location_id, location_name FROM railway_locations ORDER BY location_name";
        ps = con.prepareStatement(locSql);
        rs = ps.executeQuery();
        while (rs.next()) {
            locationOptions.append("<option value=\"").append(rs.getInt("location_id")).append("\">")
                    .append(safe(rs.getString("location_name"))).append("</option>");
        }
        rs.close();
        ps.close();

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
    <title>Add Asset - IR-AMS</title>

    <link rel="stylesheet"
          href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.0/css/all.min.css">

    <link rel="stylesheet" href="css/ir-glass.css?v=asset-allocation-inner-1">
    <link rel="stylesheet" href="css/ams-pro.css?v=asset-allocation-inner-1">
    <link rel="stylesheet" href="css/ir-ams-railway-ui.css?v=asset-allocation-inner-1">
<link rel="stylesheet" href="css/add_asset.css?v=topbarfix1">
</head>

<body class="railway-ui">
<div class="app ams-shell">

    <jsp:include page="sidebar.jsp" />

    <main class="main railway-main">
        <jsp:include page="topbar.jsp" />

        <div class="main-scroll-content add-asset-board">

            <section class="add-asset-hero-new">
                <h1>Add New Railway Asset</h1>

                <p>
                    Register a new railway asset with category-wise supplier selection, QR identity,
                    purchase details, warranty date, depreciation rate and default available status.
                </p>

                <div class="hero-pills">
                    <div class="hero-pill"><i class="fa-solid fa-plus"></i> New Asset Entry</div>
                    <div class="hero-pill"><i class="fa-solid fa-qrcode"></i> Dynamic QR Ready</div>
                    <div class="hero-pill"><i class="fa-solid fa-truck-field"></i> Category Supplier Mapping</div>
                    <div class="hero-pill"><i class="fa-solid fa-circle-check"></i> Default Status: Available</div>
                </div>
            </section>

            <section class="add-panel">
                <div class="add-panel-head">
                    <div>
                        <h2>Asset Registration Form</h2>
                        <p>
                            Select a category first. The supplier dropdown will show only relevant mapped suppliers.
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
                    <div class="add-alert">
                        <i class="fa-solid fa-triangle-exclamation"></i>
                        Asset could not be added. Please check the details.
                    </div>
                <%
                    } else if ("server".equals(error)) {
                %>
                    <div class="add-alert">
                        <i class="fa-solid fa-triangle-exclamation"></i>
                        Server error occurred. Please check duplicate Asset Code or Auto QR Code.
                    </div>
                <%
                    } else if ("invalidvendor".equals(error)) {
                %>
                    <div class="add-alert">
                        <i class="fa-solid fa-triangle-exclamation"></i>
                        Invalid category-supplier combination. Please select a supplier mapped with the selected category.
                    </div>
                <%
                    } else if ("invaliddate".equals(error)) {
                %>
                    <div class="add-alert">
                        <i class="fa-solid fa-triangle-exclamation"></i>
                        Invalid date selection. Purchase Date cannot be future and Warranty Expiry cannot be before Purchase Date.
                    </div>
                <%
                    } else if ("invalidfile".equals(error)) {
                %>
                    <div class="add-alert">
                        <i class="fa-solid fa-triangle-exclamation"></i>
                        Asset image must be JPG, JPEG, PNG, or WEBP and not larger than 5 MB.
                    </div>
                <%
                    } else if ("duplicate".equals(error)) {
                %>
                    <div class="add-alert">
                        <i class="fa-solid fa-triangle-exclamation"></i>
                        Asset Code or Serial Number already exists.
                    </div>
                <%
                    /* Fault: AddAssetServlet redirects here with error=duplicate_code
                       specifically when isAssetCodeExists() catches a clash (checked
                       BEFORE the broader isDuplicateAssetCodeOrSerial() check below it,
                       which is what "duplicate" above actually covers) - but this page
                       never had a branch for that exact value, so hitting the single
                       most common real-world mistake (retyping/re-submitting an Asset
                       Code that's already in use) reloaded the form with zero feedback:
                       no error, no obvious reason nothing happened. */
                    } else if ("duplicate_code".equals(error)) {
                %>
                    <div class="add-alert">
                        <i class="fa-solid fa-triangle-exclamation"></i>
                        Asset Code already exists. Please use a different Asset Code.
                    </div>
                <%
                    }
                %>

                <form action="AddAssetServlet" method="post" id="addAssetForm" enctype="multipart/form-data">

                    <div class="add-form-grid">

                        <div class="add-form-group">
                            <label>
                                <i class="fa-solid fa-barcode"></i>
                                Asset Code
                            </label>

                            <input type="text"
                                   id="assetCodeInput"
                                   name="assetCode"
                                   placeholder="Example: ECoR-HQ-LAP-0021"
                                   value="<%= safe(prevAssetCode != null ? prevAssetCode : nextAssetCode) %>"
                                   required>
                            <div class="code-helper" style="margin-top: 5px; font-size: 0.85em; color: #555;">
                                System suggested code: <strong><%= safe(nextAssetCode) %></strong>
                                <button type="button" onclick="document.getElementById('assetCodeInput').value='<%= safe(nextAssetCode) %>'; document.getElementById('assetCodeInput').dispatchEvent(new Event('input'));" style="margin-left: 10px; padding: 2px 6px; font-size: 0.9em; cursor: pointer; background: #eee; border: 1px solid #ccc; border-radius: 4px;">Use this code</button>
                            </div>
                            <div id="assetCodeStatus" style="margin-top: 5px; font-size: 0.85em; font-weight: 500;"></div>
                        </div>

                        <div class="add-form-group">
                            <label>
                                <i class="fa-solid fa-cube"></i>
                                Asset Name
                            </label>

                            <input type="text"
                                   name="assetName"
                                   placeholder="Example: Dell Latitude Laptop"
                                   required>
                        </div>

                        <div class="add-form-group">
                            <label>
                                <i class="fa-solid fa-layer-group"></i>
                                Category
                            </label>

                            <select name="categoryId" id="categoryId" required>
                                <option value="">Select Category</option>
                                <%= categoryOptions.toString() %>
                            </select>
                        </div>

                        <div class="add-form-group">
                            <label>
                                <i class="fa-solid fa-truck-field"></i>
                                Supplier
                            </label>

                            <select name="vendorId" id="vendorId" required disabled>
                                <option value="">Select Category First</option>
                            </select>
                        </div>

                        <div class="add-form-group">
                            <label>
                                <i class="fa-solid fa-fingerprint"></i>
                                Serial Number
                            </label>

                            <input type="text"
                                   name="serialNumber"
                                   placeholder="Example: DL-HQ-LAP-0021"
                                   required>
                        </div>

                        <div class="add-form-group">
                            <label>
                                <i class="fa-solid fa-sitemap"></i>
                                Department
                            </label>
                            <select name="departmentId" id="departmentId">
                                <option value="0">Select Department</option>
                                <%= departmentOptions.toString() %>
                            </select>
                        </div>

                        <div class="add-form-group">
                            <label>
                                <i class="fa-solid fa-train"></i>
                                Division
                            </label>
                            <select name="divisionId" id="divisionId">
                                <option value="0">Select Division</option>
                                <%= divisionOptions.toString() %>
                            </select>
                        </div>

                        <div class="add-form-group">
                            <label>
                                <i class="fa-solid fa-map-location-dot"></i>
                                Location
                            </label>
                            <select name="locationId" id="locationId">
                                <option value="0">Select Location</option>
                                <%= locationOptions.toString() %>
                            </select>
                        </div>

                        <div class="add-form-group">
                            <label>
                                <i class="fa-solid fa-location-dot"></i>
                                Specific Location / Room / Remarks
                            </label>

                            <input type="text"
                                   name="location"
                                   placeholder="Example: IT Helpdesk Section, Rail Sadan">
                        </div>

                        <div class="add-form-group">
                            <label>
                                <i class="fa-regular fa-calendar-days"></i>
                                Purchase Date
                            </label>

                            <input type="date"
                                   id="purchaseDate"
                                   name="purchaseDate"
                                   max="<%= todayDate %>"
                                   required>
                        </div>

                        <div class="add-form-group">
                            <label>
                                <i class="fa-solid fa-indian-rupee-sign"></i>
                                Purchase Cost
                            </label>

                            <input type="number"
                                   name="purchaseCost"
                                   placeholder="Example: 75000"
                                   min="0"
                                   step="0.01"
                                   required>
                        </div>

                        <div class="add-form-group">
                            <label>
                                <i class="fa-regular fa-calendar-xmark"></i>
                                Warranty Expiry
                            </label>

                            <input type="date"
                                   id="warrantyExpiry"
                                   name="warrantyExpiry"
                                   required>
                        </div>

                        <div class="add-form-group">
                            <label>
                                <i class="fa-solid fa-chart-line"></i>
                                Depreciation Rate (%)
                            </label>

                            <input type="number"
                                   name="depreciationRate"
                                   placeholder="Example: 10"
                                   min="0"
                                   step="0.01"
                                   required>
                        </div>

                        <div class="add-form-group file-upload-group">
                            <label>
                                <i class="fa-regular fa-image"></i>
                                Asset Photo
                            </label>

                            <input type="file"
                                   name="assetImage"
                                   accept=".jpg,.jpeg,.png,.webp,image/jpeg,image/png,image/webp">

                            <div class="upload-hint">
                                Optional. Upload a clear asset photo up to 5 MB. The file path will be saved in MySQL.
                            </div>
                        </div>

                        <%-- Same "optional attach at creation time" pattern add_employee.jsp already
                             uses for employee documents, applied here with the Document Type options
                             view_asset.jsp's Asset Document Vault already uses (INVOICE/WARRANTY/
                             MANUAL/OTHER) - so an invoice/bill in hand right now can be attached in
                             the same step as creating the asset, instead of a separate trip to the
                             asset's detail page afterward. More documents can still be added later
                             from there. --%>
                        <div class="add-form-group" style="grid-column: 1 / -1; margin-top: 10px; border-top: 1px solid var(--ir-border, #e2e8f0); padding-top: 20px;">
                            <label style="margin-bottom: 4px;">
                                <i class="fa-solid fa-file-circle-plus"></i>
                                Optional Document Upload
                            </label>
                            <div class="upload-hint" style="margin-top: 0; margin-bottom: 12px;">
                                Attach the invoice/bill, warranty certificate, or manual now if you have it. More documents can be added later from the asset's page.
                            </div>

                            <div style="display: grid; grid-template-columns: 1fr 1fr; gap: 15px;">
                                <div>
                                    <label style="display:block; margin-bottom: 5px; font-size: 13px;">Document Type</label>
                                    <select name="documentType">
                                        <option value="">Select Type</option>
                                        <option value="INVOICE">Invoice / Purchase Bill</option>
                                        <option value="WARRANTY">Warranty Certificate</option>
                                        <option value="MANUAL">Manual / Service Guide</option>
                                        <option value="OTHER">Other Supporting Record</option>
                                    </select>
                                </div>
                                <div>
                                    <label style="display:block; margin-bottom: 5px; font-size: 13px;">Select File</label>
                                    <input type="file"
                                           name="assetDocument"
                                           accept=".pdf,.jpg,.jpeg,.png,.webp,.doc,.docx,.xls,.xlsx,.csv">
                                    <div class="upload-hint">Allowed: PDF, JPG, PNG, WEBP, DOC, DOCX, XLS, XLSX, CSV. Max: 10 MB.</div>
                                </div>
                            </div>
                        </div>

                    </div>

                    <div class="add-note">
                        <i class="fa-solid fa-circle-info"></i>

                        <div>
                            <strong>Supplier Mapping Rule:</strong>
                            Only suppliers mapped to the selected asset category will appear here.
                            For example, Laptop will show laptop suppliers only; Furniture will show furniture suppliers only.
                        </div>
                    </div>

                    <div class="form-actions">
                        <button type="submit" class="add-btn">
                            <i class="fa-solid fa-floppy-disk"></i>
                            Save Asset
                        </button>

                        <a href="assets.jsp" class="add-btn secondary">
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

    const categorySelect = document.getElementById("categoryId");
    const vendorSelect = document.getElementById("vendorId");

    function loadVendorsByCategory() {
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

        if (vendors.length === 0) {
            vendorSelect.disabled = true;

            const option = document.createElement("option");
            option.value = "";
            option.textContent = "No Supplier Mapped";
            vendorSelect.appendChild(option);
            return;
        }

        vendorSelect.disabled = false;

        const defaultOption = document.createElement("option");
        defaultOption.value = "";
        defaultOption.textContent = "Select Supplier";
        vendorSelect.appendChild(defaultOption);

        vendors.forEach(vendor => {
            const option = document.createElement("option");
            option.value = vendor.id;
            option.textContent = vendor.name;
            vendorSelect.appendChild(option);
        });
    }

    if (categorySelect) {
        categorySelect.addEventListener("change", loadVendorsByCategory);
    }

    const addAssetForm = document.getElementById("addAssetForm");
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

    if (addAssetForm) {
        addAssetForm.addEventListener("submit", function (event) {
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
        const submitBtn = document.querySelector(".add-form form button[type='submit']") || document.querySelector("form button[type='submit']");
        
        let debounceTimer;

        if (assetCodeInput) {
            assetCodeInput.addEventListener("input", function () {
                clearTimeout(debounceTimer);
                
                const val = this.value.trim();
                if (!val) {
                    statusDiv.innerHTML = "";
                    assetCodeInput.style.borderColor = "";
                    if (submitBtn) submitBtn.disabled = false;
                    return;
                }
                
                debounceTimer = setTimeout(function () {
                    const xhr = new XMLHttpRequest();
                    xhr.open("GET", "<%= request.getContextPath() %>/CheckAssetCodeServlet?assetCode=" + encodeURIComponent(val), true);
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
            
            // Run on load in case of re-population
            if (assetCodeInput.value.trim() !== '') {
                assetCodeInput.dispatchEvent(new Event('input'));
            }
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
