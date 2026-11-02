<%@page contentType="text/html" pageEncoding="UTF-8"%>
<%@page import="com.mycompany.asset_management_system_ams.AssetAllocation"%>
<%@page import="com.mycompany.asset_management_system_ams.AssetAllocationDAO"%>
<%@page import="java.util.List"%>

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
            && !"ASSET_MANAGER".equalsIgnoreCase(role)
            && !"EMPLOYEE".equalsIgnoreCase(role)) {
        response.sendRedirect("returns.jsp?access=denied");
        return;
    }

    String error = request.getParameter("error");
    String selectedAllocationParam = request.getParameter("allocationId");
    int selectedAllocationId = 0;

    try {
        if (selectedAllocationParam != null && !selectedAllocationParam.trim().equals("")) {
            selectedAllocationId = Integer.parseInt(selectedAllocationParam);
        }
    } catch (Exception e) {
        selectedAllocationId = 0;
    }

    AssetAllocationDAO allocationDAO = new AssetAllocationDAO();
    List<AssetAllocation> allocationList = allocationDAO.getAllAllocations();

    int activeAllocationCount = 0;

    for (AssetAllocation allocation : allocationList) {
        if ("ALLOCATED".equalsIgnoreCase(allocation.getAllocationStatus())) {
            activeAllocationCount++;
        }
    }
%>

<!DOCTYPE html>
<html>
<head>
    <title>IR-AMS Return Verification</title>

    <link rel="stylesheet"
          href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.0/css/all.min.css">

    <link rel="stylesheet" href="css/ir-glass.css?v=28000">
    <link rel="stylesheet" href="css/ams-pro.css?v=28000">
    <link rel="stylesheet" href="css/ir-ams-railway-ui.css?v=28000">
<link rel="stylesheet" href="css/add_return.css?v=topbarfix1">
    </head>

<body class="railway-ui">

<div class="app ams-shell">

    <jsp:include page="sidebar.jsp" />

    <main class="main railway-main">
        <jsp:include page="topbar.jsp" />

        <div class="main-scroll-content">

            <section class="return-command-hero">
                <h1>Return Verification Command</h1>

                <p>
                    Verify asset returns, capture condition status, close active custody, update live inventory status,
                    and preserve audit-ready return records.
                </p>

                <div class="return-brief-grid">
                    <div class="return-brief-card">
                        <i class="fa-solid fa-arrows-rotate"></i>
                        <div>
                            <span>Active Allocations</span>
                            <strong><%= activeAllocationCount %></strong>
                        </div>
                    </div>

                    <div class="return-brief-card">
                        <i class="fa-solid fa-clipboard-check"></i>
                        <div>
                            <span>Condition Check</span>
                            <strong>Required</strong>
                        </div>
                    </div>

                    <div class="return-brief-card">
                        <i class="fa-solid fa-wrench"></i>
                        <div>
                            <span>Repair Routing</span>
                            <strong>Automatic</strong>
                        </div>
                    </div>

                    <div class="return-brief-card">
                        <i class="fa-solid fa-shield-halved"></i>
                        <div>
                            <span>Audit Control</span>
                            <strong>Enabled</strong>
                        </div>
                    </div>
                </div>
            </section>

            <section class="glass-panel return-console-panel">

                <div class="return-section-title">
                    <div>
                        <h2>Return Verification Form</h2>
                        <p>Close asset custody after physical verification and receiving authority confirmation.</p>
                    </div>

                    <div class="return-status-chip">
                        <i class="fa-solid fa-circle-check"></i>
                        Return Control Active
                    </div>
                </div>

                <%
                    if (selectedAllocationId > 0) {
                %>
                    <div class="return-context-banner">
                        <div class="return-context-icon">
                            <i class="fa-solid fa-clipboard-check"></i>
                        </div>

                        <div class="return-context-content">
                            <h3>Return Verification Initiated</h3>
                            <p>
                                Allocation record <strong>ALLOC-<%= selectedAllocationId %></strong> has been loaded.
                                Verify condition and receiving details before closing the return.
                            </p>
                        </div>
                    </div>
                <%
                    }
                %>

                <%
                    if ("failed".equals(error)) {
                %>
                    <div class="alert-error">
                        Return could not be added. Please check the selected allocation.
                    </div>
                <%
                    } else if ("server".equals(error)) {
                %>
                    <div class="alert-error">
                        Server error occurred. This allocation may already be returned.
                    </div>
                <%
                    } else if ("invaliddate".equals(error)) {
                %>
                    <div class="alert-error">
                        Return date cannot be a future date.
                    </div>
                <%
                    } else if ("blocked".equals(error)) {
                %>
                    <div class="alert-error">
                        Return blocked. This allocation may already be returned or is not active.
                    </div>
                <%
                    }
                %>

                <form action="AddReturnServlet" method="post">

                    <div class="form-grid">

                        <div class="form-group">
                            <label>Allocated Asset</label>
                            <select name="allocationId" required>
                                <option value="">Select Active Allocation</option>

                                <%
                                    for (AssetAllocation allocation : allocationList) {
                                        if ("ALLOCATED".equalsIgnoreCase(allocation.getAllocationStatus())) {
                                %>

                                    <option value="<%= allocation.getAllocationId() %>"
                                            <%= allocation.getAllocationId() == selectedAllocationId ? "selected" : "" %>>
                                        ALLOC-<%= allocation.getAllocationId() %>
                                        | <%= allocation.getAssetCode() %> - <%= allocation.getAssetName() %>
                                        | <%= allocation.getEmployeeCode() %> - <%= allocation.getEmployeeName() %>
                                    </option>

                                <%
                                        }
                                    }
                                %>

                            </select>
                        </div>

                        <div class="form-group">
                            <label>Return Date</label>
                            <input type="date"
                                   name="returnDate"
                                   id="returnDate"
                                   required>
                        </div>

                        <div class="form-group">
                            <label>Return Condition</label>
                            <select name="returnCondition" required>
                                <option value="">Select Condition</option>
                                <option value="GOOD">GOOD</option>
                                <option value="DAMAGED">DAMAGED</option>
                                <option value="NEEDS_REPAIR">NEEDS_REPAIR</option>
                            </select>
                        </div>

                        <div class="form-group">
                            <label>Received By</label>
                            <input type="text"
                                   name="receivedBy"
                                   placeholder="Example: Store Officer"
                                   required>
                        </div>

                        <div class="return-policy-strip">
                            <div>
                                <span>Good Condition</span>
                                <strong>Available</strong>
                            </div>

                            <div>
                                <span>Damaged / Repair</span>
                                <strong>Maintenance</strong>
                            </div>

                            <div>
                                <span>Audit Control</span>
                                <strong>Enabled</strong>
                            </div>
                        </div>

                        <div class="form-group" style="grid-column: 1 / -1;">
                            <label>Closure Remarks</label>
                            <input type="text"
                                   name="remarks"
                                   placeholder="Example: Asset verified and returned to store custody"
                                   required>
                        </div>

                    </div>

                    <div class="form-actions">
                        <button type="submit" class="btn">
                            <i class="fa-solid fa-circle-check"></i> Verify & Close Return
                        </button>

                        <a href="returns.jsp" class="btn">
                            <i class="fa-solid fa-arrow-left"></i> Back to Return Register
                        </a>
                    </div>

                </form>

            </section>

        </div>
    </main>

</div>
<script>
    const returnDateInput = document.getElementById("returnDate");

    function getTodayIsoDate() {
        const now = new Date();
        const localDate = new Date(now.getTime() - now.getTimezoneOffset() * 60000);
        return localDate.toISOString().split("T")[0];
    }

    if (returnDateInput) {
        returnDateInput.max = getTodayIsoDate();

        if (returnDateInput.value === "") {
            returnDateInput.value = getTodayIsoDate();
        }

        returnDateInput.addEventListener("change", function () {
            if (returnDateInput.value && returnDateInput.value > getTodayIsoDate()) {
                returnDateInput.value = "";
                alert("Return date cannot be a future date.");
            }
        });
    }

    const returnForm = document.querySelector("form");

    if (returnForm) {
        returnForm.addEventListener("submit", function (event) {
            if (!returnDateInput || !returnDateInput.value) {
                event.preventDefault();
                alert("Please select return date.");
                return;
            }

            if (returnDateInput.value > getTodayIsoDate()) {
                event.preventDefault();
                returnDateInput.value = "";
                alert("Return date cannot be a future date.");
            }
        });
    }

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

<script src="js/topbar-search.js?v=28000"></script>
<script src="js/user-dropdown.js?v=28000"></script>
<script src="js/sidebar-role.js?v=28000"></script>
<script src="js/ir-body-watermark.js?v=28000"></script>
<script src="js/dashboard-actions.js?v=28000"></script>

</body>
</html>