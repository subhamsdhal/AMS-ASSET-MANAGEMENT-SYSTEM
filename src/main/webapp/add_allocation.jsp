<%@page contentType="text/html" pageEncoding="UTF-8"%>
<%@page import="com.mycompany.asset_management_system_ams.Asset"%>
<%@page import="com.mycompany.asset_management_system_ams.AssetDAO"%>
<%@page import="com.mycompany.asset_management_system_ams.Employee"%>
<%@page import="com.mycompany.asset_management_system_ams.EmployeeDAO"%>
<%@page import="java.util.List"%>

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

    if (!("SUPER_ADMIN".equals(role) || "ADMIN".equals(role)) && !"ASSET_MANAGER".equalsIgnoreCase(role)) {
        response.sendRedirect("allocation.jsp?access=denied");
        return;
    }

    String error = request.getParameter("error");

    AssetDAO assetDAO = new AssetDAO();
    EmployeeDAO employeeDAO = new EmployeeDAO();

    List<Asset> assetList = assetDAO.getAllAssets();
    List<Employee> employeeList = employeeDAO.getAllEmployees();

    int availableAssetCount = 0;
    int activeEmployeeCount = 0;

    for (Asset asset : assetList) {
        if ("AVAILABLE".equalsIgnoreCase(asset.getAssetStatus())) {
            availableAssetCount++;
        }
    }

    for (Employee emp : employeeList) {
        if ("ACTIVE".equalsIgnoreCase(emp.getStatus())) {
            activeEmployeeCount++;
        }
    }
%>

<!DOCTYPE html>
<html>
<head>
    <title>IR-AMS Add Allocation</title>

    <link rel="stylesheet"
          href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.0/css/all.min.css">

    <link rel="stylesheet" href="css/ir-glass.css?v=28000">
    <link rel="stylesheet" href="css/ams-pro.css?v=28000">
    <link rel="stylesheet" href="css/ir-ams-railway-ui.css?v=28000">
<link rel="stylesheet" href="css/add_allocation.css?v=topbarfix1">
        </head>

<body class="railway-ui">

<div class="app ams-shell">

    <jsp:include page="sidebar.jsp" />

    <main class="main railway-main">
        <jsp:include page="topbar.jsp" />

        <div class="main-scroll-content">

            <section class="allocation-command-hero">
                <h1>Asset Allocation Command</h1>

                <p>
                    Issue available railway assets to verified active employees with custody validation,
                    audit traceability, allocation control, and live asset status synchronization.
                </p>

                <div class="allocation-brief-grid">
                    <div class="allocation-brief-card">
                        <i class="fa-solid fa-box-open"></i>
                        <div>
                            <span>Available Assets</span>
                            <strong><%= availableAssetCount %></strong>
                        </div>
                    </div>

                    <div class="allocation-brief-card">
                        <i class="fa-solid fa-user-check"></i>
                        <div>
                            <span>Active Employees</span>
                            <strong><%= activeEmployeeCount %></strong>
                        </div>
                    </div>

                    <div class="allocation-brief-card">
                        <i class="fa-solid fa-shield-halved"></i>
                        <div>
                            <span>Validation</span>
                            <strong>Enabled</strong>
                        </div>
                    </div>

                    <div class="allocation-brief-card">
                        <i class="fa-solid fa-clock-rotate-left"></i>
                        <div>
                            <span>Return Flow</span>
                            <strong>Tracked</strong>
                        </div>
                    </div>
                </div>
            </section>

            <section class="glass-panel allocation-console-panel allocation-smart-page">

                <div class="allocation-section-title">
                    <div>
                        <h2>Allocation Entry Form</h2>
                        <p>Select available assets, choose active employee, and register official custody issue.</p>
                    </div>

                    <div class="allocation-status-chip">
                        <i class="fa-solid fa-circle-check"></i>
                        Allocation Control Active
                    </div>
                </div>

                <%
                    if ("failed".equals(error)) {
                %>
                    <div class="alert-error">
                        Allocation could not be added. Please check the selected assets and employee.
                    </div>
                <%
                    } else if ("server".equals(error)) {
                %>
                    <div class="alert-error">
                        Server error occurred. Please check selected asset and employee.
                    </div>
                <%
                    } else if ("noasset".equals(error)) {
                %>
                    <div class="alert-error">
                        Please select at least one available asset before saving allocation.
                    </div>
                <%
                    } else if ("invaliddate".equals(error)) {
                %>
                    <div class="alert-error">
                        Allocation date cannot be a future date.
                    </div>
                <%
                    } else if ("blocked".equals(error)) {
                %>
                    <div class="alert-error">
                        Allocation blocked. Selected asset may already be allocated or employee may be inactive/deleted.
                    </div>
                <%
                    }
                %>

                <form action="AddAllocationServlet" method="post">

                    <div class="form-grid">

                        <div class="form-group form-group-full">
                            <label>Select Available Assets</label>

                            <div class="smart-asset-control">

                                <div class="smart-asset-input-wrap">
                                    <i class="fa-solid fa-magnifying-glass"></i>

                                    <input type="text"
                                           id="smartAssetInput"
                                           autocomplete="off"
                                           placeholder="Search asset code, name, category or location">
                                </div>

                                <button type="button" class="mini-btn" onclick="selectAssetsFromSmartInput()">
                                    <i class="fa-solid fa-check-double"></i> Select
                                </button>

                                <button type="button" class="mini-btn danger-mini" onclick="clearAssetSearchAndSelection()">
                                    <i class="fa-solid fa-xmark"></i> Clear
                                </button>

                            </div>

                            <div class="multi-asset-box" id="multiAssetBox">

                                <%
                                    boolean hasAvailableAsset = false;

                                    for (Asset asset : assetList) {
                                        if ("AVAILABLE".equalsIgnoreCase(asset.getAssetStatus())) {
                                            hasAvailableAsset = true;

                                            String assetCode = safe(asset.getAssetCode());
                                            String assetName = safe(asset.getAssetName());
                                            String categoryName = asset.getCategoryName() == null ? "Uncategorized" : safe(asset.getCategoryName());
                                            String assetLocation = asset.getLocation() == null ? "No Location" : safe(asset.getLocation());

                                            String searchText = (assetCode + " " + assetName + " " + categoryName + " " + assetLocation).toLowerCase();
                                %>

                                    <label class="multi-asset-item"
                                           data-search="<%= searchText %>"
                                           data-code="<%= assetCode %>"
                                           data-name="<%= assetName %>">

                                        <input type="checkbox"
                                               class="asset-check"
                                               name="assetIds"
                                               value="<%= asset.getAssetId() %>"
                                               data-code="<%= assetCode %>"
                                               data-name="<%= assetName %>"
                                               onchange="updateSelectedAssets()">

                                        <span class="asset-card-text">
                                            <strong><%= assetCode %></strong>
                                            <small><%= assetName %></small>
                                            <em><%= categoryName %> • <%= assetLocation %></em>
                                        </span>
                                    </label>

                                <%
                                        }
                                    }

                                    if (!hasAvailableAsset) {
                                %>

                                    <div class="empty-state-small">
                                        No available assets found for allocation.
                                    </div>

                                <%
                                    }
                                %>

                            </div>

                            <small class="form-hint">
                                Only AVAILABLE assets are shown. Backend validation blocks already allocated or unavailable assets.
                            </small>
                        </div>

                        <div class="form-group form-group-full">
                            <label>Selected Assets for Allocation</label>

                            <div class="selected-assets-panel">
                                <div class="selected-assets-header">
                                    <strong id="selectedAssetCount">0 Assets Selected</strong>
                                    <span>Selected assets will be issued under employee custody.</span>
                                </div>

                                <div class="selected-assets-list" id="selectedAssetsList">
                                    <div class="selected-empty">No asset selected yet.</div>
                                </div>
                            </div>
                        </div>

                        <div class="form-group">
                            <label>Employee</label>
                            <select name="employeeId" required>
                                <option value="">Select Active Employee</option>

                                <%
                                    boolean hasActiveEmployee = false;

                                    for (Employee emp : employeeList) {
                                        if ("ACTIVE".equalsIgnoreCase(emp.getStatus())) {
                                            hasActiveEmployee = true;
                                %>

                                    <option value="<%= emp.getEmployeeId() %>">
                                        <%= safe(emp.getEmployeeCode()) %> - <%= safe(emp.getEmployeeName()) %>
                                    </option>

                                <%
                                        }
                                    }

                                    if (!hasActiveEmployee) {
                                %>
                                    <option value="" disabled>No active employees available</option>
                                <%
                                    }
                                %>

                            </select>
                        </div>

                        <div class="form-group">
                            <label>Allocation Date</label>
                            <input type="date"
                                   name="allocationDate"
                                   id="allocationDate"
                                   required>
                        </div>

                        <div class="allocation-policy-strip">
                            <div>
                                <span>Allocation Status</span>
                                <strong>ALLOCATED</strong>
                            </div>

                            <div>
                                <span>Return Processing</span>
                                <strong>Return Module</strong>
                            </div>

                            <div>
                                <span>Audit Control</span>
                                <strong>Enabled</strong>
                            </div>
                        </div>

                        <div class="form-group form-group-full">
                            <label>Official Remarks</label>
                            <input type="text"
                                   name="remarks"
                                   placeholder="Example: Issued for official railway operational work"
                                   required>
                        </div>

                    </div>

                    <div class="form-actions">
                        <button type="submit" class="btn">
                            <i class="fa-solid fa-floppy-disk"></i> Save Allocation
                        </button>

                        <a href="allocation.jsp" class="btn">
                            <i class="fa-solid fa-arrow-left"></i> Back to Allocation
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

<script>
    const smartAssetInput = document.getElementById("smartAssetInput");

    function getTodayIsoDate() {
        const now = new Date();
        const localDate = new Date(now.getTime() - now.getTimezoneOffset() * 60000);
        return localDate.toISOString().split("T")[0];
    }

    const allocationDateInput = document.getElementById("allocationDate");

    if (allocationDateInput) {
        allocationDateInput.max = getTodayIsoDate();

        allocationDateInput.addEventListener("change", function () {
            if (allocationDateInput.value && allocationDateInput.value > getTodayIsoDate()) {
                allocationDateInput.value = "";
                alert("Allocation date cannot be a future date.");
            }
        });
    }

    function getAssetTokens(text) {
        return text
                .toLowerCase()
                .split(/[,;\n]+/)
                .map(function (token) {
                    return token.trim();
                })
                .filter(function (token) {
                    return token.length > 0;
                });
    }

    function liveFilterAssets() {
        const query = smartAssetInput.value.toLowerCase().trim();
        const tokens = getAssetTokens(query);
        const assetItems = document.querySelectorAll(".multi-asset-item");

        assetItems.forEach(function (item) {
            const searchText = item.getAttribute("data-search").toLowerCase();

            if (tokens.length === 0) {
                item.classList.remove("asset-hidden");
                return;
            }

            let matched = false;

            tokens.forEach(function (token) {
                if (searchText.includes(token)) {
                    matched = true;
                }
            });

            if (matched) {
                item.classList.remove("asset-hidden");
            } else {
                item.classList.add("asset-hidden");
            }
        });
    }

    if (smartAssetInput) {
        smartAssetInput.addEventListener("input", function () {
            liveFilterAssets();
        });

        smartAssetInput.addEventListener("keydown", function (event) {
            if (event.key === "Enter") {
                event.preventDefault();
                selectAssetsFromSmartInput();
            }
        });
    }

    function updateSelectedAssets() {
        const checks = document.querySelectorAll(".asset-check");
        const selectedList = document.getElementById("selectedAssetsList");
        const selectedCount = document.getElementById("selectedAssetCount");

        selectedList.innerHTML = "";

        let count = 0;

        checks.forEach(function (check) {
            const item = check.closest(".multi-asset-item");

            item.classList.remove("selected");

            if (check.checked) {
                count++;
                item.classList.add("selected");

                const chip = document.createElement("div");
                chip.className = "selected-asset-chip";

                chip.innerHTML =
                        "<i class='fa-solid fa-box'></i> " +
                        check.getAttribute("data-code") +
                        " - " +
                        check.getAttribute("data-name") +
                        " <button type='button' onclick='removeSelectedAsset(\"" + check.value + "\")'>×</button>";

                selectedList.appendChild(chip);
            }
        });

        selectedCount.innerText = count + (count === 1 ? " Asset Selected" : " Assets Selected");

        if (count === 0) {
            selectedList.innerHTML = "<div class='selected-empty'>No asset selected yet.</div>";
        }
    }

    function removeSelectedAsset(assetId) {
        const check = document.querySelector(".asset-check[value='" + assetId + "']");

        if (check) {
            check.checked = false;
            updateSelectedAssets();
        }

        if (smartAssetInput) {
            smartAssetInput.focus();
        }
    }

    function clearAssetSearchAndSelection() {
        const checks = document.querySelectorAll(".asset-check");
        const assetItems = document.querySelectorAll(".multi-asset-item");

        checks.forEach(function (check) {
            check.checked = false;
        });

        assetItems.forEach(function (item) {
            item.classList.remove("selected");
            item.classList.remove("asset-hidden");
        });

        if (smartAssetInput) {
            smartAssetInput.value = "";
            smartAssetInput.focus();
        }

        updateSelectedAssets();
    }

    function selectAssetsFromSmartInput() {
        const text = smartAssetInput.value.toLowerCase().trim();

        if (text.length === 0) {
            alert("Please type asset code, name, category or location first.");
            smartAssetInput.focus();
            return;
        }

        const tokens = getAssetTokens(text);

        let matchedCount = 0;

        const checks = document.querySelectorAll(".asset-check");

        tokens.forEach(function (token) {
            checks.forEach(function (check) {
                const parent = check.closest(".multi-asset-item");
                const searchText = parent.getAttribute("data-search").toLowerCase();
                const code = check.getAttribute("data-code").toLowerCase();
                const name = check.getAttribute("data-name").toLowerCase();

                if (code === token || name.includes(token) || searchText.includes(token)) {
                    if (!check.checked) {
                        check.checked = true;
                        matchedCount++;
                    }
                }
            });
        });

        updateSelectedAssets();
        liveFilterAssets();

        smartAssetInput.focus();

        if (matchedCount === 0) {
            alert("No matching available asset found.");
        }
    }

    const allocationForm = document.querySelector("form");

    if (allocationForm) {
        allocationForm.addEventListener("submit", function (event) {
            const checkedAssets = document.querySelectorAll(".asset-check:checked");

            if (checkedAssets.length === 0) {
                event.preventDefault();
                alert("Please select at least one asset for allocation.");
                smartAssetInput.focus();
                return;
            }

            if (!allocationDateInput || !allocationDateInput.value) {
                event.preventDefault();
                alert("Please select allocation date.");
                return;
            }

            if (allocationDateInput.value > getTodayIsoDate()) {
                event.preventDefault();
                allocationDateInput.value = "";
                alert("Allocation date cannot be a future date.");
            }
        });
    }

    updateSelectedAssets();
</script>

<script src="js/topbar-search.js?v=28000"></script>
<script src="js/user-dropdown.js?v=28000"></script>
<script src="js/sidebar-role.js?v=28000"></script>
<script src="js/ir-body-watermark.js?v=28000"></script>
<script src="js/dashboard-actions.js?v=28000"></script>

</body>
</html>